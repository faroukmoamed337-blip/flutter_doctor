// ignore_for_file: prefer_interpolation_to_compose_strings

import '../flutter_doctor.dart';
import '../models/issue_priority.dart';
import '../models/issue_category.dart';
import '../models/evidence_item.dart';
import '../models/root_cause.dart';
import 'issue_prioritizer.dart';

/// Deterministic Root Cause Engine.
///
/// Analyzes [FlutterAnalysisResult] + [List<PrioritizedGroup>] + environment
/// [EvidenceItem]s to produce [RootCauseCandidate] objects.
///
/// Design rules:
/// - No AI API calls.
/// - No external network calls.
/// - Each analyzer issue contributes to AT MOST ONE root cause candidate.
/// - Confidence is only HIGH when evidence is unambiguous and multi-sourced.
/// - Unknown relationships are NOT guessed.
class RootCauseEngine {
  const RootCauseEngine();

  /// Produces a sorted list of [RootCauseCandidate] objects.
  ///
  /// Sorted by priority first (critical → unknown), then occurrenceCount desc.
  ///
  /// Each [FlutterIssue] is attributed to at most one candidate —
  /// the total across all candidates never exceeds [result.allIssues.length].
  List<RootCauseCandidate> analyze({
    required FlutterAnalysisResult result,
    required List<PrioritizedGroup> prioritizedGroups,
    required List<EvidenceItem> environmentEvidence,
  }) {
    final candidates = <RootCauseCandidate>[];
    // Track which rules have already been processed to avoid double-counting.
    final processedRules = <String>{};

    // ── CRITICAL clusters ─────────────────────────────────────────────
    _clusterUndefinedSymbols(result, prioritizedGroups, environmentEvidence,
        candidates, processedRules);
    _clusterTypeErrors(result, prioritizedGroups, environmentEvidence,
        candidates, processedRules);

    // ── HIGH clusters ──────────────────────────────────────────────────
    _clusterBuildContext(result, prioritizedGroups, environmentEvidence,
        candidates, processedRules);
    _clusterNullSafety(result, prioritizedGroups, environmentEvidence,
        candidates, processedRules);

    // ── MEDIUM clusters ────────────────────────────────────────────────
    _clusterDeprecatedApis(result, prioritizedGroups, environmentEvidence,
        candidates, processedRules);
    _clusterMissingDependencies(result, prioritizedGroups, environmentEvidence,
        candidates, processedRules);
    _clusterUnusedCode(result, prioritizedGroups, environmentEvidence,
        candidates, processedRules);

    // ── LOW clusters ───────────────────────────────────────────────────
    _clusterPerformanceHints(result, prioritizedGroups, environmentEvidence,
        candidates, processedRules);
    _clusterSizedBox(result, prioritizedGroups, environmentEvidence, candidates,
        processedRules);
    _clusterUnusedImports(result, prioritizedGroups, environmentEvidence,
        candidates, processedRules);
    _clusterDebugStatements(result, prioritizedGroups, environmentEvidence,
        candidates, processedRules);
    _clusterControlFlowStyle(result, prioritizedGroups, environmentEvidence,
        candidates, processedRules);
    _clusterNamingStyle(result, prioritizedGroups, environmentEvidence,
        candidates, processedRules);

    // Sort: priority asc, then occurrenceCount desc.
    candidates.sort((a, b) {
      final byPriority = a.priority.sortOrder.compareTo(b.priority.sortOrder);
      if (byPriority != 0) return byPriority;
      return b.occurrenceCount.compareTo(a.occurrenceCount);
    });

    return candidates;
  }

  // ────────────────────────────────────────────────────────────────────
  // CRITICAL: Undefined symbols
  // ────────────────────────────────────────────────────────────────────

