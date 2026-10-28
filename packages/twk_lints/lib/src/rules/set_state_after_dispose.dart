/// The warning of a `setState` that may run after `dispose`:
/// [SetStateAfterDispose].
library;

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import '../mounted_flow.dart';
import '../twk_types.dart';

/// A `setState` of a twk `State` that may run once the state was
/// disposed, which fails an assert: in `dispose`, after an `await`, or in
/// a callback of a `Future` (`then`, `catchError`, `whenComplete`,
/// `Future.delayed`), with no check of `mounted` since.
///
/// A check is a read of `mounted` (or `context.mounted`) that holds on
/// every path from the last gap to the call: `if (mounted)` around it,
/// `if (!mounted) return;` before it, or such a check in each branch of an
/// `if` that awaited. The paths are [MountedFlow]'s.
///
/// ```dart-nocheck
/// Future<void> _load() async {
///   final items = await fetchItems();
///   setState(() => _items = items); // reported: after an await
/// }
/// ```
///
/// With the check the rule asks for:
///
/// ```dart-nocheck
/// Future<void> _load() async {
///   final items = await fetchItems();
///   if (!mounted) return;
///   setState(() => _items = items);
/// }
/// ```
final class SetStateAfterDispose extends MultiAnalysisRule {
  /// The rule, named `set_state_after_dispose`, a warning.
  SetStateAfterDispose()
    : super(
        name: 'set_state_after_dispose',
        description:
            "Don't call setState where the State may have been disposed.",
      );

  /// What it reports of a `setState` in `dispose`.
  static const inDispose = LintCode(
    'set_state_after_dispose',
    "'setState' is called in 'dispose'.",
    correctionMessage: "Try changing the fields without 'setState'.",
    uniqueName: 'set_state_after_dispose_in_dispose',
    severity: DiagnosticSeverity.WARNING,
  );

  /// What it reports of a `setState` after a gap: the `await` or the
  /// callback it follows.
  static const afterAwait = LintCode(
    'set_state_after_dispose',
    "'setState' may run after 'dispose': {0}, with no check of 'mounted'.",
    correctionMessage: "Try 'if (!mounted) return;' before it.",
    uniqueName: 'set_state_after_dispose_after_gap',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  List<DiagnosticCode> get diagnosticCodes => [inDispose, afterAwait];

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addMethodInvocation(this, _Visitor(this));
  }
}

final class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final SetStateAfterDispose rule;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name != 'setState' ||
        (node.target != null && node.target is! ThisExpression)) {
      return;
    }
    final method = node.methodName.element;
    if (method is! MethodElement ||
        !isTwkClass(method.enclosingElement, 'State')) {
      return;
    }
    final member = node.thisOrAncestorOfType<MethodDeclaration>();
    if (member != null &&
        member.name.lexeme == 'dispose' &&
        member.parent?.parent is ClassDeclaration) {
      rule.reportAtNode(
        node.methodName,
        diagnosticCode: SetStateAfterDispose.inDispose,
      );
      return;
    }
    final body = node.thisOrAncestorOfType<FunctionBody>();
    if (body == null) {
      return;
    }
    final gap = MountedFlow.of(body).gapAt(node.methodName);
    if (gap == null) {
      return;
    }
    rule.reportAtNode(
      node.methodName,
      diagnosticCode: SetStateAfterDispose.afterAwait,
      arguments: [gap.why],
    );
  }
}
