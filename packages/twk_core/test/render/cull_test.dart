// A child its parent's clip leaves no cell of is not painted, nor anything
// inside it: a scroll view paints what shows of its content, not all of
// it. An object whose paint does more than paint cells (shows the cursor)
// is painted however it is cut off, when it says so. What a viewport kept
// of its rows has the objects inside it forget what they painted, but only
// those that painted since they last forgot it.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/vt.dart';

/// A tree on a screen of [width] × [height] cells, each frame's bytes fed
/// to an emulator.
final class View {
  View(this.width, this.height, RenderObject root)
    : screen = Screen(width, height),
      vt = Vt(width, height) {
    owner = PipelineOwner(() {})..root = root;
  }

  final int width;
  final int height;
  final Screen screen;
  final Vt vt;
  late final PipelineOwner owner;

  void frame() {
    owner
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    final bytes = screen.render();
    if (bytes != null) {
      vt.feed(bytes);
    }
  }

  List<String> get shown => vt.lines;
}

/// One row reading [label], counting its paints and the times it was told
/// to forget what it painted.
final class Row extends RenderObject {
  Row(this.label);

  final String label;
  var paints = 0;
  var forgets = 0;

  /// The clip bounds of its last paint.
  (int, int, int, int)? clip;

  @override
  void invalidatePaintCache() => forgets++;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW < BoxConstraints.unbounded ? c.maxW : c.constrainW(10);
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) {
    paints++;
    clip = ctx.canvas.clipBounds;
    ctx.canvas.text(0, 0, label, ctx.canvas.styles.pen(const Pen()));
  }
}

/// A box as big as its child, counting its paints.
final class Box extends RenderObject with RenderObjectWithChildMixin {
  Box([RenderObject? child]) {
    this.child = child;
  }

  var paints = 0;

  @override
  void performLayout(BoxConstraints c) {
    final ch = child;
    if (ch == null) {
      width = c.minW;
      height = c.minH;
      return;
    }
    ch.layout(c, parentUsesSize: true);
    width = ch.width;
    height = ch.height;
  }

  @override
  void paint(PaintContext ctx) {
    paints++;
    final ch = child;
    if (ch != null) {
      paintChild(ctx, ch);
    }
  }
}

/// [n] rows `<label> 0` and on.
List<Row> rows(int n, [String label = 'row']) => [
  for (var i = 0; i < n; i++) Row('$label $i'),
];

RenderFlex column(List<RenderObject> children) =>
    RenderFlex(direction: Axis.vertical, children: children);

