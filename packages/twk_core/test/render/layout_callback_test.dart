// A render object that changes what is below it while it is laid out (a
// layout callback): what changed is laid out with it, a relayout boundary
// it marks below in the same flush, and a parent that laid it out by
// intrinsic sizes the change made different is laid out again on the next
// frame. Layouts that keep marking each other are cut off.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// One line of [text] (one column per character), as wide as the text
/// within the constraints.
final class Label extends RenderObject {
  Label(this.text);

  final String text;

  @override
  int computeMaxIntrinsicWidth(int height) => text.length;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(text.length);
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) {}
}

/// Its child is what [make] returns for its constraints, made in a layout
/// callback each time they change; as big as the child, and asks for what
/// the child asks for. Counts the children made.
final class Builds extends RenderObject with RenderObjectWithChildMixin {
  Builds(this.make);

  final RenderObject Function(BoxConstraints c) make;
  BoxConstraints? _built;
  var made = 0;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  void performLayout(BoxConstraints c) {
    if (c != _built) {
      _built = c;
      invokeLayoutCallback(() {
        made++;
        this.child = make(c);
      });
    }
    final child = this.child!..layout(c, parentUsesSize: true);
    width = child.width;
    height = child.height;
  }

  @override
  void paint(PaintContext ctx) => paintChild(ctx, child!);
}

/// Lays [child] out [inset] columns narrower than itself, or exactly as
/// wide as the child asks to be when [asks], and as tall as itself. Counts
/// its layouts.
final class Hug extends RenderObject {
  Hug(this.child, {this.asks = false}) {
    adopt(child);
  }

  final RenderObject child;
  final bool asks;
  var inset = 1;
  var layouts = 0;

  @override
  void visitChildren(void Function(RenderObject) visit) => visit(child);

  @override
  void performLayout(BoxConstraints c) {
    layouts++;
    width = c.maxW;
    height = c.maxH;
    final w = asks ? child.getMaxIntrinsicWidth(c.maxH) : c.maxW - inset;
    child.layout(BoxConstraints.tight(w, c.maxH), parentUsesSize: true);
  }

  @override
  void paint(PaintContext ctx) => paintChild(ctx, child);
}

/// Runs [change] in a layout callback at each of its layouts, then lays
/// its child out within its own constraints, which it takes all of.
final class Changes extends RenderObject with RenderObjectWithChildMixin {
  Changes(RenderObject child) {
    this.child = child;
  }

  void Function() change = () {};

  @override
  void performLayout(BoxConstraints c) {
    invokeLayoutCallback(change);
    width = c.maxW;
    height = c.maxH;
    child!.layout(c);
  }

  @override
  void paint(PaintContext ctx) => paintChild(ctx, child!);
}

/// Builds item i of [list] as `item <i>` in a [RenderPadding] of no
/// padding, keeping those it built.
final class Items implements ListItemManager {
  late final RenderList list;
  final built = <int, RenderPadding>{};

  @override
  void buildItem(int index) => list.insertItem(
    built[index] = RenderPadding(
      padding: EdgeInsets.zero,
      child: RenderText('item $index', pen),
    ),
    index,
  );

  @override
  void dropItem(RenderObject item) {
    built.remove((item.parentData as ListParentData).index);
    list.remove(item);
  }
}

/// A screen to lay out and paint a render tree on, as big as the frame.
final screen = Screen(10, 1);

/// A pen of the terminal's colours.
final int pen = screen.styles.pen(const Pen());

/// Lays out and paints what [owner] holds at [width] × 1, as a frame does.
void frame(PipelineOwner owner, int width) => owner
  ..flushLayout(width, 1)
  ..flushPaint(PaintContext(screen.canvas, screen.surface, screen.presenter));

/// What the last [frame] left on the screen.
String shown() {
  screen.render();
  return [
    for (var x = 0; x < screen.width; x++)
      screen.glyphs.stringOf(screen.surface.cells[x]),
  ].join().trimRight();
}

/// The text of [o]'s child, a [Label].
String textOf(RenderObject o) {
  RenderObject? child;
  o.visitChildren((c) => child = c);
  return (child! as Label).text;
}

