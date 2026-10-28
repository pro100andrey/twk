/// The lint of a `Table` whose row type is inferred loosely:
/// [UntypedTable].
library;

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import '../twk_types.dart';

/// A twk `Table` without its type argument whose row type is inferred as
/// `dynamic`, `Object`, `Never` or a nullable type: the columns then
/// read their rows loosely typed (`(row) => row.name` a dynamic call)
/// where a typo is found only when the table is shown.
///
/// ```dart-nocheck
/// Table(
///   rows: todos,
///   columns: [TableColumn(cell: (todo) => Text(todo.title))], // reported
/// )
/// ```
///
/// With the row type the rule asks for:
///
/// ```dart-nocheck
/// Table<Todo>(
///   rows: todos,
///   columns: [TableColumn(cell: (todo) => Text(todo.title))],
/// )
/// ```
final class UntypedTable extends AnalysisRule {
  /// The rule, named `untyped_table`, a lint.
  UntypedTable()
    : super(
        name: 'untyped_table',
        description: 'Give a Table its row type where inference cannot.',
      );

  /// What it reports: the row type inferred.
  static const code = LintCode(
    'untyped_table',
    "The row type of this Table is inferred as '{0}'.",
    correctionMessage: "Try writing the row type: 'Table<Row>(...)'.",
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

  final UntypedTable rule;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type;
    if (type.typeArguments != null || !isTwkClass(type.element, 'Table')) {
      return;
    }
    final table = node.staticType;
    if (table is! InterfaceType || table.typeArguments.length != 1) {
      return;
    }
    final row = table.typeArguments.single;
    final loose =
        row is DynamicType ||
        row is NeverType ||
        row.isDartCoreObject ||
        row.nullabilitySuffix == NullabilitySuffix.question;
    if (loose && row is! InvalidType) {
      rule.reportAtNode(
        node.constructorName,
        arguments: [row.getDisplayString()],
      );
    }
  }
}
