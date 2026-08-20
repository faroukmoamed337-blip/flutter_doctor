import 'issue_priority.dart';
import 'issue_category.dart';
import 'evidence_item.dart';

/// How strongly the deterministic engine can assert a root cause.
/// Only [high] is used when evidence is unambiguous and multi-sourced.
/// [unknown] is used when evidence exists but is insufficient to conclude.
enum RootCauseConfidence {
  high,
  medium,
  low,
  unknown;

  String get label => switch (this) {
        RootCauseConfidence.high => 'HIGH',
        RootCauseConfidence.medium => 'MEDIUM',
        RootCauseConfidence.low => 'LOW',
        RootCauseConfidence.unknown => 'UNKNOWN',
      };

  /// Parses a string into a [RootCauseConfidence].
  /// Throws [FormatException] if [val] is not a valid confidence string.
  static RootCauseConfidence parse(String val) {
    return switch (val.trim().toLowerCase()) {
      'high' => RootCauseConfidence.high,
      'medium' => RootCauseConfidence.medium,
      'low' => RootCauseConfidence.low,
      'unknown' => RootCauseConfidence.unknown,
      _ => throw FormatException('Invalid RootCauseConfidence value: "$val"'),
    };
  }
}

/// A possible root cause derived from deterministic evidence.
///
/// Root causes are NOT AI-generated. They are computed by the deterministic
/// [RootCauseEngine] from structured evidence.
///
/// Design invariants:
/// - [occurrenceCount] must equal the sum of individual issues belonging to
///   this candidate. One issue MUST NOT be counted in multiple candidates.
/// - [confidence] is set only as high as the evidence supports.
/// - [summary] must describe only what the evidence actually shows.
class RootCauseCandidate {
  const RootCauseCandidate({
    required this.title,
    required this.summary,
    required this.priority,
    required this.category,
    required this.confidence,
    required this.evidence,
    required this.relatedRules,
    required this.affectedFiles,
    required this.occurrenceCount,
  });

  /// Short, developer-facing description of the root cause.
  final String title;

  /// A longer explanation of what the evidence shows.
  /// MUST NOT claim causes that are not proven by the evidence.
  final String summary;

  /// Inherited from the highest-severity related analyzer rule.
  final IssuePriority priority;

  /// The nature of the root cause.
  final IssueCategory category;

  /// How strongly the evidence supports this candidate.
  final RootCauseConfidence confidence;

  /// All evidence items that support this candidate.
  final List<EvidenceItem> evidence;

  /// Analyzer rule identifiers contributing to this candidate.
  final List<String> relatedRules;

  /// Unique file paths where related issues were detected.
  final List<String> affectedFiles;

  /// Total count of individual analyzer issues attributed to this candidate.
  /// Must not double-count issues.
  final int occurrenceCount;
}
