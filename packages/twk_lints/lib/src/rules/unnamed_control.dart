/// The lint of a control a screen reader reads without a name:
/// [UnnamedControl].
library;

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../test_directory.dart';
import '../twk_types.dart';

/// A twk control written with nothing a screen reader can call it by: in
/// the screen-reader mode its line is its role alone (`textbox`,
/// `slider 0.5`), or a glyph (`button ×`).
///
/// Reported, where it is made with arguments written in place:
///
///  * a `TextField`, `TextArea` or `TextFormField` with neither a
///    `semanticsLabel` nor a `placeholder`;
///  * a `Slider` with no `semanticsLabel`;
///  * a `Checkbox` or a `Switch` with neither a `label` nor a
///    `semanticsLabel`;
///  * a `Button` whose label, a string written in place, has no letter or
///    digit (`'×'`, `'▶'`).
///
/// An argument that is `null` or `''` counts as none; any other
/// expression, a variable say, counts as a name, unread. Not reported in
/// a file under the package's `test/`, whose fields are often nameless on
/// purpose.
///
/// ```dart-nocheck
/// TextField(controller: name) // reported: read as `textbox`
/// ```
///
/// With the name the rule asks for:
///
/// ```dart-nocheck
/// TextField(controller: name, semanticsLabel: 'Name') // `textbox Name`
/// ```
final class UnnamedControl extends AnalysisRule {
  /// The rule, named `unnamed_control`, a lint.
  UnnamedControl()
    : super(
        name: 'unnamed_control',
        description: 'Give a control a name a screen reader can read.',
      );

  /// What it reports: the control, the line a screen reader reads, and
  /// what would name it.
  static const code = LintCode(
    'unnamed_control',
    "A screen reader reads this {0} without a name, as '{1}'.",
    correctionMessage: 'Try giving it {2}.',
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (inTestDirectory(context)) {
      return;
    }
    registry.addInstanceCreationExpression(this, _Visitor(this));
  }
}

final class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final UnnamedControl rule;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final element = node.constructorName.type.element;
    final control = element?.name;
    if (control == null || !isTwkClass(element, control)) {
      return;
    }
    bool none(String parameter) => !_names(node, parameter);
    final found = switch (control) {
      'TextField' || 'TextArea' || 'TextFormField'
          when none('semanticsLabel') && none('placeholder') =>
        ('textbox', "a 'semanticsLabel'"),
      'Slider' when none('semanticsLabel') => (
        'slider',
        "a 'semanticsLabel'",
      ),
      'Checkbox' || 'Switch' when none('label') && none('semanticsLabel') => (
        control == 'Switch' ? 'switch' : 'checkbox',
        "a 'label' or a 'semanticsLabel'",
      ),
      'Button' => _glyphs(node),
      _ => null,
    };
    if (found case (final line, final fix)) {
      rule.reportAtNode(
        node.constructorName,
        arguments: [control, line, fix],
      );
    }
  }

  /// The line of a `Button` whose label written in place has no letter or
  /// digit, and what would name it; null for any other.
  static (String, String)? _glyphs(InstanceCreationExpression node) {
    final label = node.argumentList.arguments.firstOrNull?.argumentExpression;
    if (label is! StringLiteral || label.parent is NamedArgument) {
      return null;
    }
    final text = label.stringValue;
    if (text == null || _letterOrDigit.hasMatch(text)) {
      return null;
    }
    return ('button ${text.trim()}'.trimRight(), 'a label of words');
  }

  static final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);
}

/// Whether [node] has an argument named [name] that names something: not
/// `null` or `''`.
bool _names(InstanceCreationExpression node, String name) {
  for (final argument in node.argumentList.arguments) {
    if (argument is NamedArgument && argument.name.lexeme == name) {
      return switch (argument.argumentExpression) {
        NullLiteral() || StringLiteral(stringValue: '') => false,
        _ => true,
      };
    }
  }
  return false;
}
