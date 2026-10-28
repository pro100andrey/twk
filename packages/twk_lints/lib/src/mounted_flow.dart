/// Where in a function body a `State` may have been disposed:
/// [MountedFlow], the flow analysis `set_state_after_dispose` and
/// `context_after_await` share.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

/// Why a point of a function body may run once the state was disposed.
enum Gap {
  /// It follows an `await` (or the next element of an `await for`).
  await_("it follows an 'await'"),

  /// The body is a callback of a `Future`: `then`, `catchError`,
  /// `whenComplete`, `Future.delayed`.
  callback('it is in a callback of a Future');

  const Gap(this.why);

  /// The reason, as the diagnostics give it.
  final String why;
}

/// The flow of one function body: for each identifier read in it, whether
/// some path to it passes a gap — an `await`, or the start of a callback
/// of a `Future` — with no check of `mounted` after.
///
/// The analysis follows the body's statements in the order they run:
/// `if`/`else` and conditional expressions branch and join, `&&`, `||` and
/// `!` narrow a condition, `return`, `throw`, `break` and `continue` end a
/// path, loops are followed round until nothing changes (so an `await` at
/// the end of a loop's body is a gap before its start), and `switch` and
/// `try` are joined over their cases. An argument of an awaited call is
/// read before the gap. A check is a read of `mounted` (`mounted`,
/// `context.mounted`, `x.y.mounted`) that is true on the path: the
/// branch of `if (mounted)`, and what follows `if (!mounted) return;`.
/// A local variable or parameter assigned after the last gap is fresh,
/// and its reads are not after one; so is one that a function written in
/// the function declaring it assigns (a builder that keeps its context),
/// as that may run during any gap.
///
/// It does not follow functions written in the body (each is a body of
/// its own, which starts with no gap unless it is a `Future`'s callback),
/// guards of the code's own (a token, a flag), or a `State`'s `mounted`
/// apart from a context's: either one checks both.
final class MountedFlow {
  MountedFlow._(FunctionBody body) {
    final walker = _Walker(this)..s = _Flow(_entryGap(body), const <Element>{});
    switch (body) {
      case BlockFunctionBody(:final block):
        block.accept(walker);
      case ExpressionFunctionBody(:final expression):
        expression.accept(walker);
      default:
    }
  }

  MountedFlow._none();

  /// The flow of [body], analyzed once and kept while the body is.
  ///
  /// A body that is neither `async` nor a `Future`'s callback has no gap
  /// (an `await` is only valid in an `async` body), and is not walked.
  factory MountedFlow.of(FunctionBody body) =>
      !body.isAsynchronous && _entryGap(body) == 0
      ? _noGap
      : _flows[body] ??= MountedFlow._(body);

  static final _flows = Expando<MountedFlow>('MountedFlow');

  /// The flow of every body that cannot have a gap.
  static final _noGap = MountedFlow._none();

  /// The gaps some path to each identifier passes unchecked, as bits of
  /// [Gap]'s indices.
  final Map<SimpleIdentifier, int> _gaps = {};

  /// Why [node], an identifier of the body, may be read once the state
  /// was disposed; null when every path to it checks `mounted` after its
  /// last gap.
  Gap? gapAt(SimpleIdentifier node) {
    final bits = _gaps[node] ?? 0;
    if (bits & _await != 0) {
      return Gap.await_;
    }
    return bits & _callback != 0 ? Gap.callback : null;
  }

  void _record(SimpleIdentifier node, int bits) {
    if (bits != 0 && !_writtenByAFunction(node)) {
      _gaps[node] = (_gaps[node] ?? 0) | bits;
    }
  }

  /// The local variables and parameters of each function body that a
  /// function written in it assigns.
  static final _closureWrites = Expando<Set<Element>>('closure writes');

  /// Whether [node] reads a local variable or parameter that a function
  /// written in the one declaring it assigns: a builder that keeps its
  /// context, say, which may run during any `await`.
  static bool _writtenByAFunction(SimpleIdentifier node) {
    final variable = node.element;
    if (variable is! LocalVariableElement &&
        variable is! FormalParameterElement) {
      return false;
    }
    final at = variable!.firstFragment.offset;
    for (
      var body = node.thisOrAncestorOfType<FunctionBody>();
      body != null;
      body = body.parent?.thisOrAncestorOfType<FunctionBody>()
    ) {
      final function = body.parent ?? body;
      if (function.offset <= at && at < function.end) {
        final writes = _closureWrites[body] ??=
            (_ClosureWrites()
                  ..depth = -1
                  ..visitFunctionBody(body))
                .found;
        return writes.contains(variable);
      }
    }
    return false;
  }
}

/// The local variables a function in a body assigns.
final class _ClosureWrites extends RecursiveAstVisitor<void> {
  final found = <Element>{};
  var depth = 0;

