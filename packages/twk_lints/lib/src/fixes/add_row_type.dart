/// The fix of `untyped_table`: [AddRowType].
library;

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

import '../rules/untyped_table.dart';

/// Writes the element type of the table's `rows:` as its type argument:
/// `Table(rows: todos, ...)` of a `List<Todo>` becomes
/// `Table<Todo>(rows: todos, ...)`, an import added where the type's
/// library is not imported.
///
/// Offered only where that type is one [UntypedTable] would not report
/// (not `dynamic`, `Object`, `Never` or nullable) and can be named here:
/// a class, enum or the like with its type arguments, or a type
/// parameter in scope; not a private type of another library, a
/// function type or a record.
final class AddRowType extends ResolvedCorrectionProducer {
  /// The fix, in the [context] of a diagnostic.
  AddRowType({required super.context});

  /// What the fix is called: `Write the row type 'Todo'`.
  static const kind = FixKind(
    'twk.fix.addRowType',
    DartFixKindPriority.standard,
    "Write the row type '{0}'",
  );

  /// What the fix of every such table of a file is called.
  static const multiKind = FixKind(
    'twk.fix.addRowType.multi',
    DartFixKindPriority.inFile,
    'Write the row type of each table',
  );

  var _row = 'Row';

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.acrossFiles;

  @override
  FixKind get fixKind => kind;

  @override
  FixKind get multiFixKind => multiKind;

  @override
  List<String> get fixArguments => [_row];

  @override
  Future<void> compute(ChangeBuilder builder) async {
    // fixing a file, the server runs the fix on every diagnostic of it
    if (diagnostic?.diagnosticCode != UntypedTable.code) {
      return;
    }
    final table = node.thisOrAncestorOfType<InstanceCreationExpression>();
    final rows = table?.argumentList.arguments
        .whereType<NamedArgument>()
        .where((a) => a.name.lexeme == 'rows')
        .firstOrNull
        ?.argumentExpression
        .staticType;
    if (table == null || rows is! InterfaceType) {
      return;
    }
    final list = rows.asInstanceOf(typeProvider.listElement);
    final row = list?.typeArguments.single;
    if (row == null || !_named(row) || !_strict(row)) {
      return;
    }
    _row = row.getDisplayString();
    final type = table.constructorName.type;
    await builder.addDartFileEdit(file, (builder) {
      builder.addInsertion(type.name.end, (builder) {
        builder
          ..write('<')
          ..writeType(row)
          ..write('>');
      });
    });
  }

  /// Whether [type] is one the rule does not report.
  bool _strict(DartType type) =>
      type is! DynamicType &&
      type is! NeverType &&
      !type.isDartCoreObject &&
      typeSystem.isNonNullable(type);

  /// Whether [type] can be written here: an interface type of a name
  /// this library may use, with type arguments that can, or a type
  /// parameter in scope.
  bool _named(DartType type) => switch (type) {
    TypeParameterType(:final element) => _inScope(element),
    InterfaceType(:final element, :final typeArguments) =>
      (!element.isPrivate || element.library == unitResult.libraryElement) &&
          typeArguments.every(
            (t) => t is DynamicType || t is VoidType || _named(t),
          ),
    _ => false,
  };

  bool _inScope(TypeParameterElement element) {
    for (AstNode? n = node; n != null; n = n.parent) {
      final parameters = switch (n) {
        ClassDeclaration(:final namePart) => namePart.typeParameters,
        MethodDeclaration(:final typeParameters) ||
        FunctionExpression(:final typeParameters) => typeParameters,
        _ => null,
      };
      if (parameters != null &&
          parameters.typeParameters.any(
            (p) => p.declaredFragment?.element == element,
          )) {
        return true;
      }
    }
    return false;
  }
}