void main() {
  group('a child the clip leaves nothing of', () {
    test('is not painted: a viewport paints the rows in view', () {
      final r = rows(100);
      final vp = RenderViewport(child: column(r));
      final v = View(20, 5, vp)..frame();
      expect(v.shown, ['row 0', 'row 1', 'row 2', 'row 3', 'row 4']);
      expect([for (final x in r.take(6)) x.paints], [1, 1, 1, 1, 1, 0]);
      expect(r.skip(5).every((x) => x.paints == 0), isTrue);
    });

    test('nor is anything inside it', () {
      final inner = Row('inner');
      final box = Box(Box(inner));
      final vp = RenderViewport(child: column([...rows(5), box]));
      View(20, 5, vp).frame();
      expect(box.paints, 0);
      expect(inner.paints, 0);
    });

    test('a scroll of a row paints the row it exposed', () {
      final r = rows(100);
      final vp = RenderViewport(child: column(r));
      final v = View(20, 5, vp)..frame();
      vp.scrollOffset = 1;
      v.frame();
      expect(v.shown, ['row 1', 'row 2', 'row 3', 'row 4', 'row 5']);
      expect([for (final x in r.take(7)) x.paints], [1, 1, 1, 1, 1, 1, 0]);
      vp.scrollOffset = 3;
      v.frame();
      expect(v.shown, ['row 3', 'row 4', 'row 5', 'row 6', 'row 7']);
      expect(
        [for (final x in r.take(9)) x.paints],
        [1, 1, 1, 1, 1, 1, 1, 1, 0],
      );
    });

    test('a child partly in the clip is painted, cut off', () {
      final tall = Box(column(rows(3)));
      final vp = RenderViewport(child: column([...rows(4), tall]));
      final v = View(20, 5, vp)..frame();
      expect(tall.paints, 1);
      expect(v.shown.last, 'row 0');
    });

    test('is not told to forget what it painted, by its parent', () {
      final r = rows(10);
      final vp = RenderViewport(child: column(r));
      View(20, 3, vp).frame();
      // the column painted over the children it shows; those it cuts off
      // it does not visit (flex_paint_test)
      expect([for (final x in r) x.forgets], [1, 1, 1, 0, 0, 0, 0, 0, 0, 0]);
    });
  });

  group('a viewport that kept rows', () {
    test('has only what painted since forget it again', () {
      final r = rows(100);
      final vp = RenderViewport(child: column([for (final x in r) Box(x)]));
      final v = View(20, 5, vp)..frame();
      for (var i = 1; i <= 20; i++) {
        vp.scrollOffset = i;
        v.frame();
      }
      expect(v.shown, ['row 20', 'row 21', 'row 22', 'row 23', 'row 24']);
      // never painted, nor painted over: nothing to forget
      expect(r[90].forgets, 0);
      // painted on the first frame (painted over by its box), forgotten by
      // the scroll after, and then left alone
      expect(r[0].forgets, 2);
      // what came into view last: painted over, painted, forgotten
      expect(r[24].forgets, 2);
    });

    test('has what repainted on its own since forget it', () {
      final inner = RenderViewport(child: column(rows(10, 'in')));
      final vp = RenderViewport(
        child: column([
          ...rows(2),
          RenderConstrainedBox(
            additionalConstraints: const BoxConstraints(
              0,
              BoxConstraints.unbounded,
              3,
              3,
            ),
            child: inner,
          ),
          ...rows(20),
        ]),
      );
      final in0 = (inner.child! as RenderFlex).firstChild! as Row;
      final v = View(20, 5, vp)..frame();
      expect(in0.forgets, 1);
      vp.scrollOffset = 1;
      v.frame();
      expect(v.shown, ['row 1', 'in 0', 'in 1', 'in 2', 'row 0']);
      expect(in0.forgets, 2);
      // repainted on its own, the objects above it not painted
      inner.markNeedsPaint();
      v.frame();
      expect(in0.forgets, 3);
      vp.scrollOffset = 2;
      v.frame();
      expect(v.shown, ['in 0', 'in 1', 'in 2', 'row 0', 'row 1']);
      expect(in0.forgets, 4);
    });
  });

  group('an object painted when cut off', () {
    test('is painted, with nothing in the clip, and what is above it', () {
      final r = rows(10);
      final kept = r[8]..paintedWhenCutOff = true;
      final box = Box(r[9]);
      final vp = RenderViewport(
        child: column([...r.take(8), Box(kept), box]),
      );
      final v = View(20, 3, vp)..frame();
      expect(v.shown, ['row 0', 'row 1', 'row 2']);
      expect(kept.paints, 1);
      final (x0, _, x1, _) = kept.clip!;
      expect(x0, x1);
      // its siblings are not
      expect(r[7].paints, 0);
      expect(box.paints, 0);
    });

    test('not once it says so', () {
      final r = rows(10);
      final vp = RenderViewport(child: column(r));
      final v = View(20, 3, vp);
      r[9].paintedWhenCutOff = true;
      v.frame();
      expect(r[9].paints, 1);
      r[9].paintedWhenCutOff = false;
      vp.markNeedsPaint();
      v.frame();
      expect(r[9].paints, 1);
    });

    test('moved elsewhere, has its old parent painted no more', () {
      final kept = Row('kept')..paintedWhenCutOff = true;
      final from = Box(kept);
      final to = Box();
      final vp = RenderViewport(child: column([...rows(5), from, to]));
      final v = View(20, 3, vp)..frame();
      expect(from.paints, 1);
      expect(kept.paints, 1);
      from.child = null;
      to.child = kept;
      vp.markNeedsPaint();
      v.frame();
      expect(from.paints, 1);
      expect(to.paints, 1);
      expect(kept.paints, 2);
    });

    test('set while detached, counts once attached', () {
      final kept = Row('kept')..paintedWhenCutOff = true;
      final box = Box(Box(kept));
      final vp = RenderViewport(child: column([...rows(5), box]));
      View(20, 3, vp).frame();
      expect(box.paints, 1);
      expect(kept.paints, 1);
    });
  });
}
