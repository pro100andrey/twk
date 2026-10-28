/// The fix of `wall_time_in_tests`: [ElapseFakeClock].
library;

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../rules/wall_time_in_tests.dart';
import '../twk_types.dart';

/// Moves the test's fake clock instead of waiting on the wall clock:
/// `await Future<void>.delayed(d)` becomes `await clock.elapse(d)`,
/// `clock` the one twk_test `FakeClock` the code names in scope.
///
/// Offered only for an awaited `Future.delayed` of a duration alone (no
/// computation), where exactly one variable or parameter of type
/// `FakeClock` is in scope there: a local declared before it in a block
/// around it, a parameter of a function around it, or a top-level
/// variable. Not for a `TwkTester`'s clock, where `pump`, which also
/// draws a frame, may be what is meant; nor for `sleep`, a `Timer` or a
/// periodic, which a clock's `elapse` does not stand for one to one.
final class ElapseFakeClock extends ResolvedCorrectionProducer {
  /// The fix, in the [context] of a diagnostic.
  ElapseFakeClock({required super.context});

  /// What the fix is called: `Use 'clock.elapse'`.
  static const kind = FixKind(
    'twk.fix.elapseFakeClock',
    DartFixKindPriority.standard,
    "Use '{0}.elapse'",
  );

  /// What the fix of every such wait of a file is called.
  static const multiKind = FixKind(
    'twk.fix.elapseFakeClock.multi',
    DartFixKindPriority.inFile,
    "Use the fake clock's 'elapse' for each wait",
  );

  var _clock = 'clock';

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.acrossFiles;

  @override
  FixKind get fixKind => kind;

  @override
  FixKind get multiFixKind => multiKind;

  @override
  List<String> get fixArguments => [_clock];

  @override
  Future<void> compute(ChangeBuilder builder) async {
    // fixing a file, the server runs the fix on every diagnostic of it
    if (diagnostic?.diagnosticCode != WallTimeInTests.code) {
      return;
    }
    final delayed = node.thisOrAncestorOfType<InstanceCreationExpression>();
    final constructor = delayed?.constructorName.element;
    final owner = constructor?.enclosingElement;
    if (delayed == null ||
        delayed.parent is! AwaitExpression ||
        owner == null ||
        !owner.library.isDartAsync ||
        owner.name != 'Future' ||
        constructor!.name != 'delayed') {
      return;
    }
    final arguments = delayed.argumentList.arguments;
    if (arguments case [final duration] when duration is! NamedArgument) {
      final clocks = _clocksInScope(delayed);
      if (clocks.length != 1) {
        return;
      }
      _clock = clocks.single.displayName;
      await builder.addDartFileEdit(file, (builder) {
        builder
          ..addSimpleReplacement(
            range.startStart(delayed, duration),
            '$_clock.elapse(',
          )
          ..addSimpleReplacement(
            range.endEnd(duration, delayed),
            ')',
          );
      });
    }
  }

  /// The variables and parameters of type `FakeClock` in scope at [at].
  Set<Element> _clocksInScope(AstNode at) {
    final found = <Element>{};
    void add(Element? element) {
      final type = switch (element) {
        VariableElement(:final type) => type,
        _ => null,
      };
      if (type is InterfaceType &&
          typeSystem.isNonNullable(type) &&
          type.element.name == 'FakeClock' &&
          isFromPackage(type.element, 'twk_test')) {
        found.add(element!);
      }
    }

    var child = at;
    for (var parent = at.parent; parent != null; parent = parent.parent) {
      switch (parent) {
        case Block(:final statements):
          for (final statement in statements) {
            if (identical(statement, child)) {
              break;
            }
            if (statement is VariableDeclarationStatement) {
              for (final v in statement.variables.variables) {
                add(v.declaredFragment?.element);
              }
            }
          }
        case FunctionExpression(:final parameters?):
          for (final p in parameters.parameters) {
            add(p.declaredFragment?.element);
          }
        case MethodDeclaration(:final parameters?):
          for (final p in parameters.parameters) {
            add(p.declaredFragment?.element);
          }
        case CompilationUnit(:final declarations):
          for (final d in declarations) {
            if (d is TopLevelVariableDeclaration) {
              for (final v in d.variables.variables) {
                add(v.declaredFragment?.element);
              }
            }
          }
      }
      child = parent;
    }
    return found;
  }
}
