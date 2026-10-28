/// What the editing widgets draw a caret with: the columns a text takes
/// on the canvas ([TextColumns]), and the terminal's own cursor placed at
/// the caret ([showCaret], [hideCaret]), which a render object of an app's
/// own places at its caret too.
library;

import 'package:twk_core/twk_core.dart'
    show
        ClusterScan,
        CursorShape,
        PaintContext,
        RenderObject,
        TextMode,
        TextSegmenter,
        stringWidth;

/// The columns of a row of text as it is drawn: [TextColumns] in the
/// order it is stored, a `BidiRow` in the order it is read.
abstract interface class RowColumns {
  /// The columns the row takes.
  int get width;

  /// The column the caret shows at for [offset].
  int columnOf(int offset);

  /// The first column at or after [column] that a cluster starts at; the
  /// row's width past it.
  int startAtOrAfter(int column);

  /// The last column at or before [column] that a cluster starts at.
  int startAtOrBefore(int column);
}

/// The column each cell cluster of a text starts at, as `Canvas.text`
/// draws it with [segmenter]: a tab one blank, other controls nothing, in
/// grapheme mode a mark without a base dropped.
final class TextColumns implements RowColumns {
  /// The columns of a text measured with [segmenter]; of none until it
  /// [measure]s one.
  TextColumns(this.segmenter);

  /// What finds the clusters and their widths, as the canvas draws them.
  final TextSegmenter segmenter;

  final _scan = ClusterScan();

  // the text measured, the offsets its clusters start at followed by its
  // length, and the column of each
  var _text = '';
  var _starts = <int>[0];
  var _columns = <int>[0];

  /// The offsets its clusters start at, then its length.
  List<int> get starts => _starts;

  /// The column of each cluster, then its width.
  List<int> get columns => _columns;

  /// The columns the text takes.
  @override
  int get width => _columns.last;

  /// Measures [text], unless it is the text measured last.
  void measure(String text) {
    if (identical(text, _text) && _starts.isNotEmpty) {
      return;
    }
    _text = text;
    measureClusters(text, segmenter, _starts = [], _columns = [], _scan);
  }

  /// The column [offset] of the text is at: that of the cluster it starts
  /// or is inside.
  @override
  int columnOf(int offset) => _columns[_indexOf(offset)];

  /// The first column at or after [column] that a cluster starts at; the
  /// text's width past it.
  @override
  int startAtOrAfter(int column) {
    final c = _columns;
    var lo = 0;
    var hi = c.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (c[mid] < column) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return c[lo] < column ? column : c[lo];
  }

  /// The last column at or before [column] that a cluster starts at.
  @override
  int startAtOrBefore(int column) {
    final c = _columns;
    var lo = 0;
    var hi = c.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (c[mid] <= column) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return c[lo];
  }

  int _indexOf(int offset) {
    final s = _starts;
    var lo = 0;
    var hi = s.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (s[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}

/// Measures the cell clusters of [text] as `Canvas.text` draws them with
/// [segmenter] (see [TextColumns]): adds to [starts] the offset each starts
/// at, then the text's length, and to [columns] the column of each, then
/// the text's width. [scan] is scratch.
void measureClusters(
  String text,
  TextSegmenter segmenter,
  List<int> starts,
  List<int> columns,
  ClusterScan scan,
) {
  final graphemes = segmenter.mode == TextMode.graphemes;
  var column = 0;
  // a mark at the start or after a control has no base
  var baseless = true;
  for (var i = 0; i < text.length; i = scan.end) {
    starts.add(i);
    columns.add(column);
    segmenter.scan(text, i, scan);
    var w = scan.width;
    final control = w == 0;
    if (control) {
      w = scan.first == 0x09 ? 1 : 0;
    } else if (graphemes && (baseless || scan.length > 1)) {
      // the canvas drops a mark without a base, or a cluster that starts
      // with a code point of no width
      w = stringWidth(
        text.substring(i, scan.end),
        ambiguousWidth: segmenter.ambiguousWidth,
      );
    }
    baseless = control;
    column += w;
  }
  starts.add(text.length);
  columns.add(column);
}

/// The render object whose caret each presenter shows.
final _holders = Expando<RenderObject>('caret');

/// Shows the terminal's cursor in [shape] at [x], [y] of [object], which
/// is being painted with [ctx]: from this frame on it stays there, whatever
/// else repaints, until [object] shows it elsewhere or hides it, or
/// another object shows it. Where an ancestor cuts that cell off (it is
/// outside the ancestor's bounds), the cursor is hidden instead
/// ([hideCaret]).
///
/// One object holds the cursor at a time, the last to show it, and only
/// it hides it: of objects that show it while they have the focus and
/// hide it otherwise, the one with the focus keeps it as the focus moves
/// within a frame, whichever paints last.
///
/// The cell's place on the screen is [object]'s
/// [RenderObject.globalOffset]: a frame paints each object at its offsets
/// in the objects above it. Not the canvas's clip, which may be narrower:
/// a view that scrolled repaints only the rows the scroll exposed. So
/// that the cursor goes with it, or is hidden, when such a repaint cuts it
/// off, the object that holds it is painted however it is cut off
/// ([RenderObject.paintedWhenCutOff]) until it hides it.
void showCaret(
  PaintContext ctx,
  RenderObject object,
  int x,
  int y, {
  CursorShape shape = CursorShape.bar,
}) {
  final cell = _onScreen(object, x, y);
  if (cell == null) {
    hideCaret(ctx, object);
    return;
  }
  final (cx, cy) = cell;
  final p = ctx.presenter;
  final was = _holders[p];
  if (!identical(was, object)) {
    was?.paintedWhenCutOff = false;
    _holders[p] = object;
    object.paintedWhenCutOff = true;
  }
  p
    ..cursorVisible = true
    ..cursorX = cx
    ..cursorY = cy
    ..cursorShape = shape;
}

/// Where the cell [x], [y] of [object] is on the screen; null when it is
/// outside [object] or one of its ancestors.
(int, int)? _onScreen(RenderObject object, int x, int y) {
  var cx = x;
  var cy = y;
  for (RenderObject? o = object; o != null; o = o.parent) {
    if (cx < 0 || cy < 0 || cx >= o.width || cy >= o.height) {
      return null;
    }
    cx += o.parentData.dx;
    cy += o.parentData.dy;
  }
  return (cx, cy);
}

/// Hides the terminal's cursor, when [object] showed it last
/// ([showCaret]) on the terminal [ctx] paints. An object that leaves the
/// tree hides it in its `detach`, with the context it was painted with
/// last.
void hideCaret(PaintContext ctx, RenderObject object) {
  final p = ctx.presenter;
  if (identical(_holders[p], object)) {
    _holders[p] = null;
    object.paintedWhenCutOff = false;
    p.cursorVisible = false;
  }
}
