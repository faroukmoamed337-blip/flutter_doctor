// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:convert';
import '../models/ai_context.dart';
import '../models/ai_diagnosis.dart';
import '../models/issue_priority.dart';
import '../models/root_cause.dart';

/// Validates and parses raw AI JSON output against [AiContext] evidence.
///
/// Design rules:
/// 1. Output must be valid JSON matching expected schema.
/// 2. Enums are validated strictly — invalid enum strings throw [FormatException].
/// 3. Hallucinated files (not present in [context] evidence) are filtered out.
/// 4. Hallucinated analyzer rules in evidence strings are rejected/flagged.
class AiDiagnosisValidator {
  const AiDiagnosisValidator();

  /// Parses raw [jsonContent] and validates it against [context].
  ///
  /// Throws [FormatException] if JSON is malformed or invalid.
  AiDiagnosis validate(String jsonContent, AiContext context) {
    if (jsonContent.trim().isEmpty) {
      throw const FormatException('AI response was empty.');
    }

    // Extract JSON block if surrounded by markdown code fences.
    String cleaned = jsonContent.trim();
    if (cleaned.startsWith('```')) {
      final lines = cleaned.split('\n');
      if (lines.first.startsWith('```')) lines.removeAt(0);
      if (lines.isNotEmpty && lines.last.startsWith('```')) lines.removeLast();
      cleaned = lines.join('\n').trim();
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(cleaned);
    } catch (e) {
      throw FormatException('Failed to parse AI JSON response: $e');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('AI response root must be a JSON object.');
    }

    final map = decoded;

    // Validate required top-level fields
    final summary = map['summary']?.toString();
    final healthAssessment = map['health_assessment']?.toString();
    final envAssessment = map['environment_assessment']?.toString();
    final confidenceStr = map['confidence']?.toString();

    if (summary == null ||
        healthAssessment == null ||
        envAssessment == null ||
        confidenceStr == null) {
      throw const FormatException(
          'Missing required top-level fields in AI JSON response.');
    }

    // Strict enum parsing for overall confidence
    final overallConfidence = RootCauseConfidence.parse(confidenceStr);

    // Build set of allowed file paths from context
    final allowedFiles = _extractAllowedFiles(context);

    // Build set of allowed rules from context
    final allowedRules = _extractAllowedRules(context);

    int accepted = 0;
    int rejected = 0;
    int unsupported = 0;

    // Parse root causes
    final rawRootCauses = map['root_causes'];
    if (rawRootCauses is! List) {
      throw const FormatException('root_causes must be a JSON list.');
    }

    final rootCauses = <RootCauseDiagnosis>[];
    for (final item in rawRootCauses) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Root cause entry must be a JSON object.');
      }

      final title = item['title']?.toString() ?? 'Untitled';
      final explanation = item['explanation']?.toString() ?? '';
      final prioStr = item['priority']?.toString() ?? '';
      final confStr = item['confidence']?.toString() ??
          item['ai_confidence']?.toString() ??
          '';

      // Strict enum validation — throws FormatException if invalid
      final priority = IssuePriority.parse(prioStr);
      final aiConfidence = RootCauseConfidence.parse(confStr);

      final rawEvidence = item['evidence'] as List? ?? [];
      final evidence = <String>[];
      for (final e in rawEvidence) {
        final evStr = e.toString();
        if (_isEvidenceValid(evStr, allowedRules)) {
          evidence.add(evStr);
          accepted++;
        } else {
          rejected++;
        }
      }

      final rawActions = item['recommended_actions'] as List? ?? [];
      final actions = rawActions.map((a) => a.toString()).toList();

      final rawFiles = item['affected_files'] as List? ?? [];
      // Filter out hallucinated files not present in context evidence
      final affectedFiles = <String>[];
      for (final f in rawFiles) {
        final fStr = f.toString();
        final normPath = fStr.replaceAll('\\', '/');
        if (allowedFiles.contains(normPath)) {
          if (affectedFiles.length < 20) {
            affectedFiles.add(fStr);
          }
          accepted++;
        } else {
          rejected++;
        }
      }

      // Match deterministic confidence and occurrence count from context evidence
      RootCauseConfidence deterministicConf = RootCauseConfidence.unknown;
      int occurrenceCount =
          item['occurrence_count'] is int ? item['occurrence_count'] as int : 1;

