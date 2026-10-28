/// The fix of `prefer_key_bindings`: [UseKeyBindings].
library;

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../assists/wrap.dart' show twkLibrary;
import '../key_names.dart';
import '../twk_types.dart';

/// Rewrites the `InputListener` reported as a `KeyBindings` of the same
/// keys and handlers, its `child` and `key` kept:
///
/// ```dart-nocheck
/// InputListener(
///   onEvent: (event) {
///     if (event is! KeyEvent) return false;
///     if (event.char == 'q') {
///       quit();
///       return true;
///     }
///     if (event.code == KeyCode.enter || event.char == ' ') {
///       submit();
///       return true;
///     }
///     return false;
///   },
///   child: app,
/// )
/// ```
///
/// becomes `KeyBindings({'q': quit, 'enter': submit, 'space': submit},
/// child: app)`.
///
/// Offered for one shape alone: an `onEvent` written in place whose block
/// is, after an optional `if (event is! KeyEvent) return false;`, a run
/// of `if`s without `else`, each testing `event is KeyEvent && ...` (or,
/// after that guard, without it) for a key — `event.char == '<char>'` or
/// `event.code == KeyCode.<key>`, or several such tests joined by `||` —
/// and ending its block in `return true;`, then `return false;`. A
/// handler is what the block does before `return true;`: a call of a
/// function or method without arguments becomes its tear-off, one other
/// expression `() => ...`, more statements `() { ... }`; one that reads
/// the event or returns is not rewritten, nor several keys of a handler
/// other than a tear-off, nor a key that two `if`s test. The listener
/// takes nothing but `onEvent`, `child` and `key`.
///
/// `KeyBindings` takes each key as its name says, without modifiers, and
/// its press or repeat, where the comparison took the key's character or
/// code with any modifiers and any kind: Ctrl and `q` no longer quits.
final class UseKeyBindings extends ResolvedCorrectionProducer {
  /// The fix, in the [context] of a diagnostic.
  UseKeyBindings({required super.context});

  /// What the fix is called: `Convert to KeyBindings`.
  static const kind = FixKind(
    'twk.fix.useKeyBindings',
    DartFixKindPriority.standard,
    'Convert to KeyBindings',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final listener = node.thisOrAncestorOfType<InstanceCreationExpression>();
    if (listener == null ||
        !isTwkClass(listener.constructorName.type.element, 'InputListener')) {
      return;
    }
    final named = <String, Expression>{};
    for (final argument in listener.argumentList.arguments) {
      if (argument is! NamedArgument ||
          !const {'onEvent', 'child', 'key'}.contains(argument.name.lexeme)) {
        return;
      }
      named[argument.name.lexeme] = argument.argumentExpression;
    }
    final onEvent = named['onEvent'];
    final child = named['child'];
    if (onEvent is! FunctionExpression || child == null) {
      return;
    }
    final bindings = _Reader(onEvent).read();
    if (bindings == null) {
      return;
    }
    final eol = utils.endOfLine;
    final indent = utils.oneIndent;
    final base = utils.getLinePrefix(listener.offset);
    final inner = '$base$indent';
    final entryIndent = '$inner$indent';

    String handlerText(_Handler handler, String at) => switch (handler) {
      _TearOff(:final name) => name,
      _Expression(:final expression) =>
        '() => ${reindent(textOf(expression), _prefixOf(expression), at)}',
      _Statements(:final first, :final last) =>
        '() {$eol$at$indent'
            '${reindent(textOf(first, last), _prefixOf(first), '$at$indent')}'
            '$eol$at}',
    };
    String argumentText(String name, String at) =>
        '$name: ${reindent(textOf(named[name]!), _prefixOf(named[name]!), at)}';

    final rest = [
      for (final name in named.keys)
        if (name != 'onEvent') name,
    ];
    final oneLine = [
      for (final (key, handler) in bindings)
        '${_quoted(key)}: ${handlerText(handler, base)}',
    ];
    final restOneLine = [for (final name in rest) argumentText(name, base)];
    final flat = '({${oneLine.join(', ')}}, ${restOneLine.join(', ')})';
    final column = listener.offset - utils.getLineThis(listener.offset);
    final fits =
        !flat.contains(eol) &&
        column + 'KeyBindings'.length + flat.length <= 80;
    await builder.addDartFileEdit(file, (builder) {
      builder.addReplacement(range.node(listener), (builder) {
        builder.writeImportedName([twkLibrary], 'KeyBindings');
        if (fits) {
          builder.write(flat);
          return;
        }
        builder.write('($eol$inner{');
        for (final (key, handler) in bindings) {
          builder.write(
            '$eol$entryIndent${_quoted(key)}: '
            '${handlerText(handler, entryIndent)},',
          );
        }
        builder.write('$eol$inner},');
        for (final name in rest) {
          builder.write('$eol$inner${argumentText(name, inner)},');
        }
        builder.write('$eol$base)');
      });
    });
  }

