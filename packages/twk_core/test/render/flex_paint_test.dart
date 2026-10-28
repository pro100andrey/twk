// A Column or a Row paints only the children its clip shows: they follow
// each other along its main axis, so those are a run of them, found by
// bisection, and the others are not visited at all. A child cut off with
// something inside it that is painted however it is cut off is still
// painted. What the clip shows is the same as when every child is painted.
import 'dart:async';

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

  /// The glyphs and the styles of rows [from] to [to].
  List<List<int>> rows(int from, int to) {
    final s = screen.surface;
    return [
      s.cells.sublist(from * s.width, to * s.width),
      s.styles.sublist(from * s.width, to * s.width),
    ];
  }
}

/// A line reading [label] on each of its rows, [w] × [h] cells if its
/// constraints allow, counting its paints and its visits: each time its
/// parent painted it, or tried to, it was told to forget what it painted.
final class Line extends RenderObject {
  Line(this.label, {this.w = 8, this.h = 1});

  final String label;
  final int w;
  final int h;
  var paints = 0;
  var visits = 0;

  /// The clip bounds of its last paint.
  (int, int, int, int)? clip;

  @override
  void invalidatePaintCache() => visits++;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(w);
    height = c.constrainH(h);
  }

  @override
  void paint(PaintContext ctx) {
    paints++;
    clip = ctx.canvas.clipBounds;
    final pen = ctx.canvas.styles.pen(const Pen());
    for (var y = 0; y < height; y++) {
      ctx.canvas.text(0, y, label, pen);
    }
  }
}

/// A box as big as its child.
final class Box extends RenderObject with RenderObjectWithChildMixin {
  Box(RenderObject child) {
    this.child = child;
  }

  @override
  void performLayout(BoxConstraints c) {
    final ch = child!..layout(c, parentUsesSize: true);
    width = ch.width;
    height = ch.height;
  }

  @override
  void paint(PaintContext ctx) => paintChild(ctx, child!);
}

/// [n] lines `<i>`, one row high.
List<Line> lines(int n) => [for (var i = 0; i < n; i++) Line('$i')];

int visited(List<Line> l) => l.where((x) => x.visits > 0).length;

int painted(List<Line> l) => l.where((x) => x.paints > 0).length;

/// The indices of the lines visited [times] times.
List<int> visitedTimes(List<Line> l, int times) => [
  for (var i = 0; i < l.length; i++)
    if (l[i].visits == times) i,
];

