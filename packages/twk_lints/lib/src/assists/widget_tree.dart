/// What the assists that edit the widget tree share: the widget created at
/// the cursor, its `child` argument, the type the place it is in takes,
/// and the text of a node with the comments on the lines above it.
library;

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/type.dart';

import '../twk_types.dart';

/// The creation of a widget at [node]: as [widgetExpressionAt] finds it,
/// when it is an instance creation; else null.
InstanceCreationExpression? widgetCreationAt(AstNode? node) =>
    switch (widgetExpressionAt(node)) {
      final InstanceCreationExpression creation => creation,
      _ => null,
    };

/// The argument named [name] of [creation], if it is given one.
NamedArgument? namedArgument(
  InstanceCreationExpression creation,
  String name,
) => creation.argumentList.arguments
    .whereType<NamedArgument>()
    .where((a) => a.name.lexeme == name)
    .firstOrNull;

/// The `child:` argument of [creation] whose value is a widget created in
/// place that has a `child:` argument of its own: the pair a swap changes
/// round, as (the argument, the child).
(NamedArgument, InstanceCreationExpression)? swappableChild(
  InstanceCreationExpression creation,
) {
  final argument = namedArgument(creation, 'child');
  final child = argument?.argumentExpression;
  if (argument == null ||
      child is! InstanceCreationExpression ||
      !isWidgetType(child.staticType) ||
      namedArgument(child, 'child') == null) {
    return null;
  }
  return (argument, child);
}

/// The type of the elements of [list], if resolved.
DartType? listElementType(ListLiteral list) => switch (list.staticType) {
  InterfaceType(typeArguments: [final type]) => type,
  _ => null,
};

/// The type of [argument]'s parameter, if resolved.
DartType? parameterType(NamedArgument argument) =>
    argument.correspondingParameter?.type;

/// What the assists that edit the widget tree ask of the file they edit.
extension WidgetTreeEdits on ResolvedCorrectionProducer {
  /// The type the place [expression] is in takes: the element type of the
  /// list it is an element of (also through `if` and `for` elements), the
  /// parameter it is the argument of, the type a function returns or a
  /// variable is declared; null where unknown.
  DartType? slotType(Expression expression) {
    AstNode element = expression;
    var parent = expression.parent;
    while (parent is IfElement || parent is ForElement) {
      element = parent!;
      parent = parent.parent;
    }
    if (parent is ListLiteral) {
      return listElementType(parent);
    }
    if (!identical(element, expression)) {
      return null;
    }
    final type = inferUndefinedExpressionType(expression);
    return type is InvalidType ? null : type;
  }

  /// Whether a value of [type] may be put where [slot] is taken.
  bool fits(DartType? type, DartType? slot) =>
      type != null && slot != null && typeSystem.isAssignableTo(type, slot);

  /// Where [node] starts with the comments on lines of their own just
  /// before it, which belong to it (a comment after the end of the line
  /// before belongs to that line).
  int startWithComments(AstNode node) {
    final lines = unitResult.lineInfo;
    for (
      Token? comment = node.beginToken.precedingComments;
      comment != null;
      comment = comment.next
    ) {
      final line = lines.getLocation(comment.offset).lineNumber - 1;
      if (utils.getLineContentStart(comment.offset) ==
          lines.getOffsetOfLine(line)) {
        return comment.offset;
      }
    }
    return node.offset;
  }

  /// [text], whose lines after its first are indented as from [from],
  /// indented as from [to] instead.
  String reindent(String text, String from, String to) =>
      from == to ? text : utils.replaceSourceIndent(text, from, to);

  /// The text of the file from [start] to [end].
  String textOf(int start, int end) => unitResult.content.substring(start, end);
}
