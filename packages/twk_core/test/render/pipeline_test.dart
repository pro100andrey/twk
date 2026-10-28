// A repaint boundary marked from inside repaints the rows of what was
// marked, as it is laid out when the frame paints, all of them across:
// nothing outside them is painted, and the presenter has only them to
// compare. What a boundary inside those rows has to repaint, they repaint
// with it. An object repainted whole with its boundary is painted with any
// rows of it; one the rows cut through forgets what it kept of its paint.
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// A tree on a screen of [width] × [height] cells.
final class View {
  View(this.width, this.height, RenderObject root)
    : screen = Screen(width, height) {
    if (root is RenderBox) {
      root.pen = screen.styles.pen(const Pen(bg: Color.rgb(20, 20, 20)));
    }
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
}

/// A cell of text [label], [rows] tall, counting its paints and the times
/// it was told to forget what it painted.
final class Cell extends RenderObject {
  Cell(this._label, {this.rows = 1, this.boundary = false});

  String _label;
  String get label => _label;
  set label(String l) {
    _label = l;
    markNeedsPaint();
  }

  final int rows;
  final bool boundary;
  var paints = 0;
  var forgets = 0;

  @override
  bool get isRepaintBoundary => boundary;

  @override
  void invalidatePaintCache() => forgets++;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW < BoxConstraints.unbounded ? c.maxW : c.constrainW(8);
    height = c.constrainH(rows);
  }

  @override
  void paint(PaintContext ctx) {
    paints++;
    final pen = ctx.canvas.styles.pen(
      const Pen(fg: Color.rgb(200, 200, 200), bg: Color.rgb(10, 10, 10)),
    );
    ctx.canvas
      ..fill(0, 0, width, height, pen)
      ..text(0, 0, _label, pen);
  }
}

/// A grid of [rows] rows of [columns] cells in a column.
(RenderObject, List<List<Cell>>) grid(int rows, int columns) {
  final cells = [
    for (var y = 0; y < rows; y++)
      [for (var x = 0; x < columns; x++) Cell('$x,$y')],
  ];
  final column = RenderColumn([
    for (final row in cells) (RenderRow([for (final c in row) (c, 4)]), 1),
  ]);
  return (column, cells);
}

int paintsOf(List<List<Cell>> cells) {
  var n = 0;
  for (final row in cells) {
    for (final c in row) {
      n += c.paints;
    }
  }
  return n;
}

