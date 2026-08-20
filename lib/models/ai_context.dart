// Compact structured context passed to a future AI provider.
//
// Design rules:
// - Must NOT contain all raw diagnostics (can be thousands of lines).
// - Must be compact — AI providers have token limits.
// - Must contain enough context for an AI to reason about the project.
// - All values are plain strings/maps/lists — easily serializable.

/// A compact summary of one prioritized analyzer rule group.
class IssueSummary {
  const IssueSummary({
    required this.rule,
    required this.priority,
    required this.category,
    required this.occurrenceCount,
    required this.exampleMessage,
    required this.fileCount,
  });

  final String rule;
  final String priority;
  final String category;
  final int occurrenceCount;
  final String exampleMessage;
  final int fileCount;

  Map<String, Object> toMap() => {
        'rule': rule,
        'priority': priority,
        'category': category,
        'occurrences': occurrenceCount,
        'example': exampleMessage,
        'files': fileCount,
      };
}

/// A compact summary of one root cause candidate.
class RootCauseSummary {
  const RootCauseSummary({
    required this.title,
    required this.summary,
    required this.priority,
    required this.confidence,
    required this.occurrenceCount,
    required this.affectedFileCount,
    this.affectedFiles = const [],
    required this.relatedRules,
    required this.evidenceSummary,
  });

  final String title;
  final String summary;
  final String priority;
  final String confidence;
  final int occurrenceCount;
  final int affectedFileCount;
  final List<String> affectedFiles;
  final List<String> relatedRules;
  final List<String> evidenceSummary;

  Map<String, Object> toMap() => {
        'title': title,
        'summary': summary,
        'priority': priority,
        'confidence': confidence,
        'occurrences': occurrenceCount,
        'affected_files': affectedFileCount,
        'related_rules': relatedRules,
        'evidence': evidenceSummary,
      };
}

/// Compact structured context ready for a future AI provider.
///
/// Contains environment info, analyzer summary, top issues by priority,
/// and root cause candidates. Does NOT contain raw diagnostics.
class AiContext {
  const AiContext({
    required this.projectInfo,
    required this.environmentInfo,
    required this.androidInfo,
    required this.analyzerSummary,
    required this.topCritical,
    required this.topHigh,
    required this.topMedium,
    required this.rootCauses,
  });

  /// Project-level metadata (Flutter, Dart, channel).
  final Map<String, String?> projectInfo;

  /// Host environment (Java, Android SDK).
  final Map<String, String?> environmentInfo;

  /// Android toolchain (AGP, Gradle, Kotlin, SDK levels).
  final Map<String, String?> androidInfo;

  /// Total, errors, warnings, infos — never the raw list.
  final Map<String, int> analyzerSummary;

  /// Top critical rule groups (max 5).
  final List<IssueSummary> topCritical;

  /// Top high-priority rule groups (max 5).
  final List<IssueSummary> topHigh;

  /// Top medium-priority rule groups (max 5).
  final List<IssueSummary> topMedium;

  /// Root cause candidates.
  final List<RootCauseSummary> rootCauses;

  /// Converts to a flat map — useful for JSON serialization to an AI provider.
  Map<String, Object?> toMap() => {
        'project': projectInfo,
        'environment': environmentInfo,
        'android': androidInfo,
        'analyzer': analyzerSummary,
        'top_critical': topCritical.map((e) => e.toMap()).toList(),
        'top_high': topHigh.map((e) => e.toMap()).toList(),
        'top_medium': topMedium.map((e) => e.toMap()).toList(),
        'root_causes': rootCauses.map((e) => e.toMap()).toList(),
      };
}