  void _clusterUndefinedSymbols(
    FlutterAnalysisResult result,
    List<PrioritizedGroup> groups,
    List<EvidenceItem> env,
    List<RootCauseCandidate> out,
    Set<String> processed,
  ) {
    const targetRules = [
      'undefined_method',
      'undefined_class',
      'undefined_identifier',
      'undefined_function',
    ];

    for (final rule in targetRules) {
      if (processed.contains(rule)) continue;
      final issues = result.allIssues.where((i) => i.rule == rule).toList();
      if (issues.isEmpty) continue;
      processed.add(rule);

      // Sub-cluster by the extracted symbol name.
      final bySym = _groupByUndefinedSymbol(issues, rule);
      for (final entry in bySym.entries) {
        final sym = entry.key;
        final symIssues = entry.value;
        final files = _uniqueFiles(symIssues);

        // High confidence when the SAME symbol is missing across 3+ files.
        final confidence = (sym != _kUnknown && files.length >= 3)
            ? RootCauseConfidence.high
            : (sym != _kUnknown && symIssues.length >= 2)
                ? RootCauseConfidence.medium
                : RootCauseConfidence.low;

        final evidence = [
          _analyzerEvidence(EvidenceType.rule, rule),
          _analyzerEvidence(EvidenceType.occurrence,
              symIssues.length.toString() + ' occurrences'),
          if (sym != _kUnknown) _analyzerEvidence(EvidenceType.apiSymbol, sym),
          if (files.length > 1)
            _analyzerEvidence(EvidenceType.description,
                files.length.toString() + ' affected files'),
          ..._envBySource(env, EvidenceSource.flutterVersion),
        ];

        final title = sym == _kUnknown
            ? 'Multiple undefined ' + _symbolKind(rule) + 's'
            : sym + ' is undefined';

        final summary = _undefinedSummary(rule, sym, symIssues, files);

        out.add(RootCauseCandidate(
          title: title,
          summary: summary,
          priority: IssuePriority.critical,
          category: IssueCategory.correctness,
          confidence: confidence,
          evidence: evidence,
          relatedRules: [rule],
          affectedFiles: files,
          occurrenceCount: symIssues.length,
        ));
      }
    }
  }

  // ────────────────────────────────────────────────────────────────────
  // CRITICAL: Type errors
  // ────────────────────────────────────────────────────────────────────

  void _clusterTypeErrors(
    FlutterAnalysisResult result,
    List<PrioritizedGroup> groups,
    List<EvidenceItem> env,
    List<RootCauseCandidate> out,
    Set<String> processed,
  ) {
    const targetRules = [
      'argument_type_not_assignable',
      'return_of_invalid_type',
      'invalid_assignment',
    ];

    final issues = <FlutterIssue>[];
    final usedRules = <String>[];
    for (final rule in targetRules) {
      if (processed.contains(rule)) continue;
      final r = result.allIssues.where((i) => i.rule == rule).toList();
      if (r.isEmpty) continue;
      issues.addAll(r);
      usedRules.add(rule);
      processed.add(rule);
    }
    if (issues.isEmpty) return;

    final files = _uniqueFiles(issues);
    out.add(RootCauseCandidate(
      title: 'Type safety violations',
      summary: 'The project has ' +
          issues.length.toString() +
          ' type-related errors across ' +
          files.length.toString() +
          ' files. Values are being passed or returned with incompatible types. '
              'These must be resolved before the project can compile correctly.',
      priority: IssuePriority.critical,
      category: IssueCategory.correctness,
      confidence: RootCauseConfidence.high,
      evidence: [
        for (final r in usedRules) _analyzerEvidence(EvidenceType.rule, r),
        _analyzerEvidence(
            EvidenceType.occurrence,
            issues.length.toString() +
                ' occurrences across ' +
                files.length.toString() +
                ' files'),
      ],
      relatedRules: usedRules,
      affectedFiles: files,
      occurrenceCount: issues.length,
    ));
  }

  // ────────────────────────────────────────────────────────────────────
  // HIGH: BuildContext across async gaps
  // ────────────────────────────────────────────────────────────────────

