// Issue category for the deterministic Issue Intelligence layer.
// Category describes the nature of the problem an analyzer rule represents.

enum IssueCategory {
  correctness,
  runtimeSafety,
  compatibility,
  deprecatedApi,
  performance,
  maintainability,
  style,
  codeQuality,
  unknown;

  /// Human-readable display name.
  String get label => switch (this) {
        IssueCategory.correctness => 'Correctness',
        IssueCategory.runtimeSafety => 'Runtime Safety',
        IssueCategory.compatibility => 'Compatibility',
        IssueCategory.deprecatedApi => 'Deprecated API',
        IssueCategory.performance => 'Performance',
        IssueCategory.maintainability => 'Maintainability',
        IssueCategory.style => 'Style',
        IssueCategory.codeQuality => 'Code Quality',
        IssueCategory.unknown => 'Unknown',
      };
}
