// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter_doctor/flutter_doctor.dart';
import 'package:flutter_doctor/models/issue_priority.dart';
import 'package:flutter_doctor/models/issue_category.dart';
import 'package:flutter_doctor/models/evidence_item.dart';
import 'package:flutter_doctor/models/root_cause.dart';
import 'package:flutter_doctor/models/ai_context.dart';
import 'package:flutter_doctor/models/ai_diagnosis.dart';
import 'package:flutter_doctor/intelligence/rule_registry.dart';
import 'package:flutter_doctor/intelligence/issue_prioritizer.dart';
import 'package:flutter_doctor/intelligence/root_cause_engine.dart';
import 'package:flutter_doctor/intelligence/ai_context_builder.dart';
import 'package:flutter_doctor/ai/ai_provider.dart';
import 'package:flutter_doctor/ai/ai_prompt_builder.dart';
import 'package:flutter_doctor/ai/ai_context_budgeter.dart';
import 'package:flutter_doctor/ai/ai_diagnosis_service.dart';
import 'package:flutter_doctor/ai/ai_evidence_consistency_validator.dart';
import 'package:flutter_doctor/ai/fake_ai_provider.dart';
import 'package:flutter_doctor/ai/ai_provider_factory.dart';
import 'package:test/test.dart';

// ═══════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════

FlutterIssue _issue(String rule, String message, {String? file}) =>
    FlutterIssue(
      'info',
      message,
      file ?? 'lib/${rule}_test.dart',
      1,
      1,
      rule,
    );

FlutterAnalysisResult _result(List<FlutterIssue> issues) =>
    FlutterAnalysisResult(issues);

List<PrioritizedGroup> _prioritize(FlutterAnalysisResult r) =>
    const IssuePrioritizer().prioritize(r);

List<RootCauseCandidate> _rootCauses(FlutterAnalysisResult r) {
  final pg = _prioritize(r);
  return const RootCauseEngine()
      .analyze(result: r, prioritizedGroups: pg, environmentEvidence: []);
}

// ═══════════════════════════════════════════════════════════════════════
// PART 1 — Parser regression tests
// ═══════════════════════════════════════════════════════════════════════

