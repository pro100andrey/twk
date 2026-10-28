/// The fix of `unnamed_control`: [AddSemanticsLabel].
library;

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

/// Gives the control reported `semanticsLabel: ''`, the cursor between
/// the quotes for the name to be typed: before its first argument, or in
/// place of the `null` or `''` it has.
///
/// Not offered where the constructor takes no `semanticsLabel`, as a
/// `Button` does not.
final class AddSemanticsLabel extends ResolvedCorrectionProducer {
  /// The fix, in the [context] of a diagnostic.
  AddSemanticsLabel({required super.context});

  /// What the fix is called: `Add 'semanticsLabel'`.
  static const kind = FixKind(
    'twk.fix.addSemanticsLabel',
    DartFixKindPriority.standard,
    "Add 'semanticsLabel'",
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final control = node.thisOrAncestorOfType<InstanceCreationExpression>();
    final takes =
        control?.constructorName.element?.formalParameters.any(
          (p) => p.isNamed && p.name == 'semanticsLabel',
        ) ??
        false;
    if (control == null || !takes) {
      return;
    }
    final arguments = control.argumentList;
    final given = arguments.arguments
        .whereType<NamedArgument>()
        .where((a) => a.name.lexeme == 'semanticsLabel')
        .firstOrNull;
    await builder.addDartFileEdit(file, (builder) {
      if (given != null) {
        builder.addReplacement(given.argumentExpression.sourceRange, (
          builder,
        ) {
          builder
            ..write("'")
            ..selectHere()
            ..write("'");
        });
        return;
      }
      final first = arguments.arguments.firstOrNull;
      final at = first?.offset ?? arguments.leftParenthesis.end;
      builder.addInsertion(at, (builder) {
        builder
          ..write("semanticsLabel: '")
          ..selectHere()
          ..write("'");
        if (first != null) {
          final ownLine =
              utils.getLineThis(first.offset) !=
              utils.getLineThis(arguments.leftParenthesis.offset);
          builder.write(
            ownLine ? ',${utils.endOfLine}${utils.getLinePrefix(at)}' : ', ',
          );
        }
      });
    });
  }
}
