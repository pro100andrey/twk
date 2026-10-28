/// The assists that move the widget at the cursor one place along the
/// list of widgets it is in: [MoveWidgetUp] and [MoveWidgetDown].
library;

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../twk_types.dart';
import 'widget_tree.dart';

/// Changes the widget at the cursor, an element of a list of widgets
/// written in place, round with the element [by] places from it, each
/// with the comments on the lines above it. The elements are widgets
/// written as expressions: neither one is an `if`, `for` or spread
/// element, nor goes past one, as which of their widgets would move is
/// not the cursor's to say.
abstract base class _Move extends ResolvedCorrectionProducer {
  _Move({required super.context});

  /// -1 to move up, towards the start of the list; 1 to move down.
  int get by;

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final widget = widgetExpressionAt(node);
    final list = widget?.parent;
    if (widget == null ||
        list is! ListLiteral ||
        !isWidgetType(listElementType(list))) {
      return;
    }
    final elements = list.elements;
    final index = elements.indexOf(widget) + by;
    if (index < 0 || index >= elements.length) {
      return;
    }
    final other = elements[index];
    if (other is! Expression) {
      return;
    }
    final widgetStart = startWithComments(widget);
    final otherStart = startWithComments(other);
    final widgetIndent = utils.getLinePrefix(widgetStart);
    final otherIndent = utils.getLinePrefix(otherStart);
    await builder.addDartFileEdit(file, (builder) {
      builder
        ..addSimpleReplacement(
          range.startOffsetEndOffset(widgetStart, widget.end),
          reindent(textOf(otherStart, other.end), otherIndent, widgetIndent),
        )
        ..addSimpleReplacement(
          range.startOffsetEndOffset(otherStart, other.end),
          reindent(textOf(widgetStart, widget.end), widgetIndent, otherIndent),
        );
    });
  }
}

/// Moves the widget at the cursor, in a list of widgets, before the
/// element before it, both written as widgets.
///
/// The cursor on `Text('b')`:
///
/// ```dart-nocheck
/// Column(children: [Text('a'), Text('b')])
/// ```
///
/// becomes:
///
/// ```dart-nocheck
/// Column(children: [Text('b'), Text('a')])
/// ```
final class MoveWidgetUp extends _Move {
  /// The assist for the request [context] describes.
  MoveWidgetUp({required super.context});

  /// The assist as the editor lists it: "Move widget up".
  static const kind = AssistKind(
    'twk.assist.moveWidgetUp',
    DartFixKindPriority.standard,
    'Move widget up',
  );

  @override
  AssistKind get assistKind => kind;

  @override
  int get by => -1;
}

/// Moves the widget at the cursor, in a list of widgets, after the
/// element after it, both written as widgets.
///
/// The cursor on `Text('a')`:
///
/// ```dart-nocheck
/// Column(children: [Text('a'), Text('b')])
/// ```
///
/// becomes:
///
/// ```dart-nocheck
/// Column(children: [Text('b'), Text('a')])
/// ```
final class MoveWidgetDown extends _Move {
  /// The assist for the request [context] describes.
  MoveWidgetDown({required super.context});

  /// The assist as the editor lists it: "Move widget down".
  static const kind = AssistKind(
    'twk.assist.moveWidgetDown',
    DartFixKindPriority.standard,
    'Move widget down',
  );

  @override
  AssistKind get assistKind => kind;

  @override
  int get by => 1;
}
