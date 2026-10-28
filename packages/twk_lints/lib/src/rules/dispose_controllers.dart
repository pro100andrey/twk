/// The warning of a controller a `State` creates and does not dispose:
/// [DisposeControllers].
library;

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import '../twk_types.dart';

/// A field of a twk `State` that the state creates (in its initializer,
/// or by assigning it a new object in a method such as `initState`), of a
/// type with a `dispose()` method — a controller, a `FocusNode`, any
/// `ChangeNotifier` — that nothing in the class disposes.
///
/// ```dart-nocheck
/// final class _SearchState extends State<Search> {
///   final _controller = TextEditingController(); // reported
///
///   @override
///   Widget build(BuildContext context) => TextField(controller: _controller);
/// }
/// ```
///
/// Disposing of it in `dispose` is what the rule asks for:
///
/// ```dart-nocheck
/// @override
/// void dispose() {
///   _controller.dispose();
///   super.dispose();
/// }
/// ```
///
/// A loop that disposes its variable disposes what it goes over: a list
/// or set written in place (`for (final n in [_a, _b]) n.dispose()`,
/// `[_a, _b].forEach((n) => n.dispose())`), or a collection field the
/// fields are put in by its initializer, `add` or `addAll`. A list a
/// method returns is not followed: its fields are still reported.
final class DisposeControllers extends AnalysisRule {
  /// The rule, named `dispose_controllers`, a warning.
  DisposeControllers()
    : super(
        name: 'dispose_controllers',
        description: 'Dispose the controllers a State creates.',
      );

  /// What it reports: the field's type and name.
  static const code = LintCode(
    'dispose_controllers',
    "The State creates the {0} '{1}' and doesn't dispose it.",
    correctionMessage: "Try calling '{1}.dispose()' in 'dispose'.",
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addClassDeclaration(this, _Visitor(this));
  }
}

final class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final DisposeControllers rule;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final element = classElementOf(node);
    if (element == null || !isStateClass(element)) {
      return;
    }
    final fields = <FieldElement, VariableDeclaration>{};
    for (final member in node.body.members) {
      if (member is FieldDeclaration && !member.isStatic) {
        for (final v in member.fields.variables) {
          if (v.declaredFragment?.element case final FieldElement f) {
            fields[f] = v;
          }
        }
      }
    }
    if (fields.isEmpty) {
      return;
    }
    final scan = _Scan(fields.keys.toSet(), element.library);
    for (final entry in fields.entries) {
      if (_created(entry.value.initializer, element.library)) {
        scan.created.add(entry.key);
      }
    }
    node.body.visitChildren(scan);
    final disposed = scan.disposed;
    for (final f in scan.created) {
      if (!disposed.contains(f)) {
        final type = f.type;
        final name = type is InterfaceType
            ? type.element.displayName
            : type.getDisplayString();
        rule.reportAtToken(fields[f]!.name, arguments: [name, f.displayName]);
      }
    }
  }
}

/// Whether [e] creates an object with a `dispose()` method.
bool _created(Expression? e, LibraryElement library) {
  final type = switch (e) {
    InstanceCreationExpression() => e.staticType,
    // `late final x = X()..addListener(...)`
    CascadeExpression(:final InstanceCreationExpression target) =>
      target.staticType,
    _ => null,
  };
  return type is InterfaceType && _disposable(type, library);
}

bool _disposable(InterfaceType type, LibraryElement library) {
  final dispose = type.lookUpMethod('dispose', library);
  return dispose != null &&
      !dispose.isStatic &&
      dispose.formalParameters.every((p) => !p.isRequired);
}

/// What a class body creates and disposes of [fields].
///
/// A field counts as disposed when the class calls `dispose()` on it, or
/// on the variable of a loop over a collection it is in: a `for`-in or a
/// `forEach` whose function disposes its parameter, over a list or set
/// written in place that names the field, or over a collection field that
/// names it in its initializer or that the class `add`s or `addAll`s it to.
final class _Scan extends RecursiveAstVisitor<void> {
  _Scan(this.fields, this.library);

  final Set<FieldElement> fields;
  final LibraryElement library;
  final created = <FieldElement>{};
  final _disposed = <FieldElement>{};

  // the fields each collection field is given, and the collection fields
  // a loop disposes the elements of
  final _members = <FieldElement, Set<FieldElement>>{};
  final _disposedCollections = <FieldElement>{};