  String _prefixOf(AstNode node) => utils.getLinePrefix(node.offset);

  /// The text of the file from [first]'s start to [last]'s end.
  String textOf(AstNode first, [AstNode? last]) =>
      unitResult.content.substring(first.offset, (last ?? first).end);

  /// [text], whose lines after its first are indented as from [from],
  /// indented as from [to] instead.
  String reindent(String text, String from, String to) =>
      from == to ? text : utils.replaceSourceIndent(text, from, to);
}

/// What a key runs.
sealed class _Handler {}

/// A function or method torn off: [name].
final class _TearOff extends _Handler {
  _TearOff(this.name);
  final String name;
}

/// One expression, `() => expression`.
final class _Expression extends _Handler {
  _Expression(this.expression);
  final Expression expression;
}

/// The statements from [first] to [last], `() { ... }`.
final class _Statements extends _Handler {
  _Statements(this.first, this.last);
  final Statement first;
  final Statement last;
}

/// Reads the keys and handlers of an `onEvent` of the one shape the fix
/// takes.
final class _Reader {
  _Reader(this.function);

  final FunctionExpression function;
  late final Element event;

  /// The keys, by name, and their handlers, in their order; null where
  /// [function] is not of the shape.
  List<(String, _Handler)>? read() {
    final parameter = switch (function.parameters?.parameters) {
      [final p] => p.declaredFragment?.element,
      _ => null,
    };
    final body = function.body;
    if (parameter == null || body is! BlockFunctionBody) {
      return null;
    }
    event = parameter;
    final statements = body.block.statements;
    if (statements.isEmpty || !_returns(statements.last, value: false)) {
      return null;
    }
    var from = 0;
    final guarded = _isGuard(statements.first);
    if (guarded) {
      from = 1;
    }
    final bindings = <(String, _Handler)>[];
    final names = <String>{};
    for (final statement in statements.sublist(from, statements.length - 1)) {
      if (statement is! IfStatement ||
          statement.elseStatement != null ||
          statement.caseClause != null) {
        return null;
      }
      final keys = _keysOf(statement.expression, guarded: guarded);
      final then = statement.thenStatement;
      if (keys == null ||
          then is! Block ||
          then.statements.length < 2 ||
          !_returns(then.statements.last, value: true)) {
        return null;
      }
      final handler = _handler(
        then.statements.sublist(0, then.statements.length - 1),
      );
      if (handler == null || (keys.length > 1 && handler is! _TearOff)) {
        return null;
      }
      for (final key in keys) {
        if (!names.add(key)) {
          return null;
        }
        bindings.add((key, handler));
      }
    }
    return bindings.isEmpty ? null : bindings;
  }

  /// Whether [statement] is `return true;` ([value]) or `return false;`.
  bool _returns(Statement statement, {required bool value}) =>
      statement is ReturnStatement &&
      statement.expression is BooleanLiteral &&
      (statement.expression! as BooleanLiteral).value == value;

  /// Whether [statement] is `if (event is! KeyEvent) return false;`.
  bool _isGuard(Statement statement) {
    if (statement is! IfStatement ||
        statement.elseStatement != null ||
        statement.caseClause != null) {
      return false;
    }
    final test = statement.expression;
    final then = switch (statement.thenStatement) {
      Block(statements: [final only]) => only,
      final other => other,
    };
    return test is IsExpression &&
        test.notOperator != null &&
        _isEvent(test.expression) &&
        isTwkClass(test.type.type?.element, 'KeyEvent') &&
        _returns(then, value: false);
  }

  bool _isEvent(Expression e) => e is SimpleIdentifier && e.element == event;

