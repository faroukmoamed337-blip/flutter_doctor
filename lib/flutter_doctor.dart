// ignore_for_file: library_private_types_in_public_api, prefer_interpolation_to_compose_strings, curly_braces_in_flow_control_structures

import 'dart:io';
import 'toolchain.dart';
import 'package:yaml/yaml.dart';
import 'models/issue_priority.dart';
import 'models/root_cause.dart';
import 'models/ai_diagnosis.dart';
import 'intelligence/issue_prioritizer.dart';
import 'intelligence/root_cause_engine.dart';
import 'ai/ai_provider.dart';

class FlutterIssue {
  const FlutterIssue(this.severity, this.message, this.file, this.line,
      this.column, this.rule);
  final String severity, message, file, rule;
  final int line, column;
}

class FlutterAnalysisResult {
  FlutterAnalysisResult(this.allIssues);
  final List<FlutterIssue> allIssues;
  List<FlutterIssue> get errors =>
      allIssues.where((x) => x.severity == 'error').toList();
  List<FlutterIssue> get warnings =>
      allIssues.where((x) => x.severity == 'warning').toList();
  List<FlutterIssue> get infos =>
      allIssues.where((x) => x.severity == 'info').toList();
  List<_Group> groups(String severity) {
    final m = <String, List<FlutterIssue>>{};
    for (final x in allIssues.where((x) => x.severity == severity)) {
      m.putIfAbsent(x.rule, () => []).add(x);
    }
    final r = m.entries.map((e) => _Group(e.key, e.value)).toList()
      ..sort((a, b) => b.items.length.compareTo(a.items.length));
    return r;
  }
}

class _Group {
  _Group(this.rule, this.items);
  final String rule;
  final List<FlutterIssue> items;
}

class FlutterIssueParser {
  static final _r = RegExp(
      r'^\s*(error|warning|info)\s*-\s*(.*)\s*-\s*(.+?):(\d+):(\d+)\s*-\s*([^\s]+)\s*$',
      caseSensitive: false);
  List<FlutterIssue> parse(String output) => output
      .split(RegExp(r'\r?\n'))
      .map((line) {
        final m = _r.firstMatch(line);
        return m == null
            ? null
            : FlutterIssue(
                m.group(1)!.toLowerCase(),
                m.group(2)!.trim(),
                m.group(3)!.trim(),
                int.parse(m.group(4)!),
                int.parse(m.group(5)!),
                m.group(6)!);
      })
      .whereType<FlutterIssue>()
      .toList();
}
class FlutterDependencyResult {
  const FlutterDependencyResult({
    required this.success,
    required this.output,
  });

  final bool success;
  final String output;
}

class FlutterDependencyManager {
  FlutterDependencyResult get(String path) {
    try {
      final process = Process.runSync(
        Platform.isWindows ? 'cmd.exe' : 'flutter',
        Platform.isWindows
            ? ['/c', 'flutter', 'pub', 'get']
            : ['pub', 'get'],
        workingDirectory: path,
      );

      final output =
          '${process.stdout}\n${process.stderr}'.trim();

      return FlutterDependencyResult(
        success: process.exitCode == 0,
        output: output,
      );
    } on ProcessException catch (e) {
      return FlutterDependencyResult(
        success: false,
        output: e.message,
      );
    }
  }
}
void reportDependencyHealth(FlutterDependencyResult result) {
  print('');
  print('================================');
  print('      Dependency Health');
  print('================================');
  print('');

  if (result.success) {
    print('pubspec.yaml        ✅ Valid');
    print('Dependencies        ✅ Resolved');
    print('flutter pub get      ✅ Successful');
  } else {
    print('pubspec.yaml        ✅ Found');
    print('Dependencies        ❌ Resolution failed');
    print('flutter pub get      ❌ Failed');

    print('');
    print('Output:');
    print(result.output);
  }

  print('');
  print('================================');
}
class FlutterAnalyzer {
  FlutterAnalysisResult? analyze(String path) {
    try {
      final p = Process.runSync(
          Platform.isWindows ? 'cmd.exe' : 'flutter',
          Platform.isWindows
              ? ['/c', 'flutter', 'analyze', '--no-pub']
              : ['analyze', '--no-pub'],
          workingDirectory: path);
      final output = p.stdout.toString() + '\n' + p.stderr.toString();
      if (output.toLowerCase().contains('flutter is not recognized') ||
          output.toLowerCase().contains('command not found')) return null;
      return FlutterAnalysisResult(FlutterIssueParser().parse(output));
    } on ProcessException {
      return null;
    }
  }
}

