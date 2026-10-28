// An object repainted whole with its boundaries (a follower of an anchor)
// is painted whenever a boundary it is in repaints any rows, whichever
// boundary it is in now: moved into another, it follows that one, and
// dropped from the tree, none. A flush finds them from the boundaries it
// repaints, through the parts of them that hold any: one that repaints no
// boundary with a follower in it does not look at a follower at all.
// An object checked before paint marks what it needs in the frame about
// to paint, while it is in the tree.
import 'dart:math';
import 'dart:typed_data';

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

  /// The glyph in the top left cell.
  String get first => String.fromCharCode(screen.surface.cells[0] & 0xFFFFFF);

  /// A pen with an opaque background, as a repaint boundary needs.
  int get opaque => screen.styles.pen(const Pen(bg: Color.rgb(0, 0, 0)));
}

/// Repainted whole with its boundaries, as big as it may be; counts its
/// paints and the times its place in its parent was read.
final class Follower extends RenderObject {
  Follower() {
    repaintedWhole = true;
  }

  var paints = 0;
  var reads = 0;

  @override
  ParentData get parentData {
    reads++;
    return super.parentData;
  }

  @override
  set parentData(ParentData d) => super.parentData = d;

  @override
  bool get sizedByParent => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  /// The rows it has repainted with its boundaries, all of them while
  /// null; none when the first is not before the other.
  (int, int)? rows;

  @override
  void wholeRows(Int32List out) {
    final r = rows;
    if (r != null) {
      out
        ..[0] = r.$1
        ..[1] = r.$2;
    }
  }

  @override
  void paint(PaintContext ctx) => paints++;
}

/// A line of text in an opaque pen; a repaint boundary when [boundary].
final class Line extends RenderObject {
  Line(this._text, {this.boundary = false});

  String _text;

  /// Shows [t] from the next frame on.
  void show(String t) {
    _text = t;
    markNeedsPaint();
  }

  final bool boundary;

  @override
  bool get isRepaintBoundary => boundary;

  @override
  bool get sizedByParent => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) {
    final pen = ctx.canvas.styles.pen(const Pen(bg: Color.rgb(0, 0, 0)));
    ctx.canvas
      ..fill(0, 0, width, height, pen)
      ..text(0, 0, _text, pen);
  }
}

/// A [Line] checked before each paint ([RenderObject.beforePaint]), which
/// then shows [next] when it is set.
final class Checked extends Line {
  Checked(super._text) {
    checkedBeforePaint = true;
  }

  var checks = 0;
  String? next;

  @override
  void beforePaint() {
    checks++;
    final n = next;
    if (n != null) {
      next = null;
      show(n);
    }
  }
}

/// A repaint boundary of [pen] holding [children] one over the other.
RenderBox layer(int pen, List<RenderObject> children) => RenderBox(
  pen: pen,
  boundary: true,
  child: RenderStack(children: children),
);

void main() {
  test('a flush that repaints no boundary with a follower in it looks at '
      'none', () {
    final followers = [for (var i = 0; i < 50; i++) Follower()];
    final spinner = Line('⠋', boundary: true);
    final root = RenderBox(pen: 0, boundary: true);
    final v = View(8, 4, root);
    final pen = v.opaque;
    root
      ..pen = pen
      ..child = RenderColumn([(layer(pen, followers), 3), (spinner, 1)]);
    v.frame();
    final reads = [for (final f in followers) f.reads];
    final paints = [for (final f in followers) f.paints];
    for (final s in ['⠙', '⠹', '⠸']) {
      spinner.show(s);
      v.frame();
    }
    expect([for (final f in followers) f.reads], reads);
    expect([for (final f in followers) f.paints], paints);
  });

  test('a follower moved into another boundary is repainted with that one, '
      'and dropped, with none', () {
    final follower = Follower();
    final a = Line('a');
    final b = Line('b');
    final root = RenderBox(pen: 0, boundary: true);
    final v = View(8, 4, root);
    final pen = v.opaque;
    final first = layer(pen, [a, follower]);
    final second = layer(pen, [b]);
    root
      ..pen = pen
      ..child = RenderColumn([(first, 2), (second, 2)]);
    v.frame();
    var paints = follower.paints;
    a.show('a2');
    v.frame();
    expect(follower.paints, ++paints, reason: 'with its boundary');
    (first.child! as RenderStack).remove(follower);
    (second.child! as RenderStack).add(follower);
    v.frame();
    paints = follower.paints;
    a.show('a3');
    v.frame();
    expect(follower.paints, paints, reason: 'not in that boundary any more');
    b.show('b2');
    v.frame();
    expect(follower.paints, ++paints, reason: 'with the one it is in now');
    (second.child! as RenderStack).remove(follower);
    v.frame();
    final reads = follower.reads;
    b.show('b3');
    v.frame();
    expect(follower.paints, paints, reason: 'out of the tree');
    expect(follower.reads, reads);
    // put back, in a subtree that was out of the tree
    final again = layer(pen, [follower]);
    (second.child! as RenderStack).add(again);
    v.frame();
    paints = follower.paints;
    b.show('b4');
    v.frame();
    expect(follower.paints, ++paints, reason: 'back in a boundary');
  });

  test('a follower has its boundaries repaint the rows it says it needs', () {
    final follower = Follower();
    final line = Line('a');
    final root = RenderBox(pen: 0, boundary: true);
    final v = View(4, 6, root);
    final pen = v.opaque;
    root
      ..pen = pen
      ..child = RenderStack(
        children: [
          RenderColumn([(RenderBox(pen: pen), 5), (line, 1)]),
          follower,
        ],
      );
    v.frame();
    line.show('b');
    expect(v.frame(), [4, 4, 4, 4, 4, 4], reason: 'all of its rows');
    follower.rows = (1, 3);
    line.show('c');
    // one band of rows: from its first to the marked one
    expect(v.frame(), [0, 4, 4, 4, 4, 4]);
    follower.rows = (0, 0);
    line.show('d');
    expect(v.frame(), [0, 0, 0, 0, 0, 4], reason: 'none');
    follower.rows = (5, 9);
    line.show('e');
    expect(v.frame(), [0, 0, 0, 0, 0, 4], reason: 'cut off at its bounds');
  });

  test('an object checked before paint marks for paint in the frame about '
      'to paint, while it is in the tree and checked', () {
    final checked = Checked('a');
    final line = Line('x', boundary: true);
    final root = RenderBox(pen: 0, boundary: true);
    final v = View(4, 2, root);
    final pen = v.opaque;
    final holder = layer(pen, [checked]);
    root
      ..pen = pen
      ..child = RenderColumn([(holder, 1), (line, 1)]);
    v.frame();
    expect(v.first, 'a');
    final checks = checked.checks;
    v.frame();
    expect(checked.checks, checks, reason: 'a frame with nothing to paint');
    // another boundary repaints; the checked one marks itself as it goes
    checked.next = 'b';
    line.show('y');
    expect(v.frame(), [4, 4], reason: 'its row in the same frame');
    expect(v.first, 'b');
    expect(checked.checks, checks + 1);
    (holder.child! as RenderStack).remove(checked);
    line.show('z');
    v.frame();
    expect(checked.checks, checks + 1, reason: 'out of the tree');
    (holder.child! as RenderStack).add(checked);
    v.frame();
    expect(checked.checks, checks + 2, reason: 'back');
    checked.checkedBeforePaint = false;
    line.show('w');
    v.frame();
    expect(checked.checks, checks + 2, reason: 'not checked any more');
  });
}
