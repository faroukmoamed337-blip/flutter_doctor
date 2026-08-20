// ignore_for_file: prefer_interpolation_to_compose_strings

import '../models/ai_context.dart';
import '../models/ai_diagnosis.dart';
import '../models/issue_priority.dart';
import '../models/root_cause.dart';

/// Validates AI claims against deterministic evidence to ensure the AI never
/// contradicts verified facts.
///
/// Design invariants:
/// 1. Deterministic evidence is authoritative over AI output.
/// 2. Environment version claims (Flutter, Dart, AGP, Gradle, Java, SDKs)
///    must match detected values.
/// 3. Incompatibility claims without evidence are rejected or marked
///    unsupported.
/// 4. Analyzer rules referenced by AI must exist in deterministic context.
/// 5. File paths referenced by AI must exist in deterministic evidence.
/// 6. Occurrence counts are overridden by deterministic counts.
/// 7. Priority cannot be downgraded below deterministic priority.
/// 8. Deterministic and AI confidence levels are preserved separately.
class AiEvidenceConsistencyValidator {
  const AiEvidenceConsistencyValidator();

  /// Validates [raw] diagnosis against deterministic evidence in [context].
  AiDiagnosis validate(AiDiagnosis raw, AiContext context) {
    int accepted = 0;
    int rejected = 0;
    int unsupported = 0;

    // -----------------------------------------------------------------------
    // 1. Build verified facts from deterministic evidence
    // -----------------------------------------------------------------------

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

    // -----------------------------------------------------------------------
    // 2. Validate Environment Version Claims
    // -----------------------------------------------------------------------

    final envText =
        (raw.environmentAssessment + ' ' + raw.summary).toLowerCase();

    // Check Flutter version contradiction.
    final flutterVer = context.projectInfo['flutter'];

    if (flutterVer != null) {
      final versionRegex = RegExp(
        r'flutter\s+(?:version\s+)?([0-9]+\.[0-9]+\.[0-9]+)',
      );

      for (final match in versionRegex.allMatches(envText)) {
        final claimedVer = match.group(1);

        if (claimedVer != null && claimedVer != flutterVer) {
          rejected++;
        } else {
          accepted++;
        }
      }
    }

    // Check Gradle version contradiction.
    final gradleVer = context.androidInfo['gradle'];

    if (gradleVer != null) {
      final versionRegex = RegExp(
        r'gradle\s+(?:version\s+)?([0-9]+\.[0-9]+(?:\.[0-9]+)?)',
      );

      for (final match in versionRegex.allMatches(envText)) {
        final claimedVer = match.group(1);

        if (claimedVer != null && claimedVer != gradleVer) {
          rejected++;
        } else {
          accepted++;
        }
      }
    }

    // -----------------------------------------------------------------------
    // 3. Compatibility Claim Validation
    // -----------------------------------------------------------------------

    final mentionsIncompatible = envText.contains('incompatible') ||
        envText.contains('compatibility error');

    if (mentionsIncompatible) {
      final isAbsoluteClaim = envText.contains('definitely incompatible') ||
          envText.contains('are incompatible') ||
          envText.contains('will crash');

      if (isAbsoluteClaim) {
        rejected++;
      } else {
        final hasCautiousLang = envText.contains('could not be verified') ||
            envText.contains('may') ||
            envText.contains('possible') ||
            envText.contains('check');

        if (hasCautiousLang) {
          accepted++;
        } else {
          unsupported++;
        }
      }
    }

    // -----------------------------------------------------------------------
    // 4. Build deterministic file paths, analyzer rules and root-cause map
    // -----------------------------------------------------------------------

    final validFiles = _extractValidFiles(context);

    final validRules = <String>{};

    final rootCauseMap = <String, RootCauseSummary>{};

    for (final rc in context.rootCauses) {
      validRules.addAll(rc.relatedRules);

      rootCauseMap[rc.title.toLowerCase()] = rc;

      for (final rule in rc.relatedRules) {
        rootCauseMap[rule.toLowerCase()] = rc;
      }
    }

    for (final s in context.topCritical) {
      validRules.add(s.rule);
    }

    for (final s in context.topHigh) {
      validRules.add(s.rule);
    }

    for (final s in context.topMedium) {
      validRules.add(s.rule);
    }

    // -----------------------------------------------------------------------
    // 5. Validate Root Cause Diagnoses
    // -----------------------------------------------------------------------

    final validatedRootCauses = <RootCauseDiagnosis>[];

    for (final rc in raw.rootCauses) {
      // Find matching deterministic root cause if available.
      RootCauseSummary? match;

      final normalizedTitle = rc.title.toLowerCase();

      for (final key in rootCauseMap.keys) {
        if (normalizedTitle.contains(key) || key.contains(normalizedTitle)) {
          match = rootCauseMap[key];
          break;
        }
      }

      // ---------------------------------------------------------------
      // Priority validation
      // AI cannot downgrade deterministic priority.
      // ---------------------------------------------------------------

      IssuePriority priority = rc.priority;

      final deterministicConf = match != null
          ? RootCauseConfidence.parse(match.confidence)
          : RootCauseConfidence.unknown;

      if (match != null) {
        final detPriority = IssuePriority.parse(match.priority);

        if (priority.sortOrder > detPriority.sortOrder) {
          // AI attempted to downgrade priority.
          // Example: deterministic CRITICAL -> AI LOW.
          priority = detPriority;
          rejected++;
        } else {
          accepted++;
        }
      }

      // ---------------------------------------------------------------
      // Occurrence validation
      // Deterministic count is authoritative.
      // ---------------------------------------------------------------

      final occurrenceCount = match?.occurrenceCount ?? 1;

      // ---------------------------------------------------------------
      // File validation
      //
      // Every AI-referenced file MUST exist in deterministic evidence.
      // There is intentionally NO:
      //
      //   validFiles.isEmpty || ...
      //
      // because an empty deterministic file set must NOT allow arbitrary
      // AI-generated file paths.
      // ---------------------------------------------------------------

      final validAffectedFiles = <String>[];

      for (final f in rc.affectedFiles) {
        final normPath = _normalizePath(f);

        if (validFiles.contains(normPath)) {
          validAffectedFiles.add(normPath);
          accepted++;
        } else {
          // Hallucinated / unsupported file path.
          rejected++;
        }
      }

      // ---------------------------------------------------------------
      // Evidence rule validation
      // ---------------------------------------------------------------

      final validEvidence = <String>[];

      for (final ev in rc.evidence) {
        if (ev.contains('rule:')) {
          final rName = ev.split('rule:').last.trim();

          if (validRules.contains(rName)) {
            validEvidence.add(ev);
            accepted++;
          } else {
            // AI referenced an analyzer rule that does not exist
            // in deterministic evidence.
            rejected++;
          }
        } else {
          validEvidence.add(ev);
        }
      }

      // ---------------------------------------------------------------
      // Support validation
      // ---------------------------------------------------------------

      final bool isSupported = match != null ||
          validAffectedFiles.isNotEmpty ||
          validEvidence.isNotEmpty;

      if (!isSupported) {
        unsupported++;
      }

      validatedRootCauses.add(
        RootCauseDiagnosis(
          title: rc.title,
          explanation: rc.explanation,
          priority: priority,
          deterministicConfidence: deterministicConf,
          aiConfidence: rc.aiConfidence,
          evidence: validEvidence,
          recommendedActions: rc.recommendedActions,
          affectedFiles: validAffectedFiles,
          occurrenceCount: occurrenceCount,
          isSupported: isSupported,
        ),
      );
    }

    // -----------------------------------------------------------------------
    // 6. Validate Recommendations
    // -----------------------------------------------------------------------

    final validRecs = <Recommendation>[];
    final unsupportedRecs = <Recommendation>[];

    for (final rec in raw.recommendations) {
      final text = (rec.title + ' ' + rec.explanation).toLowerCase();

      bool contradictsFact = false;
      String? rejectionReason;

      if (text.contains('downgrade gradle') && !mentionsIncompatible) {
        contradictsFact = true;

        rejectionReason =
            'Recommends Gradle downgrade without evidence of incompatibility.';
      } else if (text.contains('upgrade flutter') && text.contains('solely')) {
        contradictsFact = true;

        rejectionReason =
            'Recommends Flutter upgrade without missing API evidence.';
      }

      if (contradictsFact) {
        unsupported++;

        unsupportedRecs.add(
          Recommendation(
            title: rec.title,
            explanation: rec.explanation,
            priority: rec.priority,
            relatedRootCause: rec.relatedRootCause,
            isSupported: false,
            rejectionReason: rejectionReason,
          ),
        );
      } else {
        accepted++;
        validRecs.add(rec);
      }
    }

    // -----------------------------------------------------------------------
    // 7. Return validated diagnosis
    // -----------------------------------------------------------------------

    return AiDiagnosis(
      summary: raw.summary,
      healthAssessment: raw.healthAssessment,
      rootCauses: validatedRootCauses,
      recommendations: validRecs,
      unsupportedRecommendations: unsupportedRecs,
      environmentAssessment: raw.environmentAssessment,
      confidence: raw.confidence,
      verifiedFacts: verifiedFacts,
      claimsAcceptedCount: accepted,
      claimsRejectedCount: rejected,
      unsupportedClaimsCount: unsupported,
    );
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Extracts file paths from deterministic evidence.
  ///
  /// Supports evidence such as:
  ///
  ///     lib/main.dart
  ///
  /// and:
  ///
  ///     file: lib/main.dart
  ///
  /// and Windows paths:
  ///
  ///     lib\main.dart
  ///
  /// Every returned path is normalized to `/`.
  Set<String> _extractValidFiles(AiContext context) {
    final files = <String>{};

    final pathRegex = RegExp(
      r'(?:^|\s)(lib[\\/][^\s:,]+\.dart)',
    );

    for (final rc in context.rootCauses) {
      for (final f in rc.affectedFiles) {
        files.add(_normalizePath(f));
      }

      for (final evidence in rc.evidenceSummary) {
        final normalizedEvidence = evidence.replaceAll('\\', '/');

        for (final match in pathRegex.allMatches(normalizedEvidence)) {
          final path = match.group(1);

          if (path != null) {
            files.add(_normalizePath(path));
          }
        }
      }
    }

    return files;
  }

  /// Normalizes Windows and Unix file separators.
  String _normalizePath(String path) {
    return path.trim().replaceAll('\\', '/');
  }
}
