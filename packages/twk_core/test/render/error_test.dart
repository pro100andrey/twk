// A layout or a paint that throws is contained in the object that threw:
// it shows the message in white on red in its place, the owner reports it
// once, and the rest of the frame is painted as if nothing happened; an
// error box's text in the color it is given.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// A render tree filling a whole screen, its errors reported into
/// [reports] as `phase object: error` unless `report` is false.
final class View {
  View(this.width, this.height, {bool report = true})
    : screen = Screen(width, height) {
    pen = screen.styles.pen(const Pen(bg: Color.rgb(0, 0, 0)));
    owner = PipelineOwner(() {});
    if (report) {
      owner.onError = (object, phase, error, stack) =>
          reports.add('${phase.name} $object: $error');
    }
  }

  final int width;
  final int height;
  final Screen screen;
  late final int pen;
  late final PipelineOwner owner;
  final reports = <String>[];

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

  /// Whether the cells of row [y] from [x0] to [x1] are white on red.
  bool redFrom(int x0, int x1, int y) {
    final styles = screen.styles;
    for (var x = x0; x < x1; x++) {
      final style = screen.surface.styles[y * width + x];
      if (styles.bgOf(style) != Color.red ||
          styles.fgOf(style) != Color.brightWhite) {
        return false;
      }
    }
    return true;
  }
}

/// What the objects here throw: an exception that says [message].
final class Failure implements Exception {
  const Failure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Throws a [Failure] that says [message].
Matcher throwsFailure(String message) =>
    throwsA(isA<Failure>().having((f) => f.message, 'message', message));

/// Fills the room it gets with [char], unless [layoutError] or [paintError]
/// is set: it throws a [Failure] that says that instead, a paint after
/// leaving the canvas saved, moved and clipped.
final class Faulty extends RenderObject {
  Faulty(this.char, this.pen);

  final String char;
  final int pen;
  String? layoutError;
  String? paintError;
  var layouts = 0;
  var paints = 0;

  @override
  void performLayout(BoxConstraints c) {
    layouts++;
    final error = layoutError;
    if (error != null) {
      throw Failure(error);
    }
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) {
    paints++;
    final error = paintError;
    if (error != null) {
      ctx.canvas
        ..save()
        ..translate(2, 1)
        ..clipRect(0, 0, 1, 1);
      throw Failure(error);
    }
    ctx.canvas.fill(0, 0, width, height, pen, char.codeUnitAt(0));
  }

  @override
  String toString() => 'Faulty $char';
}

/// Paints its child over all of itself; its [paintsOver] throws [error]
/// when set, and with [overError] set it paints over the child, which
/// throws that.
final class Cover extends RenderObject with RenderObjectWithChildMixin {
  Cover(RenderObject child) {
    this.child = child;
  }

  String? error;
  String? overError;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
    child!.layout(BoxConstraints.tight(width, height));
  }

  @override
  void paint(PaintContext ctx) => paintChild(ctx, child!);

  @override
  bool paintsOver(RenderObject child, int x, int y, int w, int h) {
    final e = error;
    if (e != null) {
      throw Failure(e);
    }
    return overError != null;
  }

  @override
  void paintOver(
    PaintContext ctx,
    RenderObject child,
    int x,
    int y,
    int w,
    int h,
  ) => throw Failure(overError!);

  @override
  String toString() => 'Cover';
}

