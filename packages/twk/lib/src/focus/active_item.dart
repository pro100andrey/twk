/// The item of a focused widget its keys act on, which the terminal's
/// hidden cursor rests on: [ActiveItem].
library;

import 'package:twk_core/twk_core.dart'
    show
        BoxConstraints,
        DiagnosticPropertiesBuilder,
        PaintContext,
        RenderObject,
        RenderObjectWithChildMixin;

import '../editing/caret.dart' show clearRestCursor, restCursor;
import '../framework/framework.dart';
import '../layout/one_child.dart';

/// Shows [child], an item of a widget that has the focus as a whole (a
/// list, a menu, a set of choices), which, while [active], is the one its
/// keys act on: the list's cursor row. The terminal's cursor, hidden,
/// rests on its first cell then (see `restCursor`), as the web's
/// `aria-activedescendant` points at it, so that a terminal that marks
/// the cursor's row (iTerm2's cursor guide) or follows it (macOS zoom, a
/// screen reader, a braille display) shows it rather than the widget's
/// first row.
///
/// It is there around every item, [active] on one, so that moving the
/// cursor builds no item again. One active inside another, as a table's
/// cursor cell in its selected row, is where the cursor rests. Only while
/// it is in the focused widget does it put the cursor there; an item
/// scrolled out of view leaves it on the widget's first cell. A widget
/// that paints its items itself, in one render object, calls
/// `restCursor` in its paint instead.
///
/// A list whose cursor row the hidden cursor follows:
///
/// ```dart
/// Widget item(int i, int cursor) => ActiveItem(
///   active: i == cursor,
///   child: Text(i == cursor ? '> item $i' : '  item $i'),
/// );
/// ```
final class ActiveItem extends SingleChildRenderObjectWidget {
  /// [child], the item its widget's keys act on while [active].
  const ActiveItem({required this.active, super.key, super.child});

  /// Whether it is the item the keys act on.
  final bool active;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderActiveItem(active);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderActiveItem).active = active;
}

/// What [ActiveItem] puts in the render tree: its child, as big as the
/// child is, the hidden cursor put on its first cell as it is painted
/// while [active].
final class _RenderActiveItem extends RenderObject
    with RenderObjectWithChildMixin {
  _RenderActiveItem(this._active);

  /// See [ActiveItem.active].
  bool get active => _active;
  bool _active;

  set active(bool value) {
    if (value != _active) {
      _active = value;
      markNeedsPaint();
    }
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
    // before the child: an active item in it, painted after, is the last
    // given
    if (_active) {
      restCursor(ctx, this, 0, 0);
    } else {
      clearRestCursor(ctx, this);
    }
    final child = this.child;
    if (child != null) {
      paintChild(ctx, child);
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add('active', _active);
  }
}
