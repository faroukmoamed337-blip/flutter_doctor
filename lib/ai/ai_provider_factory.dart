import 'dart:io';
import 'ai_provider.dart';

/// Factory for configuring an [AiProvider] from host environment settings.
///
/// Looks for `FLUTTER_DOCTOR_AI_PROVIDER` and `FLUTTER_DOCTOR_AI_API_KEY`.
/// If non-configured or empty, returns [NoAiProvider].
class AiProviderFactory {
  const AiProviderFactory();

  /// Resolves the provider from environment variables.
  static AiProvider fromEnvironment({
    Map<String, String>? env,
  }) {
    final environment = env ?? Platform.environment;
    final providerName = environment['FLUTTER_DOCTOR_AI_PROVIDER'];
    final apiKey = environment['FLUTTER_DOCTOR_AI_API_KEY'];

    if (providerName == null ||
        providerName.isEmpty ||
        apiKey == null ||
        apiKey.isEmpty) {
      return const NoAiProvider();
    }

    // Future concrete providers (Gemini, OpenAI, Anthropic, Local LLM) can be registered here.
    // For now, if specified but unsupported, return NoAiProvider to ensure CLI never crashes.
    return const NoAiProvider();
  }
}