void main() {
  test('a layout that throws shows the message in white on red, as big as '
      'it is within the constraints, and is reported once', () {
    final v = View(6, 3);
    final bad = Faulty('b', v.pen)..layoutError = 'no room here';
    v.owner.root = RenderPositionedBox(
      alignment: Alignment.topLeft,
      child: bad,
    );
    v.frame();
    expect(v.rows(), ['no', 'room', 'here']);
    expect((bad.width, bad.height), (6, 3));
    expect(v.redFrom(0, 6, 0) && v.redFrom(0, 6, 2), isTrue);
    expect(v.reports, ['layout Faulty b: no room here']);

    bad.markNeedsLayout();
    v.frame();
    expect(bad.layouts, 2);
    expect(v.reports, hasLength(1), reason: 'the same error again');

    bad
      ..layoutError = 'nope'
      ..markNeedsLayout();
    v.frame();
    expect(v.rows(), ['nope', '', '']);
    expect((bad.width, bad.height), (4, 1));
    expect(v.reports.last, 'layout Faulty b: nope');

    bad
      ..layoutError = null
      ..markNeedsLayout();
    v.frame();
    expect(v.rows(), ['bbbbbb', 'bbbbbb', 'bbbbbb']);
    expect(v.reports, hasLength(2));
  });

  test('a paint that throws shows its error over its bounds, and what it '
      'left on the canvas does not move the rest', () {
    final v = View(6, 3);
    final bad = Faulty('b', v.pen)..paintError = 'oops';
    final below = Faulty('c', v.pen);
    v.owner.root = RenderColumn([
      (Faulty('a', v.pen), 1),
      (bad, 1),
      (below, 1),
    ]);
    v.frame();
    expect(v.rows(), ['aaaaaa', 'oops', 'cccccc']);
    expect(v.redFrom(0, 6, 1), isTrue);
    expect(v.redFrom(0, 1, 0) || v.redFrom(0, 1, 2), isFalse);
    expect(v.reports, ['paint Faulty b: oops']);

    // repainted with its parent, it shows the error without painting
    below.markNeedsPaint();
    v.frame();
    expect(bad.paints, 1);
    expect(v.rows(), ['aaaaaa', 'oops', 'cccccc']);

    // marked itself, it paints again; the same error is not reported again
    bad.markNeedsPaint();
    v.frame();
    expect(bad.paints, 2);
    expect(v.rows(), ['aaaaaa', 'oops', 'cccccc']);
    expect(v.reports, hasLength(1));

    bad
      ..paintError = null
      ..markNeedsPaint();
    v.frame();
    expect(v.rows(), ['aaaaaa', 'bbbbbb', 'cccccc']);
    expect(v.redFrom(0, 1, 1), isFalse);

    bad
      ..paintError = 'oops'
      ..markNeedsPaint();
    v.frame();
    expect(v.reports, hasLength(2), reason: 'it painted without an error');
  });

  test('a repaint boundary inside an object that shows an error does not '
      'paint over it', () {
    final v = View(6, 1);
    final inside = RenderText('in', v.pen, boundary: true);
    final cover = Cover(inside);
    final bad = Faulty('b', v.pen);
    v.owner.root = RenderRow([(cover, 3), (bad, 3)]);
    v.frame();
    expect(v.rows(), ['in bbb']);

    // its parent throws while it repaints on its own
    cover.error = 'x';
    inside.text = 'IN';
    v.frame();
    expect(v.rows(), ['x  bbb']);
    expect(v.redFrom(0, 3, 0), isTrue);
    expect(v.reports, ['paint Cover: x']);

    inside.text = 'on';
    v.frame();
    expect(v.rows(), ['x  bbb']);
  });

  test('a parent whose paint over a repaint boundary inside it throws as '
      'the boundary repaints on its own shows the error', () {
    final v = View(6, 1);
    final inside = RenderText('in', v.pen, boundary: true);
    final cover = Cover(inside);
    v.owner.root = RenderRow([(cover, 3), (Faulty('b', v.pen), 3)]);
    v.frame();
    cover.overError = 'over';
    inside.text = 'IN';
    v.frame();
    expect(v.rows(), ['ovebbb']);
    expect(v.reports, ['paint Cover: over']);
    expect(cover.debugError, 'over');
  });

  test('without onError, the first error is thrown once the flush has '
      'ended, the tree left to show them all', () {
    final v = View(6, 2, report: false);
    final one = Faulty('1', v.pen)..layoutError = 'one';
    final two = Faulty('2', v.pen)..layoutError = 'two';
    v.owner.root = RenderColumn([(one, 1), (two, 1)]);
    expect(() => v.owner.flushLayout(6, 2), throwsFailure('one'));
    v.frame();
    expect(v.rows(), ['one', 'two']);

    two
      ..layoutError = null
      ..markNeedsLayout();
    v.frame();
    expect(v.rows(), ['one', '222222']);

    one
      ..layoutError = null
      ..paintError = 'three'
      ..markNeedsLayout();
    expect(v.frame, throwsFailure('three'));
    v.frame();
    expect(v.rows(), ['three', '222222']);
  });

  test('outside a flush, without onError, a layout that throws throws', () {
    final v = View(6, 2, report: false);
    final bad = Faulty('b', v.pen)..layoutError = 'detached';
    expect(
      () => bad.layout(const BoxConstraints.tight(3, 1)),
      throwsFailure('detached'),
    );
    v.owner.root = bad;
    expect(
      () => bad.layout(const BoxConstraints.tight(3, 1)),
      throwsFailure('detached'),
    );
  });

  test('an object that shows an error says so when described', () {
    final v = View(6, 1);
    final bad = Faulty('b', v.pen)..paintError = 'oops';
    v.owner.root = bad;
    expect(bad.describe().flags, isNot(contains(DiagnosticsFlag.error)));
    v.frame();
    final node = bad.describe();
    expect(node.flags, contains(DiagnosticsFlag.error));
    expect('${node.properties.last}', 'error: "oops"');
  });

  test("an error box's text is bright white, or the color it is given, on "
      'red; a color set later repaints it', () {
    final v = View(6, 1);
    final box = RenderErrorBox('boom');
    v.owner.root = box;
    v.frame();
    expect(v.rows(), ['boom']);
    expect(v.redFrom(0, 6, 0), isTrue);
    const white = Color.rgb(255, 255, 255);
    box.color = white;
    v.frame();
    final styles = v.screen.styles;
    for (var x = 0; x < 6; x++) {
      final style = v.screen.surface.styles[x];
      expect((styles.fgOf(style), styles.bgOf(style)), (white, Color.red));
    }
    expect(RenderErrorBox('x', color: white).color, white);
  });

  test("an error box's message is broken between words, within a word "
      'where it must; a new message lays it out again', () {
    final v = View(10, 2);
    final box = RenderErrorBox('boom');
    v.owner.root = box;
    v.frame();
    expect(v.rows(), ['boom', '']);
    box.message = 'a much longer one';
    v.frame();
    expect(box.message, 'a much longer one');
    expect(v.rows(), ['a much', 'longer one']);
    box.message = 'unbreakable!';
    v.frame();
    expect(v.rows(), ['unbreakabl', 'e!']);
  });

  test('an error box asks to be as wide as its widest line, one column at '
      'least, and as tall as its lines at a width', () {
    final box = RenderErrorBox('disk full\nretry');
    expect(
      [
        box.getMinIntrinsicWidth(1),
        box.getMaxIntrinsicWidth(1),
        box.getMinIntrinsicHeight(5),
        box.getMaxIntrinsicHeight(9),
      ],
      [1, 9, 3, 2],
    );
    expect(RenderErrorBox('').getMinIntrinsicWidth(1), 0);
  });

  test('an error box describes its message', () {
    expect('${RenderErrorBox('boom').describe()}', 'RenderErrorBox ‹"boom"›');
  });
}