void main() {
  test('an object marked repaints the rows it covers, not its boundary', () {
    final (column, cells) = grid(10, 5);
    final v = View(20, 10, RenderBox(pen: 0, boundary: true, child: column))
      ..frame();
    expect(paintsOf(cells), 50);
    cells[4][2].label = 'x';
    final painted = v.frame();
    // the row, all across: the other cells of it are painted again too
    expect(paintsOf(cells), 55);
    expect([for (final c in cells[4]) c.paints], [2, 2, 2, 2, 2]);
    expect(painted, [0, 0, 0, 0, 20, 0, 0, 0, 0, 0]);
  });

  test('so does one under a root that is no boundary', () {
    final (column, cells) = grid(10, 5);
    final v = View(20, 10, column)..frame();
    cells[7][0].label = 'x';
    cells[8][4].label = 'y';
    final painted = v.frame();
    expect(paintsOf(cells), 60);
    expect(painted, [0, 0, 0, 0, 0, 0, 0, 20, 20, 0]);
  });

  test('marked all over, or laid out, a boundary repaints all of it', () {
    final (column, cells) = grid(6, 2);
    final root = RenderBox(pen: 0, boundary: true, child: column);
    final v = View(8, 6, root)..frame();
    cells[1][1].label = 'x';
    root.markNeedsPaint();
    v.frame();
    expect(paintsOf(cells), 24);
    v.owner.markAllDirty();
    v.frame();
    expect(paintsOf(cells), 36);
  });

  test('a boundary inside the rows has what it was to repaint painted with '
      'them, once', () {
    final inner = Cell('in', rows: 3, boundary: true);
    final marked = Cell('m');
    final column = RenderColumn([
      (marked, 1),
      (inner, 3),
      (Cell('below'), 1),
    ]);
    final v = View(8, 5, RenderBox(pen: 0, boundary: true, child: column))
      ..frame();
    marked.label = 'x';
    inner.label = 'y';
    final painted = v.frame();
    expect(inner.paints, 2);
    expect(marked.paints, 2);
    expect(painted, [8, 8, 8, 8, 0]);
  });

  test('an object repainted whole with its boundary is painted with any rows '
      'of it', () {
    final (column, cells) = grid(4, 2);
    final whole = Cell('w');
    final root = RenderBox(
      pen: 0,
      boundary: true,
      child: RenderColumn([(whole, 1), (column, 4)]),
    );
    final v = View(8, 5, root)..frame();
    whole.repaintedWhole = true;
    cells[0][0].label = 'x';
    // one band of rows: from its row to the marked one
    expect(v.frame(), [8, 8, 0, 0, 0]);
    expect(whole.paints, 2);
    whole.repaintedWhole = false;
    cells[1][0].label = 'x';
    expect(v.frame(), [0, 0, 8, 0, 0]);
    expect(whole.paints, 2);
  });

  test('an object the rows cut through forgets what it kept of its paint; '
      'one they hold whole, or miss, keeps it', () {
    final tall = Cell('t', rows: 4);
    final held = Cell('h');
    final missed = Cell('m');
    final marked = Cell('x');
    final root = RenderBox(
      pen: 0,
      boundary: true,
      child: RenderRow([
        (tall, 2),
        (RenderColumn([(missed, 1), (marked, 1), (held, 1), (Cell(''), 1)]), 2),
      ]),
    );
    final v = View(4, 4, root)..frame();
    final before = [tall.forgets, held.forgets, missed.forgets];
    marked.label = 'y';
    v.frame();
    // told by its parent as it paints it, then cut through
    expect(tall.forgets - before[0], 2);
    // out of the rows: their column, which paints only the children the
    // rows show, does not visit them
    expect(missed.forgets - before[2], 0);
    expect(held.forgets - before[1], 0);
    expect(tall.paints, 2);
  });

  test('under a debug paint a boundary repaints all of it', () {
    final (column, cells) = grid(4, 2);
    final v = View(8, 4, RenderBox(pen: 0, boundary: true, child: column));
    v.owner.debugRepaintRainbow = true;
    v.frame();
    cells[0][0].label = 'x';
    expect(v.frame(), [8, 8, 8, 8]);
    expect(paintsOf(cells), 16);
  });

  test('a boundary repainted whole with itself repaints all of its rows '
      'with any of them', () {
    final (column, cells) = grid(4, 2);
    final root = RenderBox(pen: 0, boundary: true, child: column)
      ..repaintedWhole = true;
    final v = View(8, 4, root)..frame();
    cells[2][0].label = 'x';
    expect(v.frame(), [8, 8, 8, 8]);
    expect(paintsOf(cells), 16);
  });

  test('an object repainted whole whose rows throw shows the error, all '
      'of it repainted', () {
    final (column, cells) = grid(3, 2);
    final whole = _WholeRows();
    final root = RenderBox(
      pen: 0,
      boundary: true,
      child: RenderColumn([(whole, 1), (column, 3)]),
    );
    final reports = <String>[];
    final v = View(8, 4, root);
    v.owner.onError = (o, phase, e, _) => reports.add('${phase.name} $e');
    v.frame();
    whole.repaintedWhole = true;
    cells[1][0].label = 'x';
    v.frame();
    expect(reports, ['paint Bad state: no rows']);
    expect(whole.debugError, 'Bad state: no rows');
  });

  test('more boundaries than a frame has repainted before all repaint', () {
    final cells = [for (var i = 0; i < 40; i++) Cell('$i', boundary: true)];
    final v = View(4, 40, RenderColumn([for (final c in cells) (c, 1)]))
      ..frame();
    for (final c in cells) {
      c.label = 'x';
    }
    expect(v.frame(), List.filled(40, 4));
    expect(cells.map((c) => c.paints), everyElement(2));
  });

  test('an object marked below what becomes a repaint boundary before the '
      'frame has that boundary repaint all of it', () {
    final inside = Cell('t');
    final below = Cell('u');
    final toggle = _Toggle(RenderColumn([(inside, 1), (below, 1)]));
    final v = View(
      8,
      3,
      RenderBox(
        pen: 0,
        boundary: true,
        child: RenderColumn([(toggle, 2), (Cell('b'), 1)]),
      ),
    )..frame();
    inside.label = 'x';
    toggle.boundary = true;
    // all of it, not only the row of what was marked
    expect(v.frame(), [8, 8, 0]);
    expect((inside.paints, below.paints), (2, 2));
  });

  test('an object marked for paint while the frame paints is painted on the '
      'next frame', () {
    final target = Cell('t');
    final boundary = RenderBox(pen: 0, boundary: true, child: target);
    final poker = _Poker(target);
    final v = View(
      8,
      3,
      RenderColumn([(poker, 1), (boundary, 2)]),
    );
    boundary.pen = v.screen.styles.pen(const Pen(bg: Color.rgb(1, 1, 1)));
    v.frame();
    poker
      ..poke = true
      ..markNeedsPaint();
    target.label = 'x';
    v.frame();
    expect(target.paints, 2);
    expect(v.owner.hasWork, isTrue);
    expect(boundary.debugNeedsPaint, isTrue);
    expect(v.frame(), [0, 8, 8]);
    expect(target.paints, 3);
  });

  test('relayout boundaries marked in one frame are laid out outermost '
      'first, one an outer one laid out not again', () {
    final order = <String>[];
    final inner = _Frame('inner', order, Cell('c'));
    final outer = _Frame('outer', order, inner);
    final v = View(8, 3, RenderBox(pen: 0, boundary: true, child: outer))
      ..frame();
    order.clear();
    inner.markNeedsLayout();
    outer.markNeedsLayout();
    v.frame();
    expect(order, ['outer', 'inner']);
  });

  test('a beforePaint that throws has its object show the error, reported '
      'as a paint', () {
    final cell = _Checked();
    final reports = <String>[];
    final v = View(8, 1, cell);
    v.owner.onError = (o, phase, e, _) => reports.add('${phase.name} $e');
    v.frame();
    expect(reports, ['paint Bad state: not ready']);
    expect(cell.debugError, 'Bad state: not ready');
  });
}