void report(FlutterAnalysisResult? r) {
  print('');
  print('================================');
  print('        Flutter Analyze');
  print('================================');
  print('');
  if (r == null) {
    print('❌ Flutter SDK not found.');
    print('');
    print('Make sure the "flutter" command is available in PATH.');
    return;
  }
  print('🔴 Errors:   ' + r.errors.length.toString());
  print('🟡 Warnings: ' + r.warnings.length.toString());
  print('🔵 Infos:    ' + r.infos.length.toString());
  print('');
  print('Total issues: ' + r.allIssues.length.toString());
  print('');
  print('--------------------------------');
  print('        Health Status');
  print('--------------------------------');
  print('');
  print(r.errors.isNotEmpty
      ? '🔴 CRITICAL'
      : r.warnings.isNotEmpty
          ? '🟡 NEEDS ATTENTION'
          : '🟢 HEALTHY');
  for (final severity in ['error', 'warning', 'info']) {
    final title = severity == 'info'
        ? 'Code Quality'
        : severity[0].toUpperCase() + severity.substring(1) + 's';
    print('');
    print('--------------------------------');
    print('        ' + title);
    print('--------------------------------');
    final groups = r.groups(severity);
    if (groups.isEmpty) {
      print('');
      print('No issues found.');
    }
    for (var i = 0; i < groups.length && i < 10; i++) {
      final g = groups[i];
      print('');
      print((i + 1).toString() + '. ' + g.rule);
      print('   ' + g.items.length.toString() + ' occurrences');
      if (severity == 'error') {
        print('');
        print('   Example:');
        print('   ' + g.items.first.message);
        print('');
        print('   Affected files:');
        final files =
            g.items.map((x) => x.file.replaceAll('\\', '/')).toSet().toList();
        for (final f in files.take(5)) {
          print('   • ' + f);
        }
        if (files.length > 5)
          print('   ... and ' + (files.length - 5).toString() + ' more files');
      }
    }
  }
  print('');
  print('================================');

  // ── Issue Intelligence (Phase 8) ─────────────────────────────────
  reportPrioritization(r);
}

/// Prints the Issue Intelligence / Prioritization section.
/// This is an additive layer — the existing analyzer data is never changed.
void reportPrioritization(FlutterAnalysisResult r) {
  final prioritizer = const IssuePrioritizer();
  final sorted = prioritizer.prioritize(r);
  final counts = prioritizer.countByPriority(sorted);
  final top = prioritizer.topProblems(sorted);

  print('');
  print('================================');
  print('      Issue Prioritization');
  print('================================');
  print('');
  print('Priority legend:');
  print(
      '  🔴 CRITICAL  Likely prevents compilation or direct correctness problem.');
  print('  🟠 HIGH      Potential runtime / correctness / safety problem.');
  print('  🟡 MEDIUM    Important maintenance, deprecation, or risky code.');
  print('  🔵 LOW       Code quality, style, readability, or optimization.');
  print('  ⚪ UNKNOWN   Analyzer rule not yet classified.');
  print('');

  // Priority summary — counts based on occurrences, not rule count.
  final order = [
    IssuePriority.critical,
    IssuePriority.high,
    IssuePriority.medium,
    IssuePriority.low,
    IssuePriority.unknown,
  ];
  for (final p in order) {
    final count = counts[p] ?? 0;
    final label = p.label;
    final pad =
        ' ' * (12 - label.replaceAll(RegExp(r'[^\x00-\x7F]'), '  ').length);
    print(label + ':' + pad + count.toString());
  }

  // ── Highest Priority (full detail, up to 10) ──────────────────────
  if (sorted.isNotEmpty) {
    print('');
    print('--------------------------------');
    print('      Highest Priority');
    print('--------------------------------');
    for (var i = 0; i < sorted.length && i < 10; i++) {
      final g = sorted[i];
      print('');
      print((i + 1).toString() + '. ' + g.rule);
      print('   ' + g.priority.label);
      print('   Category: ' + g.category.label);
      print('   Occurrences: ' + g.occurrenceCount.toString());
      if (g.description.isNotEmpty) {
        print('');
        // Word-wrap description at ~60 chars for readability.
        _printWrapped('   ', g.description, 60);
      }
      print('');
      print('   Example:');
      print('   ' + g.exampleMessage);
      print('');
      print('   Affected files:');
      for (final f in g.affectedFiles.take(5)) {
        print('   • ' + f);
      }
      if (g.affectedFiles.length > 5)
        print('   ... and ' +
            (g.affectedFiles.length - 5).toString() +
            ' more files');
    }
  }

  // ── Top Problems (compact, up to 10) ─────────────────────────────
  if (top.isNotEmpty) {
    print('');
    print('--------------------------------');
    print('        Top Problems');
    print('--------------------------------');
    for (final g in top) {
      print('');
      print(g.priority.emoji + ' ' + g.rule);
      print(g.occurrenceCount.toString() +
          ' occurrence' +
          (g.occurrenceCount == 1 ? '' : 's'));
    }
  }

  print('');
  print('================================');
}

