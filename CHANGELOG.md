# Changelog

## 0.1.1

- Improved AI evidence validation.
- Added deterministic file path validation.
- Prevented hallucinated file references from AI output.
- Improved AI evidence consistency checks.
- Improved dependency resolution diagnostics.
- Added package homepage and repository metadata.

## 0.1.0

Initial deterministic Flutter Doctor release.

- Flutter project detection and pubspec dependency inspection.
- Host environment detection (Flutter SDK, Dart SDK, Java version, JAVA_HOME, Android SDK).
- Android toolchain detection (AGP, Gradle, Kotlin, compileSdk, targetSdk, minSdk).
- Toolchain compatibility matrix evaluation and contradiction reporting.
- Flutter analyzer diagnostic aggregation and severity counts (Errors, Warnings, Infos).
- Severity-based health status determination.
- Priority-based issue classification (Critical, High, Medium, Low, Unknown).
- Deterministic root cause candidate analysis.