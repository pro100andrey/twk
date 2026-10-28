// The debug paints of a PipelineOwner: the repaint rainbow tints what each
// repaint covered, the relayout highlight outlines what was laid out.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

const _black = Color.rgb(0, 0, 0);

/// A render tree filling a whole screen.
base class View {
  View(this.width, this.height) : screen = Screen(width, height) {
    pen = styles.pen(const Pen(bg: _black));
    owner = PipelineOwner(() {});
  }

  final int width;
  final int height;
  final Screen screen;
  late final int pen;
  late final PipelineOwner owner;

  StyleTable get styles => screen.styles;

  void frame() {
    owner
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    screen.render();
  }

  /// The style of each cell, row by row.
  List<int> get cellStyles => List.of(screen.surface.styles);

  int styleAt(int x, int y) => screen.surface.styles[y * width + x];

  /// What a cell [pen] painted holds when nothing tints it.
  int get plain => styles.style(bg: _black);
}

/// A row of two blocks over a block that is a repaint boundary.
final class Tree extends View {
  Tree(super.width, super.height) {
    a = Block(['a'], pen);
    b = Block(['b'], pen);
    bottom = Block(['bottom'], pen, boundary: true);
    top = RenderRow([(a, width ~/ 2), (b, width - width ~/ 2)]);
    root = RenderColumn([(top, height ~/ 2), (bottom, height - height ~/ 2)]);
    owner.root = root;
  }

  late final Block a;
  late final Block b;
  late final Block bottom;
  late final RenderRow top;
  late final RenderColumn root;

  List<RenderObject> get all => [root, top, a, b, bottom];
}

/// [lines] of text on a fill of [pen], as big as its constraints let it
/// be; a repaint boundary when [boundary] is set. Counts its layouts; new
/// [lines] lay it out again.
final class Block extends RenderObject {
  Block(this._lines, this.pen, {this.boundary = false});

  List<String> _lines;
  final int pen;
  final bool boundary;
  var layouts = 0;

  List<String> get lines => _lines;
  set lines(List<String> l) {
    _lines = l;
    markNeedsLayout();
  }

  @override
  bool get isRepaintBoundary => boundary;

  @override
  bool get sizedByParent => true;

  @override
  void performLayout(BoxConstraints c) {
    layouts++;
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) {
    ctx.canvas.fill(0, 0, width, height, pen);
    for (var y = 0; y < _lines.length; y++) {
      ctx.canvas.text(0, y, _lines[y], pen);
    }
  }
}

/// Lays its child out [childWidth] wide, wider than itself: the child
/// sticks out, and is cut off at its edges.
final class Window extends RenderObject with RenderObjectWithChildMixin {
  Window(RenderObject c, this.childWidth) {
    child = c;
  }

  final int childWidth;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
    child!.layout(BoxConstraints.tight(childWidth, height));
  }

  @override
  void paint(PaintContext ctx) => paintChild(ctx, child!);
}

/// The cells, as (x, y), whose styles differ between [a] and [b], rows
/// [width] wide.
Set<(int, int)> differing(List<int> a, List<int> b, int width) => {
  for (var i = 0; i < a.length; i++)
    if (a[i] != b[i]) (i % width, i ~/ width),
};

/// The cells of [w] × [h] at [x], [y].
Set<(int, int)> cellsOf(int x, int y, int w, int h) => {
  for (var yy = y; yy < y + h; yy++)
    for (var xx = x; xx < x + w; xx++) (xx, yy),
};

/// The cells along the edges of [o] on the screen.
Set<(int, int)> edgesOf(RenderObject o) {
  final (x, y) = o.globalOffset;
  final x1 = x + o.width - 1;
  final y1 = y + o.height - 1;
  return {
    for (final (cx, cy) in cellsOf(x, y, o.width, o.height))
      if (cx == x || cx == x1 || cy == y || cy == y1) (cx, cy),
  };
}

