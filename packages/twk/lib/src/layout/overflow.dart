/// Boxes whose child is laid out or shown otherwise than their own
/// constraints and place say: [LimitedBox] limits it only where it would
/// have no limit, [OverflowBox] and [SizedOverflowBox] give it other
/// constraints than their own, and [Transform.translate] shows it moved.
///
/// @docImport 'basic.dart';
library;

import 'package:twk_core/twk_core.dart'
    show
        Alignment,
        BoxConstraints,
        DiagnosticPropertiesBuilder,
        HitTestResult,
        PaintContext,
        RenderObject,
        RenderObjectWithChildMixin,
        describeAlignment;

import '../framework/framework.dart';
import 'one_child.dart';

/// Lays [child] out at most [maxWidth] wide where the constraints leave
/// the width unbounded, and at most [maxHeight] tall where they leave the
/// height so, as in a `Column` or a scrolled list; a bounded axis it leaves
/// as it is. As big as the child, or without one as small as the limited
/// constraints allow.
///
/// As Flutter's `LimitedBox`. A box that fills its room, five rows tall in
/// a list, where the room has no end:
///
/// ```dart
/// ListView(
///   children: const [
///     LimitedBox(maxHeight: 5, child: SizedBox.expand(child: Box())),
///   ],
/// )
/// ```
///
/// See also:
///
///  * [ConstrainedBox], which limits the child where the room is bounded
///    too.
final class LimitedBox extends SingleChildRenderObjectWidget {
  /// Limits [child] to [maxWidth] and [maxHeight], each 0 or more, along
  /// an unbounded axis; no limit by default.
  const LimitedBox({
    super.key,
    this.maxWidth = BoxConstraints.unbounded,
    this.maxHeight = BoxConstraints.unbounded,
    super.child,
  }) : assert(maxWidth >= 0 && maxHeight >= 0, 'a limit of 0 cells or more');

  /// The most columns the child gets along an unbounded width.
  final int maxWidth;

  /// The most rows the child gets along an unbounded height.
  final int maxHeight;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLimitedBox(maxWidth, maxHeight);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderLimitedBox)
        ..maxWidth = maxWidth
        ..maxHeight = maxHeight;
}

/// Lays [child] out within constraints of its own: [minWidth],
/// [maxWidth], [minHeight] and [maxHeight] where given, those this box
/// gets where not, a given limit winning over one taken that it crosses.
/// The box is as big as its constraints allow (along an axis they leave
/// unbounded, as long as the child, within them) and places the child in
/// it by [alignment]: a child bigger than the box sticks out of it on the
/// side the alignment says, and is cut off at its edges, as everything a
/// render object paints is cut off at its parent's; it takes the mouse
/// where it shows.
///
/// As Flutter's `OverflowBox`, but for painting outside of itself. A
/// heading 30 cells wide in a box that may be narrower, its middle shown:
///
/// ```dart
/// const OverflowBox(
///   minWidth: 30,
///   maxWidth: 30,
///   child: Text('A heading wider than the box'),
/// )
/// ```
///
/// See also:
///
///  * [SizedOverflowBox], with a size of its own.
///  * [ConstrainedBox], which keeps the child's constraints within its own.
final class OverflowBox extends SingleChildRenderObjectWidget {
  /// Lays [child] out within the limits given, each 0 or more and a min
  /// at most its max, placed at [alignment], the middle by default.
  const OverflowBox({
    super.key,
    this.alignment = Alignment.center,
    this.minWidth,
    this.maxWidth,
    this.minHeight,
    this.maxHeight,
    super.child,
  }) : assert(
         (minWidth ?? 0) >= 0 &&
             (minHeight ?? 0) >= 0 &&
             (minWidth ?? 0) <= (maxWidth ?? BoxConstraints.unbounded) &&
             (minHeight ?? 0) <= (maxHeight ?? BoxConstraints.unbounded),
         'limits of 0 cells or more, a min at most its max',
       );

  /// Where the child goes in the box.
  final Alignment alignment;

  /// The fewest columns the child takes; the box's own when null.
  final int? minWidth;

  /// The most columns the child takes; the box's own when null.
  final int? maxWidth;

  /// The fewest rows the child takes; the box's own when null.
  final int? minHeight;

  /// The most rows the child takes; the box's own when null.
  final int? maxHeight;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderOverflowBox(
    (minWidth, maxWidth, minHeight, maxHeight),
    alignment: alignment,
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderOverflowBox)
        ..alignment = alignment
        ..limits = (minWidth, maxWidth, minHeight, maxHeight);
}

