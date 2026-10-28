/// Children on top of each other: [Stack] lays them out, [Positioned] pins
/// one to its edges.
///
/// @docImport '../overlay/layer.dart';
library;

import 'package:twk_core/twk_core.dart'
    show Alignment, RenderObject, RenderStack, StackFit, StackParentData;

import '../framework/framework.dart';
import 'child_list.dart';

export 'package:twk_core/twk_core.dart' show StackFit;

/// Lays its children out on top of each other and paints them in order: a
/// later child covers an earlier one where they overlap. [alignment]
/// places the children that are not [Positioned], laid out as [fit] says;
/// the stack is as big as the biggest of them, or with none as big as it
/// may be. What sticks out of it is cut off. See [RenderStack].
///
/// A badge on the top right corner of a panel:
///
/// ```dart
/// const Stack(
///   children: [
///     Box(border: Border.all(), child: Text('Messages')),
///     Positioned(top: 0, right: 1, child: Text('3')),
///   ],
/// )
/// ```
///
/// See also:
///
///  * [Overlay], for layers that come and go above the app.
final class Stack extends MultiChildRenderObjectWidget {
  /// Lays [children] out on top of each other: those not positioned at
  /// the top left, as small as they like, by default.
  const Stack({
    super.key,
    this.alignment = Alignment.topLeft,
    this.fit = StackFit.loose,
    super.children,
  });

  /// Where the children that are not positioned go, and a positioned one
  /// along an axis it has no edge on.
  final Alignment alignment;

  /// How the children that are not positioned are laid out.
  final StackFit fit;

  @override
  MultiChildRenderObjectElement createElement() => ChildListElement(this);

  @override
  RenderStack createRenderObject(BuildContext context) =>
      RenderStack(alignment: alignment, fit: fit);

  @override
  void updateRenderObject(BuildContext context, RenderStack renderObject) {
    renderObject
      ..alignment = alignment
      ..fit = fit;
  }
}

/// Pins [child] to the edges of the [Stack] it is in, in cells: [left]
/// columns in from its left edge, [right] from its right, [top] and
/// [bottom] rows from its top and bottom; a negative edge puts it partly
/// outside. Along an axis with both edges the child is as long as the
/// cells between them; otherwise [width] or [height] sets its length, or
/// it is as long as it wants up to the stack's far edge. Along an axis
/// with no edge, the stack's alignment places it. It goes inside a
/// [Stack] with no render object widget in between.
///
/// A hint two cells in from the right edge of a stack, on its last row:
///
/// ```dart
/// const Positioned(right: 2, bottom: 0, child: Text('? help'))
/// ```
final class Positioned extends ParentDataWidget<StackParentData> {
  /// Pins [child] to the edges given; at most two of [left], [right] and
  /// [width], and of [top], [bottom] and [height].
  const Positioned({
    required super.child,
    super.key,
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.width,
    this.height,
  }) : assert(
         left == null || right == null || width == null,
         'at most two of left, right and width',
       ),
       assert(
         top == null || bottom == null || height == null,
         'at most two of top, bottom and height',
       );

  /// Pinned to every edge, [left], [top], [right] and [bottom] cells in:
  /// as big as the stack less those.
  const Positioned.fill({
    required super.child,
    super.key,
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  }) : width = null,
       height = null;

  /// Columns from the stack's left edge to the child's; null for none.
  final int? left;

  /// Rows from the stack's top edge to the child's; null for none.
  final int? top;

  /// Columns from the child's right edge to the stack's; null for none.
  final int? right;

  /// Rows from the child's bottom edge to the stack's; null for none.
  final int? bottom;

  /// The child's width, where it has not both [left] and [right]; null to
  /// leave it to the child.
  final int? width;

  /// The child's height, where it has not both [top] and [bottom]; null to
  /// leave it to the child.
  final int? height;

  @override
  void applyParentData(RenderObject renderObject) {
    final at = renderObject.parentData as StackParentData;
    if (at.left != left ||
        at.top != top ||
        at.right != right ||
        at.bottom != bottom ||
        at.width != width ||
        at.height != height) {
      at
        ..left = left
        ..top = top
        ..right = right
        ..bottom = bottom
        ..width = width
        ..height = height;
      renderObject.parent?.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => Stack;
}
