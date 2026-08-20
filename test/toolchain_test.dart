import 'package:flutter_doctor/toolchain.dart';
import 'package:test/test.dart';

void main() {
  test('AGP Gradle rule', () {
    expect(agpGradleCompatibility('8.5.0', '8.6').status, 'ERROR');
    expect(agpGradleCompatibility('8.5.0', '8.7').status, 'PASS');
    expect(agpGradleCompatibility(null, '8.7').status, 'UNKNOWN');
  });
  test('gradle parsing Groovy and Kotlin', () {
    final a = AndroidToolchainAnalyzer();
    expect(a, isNotNull);
  });
}
