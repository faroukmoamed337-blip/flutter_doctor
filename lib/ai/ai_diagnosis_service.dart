// ignore_for_file: prefer_interpolation_to_compose_strings

import '../models/ai_context.dart';
import '../models/ai_diagnosis.dart';
import 'ai_context_budgeter.dart';
import 'ai_diagnosis_validator.dart';
import 'ai_evidence_consistency_validator.dart';
import 'ai_prompt_builder.dart';
import 'ai_provider.dart';
import 'ai_provider_factory.dart';

/// Orchestrates AI Diagnosis execution.
///
/// Accepts an [AiContext], applies deterministic budget capping, sends the context
/// through the configured [AiProvider], validates schema, runs consistency validation
/// against deterministic evidence, and returns an [AiDiagnosisResult].
///
/// Design guarantees:
/// - Never crashes the application — all provider/parsing errors produce safe fallbacks.
/// - Does not modify target project code.
/// - Does not send raw diagnostic lists or source files to provider.
class AiDiagnosisService {
  const AiDiagnosisService({
    this.promptBuilder = const AiPromptBuilder(),
    this.validator = const AiDiagnosisValidator(),
    this.consistencyValidator = const AiEvidenceConsistencyValidator(),
    this.budgeter = const AiContextBudgeter(),
  });

  final AiPromptBuilder promptBuilder;
  final AiDiagnosisValidator validator;
  final AiEvidenceConsistencyValidator consistencyValidator;
  final AiContextBudgeter budgeter;

  /// Executes AI diagnosis for [context].
  ///
  /// If [provider] is not supplied, resolves one from host environment settings.
  Future<AiDiagnosisResult> diagnose({
    required AiContext context,
    AiProvider? provider,
  }) async {
    final activeProvider = provider ?? AiProviderFactory.fromEnvironment();

    if (activeProvider is NoAiProvider) {
      return AiDiagnosisResult.unavailable('No AI provider configured.');
    }

    try {
      // 1. Apply budget to ensure context is compact
      final budgetedContext = budgeter.applyBudget(context);

      // 2. Query provider
      final response = await activeProvider.analyze(budgetedContext).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('AI provider timed out after 30 seconds.');
        },
      );

      // 3. Schema validation & initial parse
      final rawDiagnosis =
          validator.validate(response.content, budgetedContext);

      // 4. Consistency validation against deterministic facts
      final validatedDiagnosis =
          consistencyValidator.validate(rawDiagnosis, budgetedContext);

      return AiDiagnosisResult.success(validatedDiagnosis);
    } on FormatException catch (e) {
      return AiDiagnosisResult.unavailable(
          'Invalid AI response schema: ' + e.message);
    } catch (e) {
      return AiDiagnosisResult.unavailable('AI provider error: ' +
          e.toString().replaceAll(RegExp(r'Exception:\s*'), ''));
    }
  }
}
