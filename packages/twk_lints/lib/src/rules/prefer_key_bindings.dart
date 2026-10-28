/// The lint of an `InputListener` that only binds keys:
/// [PreferKeyBindings].
library;

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import '../twk_types.dart';

/// A twk `InputListener` whose `onEvent` only matches keys: it tests for
/// no event but `KeyEvent`, compares a key's `code` or `char` with a
/// constant, reads no `KeyKind` but `press`, and passes the event on to
/// nothing. `KeyBindings` does that, nearer the focus, and lists its keys
/// with their hints.
///
/// The handler is a function written in place, or a function or method
/// of the same file named there.
///
/// ```dart-nocheck
/// InputListener( // reported
///   onEvent: (event) {
///     if (event is KeyEvent && event.char == 'q') {
///       quit();
///       return true;
///     }
///     return false;
///   },
///   child: app,
/// )
/// ```
///
/// As the rule asks for it:
///
/// ```dart-nocheck
/// KeyBindings({'q': quit}, child: app)
/// ```
final class PreferKeyBindings extends AnalysisRule {
  /// The rule, named `prefer_key_bindings`, a lint.
  PreferKeyBindings()
    : super(
        name: 'prefer_key_bindings',
        description: 'Bind keys with KeyBindings, not an InputListener.',
      );

  /// What it reports.
  static const code = LintCode(
    'prefer_key_bindings',
    'This InputListener only matches keys.',
    correctionMessage:
        "Try 'KeyBindings({'q': quit}, child: ...)', which also lists the "
        'keys it binds.',
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addInstanceCreationExpression(this, _Visitor(this));
  }
}

final class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final PreferKeyBindings rule;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (!isTwkClass(node.constructorName.type.element, 'InputListener')) {
      return;
    }
    final onEvent = node.argumentList.arguments
        .whereType<NamedArgument>()
        .where((a) => a.name.lexeme == 'onEvent')
        .firstOrNull
        ?.argumentExpression;
    final handler = switch (onEvent) {
      FunctionExpression(:final parameters, :final body) => (parameters, body),
      SimpleIdentifier(:final element?) ||
      PrefixedIdentifier(:final element?) ||
      PropertyAccess(
        propertyName: SimpleIdentifier(:final element?),
      ) => _declaration(node.root, element),
      _ => null,
    };
    if (handler == null) {
      return;
    }
    final (parameters, body) = handler;
    if (parameters?.parameters case [final p]) {
      final event = p.declaredFragment?.element;
      if (event != null) {
        final scan = _Scan(event);
        body.accept(scan);
        if (scan.keysOnly) {
          rule.reportAtNode(node.constructorName);
        }
      }
    }
  }

  /// The parameters and body of the function [element] declared in [unit],
  /// found from its name's offset: a top-level function, a method, or a
  /// local function that is in no method.
  (FormalParameterList?, FunctionBody)? _declaration(
    AstNode unit,
    Element element,
  ) {
    final fragment = element.firstFragment;
    final offset = fragment.nameOffset;
    if (unit is! CompilationUnit ||
        offset == null ||
        fragment.libraryFragment != unit.declaredFragment) {
      return null;
    }
    // nodeCovering2, which is to replace it, is experimental
    for (var n = unit.nodeCovering(offset: offset); n != null; n = n.parent) {
      switch (n) {
        case MethodDeclaration():
          return n.declaredFragment?.element == element
              ? (n.parameters, n.body)
              : null;
        case FunctionDeclaration() when n.declaredFragment?.element == element:
          // a local function of a method is not looked for
          if (n.thisOrAncestorOfType<MethodDeclaration>() != null) {
            return null;
          }
          return (n.functionExpression.parameters, n.functionExpression.body);
      }
    }
    return null;
  }
}

/// How a handler uses its [event].
final class _Scan extends RecursiveAstVisitor<void> {
  _Scan(this.event);

  final Element event;
  var _testsKey = false;
  var _testsOther = false;
  var _comparesKey = false;
  var _readsKind = false;
  var _passesEvent = false;

  bool get keysOnly =>
      _testsKey && _comparesKey && !_testsOther && !_readsKind && !_passesEvent;

