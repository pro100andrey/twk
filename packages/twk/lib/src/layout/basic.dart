/// Boxes with one child: [Padding] around it, [Align] and [Center] to place
/// it, [SizedBox] and [ConstrainedBox] to limit its size,
/// [FractionallySizedBox] to give it a fraction of the room there is, and
/// [IntrinsicWidth] and [IntrinsicHeight] to size it to its content.
///
/// @docImport 'box.dart';
/// @docImport 'container.dart';
/// @docImport 'flex.dart';
/// @docImport 'overflow.dart';
/// @docImport 'stack.dart';
library;

import 'package:twk_core/twk_core.dart'
    show
        Alignment,
        BoxConstraints,
        EdgeInsets,
        RenderConstrainedBox,
        RenderFractionallySizedBox,
        RenderIntrinsicHeight,
        RenderIntrinsicWidth,
        RenderPadding,
        RenderPositionedBox;

import '../framework/framework.dart';
import 'one_child.dart';

export 'package:twk_core/twk_core.dart' show Alignment, EdgeInsets;

/// Insets [child] by [padding]: as big as the child and the padding.
///
/// The child gets the room less the padding; without a child, the box is
/// as big as the padding alone, as far as the constraints allow. See
/// [RenderPadding].
///
/// A label two cells in from the left and right, one from the top:
///
/// ```dart
/// const Padding(
///   padding: EdgeInsets.only(left: 2, right: 2, top: 1),
///   child: Text('Name'),
/// )
/// ```
///
/// See also:
///
///  * [Box], which can draw a border and a background around the padding.
///  * [Container], which puts padding, a decoration and a size together.
final class Padding extends SingleChildRenderObjectWidget {
  /// Insets [child] by [padding].
  const Padding({required this.padding, super.key, super.child});

  /// The empty cells on each side of the child.
  final EdgeInsets padding;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderPadding createRenderObject(BuildContext context) =>
      RenderPadding(padding: padding);

  @override
  void updateRenderObject(BuildContext context, RenderPadding renderObject) =>
      renderObject.padding = padding;
}

/// Places [child] inside itself as [alignment] says.
///
/// It is as big as it may be, or along an axis with a factor
/// ([widthFactor], [heightFactor]) that many times as long as the child.
/// Along an axis that may be any length, a scroll view's or a list row's
/// height, it is as long as the child, as in Flutter. The child is laid
/// out loosely: as small as it likes, up to the box's size. See
/// [RenderPositionedBox].
///
/// A status in the bottom right corner of the room there is:
///
/// ```dart
/// const Align(alignment: Alignment.bottomRight, child: Text('Saved'))
/// ```
///
/// See also:
///
///  * [Center], the same with the child in the middle.
///  * [Positioned], which places a child of a [Stack] by its edges.
final class Align extends SingleChildRenderObjectWidget {
  /// Places [child] at [alignment], the middle by default; a factor of 0
  /// or more, null for as big as the box may be along that axis.
  const Align({
    super.key,
    this.alignment = Alignment.center,
    this.widthFactor,
    this.heightFactor,
    super.child,
  }) : assert(
         (widthFactor ?? 0) >= 0 && (heightFactor ?? 0) >= 0,
         'a factor of 0 or more',
       );

  /// Where the child goes.
  final Alignment alignment;

  /// How many times as wide as the child this is; as wide as it may be
  /// when null.
  final int? widthFactor;

  /// How many times as tall as the child this is; as tall as it may be
  /// when null.
  final int? heightFactor;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderPositionedBox createRenderObject(BuildContext context) =>
      RenderPositionedBox(
        alignment: alignment,
        widthFactor: widthFactor,
        heightFactor: heightFactor,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderPositionedBox renderObject,
  ) {
    renderObject
      ..alignment = alignment
      ..widthFactor = widthFactor
      ..heightFactor = heightFactor;
  }
}

