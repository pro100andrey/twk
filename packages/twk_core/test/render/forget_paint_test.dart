// Forgetting what was painted visits only the objects that painted since
// they last forgot: a long Column scrolled a row a frame in a viewport, or
// with one child marked for paint, costs what the clip shows, not a walk
// over every child. What the screen shows is the same as before.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// A tree on a screen of [width] × [height] cells.
final class View {
  View(this.width, this.height, RenderObject root)
    : screen = Screen(width, height) {
    owner = PipelineOwner(() {})..root = root;
  }

  final int width;
  final int height;
  final Screen screen;
  late final PipelineOwner owner;

  void frame() {
    owner
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    screen.render();
  }

  /// The text of row [y].
  String row(int y) {
    final s = screen.surface;
    return String.fromCharCodes(
      s.cells.sublist(y * s.width, (y + 1) * s.width),
    ).trimRight();
  }
}

// how many times any Line had its parent data read: a container reads it
// on each child it visits ([RenderObject.visitChildren]), and a paint on
// each child it paints
var reads = 0;

/// A row reading [label], counting the reads of its parent data.
final class Line extends RenderObject {
  Line(this.label);

  final String label;
  var paints = 0;
  var forgets = 0;

  @override
  ParentData get parentData {
    reads++;
    return super.parentData;
  }

  @override
  set parentData(ParentData d) => super.parentData = d;

  @override
  void invalidatePaintCache() => forgets++;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(label.length);
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) {
    paints++;
    ctx.canvas.text(0, 0, label, ctx.canvas.styles.pen(const Pen()));
  }
}

/// A boundary as big as its constraints allow, its child as long as it
/// likes and cut off at its bounds.
final class Boundary extends RenderObject with RenderObjectWithChildMixin {
  Boundary(RenderObject child) {
    this.child = child;
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  void performLayout(BoxConstraints c) {
    final ch = child!
      ..layout(
        BoxConstraints(c.minW, c.maxW, 0, BoxConstraints.unbounded),
        parentUsesSize: true,
      );
    width = ch.width;
    height = c.constrainH(ch.height);
  }

  @override
  void paint(PaintContext ctx) => paintChild(ctx, child!);
}

const n = 10000;

List<Line> lines() => [for (var i = 0; i < n; i++) Line('row $i')];

void main() {
  test('a 10k Column scrolled a row a frame visits what the clip shows', () {
    final children = lines();
    final viewport = RenderViewport(
      child: RenderColumn([for (final l in children) (l, 1)]),
    );
    final view = View(20, 20, viewport)..frame();
    expect(view.row(0), 'row 0');
    for (var f = 1; f <= 50; f++) {
      viewport.scrollOffset = f;
      reads = 0;
      view.frame();
      // the row the scroll brought in, painted, and those the bisection
      // probes: a few dozen, not 10k
      expect(reads, lessThan(100), reason: 'frame $f');
      expect(view.row(0), 'row $f');
      expect(view.row(19), 'row ${f + 19}');
    }
    // each frame painted the row it brought in, which then forgot it
    expect(children[69].paints, 1);
    expect(children[69].forgets, greaterThan(0));
    expect(children[100].paints, 0);
  });

  test('a 10k Column with a child marked for paint visits what painted', () {
    final children = lines();
    final column = RenderColumn([for (final l in children) (l, 1)]);
    final view = View(20, 20, Boundary(column))..frame();
    for (var f = 0; f < 20; f++) {
      children[f % 20].markNeedsPaint();
      reads = 0;
      view.frame();
      // its rows are repainted, and only the children that painted are
      // told to forget what those rows cut through
      expect(reads, lessThan(100), reason: 'frame $f');
      expect(view.row(f % 20), 'row ${f % 20}');
    }
  });

  test('a child moved with what it painted is forgotten by its new parent', () {
    final a = [for (var i = 0; i < 10; i++) Line('a $i')];
    final b = [for (var i = 0; i < 10; i++) Line('b $i')];
    final columnA = RenderColumn([for (final l in a) (l, 1)]);
    final columnB = RenderColumn([for (final l in b) (l, 1)]);
    final viewportA = RenderViewport(child: columnA);
    final viewportB = RenderViewport(child: columnB);
    final view = View(20, 10, RenderColumn([(viewportA, 5), (viewportB, 5)]))
      ..frame();
    // a 2 has painted and not forgotten since; it goes on top of b
    final moved = a[2];
    columnA.remove(moved);
    columnB.insert(moved);
    view.frame();
    expect(view.row(5), 'a 2');
    expect(view.row(6), 'b 0');
    // the scroll keeps the rows it showed: the new parent tells it to
    // forget what it painted, the old one does not
    final forgets = moved.forgets;
    viewportA.scrollOffset = 1;
    view.frame();
    expect(view.row(0), 'a 1');
    expect(moved.forgets, forgets);
    viewportB.scrollOffset = 1;
    view.frame();
    expect(view.row(5), 'b 0');
    expect(moved.forgets, greaterThan(forgets));
  });

  test('a child moved back and forth is forgotten by where it is', () {
    final a = [for (var i = 0; i < 10; i++) Line('a $i')];
    final b = [for (var i = 0; i < 10; i++) Line('b $i')];
    final columnA = RenderColumn([for (final l in a) (l, 1)]);
    final columnB = RenderColumn([for (final l in b) (l, 1)]);
    final viewportA = RenderViewport(child: columnA);
    final viewportB = RenderViewport(child: columnB);
    final view = View(20, 10, RenderColumn([(viewportA, 5), (viewportB, 5)]))
      ..frame();
    final moved = a[2];
    for (var i = 0; i < 41; i++) {
      final (from, to) = i.isEven ? (columnA, columnB) : (columnB, columnA);
      from.remove(moved);
      to.insert(moved);
      view.frame();
    }
    expect(view.row(5), 'a 2');
    // ends in column B, on top
    expect(view.row(5), 'a 2');
    expect(view.row(0), 'a 0');
    final forgets = [
      for (final l in [...a, ...b]) l.forgets,
    ];
    viewportA.scrollOffset = 1;
    view.frame();
    expect(view.row(0), 'a 1');
    // what column A showed is forgotten, the child it no longer has is not
    for (final i in [0, 1, 3, 4]) {
      expect(a[i].forgets, greaterThan(forgets[i]), reason: 'a $i');
    }
    expect(moved.forgets, forgets[2]);
    viewportB.scrollOffset = 1;
    view.frame();
    expect(view.row(5), 'b 0');
    expect(moved.forgets, greaterThan(forgets[2]));
    expect(b[3].forgets, greaterThan(forgets[13]));
  });
}