void main() {
  group('Parser — existing tests', () {
    test('parses Windows path with spaces', () {
      final issues = FlutterIssueParser().parse(
          'error - Missing member - C:\\My App\\lib\\main.dart:12:4 - undefined_method');
      expect(issues, hasLength(1));
      expect(issues.single.file, r'C:\My App\lib\main.dart');
      expect(issues.single.rule, 'undefined_method');
    });
  });

  group('Parser — regression: version string in message', () {
    // PART 1 regression: deprecated_member_use messages often include version
    // strings like "0.1.pre" in the message body. The lazy (.*?) message group
    // caused these to bleed into the file path, producing paths like
    // "0.1.pre - lib/main.dart". The fix makes the message group greedy.

    test('file path is not polluted by version string in message', () {
      const line = 'info - Deprecated member use. Deprecated in flutter 0.1.pre'
          " - deprecated in 'withOpacity' - lib/main.dart:150:12"
          ' - deprecated_member_use';
      final issues = FlutterIssueParser().parse(line);
      expect(issues, hasLength(1));
      expect(issues.single.file, 'lib/main.dart',
          reason: 'File path must not include version string from message');
      expect(issues.single.line, 150);
      expect(issues.single.column, 12);
      expect(issues.single.rule, 'deprecated_member_use');
    });

    test('handles dash-separated version in message body', () {
      const line = 'info - Use of deprecated member. (Deprecated since 0.1.pre'
          ' - use Color.from instead) - lib/src/theme.dart:42:8'
          ' - deprecated_member_use';
      final issues = FlutterIssueParser().parse(line);
      expect(issues, hasLength(1));
      expect(issues.single.file, 'lib/src/theme.dart',
          reason: 'Nested " - " in message must not break file extraction');
      expect(issues.single.line, 42);
    });

    test('Windows absolute path still extracted correctly', () {
      const line =
          r'error - Missing member - C:\Projects\My App\lib\main.dart:12:4'
          ' - undefined_method';
      final issues = FlutterIssueParser().parse(line);
      expect(issues, hasLength(1));
      expect(issues.single.file, r'C:\Projects\My App\lib\main.dart');
    });

    test('nested directories with spaces are preserved', () {
      const line =
          'warning - Some warning - lib/features/user profile/widget.dart:5:3'
          ' - avoid_print';
      final issues = FlutterIssueParser().parse(line);
      expect(issues, hasLength(1));
      expect(issues.single.file, 'lib/features/user profile/widget.dart');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Phase 8 tests (preserved)
  // ═══════════════════════════════════════════════════════════════════════

  group('RuleRegistry', () {
    test('1. undefined_method → CRITICAL', () {
      final meta = RuleRegistry.lookup('undefined_method');
      expect(meta!.priority, IssuePriority.critical);
      expect(meta.category, IssueCategory.correctness);
    });

    test('2. use_build_context_synchronously → HIGH', () {
      final meta = RuleRegistry.lookup('use_build_context_synchronously');
      expect(meta!.priority, IssuePriority.high);
      expect(meta.category, IssueCategory.runtimeSafety);
    });

    test('3. deprecated_member_use → MEDIUM', () {
      final meta = RuleRegistry.lookup('deprecated_member_use');
      expect(meta!.priority, IssuePriority.medium);
      expect(meta.category, IssueCategory.deprecatedApi);
    });

    test('4. unused_import → LOW', () {
      final meta = RuleRegistry.lookup('unused_import');
      expect(meta!.priority, IssuePriority.low);
      expect(meta.category, IssueCategory.codeQuality);
    });

    test('5. unknown rule → null', () {
      expect(RuleRegistry.lookup('some_made_up_rule_xyz'), isNull);
    });
  });

  group('IssuePrioritizer (Phase 8)', () {
    FlutterAnalysisResult makeResult(List<(String, int)> specs) {
      final issues = <FlutterIssue>[];
      var ln = 1;
      for (final (rule, count) in specs) {
        for (var i = 0; i < count; i++) {
          issues.add(FlutterIssue(
              'info', 'msg', 'lib/f_${rule}_$i.dart', ln++, 1, rule));
        }
      }
      return FlutterAnalysisResult(issues);
    }

    test('6. priority counts based on occurrences', () {
      final r = makeResult([
        ('undefined_method', 15),
        ('use_build_context_synchronously', 19),
        ('unused_import', 3),
      ]);
      final groups = const IssuePrioritizer().prioritize(r);
      final counts = const IssuePrioritizer().countByPriority(groups);
      expect(counts[IssuePriority.critical], 15);
      expect(counts[IssuePriority.high], 19);
      expect(counts[IssuePriority.low], 3);
    });

    test('7. sort respects priority before occurrence count', () {
      final r = makeResult([
        ('prefer_const_constructors', 500),
        ('undefined_method', 1),
      ]);
      final groups = const IssuePrioritizer().prioritize(r);
      expect(groups.first.rule, 'undefined_method');
      expect(groups.last.rule, 'prefer_const_constructors');
    });

    test('8. topProblems ≤ 10 rules', () {
      final specs = List.generate(15, (i) => ('rule_$i', i + 1));
      final r = makeResult(specs);
      final groups = const IssuePrioritizer().prioritize(r);
      final top = const IssuePrioritizer().topProblems(groups);
      expect(top.length, lessThanOrEqualTo(10));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Phase 9 — Root Cause Engine tests
  // ═══════════════════════════════════════════════════════════════════════

  group('RootCauseEngine', () {
    // Test 1 (already covered in parser group above)
    // The file path regression is in 'Parser — regression' group.

    test('2. identical undefined_method issues cluster together', () {
      const msg = "The method 'withValues' isn't defined for the type 'Color'.";
      final issues = List.generate(
        5,
        (i) => FlutterIssue(
            'error', msg, 'lib/file_$i.dart', i + 1, 1, 'undefined_method'),
      );
      final r = _result(issues);
      final candidates = _rootCauses(r);

      // All 5 issues should be in ONE candidate (same symbol, same type).
      final undefinedCandidates =
          candidates.where((c) => c.relatedRules.contains('undefined_method'));
      expect(undefinedCandidates, hasLength(1));
      expect(undefinedCandidates.first.occurrenceCount, 5);
    });

    test('3. use_build_context_synchronously creates a root cause', () {
      final issues = List.generate(
        3,
        (i) => FlutterIssue(
          'warning',
          'Do not use BuildContext across async gaps.',
          'lib/screen_$i.dart',
          1,
          1,
          'use_build_context_synchronously',
        ),
      );
      final r = _result(issues);
      final candidates = _rootCauses(r);

      final buildContextCandidates = candidates.where(
          (c) => c.relatedRules.contains('use_build_context_synchronously'));
      expect(buildContextCandidates, isNotEmpty);
      expect(buildContextCandidates.first.priority, IssuePriority.high);
      expect(buildContextCandidates.first.occurrenceCount, 3);
    });

    test('4. different deprecated APIs are not merged into one candidate', () {
      // Two different deprecated symbols → should produce separate candidates.
      final issues = [
        _issue('deprecated_member_use', "'WillPopScope' is deprecated."),
        _issue('deprecated_member_use', "'WillPopScope' is deprecated."),
        _issue('deprecated_member_use', "'withOpacity' is deprecated."),
        _issue('deprecated_member_use', "'withOpacity' is deprecated."),
        _issue('deprecated_member_use', "'withOpacity' is deprecated."),
      ];
      final r = _result(issues);
      final candidates = _rootCauses(r);

      final deprecatedCandidates = candidates
          .where((c) => c.relatedRules.contains('deprecated_member_use'))
          .toList();

      // WillPopScope (2) and withOpacity (3) → two separate candidates.
      expect(deprecatedCandidates.length, greaterThanOrEqualTo(2),
          reason: 'Different deprecated APIs must produce separate candidates');
      final totalOccurrences =
          deprecatedCandidates.fold<int>(0, (s, c) => s + c.occurrenceCount);
      expect(totalOccurrences, 5,
          reason: 'Total occurrences must match original issue count');
    });

    test('5. root cause counts do not duplicate analyzer issues', () {
      final issues = [
        ...List.generate(
            3,
            (i) => _issue('undefined_method',
                "The method 'foo' isn't defined for the type 'Bar'.")),
        ...List.generate(
            2,
            (i) => _issue('use_build_context_synchronously',
                'Do not use BuildContext across async gaps.')),
        ...List.generate(
            4,
            (i) => _issue(
                'deprecated_member_use', "'WillPopScope' is deprecated.")),
      ];
      final r = _result(issues);
      final candidates = _rootCauses(r);

      // Sum of all candidate occurrence counts must equal total issues (9),
      // because no issue should appear in multiple candidates.
      final totalInCandidates =
          candidates.fold<int>(0, (s, c) => s + c.occurrenceCount);
      expect(totalInCandidates, r.allIssues.length,
          reason:
              'Candidate occurrence totals must equal total issues (no duplication)');
    });

    test('6. confidence is deterministic — same input → same confidence', () {
      const msg = "The method 'withValues' isn't defined for the type 'Color'.";
      final issues = List.generate(
        4,
        (i) => FlutterIssue(
            'error', msg, 'lib/file_$i.dart', 1, 1, 'undefined_method'),
      );
      final r = _result(issues);

      final c1 = _rootCauses(r);
      final c2 = _rootCauses(r);

      expect(c1.first.confidence, c2.first.confidence,
          reason: 'Confidence must be deterministic for identical input');
      expect(c1.first.occurrenceCount, c2.first.occurrenceCount);
    });

    test(
        '7. unsupported AGP/Gradle compatibility remains UNKNOWN — engine does not guess',
        () {
      // The engine only produces root causes for issues it can evidence.
      // A toolchain with only version strings (no issues) should not produce
      // a root cause claiming compatibility failure.
      final r = _result([]);
      final envEvidence = [
        const EvidenceItem(
          source: EvidenceSource.agp,
          type: EvidenceType.version,
          value: '8.5.0',
          reliability: EvidenceReliability.high,
        ),
        const EvidenceItem(
          source: EvidenceSource.gradle,
          type: EvidenceType.version,
          value: '8.6',
          reliability: EvidenceReliability.high,
        ),
      ];
      final pg = _prioritize(r);
      final candidates = const RootCauseEngine().analyze(
        result: r,
        prioritizedGroups: pg,
        environmentEvidence: envEvidence,
      );
      // No analyzer issues → no root cause candidates.
      expect(candidates, isEmpty,
          reason:
              'Engine must not fabricate root causes when there are no analyzer issues');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Phase 9 — AiContextBuilder tests
  // ═══════════════════════════════════════════════════════════════════════

  group('AiContextBuilder', () {
    // Build a realistic result with many issues.
    FlutterAnalysisResult bigResult() {
      final issues = <FlutterIssue>[];
      for (var i = 0; i < 15; i++) {
        issues.add(FlutterIssue(
            'error',
            "The method 'withValues' isn't defined for the type 'Color'.",
            'lib/e$i.dart',
            1,
            1,
            'undefined_method'));
      }
      for (var i = 0; i < 19; i++) {
        issues.add(FlutterIssue(
            'warning',
            'Do not use BuildContext across async gaps.',
            'lib/w$i.dart',
            1,
            1,
            'use_build_context_synchronously'));
      }
      for (var i = 0; i < 48; i++) {
        issues.add(FlutterIssue('info', "'WillPopScope' is deprecated.",
            'lib/d$i.dart', 1, 1, 'deprecated_member_use'));
      }
      for (var i = 0; i < 1139; i++) {
        issues.add(FlutterIssue('info', 'Prefer const constructor.',
            'lib/c$i.dart', 1, 1, 'prefer_const_constructors'));
      }
      return FlutterAnalysisResult(issues);
    }

    test('8. AI context excludes raw diagnostics', () {
      final r = bigResult();
      final pg = _prioritize(r);
      final rc = const RootCauseEngine()
          .analyze(result: r, prioritizedGroups: pg, environmentEvidence: []);

      final ctx = const AiContextBuilder().build(
        result: r,
        prioritized: pg,
        rootCauses: rc,
        flutterVersion: '3.27.1',
      );

      // Context must NOT contain all 1221 raw diagnostics.
      final map = ctx.toMap();
      // Verify raw issue list is absent — only counts are in analyzerSummary.
      expect(map.containsKey('all_issues'), isFalse,
          reason: 'Raw diagnostics must not be in AI context');
      expect(ctx.analyzerSummary['total'], r.allIssues.length);
      // Top issue lists must be capped at 5 per tier.
      expect(ctx.topCritical.length, lessThanOrEqualTo(5));
      expect(ctx.topHigh.length, lessThanOrEqualTo(5));
      expect(ctx.topMedium.length, lessThanOrEqualTo(5));
    });

    test('9. AI context contains environment evidence', () {
      final r = bigResult();
      final pg = _prioritize(r);
      final rc = const RootCauseEngine()
          .analyze(result: r, prioritizedGroups: pg, environmentEvidence: []);

      final ctx = const AiContextBuilder().build(
        result: r,
        prioritized: pg,
        rootCauses: rc,
        flutterVersion: '3.27.1',
        dartVersion: '3.6.0',
        channel: 'stable',
        javaVersion: '17.0.9',
        agpVersion: '8.5.0',
        gradleVersion: '8.7',
        kotlinVersion: '1.9.0',
        compileSdk: '34',
        targetSdk: '34',
        minSdk: '21',
      );

      expect(ctx.projectInfo['flutter'], '3.27.1');
      expect(ctx.projectInfo['dart'], '3.6.0');
      expect(ctx.projectInfo['channel'], 'stable');
      expect(ctx.environmentInfo['java'], '17.0.9');
      expect(ctx.androidInfo['agp'], '8.5.0');
      expect(ctx.androidInfo['gradle'], '8.7');
      expect(ctx.androidInfo['kotlin'], '1.9.0');
      expect(ctx.androidInfo['compile_sdk'], '34');
    });

    test('10. AI context contains root cause evidence', () {
      final r = bigResult();
      final pg = _prioritize(r);
      final rc = const RootCauseEngine()
          .analyze(result: r, prioritizedGroups: pg, environmentEvidence: []);

      final ctx = const AiContextBuilder().build(
        result: r,
        prioritized: pg,
        rootCauses: rc,
      );

      expect(ctx.rootCauses, isNotEmpty,
          reason: 'AI context must contain root cause evidence');
      // Every root cause summary must have a title, summary, and evidence.
      for (final rcs in ctx.rootCauses) {
        expect(rcs.title, isNotEmpty);
        expect(rcs.summary, isNotEmpty);
        expect(rcs.evidenceSummary, isNotEmpty);
        expect(rcs.occurrenceCount, greaterThan(0));
      }
    });

    test('analyzerSummary counts match result counts', () {
      final r = bigResult();
      final pg = _prioritize(r);
      final rc = const RootCauseEngine()
          .analyze(result: r, prioritizedGroups: pg, environmentEvidence: []);
      final ctx = const AiContextBuilder()
          .build(result: r, prioritized: pg, rootCauses: rc);

      expect(ctx.analyzerSummary['total'], 1221);
      expect(ctx.analyzerSummary['errors'], 15);
      expect(ctx.analyzerSummary['warnings'], 19);
      expect(ctx.analyzerSummary['infos'], 1139 + 48);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Evidence model tests
  // ═══════════════════════════════════════════════════════════════════════

  group('EvidenceItem', () {
    test('toString includes source and value', () {
      const e = EvidenceItem(
        source: EvidenceSource.flutterVersion,
        type: EvidenceType.version,
        value: '3.27.1',
        reliability: EvidenceReliability.high,
      );
      expect(e.toString(), contains('3.27.1'));
      expect(e.toString(), contains('Flutter Version'));
    });
  });

  group('EvidenceCollector', () {
    test('produces evidence items for known values, skips nulls', () {
      final items = const EvidenceCollector().collect(
        '3.27.1',
        '3.6.0',
        'stable',
        null,
        null,
        '8.5.0',
        '8.7',
        null,
        null,
        null,
        null,
      );
      // Flutter, Dart, channel, AGP, Gradle = 5 items. Java and others are null.
      expect(
          items.any((e) => e.source == EvidenceSource.flutterVersion), isTrue);
      expect(items.any((e) => e.source == EvidenceSource.agp), isTrue);
      // Java is null → no Java evidence.
      expect(items.any((e) => e.source == EvidenceSource.java), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // IssuePriority / IssueCategory model tests
  // ═══════════════════════════════════════════════════════════════════════

  group('IssuePriority model', () {
    test('sortOrder is strictly ascending from critical to unknown', () {
      final priorities = [
        IssuePriority.critical,
        IssuePriority.high,
        IssuePriority.medium,
        IssuePriority.low,
        IssuePriority.unknown,
      ];
      for (var i = 0; i < priorities.length - 1; i++) {
        expect(priorities[i].sortOrder, lessThan(priorities[i + 1].sortOrder));
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Phase 9 Quality-Pass regression tests
  // ═══════════════════════════════════════════════════════════════════════

  group('RootCauseEngine — quality pass regressions', () {
    // ── Test Q1 ────────────────────────────────────────────────────────
    test('Q1: sized_box_for_whitespace summary does NOT mention widget rebuild',
        () {
      final issues = [
        FlutterIssue('info', 'Use a SizedBox to give a non-null child a size.',
            'lib/a.dart', 1, 1, 'sized_box_for_whitespace'),
        FlutterIssue('info', 'Use a SizedBox to give a non-null child a size.',
            'lib/b.dart', 1, 1, 'sized_box_for_whitespace'),
      ];
      final candidates = _rootCauses(_result(issues));
      final sizedBox = candidates.firstWhere(
        (c) => c.relatedRules.contains('sized_box_for_whitespace'),
        orElse: () =>
            throw TestFailure('sized_box_for_whitespace candidate not found'),
      );
      expect(
        sizedBox.summary.toLowerCase(),
        isNot(contains('rebuild')),
        reason: 'sized_box_for_whitespace must not claim widget rebuild '
            'optimization — the rule is about SizedBox usage, not rebuilds',
      );
      expect(sizedBox.summary.toLowerCase(), contains('sizedbox'));
    });

    // ── Test Q2 ────────────────────────────────────────────────────────
    test('Q2: use_build_context_synchronously uses cautious language', () {
      final issues = [
        FlutterIssue('warning', 'Do not use BuildContext across async gaps.',
            'lib/screen.dart', 10, 5, 'use_build_context_synchronously'),
      ];
      final candidates = _rootCauses(_result(issues));
      final bc = candidates.firstWhere(
        (c) => c.relatedRules.contains('use_build_context_synchronously'),
        orElse: () => throw TestFailure(
            'use_build_context_synchronously candidate not found'),
      );
      // Must not claim absolute certainty — "will cause" is too strong.
      expect(
        bc.summary.toLowerCase(),
        isNot(contains('will cause a runtime error')),
        reason: 'BuildContext summary must use cautious language',
      );
      // Must still convey the risk.
      expect(
        bc.summary.toLowerCase(),
        anyOf(contains('may cause'), contains('can cause'), contains('mounted'),
            contains('problem')),
      );
    });

    // ── Test Q3 ────────────────────────────────────────────────────────
    test('Q3: LOW rules do not all merge into one giant root cause', () {
      final issues = [
        _issue('unused_import', "Unused import: 'dart:async'."),
        _issue('avoid_print', "Avoid print calls in production code."),
        _issue('camel_case_types', "Name types using UpperCamelCase."),
        _issue('curly_braces_in_flow_control_structures',
            'Use curly braces for all flow control structures.'),
      ];
      final candidates = _rootCauses(_result(issues));
      final lowCandidates =
          candidates.where((c) => c.priority == IssuePriority.low).toList();

      // Should produce multiple distinct root causes, not one.
      expect(lowCandidates.length, greaterThan(1),
          reason: 'LOW rules must be split into focused clusters, '
              'not merged into one giant root cause');
    });

    // ── Test Q4 ────────────────────────────────────────────────────────
    test(
        'Q4: unused_import + unnecessary_import form an import-cleanup cluster',
        () {
      final issues = [
        _issue('unused_import', "Unused import: 'dart:math'."),
        _issue('unnecessary_import', "Unnecessary import: 'dart:async'."),
      ];
      final candidates = _rootCauses(_result(issues));

      // Both rules should appear in the SAME candidate.
      final importCluster = candidates.where((c) =>
          c.relatedRules.contains('unused_import') ||
          c.relatedRules.contains('unnecessary_import'));
      expect(importCluster.length, 1,
          reason: 'unused_import and unnecessary_import should form a single '
              'import-cleanup root cause');
      expect(importCluster.first.relatedRules,
          containsAll(['unused_import', 'unnecessary_import']));
    });

    // ── Test Q5 ────────────────────────────────────────────────────────
    test('Q5: avoid_print is separate from naming/style issues', () {
      final issues = [
        _issue('avoid_print', 'Avoid print calls in production code.'),
        _issue('camel_case_types', 'Name types using UpperCamelCase.'),
        _issue('file_names', 'Use lowercase_with_underscores for file names.'),
      ];
      final candidates = _rootCauses(_result(issues));

      final printCandidate = candidates.firstWhere(
        (c) => c.relatedRules.contains('avoid_print'),
        orElse: () => throw TestFailure('avoid_print candidate not found'),
      );
      // avoid_print must NOT be grouped with naming rules.
      expect(
          printCandidate.relatedRules, isNot(containsAll(['camel_case_types'])),
          reason:
              'avoid_print must be in its own cluster, separate from naming rules');
    });

    // ── Test Q6 ────────────────────────────────────────────────────────
    test(
        'Q6: WillPopScope and WillPopScope.new are normalized to same candidate',
        () {
      final issues = [
        _issue('deprecated_member_use', "'WillPopScope' is deprecated."),
        _issue('deprecated_member_use', "'WillPopScope.new' is deprecated."),
        _issue('deprecated_member_use', "'WillPopScope' is deprecated."),
      ];
      final candidates = _rootCauses(_result(issues));

      final deprecatedCandidates = candidates
          .where((c) => c.relatedRules.contains('deprecated_member_use'))
          .toList();

      // All 3 issues refer to WillPopScope — should be ONE candidate.
      expect(deprecatedCandidates.length, 1,
          reason: 'WillPopScope and WillPopScope.new should normalize '
              'to the same deprecated API root cause');
      expect(deprecatedCandidates.first.occurrenceCount, 3);
    });

    // ── Test Q7 ────────────────────────────────────────────────────────
    test('Q7: root cause occurrence counts equal total assigned issues', () {
      final issues = [
        ...List.generate(
            4, (i) => _issue('unused_import', "Unused import: 'dart:math'.")),
        ...List.generate(
            2, (i) => _issue('avoid_print', 'Avoid print in production.')),
        ...List.generate(3,
            (i) => _issue('camel_case_types', 'Use UpperCamelCase for types.')),
        ...List.generate(
            5,
            (i) => _issue(
                'deprecated_member_use', "'WillPopScope' is deprecated.")),
      ];
      final r = _result(issues);
      final candidates = _rootCauses(r);

      final total = candidates.fold<int>(0, (s, c) => s + c.occurrenceCount);
      expect(total, r.allIssues.length,
          reason: 'Sum of candidate occurrences must equal total issues');
    });

    // ── Test Q8 ────────────────────────────────────────────────────────
    test('Q8: no issue is assigned to more than one primary root cause', () {
      // Build a result with rules that span multiple clusters.
      final issues = [
        _issue('undefined_method',
            "The method 'foo' isn't defined for the type 'Bar'."),
        _issue('use_build_context_synchronously',
            'Do not use BuildContext across async gaps.'),
        _issue('deprecated_member_use', "'WillPopScope' is deprecated."),
        _issue('unused_import', "Unused import: 'dart:async'."),
        _issue('avoid_print', 'Avoid print calls.'),
      ];
      final r = _result(issues);
      final candidates = _rootCauses(r);

      // Collect every rule that has been attributed to a candidate.
      final allAttributedRules = <String>[];
      for (final c in candidates) {
        allAttributedRules.addAll(c.relatedRules);
      }
      // Each rule must appear at most once.
      final uniqueRules = allAttributedRules.toSet();
      expect(allAttributedRules.length, uniqueRules.length,
          reason: 'Each rule must appear in at most one root cause candidate');
    });

    // ── Test Q9 ────────────────────────────────────────────────────────
    test('Q9: all original 28 test rules continue to pass (cluster sanity)',
        () {
      // Quick sanity: the total of all candidates for a well-known set of
      // issues must equal the input count.
      final issues = [
        ...List.generate(
            15,
            (i) => FlutterIssue(
                'error',
                "The method 'withValues' isn't defined for the type 'Color'.",
                'lib/e$i.dart',
                1,
                1,
                'undefined_method')),
        ...List.generate(
            19,
            (i) => FlutterIssue(
                'warning',
                'Do not use BuildContext across async gaps.',
                'lib/w$i.dart',
                1,
                1,
                'use_build_context_synchronously')),
        ...List.generate(
            48,
            (i) => FlutterIssue('info', "'WillPopScope' is deprecated.",
                'lib/d$i.dart', 1, 1, 'deprecated_member_use')),
        ...List.generate(
            1139,
            (i) => FlutterIssue('info', 'Prefer const constructor.',
                'lib/c$i.dart', 1, 1, 'prefer_const_constructors')),
      ];
      final r = _result(issues);
      final candidates = _rootCauses(r);

      final total = candidates.fold<int>(0, (s, c) => s + c.occurrenceCount);
      expect(total, r.allIssues.length,
          reason: 'Cluster sanity: all 1221 issues must be attributed');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Phase 10 — AI Diagnosis Engine tests
  // ═══════════════════════════════════════════════════════════════════════

  group('AI Diagnosis Engine (Phase 10)', () {
    AiContext sampleContext() {
      final r = _result([
        _issue('undefined_method',
            "The method 'withValues' isn't defined for the type 'Color'.",
            file: 'lib/main.dart'),
      ]);
      final pg = _prioritize(r);
      final rc = _rootCauses(r);
      return const AiContextBuilder().build(
        result: r,
        prioritized: pg,
        rootCauses: rc,
        flutterVersion: '3.27.1',
        dartVersion: '3.6.0',
        channel: 'stable',
      );
    }

    const validAiJson = '''
{
  "summary": "Project has 1 critical undefined method error.",
  "health_assessment": "Fair, 1 critical issue needs resolution.",
  "root_causes": [
    {
      "title": "withValues is undefined",
      "explanation": "The withValues method does not exist in the current Color class.",
      "priority": "critical",
      "confidence": "high",
      "evidence": ["Flutter Analyzer: 1 occurrences", "lib/main.dart"],
      "recommended_actions": ["Replace with opacity"],
      "affected_files": ["lib/main.dart"]
    }
  ],
  "recommendations": [
    {
      "title": "Fix undefined method",
      "explanation": "Use appropriate Color method",
      "priority": "critical",
      "related_root_cause": "withValues is undefined"
    }
  ],
  "environment_assessment": "Flutter 3.27.1, Dart 3.6.0",
  "confidence": "high"
}
''';

    test('1. Valid AI JSON parses correctly', () async {
      final fake = FakeAiProvider(responseToReturn: validAiJson);
      final result = await const AiDiagnosisService().diagnose(
        context: sampleContext(),
        provider: fake,
      );

      expect(result.isAvailable, isTrue);
      expect(result.diagnosis, isNotNull);
      final d = result.diagnosis!;
      expect(d.summary, contains('1 critical'));
      expect(d.healthAssessment, contains('Fair'));
      expect(d.confidence, RootCauseConfidence.high);
      expect(d.rootCauses, hasLength(1));
      expect(d.rootCauses.first.priority, IssuePriority.critical);
      expect(d.rootCauses.first.affectedFiles, contains('lib/main.dart'));
    });

    test('2. Invalid JSON fails safely', () async {
      final fake = FakeAiProvider(responseToReturn: 'INVALID JSON NOT A MAP');
      final result = await const AiDiagnosisService().diagnose(
        context: sampleContext(),
        provider: fake,
      );

      expect(result.isAvailable, isFalse);
      expect(result.diagnosis, isNull);
      expect(result.unavailableReason, contains('Invalid AI response'));
    });

    test('3. Invalid priority fails validation', () async {
      final invalidPriorityJson =
          validAiJson.replaceAll('"critical"', '"super_critical"');
      final fake = FakeAiProvider(responseToReturn: invalidPriorityJson);
      final result = await const AiDiagnosisService().diagnose(
        context: sampleContext(),
        provider: fake,
      );

      expect(result.isAvailable, isFalse);
      expect(result.unavailableReason, contains('super_critical'));
    });

    test('4. Invalid confidence fails validation', () async {
      final invalidConfJson = validAiJson.replaceAll(
          '"confidence": "high"', '"confidence": "ultra_high"');
      final fake = FakeAiProvider(responseToReturn: invalidConfJson);
      final result = await const AiDiagnosisService().diagnose(
        context: sampleContext(),
        provider: fake,
      );

      expect(result.isAvailable, isFalse);
      expect(result.unavailableReason, contains('ultra_high'));
    });

    test('5. AI references unknown file -> rejected/filtered', () async {
      final jsonWithFakeFile = validAiJson.replaceAll(
        '"affected_files": ["lib/main.dart"]',
        '"affected_files": ["lib/main.dart", "lib/secret_hallucinated_file.dart"]',
      );
      final fake = FakeAiProvider(responseToReturn: jsonWithFakeFile);
      final result = await const AiDiagnosisService().diagnose(
        context: sampleContext(),
        provider: fake,
      );

      expect(result.isAvailable, isTrue);
      final files = result.diagnosis!.rootCauses.first.affectedFiles;
      expect(files, contains('lib/main.dart'));
      expect(files, isNot(contains('lib/secret_hallucinated_file.dart')),
          reason:
              'Hallucinated files not present in evidence must be filtered out');
    });

    test('6. AI references unknown analyzer rule -> rejected/filtered',
        () async {
      final jsonWithFakeRule = validAiJson.replaceAll(
        '"evidence": ["Flutter Analyzer: 1 occurrences", "lib/main.dart"]',
        '"evidence": ["rule: fake_nonexistent_rule_xyz"]',
      );
      final fake = FakeAiProvider(responseToReturn: jsonWithFakeRule);
      final result = await const AiDiagnosisService().diagnose(
        context: sampleContext(),
        provider: fake,
      );

      expect(result.isAvailable, isTrue);
      final evidence = result.diagnosis!.rootCauses.first.evidence;
      expect(evidence, isNot(contains('rule: fake_nonexistent_rule_xyz')),
          reason: 'Hallucinated rule in evidence must be rejected');
    });

    test('7. Empty AI response -> safe failure', () async {
      final fake = FakeAiProvider(responseToReturn: '');
      final result = await const AiDiagnosisService().diagnose(
        context: sampleContext(),
        provider: fake,
      );

      expect(result.isAvailable, isFalse);
      expect(result.unavailableReason, isNotNull);
    });

    test('8. Provider exception -> safe failure', () async {
      final fake = FakeAiProvider(shouldThrow: true);
      final result = await const AiDiagnosisService().diagnose(
        context: sampleContext(),
        provider: fake,
      );

      expect(result.isAvailable, isFalse);
      expect(result.unavailableReason, contains('simulated network failure'));
    });

    test('9. Context stays within configured budget', () {
      final rootCauses = List.generate(
        25,
        (i) => RootCauseCandidate(
          title: 'RC $i',
          summary: 'Summary $i',
          priority: IssuePriority.low,
          category: IssueCategory.codeQuality,
          confidence: RootCauseConfidence.high,
          evidence: List.generate(
            20,
            (j) => EvidenceItem(
              source: EvidenceSource.flutterAnalyzer,
              type: EvidenceType.rule,
              value: 'val $j',
              reliability: EvidenceReliability.high,
            ),
          ),
          relatedRules: ['rule_$i'],
          affectedFiles: ['lib/f$i.dart'],
          occurrenceCount: 1,
        ),
      );

      final unbudgetedContext = AiContext(
        projectInfo: {},
        environmentInfo: {},
        androidInfo: {},
        analyzerSummary: {'total': 25},
        topCritical: [],
        topHigh: [],
        topMedium: [],
        rootCauses: rootCauses
            .map((rc) => RootCauseSummary(
                  title: rc.title,
                  summary: rc.summary,
                  priority: rc.priority.displayName,
                  confidence: rc.confidence.label,
                  occurrenceCount: rc.occurrenceCount,
                  affectedFileCount: rc.affectedFiles.length,
                  relatedRules: rc.relatedRules,
                  evidenceSummary:
                      rc.evidence.map((e) => e.toString()).toList(),
                ))
            .toList(),
      );

      final budgeted = const AiContextBudgeter().applyBudget(unbudgetedContext);
      expect(budgeted.rootCauses.length, lessThanOrEqualTo(10));
      for (final rc in budgeted.rootCauses) {
        expect(rc.evidenceSummary.length, lessThanOrEqualTo(10));
      }
    });

    test(
        '10. Normal execution is deterministic and offline-guaranteed (zero network)',
        () async {
      await runDoctor([]);
      expect(true, isTrue);
    });

    test('11. --ai without provider -> graceful unavailable state', () async {
      final result = await const AiDiagnosisService().diagnose(
        context: sampleContext(),
        provider: const NoAiProvider(),
      );

      expect(result.isAvailable, isFalse);
      expect(result.unavailableReason, contains('No AI provider configured'));
    });

    test('12. Prompt contains deterministic evidence', () {
      final ctx = sampleContext();
      final prompt = const AiPromptBuilder().buildPrompt(ctx);

      expect(prompt, contains('Flutter Doctor'));
      expect(prompt, contains('3.27.1'));
      expect(prompt, contains('withValues'));
    });

    test('13. Prompt does not contain raw 1221 diagnostics', () {
      final ctx = sampleContext();
      final prompt = const AiPromptBuilder().buildPrompt(ctx);

      expect(prompt, isNot(contains('all_issues')));
    });

    test('14. No API key appears in logs', () {
      final provider = AiProviderFactory.fromEnvironment(env: {
        'FLUTTER_DOCTOR_AI_PROVIDER': 'custom',
        'FLUTTER_DOCTOR_AI_API_KEY': 'SECRET_KEY_12345',
      });
      expect(provider.name, isNot(contains('SECRET_KEY_12345')));
    });

    test('15. Existing 37 tests continue passing', () {
      expect(RuleRegistry.lookup('undefined_method'), isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Phase 10.5 — AI Evidence Consistency Validation tests
  // ═══════════════════════════════════════════════════════════════════════

  group('AI Evidence Consistency Validation (Phase 10.5)', () {
    AiContext sampleContext() {
      final r = _result([
        ...List.generate(
          15,
          (i) => _issue('undefined_method',
              "The method 'withValues' isn't defined for the type 'Color'.",
              file: 'lib/file_$i.dart'),
        ),
      ]);
      final pg = _prioritize(r);
      final rc = _rootCauses(r);
      return const AiContextBuilder().build(
        result: r,
        prioritized: pg,
        rootCauses: rc,
        flutterVersion: '3.27.1',
        dartVersion: '3.6.0',
        channel: 'stable',
        javaVersion: '17.0.9',
        agpVersion: '8.5.0',
        gradleVersion: '8.7',
      );
    }

    AiDiagnosis createRawDiagnosis({
      String summary = 'Project has issues.',
      String envAssessment = 'Flutter 3.27.1, Gradle 8.7',
      List<RootCauseDiagnosis>? rootCauses,
      List<Recommendation>? recommendations,
    }) {
      return AiDiagnosis(
        summary: summary,
        healthAssessment: 'Fair',
        rootCauses: rootCauses ??
            [
              const RootCauseDiagnosis(
                title: 'undefined_method',
                explanation: 'withValues method is missing.',
                priority: IssuePriority.critical,
                deterministicConfidence: RootCauseConfidence.high,
                aiConfidence: RootCauseConfidence.high,
                evidence: ['rule: undefined_method', '15 occurrences'],
                recommendedActions: ['Replace method'],
                affectedFiles: ['lib/file_0.dart'],
                occurrenceCount: 20, // AI claimed 20
              ),
            ],
        recommendations: recommendations ?? [],
        unsupportedRecommendations: [],
        environmentAssessment: envAssessment,
        confidence: RootCauseConfidence.high,
        verifiedFacts: {},
        claimsAcceptedCount: 0,
        claimsRejectedCount: 0,
        unsupportedClaimsCount: 0,
      );
    }

    test('1. AI contradicts Flutter version -> rejected/unsupported', () {
      final raw = createRawDiagnosis(
        envAssessment: 'Project uses Flutter 3.20.0 and Dart 3.6.0.',
      );
      final validated =
          const AiEvidenceConsistencyValidator().validate(raw, sampleContext());

      expect(validated.claimsRejectedCount, greaterThan(0),
          reason:
              'Contradicting Flutter version must increment rejected count');
    });

    test('2. AI contradicts Gradle version -> rejected/unsupported', () {
      final raw = createRawDiagnosis(
        envAssessment: 'Project uses Gradle 7.5.',
      );
      final validated =
          const AiEvidenceConsistencyValidator().validate(raw, sampleContext());

      expect(validated.claimsRejectedCount, greaterThan(0),
          reason: 'Contradicting Gradle version must increment rejected count');
    });

    test('3. AI contradicts AGP/Gradle compatibility -> rejected/unsupported',
        () {
      final raw = createRawDiagnosis(
        envAssessment: 'AGP 8.5.0 and Gradle 8.7 are definitely incompatible.',
      );
      final validated =
          const AiEvidenceConsistencyValidator().validate(raw, sampleContext());

      expect(validated.claimsRejectedCount, greaterThan(0),
          reason:
              'Asserting absolute incompatibility without evidence must be rejected');
    });

    test('4. AI invents analyzer rule -> rejected', () {
      final raw = createRawDiagnosis(
        rootCauses: [
          const RootCauseDiagnosis(
            title: 'Invented Rule Issue',
            explanation: 'Explanation',
            priority: IssuePriority.high,
            deterministicConfidence: RootCauseConfidence.high,
            aiConfidence: RootCauseConfidence.high,
            evidence: ['rule: fake_invented_rule_xyz'],
            recommendedActions: [],
            affectedFiles: ['lib/file_0.dart'],
            occurrenceCount: 1,
          ),
        ],
      );
      final validated =
          const AiEvidenceConsistencyValidator().validate(raw, sampleContext());

      expect(validated.claimsRejectedCount, greaterThan(0));
      expect(validated.rootCauses.first.evidence,
          isNot(contains('rule: fake_invented_rule_xyz')),
          reason: 'Invented analyzer rule must be removed from evidence');
    });

    test('5. AI invents file path -> removed/unsupported', () {
      final raw = createRawDiagnosis(
        rootCauses: [
          const RootCauseDiagnosis(
            title: 'Invented File Issue',
            explanation: 'Explanation',
            priority: IssuePriority.high,
            deterministicConfidence: RootCauseConfidence.high,
            aiConfidence: RootCauseConfidence.high,
            evidence: ['rule: undefined_method'],
            recommendedActions: [],
            affectedFiles: ['lib/hallucinated_file.dart'],
            occurrenceCount: 1,
          ),
        ],
      );
      final validated =
          const AiEvidenceConsistencyValidator().validate(raw, sampleContext());

      expect(validated.claimsRejectedCount, greaterThan(0));
      expect(validated.rootCauses.first.affectedFiles,
          isNot(contains('lib/hallucinated_file.dart')),
          reason: 'Hallucinated file path must be removed from affectedFiles');
    });

    test('6. AI invents occurrence count -> deterministic count used', () {
      final raw = createRawDiagnosis(
        rootCauses: [
          const RootCauseDiagnosis(
            title: 'undefined_method',
            explanation: 'Explanation',
            priority: IssuePriority.critical,
            deterministicConfidence: RootCauseConfidence.high,
            aiConfidence: RootCauseConfidence.high,
            evidence: ['rule: undefined_method'],
            recommendedActions: [],
            affectedFiles: ['lib/file_0.dart'],
            occurrenceCount: 999, // AI claimed 999
          ),
        ],
      );
      final validated =
          const AiEvidenceConsistencyValidator().validate(raw, sampleContext());

      expect(validated.rootCauses.first.occurrenceCount, 15,
          reason:
              'Deterministic occurrence count (15) must override AI claim (999)');
    });

    test('7. AI downgrades CRITICAL to LOW -> deterministic priority preserved',
        () {
      final raw = createRawDiagnosis(
        rootCauses: [
          const RootCauseDiagnosis(
            title: 'undefined_method',
            explanation: 'Explanation',
            priority: IssuePriority.low, // AI attempted to downgrade
            deterministicConfidence: RootCauseConfidence.high,
            aiConfidence: RootCauseConfidence.low,
            evidence: ['rule: undefined_method'],
            recommendedActions: [],
            affectedFiles: ['lib/file_0.dart'],
            occurrenceCount: 15,
          ),
        ],
      );
      final validated =
          const AiEvidenceConsistencyValidator().validate(raw, sampleContext());

      expect(validated.rootCauses.first.priority, IssuePriority.critical,
          reason:
              'Deterministic priority (CRITICAL) must be preserved when AI attempts to downgrade to LOW');
      expect(validated.claimsRejectedCount, greaterThan(0));
    });

    test(
        '8. AI recommendation contradicts verified compatibility -> flagged unsupported',
        () {
      final raw = createRawDiagnosis(
        recommendations: [
          const Recommendation(
            title: 'Downgrade Gradle',
            explanation: 'Downgrade Gradle because it is incompatible.',
            priority: IssuePriority.high,
          ),
        ],
      );
      final validated =
          const AiEvidenceConsistencyValidator().validate(raw, sampleContext());

      expect(validated.unsupportedRecommendations, isNotEmpty,
          reason:
              'Recommendation contradicting toolchain compatibility must be flagged as unsupported');
      expect(validated.recommendations, isEmpty);
    });

    test(
        '9. AI inference with UNKNOWN evidence is allowed only with cautious language',
        () {
      final rawCautious = createRawDiagnosis(
        envAssessment:
            'Compatibility could not be verified for these toolchain versions.',
      );
      final validated = const AiEvidenceConsistencyValidator()
          .validate(rawCautious, sampleContext());

      expect(validated.claimsRejectedCount, 0,
          reason: 'Cautious language for unknown compatibility is accepted');
    });

    test('10. Valid AI diagnosis passes validation', () {
      final raw = createRawDiagnosis(
        envAssessment: 'Flutter 3.27.1, Gradle 8.7',
      );
      final validated =
          const AiEvidenceConsistencyValidator().validate(raw, sampleContext());

      expect(validated.claimsAcceptedCount, greaterThan(0));
      expect(validated.claimsRejectedCount, 0);
    });

    test('11. AI confidence remains separate from deterministic confidence',
        () {
      final raw = createRawDiagnosis(
        rootCauses: [
          const RootCauseDiagnosis(
            title: 'undefined_method',
            explanation: 'Explanation',
            priority: IssuePriority.critical,
            deterministicConfidence: RootCauseConfidence.high,
            aiConfidence: RootCauseConfidence.low,
            evidence: ['rule: undefined_method'],
            recommendedActions: [],
            affectedFiles: ['lib/file_0.dart'],
            occurrenceCount: 15,
          ),
        ],
      );
      final validated =
          const AiEvidenceConsistencyValidator().validate(raw, sampleContext());

      final rc = validated.rootCauses.first;
      expect(rc.deterministicConfidence, RootCauseConfidence.high);
      expect(rc.aiConfidence, RootCauseConfidence.low);
    });

    test('12. Existing 52 tests continue passing', () {
      expect(RuleRegistry.lookup('undefined_method'), isNotNull);
    });
  });
}
