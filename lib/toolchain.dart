// ignore_for_file: prefer_interpolation_to_compose_strings, curly_braces_in_flow_control_structures

import 'dart:convert';
import 'dart:io';

class EnvironmentInfo {
  const EnvironmentInfo(
      {this.flutterVersion,
      this.dartVersion,
      this.flutterChannel,
      this.javaVersion,
      this.javaHome,
      this.androidSdkPath});
  final String? flutterVersion,
      dartVersion,
      flutterChannel,
      javaVersion,
      javaHome,
      androidSdkPath;
}

class AndroidToolchainInfo {
  const AndroidToolchainInfo(
      {this.gradleVersion,
      this.agpVersion,
      this.kotlinVersion,
      this.compileSdk,
      this.targetSdk,
      this.minSdk});
  final String? gradleVersion, agpVersion, kotlinVersion;
  final int? compileSdk, targetSdk, minSdk;
}

class EnvironmentAnalyzer {
  EnvironmentInfo analyze() {
    String? flutter, dart, channel, java;
    try {
      final p = Process.runSync(
          Platform.isWindows ? 'cmd.exe' : 'flutter',
          Platform.isWindows
              ? ['/c', 'flutter', '--version', '--machine']
              : ['--version', '--machine']);
      final data = jsonDecode(p.stdout.toString()) as Map<String, dynamic>;
      flutter = data['flutterVersion']?.toString();
      dart = data['dartSdkVersion']?.toString();
      channel = data['channel']?.toString();
    } catch (_) {}
    try {
      final p = Process.runSync(Platform.isWindows ? 'cmd.exe' : 'java',
          Platform.isWindows ? ['/c', 'java', '-version'] : ['-version']);
      final match = RegExp(r'(?:version|openjdk)\s+"?([0-9][^"\s]*)')
          .firstMatch(p.stderr.toString() + '\n' + p.stdout.toString());
      java = match?.group(1);
    } catch (_) {}
    return EnvironmentInfo(
        flutterVersion: flutter,
        dartVersion: dart,
        flutterChannel: channel,
        javaVersion: java,
        javaHome: Platform.environment['JAVA_HOME'],
        androidSdkPath: Platform.environment['ANDROID_SDK_ROOT'] ??
            Platform.environment['ANDROID_HOME']);
  }
}

class AndroidToolchainAnalyzer {
  AndroidToolchainInfo analyze(String projectPath) {
    final android = Directory(projectPath + Platform.pathSeparator + 'android');
    if (!android.existsSync()) return const AndroidToolchainInfo();
    String all = '';
    for (final name in [
      'build.gradle',
      'build.gradle.kts',
      'settings.gradle',
      'settings.gradle.kts',
      'app/build.gradle',
      'app/build.gradle.kts'
    ]) {
      final f = File(android.path + Platform.pathSeparator + name);
      if (f.existsSync()) all += '\n' + f.readAsStringSync();
    }
    final wrapper = File(android.path +
        Platform.pathSeparator +
        'gradle' +
        Platform.pathSeparator +
        'wrapper' +
        Platform.pathSeparator +
        'gradle-wrapper.properties');
    final wrapperText = wrapper.existsSync() ? wrapper.readAsStringSync() : '';
    String? find(String pattern) =>
        RegExp(pattern, caseSensitive: false, multiLine: true)
            .firstMatch(all)
            ?.group(1);
    int? number(String pattern) => int.tryParse(find(pattern) ?? '');
    return AndroidToolchainInfo(
      gradleVersion: RegExp(r'gradle-([0-9.]+)-(?:bin|all)')
          .firstMatch(wrapperText)
          ?.group(1),
      agpVersion: find(r'com\.android\.tools\.build:gradle:([0-9.]+)') ??
          find(
              r'id\s*[\(\s]*["\x27]com\.android\.(?:application|library)["\x27][\)\s]*version\s*["\x27]([0-9.]+)'),
      kotlinVersion: find(r'kotlin_version\s*=\s*["\x27]([0-9.]+)') ??
          find(
              r'org\.jetbrains\.kotlin(?:\.android)?["\x27][\)\s]*version\s*["\x27]([0-9.]+)'),
      compileSdk: number(r'compileSdk(?:Version)?\s*(?:=\s*)?([0-9]+)'),
      targetSdk: number(r'targetSdk(?:Version)?\s*(?:=\s*)?([0-9]+)'),
      minSdk: number(r'minSdk(?:Version)?\s*(?:=\s*)?([0-9]+)'),
    );
  }
}

