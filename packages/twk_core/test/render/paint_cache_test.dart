// A child its parent paints forgets what it kept of its paint: the
// parent's paint covered its cells. One the clip leaves no cell of is not
// painted, its cells are as it left them, and it keeps what it kept: a
// boundary the rows of a repaint around it miss repaints only what changed
// in it on its next frame (a log only the line appended to it). One that
// is painted however it is cut off (a cursor) is still told to forget.
import 'dart:math';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// A tree on a screen of [width] × [height] cells.
final class View {
  View(this.width, this.height, this.root) : screen = Screen(width, height) {
    owner = PipelineOwner(() {}, segmenter: screen.canvas.segmenter)
      ..root = root;
  }

  final int width;
  final int height;
  final RenderObject root;
  final Screen screen;
  late final PipelineOwner owner;

  /// Lays out and paints what was marked; the rows of the surface it
  /// painted, as many cells as it painted of each.
  List<int> frame() {
    owner
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    final s = screen.surface;
    final painted = [
      for (var y = 0; y < height; y++) max(0, s.dirtyHi[y] - s.dirtyLo[y]),
    ];
    screen.render();
    return painted;
  }

  /// A pen with an opaque background, as a repaint boundary needs.
  int get opaque => screen.styles.pen(const Pen(bg: Color.rgb(0, 0, 0)));
}

/// Its children one below the other, each as many rows high as [rows]
/// says, all of them painted whatever the clip shows of them: what paints
/// them is [RenderObject.paintChild] alone.
final class Rows extends RenderObject with ContainerRenderObjectMixin<RowData> {
  Rows(this.rows, List<RenderObject> children) {
    addAll(children);
  }

  final List<int> rows;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! RowData) {
      child.parentData = RowData();
    }
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
    var y = 0;
    var i = 0;
    for (var child = firstChild; child != null; i++) {
      child.layout(BoxConstraints.tight(width, rows[i]));
      child.parentData.dy = y;
      y += rows[i];
      child = (child.parentData as RowData).nextSibling;
    }
  }

  @override
  void paint(PaintContext ctx) {
    for (var child = firstChild; child != null;) {
      paintChild(ctx, child);
      child = (child.parentData as RowData).nextSibling;
    }
  }
}

/// Where a child of [Rows] is, and its siblings.
final class RowData extends ParentData with ContainerParentDataMixin {}

/// A line of text, counting its paints and the times it was told to forget
/// what it painted; a repaint boundary when [boundary].
final class Line extends RenderObject {
  Line(this._text, {this.boundary = false});

  String _text;

  /// Shows [t] from the next frame on.
  void show(String t) {
    _text = t;
    markNeedsPaint();
  }

  final bool boundary;
  var paints = 0;
  var forgets = 0;

  @override
  bool get isRepaintBoundary => boundary;

  @override
  bool get sizedByParent => true;

  @override
  void invalidatePaintCache() => forgets++;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) {
    paints++;
    final pen = ctx.canvas.styles.pen(
      const Pen(fg: Color.rgb(200, 200, 200), bg: Color.rgb(10, 10, 10)),
    );
    ctx.canvas
      ..fill(0, 0, width, height, pen)
      ..text(0, 0, _text, pen);
  }
}

void main() {
  test('a boundary the rows of a repaint around it miss keeps what it kept '
      'of its paint', () {
    final kept = Line('kept', boundary: true);
    final status = Line('⠋');
    final v = View(8, 4, RenderBox(pen: 0, boundary: true));
    (v.root as RenderBox)
      ..pen = v.opaque
      ..child = Rows([3, 1], [kept, status]);
    v.frame();
    final forgets = kept.forgets;
    status.show('⠙');
    expect(v.frame(), [0, 0, 0, 8]);
    expect(kept.forgets, forgets, reason: 'not painted, nothing to forget');
    expect(kept.paints, 1);
  });

  test('a log beside a status row repaints only the line appended to it', () {
    final status = Line('⠋');
    final root = RenderBox(pen: 0, boundary: true);
    final v = View(8, 5, root);
    final pen = v.opaque;
    final log = RenderLog(pen: pen, itemPen: (_, _) => pen);
    root
      ..pen = pen
      ..child = Rows([4, 1], [log, status]);
    for (var i = 0; i < 6; i++) {
      log.add('line $i');
    }
    v.frame();
    log.add('line 6');
    // scrolled by a row: the row it exposed painted
    expect(v.frame(), [0, 0, 0, 8, 0]);
    status.show('⠙');
    expect(v.frame(), [0, 0, 0, 0, 8]);
    log.add('line 7');
    expect(v.frame(), [0, 0, 0, 8, 0], reason: 'the status row repainted');
  });

  test('a child painted however it is cut off is told to forget even where '
      'the clip leaves none of it', () {
    final cursor = Line('|')..paintedWhenCutOff = true;
    final status = Line('⠋');
    final v = View(8, 4, RenderBox(pen: 0, boundary: true));
    (v.root as RenderBox)
      ..pen = v.opaque
      ..child = Rows([3, 1], [cursor, status]);
    v.frame();
    final forgets = cursor.forgets;
    final paints = cursor.paints;
    status.show('⠙');
    expect(v.frame(), [0, 0, 0, 8]);
    expect(cursor.paints, paints + 1, reason: 'painted, in an empty clip');
    expect(cursor.forgets, forgets + 1);
  });
}
