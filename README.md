# Flutter Doctor

A CLI tool to analyze Flutter project health, evaluate toolchain compatibility, prioritize analyzer issues, and perform deterministic root cause analysis.

> **Note**: Version 0.1.0 is a 100% deterministic, offline analysis tool. It operates completely locally with zero network access and does not require AI models or API keys.

---

## Features

- **Project Detection & Dependency Inspection**: Validates Flutter project structure and inspects direct and development dependencies.
- **Environment & Toolchain Discovery**: Detects Flutter SDK, Dart SDK, Java version, `JAVA_HOME`, Android SDK, AGP, Gradle, Kotlin, `compileSdk`, `targetSdk`, and `minSdk`.
- **Toolchain Compatibility Matrix**: Evaluates AGP and Gradle version compatibility deterministically to highlight version mismatches before build failures occur.
- **Analyzer Integration & Aggregation**: Aggregates `flutter analyze` diagnostic output into structured severity counts (Errors, Warnings, Infos) and health status metrics.
- **Issue Prioritization**: Categorizes analyzer rules into structured priority tiers (**CRITICAL**, **HIGH**, **MEDIUM**, **LOW**, **UNKNOWN**) based on issue severity and runtime risk.
- **Deterministic Root Cause Analysis**: Clusters related analyzer issues and environment evidence to report actionable root cause candidates.

---

## Installation

Activate the package globally from pub.dev using the Dart SDK:

```bash
dart pub global activate flutter_doctor
```

---

## Usage

Run `flutter_doctor` by passing the directory path of your target Flutter project:

```bash
flutter_doctor --path "D:\APPS\my_app"
```

If no `--path` argument is supplied, `flutter_doctor` analyzes the current working directory:

```bash
flutter_doctor
```

---

## Report Sections

When executed, `flutter_doctor` outputs a structured diagnostic report containing six key sections:

1. **Environment**: Summary of detected Flutter SDK, Dart SDK, release channel, Java runtime, `JAVA_HOME`, and Android SDK paths.
2. **Android Toolchain**: Inspection of AGP (Android Gradle Plugin), Gradle, Kotlin, `compileSdk`, `targetSdk`, and `minSdk` configurations.
3. **Compatibility**: Automated matrix evaluation of AGP/Gradle compatibility status (`PASS`, `ERROR`, or `UNKNOWN`).
4. **Flutter Analyze**: Diagnostic totals (Errors, Warnings, Infos), overall health status (**CRITICAL**, **NEEDS ATTENTION**, or **HEALTHY**), and top rule occurrences.
5. **Issue Prioritization**: Classification of analyzer issues ordered by priority tier with occurrence counts and affected files.
6. **Root Causes**: Proven root cause candidates with confidence ratings, related rules, supporting evidence, and summary explanations.

---

## License

MIT License. See [LICENSE](LICENSE) for details.
