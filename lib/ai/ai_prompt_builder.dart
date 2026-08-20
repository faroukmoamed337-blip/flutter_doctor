// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:convert';
import '../models/ai_context.dart';

/// Dedicated prompt builder for AI Diagnosis.
///
/// Structures the compact [AiContext] into a strict prompt enforcing:
/// - FACT / INFERENCE / RECOMMENDATION distinction.
/// - Strict JSON output format matching expected schema.
/// - Anti-hallucination rules.
class AiPromptBuilder {
  const AiPromptBuilder();

  /// Builds a complete prompt string from [context].
  String buildPrompt(AiContext context) {
    final contextJson = jsonEncode(context.toMap());

    return '''
You are an expert Flutter engineer analyzing diagnostic evidence collected by Flutter Doctor.

INSTRUCTIONS:
1. Analyze ONLY the structured context provided below.
2. Output JSON ONLY matching the exact schema specified below. Do not include markdown text outside JSON blocks.
3. Distinguish between FACT (directly from analyzer/environment), INFERENCE (logical deduction from facts), and RECOMMENDATION (actionable advice).
4. Safety against hallucination:
   - Do NOT invent files, analyzer rules, package versions, or toolchain requirements.
   - Do NOT claim a compatibility problem unless the evidence supports it.
   - Do NOT assume a Flutter upgrade is required unless missing APIs or SDK bounds prove it.
   - Do NOT claim that an issue will definitely crash unless evidence proves it.
   - Every root cause diagnosis MUST reference at least one evidence item present in the context.
   - If evidence is insufficient, set confidence to "unknown" and state that additional evidence is required.

JSON SCHEMA:
{
  "summary": "High-level summary of analysis",
  "health_assessment": "Overall health assessment of the project",
  "root_causes": [
    {
      "title": "Short title",
      "explanation": "Detailed explanation traceable to evidence",
      "priority": "critical|high|medium|low|unknown",
      "confidence": "high|medium|low|unknown",
      "evidence": ["Evidence string from context"],
      "recommended_actions": ["Action item"],
      "affected_files": ["file path from context"]
    }
  ],
  "recommendations": [
    {
      "title": "Short recommendation title",
      "explanation": "Actionable explanation",
      "priority": "critical|high|medium|low|unknown",
      "related_root_cause": "Title of related root cause or null"
    }
  ],
  "environment_assessment": "Assessment of toolchain/environment evidence",
  "confidence": "high|medium|low|unknown"
}

DETERMINISTIC CONTEXT:
$contextJson
''';
  }
}