/// [size] big, as far as its constraints allow, it lays [child] out
/// within the constraints it gets itself, as though it were not there,
/// and places it in itself by [alignment]: a child bigger than the box
/// sticks out of it on the side the alignment says and is cut off at its
/// edges, as an [OverflowBox]'s is; it takes the mouse where it shows.
///
/// As Flutter's `SizedOverflowBox`, but for painting outside of itself.
/// A row that takes one cell for a mark three cells wide, which sticks
/// out to its right:
///
/// ```dart
/// const SizedOverflowBox(
///   size: (1, 1),
///   alignment: Alignment.centerLeft,
///   child: Text('(!)'),
/// )
/// ```
final class SizedOverflowBox extends SingleChildRenderObjectWidget {
  /// Takes [size] cells, and lays [child] out as though it were not there,
  /// placed at [alignment], the middle by default.
  const SizedOverflowBox({
    required this.size,
    super.key,
    this.alignment = Alignment.center,
    super.child,
  });

  /// The width and the height of the box, in cells.
  final (int, int) size;

  /// Where the child goes in the box.
  final Alignment alignment;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizedOverflowBox(size, alignment: alignment);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderSizedOverflowBox)
        ..alignment = alignment
        ..size = size;
}

/// Shows [child] moved by [offset], its columns to the right and its rows
/// down (left and up where negative), and lays it out as if it were not
/// moved: as big as the child, which is cut off at the edges of this
/// box's own place. With [transformHitTests] the mouse finds the child
/// where it shows; without, where it would be unmoved.
///
/// A terminal's cells neither turn nor scale: of Flutter's `Transform`
/// there is only [Transform.translate], in whole cells. To move a child a
/// share of its size, see `FractionalTranslation`.
///
/// A label shown one cell to the right and one row down from where it is
/// laid out:
///
/// ```dart
/// const Transform.translate(offset: (1, 1), child: Text('Saved'))
/// ```
final class Transform extends SingleChildRenderObjectWidget {
  /// Moves [child] by [offset], (columns, rows).
  const Transform.translate({
    required this.offset,
    super.key,
    this.transformHitTests = true,
    super.child,
  });

  /// How far the child is moved, (columns to the right, rows down).
  final (int, int) offset;

  /// Whether the mouse finds the child where it shows rather than where it
  /// would be unmoved.
  final bool transformHitTests;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTranslate(offset, transformHitTests: transformHitTests);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderTranslate)
        ..offset = offset
        ..transformHitTests = transformHitTests;
}

const int _unbounded = BoxConstraints.unbounded;