class Compatibility {
  const Compatibility(this.status, this.message);
  final String status, message;
}

Compatibility agpGradleCompatibility(String? agp, String? gradle) {
  if (agp == null || gradle == null)
    return const Compatibility(
        'UNKNOWN', 'Compatibility could not be verified automatically.');
  final rules = <String, String>{
    '9.2': '9.4.1',
    '9.1': '9.3.1',
    '9.0': '9.1.0',
    '8.13': '8.13',
    '8.12': '8.13',
    '8.11': '8.13',
    '8.10': '8.11.1',
    '8.9': '8.11.1',
    '8.8': '8.10.2',
    '8.7': '8.9',
    '8.6': '8.7',
    '8.5': '8.7',
    '8.4': '8.6',
    '8.3': '8.4',
    '8.2': '8.2',
    '8.1': '8.0',
    '8.0': '8.0',
    '7.4': '7.5',
    '7.3': '7.4',
    '7.2': '7.3.3',
    '7.1': '7.2',
    '7.0': '7.0'
  };
  final parts = agp.split('.');
  final key = parts.length > 1 ? parts[0] + '.' + parts[1] : agp;
  final required = rules[key];
  if (required == null)
    return const Compatibility(
        'UNKNOWN', 'Compatibility could not be verified automatically.');
  return _compare(gradle, required) >= 0
      ? const Compatibility('PASS', 'Compatible')
      : Compatibility('ERROR', 'Required: Gradle >= ' + required);
}

int _compare(String a, String b) {
  final x = a.split('.').map(int.tryParse).toList(),
      y = b.split('.').map(int.tryParse).toList();
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] ?? 0 : 0) - (i < y.length ? y[i] ?? 0 : 0);
    if (d != 0) return d;
  }
  return 0;
}

void reportToolchain(EnvironmentInfo e, AndroidToolchainInfo a) {
  String v(Object? x) => x?.toString() ?? 'UNKNOWN';
  print('');
  print('================================');
  print('       Android Toolchain');
  print('================================');
  print('');
  print('Flutter: ' + v(e.flutterVersion));
  print('Dart: ' + v(e.dartVersion));
  print('Channel: ' + v(e.flutterChannel));
  print('Java: ' + v(e.javaVersion));
  print('JAVA_HOME: ' + v(e.javaHome));
  print('Android SDK: ' + v(e.androidSdkPath));
  print('AGP: ' + v(a.agpVersion));
  print('Gradle: ' + v(a.gradleVersion));
  print('Kotlin: ' + v(a.kotlinVersion));
  print('compileSdk: ' + v(a.compileSdk));
  print('targetSdk: ' + v(a.targetSdk));
  print('minSdk: ' + v(a.minSdk));
  final agp = agpGradleCompatibility(a.agpVersion, a.gradleVersion);
  print('');
  print('--------------------------------');
  print('       Compatibility');
  print('--------------------------------');
  print('');
  print((agp.status == 'PASS'
          ? '🟢 '
          : agp.status == 'ERROR'
              ? '🔴 '
              : '⚠️ ') +
      'AGP / Gradle');
  print(agp.message);
  print('');
  print('⚠️ Java / Gradle');
  print('Compatibility could not be verified automatically.');
  print('');
  print('⚠️ compileSdk / AGP');
  print('Compatibility could not be verified automatically.');
}

enum EvidenceSeverity { error, warning, info, unknown }

class CompatibilitySuggestion {
  const CompatibilitySuggestion(this.title, this.severity, this.message,
      this.source, this.component, this.recommendation);
  final String title, message, source, component, recommendation;
  final EvidenceSeverity severity;
}

class ProjectEvidence {
  const ProjectEvidence(this.environment, this.android, this.javaExecutable,
      this.minSdkSource, this.suggestions);
  final EnvironmentInfo environment;
  final AndroidToolchainInfo android;
  final String? javaExecutable, minSdkSource;
  final List<CompatibilitySuggestion> suggestions;
}

