import '../models/ai_context.dart';

/// The structured response from an AI provider.
class AiResponse {
  const AiResponse({
    required this.content,
    this.confidence,
    this.metadata,
  });

  /// The AI-generated text response.
  final String content;

  /// Optional confidence hint provided by the AI provider.
  final String? confidence;

  /// Optional provider-specific metadata (model name, token usage, etc.).
  final Map<String, dynamic>? metadata;
}

/// Abstract interface for a future AI provider.
///
/// The deterministic Flutter Doctor works fully WITHOUT an AI provider.
/// This interface exists purely as a design contract for Phase 10+.
///
/// Implementations MUST:
/// - Accept an [AiContext] (never raw source code or full diagnostics).
/// - Return a structured [AiResponse].
/// - Not modify the target Flutter project in any way.
/// - Not make assumptions beyond what [AiContext] contains.
///
/// Do NOT implement any concrete provider until Phase 10.
abstract class AiProvider {
  /// Human-readable name for this provider (e.g., 'Gemini', 'OpenAI GPT-4o').
  String get name;

  /// Sends the structured [AiContext] to the AI provider and returns a response.
  ///
  /// Throws [UnsupportedError] if the provider is a stub.
  Future<AiResponse> analyze(AiContext context);
}

/// A no-op provider used when no AI is configured.
/// Returns a message indicating that AI analysis is not available.
/// This allows the pipeline to run end-to-end without crashing.
class NoAiProvider implements AiProvider {
  const NoAiProvider();

  @override
  String get name => 'None (deterministic mode)';

  @override
  Future<AiResponse> analyze(AiContext context) async {
    return const AiResponse(
      content: 'No AI provider configured. The deterministic analysis above '
          'is the complete output.',
      confidence: null,
    );
  }
}
