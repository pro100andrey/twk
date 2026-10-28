/// The lint of a test that waits on the wall clock: [WallTimeInTests].
library;

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import '../test_directory.dart';
import '../twk_types.dart';

/// A wait on the wall clock in a file under a package's `test/`: a
/// `Future.delayed` of a duration that is not the constant zero, a
/// `sleep`, a `Timer` of such a duration, a `Timer.periodic` or a
/// `Stream.periodic`. A test that waits a fixed time for a frame, a
/// timer or another process guesses how long is long enough, and on a
/// loaded machine the guess is wrong.
///
/// ```dart-nocheck
/// testTwk('the spinner turns', (t) async {
///   await t.pumpWidget(const Spinner());
///   await Future<void>.delayed(const Duration(milliseconds: 100)); // reported
/// });
/// ```
///
/// The tester's clock is a fake one, which the test moves:
///
/// ```dart-nocheck
/// testTwk('the spinner turns', (t) async {
///   await t.pumpWidget(const Spinner());
///   await t.pump(const Duration(milliseconds: 100));
/// });
/// ```
///
/// Not reported, as their timers are on a fake clock wherever the tester
/// runs them: timers made in a function written in place as the argument
/// of twk_test's `FakeClock.run` or `TwkTester.act`; and app code, its
/// timers on the clock the app runs on — a member of a twk `State`, or a
/// function written in place in the arguments of a widget (a callback the
/// app calls). A `sleep` stops the isolate on any clock, and is reported
/// there too. Nor in a program the tests start (a library with a `main`
/// in a file not named `_test.dart`), whose time is real: the test awaits
/// what it does.
final class WallTimeInTests extends AnalysisRule {
  /// The rule, named `wall_time_in_tests`, a lint.
  WallTimeInTests()
    : super(
        name: 'wall_time_in_tests',
        description: "Don't wait on the wall clock in a test.",
      );

  /// What it reports: what waits (`Future.delayed`, `sleep`, `Timer`,
  /// `Timer.periodic`, `Stream.periodic`).
  static const code = LintCode(
    'wall_time_in_tests',
    "'{0}' waits on the wall clock in a test.",
    correctionMessage:
        "Try the tester's 'pump' or a FakeClock's 'elapse' for an app or a "
        "timer, 'elapseUntil' for a future on that clock, and twk_test's "
        "'waitFor' or 'waitUntil' for what a real process, socket or file "
        'does.',
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (!inTestDirectory(context) || _isProgram(context)) {
      return;
    }
    final visitor = _Visitor(this);
    registry
      ..addInstanceCreationExpression(this, visitor)
      ..addMethodInvocation(this, visitor);
  }
}

/// Whether the library is a program the tests start: it declares `main`
/// and its file is not a test's.
bool _isProgram(RuleContext context) {
  final path = context.definingUnit.file.path;
  if (path.endsWith('_test.dart')) {
    return false;
  }
  return context.definingUnit.unit.declarations.any(
    (d) => d is FunctionDeclaration && d.name.lexeme == 'main',
  );
}

final class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final WallTimeInTests rule;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final constructor = node.constructorName.element;
    final owner = constructor?.enclosingElement;
    if (owner == null || !owner.library.isDartAsync) {
      return;
    }
    final arguments = node.argumentList.arguments;
    final what = switch ((owner.name, constructor!.name)) {
      ('Future', 'delayed')
          when !_zero(arguments.firstOrNull?.argumentExpression) =>
        'Future.delayed',
      ('Timer', 'new') when !_zero(arguments.firstOrNull?.argumentExpression) =>
        'Timer',
      ('Timer', 'periodic') => 'Timer.periodic',
      ('Stream', 'periodic') => 'Stream.periodic',
      _ => null,
    };
    if (what != null && !_onFakeClock(node)) {
      rule.reportAtNode(node.constructorName, arguments: [what]);
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final function = node.methodName.element;
    if (function is TopLevelFunctionElement &&
        function.name == 'sleep' &&
        function.library.uri.toString() == 'dart:io' &&
        !_zero(node.argumentList.arguments.firstOrNull?.argumentExpression)) {
      rule.reportAtNode(node.methodName, arguments: ['sleep']);
    }
  }
}

/// Whether [duration] is a constant `Duration` of zero.
bool _zero(Expression? duration) {
  final value = duration?.computeConstantValue()?.value;
  final microseconds =
      value?.getField('inMicroseconds') ?? value?.getField('_duration');
  return microseconds?.toIntValue() == 0;
}

/// Whether the timer [node] makes is on a fake clock: made in a function
/// written in place as the argument of `FakeClock.run` or
/// `TwkTester.act`, or in app code.
bool _onFakeClock(AstNode node) {
  var inFunction = false;
  var child = node;
  for (var parent = node.parent; parent != null; parent = parent.parent) {
    switch (parent) {
      case FunctionExpression():
        inFunction = true;
      case ClassDeclaration() when isStateClass(classElementOf(parent)):
        return true;
      case MethodInvocation(:final argumentList)
          when inFunction &&
              identical(child, argumentList) &&
              (_runsInClockZone(parent) || isWidgetType(parent.staticType)):
        return true;
      case InstanceCreationExpression(:final argumentList)
          when inFunction &&
              identical(child, argumentList) &&
              isWidgetType(parent.staticType):
        return true;
    }
    child = parent;
  }
  return false;
}

/// Whether [node] is twk_test's `FakeClock.run` or `TwkTester.act`, which
/// run their argument in the fake clock's zone.
bool _runsInClockZone(MethodInvocation node) {
  final method = node.methodName.element;
  final owner = method?.enclosingElement;
  return owner is InterfaceElement &&
      isFromPackage(owner, 'twk_test') &&
      switch ((owner.name, method!.name)) {
        ('FakeClock', 'run') || ('TwkTester', 'act') => true,
        _ => false,
      };
}
