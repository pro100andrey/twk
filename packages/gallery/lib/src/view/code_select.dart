// The Code tab's text as twk's SelectionArea selects in it
// (doc/design.md, "The mouse"): the lines of a view that paints them
// itself (highlighted tokens, line numbers, scrolled both ways), a
// Selectable, so that the area selects in them as in a Text.
import 'package:twk/twk.dart';

import '../model/code_text.dart';
import '../paint.dart';

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