  void _clusterBuildContext(
    FlutterAnalysisResult result,
    List<PrioritizedGroup> groups,
    List<EvidenceItem> env,
    List<RootCauseCandidate> out,
    Set<String> processed,
  ) {
    const rule = 'use_build_context_synchronously';
    if (processed.contains(rule)) return;
    final issues = result.allIssues.where((i) => i.rule == rule).toList();
    if (issues.isEmpty) return;
    processed.add(rule);

    final files = _uniqueFiles(issues);
    out.add(RootCauseCandidate(
      title: 'BuildContext used across asynchronous gaps',
      summary: 'BuildContext is referenced after an async gap in ' +
          issues.length.toString() +
          ' locations across ' +
          files.length.toString() +
          ' files. If a widget is unmounted during an async operation, '
              'using its BuildContext may cause a runtime problem. '
              'Check the "mounted" property before using the context after an await.',
      priority: IssuePriority.high,
      category: IssueCategory.runtimeSafety,
      confidence: RootCauseConfidence.high,
      evidence: [
        _analyzerEvidence(EvidenceType.rule, rule),
        _analyzerEvidence(
            EvidenceType.occurrence,
            issues.length.toString() +
                ' occurrences in ' +
                files.length.toString() +
                ' files'),
      ],
      relatedRules: [rule],
      affectedFiles: files,
      occurrenceCount: issues.length,
    ));
  }

  // ────────────────────────────────────────────────────────────────────
  // HIGH: Null safety violations
  // ────────────────────────────────────────────────────────────────────

  void _clusterNullSafety(
    FlutterAnalysisResult result,
    List<PrioritizedGroup> groups,
    List<EvidenceItem> env,
    List<RootCauseCandidate> out,
    Set<String> processed,
  ) {
    const targetRules = [
      'invalid_null_aware_operator',
      'unnecessary_non_null_assertion',
      'override_on_non_overriding_member',
    ];

    final issues = <FlutterIssue>[];
    final usedRules = <String>[];
    for (final rule in targetRules) {
      if (processed.contains(rule)) continue;
      final r = result.allIssues.where((i) => i.rule == rule).toList();
      if (r.isEmpty) continue;
      issues.addAll(r);
      usedRules.add(rule);
      processed.add(rule);
    }
    if (issues.isEmpty) return;

    final files = _uniqueFiles(issues);
    out.add(RootCauseCandidate(
      title: 'Null safety and override issues',
      summary: issues.length.toString() +
          ' null-safety or override-related issues detected. '
              'These may indicate logic errors or incorrect assumptions about nullability.',
      priority: IssuePriority.high,
      category: IssueCategory.runtimeSafety,
      confidence: RootCauseConfidence.medium,
      evidence: [
        for (final r in usedRules) _analyzerEvidence(EvidenceType.rule, r),
        _analyzerEvidence(
            EvidenceType.occurrence, issues.length.toString() + ' occurrences'),
      ],
      relatedRules: usedRules,
      affectedFiles: files,
      occurrenceCount: issues.length,
    ));
  }

  // ────────────────────────────────────────────────────────────────────
  // MEDIUM: Deprecated APIs (sub-clustered by symbol)
  // ────────────────────────────────────────────────────────────────────

  void _clusterDeprecatedApis(
    FlutterAnalysisResult result,
    List<PrioritizedGroup> groups,
    List<EvidenceItem> env,
    List<RootCauseCandidate> out,
    Set<String> processed,
  ) {
    const rule = 'deprecated_member_use';
    if (processed.contains(rule)) return;
    final issues = result.allIssues.where((i) => i.rule == rule).toList();
    if (issues.isEmpty) return;
    processed.add(rule);

    // Sub-cluster by deprecated symbol name.
    final bySymbol = _groupByDeprecatedSymbol(issues);

    for (final entry in bySymbol.entries) {
      final sym = entry.key;
      final symIssues = entry.value;
      final files = _uniqueFiles(symIssues);

      final isKnown = sym != _kUnknown;
      final confidence = isKnown && symIssues.length >= 2
          ? RootCauseConfidence.medium
          : RootCauseConfidence.low;

      out.add(RootCauseCandidate(
        title: isKnown
            ? "'" + sym + "' is deprecated"
            : 'Unidentified deprecated API usage',
        summary: symIssues.length.toString() +
            ' use' +
            (symIssues.length == 1 ? '' : 's') +
            ' of ' +
            (isKnown ? "'" + sym + "'" : 'a deprecated API') +
            ' detected across ' +
            files.length.toString() +
            ' file' +
            (files.length == 1 ? '' : 's') +
            '. ' +
            'This API may be removed in a future SDK version. '
                'Review the deprecation message for the recommended replacement.',
        priority: IssuePriority.medium,
        category: IssueCategory.deprecatedApi,
        confidence: confidence,
        evidence: [
          _analyzerEvidence(EvidenceType.rule, rule),
          if (isKnown) _analyzerEvidence(EvidenceType.apiSymbol, sym),
          _analyzerEvidence(
              EvidenceType.occurrence,
              symIssues.length.toString() +
                  ' occurrences in ' +
                  files.length.toString() +
                  ' files'),
          ..._envBySource(env, EvidenceSource.flutterVersion),
          ..._envBySource(env, EvidenceSource.dartVersion),
        ],
        relatedRules: [rule],
        affectedFiles: files,
        occurrenceCount: symIssues.length,
      ));
    }
  }