/// Prints the Root Causes section from a pre-computed candidate list.
void reportRootCauses(List<RootCauseCandidate> candidates) {
  print('');
  print('================================');
  print('          Root Causes');
  print('================================');
  if (candidates.isEmpty) {
    print('');
    print('No deterministic root causes detected.');
    print('');
    print('================================');
    return;
  }
  for (var i = 0; i < candidates.length; i++) {
    final rc = candidates[i];
    print('');
    print((i + 1).toString() + '. ' + rc.priority.emoji + ' ' + rc.title);
    print('');
    print('   Confidence: ' + rc.confidence.label);
    print('   Priority:   ' + rc.priority.label);
    print('   Issues:     ' +
        rc.occurrenceCount.toString() +
        ' related analyzer issue' +
        (rc.occurrenceCount == 1 ? '' : 's'));
    if (rc.relatedRules.isNotEmpty) {
      print('   Rules:      ' + rc.relatedRules.join(', '));
    }
    print('');
    print('   Evidence:');
    for (final e in rc.evidence.take(5)) {
      print('   • ' + e.toString());
    }
    print('');
    print('   Summary:');
    _printWrapped('   ', rc.summary, 64);
    if (rc.affectedFiles.isNotEmpty) {
      print('');
      print('   Affected files:');
      for (final f in rc.affectedFiles.take(5)) {
        print('   • ' + f);
      }
      if (rc.affectedFiles.length > 5)
        print('   ... and ' +
            (rc.affectedFiles.length - 5).toString() +
            ' more files');
    }
    if (i < candidates.length - 1) {
      print('');
      print('   ' + '-' * 44);
    }
  }
  print('');
  print('================================');
}

/// Prints the AI Diagnosis section.
void reportAiDiagnosis(AiDiagnosisResult result) {
  print('');
  print('================================');
  print('          AI Diagnosis');
  print('================================');
  print('');

  if (!result.isAvailable || result.diagnosis == null) {
    print('⚪ AI Diagnosis unavailable');
    if (result.unavailableReason != null &&
        result.unavailableReason!.isNotEmpty) {
      print('');
      print('Reason:');
      print(result.unavailableReason);
    }
    print('');
    print('================================');
    return;
  }

  final d = result.diagnosis!;
  print('Assessment:');
  _printWrapped('', d.healthAssessment, 64);
  print('');

  if (d.verifiedFacts.isNotEmpty) {
    print('--------------------------------');
    print('        Verified Facts');
    print('--------------------------------');
    print('');
    for (final entry in d.verifiedFacts.entries) {
      print('• ' + entry.key + ': ' + entry.value);
    }
    print('');
  }

  print('--------------------------------');
  print('        AI Insights');
  print('--------------------------------');

  if (d.rootCauses.isEmpty) {
    print('');
    print('No AI root cause diagnoses available.');
  } else {
    for (var i = 0; i < d.rootCauses.length; i++) {
      final rc = d.rootCauses[i];
      print('');
      print((i + 1).toString() + '. ' + rc.priority.emoji + ' ' + rc.title);
      print('');
      print('Confidence:');
      print(rc.aiConfidence.label +
          ' (Deterministic: ' +
          rc.deterministicConfidence.label +
          ' | AI: ' +
          rc.aiConfidence.label +
          ')');
      print('');
      print('Diagnosis:');
      _printWrapped('', rc.explanation, 64);

      if (rc.evidence.isNotEmpty) {
        print('');
        print('Evidence:');
        for (final e in rc.evidence) {
          print('• ' + e);
        }
      }

      if (rc.recommendedActions.isNotEmpty) {
        print('');
        print('Recommended Actions:');
        for (var j = 0; j < rc.recommendedActions.length; j++) {
          print((j + 1).toString() + '. ' + rc.recommendedActions[j]);
        }
      }

      if (i < d.rootCauses.length - 1) {
        print('');
        print('--------------------------------');
      }
    }
  }

  print('');
  print('--------------------------------');
  print('        Recommendations');
  print('--------------------------------');
  if (d.recommendations.isEmpty) {
    print('');
    print('No verified recommendations.');
  } else {
    for (final rec in d.recommendations) {
      print('');
      print('⚠️ AI Recommendation: ' + rec.title);
      _printWrapped('', rec.explanation, 64);
    }
  }

  print('');
  print('--------------------------------');
  print('        Validation');
  print('--------------------------------');
  print('');
  print('AI claims accepted: ' + d.claimsAcceptedCount.toString());
  print('AI claims rejected: ' + d.claimsRejectedCount.toString());
  print('Unsupported claims: ' + d.unsupportedClaimsCount.toString());
  print('');
  print('The deterministic analyzer remains authoritative.');
  print('================================');
}