void main() {
  test('what a layout callback changes is laid out with the object, and '
      'asks for no layout on the next frame', () {
    final owner = PipelineOwner(() {});
    final builds = Builds((c) => Label('${c.maxW}'));
    final hug = Hug(builds);
    owner.root = hug;
    frame(owner, 10);
    expect([textOf(builds), builds.width, builds.made], ['9', 9, 1]);
    // laid out again with new constraints, it replaces its child: the marks
    // that makes reach no further
    hug
      ..inset = 4
      ..markNeedsLayout();
    frame(owner, 10);
    expect([textOf(builds), builds.width, builds.made], ['6', 6, 2]);
    expect(owner.hasWork, isFalse);
    expect(hug.layouts, 2);
  });

  test('a parent that laid it out by intrinsic sizes the callback changed '
      'is laid out again on the next frame, once they hold', () {
    final owner = PipelineOwner(() {});
    final builds = Builds(
      (c) => Label(c.maxW < 4 ? 'narrow' : 'wide'),
    );
    final hug = Hug(builds, asks: true);
    owner.root = hug;
    frame(owner, 10);
    // it asked for nothing before its first child: laid out 0 wide
    expect([textOf(builds), builds.width], ['narrow', 0]);
    expect(owner.hasWork, isTrue);
    frame(owner, 10);
    expect([textOf(builds), builds.width, hug.layouts], ['wide', 6, 2]);
    // 'wide' asks for 4, which builds 'wide' again
    expect(owner.hasWork, isTrue);
    frame(owner, 10);
    expect([textOf(builds), builds.width, hug.layouts], ['wide', 4, 3]);
    expect(builds.made, 3);
    expect(owner.hasWork, isFalse);
  });

  test('a root whose intrinsic sizes the callback changed is laid out again '
      'on the next frame, for what sized it by them', () {
    final owner = PipelineOwner(() {});
    final builds = Builds((c) => Label('wide'));
    owner.root = builds;
    // as an inline region is sized
    expect(builds.getMaxIntrinsicWidth(1), 0);
    frame(owner, 10);
    expect(owner.hasWork, isTrue);
    expect(builds.getMaxIntrinsicWidth(1), 4);
    frame(owner, 10);
    expect([builds.made, owner.hasWork], [1, false]);
  });

  test('a relayout boundary the callback marks below what the object lays '
      'out is laid out and painted in the same frame', () {
    final owner = PipelineOwner(() {});
    // laid out tight: a boundary, under one laid out with the same
    // constraints as before, which has nothing to lay out
    final inner = RenderPadding(
      padding: EdgeInsets.zero,
      child: RenderText('x', pen),
    );
    final changes = Changes(
      RenderPadding(padding: EdgeInsets.zero, child: inner),
    );
    owner.root = changes;
    frame(owner, 10);
    expect(shown(), 'x');
    changes
      ..change = () {
        inner.padding = const EdgeInsets.only(left: 3);
      }
      ..markNeedsLayout();
    frame(owner, 10);
    expect(shown(), '   x');
    expect(owner.hasWork, isFalse);
  });

  test('an item of a list with an item extent that the callback changes is '
      'laid out and painted in the same frame', () {
    final owner = PipelineOwner(() {});
    final items = Items();
    // the list is sized by its parent and its items laid out tight: each a
    // boundary
    final changes = Changes(
      items.list = RenderList(items: items, itemCount: 3, itemExtent: 1),
    );
    owner.root = changes;
    frame(owner, 10);
    expect(shown(), 'item 0');
    changes
      ..change = () {
        items.built[0]!.padding = const EdgeInsets.only(left: 2);
      }
      ..markNeedsLayout();
    frame(owner, 10);
    expect(shown(), '  item 0');
    expect(owner.hasWork, isFalse);
  });

  test('layouts that keep marking each other stop after a number of passes: '
      'the object laid out last shows an error, reported once, and what it '
      'marked waits for the next frame', () {
    final owner = PipelineOwner(() {});
    final reports = <String>[];
    owner.onError = (object, phase, error, stack) =>
        reports.add('${phase.name} ${object.runtimeType}: $error');
    final b = Changes(RenderText('b', pen));
    // b is laid out tight under a padding that has nothing to lay out
    final a = Changes(RenderPadding(padding: EdgeInsets.zero, child: b));
    owner.root = a;
    frame(owner, 10);
    a
      ..change = b.markNeedsLayout
      ..markNeedsLayout();
    b.change = a.markNeedsLayout;
    frame(owner, 10);
    const unsettled =
        'layout does not settle: after 100 passes, laying out Changes still '
        'marks relayout boundaries';
    expect(reports, ['layout Changes: Bad state: $unsettled']);
    expect([a.debugError, b.debugError].nonNulls, hasLength(1));
    expect(owner.hasWork, isTrue);
    frame(owner, 10);
    expect(reports, hasLength(1));
    // once they stop, the error is gone
    b.change = () {};
    frame(owner, 10);
    expect([a.debugError, b.debugError, owner.hasWork], [null, null, false]);
  });

  test('a parent that asked for no intrinsic size is not laid out again', () {
    final owner = PipelineOwner(() {});
    final builds = Builds((c) => Label(c.maxW < 6 ? 'narrow' : 'wide'));
    final hug = Hug(builds);
    owner.root = hug;
    frame(owner, 10);
    hug
      ..inset = 5
      ..markNeedsLayout();
    frame(owner, 10);
    expect([textOf(builds), hug.layouts, owner.hasWork], ['narrow', 2, false]);
  });
}
