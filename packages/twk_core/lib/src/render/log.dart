part of 'render.dart';

/// A scrolling list of one-line items (a log or a chat view), as big as
/// its constraints allow, that follows its end as lines are added.
///
/// It is its own repaint boundary, so [pen] needs an opaque background.
/// When it only scrolled and nothing is painted over it, it shifts its
/// rows on the surface ([Surface.scrollRect]), so that the terminal
/// scrolls them in hardware, and paints just the exposed rows and the
/// lines appended since the last frame.
///
/// Lines are append-only and [itemPen] must return the same pen for the same
/// line on every frame: rows that neither scrolled into view nor show a new
/// line keep what was painted before. When what [itemPen] returns for
/// lines already shown changes (a selection, a highlight), call
/// [repaintAll].
///
/// It scrolls what it holds through whatever room it gets, so it asks for
/// none: its intrinsic sizes are 0.
///
/// ```dart
/// final styles = StyleTable();
/// final text = styles.pen(const Pen(bg: Color.rgb(0, 0, 0)));
/// final log = RenderLog(pen: text, itemPen: (index, line) => text)
///   ..add('connected')
///   ..add('3 messages');
/// log.scrollBy(-1); // one line back: it stops following the end
/// ```
final class RenderLog extends RenderObject {
  /// An empty log filled with [pen], each line drawn in what [itemPen]
  /// returns for it.
  RenderLog({required this.pen, required this.itemPen});

  /// The id of the pen the log is filled with, with an opaque background.
  final int pen;

  /// The id of the pen the line at `index`, `line`, is drawn in: the same
  /// for the same line on every frame, until [repaintAll].
  final int Function(int index, String line) itemPen;
  final _lines = <String>[];
  final _runs = <GlyphRun?>[];

  // the index of the first visible line; follows the end while stickToEnd
  var _first = 0;

  /// Whether the log shows its last lines, following the end as lines are
  /// added; true at first. Scrolling back ([scrollBy]) turns it off, and
  /// scrolling to the end, or a layout tall enough to show it, on.
  var stickToEnd = true;

  // what is on the surface from the last paint
  var _paintedFirst = -1;
  var _paintedLength = 0;
  var _paintedWidth = -1;
  var _paintedHeight = -1;
  var _fullRepaint = true;

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  /// The lines it holds, the first shown unless it is the first line,
  /// whether it follows the end, and its pen.
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add('lines', _lines.length)
      ..add('first', _first, defaultValue: 0);
    if (stickToEnd) {
      properties.addTag('sticky');
    }
    properties.add('pen', pen);
  }

  /// How many lines the log holds.
  int get length => _lines.length;

  /// Appends [line], which is shown on the next frame when the log follows
  /// its end ([stickToEnd]): on one row, a column in from the left edge,
  /// cut off at the right one.
  void add(String line) {
    _lines.add(line);
    _runs.add(null);
    if (stickToEnd) {
      _first = _maxFirst;
    }
    markNeedsPaint();
  }

  int get _maxFirst => _lines.length - height > 0 ? _lines.length - height : 0;

  /// Repaints every visible line on the next frame.
  void repaintAll() {
    _fullRepaint = true;
    markNeedsPaint();
  }

  /// Scrolls the view [delta] lines on, back when negative, kept from the
  /// first line to the last screenful; it follows the end ([stickToEnd])
  /// when it ends there.
  void scrollBy(int delta) {
    final f = (_first + delta).clamp(0, _maxFirst);
    stickToEnd = f == _maxFirst;
    if (f == _first) {
      return;
    }
    _first = f;
    markNeedsPaint();
  }

  @override
  void invalidatePaintCache() => _fullRepaint = true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
    // a view that grew may now reach the end: then it follows it again
    if (stickToEnd || _first > _maxFirst) {
      _first = _maxFirst;
      stickToEnd = true;
    }
    _fullRepaint = true;
  }

  @override
  void paint(PaintContext ctx) {
    assert(_opaqueBackground(ctx, pen), _translucentBoundary);
    final shift = _first - _paintedFirst;
    var gx = 0;
    var gy = 0;
    for (RenderObject? o = this; o != null; o = o.parent) {
      gx += o.parentData.dx;
      gy += o.parentData.dy;
    }
    // the surface can move only rows it has: a log partly off the surface
    // (or cut by an ancestor) repaints what is visible instead
    final whollyVisible = ctx.canvas.clipContains(
      gx,
      gy,
      gx + width,
      gy + height,
    );
    final canShift =
        whollyVisible &&
        !_fullRepaint &&
        _paintedFirst >= 0 &&
        width == _paintedWidth &&
        height == _paintedHeight &&
        shift != 0 &&
        shift.abs() < height;
    // rows [from, to) to repaint: all of them, or those a shift exposed
    var from = 0;
    var to = height;
    if (canShift) {
      // the surface records the move; the presenter replays it in hardware
      // (whole rows, or DECSLRM margins for a narrower view where supported)
      ctx.surface.scrollRect(gx, gx + width, gy, gy + height, shift);
      if (shift > 0) {
        from = height - shift;
      } else {
        to = -shift;
      }
    } else if (!_fullRepaint && shift == 0 && _paintedFirst >= 0) {
      to = 0; // same window: nothing moved
    }
    // plus the rows showing lines appended since the last paint
    final newFrom = (_paintedLength - _first).clamp(0, height);
    final newTo = (_lines.length - _first).clamp(0, height);
    final cv = ctx.canvas;
    for (var row = 0; row < height; row++) {
      if ((row < from || row >= to) && (row < newFrom || row >= newTo)) {
        continue;
      }
      cv.fill(0, row, width, 1, pen);
      final i = _first + row;
      if (i >= 0 && i < _lines.length) {
        final run = _runs[i] ??= cv.shape(_lines[i]);
        cv.run(1, row, run, itemPen(i, _lines[i]));
      }
    }
    _paintedFirst = _first;
    _paintedLength = _lines.length;
    _paintedWidth = width;
    _paintedHeight = height;
    _fullRepaint = false;
  }
}