  void visitFunctionBody(FunctionBody node) {
    depth++;
    node.visitChildren(this);
    depth--;
  }

  @override
  void visitBlockFunctionBody(BlockFunctionBody node) =>
      visitFunctionBody(node);

  @override
  void visitExpressionFunctionBody(ExpressionFunctionBody node) =>
      visitFunctionBody(node);

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    final variable = node.writeElement;
    if (depth > 0 && variable != null) {
      found.add(variable);
    }
    super.visitAssignmentExpression(node);
  }
}

const _await = 1;
const _callback = 2;

const _futureCallbacks = {'then', 'catchError', 'whenComplete'};

/// The gap [body] starts with: [_callback] for a callback of a `Future`.
int _entryGap(FunctionBody body) {
  final function = body.parent;
  if (function is! FunctionExpression) {
    return 0;
  }
  final callee = switch (function.parent) {
    ArgumentList(parent: final p) => p,
    NamedArgument(parent: ArgumentList(parent: final p)) => p,
    _ => null,
  };
  final isCallback = switch (callee) {
    MethodInvocation(:final methodName, :final realTarget?) =>
      _futureCallbacks.contains(methodName.name) &&
          (realTarget.staticType?.isDartAsyncFuture ?? false),
    InstanceCreationExpression(:final constructorName) =>
      (constructorName.type.type?.isDartAsyncFuture ?? false) &&
          constructorName.name?.name == 'delayed',
    _ => false,
  };
  return isCallback ? _callback : 0;
}

/// Whether [e] reads `mounted`, of the state or of a context.
bool isMountedRead(Expression e) {
  final name = switch (e) {
    SimpleIdentifier() => e,
    PrefixedIdentifier(:final identifier) => identifier,
    PropertyAccess(:final propertyName) => propertyName,
    _ => null,
  };
  return name != null && name.name == 'mounted';
}

/// What holds on one path at one point: the gaps passed since `mounted`
/// was last checked, and the local variables assigned since the last gap.
final class _Flow {
  const _Flow(this.gaps, this.fresh);

  static const checked = _Flow(0, <Element>{});

  final int gaps;
  final Set<Element> fresh;

  /// This flow after a gap of [bits].
  _Flow after(int bits) => _Flow(gaps | bits, const <Element>{});

  /// This flow with [variable] assigned.
  _Flow assigned(Element variable) => gaps == 0 || fresh.contains(variable)
      ? this
      : _Flow(gaps, {...fresh, variable});

  /// The gaps a read of [element] passes.
  int gapsOf(Element? element) =>
      (element is LocalVariableElement || element is FormalParameterElement) &&
          fresh.contains(element)
      ? 0
      : gaps;

  bool same(_Flow other) =>
      gaps == other.gaps &&
      fresh.length == other.fresh.length &&
      fresh.containsAll(other.fresh);
}

/// Either of two paths; null is a path that does not get there.
_Flow? _join(_Flow? a, _Flow? b) {
  if (a == null || b == null) {
    return a ?? b;
  }
  if (a.gaps == 0) {
    return b;
  }
  if (b.gaps == 0) {
    return a;
  }
  return _Flow(a.gaps | b.gaps, a.fresh.intersection(b.fresh));
}

bool _same(_Flow? a, _Flow? b) =>
    a == null ? b == null : b != null && a.same(b);

/// Follows a body's statements and expressions in the order they run,
/// with [s] the flow at the current point (null where it is unreachable).
final class _Walker extends RecursiveAstVisitor<void> {
  _Walker(this.flow);

  final MountedFlow flow;
  _Flow? s;

  /// The flows that break out of, and continue, each statement.
  final _breaks = <AstNode, _Flow?>{};
  final _continues = <AstNode, _Flow?>{};

  /// The flows where [e] is true and where it is false.
  (_Flow?, _Flow?) _condition(Expression e) {
    switch (e) {
      case ParenthesizedExpression(:final expression):
        return _condition(expression);
      case PrefixExpression(
        operator: Token(type: TokenType.BANG),
        :final operand,
      ):
        final (t, f) = _condition(operand);
        return (f, t);
      case BinaryExpression(
        operator: Token(type: TokenType.AMPERSAND_AMPERSAND),
      ):
        final (lt, lf) = _condition(e.leftOperand);
        s = lt;
        final (rt, rf) = _condition(e.rightOperand);
        return (rt, _join(lf, rf));
      case BinaryExpression(operator: Token(type: TokenType.BAR_BAR)):
        final (lt, lf) = _condition(e.leftOperand);
        s = lf;
        final (rt, rf) = _condition(e.rightOperand);
        return (_join(lt, rt), rf);
      default:
        e.accept(this);
        if (isMountedRead(e)) {
          return (s == null ? null : _Flow.checked, s);
        }
        return (s, s);
    }
  }