  /// The fields disposed, directly or through a collection.
  Set<FieldElement> get disposed => {
    ..._disposed,
    for (final c in _disposedCollections) ...?_members[c],
  };

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.declaredFragment?.element case final FieldElement f
        when fields.contains(f)) {
      _addMembers(f, node.initializer);
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    final f = _field(node.writeElement);
    if (f != null) {
      if (_created(node.rightHandSide, library)) {
        created.add(f);
      }
      _addMembers(f, node.rightHandSide);
    }
    super.visitAssignmentExpression(node);
  }

  @override
  void visitForStatement(ForStatement node) {
    if (node.forLoopParts case ForEachPartsWithDeclaration(
      :final loopVariable,
      :final iterable,
    )) {
      if (_disposes(node.body, loopVariable.declaredFragment?.element)) {
        _disposeElementsOf(iterable);
      }
    }
    super.visitForStatement(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.realTarget;
    final only = _onlyPositional(node.argumentList);
    switch (node.methodName.name) {
      case 'dispose':
        if (_fieldOf(target) case final f?) {
          _disposed.add(f);
        }
      case 'forEach' when target != null && only != null:
        if (only
            case FunctionExpression(
              parameters: FormalParameterList(parameters: [final p]),
              :final body,
            )
            when _disposes(body, p.declaredFragment?.element)) {
          _disposeElementsOf(target);
        }
      case 'add' when only != null:
        if ((_fieldOf(target), _fieldOf(only)) case (final c?, final f?)) {
          (_members[c] ??= {}).add(f);
        }
      case 'addAll' when only != null:
        if (_fieldOf(target) case final c?) {
          _addMembers(c, only);
        }
    }
    super.visitMethodInvocation(node);
  }

  /// The positional argument of [arguments] when it has just one, read in
  /// place.
  static Expression? _onlyPositional(ArgumentList arguments) {
    Expression? only;
    for (final a in arguments.arguments) {
      if (a is! NamedArgument) {
        if (only != null) {
          return null;
        }
        only = a.argumentExpression;
      }
    }
    return only;
  }

  /// Records the fields the list or set literal [e] names as members of
  /// the collection field [c].
  void _addMembers(FieldElement c, Expression? e) {
    final named = _named(e);
    if (named.isNotEmpty) {
      (_members[c] ??= {}).addAll(named);
    }
  }

  void _disposeElementsOf(Expression iterable) {
    if (_fieldOf(iterable) case final c?) {
      _disposedCollections.add(c);
    } else {
      _disposed.addAll(_named(iterable));
    }
  }

  /// The fields a list or set literal names as its elements.
  Set<FieldElement> _named(Expression? e) => switch (e) {
    ListLiteral(:final elements) || SetOrMapLiteral(:final elements) => {
      for (final element in elements)
        if (element is Expression) ?_fieldOf(element),
    },
    _ => const {},
  };

  /// Whether [body] calls `dispose()` on [variable].
  bool _disposes(AstNode body, Element? variable) {
    if (variable == null) {
      return false;
    }
    final finder = _DisposeOf(variable);
    body.accept(finder);
    return finder.found;
  }

  FieldElement? _fieldOf(Expression? e) => switch (e) {
    SimpleIdentifier() => _field(e.element),
    PropertyAccess(target: ThisExpression(), :final propertyName) => _field(
      propertyName.element,
    ),
    PostfixExpression(:final operand) => _fieldOf(operand),
    ParenthesizedExpression(:final expression) => _fieldOf(expression),
    _ => null,
  };

  FieldElement? _field(Element? element) {
    // in a generic State, the field read is the declared one with the
    // class's type parameters for its arguments: its base is the field
    final variable = switch (element?.baseElement) {
      GetterElement(:final variable) ||
      SetterElement(:final variable) => variable.baseElement,
      final FieldElement f => f,
      _ => null,
    };
    return variable is FieldElement && fields.contains(variable)
        ? variable
        : null;
  }
}

/// Finds a `dispose()` called on one variable.
final class _DisposeOf extends RecursiveAstVisitor<void> {
  _DisposeOf(this.variable);

  final Element variable;
  var found = false;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.realTarget case SimpleIdentifier(:final element)
        when node.methodName.name == 'dispose' && element == variable) {
      found = true;
    }
    super.visitMethodInvocation(node);
  }
}
