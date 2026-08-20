// ignore_for_file: prefer_interpolation_to_compose_strings

import '../flutter_doctor.dart';
import '../models/ai_context.dart';
import '../models/issue_priority.dart';
import '../models/root_cause.dart';
import 'issue_prioritizer.dart';

/// Transforms [ProjectEvidence] + [RootCauseCandidate]s into a compact
/// [AiContext] ready for a future AI provider.
///
/// Design rules:
/// - MUST NOT include raw diagnostics (can be thousands of lines).
/// - MUST be compact — AI providers have token limits.
/// - Top issues are capped per priority tier.
/// - Root causes are included in full (they are already compact summaries).
class AiContextBuilder {
  const AiContextBuilder();

  /// Builds a compact [AiContext] from analysis results.
  ///
  /// [result] is used only for counts — individual diagnostics are NOT included.
  /// [prioritized] supplies the top issues per priority tier.
  /// [rootCauses] are the deterministic root cause candidates.
  /// Environment fields come from the toolchain evidence.
  AiContext build({
    required FlutterAnalysisResult result,
    required List<PrioritizedGroup> prioritized,
    required List<RootCauseCandidate> rootCauses,
    String? flutterVersion,
    String? dartVersion,
    String? channel,
    String? javaVersion,
    String? androidSdkPath,
    String? agpVersion,
    String? gradleVersion,
    String? kotlinVersion,
    String? compileSdk,
    String? targetSdk,
    String? minSdk,
  }) {
    // Analyzer summary — counts only.
    final analyzerSummary = <String, int>{
      'total': result.allIssues.length,
      'errors': result.errors.length,
      'warnings': result.warnings.length,
      'infos': result.infos.length,
    };

    // Top issues per priority tier (max 5 each).
    final topCritical = _topN(prioritized, IssuePriority.critical, 5);
    final topHigh = _topN(prioritized, IssuePriority.high, 5);
    final topMedium = _topN(prioritized, IssuePriority.medium, 5);

    // Root cause summaries.
    final rcSummaries = rootCauses.map((rc) {
      return RootCauseSummary(
        title: rc.title,
        summary: rc.summary,
        priority: rc.priority.displayName,
        confidence: rc.confidence.label,
        occurrenceCount: rc.occurrenceCount,
        affectedFileCount: rc.affectedFiles.length,
        relatedRules: rc.relatedRules,
        evidenceSummary:
            rc.evidence.map((e) => e.source.label + ': ' + e.value).toList(),
      );
    }).toList();

    return AiContext(
      projectInfo: {
        'flutter': flutterVersion,
        'dart': dartVersion,
        'channel': channel,
      },
      environmentInfo: {
        'java': javaVersion,
        'android_sdk': androidSdkPath,
      },
      androidInfo: {
        'agp': agpVersion,
        'gradle': gradleVersion,
        'kotlin': kotlinVersion,
        'compile_sdk': compileSdk,
        'target_sdk': targetSdk,
        'min_sdk': minSdk,
      },
      analyzerSummary: analyzerSummary,
      topCritical: topCritical,
      topHigh: topHigh,
      topMedium: topMedium,
      rootCauses: rcSummaries,
    );
  }

  List<IssueSummary> _topN(
    List<PrioritizedGroup> prioritized,
    IssuePriority priority,
    int n,
  ) {
    return prioritized
        .where((g) => g.priority == priority)
        .take(n)
        .map((g) => IssueSummary(
              rule: g.rule,
              priority: g.priority.displayName,
              category: g.category.label,
              occurrenceCount: g.occurrenceCount,
              exampleMessage: g.exampleMessage,
              fileCount: g.affectedFiles.length,
            ))
        .toList();
  }
}