  void _tested(DartType? type) {
    if (isTwkClass(type?.element, 'KeyEvent')) {
      _testsKey = true;
    } else if (isTwkSubtype(type, 'InputEvent') &&
        !isTwkClass(type?.element, 'InputEvent')) {
      _testsOther = true;
    }
  }

  @override
  void visitIsExpression(IsExpression node) {
    _tested(node.type.type);
    super.visitIsExpression(node);
  }

  @override
  void visitObjectPattern(ObjectPattern node) {
    _tested(node.type.type);
    if (isTwkClass(node.type.type?.element, 'KeyEvent')) {
      for (final field in node.fields) {
        final name = field.name?.name?.lexeme ?? field.element?.name;
        if ((name == 'code' || name == 'char') && _constant(field.pattern)) {
          _comparesKey = true;
        }
      }
    }
    super.visitObjectPattern(node);
  }

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    _tested(node.type?.type);
    super.visitDeclaredVariablePattern(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final op = node.operator.type;
    if ((op == TokenType.EQ_EQ || op == TokenType.BANG_EQ) &&
        ((_isKey(node.leftOperand) && _isConstant(node.rightOperand)) ||
            (_isKey(node.rightOperand) && _isConstant(node.leftOperand)))) {
      _comparesKey = true;
    }
    super.visitBinaryExpression(node);
  }

  @override
  void visitSwitchStatement(SwitchStatement node) {
    if (_isKey(node.expression) &&
        node.members.whereType<SwitchPatternCase>().any(
          (c) => _constant(c.guardedPattern.pattern),
        )) {
      _comparesKey = true;
    }
    super.visitSwitchStatement(node);
  }

  @override
  void visitSwitchExpression(SwitchExpression node) {
    if (_isKey(node.expression) &&
        node.cases.any((c) => _constant(c.guardedPattern.pattern))) {
      _comparesKey = true;
    }
    super.visitSwitchExpression(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.element;
    if (element == event && !_onlyInspected(node)) {
      _passesEvent = true;
    }
    if (element is FieldElement || element is GetterElement) {
      final name = element?.name;
      final enclosing = element?.enclosingElement;
      if (isTwkClass(enclosing, 'KeyKind') && name != 'press') {
        _readsKind = true;
      }
    }
    super.visitSimpleIdentifier(node);
  }

  /// Whether [node], a use of the event, only reads it.
  bool _onlyInspected(SimpleIdentifier node) => switch (node.parent) {
    PrefixedIdentifier(:final prefix) => identical(prefix, node),
    PropertyAccess(:final target) => identical(target, node),
    MethodInvocation(:final target) => identical(target, node),
    IsExpression() || SwitchStatement() || SwitchExpression() => true,
    IfStatement(caseClause: _?) => true,
    _ => false,
  };

  /// Whether [e] is `event.code` or `event.char` of a key event.
  bool _isKey(Expression e) {
    final name = switch (e) {
      PrefixedIdentifier(:final identifier) => identifier,
      PropertyAccess(:final propertyName) => propertyName,
      _ => null,
    };
    final element = name?.element;
    return name != null &&
        (name.name == 'code' || name.name == 'char') &&
        isTwkClass(element?.enclosingElement, 'KeyEvent');
  }

  bool _isConstant(Expression e) => switch (e) {
    StringLiteral() => true,
    PrefixedIdentifier(:final identifier) => _isEnumConstant(identifier),
    PropertyAccess(:final propertyName) => _isEnumConstant(propertyName),
    SimpleIdentifier() => _isEnumConstant(e),
    _ => false,
  };

  bool _isEnumConstant(SimpleIdentifier name) {
    final element = name.element;
    final variable = element is GetterElement ? element.variable : element;
    return variable is FieldElement && variable.isEnumConstant;
  }

  bool _constant(DartPattern pattern) => switch (pattern) {
    ConstantPattern(:final expression) => _isConstant(expression),
    LogicalOrPattern(:final leftOperand, :final rightOperand) =>
      _constant(leftOperand) && _constant(rightOperand),
    ParenthesizedPattern(:final pattern) => _constant(pattern),
    _ => false,
  };
}