  // ────────────────────────────────────────────────────────────────────
  // MEDIUM: Missing declared dependencies
  // ────────────────────────────────────────────────────────────────────

  void _clusterMissingDependencies(
    FlutterAnalysisResult result,
    List<PrioritizedGroup> groups,
    List<EvidenceItem> env,
    List<RootCauseCandidate> out,
    Set<String> processed,
  ) {
    const rule = 'depend_on_referenced_packages';
    if (processed.contains(rule)) return;
    final issues = result.allIssues.where((i) => i.rule == rule).toList();
    if (issues.isEmpty) return;
    processed.add(rule);

    final files = _uniqueFiles(issues);
    out.add(RootCauseCandidate(
      title: 'Packages used without direct dependency',
      summary: issues.length.toString() +
          ' file' +
          (issues.length == 1 ? '' : 's') +
          ' reference packages not listed as direct dependencies in pubspec.yaml. '
              'Transitive dependencies are not guaranteed to remain available. '
              'Add the missing packages to pubspec.yaml.',
      priority: IssuePriority.medium,
      category: IssueCategory.maintainability,
      confidence: RootCauseConfidence.high,
      evidence: [
        _analyzerEvidence(EvidenceType.rule, rule),
        _analyzerEvidence(
            EvidenceType.occurrence, issues.length.toString() + ' occurrences'),
        EvidenceItem(
          source: EvidenceSource.pubspec,
          type: EvidenceType.description,
          value: 'Packages must be listed as direct dependencies',
          reliability: EvidenceReliability.high,
        ),
      ],
      relatedRules: [rule],
      affectedFiles: files,
      occurrenceCount: issues.length,
    ));
  }

  // ────────────────────────────────────────────────────────────────────
  // MEDIUM: Unused code
  // ────────────────────────────────────────────────────────────────────

  void _clusterUnusedCode(
    FlutterAnalysisResult result,
    List<PrioritizedGroup> groups,
    List<EvidenceItem> env,
    List<RootCauseCandidate> out,
    Set<String> processed,
  ) {
    const targetRules = [
      'unused_local_variable',
      'unused_field',
      'unused_element',
      'dead_null_aware_expression',
    ];

    final issues = <FlutterIssue>[];
    final usedRules = <String>[];
    for (final rule in targetRules) {
      if (processed.contains(rule)) continue;
      final r = result.allIssues.where((i) => i.rule == rule).toList();
      if (r.isEmpty) continue;
      issues.addAll(r);
      usedRules.add(rule);
      processed.add(rule);
    }
    if (issues.isEmpty) return;

    final files = _uniqueFiles(issues);
    out.add(RootCauseCandidate(
      title: 'Unused code and dead declarations',
      summary: issues.length.toString() +
          ' unused variables, fields, or elements detected across ' +
          files.length.toString() +
          ' files. These may indicate dead code or logic errors '
              'where a variable is written but never read.',
      priority: IssuePriority.medium,
      category: IssueCategory.codeQuality,
      confidence: RootCauseConfidence.medium,
      evidence: [
        for (final r in usedRules) _analyzerEvidence(EvidenceType.rule, r),
        _analyzerEvidence(
            EvidenceType.occurrence, issues.length.toString() + ' occurrences'),
      ],
      relatedRules: usedRules,
      affectedFiles: files,
      occurrenceCount: issues.length,
    ));
  }

