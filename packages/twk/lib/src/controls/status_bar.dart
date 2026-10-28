/// A status bar: [StatusBar], a row of sections at its left, in its middle
/// and at its right.
library;

import 'package:twk_core/twk_core.dart'
    show
        BoxConstraints,
        ContainerParentDataMixin,
        ContainerRenderObjectMixin,
        PaintContext,
        ParentData,
        RenderObject;

import '../framework/framework.dart';
import '../layout/basic.dart';
import '../layout/box.dart';
import '../layout/child_list.dart';
import '../style/style.dart';
import '../text/widgets.dart';

/// A status bar: one row of three sections, [left] at its left edge,
/// [right] at its right edge and [center] in its middle.
///
/// At least [gap] columns are between two sections. Each is as wide as it
/// likes while the row has room for them all. When it has not, [right]
/// keeps its width first, as far as it fits, then [left] takes what it
/// leaves, then [center] goes in the middle of the room between them; cut
/// to that room, and gone when there is none. A section cut is laid out
/// that narrow and one row tall, so it shows its first row: a `Text` that
/// wraps, as it does by default, the first of its lines at that width; one
/// with `wrap: TextWrap.none` and `overflow: TextOverflow.ellipsis` its one
/// line, ending with "…".
///
/// It is as wide as it may be; along an axis with no bound, as wide as
/// its sections and the gaps between them. It is filled with [style] merged
/// over the theme's surface and text, which the `Text`s of the sections are
/// drawn in under their own style ([DefaultTextStyle]).
///
/// A bar at the bottom of an editor: the file, the mode, the place of the
/// caret:
///
/// ```dart
/// const Column(
///   children: [
///     Expanded(child: Text('…')),
///     StatusBar(
///       left: Text('main.dart'),
///       center: Text('INSERT'),
///       right: Text('12:4'),
///     ),
///   ],
/// )
/// ```
///
/// See also:
///
///  * `KeyHintsBar`, a row of the keys that can be pressed.
final class StatusBar extends StatelessWidget {
  /// A bar of the sections given, [gap] at least 0, which it asserts.
  const StatusBar({
    super.key,
    this.left,
    this.center,
    this.right,
    this.gap = 1,
    this.style,
  }) : assert(gap >= 0, 'a gap of 0 cells or more');

  /// The section at the left edge; null for none.
  final Widget? left;

  /// The section in the middle; null for none.
  final Widget? center;

  /// The section at the right edge, which keeps its width first; null for
  /// none.
  final Widget? right;

  /// The fewest columns between two sections.
  final int gap;

  /// The row, the theme's surface and text under it.
  final Style? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.surface
        .merge(theme.text)
        .merge(this.style ?? const Style());
    return Box(
      style: style,
      child: DefaultTextStyle(
        style: style,
        child: _Sections(
          gap: gap,
          children: [
            left ?? const SizedBox.shrink(),
            center ?? const SizedBox.shrink(),
            right ?? const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}

/// The left, center and right sections of a [StatusBar].
final class _Sections extends MultiChildRenderObjectWidget {
  const _Sections({required this.gap, super.children});

  final int gap;

  @override
  MultiChildRenderObjectElement createElement() => ChildListElement(this);

  @override
  _RenderSections createRenderObject(BuildContext context) =>
      _RenderSections(gap);

  @override
  void updateRenderObject(BuildContext context, _RenderSections renderObject) =>
      renderObject.gap = gap;
}

final class _SectionData extends ParentData with ContainerParentDataMixin {}

/// What a [StatusBar] lays out and paints: its three children, the left,
/// the center and the right section, one row tall, as [StatusBar] says.
final class _RenderSections extends RenderObject
    with ContainerRenderObjectMixin<_SectionData> {
  _RenderSections(this._gap);

  int _gap;
  int get gap => _gap;
  set gap(int g) {
    if (g != _gap) {
      _gap = g;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _SectionData) {
      child.parentData = _SectionData();
    }
  }

  /// The widths the sections like, the left, center and right.
  (int, int, int) _natural() {
    final left = firstChild;
    final center = left == null ? null : childAfter(left);
    final right = center == null ? null : childAfter(center);
    return (
      left?.getMaxIntrinsicWidth(1) ?? 0,
      center?.getMaxIntrinsicWidth(1) ?? 0,
      right?.getMaxIntrinsicWidth(1) ?? 0,
    );
  }

  @override
  int computeMinIntrinsicWidth(int height) => 0;

  @override
  int computeMaxIntrinsicWidth(int height) {
    final (l, c, r) = _natural();
    final shown = (l > 0 ? 1 : 0) + (c > 0 ? 1 : 0) + (r > 0 ? 1 : 0);
    return l + c + r + (shown > 1 ? (shown - 1) * _gap : 0);
  }

  @override
  int computeMinIntrinsicHeight(int width) => 1;

  @override
  int computeMaxIntrinsicHeight(int width) => 1;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW < BoxConstraints.unbounded
        ? c.maxW
        : c.constrainW(computeMaxIntrinsicWidth(1));
    height = c.constrainH(1);
    final left = firstChild;
    final center = left == null ? null : childAfter(left);
    final right = center == null ? null : childAfter(center);
    if (left == null || center == null || right == null) {
      return;
    }
    final (l, cn, r) = _natural();
    final w = width;
    final rw = r < w ? r : w;
    final lRoom = w - rw - (rw > 0 ? _gap : 0);
    final lw = l < lRoom ? l : (lRoom > 0 ? lRoom : 0);
    final from = lw > 0 ? lw + _gap : 0;
    final to = rw > 0 ? w - rw - _gap : w;
    final room = to > from ? to - from : 0;
    final cw = cn < room ? cn : room;
    final middle = (w - cw) ~/ 2;
    final cx = middle > to - cw ? to - cw : (middle < from ? from : middle);
    _lay(left, lw, 0);
    _lay(center, cw, cx);
    _lay(right, rw, -1);
  }

  /// Lays [child] out at most [w] wide and places it at [x], or at the
  /// right edge for -1.
  void _lay(RenderObject child, int w, int x) {
    child.layout(BoxConstraints(0, w, 0, height), parentUsesSize: true);
    child.parentData
      ..dx = x < 0 ? width - child.width : x
      ..dy = 0;
  }

  @override
  void paint(PaintContext ctx) {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (child.width > 0) {
        paintChild(ctx, child);
      }
    }
  }
}
