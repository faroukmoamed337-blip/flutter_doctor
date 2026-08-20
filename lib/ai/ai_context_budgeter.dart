import '../models/ai_context.dart';

/// Applies deterministic context budget caps to an [AiContext].
///
/// Ensures the context passed to AI remains compact and within token limits:
/// - Maximum 10 root causes.
/// - Maximum 10 evidence items per root cause.
/// - Maximum 5 top issue groups per priority tier.
class AiContextBudgeter {
  const AiContextBudgeter();

  static const int maxRootCauses = 10;
  static const int maxEvidencePerRootCause = 10;

  AiContext applyBudget(AiContext context) {
    final budgetedRootCauses = context.rootCauses
        .take(maxRootCauses)
        .map((rc) => RootCauseSummary(
              title: rc.title,
              summary: rc.summary,
              priority: rc.priority,
              confidence: rc.confidence,
              occurrenceCount: rc.occurrenceCount,
              affectedFileCount: rc.affectedFileCount,
              affectedFiles: rc.affectedFiles,
              relatedRules: rc.relatedRules,
              evidenceSummary:
                  rc.evidenceSummary.take(maxEvidencePerRootCause).toList(),
            ))
        .toList();

    return AiContext(
      projectInfo: context.projectInfo,
      environmentInfo: context.environmentInfo,
      androidInfo: context.androidInfo,
      analyzerSummary: context.analyzerSummary,
      topCritical: context.topCritical.take(5).toList(),
      topHigh: context.topHigh.take(5).toList(),
      topMedium: context.topMedium.take(5).toList(),
      rootCauses: budgetedRootCauses,
    );
  }
}
