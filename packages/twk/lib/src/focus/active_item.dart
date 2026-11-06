/// The item of a focused widget its keys act on, which the terminal's
/// hidden cursor rests on: [ActiveItem].
library;

import 'package:twk_core/twk_core.dart'
    show
        BoxConstraints,
        DiagnosticPropertiesBuilder,
        PaintContext,
        Presenter,
        RenderObject,
        RenderObjectWithChildMixin,
        RenderParagraph;

import '../editing/caret.dart' show clearRestCursorOn, restCursorOn;
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
  /// [child], the item its widget's keys act on while [active], the
  /// cursor on [column] of its first row, or where its text [text] is
  /// drawn.
  const ActiveItem({
    required this.active,
    this.column = 0,
    this.text,
    super.key,
    super.child,
  });

  /// Whether it is the item the keys act on.
  final bool active;

  /// The column of its first row the cursor rests on: 0, its first cell,
  /// or where the item starts in a row its child draws of several. See
  /// [text] for an item of a row of text.
  final int column;

  /// Where the item is in a row of text its child, a `Text`, draws of
  /// several (as `HitRow`'s targets are): the start and the end of the
  /// item's text in the text's spans joined, in UTF-16 code units. The
  /// cursor rests on the first cell of its first row the paragraph draws
  /// of that text, found at each layout, so wherever it is drawn
  /// (reordered right to left, the row cut); on [column] where it draws
  /// none, or where the child is no paragraph. Null, the default: on
  /// [column].
  final (int, int)? text;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderActiveItem(active, column, text);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderActiveItem)
        ..active = active
        ..column = column
        ..text = text;
}

/// What [ActiveItem] puts in the render tree: its child, as big as the
/// child is, the hidden cursor put on [column] of its first row as it is
/// painted while [active].
final class _RenderActiveItem extends RenderObject
    with RenderObjectWithChildMixin {
  _RenderActiveItem(this._active, this._column, this._text);

  /// See [ActiveItem.active].
  bool get active => _active;
  bool _active;

  set active(bool value) {
    if (value != _active) {
      _active = value;
      _rest();
    }
  }

  /// See [ActiveItem.column].
  int get column => _column;
  int _column;

  set column(int value) {
    if (value != _column) {
      _column = value;
      _rest();
    }
  }

  /// See [ActiveItem.text].
  (int, int)? get text => _text;
  (int, int)? _text;

  set text((int, int)? value) {
    if (value != _text) {
      _text = value;
      _rest();
    }
  }

  /// The column the cursor rests on: [column], or that of the first cell
  /// the child paragraph draws of [text] as last laid out.
  int get _restColumn {
    final text = _text;
    final child = this.child;
    if (text != null && child is RenderParagraph) {
      if (child.columnsOf(text.$1, text.$2, 0) case (final from, _)) {
        return from;
      }
    }
    return _column;
  }

  // what it was painted with last; null before it is painted
  Presenter? _presenter;

  /// Gives the cell where the cursor rests, or takes it back, on the
  /// presenter it was painted with: a change of [active] or [column]
  /// repaints nothing, which would repaint all up to the boundary above
  /// it (a whole table for its selected row's).
  void _rest() {
    final presenter = _presenter;
    if (presenter == null) {
      return;
    }
    if (_active) {
      restCursorOn(presenter, this, _restColumn, 0);
    } else {
      clearRestCursorOn(presenter, this);
    }
  }

  @override
  void performLayout(BoxConstraints c) {
    final child = this.child;
    if (child == null) {
      width = c.minWidth;
      height = c.minHeight;
      return;
    }
    child.layout(c, parentUsesSize: true);
    width = child.width;
    height = child.height;
    if (_text != null) {
      // where the text is drawn may have moved
      _rest();
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
    // before the child: an active item in it, painted after, is the last
    // given
    _presenter = ctx.presenter;
    _rest();
    final child = this.child;
    if (child != null) {
      paintChild(ctx, child);
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add('active', _active)
      ..add('column', _column, defaultValue: 0)
      ..add('text', _text, defaultValue: null);
  }
}
