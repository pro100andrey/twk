// A viewport is a window onto a child as long as it likes: the child laid
// out with no limit along the axis, painted from the scroll offset and cut
// off at the window's bounds, the offset kept within the child's extent. A
// scroll of a window wholly on the screen shifts its rows and declares the
// scroll, which the terminal does in hardware, and only the rows it exposed
// are painted; anything inside marked for paint has all of it painted.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/vt.dart';

/// A tree on a screen of [width] × [height] cells, each frame's bytes fed
/// to an emulator.
final class View {
  View(this.width, this.height, [RenderObject? root, TerminalCaps? caps])
    : screen = Screen(width, height, caps: caps ?? const TerminalCaps()),
      vt = Vt(width, height) {
    owner = PipelineOwner(() {});
    if (root != null) {
      owner.root = root;
    }
  }

  final int width;
  final int height;
  final Screen screen;
  final Vt vt;
  late final PipelineOwner owner;

  /// The scrolls the last frame declared, as (top, bottom, rows, left,
  /// right) each.
  var scrolls = <(int, int, int, int, int)>[];

  /// Lays out, paints and renders what changed; returns the bytes written.
  String frame() {
    owner
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    final s = screen.surface.pendingScrolls;
    scrolls = [
      for (var i = 0; i < s.length; i += 5)
        (s[i], s[i + 1], s[i + 2], s[i + 3], s[i + 4]),
    ];
    final bytes = screen.render();
    if (bytes == null) {
      return '';
    }
    vt.feed(bytes);
    return latin1.decode(bytes);
  }

  /// What the terminal shows.
  List<String> get shown => vt.lines;
}

/// [count] rows reading `<label> 0`, `<label> 1` and on, as wide as they
/// may be, [columns] where that is unbounded.
final class Lines extends RenderObject {
  Lines(this._count, {this.columns = 20});

  final int columns;

  int _count;
  int get count => _count;
  set count(int n) {
    _count = n;
    markNeedsLayout();
  }

  var _label = 'line';

  /// Paints `<l> 0` and on from the next frame.
  void relabel(String l) {
    _label = l;
    markNeedsPaint();
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW < BoxConstraints.unbounded ? c.maxW : c.constrainW(columns);
    height = c.constrainH(_count);
  }

  /// How many times it was painted.
  var paints = 0;

  @override
  void paint(PaintContext ctx) {
    paints++;
    final pen = ctx.canvas.styles.pen(const Pen());
    for (var i = 0; i < _count; i++) {
      ctx.canvas.text(0, i, '$_label $i', pen);
    }
  }
}

/// One row of [count] digits, `0123456789` over and over.
final class Ruler extends RenderObject {
  Ruler(this.count);

  final int count;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(count);
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) => ctx.canvas.text(
    0,
    0,
    [for (var i = 0; i < count; i++) i % 10].join(),
    ctx.canvas.styles.pen(const Pen()),
  );
}

/// `line <from>` to `line <to - 1>`.
List<String> lines(int from, int to, [String label = 'line']) => [
  for (var i = from; i < to; i++) '$label $i',
];

/// A pen with an opaque background, as a repaint boundary needs.
const solid = Pen(bg: Color.rgb(0, 0, 40));

const decstbm = '\x1b[1;5r';