/// What a [LimitedBox] lays out.
final class _RenderLimitedBox extends RenderObject
    with RenderObjectWithChildMixin {
  _RenderLimitedBox(this._maxWidth, this._maxHeight);

  int _maxWidth;
  int get maxWidth => _maxWidth;
  set maxWidth(int w) {
    if (w != _maxWidth) {
      _maxWidth = w;
      markNeedsLayout();
    }
  }

  int _maxHeight;
  int get maxHeight => _maxHeight;
  set maxHeight(int h) {
    if (h != _maxHeight) {
      _maxHeight = h;
      markNeedsLayout();
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add('maxWidth', _maxWidth, defaultValue: _unbounded)
      ..add('maxHeight', _maxHeight, defaultValue: _unbounded);
  }

  @override
  void performLayout(BoxConstraints c) {
    final maxW = c.maxW >= _unbounded ? c.constrainW(_maxWidth) : c.maxW;
    final maxH = c.maxH >= _unbounded ? c.constrainH(_maxHeight) : c.maxH;
    final child = this.child;
    if (child == null) {
      width = c.minW;
      height = c.minH;
      return;
    }
    child
      ..layout(BoxConstraints(c.minW, maxW, c.minH, maxH), parentUsesSize: true)
      ..parentData.dx = 0
      ..parentData.dy = 0;
    width = child.width;
    height = child.height;
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMinIntrinsicHeight(int width) =>
      child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void paint(PaintContext ctx) {
    final child = this.child;
    if (child != null) {
      paintChild(ctx, child);
    }
  }
}

/// What the overflow boxes share: an alignment that places the child, and
/// painting it.
abstract base class _RenderAligning extends RenderObject
    with RenderObjectWithChildMixin {
  _RenderAligning({required this._alignment});

  Alignment _alignment;
  Alignment get alignment => _alignment;
  set alignment(Alignment a) {
    if (a != _alignment) {
      _alignment = a;
      markNeedsLayout();
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.addMessage('alignment', describeAlignment(_alignment));
  }

  /// Places the child, laid out, in the box as big as it is.
  void _align(RenderObject child) => child.parentData
    ..dx = _alignment.dx(width - child.width)
    ..dy = _alignment.dy(height - child.height);

  @override
  void paint(PaintContext ctx) {
    final child = this.child;
    if (child != null) {
      paintChild(ctx, child);
    }
  }
}

/// What an [OverflowBox] lays out.
final class _RenderOverflowBox extends _RenderAligning {
  _RenderOverflowBox(this._limits, {required super.alignment});

  (int?, int?, int?, int?) _limits;
  (int?, int?, int?, int?) get limits => _limits;
  set limits((int?, int?, int?, int?) l) {
    if (l != _limits) {
      _limits = l;
      markNeedsLayout();
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    final (minW, maxW, minH, maxH) = _limits;
    properties
      ..add('minWidth', minW, defaultValue: null)
      ..add('maxWidth', maxW, defaultValue: null)
      ..add('minHeight', minH, defaultValue: null)
      ..add('maxHeight', maxH, defaultValue: null);
  }

  @override
  void performLayout(BoxConstraints c) {
    final child = this.child;
    if (child == null) {
      width = c.maxW < _unbounded ? c.maxW : c.minW;
      height = c.maxH < _unbounded ? c.maxH : c.minH;
      return;
    }
    final (minW, maxW) = _within(_limits.$1, _limits.$2, c.minW, c.maxW);
    final (minH, maxH) = _within(_limits.$3, _limits.$4, c.minH, c.maxH);
    child.layout(BoxConstraints(minW, maxW, minH, maxH), parentUsesSize: true);
    width = c.maxW < _unbounded ? c.maxW : c.constrainW(child.width);
    height = c.maxH < _unbounded ? c.maxH : c.constrainH(child.height);
    _align(child);
  }

  /// The limits along an axis: [min] and [max] where given, [ownMin] and
  /// [ownMax] where not; a given one wins over one taken that it crosses.
  static (int, int) _within(int? min, int? max, int ownMin, int ownMax) {
    final lo = min ?? ownMin;
    final hi = max ?? ownMax;
    if (lo <= hi) {
      return (lo, hi);
    }
    return min != null ? (lo, lo) : (hi, hi);
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMinIntrinsicHeight(int width) =>
      child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      child?.getMaxIntrinsicHeight(width) ?? 0;
}

/// What a [SizedOverflowBox] lays out.
final class _RenderSizedOverflowBox extends _RenderAligning {
  _RenderSizedOverflowBox(this._size, {required super.alignment});

  (int, int) _size;
  (int, int) get size => _size;
  set size((int, int) s) {
    if (s != _size) {
      _size = s;
      markNeedsLayout();
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.addMessage('size', '${_size.$1}×${_size.$2}');
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(_size.$1);
    height = c.constrainH(_size.$2);
    final child = this.child;
    if (child != null) {
      child.layout(c, parentUsesSize: true);
      _align(child);
    }
  }

  // as big as its size, whatever the child asks for

  @override
  int computeMinIntrinsicWidth(int height) => _size.$1;

  @override
  int computeMaxIntrinsicWidth(int height) => _size.$1;

  @override
  int computeMinIntrinsicHeight(int width) => _size.$2;

  @override
  int computeMaxIntrinsicHeight(int width) => _size.$2;
}

/// What a [Transform.translate] lays out and paints.
final class _RenderTranslate extends RenderObject
    with RenderObjectWithChildMixin {
  _RenderTranslate(this._offset, {required this.transformHitTests});

  (int, int) _offset;
  (int, int) get offset => _offset;
  set offset((int, int) o) {
    if (o != _offset) {
      _offset = o;
      _place();
      markNeedsPaint();
    }
  }

  /// Whether the mouse finds the child where it shows.
  bool transformHitTests;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..addMessage('offset', '${_offset.$1}, ${_offset.$2}')
      ..add('transformHitTests', transformHitTests, defaultValue: true);
  }

  @override
  void performLayout(BoxConstraints c) {
    final child = this.child;
    if (child == null) {
      width = c.minW;
      height = c.minH;
      return;
    }
    child.layout(c, parentUsesSize: true);
    width = child.width;
    height = child.height;
    _place();
  }

  void _place() {
    final child = this.child;
    if (child != null) {
      child.parentData
        ..dx = _offset.$1
        ..dy = _offset.$2;
    }
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMinIntrinsicHeight(int width) =>
      child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void paint(PaintContext ctx) {
    final child = this.child;
    if (child != null) {
      paintChild(ctx, child);
    }
  }

  /// Where the child shows; without [transformHitTests], where it would
  /// be unmoved.
  @override
  bool hitTestChildren(HitTestResult result, int x, int y) {
    final child = this.child;
    if (child == null) {
      return false;
    }
    return transformHitTests
        ? super.hitTestChildren(result, x, y)
        : child.hitTest(result, x, y);
  }
}
