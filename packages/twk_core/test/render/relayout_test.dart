// A layout change lays out the smallest subtree whose size can't change
// what is around it, and the screen ends up as a full layout would leave it.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// A render tree filling a whole screen.
final class View {
  View(this.width, this.height) : screen = Screen(width, height) {
    pen = screen.styles.pen(const Pen(bg: Color.rgb(0, 0, 0)));
    owner = PipelineOwner(() {});
  }

  final int width;
  final int height;
  final Screen screen;
  late final int pen;
  late final PipelineOwner owner;

  void frame() {
    owner
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    screen.render();
  }

  List<String> rows() => [
    for (var y = 0; y < height; y++)
      [
        for (var x = 0; x < width; x++)
          screen.glyphs.stringOf(screen.surface.cells[y * width + x]),
      ].join().trimRight(),
  ];
}

/// One line of text as wide as the text, or as wide as it may be when
/// [sizedByParent]; a new [text] lays it out again. Counts its layouts. A
/// repaint boundary when [boundary] is set.
final class Label extends RenderObject {
  Label(
    this._text,
    this.pen, {
    this.boundary = false,
    this.sizedByParent = false,
  });

  String _text;
  final int pen;
  final bool boundary;
  @override
  final bool sizedByParent;
  var layouts = 0;

  String get text => _text;
  set text(String t) {
    _text = t;
    markNeedsLayout();
  }

  @override
  bool get isRepaintBoundary => boundary;

  @override
  void performLayout(BoxConstraints c) {
    layouts++;
    width = sizedByParent ? c.maxW : c.constrainW(_text.length);
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) {
    if (boundary) {
      ctx.canvas.fill(0, 0, width, height, pen);
    }
    ctx.canvas.text(0, 0, _text, pen);
  }
}

/// How a [Holder] lays its child out.
enum Hold {
  /// The child gets the holder's size.
  tight,

  /// Loosely, and the holder takes the child's size.
  hug,

  /// Loosely, and the holder takes all the room it gets.
  loose,
}

/// Holds one child as [hold] says. Counts its layouts.
final class Holder extends RenderObject {
  Holder(this.child, [this._hold = Hold.hug]) {
    adopt(child);
  }

  final RenderObject child;
  Hold _hold;
  var layouts = 0;

  Hold get hold => _hold;
  set hold(Hold h) {
    _hold = h;
    markNeedsLayout();
  }

  @override
  void visitChildren(void Function(RenderObject) visit) => visit(child);

  @override
  void performLayout(BoxConstraints c) {
    layouts++;
    width = c.maxW;
    height = c.maxH;
    switch (_hold) {
      case Hold.tight:
        child.layout(BoxConstraints.tight(width, height));
      case Hold.hug:
        child.layout(BoxConstraints(0, width, 0, height), parentUsesSize: true);
        width = c.constrainW(child.width);
        height = c.constrainH(child.height);
      case Hold.loose:
        child.layout(BoxConstraints(0, width, 0, height));
    }
  }

  @override
  void paint(PaintContext ctx) => paintChild(ctx, child);
}

/// What [Indent] keeps on its child.
final class IndentData extends ParentData {
  var columns = 0;
}

/// Lays its child out the [IndentData.columns] it keeps on the child in
/// from its left edge.
final class Indent extends RenderObject {
  Indent(this.child, int columns) {
    adopt(child);
    (child.parentData as IndentData).columns = columns;
  }

  final RenderObject child;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! IndentData) {
      child.parentData = IndentData();
    }
  }

  @override
  void visitChildren(void Function(RenderObject) visit) => visit(child);

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
    final at = child.parentData as IndentData;
    child.layout(BoxConstraints.tight(width - at.columns, height));
    at.dx = at.columns;
  }

  @override
  void paint(PaintContext ctx) => paintChild(ctx, child);
}