  /// [s] joined with what breaks out of [node].
  void _joinBreaks(AstNode node) {
    s = _join(s, _breaks.remove(node));
  }

  /// Follows a loop round until the flow at its start stays the same:
  /// [round] goes once round from [s], which is its start, leaving [s]
  /// where the next round starts, and returns the flow that leaves it.
  void _loop(AstNode node, _Flow? Function() round) {
    final entry = s;
    var head = entry;
    _Flow? exit;
    for (var i = 0; i < 16; i++) {
      s = head;
      exit = round();
      final next = _join(entry, s);
      if (_same(next, head)) {
        break;
      }
      head = next;
    }
    s = exit;
    _joinBreaks(node);
    _continues.remove(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final at = s;
    if (at != null) {
      flow._record(node, at.gapsOf(node.element));
    }
  }

  @override
  void visitAwaitExpression(AwaitExpression node) {
    node.expression.accept(this);
    s = s?.after(_await);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    switch (node.operator.type) {
      case TokenType.AMPERSAND_AMPERSAND || TokenType.BAR_BAR:
        final (t, f) = _condition(node);
        s = _join(t, f);
      case TokenType.QUESTION_QUESTION:
        node.leftOperand.accept(this);
        final before = s;
        node.rightOperand.accept(this);
        s = _join(before, s);
      default:
        super.visitBinaryExpression(node);
    }
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    if (node.operator.type == TokenType.BANG) {
      final (t, f) = _condition(node);
      s = _join(t, f);
    } else {
      super.visitPrefixExpression(node);
    }
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    final (t, f) = _condition(node.condition);
    s = t;
    node.thenExpression.accept(this);
    final then = s;
    s = f;
    node.elseExpression.accept(this);
    s = _join(then, s);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    node.leftHandSide.accept(this);
    if (node.operator.type == TokenType.QUESTION_QUESTION_EQ) {
      final before = s;
      node.rightHandSide.accept(this);
      s = _join(before, s);
    } else {
      node.rightHandSide.accept(this);
    }
    final variable = node.writeElement;
    if (variable is LocalVariableElement ||
        variable is FormalParameterElement) {
      s = s?.assigned(variable!);
    }
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    node.initializer?.accept(this);
    final variable = node.declaredFragment?.element;
    if (node.initializer != null && variable != null) {
      s = s?.assigned(variable);
    }
  }

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    final variable = node.declaredFragment?.element;
    if (variable != null) {
      s = s?.assigned(variable);
    }
  }

  @override
  void visitThrowExpression(ThrowExpression node) {
    node.expression.accept(this);
    s = null;
  }

