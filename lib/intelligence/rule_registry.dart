import '../models/issue_priority.dart';
import '../models/issue_category.dart';
import '../models/rule_metadata.dart';

/// Deterministic registry mapping analyzer rule identifiers to [RuleMetadata].
///
/// This is the single place where classification lives.
/// To add a new rule:  add one entry to [_registry].
/// To reclassify:      change the entry here.
/// Unknown rules are NOT guessed — [lookup] returns null for any unregistered rule.
class RuleRegistry {
  RuleRegistry._();

  static final Map<String, RuleMetadata> _registry = {
    // ────────────────────────────────────────────────────
    // CRITICAL — likely prevents compilation or direct
    //            correctness failure.
    // ────────────────────────────────────────────────────
    'undefined_method': RuleMetadata(
      rule: 'undefined_method',
      priority: IssuePriority.critical,
      category: IssueCategory.correctness,
      description: 'A referenced method does not exist for the target type.',
    ),
    'undefined_class': RuleMetadata(
      rule: 'undefined_class',
      priority: IssuePriority.critical,
      category: IssueCategory.correctness,
      description: 'A referenced class is not defined or not imported.',
    ),
    'undefined_identifier': RuleMetadata(
      rule: 'undefined_identifier',
      priority: IssuePriority.critical,
      category: IssueCategory.correctness,
      description: 'An identifier is used that is not defined in scope.',
    ),
    'undefined_function': RuleMetadata(
      rule: 'undefined_function',
      priority: IssuePriority.critical,
      category: IssueCategory.correctness,
      description: 'A referenced function does not exist.',
    ),
    'not_enough_required_arguments': RuleMetadata(
      rule: 'not_enough_required_arguments',
      priority: IssuePriority.critical,
      category: IssueCategory.correctness,
      description:
          'A function or constructor is called with too few required arguments.',
    ),
    'extra_positional_arguments': RuleMetadata(
      rule: 'extra_positional_arguments',
      priority: IssuePriority.critical,
      category: IssueCategory.correctness,
      description:
          'A function or constructor is called with more positional arguments than it accepts.',
    ),
    'argument_type_not_assignable': RuleMetadata(
      rule: 'argument_type_not_assignable',
      priority: IssuePriority.critical,
      category: IssueCategory.correctness,
      description:
          'An argument type cannot be assigned to the corresponding parameter type.',
    ),
    'return_of_invalid_type': RuleMetadata(
      rule: 'return_of_invalid_type',
      priority: IssuePriority.critical,
      category: IssueCategory.correctness,
      description:
          'A value of an incompatible type is returned from a function.',
    ),
    'invalid_assignment': RuleMetadata(
      rule: 'invalid_assignment',
      priority: IssuePriority.critical,
      category: IssueCategory.correctness,
      description:
          'A value cannot be assigned to a variable because the types are incompatible.',
    ),

    // ────────────────────────────────────────────────────
    // HIGH — potential runtime / correctness / safety issue.
    // ────────────────────────────────────────────────────
    'use_build_context_synchronously': RuleMetadata(
      rule: 'use_build_context_synchronously',
      priority: IssuePriority.high,
      category: IssueCategory.runtimeSafety,
      description: 'BuildContext is used across an async gap, which can cause '
          'crashes if the widget is unmounted before the async call completes.',
    ),
    'invalid_null_aware_operator': RuleMetadata(
      rule: 'invalid_null_aware_operator',
      priority: IssuePriority.high,
      category: IssueCategory.runtimeSafety,
      description:
          'A null-aware operator is used on a non-nullable type, indicating '
          'a likely misunderstanding of nullability.',
    ),
    'unnecessary_non_null_assertion': RuleMetadata(
      rule: 'unnecessary_non_null_assertion',
      priority: IssuePriority.high,
      category: IssueCategory.runtimeSafety,
      description:
          'The ! operator is applied to a value that is already non-nullable, '
          'which may hide logic errors.',
    ),
    'override_on_non_overriding_member': RuleMetadata(
      rule: 'override_on_non_overriding_member',
      priority: IssuePriority.high,
      category: IssueCategory.correctness,
      description:
          'A member is annotated with @override but does not override anything '
          'in the superclass, which may indicate a silent logic error.',
    ),

    // ────────────────────────────────────────────────────
    // MEDIUM — important maintenance, deprecation, or
    //          potentially problematic code.
    // ────────────────────────────────────────────────────
    'deprecated_member_use': RuleMetadata(
      rule: 'deprecated_member_use',
      priority: IssuePriority.medium,
      category: IssueCategory.deprecatedApi,
      description:
          'A deprecated API member is used. It may be removed in a future SDK version.',
    ),
    'depend_on_referenced_packages': RuleMetadata(
      rule: 'depend_on_referenced_packages',
      priority: IssuePriority.medium,
      category: IssueCategory.maintainability,
      description:
          'A package is used that is not listed as a direct dependency in pubspec.yaml.',
    ),
    'unused_local_variable': RuleMetadata(
      rule: 'unused_local_variable',
      priority: IssuePriority.medium,
      category: IssueCategory.codeQuality,
      description:
          'A local variable is declared but never read. This may indicate dead code or a logic error.',
    ),
    'unused_field': RuleMetadata(
      rule: 'unused_field',
      priority: IssuePriority.medium,
      category: IssueCategory.codeQuality,
      description:
          'A class field is declared but never accessed outside the class.',
    ),
    'unused_element': RuleMetadata(
      rule: 'unused_element',
      priority: IssuePriority.medium,
      category: IssueCategory.codeQuality,
      description:
          'A top-level or member element is declared but never used anywhere.',
    ),
    'dead_null_aware_expression': RuleMetadata(
      rule: 'dead_null_aware_expression',
      priority: IssuePriority.medium,
      category: IssueCategory.codeQuality,
      description:
          'The right side of a null-aware expression will never be evaluated because '
          'the left side is never null.',
    ),
    'included_file_warning': RuleMetadata(
      rule: 'included_file_warning',
      priority: IssuePriority.medium,
      category: IssueCategory.maintainability,
      description:
          'An included analysis options file produced a warning during resolution.',
    ),

    // ────────────────────────────────────────────────────
    // LOW — code quality, style, readability, or minor
    //       optimizations.
    // ────────────────────────────────────────────────────
    'unused_import': RuleMetadata(
      rule: 'unused_import',
      priority: IssuePriority.low,
      category: IssueCategory.codeQuality,
      description:
          'An import statement is present but nothing from it is used.',
    ),
    'unnecessary_import': RuleMetadata(
      rule: 'unnecessary_import',
      priority: IssuePriority.low,
      category: IssueCategory.codeQuality,
      description:
          'An import is unnecessary because the symbols it provides are already '
          'available through another import.',
    ),
    'prefer_const_constructors': RuleMetadata(
      rule: 'prefer_const_constructors',
      priority: IssuePriority.low,
      category: IssueCategory.performance,
      description:
          'A constructor call can be made const, which avoids unnecessary '
          'object allocation on subsequent rebuilds.',
    ),
    'prefer_const_literals_to_create_immutables': RuleMetadata(
      rule: 'prefer_const_literals_to_create_immutables',
      priority: IssuePriority.low,
      category: IssueCategory.performance,
      description:
          'A list or map literal passed to an immutable constructor should be const.',
    ),
    'sized_box_for_whitespace': RuleMetadata(
      rule: 'sized_box_for_whitespace',
      priority: IssuePriority.low,
      category: IssueCategory.codeQuality,
      description: 'A Container with only width/height and no other properties '
          'should be replaced with SizedBox.',
    ),
    'curly_braces_in_flow_control_structures': RuleMetadata(
      rule: 'curly_braces_in_flow_control_structures',
      priority: IssuePriority.low,
      category: IssueCategory.style,
      description:
          'Flow control statements (if/for/while) should always use curly braces '
          'to prevent accidental single-statement bugs.',
    ),
    'unnecessary_this': RuleMetadata(
      rule: 'unnecessary_this',
      priority: IssuePriority.low,
      category: IssueCategory.style,
      description:
          'The "this" keyword is used where it is not needed to resolve ambiguity.',
    ),
    'file_names': RuleMetadata(
      rule: 'file_names',
      priority: IssuePriority.low,
      category: IssueCategory.style,
      description:
          'The file name does not follow Dart naming conventions (snake_case).',
    ),
    'camel_case_types': RuleMetadata(
      rule: 'camel_case_types',
      priority: IssuePriority.low,
      category: IssueCategory.style,
      description:
          'A type name does not use UpperCamelCase as required by Dart conventions.',
    ),
    'non_constant_identifier_names': RuleMetadata(
      rule: 'non_constant_identifier_names',
      priority: IssuePriority.low,
      category: IssueCategory.style,
      description:
          'A variable or parameter name does not use lowerCamelCase as required '
          'by Dart conventions.',
    ),
    'avoid_print': RuleMetadata(
      rule: 'avoid_print',
      priority: IssuePriority.low,
      category: IssueCategory.codeQuality,
      description:
          'print() is used in production code. Use a proper logging framework instead.',
    ),
  };

  /// Returns the [RuleMetadata] for [rule], or null if the rule is not
  /// registered. Unknown rules are never guessed.
  static RuleMetadata? lookup(String rule) => _registry[rule];

  /// Returns all registered rules (for testing / introspection).
  static Iterable<String> get registeredRules => _registry.keys;
}
