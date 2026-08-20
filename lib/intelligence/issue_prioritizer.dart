import '../flutter_doctor.dart';
import '../models/issue_priority.dart';
import '../models/issue_category.dart';
import 'rule_registry.dart';

/// An enriched, prioritized view of a group of analyzer issues sharing
/// the same rule identifier.
///
/// This is read-only — it never modifies the underlying [FlutterIssue] objects.
class PrioritizedGroup {
  const PrioritizedGroup({
    required this.rule,
    required this.occurrenceCount,
    required this.priority,
    required this.category,
    required this.description,
    required this.exampleMessage,
    required this.affectedFiles,
  });

  /// The analyzer rule identifier (e.g. 'undefined_method').
  final String rule;

  /// Total number of individual issues with this rule.
  final int occurrenceCount;

  /// Severity classification from [RuleRegistry].
  final IssuePriority priority;

  /// Nature of the problem from [RuleRegistry].
  final IssueCategory category;

  /// Developer-facing description from [RuleRegistry].
  /// Empty string if the rule is not registered.
  final String description;

  /// The message from the first occurrence — used as a concrete example.
  final String exampleMessage;

  /// Unique file paths where this rule was triggered.
  final List<String> affectedFiles;
}

/// Applies [RuleRegistry] metadata to a [FlutterAnalysisResult] to produce
/// a prioritized, sorted list of [PrioritizedGroup] objects.
///
/// Responsibilities:
///   - Groups all issues by rule (across all severities).
///   - Looks up metadata in [RuleRegistry].
///   - Sorts by [IssuePriority.sortOrder] first, then occurrence count descending.
///   - Does NOT modify the parsed [FlutterAnalysisResult] or any [FlutterIssue].
class IssuePrioritizer {
  const IssuePrioritizer();

  /// Returns a sorted list of [PrioritizedGroup] for all rules found in [result].
  List<PrioritizedGroup> prioritize(FlutterAnalysisResult result) {
    // Group all issues by rule (across all severities).
    final map = <String, List<FlutterIssue>>{};
    for (final issue in result.allIssues) {
      map.putIfAbsent(issue.rule, () => []).add(issue);
    }

    final groups = map.entries.map((entry) {
      final rule = entry.key;
      final issues = entry.value;
      final meta = RuleRegistry.lookup(rule);
      final files = issues
          .map((i) => i.file.replaceAll('\\', '/'))
          .toSet()
          .toList()
        ..sort();
      return PrioritizedGroup(
        rule: rule,
        occurrenceCount: issues.length,
        priority: meta?.priority ?? IssuePriority.unknown,
        category: meta?.category ?? IssueCategory.unknown,
        description: meta?.description ?? '',
        exampleMessage: issues.first.message,
        affectedFiles: files,
      );
    }).toList();

    // Sort: priority first (lower sortOrder = higher urgency), then count desc.
    groups.sort((a, b) {
      final byPriority = a.priority.sortOrder.compareTo(b.priority.sortOrder);
      if (byPriority != 0) return byPriority;
      return b.occurrenceCount.compareTo(a.occurrenceCount);
    });

    return groups;
  }

  /// Returns a map of priority → total occurrence count (sum of all issues
  /// whose rule maps to that priority).
  Map<IssuePriority, int> countByPriority(List<PrioritizedGroup> groups) {
    final counts = <IssuePriority, int>{};
    for (final g in groups) {
      counts[g.priority] = (counts[g.priority] ?? 0) + g.occurrenceCount;
    }
    return counts;
  }

  /// Returns the top [limit] rules from the sorted list (default 10).
  /// Ordering already respects priority-before-count.
  List<PrioritizedGroup> topProblems(
    List<PrioritizedGroup> sorted, {
    int limit = 10,
  }) =>
      sorted.take(limit).toList();
}
