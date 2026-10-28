/// The assists that change a widget and its only child round, each
/// keeping its own arguments: [SwapWithChild] and [SwapWithParent].
library;

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../twk_types.dart';
import 'widget_tree.dart';

/// Changes round a widget, `parent`, and the widget written in place as
/// its `child:`, `child`, where the child has a `child:` argument too: the
/// child takes the parent's place, the parent the child's `child:`, and
/// the child's child goes to the parent. Each keeps its other arguments;
/// lines move by as many columns as the widget they are in. Done only
/// where each lands in a place of a type it is: the child where the
/// parent was, the parent as the child's `child:`, the child's child as
/// the parent's. A `const` the child is written with is dropped where
/// the parent is not constant, as the child's child is then no longer in
/// a constant context.
Future<void> _swap(
  ResolvedCorrectionProducer producer,
  ChangeBuilder builder,
  InstanceCreationExpression parent,
) async {
  final (parentArgument, child) = swappableChild(parent) ?? (null, null);
  if (parentArgument == null || child == null) {
    return;
  }
  final childArgument = namedArgument(child, 'child')!;
  final grandchild = childArgument.argumentExpression;
  if (!producer.fits(child.staticType, producer.slotType(parent)) ||
      !producer.fits(parent.staticType, parameterType(childArgument)) ||
      !producer.fits(grandchild.staticType, parameterType(parentArgument))) {
    return;
  }
  final utils = producer.utils;
  String prefix(AstNode node) => utils.getLinePrefix(node.offset);
  String relative(String indent, String base) =>
      indent.startsWith(base) ? indent.substring(base.length) : '';

  final parentIndent = prefix(parent);
  final childIndent = prefix(child);
  final grandchildIndent = prefix(grandchild);
  // the child's lines move to where the parent's start, the parent's to
  // where the line of the child's `child:` does once moved; the
  // grandchild's stay, as it is as deep as before
  final newParentIndent =
      parentIndent + relative(grandchildIndent, childIndent);

  final childStart = child.keyword?.type == Keyword.CONST && !parent.isConst
      ? child.keyword!.next!.offset
      : child.offset;
  String ofChild(int start, int end) =>
      producer.reindent(producer.textOf(start, end), childIndent, parentIndent);
  String ofParent(int start, int end) => producer.reindent(
    producer.textOf(start, end),
    parentIndent,
    newParentIndent,
  );
  final text = StringBuffer()
    ..write(ofChild(childStart, grandchild.offset))
    ..write(ofParent(parent.offset, child.offset))
    ..write(utils.getNodeText(grandchild))
    ..write(ofParent(child.end, parent.end))
    ..write(ofChild(grandchild.end, child.end));
  await builder.addDartFileEdit(producer.file, (builder) {
    builder.addSimpleReplacement(range.node(parent), text.toString());
  });
}

/// Changes round the widget at the cursor and the widget that is its
/// `child:`, each keeping its own arguments; offered where both take a
/// `child:` and are given one, and each lands in a place of a type it is.
///
/// The cursor on `Box`:
///
/// ```dart-nocheck
/// Box(
///   border: const Border.all(),
///   child: Padding(
///     padding: const EdgeInsets.all(1),
///     child: Text('a'),
///   ),
/// )
/// ```
///
/// becomes:
///
/// ```dart-nocheck
/// Padding(
///   padding: const EdgeInsets.all(1),
///   child: Box(
///     border: const Border.all(),
///     child: Text('a'),
///   ),
/// )
/// ```
final class SwapWithChild extends ResolvedCorrectionProducer {
  /// The assist for the request [context] describes.
  SwapWithChild({required super.context});

  /// The assist as the editor lists it: "Swap with child".
  static const kind = AssistKind(
    'twk.assist.swapWithChild',
    DartFixKindPriority.standard,
    'Swap with child',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  AssistKind get assistKind => kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final widget = widgetCreationAt(node);
    if (widget != null) {
      await _swap(this, builder, widget);
    }
  }
}

/// Changes round the widget at the cursor and the widget whose `child:`
/// it is, as [SwapWithChild] does from the parent.
///
/// The cursor on `Padding` in the example of [SwapWithChild] makes the
/// same change.
final class SwapWithParent extends ResolvedCorrectionProducer {
  /// The assist for the request [context] describes.
  SwapWithParent({required super.context});

  /// The assist as the editor lists it: "Swap with parent".
  static const kind = AssistKind(
    'twk.assist.swapWithParent',
    DartFixKindPriority.standard,
    'Swap with parent',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  AssistKind get assistKind => kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final widget = widgetCreationAt(node);
    if (widget?.parent
        case NamedArgument(
          name: Token(lexeme: 'child'),
          parent: ArgumentList(parent: final InstanceCreationExpression parent),
        )
        when isWidgetType(parent.staticType)) {
      await _swap(this, builder, parent);
    }
  }
}
