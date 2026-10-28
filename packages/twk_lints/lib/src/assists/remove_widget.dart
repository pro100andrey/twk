/// The assist that takes the widget at the cursor out of the tree and
/// leaves what it holds: [RemoveWidget].
library;

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import 'widget_tree.dart';

/// Replaces the widget the cursor is on with its `child`, or, in a list
/// of widgets, with the elements of its `children` list (none, where that
/// is empty); a widget of one `children` element written as a widget
/// outside a list is replaced with it. Offered only where what is left
/// is of a type the place takes: a nullable `child` is not put where a
/// widget is required, a widget of several children not where one is.
///
/// The cursor on `Padding`:
///
/// ```dart-nocheck
/// Box(child: Padding(padding: const EdgeInsets.all(1), child: Text('a')))
/// ```
///
/// becomes:
///
/// ```dart-nocheck
/// Box(child: Text('a'))
/// ```
final class RemoveWidget extends ResolvedCorrectionProducer {
  /// The assist for the request [context] describes.
  RemoveWidget({required super.context});

  /// The assist as the editor lists it: "Remove this widget".
  static const kind = AssistKind(
    'twk.assist.removeWidget',
    DartFixKindPriority.standard,
    'Remove this widget',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  AssistKind get assistKind => kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final widget = widgetCreationAt(node);
    if (widget == null) {
      return;
    }
    final slot = slotType(widget);
    final child = namedArgument(widget, 'child')?.argumentExpression;
    final children = switch (namedArgument(widget, 'children')) {
      NamedArgument(argumentExpression: final ListLiteral list) => list,
      _ => null,
    };
    if (child != null) {
      if (fits(child.staticType, slot)) {
        await _replace(builder, widget, child);
      }
    } else if (children != null) {
      final list = widget.parent;
      if (list is ListLiteral) {
        if (fits(listElementType(children), slot)) {
          await _splice(builder, widget, list, children);
        }
      } else if (children.elements case [final Expression only]
          when fits(only.staticType, slot)) {
        await _replace(builder, widget, only);
      }
    }
  }

  Future<void> _replace(
    ChangeBuilder builder,
    Expression widget,
    Expression child,
  ) async {
    final text = reindent(
      utils.getNodeText(child),
      utils.getLinePrefix(child.offset),
      utils.getLinePrefix(widget.offset),
    );
    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleReplacement(range.node(widget), text);
    });
  }

  /// Puts the elements of [children] in [list] where [widget] is.
  Future<void> _splice(
    ChangeBuilder builder,
    Expression widget,
    ListLiteral list,
    ListLiteral children,
  ) async {
    final elements = children.elements;
    if (elements.isEmpty) {
      await builder.addDartFileEdit(file, (builder) {
        builder.addDeletion(_deletion(widget, list));
      });
      return;
    }
    final text = reindent(
      textOf(startWithComments(elements.first), elements.last.end),
      utils.getLinePrefix(elements.first.offset),
      utils.getLinePrefix(widget.offset),
    );
    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleReplacement(range.node(widget), text);
    });
  }

  /// What deleting [widget] from [list] takes away: the widget and the
  /// comma after it up to the next element, else the comma before it
  /// from the element before; all between the brackets for the only one.
  static SourceRange _deletion(Expression widget, ListLiteral list) {
    final elements = list.elements;
    final index = elements.indexOf(widget);
    if (elements.length == 1) {
      return range.endStart(list.leftBracket, list.rightBracket);
    }
    if (index < elements.length - 1) {
      final next = elements[index + 1].beginToken;
      return range.startOffsetEndOffset(
        widget.offset,
        (next.precedingComments ?? next).offset,
      );
    }
    return range.endEnd(elements[index - 1], widget);
  }
}