  // ────────────────────────────────────────────────────────────────────
  // LOW: Performance hints
  // ────────────────────────────────────────────────────────────────────

  void _clusterPerformanceHints(
    FlutterAnalysisResult result,
    List<PrioritizedGroup> groups,
    List<EvidenceItem> env,
    List<RootCauseCandidate> out,
    Set<String> processed,
  ) {
    const targetRules = [
      'prefer_const_constructors',
      'prefer_const_literals_to_create_immutables',
    ];

    final issues = <FlutterIssue>[];
    final usedRules = <String>[];
    for (final rule in targetRules) {
      if (processed.contains(rule)) continue;
      final r = result.allIssues.where((i) => i.rule == rule).toList();
      if (r.isEmpty) continue;
      issues.addAll(r);
      usedRules.add(rule);
      processed.add(rule);
    }
    if (issues.isEmpty) return;

    final files = _uniqueFiles(issues);
    out.add(RootCauseCandidate(
      title: 'Const constructor opportunities',
      summary: issues.length.toString() +
          ' constructor call' +
          (issues.length == 1 ? '' : 's') +
          ' that the analyzer suggests could be made const. '
              'Const constructors allow Flutter to reuse widget instances '
              'and may reduce unnecessary object allocation.',
      priority: IssuePriority.low,
      category: IssueCategory.performance,
      confidence: RootCauseConfidence.high,
      evidence: [
        for (final r in usedRules) _analyzerEvidence(EvidenceType.rule, r),
        _analyzerEvidence(
            EvidenceType.occurrence, issues.length.toString() + ' occurrences'),
      ],
      relatedRules: usedRules,
      affectedFiles: files,
      occurrenceCount: issues.length,
    ));
  }

  // ────────────────────────────────────────────────────────────────────
  // LOW: SizedBox for whitespace
  // ────────────────────────────────────────────────────────────────────

  void _clusterSizedBox(
    FlutterAnalysisResult result,
    List<PrioritizedGroup> groups,
    List<EvidenceItem> env,
    List<RootCauseCandidate> out,
    Set<String> processed,
  ) {
    const rule = 'sized_box_for_whitespace';
    if (processed.contains(rule)) return;
    final issues = result.allIssues.where((i) => i.rule == rule).toList();
    if (issues.isEmpty) return;
    processed.add(rule);

    final files = _uniqueFiles(issues);
    out.add(RootCauseCandidate(
      title: 'Container used for whitespace instead of SizedBox',
      summary: issues.length.toString() +
          ' place' +
          (issues.length == 1 ? '' : 's') +
          ' where a Container with only width or height is reported. '
              'The analyzer suggests using SizedBox instead, '
              'which is a lighter widget for adding fixed-size whitespace.',
      priority: IssuePriority.low,
      category: IssueCategory.performance,
      confidence: RootCauseConfidence.high,
      evidence: [
        _analyzerEvidence(EvidenceType.rule, rule),
        _analyzerEvidence(
            EvidenceType.occurrence, issues.length.toString() + ' occurrences'),
      ],
      relatedRules: [rule],
      affectedFiles: files,
      occurrenceCount: issues.length,
    ));
  }

  // ────────────────────────────────────────────────────────────────────
  // LOW: Unused imports
  // ────────────────────────────────────────────────────────────────────

  void _clusterUnusedImports(
    FlutterAnalysisResult result,
    List<PrioritizedGroup> groups,
    List<EvidenceItem> env,
    List<RootCauseCandidate> out,
    Set<String> processed,
  ) {
    const targetRules = ['unused_import', 'unnecessary_import'];

    final issues = <FlutterIssue>[];
    final usedRules = <String>[];
    for (final rule in targetRules) {
      if (processed.contains(rule)) continue;
      final r = result.allIssues.where((i) => i.rule == rule).toList();
      if (r.isEmpty) continue;
      issues.addAll(r);
      usedRules.add(rule);
      processed.add(rule);
    }
    if (issues.isEmpty) return;

    final files = _uniqueFiles(issues);
    out.add(RootCauseCandidate(
      title: 'Unused and redundant imports',
      summary: issues.length.toString() +
          ' import statement' +
          (issues.length == 1 ? '' : 's') +
          ' reported as unused or redundant across ' +
          files.length.toString() +
          ' file' +
          (files.length == 1 ? '' : 's') +
          '. Removing them reduces build overhead and improves readability.',
      priority: IssuePriority.low,
      category: IssueCategory.codeQuality,
      confidence: RootCauseConfidence.high,
      evidence: [
        for (final r in usedRules) _analyzerEvidence(EvidenceType.rule, r),
        _analyzerEvidence(
            EvidenceType.occurrence, issues.length.toString() + ' occurrences'),
      ],
      relatedRules: usedRules,
      affectedFiles: files,
      occurrenceCount: issues.length,
    ));
  }