      for (final rc in context.rootCauses) {
        if (title.toLowerCase().contains(rc.title.toLowerCase()) ||
            rc.title.toLowerCase().contains(title.toLowerCase())) {
          deterministicConf = RootCauseConfidence.parse(rc.confidence);
          if (item['occurrence_count'] == null) {
            occurrenceCount = rc.occurrenceCount;
          }
          break;
        }
      }

      accepted++;

      rootCauses.add(RootCauseDiagnosis(
        title: title,
        explanation: explanation,
        priority: priority,
        deterministicConfidence: deterministicConf,
        aiConfidence: aiConfidence,
        evidence: evidence,
        recommendedActions: actions,
        affectedFiles: affectedFiles,
        occurrenceCount: occurrenceCount,
      ));
    }

    // Parse recommendations
    final rawRecs = map['recommendations'];
    final recommendations = <Recommendation>[];
    if (rawRecs is List) {
      for (final item in rawRecs) {
        if (item is Map<String, dynamic>) {
          final title = item['title']?.toString() ?? '';
          final explanation = item['explanation']?.toString() ?? '';
          final prioStr = item['priority']?.toString() ?? '';
          final priority = IssuePriority.parse(prioStr);
          final relatedRc = item['related_root_cause']?.toString();

          accepted++;
          recommendations.add(Recommendation(
            title: title,
            explanation: explanation,
            priority: priority,
            relatedRootCause: relatedRc,
          ));
        }
      }
    }

    final verifiedFacts = <String, String>{};
    if (context.projectInfo['flutter'] != null) {
      verifiedFacts['Flutter'] = context.projectInfo['flutter']!;
    }
    if (context.projectInfo['dart'] != null) {
      verifiedFacts['Dart'] = context.projectInfo['dart']!;
    }
    if (context.environmentInfo['java'] != null) {
      verifiedFacts['Java'] = context.environmentInfo['java']!;
    }
    if (context.androidInfo['agp'] != null) {
      verifiedFacts['AGP'] = context.androidInfo['agp']!;
    }
    if (context.androidInfo['gradle'] != null) {
      verifiedFacts['Gradle'] = context.androidInfo['gradle']!;
    }
    if (context.androidInfo['kotlin'] != null) {
      verifiedFacts['Kotlin'] = context.androidInfo['kotlin']!;
    }
    verifiedFacts['Errors'] =
        context.analyzerSummary['errors']?.toString() ?? '0';
    verifiedFacts['Warnings'] =
        context.analyzerSummary['warnings']?.toString() ?? '0';
    verifiedFacts['Infos'] =
        context.analyzerSummary['infos']?.toString() ?? '0';
    verifiedFacts['Total Issues'] =
        context.analyzerSummary['total']?.toString() ?? '0';

    return AiDiagnosis(
      summary: summary,
      healthAssessment: healthAssessment,
      rootCauses: rootCauses,
      recommendations: recommendations,
      unsupportedRecommendations: const [],
      environmentAssessment: envAssessment,
      confidence: overallConfidence,
      verifiedFacts: verifiedFacts,
      claimsAcceptedCount: accepted,
      claimsRejectedCount: rejected,
      unsupportedClaimsCount: unsupported,
    );
  }

  Set<String> _extractAllowedFiles(AiContext context) {
    final files = <String>{};

    final pathPattern = RegExp(
      r'(?:^|\s)(lib[\\/][^\s:,]+(?:\.dart))',
    );

    for (final rc in context.rootCauses) {
      for (final f in rc.affectedFiles) {
        files.add(f.trim().replaceAll('\\', '/'));
      }

      for (final ev in rc.evidenceSummary) {
        final normalized = ev.replaceAll('\\', '/');

        for (final match in pathPattern.allMatches(normalized)) {
          final path = match.group(1);
          if (path != null) {
            files.add(path.trim());
          }
        }
      }
    }

    return files;
  }

  Set<String> _extractAllowedRules(AiContext context) {
    final rules = <String>{};
    for (final s in context.topCritical) {
      rules.add(s.rule);
    }
    for (final s in context.topHigh) {
      rules.add(s.rule);
    }
    for (final s in context.topMedium) {
      rules.add(s.rule);
    }
    for (final rc in context.rootCauses) {
      rules.addAll(rc.relatedRules);
    }
    return rules;
  }

  bool _isEvidenceValid(String evidenceStr, Set<String> allowedRules) {
    // If evidence mentions a specific rule, check if that rule was present in context
    if (evidenceStr.contains('rule:')) {
      final rule = evidenceStr.split('rule:').last.trim();
      if (!allowedRules.contains(rule)) return false;
    }
    return true;
  }
}
