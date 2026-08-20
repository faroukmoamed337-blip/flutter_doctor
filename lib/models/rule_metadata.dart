import '../models/issue_priority.dart';
import '../models/issue_category.dart';

/// Deterministic metadata for a single analyzer rule.
///
/// Instances are immutable and live only in [RuleRegistry].
/// Do not extend or modify at runtime — this is the source of truth
/// for the current classification. To reclassify a rule, update
/// [RuleRegistry] directly.
class RuleMetadata {
  const RuleMetadata({
    required this.rule,
    required this.priority,
    required this.category,
    required this.description,
  });

  /// The exact analyzer rule identifier (e.g. 'undefined_method').
  final String rule;

  /// How urgently the developer should address issues of this rule.
  final IssuePriority priority;

  /// The nature of the problem this rule represents.
  final IssueCategory category;

  /// A concise, developer-facing description of what the rule detects.
  final String description;

  @override
  String toString() =>
      'RuleMetadata($rule, ${priority.label}, ${category.label})';
}