/// Lays its child out within its own constraints, as a relayout boundary,
/// noting its [name] in [order] each time it is laid out.
final class _Frame extends RenderObject with RenderObjectWithChildMixin {
  _Frame(this.name, this.order, RenderObject child) {
    this.child = child;
  }

  final String name;
  final List<String> order;

  @override
  void performLayout(BoxConstraints c) {
    order.add(name);
    width = c.maxW;
    height = c.maxH;
    child!.layout(BoxConstraints(0, width, 0, height));
  }

  @override
  void paint(PaintContext ctx) => paintChild(ctx, child!);
}

/// Paints its child as it is, a repaint boundary while [boundary] is set.
final class _Toggle extends RenderObject with RenderObjectWithChildMixin {
  _Toggle(RenderObject child) {
    this.child = child;
  }

  var boundary = false;

  @override
  bool get isRepaintBoundary => boundary;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
    child!.layout(BoxConstraints.tight(width, height));
  }

  @override
  void paint(PaintContext ctx) => paintChild(ctx, child!);
}

/// A [Cell] that marks [target] for paint as it paints, once [poke] is
/// set.
final class _Poker extends Cell {
  _Poker(this.target) : super('p');

  final RenderObject target;
  var poke = false;

  @override
  void paint(PaintContext ctx) {
    super.paint(ctx);
    if (poke) {
      poke = false;
      target.markNeedsPaint();
    }
  }
}

/// A [Cell] repainted whole with its boundaries, whose rows throw.
final class _WholeRows extends Cell {
  _WholeRows() : super('w');

  @override
  void wholeRows(Int32List rows) => throw StateError('no rows');
}

/// A [Cell] checked before each paint, which throws.
final class _Checked extends Cell {
  _Checked() : super('c') {
    checkedBeforePaint = true;
  }

  @override
  void beforePaint() => throw StateError('not ready');
}