/// An [Align] that puts [child] in the middle, the odd cell after it.
///
/// A dialog's text in the middle of the screen:
///
/// ```dart
/// const Center(child: Text('Nothing to show'))
/// ```
final class Center extends Align {
  /// Puts [child] in the middle; [widthFactor] and [heightFactor] as
  /// [Align]'s.
  const Center({super.key, super.widthFactor, super.heightFactor, super.child});
}

/// Makes [child] [width] wide and [height] tall, as far as the constraints
/// allow; along an axis left null, the child is as long as it wants.
///
/// Without a child it is that big itself, which makes it the usual gap
/// between the children of a [Row] or [Column]. See
/// [RenderConstrainedBox].
///
/// A field 20 cells wide, and a blank line under it:
///
/// ```dart
/// const Column(
///   children: [
///     SizedBox(width: 20, child: TextField()),
///     SizedBox(height: 1),
///   ],
/// )
/// ```
///
/// See also:
///
///  * [ConstrainedBox], for limits rather than a size.
///  * [FractionallySizedBox], for a part of the room there is.
final class SizedBox extends SingleChildRenderObjectWidget {
  /// Makes [child] [width] by [height] cells, each 0 or more; null along
  /// an axis leaves it to the child.
  const SizedBox({super.key, this.width, this.height, super.child})
    : assert(
        (width ?? 0) >= 0 && (height ?? 0) >= 0,
        'a size of 0 cells or more',
      );

  /// As big as the constraints allow.
  const SizedBox.expand({super.key, super.child})
    : width = BoxConstraints.unbounded,
      height = BoxConstraints.unbounded;

  /// As small as the constraints allow.
  const SizedBox.shrink({super.key, super.child}) : width = 0, height = 0;

  /// The width in cells; null leaves it to the child, or 0 without one.
  final int? width;

  /// The height in cells; null leaves it to the child, or 0 without one.
  final int? height;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderConstrainedBox createRenderObject(BuildContext context) =>
      RenderConstrainedBox(
        additionalConstraints: BoxConstraints.tightFor(
          width: width,
          height: height,
        ),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderConstrainedBox renderObject,
  ) => renderObject.additionalConstraints = BoxConstraints.tightFor(
    width: width,
    height: height,
  );
}

/// Lays [child] out within [constraints] as well as its own: each limit of
/// [constraints] is kept within those the box gets.
///
/// See [RenderConstrainedBox]. A message at least 10 and at most 40 cells
/// wide:
///
/// ```dart
/// const ConstrainedBox(
///   constraints: BoxConstraints(10, 40, 0, BoxConstraints.unbounded),
///   child: Text('A message that wraps at forty cells'),
/// )
/// ```
///
/// See also:
///
///  * [SizedBox], for one size along each axis.
///  * [LimitedBox], for a limit only where the room is unbounded.
final class ConstrainedBox extends SingleChildRenderObjectWidget {
  /// Lays [child] out within [constraints].
  const ConstrainedBox({required this.constraints, super.key, super.child});

  /// The limits on the child's size; [BoxConstraints.unbounded] sets none.
  final BoxConstraints constraints;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderConstrainedBox createRenderObject(BuildContext context) =>
      RenderConstrainedBox(additionalConstraints: constraints);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderConstrainedBox renderObject,
  ) => renderObject.additionalConstraints = constraints;
}