void main() {
  group('the repaint rainbow', () {
    test('tints only the boundaries that repainted, anew on each repaint', () {
      final v = View(12, 2);
      final a = Block(['a'], v.pen, boundary: true);
      final b = Block(['b'], v.pen, boundary: true);
      v.owner
        ..root = RenderRow([(a, 6), (b, 6)])
        ..debugRepaintRainbow = true;
      v.frame();
      // the root repainted on its own: all of it is tinted
      expect(v.cellStyles.where((s) => v.styles.bgOf(s) == _black), isEmpty);
      var before = v.cellStyles;
      a.markNeedsPaint();
      v.frame();
      expect(differing(before, v.cellStyles, 12), cellsOf(0, 0, 6, 2));
      before = v.cellStyles;
      b.markNeedsPaint();
      v.frame();
      expect(differing(before, v.cellStyles, 12), cellsOf(6, 0, 6, 2));
      before = v.cellStyles;
      a.markNeedsPaint();
      b.markNeedsPaint();
      v.frame();
      expect(differing(before, v.cellStyles, 12), cellsOf(0, 0, 12, 2));
      // two repaints of one frame tell apart
      expect(v.styleAt(0, 0), isNot(v.styleAt(6, 0)));
    });

    test('blends a tint over the background and keeps the rest of a cell', () {
      final v = View(6, 1);
      final pen = v.styles.pen(
        const Pen(
          fg: Color.rgb(200, 100, 0),
          bg: Color.rgb(0, 0, 80),
          attrs: Attr.bold | Attr.underline,
          underlineColor: Color.rgb(0, 200, 0),
          link: 'https://example.com',
        ),
      );
      v.owner
        ..root = Block(['hi'], pen, boundary: true)
        ..debugRepaintRainbow = true;
      v.frame();
      final s = v.styleAt(0, 0);
      expect(v.screen.glyphs.stringOf(v.screen.surface.cells[0]), 'h');
      expect(v.styles.fgOf(s), const Color.rgb(200, 100, 0));
      expect(v.styles.attrsOf(s), Attr.bold | Attr.underline);
      expect(v.styles.underlineColorOf(s), const Color.rgb(0, 200, 0));
      expect(v.styles.linkOf(s), 'https://example.com');
      expect(v.styles.bgOf(s).isRgb, isTrue);
      expect(v.styles.bgOf(s), isNot(const Color.rgb(0, 0, 80)));
    });

    test('tints a boundary only where its ancestors let it paint', () {
      final v = View(10, 1);
      final inner = Block(['0123456789'], v.pen, boundary: true);
      v.owner
        ..root = RenderRow([(Window(inner, 10), 4), (Block([], v.pen), 6)])
        ..debugRepaintRainbow = true;
      v.frame();
      final before = v.cellStyles;
      inner.markNeedsPaint();
      v.frame();
      expect(differing(before, v.cellStyles, 10), cellsOf(0, 0, 4, 1));
    });

    test('repaints all the rows of a log that scrolled, none tinted twice', () {
      final v = View(10, 3);
      final log = RenderLog(pen: v.pen, itemPen: (_, _) => v.pen);
      v.owner
        ..root = log
        ..debugRepaintRainbow = true;
      for (var i = 0; i < 3; i++) {
        log.add('line $i');
      }
      v.frame();
      log.add('line 3');
      v.frame();
      final styles = v.cellStyles.toSet();
      expect(styles, hasLength(1));
      expect(v.styles.bgOf(styles.single), isNot(_black));
    });

    test('repaints all the rows of a log its parent painted last', () {
      final v = View(10, 4);
      final log = RenderLog(pen: v.pen, itemPen: (_, _) => v.pen);
      v.owner
        ..root = RenderColumn([
          (Block(['top'], v.pen), 1),
          (log, 3),
        ])
        ..debugRepaintRainbow = true;
      for (var i = 0; i < 3; i++) {
        log.add('line $i');
      }
      v.frame();
      log.add('line 3');
      v.frame();
      final styles = v.cellStyles.sublist(10).toSet();
      expect(styles, hasLength(1));
      expect(v.styles.bgOf(styles.single), isNot(_black));
    });

    test('tints only the tree of the owner it is set on', () {
      final on = View(4, 1);
      final off = View(4, 1);
      for (final v in [on, off]) {
        v.owner.root = Block(['x'], v.pen, boundary: true);
      }
      on.owner.debugRepaintRainbow = true;
      on.frame();
      off.frame();
      expect(on.styles.bgOf(on.styleAt(0, 0)), isNot(_black));
      expect(off.cellStyles.toSet(), {off.plain});
    });

    test('turned on or off, repaints everything', () {
      final v = View(4, 1);
      v.owner.root = Block(['x'], v.pen, boundary: true);
      v.frame();
      final plain = v.cellStyles;
      expect(v.owner.debugRepaintRainbow, isFalse);
      v.owner.debugRepaintRainbow = true;
      expect(v.owner.debugRepaintRainbow, isTrue);
      expect(v.owner.hasWork, isTrue);
      v.frame();
      expect(differing(plain, v.cellStyles, 4), cellsOf(0, 0, 4, 1));
      v.owner.debugRepaintRainbow = false;
      expect(v.owner.hasWork, isTrue);
      v.frame();
      expect(v.cellStyles, plain);
    });
  });

  group('the relayout highlight', () {
    test('outlines exactly the objects laid out since the last frame', () {
      final lit = Tree(12, 8)..owner.debugRelayoutHighlight = true;
      final plain = Tree(12, 8);
      void frame() {
        lit.frame();
        plain.frame();
      }

      Set<(int, int)> outlined() =>
          differing(plain.cellStyles, lit.cellStyles, 12);

      frame();
      expect(outlined(), {for (final o in lit.all) ...edgesOf(o)});
      for (final t in [lit, plain]) {
        t.a.lines = ['A'];
      }
      frame();
      expect([lit.a.layouts, lit.b.layouts, lit.bottom.layouts], [2, 1, 1]);
      expect(outlined(), edgesOf(lit.a));
      for (final t in [lit, plain]) {
        t.bottom.lines = ['B'];
      }
      frame();
      // the root did not repaint: a keeps its outline
      expect(outlined(), {...edgesOf(lit.a), ...edgesOf(lit.bottom)});
      for (final t in [lit, plain]) {
        t.b.markNeedsPaint();
      }
      frame();
      // the root repainted all of it, and nothing was laid out
      expect(outlined(), isEmpty);
    });

    test('outlines what one frame laid out in one tint, the next anew', () {
      final v = Tree(12, 8)
        ..owner.debugRelayoutHighlight = true
        ..frame();
      // the right edge of a and the left edge of b, outlined once each
      expect(v.styleAt(5, 1), isNot(v.plain));
      expect(v.styleAt(5, 1), v.styleAt(6, 1));
      v.a.lines = ['A'];
      v.frame();
      final first = v.styleAt(0, 1);
      expect(first, isNot(v.plain));
      v.a.lines = ['a'];
      v.frame();
      expect(v.styleAt(0, 1), isNot(v.plain));
      expect(v.styleAt(0, 1), isNot(first));
    });

    test('outlines both halves of a wide glyph on an edge alike', () {
      final v = View(4, 3);
      v.owner
        ..root = RenderRow([
          (Block(['', 'ab中'], v.pen), 4),
        ])
        ..debugRelayoutHighlight = true;
      v.frame();
      expect(v.screen.surface.cells[1 * 4 + 2] & kWide, kWide);
      expect(v.styleAt(3, 1), isNot(v.styleAt(1, 1)));
      expect(v.styleAt(2, 1), v.styleAt(3, 1));
      // on the left edge
      final w = View(4, 3);
      w.owner
        ..root = RenderRow([
          (Block(['', '中ab'], w.pen), 4),
        ])
        ..debugRelayoutHighlight = true;
      w.frame();
      expect(w.screen.surface.cells[1 * 4] & kWide, kWide);
      expect(w.styleAt(0, 1), isNot(w.styleAt(2, 1)));
      expect(w.styleAt(1, 1), w.styleAt(0, 1));
    });

    test('outlines every cell of an object two columns wide or less', () {
      final v = View(2, 3);
      v.owner
        ..root = Block([], v.pen)
        ..debugRelayoutHighlight = true;
      v.frame();
      expect(v.cellStyles.toSet(), isNot(contains(v.plain)));
    });

    test('repaints all the rows of a log that scrolled', () {
      final v = View(10, 3);
      final log = RenderLog(pen: v.pen, itemPen: (_, _) => v.pen);
      v.owner
        ..root = log
        ..debugRelayoutHighlight = true;
      for (var i = 0; i < 3; i++) {
        log.add('line $i');
      }
      v.frame();
      expect(v.styleAt(0, 1), isNot(v.plain));
      log.add('line 3');
      v.frame();
      expect(v.cellStyles.toSet(), {v.plain});
    });

    test('turned on, outlines nothing laid out before; off, repaints', () {
      final lit = Tree(12, 8);
      final plain = Tree(12, 8);
      void frame() {
        lit.frame();
        plain.frame();
      }

      Set<(int, int)> outlined() =>
          differing(plain.cellStyles, lit.cellStyles, 12);

      frame();
      expect(lit.owner.debugRelayoutHighlight, isFalse);
      lit.owner.debugRelayoutHighlight = true;
      expect(lit.owner.debugRelayoutHighlight, isTrue);
      plain.owner.markAllDirty();
      frame();
      expect(outlined(), isEmpty);
      for (final t in [lit, plain]) {
        t.a.lines = ['A'];
      }
      frame();
      expect(outlined(), edgesOf(lit.a));
      lit.owner.debugRelayoutHighlight = false;
      expect(lit.owner.hasWork, isTrue);
      frame();
      expect(outlined(), isEmpty);
    });
  });
}
