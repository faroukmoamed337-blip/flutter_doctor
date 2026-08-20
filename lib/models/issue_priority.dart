// Issue priority levels for the deterministic Issue Intelligence layer.
// Priority defines how urgently a developer should address a given analyzer rule.

enum IssuePriority {
  critical,
  high,
  medium,
  low,
  info,
  unknown;

  /// Numeric sort order — lower = higher urgency.
  int get sortOrder => switch (this) {
        IssuePriority.critical => 0,
        IssuePriority.high => 1,
        IssuePriority.medium => 2,
        IssuePriority.low => 3,
        IssuePriority.info => 4,
        IssuePriority.unknown => 5,
      };

  /// Display label with emoji and name.
  String get label => switch (this) {
        IssuePriority.critical => '🔴 CRITICAL',
        IssuePriority.high => '🟠 HIGH',
        IssuePriority.medium => '🟡 MEDIUM',
        IssuePriority.low => '🔵 LOW',
        IssuePriority.info => '⚪ INFO',
        IssuePriority.unknown => '⚪ UNKNOWN',
      };

  /// Short emoji only.
  String get emoji => switch (this) {
        IssuePriority.critical => '🔴',
        IssuePriority.high => '🟠',
        IssuePriority.medium => '🟡',
        IssuePriority.low => '🔵',
        IssuePriority.info => '⚪',
        IssuePriority.unknown => '⚪',
      };

  /// Human-readable name for display.
  String get displayName => switch (this) {
        IssuePriority.critical => 'Critical',
        IssuePriority.high => 'High',
        IssuePriority.medium => 'Medium',
        IssuePriority.low => 'Low',
        IssuePriority.info => 'Info',
        IssuePriority.unknown => 'Unknown',
      };

  /// Parses a string into an [IssuePriority].
  /// Throws [FormatException] if [val] is not a valid priority string.
  static IssuePriority parse(String val) {
    return switch (val.trim().toLowerCase()) {
      'critical' => IssuePriority.critical,
      'high' => IssuePriority.high,
      'medium' => IssuePriority.medium,
      'low' => IssuePriority.low,
      'info' => IssuePriority.info,
      'unknown' => IssuePriority.unknown,
      _ => throw FormatException('Invalid IssuePriority value: "$val"'),
    };
  }
}
