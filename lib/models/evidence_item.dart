// Evidence items for the deterministic Root Cause Engine.
// Each item represents a single piece of observable, factual information
// derived from the analyzer output, toolchain, or project metadata.
// Evidence is never fabricated — unknown values are represented explicitly.

/// Where a piece of evidence came from.
enum EvidenceSource {
  flutterAnalyzer,
  pubspec,
  flutterVersion,
  dartVersion,
  java,
  gradle,
  agp,
  kotlin,
  compileSdk,
  targetSdk,
  minSdk,
  flutterDoctor,
  flutterAnalyzeSuggestions;

  String get label => switch (this) {
        EvidenceSource.flutterAnalyzer => 'Flutter Analyzer',
        EvidenceSource.pubspec => 'pubspec.yaml',
        EvidenceSource.flutterVersion => 'Flutter Version',
        EvidenceSource.dartVersion => 'Dart Version',
        EvidenceSource.java => 'Java',
        EvidenceSource.gradle => 'Gradle',
        EvidenceSource.agp => 'Android Gradle Plugin',
        EvidenceSource.kotlin => 'Kotlin',
        EvidenceSource.compileSdk => 'compileSdk',
        EvidenceSource.targetSdk => 'targetSdk',
        EvidenceSource.minSdk => 'minSdk',
        EvidenceSource.flutterDoctor => 'Flutter Doctor',
        EvidenceSource.flutterAnalyzeSuggestions =>
          'Flutter Analyze Suggestions',
      };
}

/// The semantic type of the evidence value.
enum EvidenceType {
  /// An analyzer rule identifier.
  rule,

  /// A count of occurrences.
  occurrence,

  /// A method, class, or identifier name.
  apiSymbol,

  /// A version string.
  version,

  /// A configuration value (SDK level, path, flag).
  config,

  /// A file path.
  filePath,

  /// General descriptive text.
  description,
}

/// How much the evidence can be trusted.
enum EvidenceReliability {
  /// Directly observed — can be considered fact.
  high,

  /// Derived from observation with minor uncertainty.
  medium,

  /// Inferred or partially observed.
  low,

  /// Reliability could not be determined.
  unknown;

  String get label => switch (this) {
        EvidenceReliability.high => 'High',
        EvidenceReliability.medium => 'Medium',
        EvidenceReliability.low => 'Low',
        EvidenceReliability.unknown => 'Unknown',
      };
}

/// A single observable, factual piece of evidence used by the Root Cause Engine.
///
/// Evidence is collected from the analyzer, toolchain, and project metadata.
/// It is NEVER fabricated — if something is unknown, the evidence item is
/// simply not created (or reliability is set to [EvidenceReliability.unknown]).
class EvidenceItem {
  const EvidenceItem({
    required this.source,
    required this.type,
    required this.value,
    this.location,
    required this.reliability,
  });

  /// Where this evidence came from.
  final EvidenceSource source;

  /// The semantic type of [value].
  final EvidenceType type;

  /// The raw observed value (e.g., "withValues", "3.27.1", "15 occurrences").
  final String value;

  /// An optional location hint (file path, line number, config file name).
  final String? location;

  /// How much this evidence can be trusted.
  final EvidenceReliability reliability;

  @override
  String toString() => '${source.label}: $value';
}
