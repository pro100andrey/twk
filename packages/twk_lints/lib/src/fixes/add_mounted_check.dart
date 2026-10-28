/// The fix of `set_state_after_dispose` after a gap and of
/// `context_after_await`: [AddMountedCheck].
library;

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

import '../rules/context_after_await.dart';

/// Inserts `if (!mounted) return;` — `if (!name.mounted) return;` for a
/// context in a variable — on a line of its own before the statement of
/// the `setState` or context reported.
///
/// Not offered where `return;` would not compile (a function that returns
/// a value) or where the statement is not in a block (an arrow function's
/// body, an `if` without braces).
final class AddMountedCheck extends ResolvedCorrectionProducer {
  /// The fix, in the [context] of a diagnostic.
  AddMountedCheck({required super.context});

  /// What the fix is called: `Add 'if (!mounted) return;'`.
  static const kind = FixKind(
    'twk.fix.addMountedCheck',
    DartFixKindPriority.standard,
    "Add 'if (!{0}) return;'",
  );

  var _check = 'mounted';

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => kind;

  @override
  List<String> get fixArguments => [_check];

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final use = node;
    if (use is! SimpleIdentifier) {
      return;
    }
    _check = mountedCheckFor(use) ?? 'mounted';
    final body = use.thisOrAncestorOfType<FunctionBody>();
    if (body == null || !_returnsNothing(body)) {
      return;
    }
    AstNode? statement = use;
    while (statement != null &&
        !identical(statement, body) &&
        !(statement is Statement && statement.parent is Block)) {
      statement = statement.parent;
    }
    if (statement is! Statement) {
      return;
    }
    final at = statement.offset;
    final text =
        'if (!$_check) return;${utils.endOfLine}'
        '${utils.getLinePrefix(at)}';
    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleInsertion(at, text);
    });
  }

  /// Whether a plain `return;` compiles in [body].
  bool _returnsNothing(FunctionBody body) {
    if (body.isGenerator) {
      return true;
    }
    final type = switch (body.parent) {
      FunctionExpression(:final declaredFragment?) =>
        declaredFragment.element.returnType,
      MethodDeclaration(:final declaredFragment?) =>
        declaredFragment.element.returnType,
      _ => null,
    };
    if (type == null) {
      return false;
    }
    var value = type;
    if (body.isAsynchronous &&
        value is InterfaceType &&
        (value.isDartAsyncFuture || value.isDartAsyncFutureOr)) {
      value = value.typeArguments.single;
    }
    return value is VoidType || value is DynamicType || value.isDartCoreNull;
  }
}