  // ────────────────────────────────────────────────────────────────────
  // LOW: Debug / output statements
  // ────────────────────────────────────────────────────────────────────

  void _clusterDebugStatements(
    FlutterAnalysisResult result,
    List<PrioritizedGroup> groups,
    List<EvidenceItem> env,
    List<RootCauseCandidate> out,
    Set<String> processed,
  ) {
    const rule = 'avoid_print';
    if (processed.contains(rule)) return;
    final issues = result.allIssues.where((i) => i.rule == rule).toList();
    if (issues.isEmpty) return;
    processed.add(rule);

    final files = _uniqueFiles(issues);
    out.add(RootCauseCandidate(
      title: 'Debug print statements in production code',
      summary: issues.length.toString() +
          ' use' +
          (issues.length == 1 ? '' : 's') +
          ' of print() reported across ' +
          files.length.toString() +
          ' file' +
          (files.length == 1 ? '' : 's') +
          '. The analyzer recommends replacing print() with a proper '
              'logging solution in production code.',
      priority: IssuePriority.low,
      category: IssueCategory.codeQuality,
      confidence: RootCauseConfidence.high,
      evidence: [
        _analyzerEvidence(EvidenceType.rule, rule),
        _analyzerEvidence(
            EvidenceType.occurrence, issues.length.toString() + ' occurrences'),
      ],
      relatedRules: [rule],
      affectedFiles: files,
      occurrenceCount: issues.length,
    ));
  }

  // ────────────────────────────────────────────────────────────────────
  // LOW: Control-flow style
  // ────────────────────────────────────────────────────────────────────

  void _clusterControlFlowStyle(
    FlutterAnalysisResult result,
    List<PrioritizedGroup> groups,
    List<EvidenceItem> env,
    List<RootCauseCandidate> out,
    Set<String> processed,
  ) {
    const targetRules = [
      'curly_braces_in_flow_control_structures',
      'unnecessary_this',
    ];

    final issues = <FlutterIssue>[];
    final usedRules = <String>[];
    for (final rule in targetRules) {
      if (processed.contains(rule)) continue;
      final r = result.allIssues.where((i) => i.rule == rule).toList();
      if (r.isEmpty) continue;
      issues.addAll(r);
      usedRules.add(rule);
      processed.add(rule);
    }
    if (issues.isEmpty) return;

    final files = _uniqueFiles(issues);
    out.add(RootCauseCandidate(
      title: 'Control-flow and expression style',
      summary: issues.length.toString() +
          ' control-flow or expression style issue' +
          (issues.length == 1 ? '' : 's') +
          ' reported across ' +
          files.length.toString() +
          ' file' +
          (files.length == 1 ? '' : 's') +
          '. These include missing braces in flow-control statements '
              'and unnecessary "this" references.',
      priority: IssuePriority.low,
      category: IssueCategory.style,
      confidence: RootCauseConfidence.high,
      evidence: [
        for (final r in usedRules) _analyzerEvidence(EvidenceType.rule, r),
        _analyzerEvidence(
            EvidenceType.occurrence, issues.length.toString() + ' occurrences'),
      ],
      relatedRules: usedRules,
      affectedFiles: files,
      occurrenceCount: issues.length,
    ));
  }

  // ────────────────────────────────────────────────────────────────────
  // LOW: Naming and style consistency
  // ────────────────────────────────────────────────────────────────────