void main() {
  group('layout', () {
    test('lays its child out as long as it likes along the axis and within '
        'its own constraints across, and is as big as it within its own', () {
      final extents = <(int, int)>[];
      final child = Lines(12);
      final viewport = RenderViewport(
        child: child,
        onExtents: (v, c) => extents.add((v, c)),
      );
      View(20, 5, viewport).frame();
      expect(child.constraints, const BoxConstraints(20, 20, 0, 1 << 30));
      expect((child.width, child.height), (20, 12));
      expect((viewport.width, viewport.height), (20, 5));
      expect(extents, [(5, 12)]);

      final short = RenderViewport(
        child: Lines(3),
        onExtents: (v, c) => extents.add((v, c)),
      );
      View(
        20,
        5,
        RenderPositionedBox(alignment: Alignment.topLeft, child: short),
      ).frame();
      expect((short.width, short.height), (20, 3));
      expect(extents.last, (3, 3));

      final empty = RenderViewport(onExtents: (v, c) => extents.add((v, c)));
      View(20, 5, empty).frame();
      expect((empty.width, empty.height), (20, 5));
      expect(extents.last, (5, 0));
    });

    test('along a horizontal axis, the child is as wide as it likes and '
        'within its constraints in height', () {
      final extents = <(int, int)>[];
      final ruler = Ruler(30);
      final viewport = RenderViewport(
        axis: Axis.horizontal,
        child: ruler,
        onExtents: (v, c) => extents.add((v, c)),
      );
      View(10, 2, viewport).frame();
      expect(ruler.constraints, const BoxConstraints(0, 1 << 30, 2, 2));
      expect((ruler.width, ruler.height), (30, 2));
      expect(extents, [(10, 30)]);
    });

    test('keeps its scroll offset from 0 to the child extent less its own, '
        'set before the first layout or after it', () {
      final child = Lines(12);
      final viewport = RenderViewport(child: child, scrollOffset: 100);
      final v = View(20, 5, viewport)..frame();
      expect(viewport.scrollOffset, 7);
      expect(v.shown, lines(7, 12));

      viewport.scrollOffset = 9;
      expect(viewport.scrollOffset, 7);
      viewport.scrollOffset = -3;
      expect(viewport.scrollOffset, 0);
      viewport.scrollOffset = 6;
      v.frame();
      expect(v.shown, lines(6, 11));

      child.count = 8;
      v.frame();
      expect(viewport.scrollOffset, 3);
      expect(v.shown, lines(3, 8));
      child.count = 3;
      v.frame();
      expect(viewport.scrollOffset, 0);
      expect(v.shown, [...lines(0, 3), '', '']);
    });

    test('takes the offset onExtents sets in its layout', () {
      late RenderViewport viewport;
      viewport = RenderViewport(
        child: Lines(12),
        onExtents: (v, c) => viewport.scrollOffset = c - v,
      );
      final v = View(20, 5, viewport)..frame();
      expect(v.shown, lines(7, 12));
    });

    test(
      'a column in it is as tall as its children, the flexible ones too',
      () {
        final flexible = Lines(2);
        final column = RenderColumn([
          (Lines(3), 3),
          (flexible, null),
          (Lines(4), null),
        ]);
        final v = View(20, 5, RenderViewport(child: column))..frame();
        expect((column.width, column.height), (20, 9));
        expect(flexible.height, 2);
        expect(v.shown, [...lines(0, 3), ...lines(0, 2)]);
      },
    );
  });

  group('paint', () {
    test('paints the child from its offset over its background, cut off at '
        'its bounds', () {
      final viewport = RenderViewport(
        child: Lines(12),
        scrollOffset: 4,
        background: solid,
      );
      final v = View(
        20,
        6,
        RenderColumn([(viewport, 4), (RenderText('below', 0), 1)]),
      )..frame();
      expect(v.shown, [...lines(4, 8), 'below', '']);
      expect(v.vt.cell(15, 2).bg, const Color.rgb(0, 0, 40).value);

      viewport.background = const Pen(bg: Color.rgb(40, 0, 0));
      v.frame();
      expect(v.vt.cell(15, 2).bg, const Color.rgb(40, 0, 0).value);
      expect(v.shown, [...lines(4, 8), 'below', '']);
    });

    test('scrolled by a row while all of it is on the screen, it shifts its '
        'rows and the terminal scrolls in hardware, getting only the row '
        'the scroll exposed', () {
      final viewport = RenderViewport(child: Lines(12));
      final v = View(20, 5, viewport)..frame();
      viewport.scrollOffset = 1;
      var bytes = v.frame();
      expect(v.scrolls, [(0, 5, 1, 0, 20)]);
      expect(bytes, contains('$decstbm\x1b[S'));
      expect(bytes, contains('line 5'));
      expect(bytes, isNot(contains('line 4')));
      expect(v.shown, lines(1, 6));

      viewport.scrollOffset = 0;
      bytes = v.frame();
      expect(bytes, contains('$decstbm\x1b[T'));
      expect(bytes, contains('line 0'));
      expect(bytes, isNot(contains('line 1')));
      expect(v.shown, lines(0, 5));

      viewport.scrollOffset = 3;
      bytes = v.frame();
      expect(bytes, contains('$decstbm\x1b[3S'));
      expect(v.shown, lines(3, 8));
    });

    test('scrolled back to where it was before a frame, it paints nothing', () {
      final child = Lines(12);
      final viewport = RenderViewport(child: child);
      final v = View(20, 5, viewport)..frame();
      viewport
        ..scrollOffset = 2
        ..scrollOffset = 0;
      final paints = child.paints;
      expect(v.frame(), '');
      expect(child.paints, paints);
      expect(v.shown, lines(0, 5));
    });

    test('narrower than the screen, it scrolls between left and right '
        'margins where the terminal has them, and is rewritten where not', () {
      for (final margins in [true, false]) {
        final viewport = RenderViewport(child: Lines(12, columns: 10));
        final v = View(
          20,
          5,
          RenderRow([(viewport, 10), (Lines(5), null)]),
          TerminalCaps(leftRightMargins: margins),
        )..frame();
        viewport.scrollOffset = 1;
        final bytes = v.frame();
        expect(v.scrolls, [(0, 5, 1, 0, 10)]);
        expect(bytes.contains('\x1b[1;10s\x1b[S'), margins, reason: '$margins');
        expect(v.shown, [
          for (var i = 0; i < 5; i++) 'line ${i + 1}    line $i',
        ]);
      }
    });

    test('cut off by an ancestor, it paints what shows instead of '
        'scrolling', () {
      final inner = RenderViewport(child: Lines(12));
      final v = View(
        20,
        5,
        RenderViewport(
          child: RenderColumn([(inner, 6), (Lines(3), 3)]),
        ),
      )..frame();
      inner.scrollOffset = 2;
      v.frame();
      expect(v.scrolls, isEmpty);
      expect(v.shown, lines(2, 7));
    });

    test('anything inside it marked for paint or laid out as it scrolls '
        'has it paint all of it', () {
      final child = Lines(12);
      final viewport = RenderViewport(child: child);
      final v = View(20, 5, viewport)..frame();
      child.relabel('row');
      viewport.scrollOffset = 1;
      v.frame();
      expect(v.scrolls, isEmpty);
      expect(v.shown, lines(1, 6, 'row'));

      child
        ..relabel('item')
        ..count = 11;
      viewport.scrollOffset = 2;
      v.frame();
      expect(v.shown, lines(2, 7, 'item'));
    });

    test('a repaint boundary inside it marked for paint as it scrolls '
        'repaints on its own, where the scroll kept it too', () {
      final v = View(20, 5);
      final pen = v.screen.styles.pen(solid);
      final note = RenderText('note', pen, boundary: true);
      final log = RenderLog(pen: pen, itemPen: (_, _) => pen);
      for (var i = 0; i < 4; i++) {
        log.add('log $i');
      }
      final viewport = RenderViewport(
        child: RenderColumn([
          (Lines(2), 2),
          (note, 1),
          (log, 2),
          (Lines(6), 6),
        ]),
      );
      v
        ..owner.root = viewport
        ..frame();
      expect(v.shown, ['line 0', 'line 1', 'note', ' log 2', ' log 3']);

      note.text = 'changed';
      log.add('log 4');
      viewport.scrollOffset = 1;
      v.frame();
      expect(v.scrolls, [(0, 5, 1, 0, 20)]);
      expect(v.shown, ['line 1', 'changed', ' log 3', ' log 4', 'line 0']);

      log.add('log 5');
      viewport.scrollOffset = 2;
      v.frame();
      expect(v.shown, ['changed', ' log 4', ' log 5', 'line 0', 'line 1']);
    });

    test(
      'along a horizontal axis it scrolls by columns, painting all of it',
      () {
        final viewport = RenderViewport(
          axis: Axis.horizontal,
          child: Ruler(30),
        );
        final v = View(10, 3, viewport)..frame();
        expect(v.shown, ['0123456789', '', '']);
        viewport.scrollOffset = 1;
        v.frame();
        expect(v.scrolls, isEmpty);
        expect(v.shown, ['1234567890', '', '']);
        viewport.scrollOffset = 3;
        v.frame();
        expect(v.shown, ['3456789012', '', '']);
        viewport.scrollOffset = 50;
        v.frame();
        expect(v.shown, ['0123456789', '', '']);
      },
    );

    test('painted over by a later child of a stack, it paints all of it', () {
      final viewport = RenderViewport(child: Lines(12));
      final over = RenderText('over', 0);
      final v = View(
        20,
        5,
        RenderStack(children: [viewport, over]),
      )..frame();
      viewport.scrollOffset = 1;
      v.frame();
      expect(v.scrolls, isEmpty);
      expect(v.shown, ['over 1', ...lines(2, 6)]);
    });
  });

  test('a hit test finds the child at the scroll offset, only in the '
      'window', () {
    final child = Lines(12);
    final viewport = RenderViewport(child: child, scrollOffset: 4);
    final v = View(20, 5, RenderColumn([(viewport, 3), (Lines(2), 2)]))
      ..frame();
    final result = HitTestResult();
    v.owner.hitTest(result, 2, 1);
    expect(identical(result[0], child), isTrue);
    expect((result.xAt(0), result.yAt(0)), (2, 5));
    expect(identical(result[1], viewport), isTrue);
    v.owner.hitTest(result, 2, 3);
    expect(result.length, 2);
    expect(result[0], isNot(child));
    expect(child.globalOffset, (0, -4));

    // moved at once, before the next frame
    viewport.scrollOffset = 6;
    expect(child.globalOffset, (0, -6));
    v.owner.hitTest(result, 2, 0);
    expect((result.xAt(0), result.yAt(0)), (2, 6));

    // hit where its child is not, as it paints all of its cells
    final short = RenderViewport(child: Lines(2));
    (View(20, 5, short)..frame()).owner.hitTest(result, 2, 3);
    expect(result.length, 1);
    expect(identical(result[0], short), isTrue);
  });

  test('describes its axis, scroll offset and background where they are '
      'not the defaults', () {
    final viewport = RenderViewport(child: Lines(12));
    View(20, 5, viewport).frame();
    expect('${viewport.describe()}', 'RenderViewport ‹constraints: tight›');
    viewport
      ..axis = Axis.horizontal
      ..scrollOffset = 2
      ..background = solid;
    expect(
      '${viewport.describe()}',
      startsWith(
        'RenderViewport ‹axis: horizontal, scrollOffset: 2, background: ',
      ),
    );
  });

  test('its axis and background read back as set, vertical and the '
      "terminal's own colors until then", () {
    final viewport = RenderViewport(child: Lines(12));
    expect(viewport.axis, Axis.vertical);
    expect(
      viewport.background,
      const Pen(fg: Color.defaultColor, bg: Color.defaultColor),
    );
    viewport
      ..axis = Axis.horizontal
      ..background = solid;
    expect((viewport.axis, viewport.background), (Axis.horizontal, solid));
  });

  test('asks for what its child asks for; without one, for nothing', () {
    final viewport = RenderViewport(
      child: RenderParagraph([('ab cd', const Pen())]),
    );
    expect(
      [
        viewport.getMinIntrinsicWidth(5),
        viewport.getMaxIntrinsicWidth(5),
        viewport.getMinIntrinsicHeight(2),
        viewport.getMaxIntrinsicHeight(5),
      ],
      [2, 5, 2, 1],
    );
    final empty = RenderViewport();
    expect(
      [
        empty.getMinIntrinsicWidth(5),
        empty.getMaxIntrinsicWidth(5),
        empty.getMinIntrinsicHeight(5),
        empty.getMaxIntrinsicHeight(5),
      ],
      [0, 0, 0, 0],
    );
  });

  test('a viewport given no rows for content is reported once, in debug; '
      'one with no content is not', () {
    final records = <LogRecord>[];
    final viewport = RenderViewport(child: Lines(3));
    final empty = RenderViewport(child: Lines(0));
    final v = View(
      10,
      1,
      RenderFlex(
        direction: Axis.vertical,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [Lines(1), viewport, empty],
      ),
    );
    // each would take the column's row; flexible, they get what is left
    for (final o in [viewport, empty]) {
      (o.parentData as FlexParentData).flex = 1;
    }
    v.owner.onLog = records.add;
    v.frame();
    viewport.markNeedsLayout();
    v.frame();
    var asserts = false;
    assert(asserts = true, 'debug only');
    const warning =
        'A RenderViewport was given 0 rows for 3 rows of content and shows '
        'none of it: in a Column the children beside it took every one (put '
        'it in an Expanded).';
    expect([for (final r in records) r.message], [if (asserts) warning]);
  });
}
