/// The lint of a `StatefulWidget` made for each item of a list without a
/// key: [MissingKeyInChildren].
library;

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../twk_types.dart';

/// A `StatefulWidget` made for each item of a list (in a `for` element, or
/// by the function a spread `.map` calls) without a key: when an item is
/// added, removed or moved, the states stay where they were and go to
/// other items.
///
/// ```dart-nocheck
/// Column(children: [for (final todo in todos) TodoTile(todo)]) // reported
/// ```
///
/// With the key the rule asks for:
///
/// ```dart-nocheck
/// Column(
///   children: [
///     for (final todo in todos) TodoTile(todo, key: ValueKey(todo.id)),
///   ],
/// )
/// ```
final class MissingKeyInChildren extends AnalysisRule {
  /// The rule, named `missing_key_in_children`, a lint.
  MissingKeyInChildren()
    : super(
        name: 'missing_key_in_children',
        description:
            'Give a StatefulWidget made for each item of a list a key.',
      );

  /// What it reports: the widget's name.
  static const code = LintCode(
    'missing_key_in_children',
    "The StatefulWidget '{0}' is made for each item without a key.",
    correctionMessage:
        "Try giving it a key of its item, such as 'key: ValueKey(item.id)', "
        'so that its State follows the item.',
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addListLiteral(this, _Visitor(this));
  }
}

final class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final MissingKeyInChildren rule;

  @override
  void visitListLiteral(ListLiteral node) {
    for (final element in node.elements) {
      switch (element) {
        case ForElement(:final body):
          _repeated(body);
        case SpreadElement(:final expression):
          _mapped(expression);
        default:
      }
    }
  }

  /// Checks [element], made once for each item of a loop.
  void _repeated(CollectionElement element) {
    switch (element) {
      case ForElement(:final body):
        _repeated(body);
      case IfElement(:final thenElement, :final elseElement):
        _repeated(thenElement);
        if (elseElement != null) {
          _repeated(elseElement);
        }
      case ParenthesizedExpression(:final expression):
        _repeated(expression);
      case ConditionalExpression(:final thenExpression, :final elseExpression):
        _repeated(thenExpression);
        _repeated(elseExpression);
      case InstanceCreationExpression():
        _check(element);
      default:
    }
  }

  /// Checks the widgets `items.map(...)` makes, [expression] or the target
  /// of its `toList()`.
  void _mapped(Expression expression) {
    var e = expression;
    if (e case MethodInvocation(
      methodName: SimpleIdentifier(name: 'toList'),
      :final Expression target,
    )) {
      e = target;
    }
    if (e case MethodInvocation(
      methodName: SimpleIdentifier(name: 'map'),
      argumentList: ArgumentList(arguments: [FunctionExpression(:final body)]),
    )) {
      switch (body) {
        case ExpressionFunctionBody(:final expression):
          _repeated(expression);
        case BlockFunctionBody(block: Block(:final statements)):
          for (final statement in statements) {
            if (statement case ReturnStatement(:final Expression expression)) {
              _repeated(expression);
            }
          }
        default:
      }
    }
  }

  void _check(InstanceCreationExpression node) {
    if (!isStatefulWidgetType(node.staticType)) {
      return;
    }
    final constructor = node.constructorName.element;
    final takesKey =
        constructor?.formalParameters.any(
          (p) => p.isNamed && p.name == 'key',
        ) ??
        false;
    final hasKey = node.argumentList.arguments.any(
      (a) => a is NamedArgument && a.name.lexeme == 'key',
    );
    if (takesKey && !hasKey) {
      rule.reportAtNode(
        node.constructorName,
        arguments: [node.constructorName.type.name.lexeme],
      );
    }
  }
}
