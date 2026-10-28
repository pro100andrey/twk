// The Code tab's text as twk's SelectionArea selects in it
// (doc/design.md, "The mouse"): the lines of a view that paints them
// itself (highlighted tokens, line numbers, scrolled both ways), a
// Selectable, so that the area selects in them as in a Text.
import 'package:twk/twk.dart';

import '../paint.dart';

/// The code as the Code tab selects in it: [source] and where each of its
/// lines starts and ends, offsets in UTF-16 code units.
final class CodeText {
  CodeText(this.source) {
    for (var i = 0; i < source.length; i++) {
      if (source.codeUnitAt(i) == 0x0A) {
        _ends.add(i);
        _starts.add(i + 1);
      }
    }
    _ends.add(source.length);
  }

  final String source;
  final _starts = [0];
  final _ends = <int>[];

  int get lineCount => _starts.length;

  /// Where line [i] starts and ends, its line break left out.
  (int, int) line(int i) => (_starts[i], _ends[i]);

  /// The range a cell at [column] of line [line] stands for, as
  /// [Selectable.selectableRangeAt] gives it: the cluster drawn there
  /// (what takes no cell with the one after it); left of the line's text
  /// where it starts, right of it where the next line starts; above the
  /// first line the start, below the last the end.
  (int, int) rangeAt(int line, int column) {
    if (line < 0) {
      return (0, 0);
    }
    if (line >= lineCount) {
      return (source.length, source.length);
    }
    final (start, end) = this.line(line);
    if (column < 0) {
      return (start, start);
    }
    var col = 0;
    var from = start;
    var i = start;
    while (i < end) {
      final next = source.characterEndAfter(i);
      final w = widthOf(source.substring(i, next));
      i = next;
      if (w == 0) {
        continue;
      }
      if (column < col + w) {
        return (from, i);
      }
      col += w;
      from = i;
    }
    final next = line + 1 < lineCount ? _starts[line + 1] : source.length;
    return (next, next);
  }

  /// [start, end) as copied, as the design's shell copies it: the code's
  /// own text, its line breaks kept, the blanks that end a line dropped,
  /// those that end what is selected too ([trimLineEnds]).
  String copied(int start, int end) =>
      trimLineEnds(source.substring(start, end));
}

/// [text] with the blanks that end each of its lines dropped, those that
/// end it too, as the design's shell copies a selection of the code
/// (where `SelectionArea` keeps the blanks ending what is selected when
/// text follows on the line, as a terminal does).
String trimLineEnds(String text) => text
    .split('\n')
    .map((l) => l.replaceFirst(RegExp(r'[ \t]+$'), ''))
    .join('\n');

/// What a toast says [text] is: its lines, or within a line its
/// characters.
String copiedWhat(String text) {
  final n = '\n'.allMatches(text).length + 1;
  if (n > 1) {
    return '$n lines';
  }
  final c = text.characterCount;
  return c == 1 ? '1 character' : '$c characters';
}

/// The lines of [code] as [onPaint] paints them, line [scroll] on the
/// first row, column [scrollX] at column [x0]: selected in by the
/// `SelectionArea` above it, which [onPaint] is told the selection of
/// (null while nothing is selected). Cells left of [x0] (the line
/// numbers) are not text. A drag past its top or bottom scrolls it by
/// [scrollBy], past its left or right edge by [scrollAcross], each saying
/// whether it moved.
final class CodeLines extends LeafRenderObjectWidget {
  const CodeLines({
    required this.code,
    required this.x0,
    required this.scroll,
    required this.scrollX,
    required this.scrollBy,
    required this.scrollAcross,
    required this.onPaint,
    super.key,
  });

  final CodeText code;
  final int x0;

  /// Read whenever a cell is turned into a line and a column: the view
  /// may scroll between two frames.
  final int Function() scroll;
  final int Function() scrollX;
  final bool Function(int rows) scrollBy;
  final bool Function(int columns) scrollAcross;
  final void Function(Painter p, (int, int)? selection) onPaint;

  @override
  RenderCodeLines createRenderObject(BuildContext context) =>
      RenderCodeLines(this);

  @override
  void updateRenderObject(BuildContext context, RenderCodeLines renderObject) {
    renderObject.update(this);
  }
}

/// What a [CodeLines] lays out and paints: as big as the constraints
/// allow.
final class RenderCodeLines extends RenderObject with Selectable {
  RenderCodeLines(this._widget);

  CodeLines _widget;
  void update(CodeLines w) {
    _widget = w;
    markNeedsPaint();
  }

  @override
  String get selectableText => _widget.code.source;

  @override
  (int, int) selectableRangeAt(int x, int y) {
    final w = _widget;
    final line = y + w.scroll();
    // the line numbers, and what the view scrolled off to the left of them
    if (x < w.x0 && line >= 0 && line < w.code.lineCount) {
      final (start, _) = w.code.line(line);
      return (start, start);
    }
    return w.code.rangeAt(line, x - w.x0 + w.scrollX());
  }

  @override
  bool scrollSelectionBy(int rows) => _widget.scrollBy(rows);

  @override
  bool scrollSelectionAcross(int columns) => _widget.scrollAcross(columns);

  @override
  bool hitTestSelf(int x, int y) => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW < BoxConstraints.unbounded ? c.maxW : c.minW;
    height = c.maxH < BoxConstraints.unbounded ? c.maxH : c.minH;
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas
      ..save()
      ..clipRect(0, 0, width, height);
    _widget.onPaint(Painter(canvas, width, height), selection);
    canvas.restore();
  }
}