/// Word-wraps [text] to [width] characters, prefixing each line with [prefix].
void _printWrapped(String prefix, String text, int width) {
  final words = text.split(' ');
  var line = prefix;
  for (final word in words) {
    if (line.length + word.length + 1 > width + prefix.length &&
        line != prefix) {
      print(line);
      line = prefix + word;
    } else {
      line = line == prefix ? prefix + word : line + ' ' + word;
    }
  }
  if (line != prefix) print(line);
}

Future<void> runDoctor(List<String> args, {AiProvider? aiProvider}) async {
  String path = Directory.current.path;

  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--path' && i + 1 < args.length) {
      path = args[i + 1];
      i++;
    } else if (args[i].startsWith('--path=')) {
      path = args[i].substring('--path='.length);
    } else {
      print('❌ Invalid arguments.');
      print('Usage: flutter_doctor [--path "PATH_TO_PROJECT"]');
      return;
    }
  }

  final dir = Directory(path);
  if (!dir.existsSync()) {
    print('❌ Project directory not found.');
    print('Path: ' + path);
    return;
  }
  final file = File(path + Platform.pathSeparator + 'pubspec.yaml');
  if (!file.existsSync()) {
    print('❌ pubspec.yaml not found.');
    return;
  }
  final yaml = loadYaml(file.readAsStringSync()) as YamlMap;
  final deps = yaml['dependencies'];
  if (deps is! YamlMap ||
      deps['flutter'] is! YamlMap ||
      deps['flutter']['sdk'] != 'flutter') {
    print('❌ Flutter project not detected.');
    return;
  }
  print('✅ Flutter project detected!');
  _reportDependencies(yaml);

// ── Dependency Health ──────────────────────────────────────
final dependencyResult =
    FlutterDependencyManager().get(path);

reportDependencyHealth(dependencyResult);

if (!dependencyResult.success) {
  print('');
  print('⚠️ Flutter analysis skipped.');
  print('Reason: dependency resolution failed.');
  print('');
  print('Project scan completed.');
  return;
}

// ── Platform Detection ─────────────────────────────────────
print(Directory(path + Platform.pathSeparator + 'android').existsSync()
    ? '✅ Android folder found.'
    : '⚠️ Android folder not found.');

print(Directory(path + Platform.pathSeparator + 'ios').existsSync()
    ? '✅ iOS folder found.'
    : '⚠️ iOS folder not found.');

// ── Environment Evidence ───────────────────────────────────
final evidence = buildEvidence(path);
reportEvidence(evidence);

// ── Flutter Analyze ─────────────────────────────────────────
final analysisResult = FlutterAnalyzer().analyze(path);
report(analysisResult);
  if (analysisResult != null) {
    final prioritizer = const IssuePrioritizer();
    final prioritized = prioritizer.prioritize(analysisResult);
    final envEvidence = EvidenceCollector().collect(
      evidence.environment.flutterVersion,
      evidence.environment.dartVersion,
      evidence.environment.flutterChannel,
      evidence.environment.javaVersion,
      evidence.environment.androidSdkPath,
      evidence.android.agpVersion,
      evidence.android.gradleVersion,
      evidence.android.kotlinVersion,
      evidence.android.compileSdk,
      evidence.android.targetSdk,
      evidence.android.minSdk,
    );
    final rootCauses = const RootCauseEngine().analyze(
      result: analysisResult,
      prioritizedGroups: prioritized,
      environmentEvidence: envEvidence,
    );
    reportRootCauses(rootCauses);
  }
  print('Project scan completed.');
}

void _reportDependencies(YamlMap pubspec) {
  void list(String title, Object? value) {
    final names = value is YamlMap
        ? value.keys.map((key) => key.toString()).toList()
        : <String>[];
    print('');
    print(title + ': ' + names.length.toString());
    for (final name in names) {
      print('  • ' + name);
    }
  }

  list('Direct dependencies', pubspec['dependencies']);
  list('Dev dependencies', pubspec['dev_dependencies']);
  print('');
}
