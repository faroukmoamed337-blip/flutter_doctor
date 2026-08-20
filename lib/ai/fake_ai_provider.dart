import '../models/ai_context.dart';
import 'ai_provider.dart';

/// Fake AI provider used for automated testing.
///
/// Returns pre-configured JSON responses without calling external network APIs.
class FakeAiProvider implements AiProvider {
  FakeAiProvider({
    this.responseToReturn = '',
    this.shouldThrow = false,
    this.name = 'Fake AI Provider',
  });

  final String responseToReturn;
  final bool shouldThrow;

  @override
  final String name;

  /// Holds the last context passed to [analyze] for assertion in tests.
  AiContext? lastContext;

  @override
  Future<AiResponse> analyze(AiContext context) async {
    lastContext = context;
    if (shouldThrow) {
      throw Exception('Fake AI Provider simulated network failure');
    }
    return AiResponse(content: responseToReturn);
  }
}