  void _clusterNamingStyle(
    FlutterAnalysisResult result,
    List<PrioritizedGroup> groups,
    List<EvidenceItem> env,
    List<RootCauseCandidate> out,
    Set<String> processed,
  ) {
    const targetRules = [
      'file_names',
      'camel_case_types',
      'non_constant_identifier_names',
    ];

    final issues = <FlutterIssue>[];
    final usedRules = <String>[];
    for (final rule in targetRules) {
      if (processed.contains(rule)) continue;
      final r = result.allIssues.where((i) => i.rule == rule).toList();
      if (r.isEmpty) continue;
      issues.addAll(r);
      usedRules.add(rule);
      processed.add(rule);
    }
    if (issues.isEmpty) return;

    final files = _uniqueFiles(issues);
    out.add(RootCauseCandidate(
      title: 'Naming convention violations',
      summary: issues.length.toString() +
          ' naming convention issue' +
          (issues.length == 1 ? '' : 's') +
          ' reported across ' +
          files.length.toString() +
          ' file' +
          (files.length == 1 ? '' : 's') +
          '. These include file names, type names, and identifier names '
              'that do not follow Dart naming conventions.',
      priority: IssuePriority.low,
      category: IssueCategory.style,
      confidence: RootCauseConfidence.high,
      evidence: [
        for (final r in usedRules) _analyzerEvidence(EvidenceType.rule, r),
        _analyzerEvidence(
            EvidenceType.occurrence, issues.length.toString() + ' occurrences'),
      ],
      relatedRules: usedRules,
      affectedFiles: files,
      occurrenceCount: issues.length,
    ));
  }

  // ────────────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────────────

  static const _kUnknown = '__unknown__';

  static EvidenceItem _analyzerEvidence(EvidenceType type, String value) =>
      EvidenceItem(
        source: EvidenceSource.flutterAnalyzer,
        type: type,
        value: value,
        reliability: EvidenceReliability.high,
      );

  static List<EvidenceItem> _envBySource(
    List<EvidenceItem> env,
    EvidenceSource source,
  ) =>
      env.where((e) => e.source == source).toList();

  static List<String> _uniqueFiles(List<FlutterIssue> issues) =>
      issues.map((i) => i.file.replaceAll('\\', '/')).toSet().toList()..sort();

  static String _symbolKind(String rule) => switch (rule) {
        'undefined_method' => 'method',
        'undefined_class' => 'class',
        'undefined_identifier' => 'identifier',
        'undefined_function' => 'function',
        _ => 'symbol',
      };

  /// Groups [issues] by the undefined symbol extracted from the message.
  static Map<String, List<FlutterIssue>> _groupByUndefinedSymbol(
    List<FlutterIssue> issues,
    String rule,
  ) {
    final patterns = <String, RegExp>{
      'undefined_method':
          RegExp(r"The (?:method|getter) '([^']+)' isn't defined for"),
      'undefined_class': RegExp(r"Undefined class '([^']+)'"),
      'undefined_identifier': RegExp(r"Undefined name '([^']+)'"),
      'undefined_function': RegExp(r"The function '([^']+)' isn't defined"),
    };

    final pattern = patterns[rule];
    final result = <String, List<FlutterIssue>>{};
    for (final issue in issues) {
      String key = _kUnknown;
      if (pattern != null) {
        final m = pattern.firstMatch(issue.message);
        if (m != null) key = m.group(1)!;
      }
      result.putIfAbsent(key, () => []).add(issue);
    }
    return result;
  }