  /// The key names [condition] tests for: `event is KeyEvent && keys`, or
  /// the keys alone where the handler is [guarded].
  List<String>? _keysOf(Expression condition, {required bool guarded}) {
    final e = condition.unParenthesized;
    if (e
        case BinaryExpression(
          operator: Token(type: TokenType.AMPERSAND_AMPERSAND),
          :final leftOperand,
          :final rightOperand,
        )
        when _isKeyEventTest(leftOperand.unParenthesized)) {
      return _keys(rightOperand);
    }
    return guarded ? _keys(e) : null;
  }

  /// Whether [e] is `event is KeyEvent`.
  bool _isKeyEventTest(Expression e) =>
      e is IsExpression &&
      e.notOperator == null &&
      _isEvent(e.expression) &&
      isTwkClass(e.type.type?.element, 'KeyEvent');

  /// The names of the keys `test || test ...` compares with.
  List<String>? _keys(Expression test) {
    final e = test.unParenthesized;
    if (e is! BinaryExpression) {
      return null;
    }
    if (e.operator.type == TokenType.BAR_BAR) {
      final left = _keys(e.leftOperand);
      final right = _keys(e.rightOperand);
      return left == null || right == null ? null : [...left, ...right];
    }
    if (e.operator.type != TokenType.EQ_EQ) {
      return null;
    }
    final name =
        _keyName(e.leftOperand, e.rightOperand) ??
        _keyName(e.rightOperand, e.leftOperand);
    return name == null ? null : [name];
  }

  /// The name of the key `read == constant` compares with, where [read]
  /// is `event.char` or `event.code`.
  String? _keyName(Expression read, Expression constant) {
    if (read case PrefixedIdentifier(:final prefix, :final identifier)
        when _isEvent(prefix) &&
            isTwkClass(identifier.element?.enclosingElement, 'KeyEvent')) {
      return switch (identifier.name) {
        'char' => _charName(constant),
        'code' => _codeName(constant),
        _ => null,
      };
    }
    return null;
  }

  String? _charName(Expression constant) {
    if (constant is! SimpleStringLiteral) {
      return null;
    }
    final char = constant.value;
    final lower = char.toLowerCase();
    final spec = lower != char && char.toUpperCase() == char
        ? KeySpec.char(lower, KeySpec.shift)
        : KeySpec.char(char);
    return _roundTrip(spec);
  }

  String? _codeName(Expression constant) {
    final name = switch (constant) {
      PrefixedIdentifier(:final identifier) => identifier,
      PropertyAccess(:final propertyName) => propertyName,
      _ => null,
    };
    final element = name?.element;
    final variable = element is GetterElement ? element.variable : element;
    if (variable is! FieldElement ||
        !variable.isEnumConstant ||
        !isTwkClass(variable.enclosingElement, 'KeyCode')) {
      return null;
    }
    final key = variable.name!.toLowerCase();
    return keyNames.contains(key) ? _roundTrip(KeySpec.key(key)) : null;
  }

  /// The name of [spec], where twk reads it back as [spec].
  String? _roundTrip(KeySpec spec) {
    final name = spec.toString();
    try {
      return parseKey(name) == spec ? name : null;
    } on KeyNameException {
      return null;
    }
  }

  /// What [statements] become as the handler of a key; null where they
  /// read the event or return.
  _Handler? _handler(List<Statement> statements) {
    final uses = _Uses(event);
    for (final s in statements) {
      s.accept(uses);
    }
    if (statements.isEmpty || uses.found) {
      return null;
    }
    if (statements case [ExpressionStatement(:final expression)]) {
      if (expression
          case MethodInvocation(
            target: null,
            typeArguments: null,
            argumentList: ArgumentList(arguments: []),
            :final methodName,
          )
          when methodName.element is ExecutableElement &&
              methodName.element is! GetterElement) {
        return _TearOff(methodName.name);
      }
      return _Expression(expression);
    }
    return _Statements(statements.first, statements.last);
  }
}

/// Finds a read of the event, or a `return` of the handler itself.
final class _Uses extends RecursiveAstVisitor<void> {
  _Uses(this.event);

  final Element event;
  var found = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element == event) {
      found = true;
    }
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    found = true;
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // a return in a function written in the handler is the function's
    final reads = _Reads(event);
    node.body.accept(reads);
    if (reads.found) {
      found = true;
    }
  }
}

/// Finds a read of the event.
final class _Reads extends RecursiveAstVisitor<void> {
  _Reads(this.event);

  final Element event;
  var found = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element == event) {
      found = true;
    }
  }
}

/// [key] as a string literal in single quotes.
String _quoted(String key) {
  final escaped = key
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$');
  return "'$escaped'";
}