void main() {
  test('a layout change under tight constraints lays out that subtree', () {
    final v = View(10, 3);
    final header = Label('header', v.pen);
    final label = Label('hello', v.pen);
    // the column gives body a tight size: what body hugs can't move it
    final body = Holder(label);
    final root = Holder(RenderColumn([(header, 1), (body, null)]), Hold.tight);
    v.owner.root = root;
    v.frame();
    List<int> layouts() => [
      root.layouts,
      header.layouts,
      body.layouts,
      label.layouts,
    ];
    expect(layouts(), [1, 1, 1, 1]);
    label.text = 'hi there';
    v.frame();
    expect(layouts(), [1, 1, 2, 2]);
    expect(v.rows(), ['header', 'hi there', '']);
  });

  test('a child is a boundary while its parent ignores its size', () {
    final v = View(10, 1);
    final label = Label('abc', v.pen);
    final holder = Holder(label, Hold.tight);
    v.owner.root = holder;
    v.frame();
    label.text = 'abcd';
    v.frame();
    expect([holder.layouts, label.layouts], [1, 2]);
    // loose constraints, and the holder takes the label's size: laying the
    // label out lays the holder out too
    holder.hold = Hold.hug;
    v.frame();
    expect([holder.layouts, label.layouts], [2, 3]);
    label.text = 'abcdef';
    v.frame();
    expect([holder.layouts, label.layouts], [3, 4]);
    // the same constraints, so the label isn't laid out, but its size no
    // longer matters
    holder.hold = Hold.loose;
    v.frame();
    expect([holder.layouts, label.layouts], [4, 4]);
    label.text = 'ab';
    v.frame();
    expect([holder.layouts, label.layouts], [4, 5]);
    // and back
    holder.hold = Hold.hug;
    v.frame();
    label.text = 'abc';
    v.frame();
    expect([holder.layouts, label.layouts], [6, 6]);
    holder.hold = Hold.tight;
    v.frame();
    label.text = 'x';
    v.frame();
    expect([holder.layouts, label.layouts], [7, 8]);
    expect(v.rows(), ['x']);
  });

  test('a child sized by its parent is a boundary', () {
    final v = View(10, 1);
    final label = Label('abc', v.pen, sizedByParent: true);
    final holder = Holder(label);
    v.owner.root = holder;
    v.frame();
    label.text = 'abcd';
    v.frame();
    expect([holder.layouts, label.layouts], [1, 2]);
    expect(v.rows(), ['abcd']);
  });

  test('a new child of a box lays out nothing above the box', () {
    final v = View(10, 1);
    final box = RenderBox(pen: v.pen, child: RenderText('a', v.pen));
    // the holder takes the box's size, which is all the room it gets
    final holder = Holder(box);
    v.owner.root = holder;
    v.frame();
    box.child = RenderText('b', v.pen);
    v.frame();
    expect(holder.layouts, 1);
    expect(v.rows(), ['b']);
  });

  test('a boundary that shrank leaves nothing behind', () {
    final v = View(10, 1);
    // the box doesn't use the size of its child: the label is a boundary
    final label = Label('hello', v.pen, boundary: true);
    v.owner.root = RenderBox(pen: v.pen, boundary: true, child: label);
    v.frame();
    label.text = 'hi';
    v.frame();
    expect(v.rows(), ['hi']);
  });

  test('a boundary changed while detached is laid out when attached', () {
    final v = View(12, 1);
    final label = Label('old', v.pen);
    final panel = RenderBox(pen: v.pen, child: label);
    final root = RenderBox(pen: v.pen, boundary: true, child: panel);
    v.owner.root = root;
    v.frame();
    root.child = null;
    label.text = 'new text';
    root.child = panel;
    v.frame();
    expect(v.rows(), ['new text']);
    // and it still takes changes
    label.text = 'newer';
    v.frame();
    expect(v.rows(), ['newer']);
  });

  test('a parent keeps what it needs per child in parentData', () {
    final v = View(10, 2);
    final text = RenderText('x', v.pen);
    // the box keeps only the offset; the indent needs data of its own
    RenderBox(pen: v.pen, child: text).child = null;
    v.owner.root = Indent(text, 3);
    v.frame();
    expect(v.rows(), ['   x', '']);
  });
}