ProjectEvidence buildEvidence(String path) {
  final base = EnvironmentAnalyzer().analyze();
  String? javaPath, sdk = base.androidSdkPath;
  try {
    final p = Process.runSync(Platform.isWindows ? 'cmd.exe' : 'which',
        Platform.isWindows ? ['/c', 'where', 'java'] : ['java']);
    if (p.exitCode == 0)
      javaPath = p.stdout
          .toString()
          .split(RegExp(r'\\r?\\n'))
          .firstWhere((x) => x.trim().isNotEmpty, orElse: () => '')
          .trim();
  } catch (_) {}
  try {
    final p = Process.runSync(
        Platform.isWindows ? 'cmd.exe' : 'flutter',
        Platform.isWindows
            ? ['/c', 'flutter', 'doctor', '-v']
            : ['doctor', '-v']);
    final doctor = p.stdout.toString() + '\\n' + p.stderr.toString();
    sdk ??= RegExp(r'Android SDK at (.+)', caseSensitive: false)
        .firstMatch(doctor)
        ?.group(1)
        ?.trim();
  } catch (_) {}
  final env = EnvironmentInfo(
      flutterVersion: base.flutterVersion,
      dartVersion: base.dartVersion,
      flutterChannel: base.flutterChannel,
      javaVersion: base.javaVersion,
      javaHome: base.javaHome,
      androidSdkPath: sdk);
  final android = AndroidToolchainAnalyzer().analyze(path);
  final source = _minSource(path);
  return ProjectEvidence(env, android, javaPath, source, const []);
}

String? _minSource(String path) {
  for (final name in [
    'android/app/build.gradle',
    'android/app/build.gradle.kts'
  ]) {
    final f = File(path + Platform.pathSeparator + name);
    if (f.existsSync()) {
      final t = f.readAsStringSync();
      if (RegExp(r'minSdkVersion\\s+flutter\\.minSdkVersion').hasMatch(t))
        return 'flutter.minSdkVersion';
      if (RegExp(r'minSdk(?:Version)?\\s*(?:=\\s*)?[0-9]+').hasMatch(t))
        return 'Gradle';
    }
  }
  return null;
}

List<CompatibilitySuggestion> parseSuggestions(String output) {
  final result = <CompatibilitySuggestion>[];
  for (final line in output.split(RegExp(r'\\r?\\n'))) {
    if (RegExp(r'(incompatible|requires|recommend)', caseSensitive: false)
        .hasMatch(line)) {
      result.add(CompatibilitySuggestion(
          'Flutter suggestion',
          EvidenceSeverity.info,
          line.trim(),
          'flutter analyze --suggestions',
          'Android toolchain',
          'Review Flutter recommendation.'));
    }
  }
  return result;
}

void reportEvidence(ProjectEvidence e) {
  String v(Object? x) => x?.toString() ?? 'UNKNOWN';
  print('');
  print('================================');
  print('        Environment');
  print('================================');
  print('');
  print('Flutter: ' + v(e.environment.flutterVersion));
  print('Dart: ' + v(e.environment.dartVersion));
  print('Channel: ' + v(e.environment.flutterChannel));
  print('Java: ' + v(e.environment.javaVersion));
  print('Java executable: ' + v(e.javaExecutable));
  print('JAVA_HOME: ' + (e.environment.javaHome ?? '⚠️ NOT SET'));
  print('Android SDK: ' + v(e.environment.androidSdkPath));
  print('ANDROID_SDK_ROOT: ' +
      (Platform.environment['ANDROID_SDK_ROOT'] ?? '⚠️ NOT SET'));
  print('ANDROID_HOME: ' +
      (Platform.environment['ANDROID_HOME'] ?? '⚠️ NOT SET'));
  print('');
  print('================================');
  print('       Android Toolchain');
  print('================================');
  print('');
  final a = e.android;
  print('AGP: ' + v(a.agpVersion));
  print('Gradle: ' + v(a.gradleVersion));
  print('Kotlin: ' + v(a.kotlinVersion));
  print('compileSdk: ' + v(a.compileSdk));
  print('targetSdk: ' + v(a.targetSdk));
  print('minSdk: ' + v(a.minSdk));
  if (e.minSdkSource != null) print('Source: ' + e.minSdkSource!);
  final c = agpGradleCompatibility(a.agpVersion, a.gradleVersion);
  print('');
  print('================================');
  print('      Compatibility');
  print('================================');
  print('');
  print((c.status == 'PASS'
          ? '🟢 '
          : c.status == 'ERROR'
              ? '🔴 '
              : '⚪ ') +
      'AGP / Gradle');
  print(c.message);
  print('⚪ Java / Gradle');
  print('Unknown');
  print('⚪ compileSdk / AGP');
  print('Unknown');
}