  @override
  void visitRethrowExpression(RethrowExpression node) {
    s = null;
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  @override
  void visitFunctionDeclarationStatement(FunctionDeclarationStatement node) {}

  @override
  void visitAssertStatement(AssertStatement node) {}

  @override
  void visitIfElement(IfElement node) {
    final (t, f) = _ifCondition(node.expression, node.caseClause);
    s = t;
    node.thenElement.accept(this);
    final then = s;
    s = f;
    node.elseElement?.accept(this);
    s = _join(then, s);
  }

  @override
  void visitForElement(ForElement node) {
    _forLoopParts(node, node.forLoopParts, node.awaitKeyword != null, () {
      node.body.accept(this);
    });
  }

  @override
  void visitSwitchExpression(SwitchExpression node) {
    node.expression.accept(this);
    final entry = s;
    _Flow? out;
    for (final c in node.cases) {
      s = entry;
      final (t, _) = _caseClause(c.guardedPattern);
      s = t;
      c.expression.accept(this);
      out = _join(out, s);
    }
    s = out;
  }

  // statements

  @override
  void visitIfStatement(IfStatement node) {
    final (t, f) = _ifCondition(node.expression, node.caseClause);
    s = t;
    node.thenStatement.accept(this);
    final then = s;
    s = f;
    node.elseStatement?.accept(this);
    s = _join(then, s);
  }

  /// The flows where an `if`'s condition holds and where it does not.
  (_Flow?, _Flow?) _ifCondition(Expression expression, CaseClause? clause) {
    if (clause == null) {
      return _condition(expression);
    }
    expression.accept(this);
    final before = s;
    final (t, f) = _caseClause(clause.guardedPattern);
    return (t, _join(before, f));
  }

  /// The flows where a case's pattern and guard match, and where its
  /// guard does not.
  (_Flow?, _Flow?) _caseClause(GuardedPattern pattern) {
    pattern.pattern.accept(this);
    final guard = pattern.whenClause?.expression;
    return guard == null ? (s, s) : _condition(guard);
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    node.expression?.accept(this);
    s = null;
  }

  @override
  void visitBreakStatement(BreakStatement node) {
    final target = node.target;
    if (target != null) {
      _breaks[target] = _join(_breaks[target], s);
    }
    s = null;
  }

  @override
  void visitContinueStatement(ContinueStatement node) {
    final target = node.target;
    if (target != null) {
      _continues[target] = _join(_continues[target], s);
    }
    s = null;
  }

  @override
  void visitLabeledStatement(LabeledStatement node) {
    node.statement.accept(this);
    _joinBreaks(node);
  }

  @override
  void visitBlock(Block node) {
    super.visitBlock(node);
    _joinBreaks(node);
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    _loop(node, () {
      final (t, f) = _condition(node.condition);
      s = t;
      node.body.accept(this);
      s = _join(s, _continues[node]);
      return f;
    });
  }

  @override
  void visitDoStatement(DoStatement node) {
    _loop(node, () {
      node.body.accept(this);
      s = _join(s, _continues[node]);
      final (t, f) = _condition(node.condition);
      s = t;
      return f;
    });
  }

  @override
  void visitForStatement(ForStatement node) {
    _forLoopParts(node, node.forLoopParts, node.awaitKeyword != null, () {
      node.body.accept(this);
      s = _join(s, _continues[node]);
    });
  }

  /// Follows a `for` statement or element, [body] being its body.
  void _forLoopParts(
    AstNode node,
    ForLoopParts parts,
    bool isAwait,
    void Function() body,
  ) {
    switch (parts) {
      case ForParts(:final condition, :final updaters):
        switch (parts) {
          case ForPartsWithDeclarations(:final variables):
            variables.accept(this);
          case ForPartsWithExpression(:final initialization):
            initialization?.accept(this);
          case ForPartsWithPattern(:final variables):
            variables.accept(this);
        }
        _loop(node, () {
          final (_Flow? t, _Flow? f) = condition == null
              ? (s, null)
              : _condition(condition);
          s = t;
          body();
          updaters.accept(this);
          return f;
        });
      case ForEachParts(:final iterable):
        iterable.accept(this);
        _loop(node, () {
          // the loop ends where the next element would be taken
          if (isAwait) {
            s = s?.after(_await);
          }
          final exit = s;
          switch (parts) {
            case ForEachPartsWithDeclaration(:final loopVariable):
              final variable = loopVariable.declaredFragment?.element;
              if (variable != null) {
                s = s?.assigned(variable);
              }
            case ForEachPartsWithIdentifier(:final identifier):
              final variable = identifier.element;
              if (variable is LocalVariableElement ||
                  variable is FormalParameterElement) {
                s = s?.assigned(variable!);
              }
            case ForEachPartsWithPattern(:final pattern):
              pattern.accept(this);
          }
          body();
          return exit;
        });
    }
  }

  @override
  void visitSwitchStatement(SwitchStatement node) {
    node.expression.accept(this);
    final entry = s;
    _Flow? out;
    var exhaustive = false;
    final members = node.members;
    for (final member in members) {
      // an empty case runs into the next one, from the same flow
      s = entry;
      switch (member) {
        case SwitchPatternCase(:final guardedPattern):
          final (t, _) = _caseClause(guardedPattern);
          s = t;
        case SwitchCase(:final expression):
          expression.accept(this);
        case SwitchDefault():
          exhaustive = true;
      }
      member.statements.accept(this);
      if (member.statements.isNotEmpty || identical(member, members.last)) {
        out = _join(out, s);
      }
    }
    s = exhaustive ? out : _join(out, entry);
    _joinBreaks(node);
  }

  @override
  void visitTryStatement(TryStatement node) {
    final entry = s;
    final awaits = _Awaits();
    node.body.accept(awaits);
    node.body.accept(this);
    final afterBody = s;
    // a catch may start anywhere in the body
    final caught = _join(
      _join(entry, afterBody),
      awaits.found ? entry?.after(_await) : null,
    );
    var out = afterBody;
    for (final clause in node.catchClauses) {
      s = caught;
      clause.body.accept(this);
      out = _join(out, s);
    }
    final finallyBlock = node.finallyBlock;
    if (finallyBlock != null) {
      s = _join(out, caught);
      finallyBlock.accept(this);
      if (out == null) {
        s = null;
      }
    } else {
      s = out;
    }
  }

  @override
  void visitYieldStatement(YieldStatement node) {
    node.expression.accept(this);
  }
}

/// Whether there is an `await` in a node, not in the functions in it.
final class _Awaits extends RecursiveAstVisitor<void> {
  var found = false;

  @override
  void visitAwaitExpression(AwaitExpression node) => found = true;

  @override
  void visitForStatement(ForStatement node) {
    if (node.awaitKeyword != null) {
      found = true;
    }
    super.visitForStatement(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  @override
  void visitFunctionDeclarationStatement(FunctionDeclarationStatement node) {}
}