void main() {
  group('a Column of 10 000 children clipped to 5 rows', () {
    test('visits and paints only the 5 the clip shows', () {
      final l = lines(10000);
      final vp = RenderViewport(
        child: RenderFlex(direction: Axis.vertical, children: l),
      );
      View(20, 5, vp).frame();
      expect(visited(l), 5);
      expect(painted(l), 5);
      expect(visitedTimes(l, 1), [0, 1, 2, 3, 4]);
    });

    test(
      'scrolled to the middle and on: what shows, then what was exposed',
      () {
        final l = lines(10000);
        final vp = RenderViewport(
          child: RenderFlex(direction: Axis.vertical, children: l),
        );
        final v = View(20, 5, vp)..frame();
        vp.scrollOffset = 5000;
        v.frame();
        expect(visitedTimes(l, 1), [
          0,
          1,
          2,
          3,
          4,
          5000,
          5001,
          5002,
          5003,
          5004,
        ]);
        // the viewport moved the rows it kept; the row it exposed is painted
        vp.scrollOffset = 5001;
        v.frame();
        expect(visited(l), 11);
        expect(l[5005].paints, 1);
      },
    );

    test('cut at both ends by its parent, mid-child', () {
      // children of 3 rows, the clip from the middle of one to the middle
      // of another
      final l = [for (var i = 0; i < 10000; i++) Line('$i', h: 3)];
      final vp = RenderViewport(
        scrollOffset: 3 * 4000 + 1,
        child: RenderFlex(direction: Axis.vertical, children: l),
      );
      View(20, 5, vp).frame();
      expect(visitedTimes(l, 1), [4000, 4001]);
      expect(painted(l), 2);
    });

    test('with gaps between the children', () {
      final l = lines(10000);
      final vp = RenderViewport(
        scrollOffset: 2 * 7000,
        child: RenderFlex(direction: Axis.vertical, gap: 1, children: l),
      );
      View(20, 5, vp).frame();
      expect(visitedTimes(l, 1), [7000, 7001, 7002]);
    });

    test('a child with something inside it painted when cut off', () {
      final l = lines(10000);
      final cursor = Line('cursor')..paintedWhenCutOff = true;
      final children = <RenderObject>[...l]..[9000] = Box(cursor);
      final vp = RenderViewport(
        child: RenderFlex(direction: Axis.vertical, children: children),
      );
      View(20, 5, vp).frame();
      // painted, in an empty clip; its siblings cut off are not visited
      expect(cursor.paints, 1);
      expect(cursor.clip, (0, 0, 0, 0));
      expect(visited(l), 5);
      expect(l[9000].visits, 0);
    });

    test('a child before those the clip shows with something inside it '
        'painted when cut off', () {
      final l = lines(10000);
      final cursor = Line('cursor')..paintedWhenCutOff = true;
      final children = <RenderObject>[...l]..[10] = Box(cursor);
      final vp = RenderViewport(
        scrollOffset: 5000,
        child: RenderFlex(direction: Axis.vertical, children: children),
      );
      View(20, 5, vp).frame();
      expect(cursor.paints, 1);
      expect(cursor.clip, (0, 0, 0, 0));
      expect(visitedTimes(l, 1), [5000, 5001, 5002, 5003, 5004]);
    });

    test('the column itself painted when cut off', () {
      final l = lines(10000);
      final col = RenderFlex(direction: Axis.vertical, children: l)
        ..paintedWhenCutOff = true;
      final vp = RenderViewport(child: col);
      View(20, 5, vp).frame();
      expect(visited(l), 5);
    });
  });

  test('a Row of 10 000 children clipped to 20 columns', () {
    final l = [for (var i = 0; i < 10000; i++) Line('$i', w: 4)];
    final vp = RenderViewport(
      axis: Axis.horizontal,
      scrollOffset: 4 * 6000 + 2,
      child: RenderFlex(children: l),
    );
    View(20, 3, vp).frame();
    expect(visitedTimes(l, 1), [6000, 6001, 6002, 6003, 6004, 6005]);
    expect(painted(l), 6);
  });

  test('a short Column clipped is visited whole, as before', () {
    final l = lines(2);
    final vp = RenderViewport(
      scrollOffset: 1,
      child: RenderFlex(direction: Axis.vertical, children: l),
    );
    View(20, 1, vp).frame();
    // both are handed to paintChild; the one the clip leaves out is not
    // painted, keeps what it kept of its paint and is not told to forget
    expect(visitedTimes(l, 1), [1]);
    expect(painted(l), 1);
  });

  test('children added after a paint are found by the next one', () {
    final l = lines(100);
    final col = RenderFlex(direction: Axis.vertical, children: l.sublist(50));
    final vp = RenderViewport(scrollOffset: 10, child: col);
    final v = View(20, 3, vp)..frame();
    expect(visitedTimes(l, 1), [60, 61, 62]);
    RenderObject? after;
    for (final x in l.sublist(0, 50)) {
      col.insert(x, after: after);
      after = x;
    }
    v.frame();
    expect(visitedTimes(l, 1), [10, 11, 12, 60, 61, 62]);
  });

  group('what the clip shows is what painting every child shows', () {
    // the flex in a viewport [rows] high scrolled by [offset], against the
    // same flex shown whole, cut to those rows
    void same(
      RenderFlex Function() build, {
      required int rows,
      required List<int> offsets,
      int? height,
    }) {
      RenderObject boxed(RenderFlex f) => height == null
          ? f
          : RenderConstrainedBox(
              additionalConstraints: BoxConstraints(
                0,
                BoxConstraints.unbounded,
                height,
                height,
              ),
              child: f,
            );
      final whole = View(30, 400, RenderViewport(child: boxed(build())))
        ..frame();
      for (final offset in offsets) {
        final cut = View(
          30,
          rows,
          RenderViewport(scrollOffset: offset, child: boxed(build())),
        )..frame();
        expect(
          cut.rows(0, rows),
          whole.rows(offset, offset + rows),
          reason: 'scrolled by $offset',
        );
      }
    }

    // children 1 to 3 rows long, some none
    List<RenderObject> mixed() => [
      for (var i = 0; i < 60; i++)
        Line('line $i', h: i % 7 == 3 ? 0 : 1 + i % 3),
    ];
    final offsets = [0, 1, 2, 5, 17, 40, 63, 90];

    test('one child after another', () {
      same(
        () => RenderFlex(direction: Axis.vertical, children: mixed()),
        rows: 4,
        offsets: offsets,
      );
    });

    test('with gaps', () {
      same(
        () => RenderFlex(direction: Axis.vertical, gap: 2, children: mixed()),
        rows: 5,
        offsets: offsets,
      );
    });

    for (final a in MainAxisAlignment.values) {
      test('placed ${a.name} in a taller column', () {
        same(
          () => RenderFlex(
            direction: Axis.vertical,
            mainAxisAlignment: a,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: mixed(),
          ),
          rows: 3,
          offsets: [...offsets, 150, 230, 297],
          height: 300,
        );
      });
    }

    test('children overflowing a shorter column', () {
      // without the warning of the overflow
      runZoned(
        () => same(
          () => RenderFlex(direction: Axis.vertical, children: mixed()),
          rows: 6,
          offsets: [0, 10, 25, 34],
          height: 40,
        ),
        zoneSpecification: ZoneSpecification(print: (_, _, _, _) {}),
      );
    });
  });
}