  /// Groups deprecated_member_use issues by the deprecated symbol name.
  ///
  /// Tries multiple message patterns emitted by the Dart analyzer.
  /// Issues that cannot be matched are grouped under [_kUnknown].
  /// Trivial symbol variants (e.g. Foo.new vs Foo) are normalized
  /// so they map to the same root cause.
  static Map<String, List<FlutterIssue>> _groupByDeprecatedSymbol(
    List<FlutterIssue> issues,
  ) {
    // Each pattern must capture the deprecated symbol name in group 1.
    final patterns = [
      // "'symbol' is deprecated..."
      RegExp(r"'([^']+)' is deprecated"),
      // "Use of deprecated member 'symbol'..."
      RegExp(r"deprecated member '([^']+)'"),
      // "Use of deprecated 'symbol'..."
      RegExp(r"Use of deprecated '([^']+)'"),
      // "The member 'symbol' is deprecated..."
      RegExp(r"member '([^']+)' is deprecated"),
    ];

    final result = <String, List<FlutterIssue>>{};
    for (final issue in issues) {
      String key = _kUnknown;
      for (final p in patterns) {
        final m = p.firstMatch(issue.message);
        if (m != null) {
          key = _normalizeDeprecatedSymbol(m.group(1)!);
          break;
        }
      }
      result.putIfAbsent(key, () => []).add(issue);
    }
    return result;
  }

  /// Normalizes trivial deprecated symbol variants to a canonical form.
  ///
  /// Rules applied (in order):
  /// 1. Strip a trailing ".new" suffix — "Foo.new" and "Foo" are the same
  ///    constructor and should map to the same root cause.
  ///
  /// No case-folding or fuzzy matching is performed. Only transformations
  /// that are unambiguously the same API are applied.
  static String _normalizeDeprecatedSymbol(String raw) {
    // Strip trailing .new (default constructor references).
    if (raw.endsWith('.new')) return raw.substring(0, raw.length - 4);
    return raw;
  }

  static String _undefinedSummary(
    String rule,
    String sym,
    List<FlutterIssue> issues,
    List<String> files,
  ) {
    final kind = _symbolKind(rule);
    final base = sym == _kUnknown
        ? 'Multiple undefined ${kind}s detected across '
            '${files.length} file${files.length == 1 ? "" : "s"}.'
        : "The $kind '$sym' is not recognized by the analyzer in "
            '${files.length} file${files.length == 1 ? "" : "s"} '
            '(${issues.length} occurrence${issues.length == 1 ? "" : "s"}).';
    return base +
        ' This may prevent compilation. Verify that the correct package '
            'is imported and that the API exists in the current SDK version.';
  }
}

/// Collects [EvidenceItem]s from the available project and environment data.
///
/// Called by [runDoctor] to build the evidence list before passing it to
/// [RootCauseEngine].
class EvidenceCollector {
  const EvidenceCollector();

  /// Builds evidence items from toolchain and environment info.
  List<EvidenceItem> collect(
    String? flutterVersion,
    String? dartVersion,
    String? channel,
    String? javaVersion,
    String? androidSdkPath,
    String? agpVersion,
    String? gradleVersion,
    String? kotlinVersion,
    int? compileSdk,
    int? targetSdk,
    int? minSdk,
  ) {
    final items = <EvidenceItem>[];

    void add(EvidenceSource src, EvidenceType type, String? value) {
      if (value != null && value.isNotEmpty) {
        items.add(EvidenceItem(
          source: src,
          type: type,
          value: value,
          reliability: EvidenceReliability.high,
        ));
      }
    }

    add(EvidenceSource.flutterVersion, EvidenceType.version, flutterVersion);
    add(EvidenceSource.dartVersion, EvidenceType.version, dartVersion);
    add(EvidenceSource.flutterVersion, EvidenceType.config, channel);
    add(EvidenceSource.java, EvidenceType.version, javaVersion);
    add(EvidenceSource.agp, EvidenceType.version, agpVersion);
    add(EvidenceSource.gradle, EvidenceType.version, gradleVersion);
    add(EvidenceSource.kotlin, EvidenceType.version, kotlinVersion);
    if (androidSdkPath != null) {
      items.add(EvidenceItem(
        source: EvidenceSource.agp,
        type: EvidenceType.filePath,
        value: androidSdkPath,
        reliability: EvidenceReliability.high,
      ));
    }
    if (compileSdk != null) {
      add(EvidenceSource.compileSdk, EvidenceType.config,
          compileSdk.toString());
    }
    if (targetSdk != null) {
      add(EvidenceSource.targetSdk, EvidenceType.config, targetSdk.toString());
    }
    if (minSdk != null) {
      add(EvidenceSource.minSdk, EvidenceType.config, minSdk.toString());
    }

    return items;
  }
}