/// Makes [child] a fraction of the room there is: [widthFactor] of the
/// most width the box may have, [heightFactor] of the most height (`0.5`
/// for half, `1 / 3` for a third), each rounded to the nearest cell, a half
/// up. Along an axis without a factor the child gets the room as it is.
/// The box is as big as it may be, and places the child in it by
/// [alignment]. See [RenderFractionallySizedBox].
///
/// A panel half as wide as the screen, in its middle:
///
/// ```dart
/// const FractionallySizedBox(widthFactor: 0.5, child: Box())
/// ```
///
/// See also:
///
///  * [Expanded], for a share of what a [Row] or [Column] has left.
final class FractionallySizedBox extends SingleChildRenderObjectWidget {
  /// Makes [child] [widthFactor] and [heightFactor] of the room there is,
  /// each finite and 0 or more, placed at [alignment], the middle by
  /// default.
  const FractionallySizedBox({
    super.key,
    this.alignment = Alignment.center,
    this.widthFactor,
    this.heightFactor,
    super.child,
  }) : assert(
         (widthFactor ?? 0) >= 0 &&
             (widthFactor ?? 0) < double.infinity &&
             (heightFactor ?? 0) >= 0 &&
             (heightFactor ?? 0) < double.infinity,
         'a finite factor of 0 or more',
       );

  /// Where the child goes.
  final Alignment alignment;

  /// The child's part of the most width there is; all of the room when
  /// null.
  final double? widthFactor;

  /// The child's part of the most height there is; all of the room when
  /// null.
  final double? heightFactor;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderFractionallySizedBox createRenderObject(BuildContext context) =>
      RenderFractionallySizedBox(
        alignment: alignment,
        widthFactor: widthFactor,
        heightFactor: heightFactor,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderFractionallySizedBox renderObject,
  ) {
    renderObject
      ..alignment = alignment
      ..widthFactor = widthFactor
      ..heightFactor = heightFactor;
  }
}

/// Makes [child] as wide as its content would like to be, within the room
/// there is, rounded up to a multiple of [stepWidth] when given; with
/// [stepHeight], as tall as its content would like to be at that width,
/// rounded up to a multiple of it, too. See [RenderIntrinsicWidth].
///
/// It lays the content out twice, once to ask its width; under a long
/// list, that is the whole list. A menu as wide as its widest item, each
/// item stretched to it:
///
/// ```dart
/// const IntrinsicWidth(
///   child: Column(
///     crossAxisAlignment: CrossAxisAlignment.stretch,
///     children: [Text('Open'), Text('Save as…'), Text('Quit')],
///   ),
/// )
/// ```
final class IntrinsicWidth extends SingleChildRenderObjectWidget {
  /// Makes [child] as wide as its content would like, rounded up to a
  /// multiple of [stepWidth] and [stepHeight] when given, each 1 or more.
  const IntrinsicWidth({
    super.key,
    this.stepWidth,
    this.stepHeight,
    super.child,
  }) : assert(
         (stepWidth ?? 1) > 0 && (stepHeight ?? 1) > 0,
         'a step of 1 cell or more',
       );

  /// What the width is a multiple of.
  final int? stepWidth;

  /// What the height is a multiple of; the height is left to the child
  /// when null.
  final int? stepHeight;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderIntrinsicWidth createRenderObject(BuildContext context) =>
      RenderIntrinsicWidth(stepWidth: stepWidth, stepHeight: stepHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderIntrinsicWidth renderObject,
  ) {
    renderObject
      ..stepWidth = stepWidth
      ..stepHeight = stepHeight;
  }
}

/// Makes [child] as tall as its content would like to be, within the room
/// there is: a `Row` under it with `CrossAxisAlignment.stretch` makes all
/// its children as tall as the tallest. See [RenderIntrinsicHeight].
///
/// A divider beside a text as tall as the text's lines:
///
/// ```dart
/// const IntrinsicHeight(
///   child: Row(
///     crossAxisAlignment: CrossAxisAlignment.stretch,
///     children: [
///       VerticalDivider(),
///       Expanded(child: Text('Two lines\nof text')),
///     ],
///   ),
/// )
/// ```
final class IntrinsicHeight extends SingleChildRenderObjectWidget {
  /// Makes [child] as tall as its content would like to be.
  const IntrinsicHeight({super.key, super.child});

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderIntrinsicHeight createRenderObject(BuildContext context) =>
      RenderIntrinsicHeight();
}
