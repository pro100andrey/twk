// A list builds the items in its window and a few rows past it as it lays
// them out, each as tall as it likes, and drops those that leave; it
// estimates the heights of those it never built from the ones it measured.
// It scrolls from the item at its top: by a window or less exactly, further
// by the estimate, to the ends exactly; it follows the end while it sticks
// to the bottom. A scroll of a list wholly on the screen shifts its rows
// and declares the scroll, which the terminal does in hardware, and only
// the rows exposed and those of items laid out again are painted.
import 'dart:convert';

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

  int width;
  int height;
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

/// An item some rows tall, as wide as it may be: `<label>` on its first
/// row, `<label>.<k>` on row k.
final class Block extends RenderObject {
  Block(this._label, this._rows);

  String _label;

  /// Paints [l] from the next frame on.
  void repaintAs(String l) {
    _label = l;
    markNeedsPaint();
  }

  /// Shows [l] from the next layout on.
  void relabel(String l) {
    _label = l;
    markNeedsLayout();
  }

  int _rows;

  /// Is [n] rows tall from the next layout on.
  void grow(int n) {
    _rows = n;
    markNeedsLayout();
  }

  /// How many times it was painted.
  var paints = 0;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.constrainH(_rows);
  }

  @override
  void paint(PaintContext ctx) {
    paints++;
    final pen = ctx.canvas.styles.pen(const Pen());
    for (var k = 0; k < height; k++) {
      ctx.canvas.text(0, k, k == 0 ? _label : '$_label.$k', pen);
    }
  }
}

/// Builds item i as a [Block] `item <i>` of [rows] (i) rows, keeping
/// what it built and dropped.
final class Items implements ListItemManager {
  Items([int Function(int index)? rows]) : rows = rows ?? ((_) => 1);

  final int Function(int index) rows;
  late final RenderList list;
  final built = <int>[];
  final dropped = <int>[];
  final blocks = <int, Block>{};

  @override
  void buildItem(int index) {
    built.add(index);
    final block = blocks[index] = Block('item $index', rows(index));
    list.insertItem(block, index);
  }

  @override
  void dropItem(RenderObject item) {
    final index = (item.parentData as ListParentData).index;
    dropped.add(index);
    blocks.remove(index);
    list.remove(item);
  }
}

/// A list of [count] items that [items] builds; [metrics] gets what each
/// layout settles at.
RenderList list(
  Items items,
  int count, {
  List<(int, int, int)>? metrics,
  int? itemExtent,
  bool stickToBottom = false,
  int scrollOffset = 0,
}) => items.list = RenderList(
  items: items,
  itemCount: count,
  itemExtent: itemExtent,
  stickToBottom: stickToBottom,
  scrollOffset: scrollOffset,
  onMetrics: (v, c, o) => metrics?.add((v, c, o)),
);

/// `item <from>` to `item <to - 1>`.
List<String> items(int from, int to) => [
  for (var i = from; i < to; i++) 'item $i',
];

List<int> range(int from, int to) => [for (var i = from; i < to; i++) i];

const decstbm = '\x1b[1;5r';

void main() {
  group('layout', () {
    test('builds the items in its window and the cache rows below it, each '
        'as wide as the list, and drops those that leave', () {
      final built = Items();
      final metrics = <(int, int, int)>[];
      final l = list(built, 100000, metrics: metrics);
      final v = View(20, 5, l)..frame();
      expect(built.built, range(0, 8));
      expect(v.shown, items(0, 5));
      expect(metrics, [(5, 100000, 0)]);
      expect((l.width, l.height), (20, 5));
      expect(
        built.blocks[0]!.constraints,
        const BoxConstraints(20, 20, 0, 1 << 30),
      );

      // near the start, a window above it is built
      l.scrollOffset = 2;
      v.frame();
      expect(built.built, range(0, 10));
      expect(built.dropped, isEmpty);
      expect(v.shown, items(2, 7));

      // further, the cache above it, and nothing between
      built.built.clear();
      l.scrollOffset = 50;
      v.frame();
      expect(built.built, unorderedEquals(range(47, 58)));
      expect(built.dropped, range(0, 10));
      expect(v.shown, items(50, 55));
      expect(l.childCount, 11);
      expect(metrics.last, (5, 100000, 50));
    });

    test('measures each item it lays out and takes the others to be as tall '
        'as those on average', () {
      final metrics = <(int, int, int)>[];
      final l = list(Items((i) => i % 3 + 1), 100, metrics: metrics);
      final v = View(20, 5, l)..frame();
      expect(v.shown, ['item 0', 'item 1', 'item 1.1', 'item 2', 'item 2.1']);
      // 1 + 2 + 3 + 1 + 2 rows measured, 9 / 5 rows for each of the 95 left
      expect(metrics, [(5, 9 + 171, 0)]);

      l.scrollOffset = 3;
      v.frame();
      expect(v.shown, ['item 2', 'item 2.1', 'item 2.2', 'item 3', 'item 4']);
      expect(metrics.last.$3, 3);
    });

    test('with an item extent, lays every item out that tall and measures '
        'none', () {
      final built = Items((_) => 5);
      final metrics = <(int, int, int)>[];
      final l = list(built, 1000, metrics: metrics, itemExtent: 2);
      final v = View(20, 5, l)..frame();
      expect(built.blocks[0]!.constraints, const BoxConstraints.tight(20, 2));
      expect(metrics, [(5, 2000, 0)]);
      expect(v.shown, ['item 0', 'item 0.1', 'item 1', 'item 1.1', 'item 2']);
      l.scrollOffset = 1001;
      v.frame();
      expect(v.shown, [
        'item 500.1',
        'item 501',
        'item 501.1',
        'item 502',
        'item 502.1',
      ]);
      expect(metrics.last, (5, 2000, 1001));
    });

    test('a move of a window or less is exact, the items it passes laid '
        'out', () {
      final metrics = <(int, int, int)>[];
      final l = list(Items((i) => i.isEven ? 1 : 3), 1000, metrics: metrics);
      final v = View(20, 5, l)..frame();
      expect(v.shown, ['item 0', 'item 1', 'item 1.1', 'item 1.2', 'item 2']);
      l.scrollOffset = 5;
      v.frame();
      expect(v.shown, ['item 3', 'item 3.1', 'item 3.2', 'item 4', 'item 5']);
      l.scrollOffset = 4;
      v.frame();
      expect(v.shown, ['item 2', 'item 3', 'item 3.1', 'item 3.2', 'item 4']);

      // up into items not measured, 1 row and 3 rows
      l
        ..cacheExtent = 0
        ..jumpToIndex(501);
      v.frame();
      expect(v.shown.first, 'item 501');
      l.scrollOffset -= 2;
      v.frame();
      expect(v.shown, [
        'item 499.2',
        'item 500',
        'item 501',
        'item 501.1',
        'item 501.2',
      ]);
    });

    test('a longer move goes where the estimate puts it', () {
      final metrics = <(int, int, int)>[];
      final l = list(Items((i) => i < 4 ? 2 : 1), 1000, metrics: metrics);
      final v = View(20, 5, l)..frame();
      // items 0 to 3 measured, 2 rows each: row 1000 is item 500's
      expect(metrics.last, (5, 2000, 0));
      l.scrollOffset = 1000;
      v.frame();
      expect(v.shown, items(500, 505));
    });

    test('a move to 0 or past the end of the content shows the start or the '
        'end exactly, whatever the estimate', () {
      final metrics = <(int, int, int)>[];
      final l = list(Items((i) => i < 10 ? 1 : 2), 1000, metrics: metrics);
      final v = View(20, 5, l)..frame();
      expect(metrics.last, (5, 1000, 0));
      l.scrollOffset = 995;
      v.frame();
      expect(v.shown, [
        'item 997.1',
        'item 998',
        'item 998.1',
        'item 999',
        'item 999.1',
      ]);
      final (_, content, offset) = metrics.last;
      expect(offset, content - 5);
      l.scrollOffset = 3;
      v.frame();
      l.scrollOffset = 0;
      v.frame();
      expect(v.shown, items(0, 5));
      expect(metrics.last.$3, 0);
    });

    test('a window from either end, it builds the items up to a window '
        'past the edge, so that a move of a window stops at the end and '
        'skips nothing', () {
      final metrics = <(int, int, int)>[];
      // 1 row each but the last two, of 10 rows
      final l = list(
        Items((i) => i < 10 ? 1 : 10),
        12,
        metrics: metrics,
      )..cacheExtent = 0;
      final v = View(20, 5, l)..frame();
      int pageDown() {
        // as the position does: within the end the last layout told
        final (_, content, offset) = metrics.last;
        final to = offset + 5;
        return to > content - 5 ? content - 5 : to;
      }

      l.scrollOffset = pageDown();
      v.frame();
      expect(v.shown, items(5, 10));
      l.scrollOffset = pageDown();
      v.frame();
      expect(v.shown, [
        'item 10',
        'item 10.1',
        'item 10.2',
        'item 10.3',
        'item 10.4',
      ]);

      // up from item 20, the first two items 10 rows each
      final up = list(
        Items((i) => i < 2 ? 10 : 1),
        100,
        metrics: metrics,
        scrollOffset: 20,
      )..cacheExtent = 0;
      final u = View(20, 5, up)..frame();
      expect(u.shown.first, 'item 20');
      final firsts = <String>[];
      while (metrics.last.$3 > 0) {
        final to = metrics.last.$3 - 5;
        up.scrollOffset = to < 0 ? 0 : to;
        u.frame();
        firsts.add(u.shown.first);
      }
      expect(firsts, [
        'item 15',
        'item 10',
        'item 5',
        'item 1.8',
        'item 1.3',
        'item 0.8',
        'item 0.3',
        'item 0',
      ]);
    });

    test('takes an offset onMetrics sets in its layout', () {
      late RenderList l;
      l = list(Items(), 100)
        ..onMetrics = (v, c, o) {
          if (o == 0) {
            l.scrollOffset = 50;
          }
        };
      final v = View(20, 5, l)..frame();
      expect(v.shown, items(50, 55));
    });

    test('keeps the item at its top as the items above it are measured and '
        'the estimate changes, telling the offset it settled at', () {
      final metrics = <(int, int, int)>[];
      final l = list(Items((i) => i >= 500 ? 3 : 1), 1000, metrics: metrics);
      final v = View(20, 5, l)..frame();
      // all of 1 row as far as it knows: item 600 at row 600
      l.scrollOffset = 600;
      v.frame();
      expect(v.shown, [
        'item 600',
        'item 600.1',
        'item 600.2',
        'item 601',
        'item 601.1',
      ]);
      final (_, content, offset) = metrics.last;
      expect(content, greaterThan(1000));
      expect(offset, isNot(600));
      l.scrollOffset = offset + 1;
      v.frame();
      expect(v.shown.first, 'item 600.1');
    });

    test('jumpToIndex shows an item at the top; showIndex scrolls the least '
        'that shows it', () {
      final l = list(Items(), 1000);
      final v = View(20, 5, l)..frame();
      l.jumpToIndex(500);
      v.frame();
      expect(v.shown, items(500, 505));
      l.showIndex(503);
      v.frame();
      expect(v.shown, items(500, 505));
      l.showIndex(510);
      v.frame();
      expect(v.shown, items(506, 511));
      l.showIndex(505);
      v.frame();
      expect(v.shown, items(505, 510));
      l.showIndex(2000);
      v.frame();
      expect(v.shown, items(995, 1000));

      final tall = list(Items((i) => i == 7 ? 8 : 1), 100);
      final t = View(20, 5, tall)..frame();
      tall.showIndex(7);
      t.frame();
      expect(t.shown.first, 'item 7');
    });

    test('of an offset set and a move to an item asked for since the last '
        'layout, the later wins: an offset set, the one it is at too', () {
      final l = list(Items(), 100);
      final v = View(20, 5, l)..frame();
      l
        ..scrollOffset = 10
        ..jumpToIndex(50);
      v.frame();
      expect(v.shown, items(50, 55));
      l
        ..jumpToIndex(20)
        ..scrollOffset = 60;
      v.frame();
      expect(v.shown, items(60, 65));
      l
        ..showIndex(90)
        ..scrollOffset = 60;
      v.frame();
      expect(v.shown, items(60, 65));
    });

    test('keeps showing the end as items are added while it sticks to the '
        'bottom and shows it, which it starts at', () {
      final built = Items();
      final l = list(built, 20, stickToBottom: true);
      final v = View(20, 5, l)..frame();
      expect(v.shown, items(15, 20));
      expect(built.built, unorderedEquals(range(12, 20)));
      l.itemCount = 21;
      final bytes = v.frame();
      expect(v.shown, items(16, 21));
      expect(bytes, contains('$decstbm\x1b[S'));
      expect(v.scrolls, [(0, 5, 1, 0, 20)]);

      // moved off the end, it stays
      l.scrollOffset = l.scrollOffset - 1;
      v.frame();
      l.itemCount = 22;
      v.frame();
      expect(v.shown, items(15, 20));
      // at the end again, it follows
      l.scrollOffset = 1 << 20;
      v.frame();
      l.itemCount = 23;
      v.frame();
      expect(v.shown, items(18, 23));

      // an item at the end that grows
      built.blocks[22]!.grow(2);
      v.frame();
      expect(v.shown, [
        'item 19',
        'item 20',
        'item 21',
        'item 22',
        'item 22.1',
      ]);
    });

    test('items removed take the window up to the end; none leave it '
        'empty', () {
      final metrics = <(int, int, int)>[];
      final built = Items();
      final l = list(built, 50, metrics: metrics, scrollOffset: 30);
      final v = View(20, 5, l)..frame();
      expect(v.shown, items(30, 35));
      l.itemCount = 32;
      v.frame();
      expect(v.shown, items(27, 32));
      expect(built.blocks.keys, everyElement(lessThan(32)));
      l.itemCount = 0;
      v.frame();
      expect(v.shown, ['', '', '', '', '']);
      expect(l.childCount, 0);
      expect(metrics.last, (5, 0, 0));
    });

    test('forgets what it measured when its width changes', () {
      final metrics = <(int, int, int)>[];
      var width = 20;
      final built = Items((_) => width < 15 ? 2 : 1);
      final l = list(built, 100, metrics: metrics);
      final v = View(20, 5, l)..frame();
      l.scrollOffset = 50;
      v.frame();
      l.scrollOffset = 0;
      v.frame();
      expect(metrics.last, (5, 100, 0));
      width = 10;
      v
        ..width = 10
        ..screen.resize(10, 5)
        ..owner.markAllDirty();
      for (final b in built.blocks.values) {
        b.grow(2);
      }
      v.frame();
      expect(metrics.last, (5, 200, 0));
    });

    test('needs bounded constraints', () {
      final l = list(Items(), 10);
      (View(
        20,
        5,
        RenderViewport(child: l),
      )..owner.onError = (_, _, _, _) {}).frame();
      expect(l.debugError, contains('bounded'));
    });
  });

  group('paint', () {
    test('scrolled by a row while all of it is on the screen, it shifts its '
        'rows and the terminal scrolls in hardware, getting only the row '
        'the scroll exposed', () {
      final l = list(Items(), 1000);
      final v = View(20, 5, l)..frame();
      l.scrollOffset = 1;
      var bytes = v.frame();
      expect(v.scrolls, [(0, 5, 1, 0, 20)]);
      expect(bytes, contains('$decstbm\x1b[S'));
      expect(bytes, contains('item 5'));
      expect(bytes, isNot(contains('item 4')));
      expect(v.shown, items(1, 6));

      l.scrollOffset = 0;
      bytes = v.frame();
      expect(bytes, contains('$decstbm\x1b[T'));
      expect(bytes, contains('item 0'));
      expect(bytes, isNot(contains('item 1')));
      expect(v.shown, items(0, 5));

      l.scrollOffset = 3;
      bytes = v.frame();
      expect(bytes, contains('$decstbm\x1b[3S'));
      expect(v.shown, items(3, 8));
    });

    test('paints the items laid out again or moved otherwise, and keeps the '
        'others where the scroll took them', () {
      final built = Items();
      final l = list(built, 1000);
      final v = View(20, 6, l)..frame();
      final paints = built.blocks[4]!.paints;
      built.blocks[2]!.grow(2);
      l.scrollOffset = 1;
      v.frame();
      expect(v.scrolls, [(0, 6, 1, 0, 20)]);
      expect(v.shown, [
        'item 1',
        'item 2',
        'item 2.1',
        'item 3',
        'item 4',
        'item 5',
      ]);
      // moved down a row by item 2, against the scroll: painted
      expect(built.blocks[4]!.paints, paints + 1);

      final kept = built.blocks[1]!.paints;
      built.blocks[2]!.grow(1);
      v.frame();
      expect(v.shown, items(1, 7));
      expect(built.blocks[1]!.paints, kept);

      // laid out again where the scroll takes it
      built.blocks[4]!.relabel('four');
      l.scrollOffset = 2;
      v.frame();
      expect(v.scrolls, [(0, 6, 1, 0, 20)]);
      expect(v.shown, [
        'item 2',
        'item 3',
        'four',
        'item 5',
        'item 6',
        'item 7',
      ]);
    });

    test('anything inside it marked for paint other than by a layout has it '
        'paint all of it', () {
      final built = Items();
      final l = list(built, 1000);
      final v = View(20, 5, l)..frame();
      built.blocks[3]!.repaintAs('three');
      l.scrollOffset = 1;
      v.frame();
      expect(v.scrolls, isEmpty);
      expect(v.shown, ['item 1', 'item 2', 'three', 'item 4', 'item 5']);
    });

    test('a repaint boundary inside an item marked for paint as it scrolls '
        'repaints on its own, where the scroll kept it too', () {
      final v = View(20, 5, RenderBox(pen: 0));
      final pen = v.screen.styles.pen(const Pen(bg: Color.rgb(0, 0, 40)));
      final notes = <int, RenderText>{};
      late final RenderList l;
      final manager = _Boundaries(() => l, notes, pen);
      l = RenderList(items: manager, itemCount: 100);
      v
        ..owner.root = l
        ..frame();
      expect(v.shown, ['note 0', 'note 1', 'note 2', 'note 3', 'note 4']);
      const red = Color.rgb(40, 0, 0);
      notes[2]!.pen = v.screen.styles.pen(const Pen(bg: red));
      l.scrollOffset = 1;
      v.frame();
      expect(v.scrolls, [(0, 5, 1, 0, 20)]);
      expect(v.shown, ['note 1', 'note 2', 'note 3', 'note 4', 'note 5']);
      expect(v.vt.cell(10, 1).bg, red.value);
    });

    test('cut off by an ancestor, it paints what shows instead of '
        'scrolling', () {
      final l = list(Items(), 100);
      final v = View(
        20,
        5,
        RenderViewport(
          child: RenderColumn([(l, 6), (RenderText('below', 0), 1)]),
        ),
      )..frame();
      l.scrollOffset = 2;
      v.frame();
      expect(v.scrolls, isEmpty);
      expect(v.shown, items(2, 7));
    });

    test('fills the rows below its items with its background', () {
      final l = list(Items(), 3)
        ..background = const Pen(bg: Color.rgb(0, 0, 40));
      final v = View(20, 5, l)..frame();
      expect(v.shown, [...items(0, 3), '', '']);
      expect(v.vt.cell(15, 4).bg, const Color.rgb(0, 0, 40).value);
      l.itemCount = 2;
      v.frame();
      expect(v.shown, [...items(0, 2), '', '', '']);
    });
  });

  test('a hit test finds the item at the cell, only in the window', () {
    final built = Items();
    final l = list(built, 100, scrollOffset: 4);
    final v = View(20, 6, RenderColumn([(l, 3), (RenderText('x', 0), 1)]))
      ..frame();
    final result = HitTestResult();
    v.owner.hitTest(result, 2, 1);
    expect(identical(result[0], built.blocks[5]), isTrue);
    expect(identical(result[1], l), isTrue);
    // moved at once, before the next frame
    l.scrollOffset = 5;
    v.owner.hitTest(result, 2, 1);
    expect(identical(result[0], built.blocks[6]), isTrue);
  });

  test('a hit test below its items finds the list: it fills all of its '
      'cells', () {
    final l = list(Items(), 2);
    final v = View(20, 5, l)..frame();
    final result = HitTestResult();
    v.owner.hitTest(result, 2, 4);
    expect(result.length, 1);
    expect(identical(result[0], l), isTrue);
  });

  test('describes its items, offset, extent and cache where they are not '
      'the defaults, and whether it sticks to the bottom', () {
    final l = list(Items(), 100);
    View(20, 5, l).frame();
    expect(
      '${l.describe()}',
      'RenderList ‹itemCount: 100, constraints: tight›',
    );
    l
      ..scrollOffset = 2
      ..itemExtent = 2
      ..cacheExtent = 0
      ..stickToBottom = true;
    expect(
      '${l.describe()}',
      startsWith(
        'RenderList ‹itemCount: 100, scrollOffset: 2, itemExtent: 2, '
        'cacheExtent: 0, stickToBottom',
      ),
    );
    expect('${l.firstChild!.describe()}', contains('index: 0'));
  });

  group('items', () {
    test('an item moved to another index takes that place on the next '
        'layout', () {
      final built = Items();
      final l = list(built, 5);
      final v = View(20, 5, l)..frame();
      l
        ..moveItem(built.blocks[1]!, 3)
        ..moveItem(built.blocks[3]!, 1);
      v.frame();
      expect(v.shown, ['item 0', 'item 3', 'item 2', 'item 1', 'item 4']);
      expect(l.childCount, 5);
    });

    test('an item its manager leaves in the list when dropping it is taken '
        'out by the list', () {
      final kept = _Keeper();
      final l = kept.list = RenderList(items: kept, itemCount: 100);
      final v = View(20, 5, l)..frame();
      final first = l.firstChild!;
      l.scrollOffset = 50;
      v.frame();
      expect(kept.dropped, contains(0));
      expect(first.parent, isNull);
      expect(l.childCount, 11);
    });

    test('when the items it showed are gone, it shows the last ones', () {
      final l = list(Items(), 100, scrollOffset: 50);
      final v = View(20, 5, l)..frame();
      expect(v.shown, items(50, 55));
      l.itemCount = 10;
      v.frame();
      expect(l.itemCount, 10);
      expect(v.shown, items(5, 10));
    });

    test('an item at the top that shrinks past the rows scrolled off it is '
        'shown from its last row on', () {
      final built = Items((_) => 3);
      final l = list(built, 100, scrollOffset: 2);
      final v = View(20, 5, l)..frame();
      expect(v.shown.first, 'item 0.2');
      built.blocks[0]!.grow(1);
      v.frame();
      expect(v.shown, ['item 0', 'item 1', 'item 1.1', 'item 1.2', 'item 2']);
    });

    test('sticking to the bottom with fewer rows of items than the window, '
        'it shows them from the top', () {
      final metrics = <(int, int, int)>[];
      final l = list(Items(), 2, stickToBottom: true, metrics: metrics);
      final v = View(20, 5, l)..frame();
      expect(v.shown, [...items(0, 2), '', '', '']);
      expect(metrics, [(5, 2, 0)]);
    });

    test('moved by its metrics callback on every layout, it is laid out again '
        'on the next frame', () {
      late final RenderList l;
      var moves = 0;
      final built = Items();
      l = built.list = RenderList(
        items: built,
        itemCount: 100,
        onMetrics: (_, _, offset) {
          if (moves < 3) {
            moves++;
            l.scrollOffset = offset + 1;
          }
        },
      );
      final v = View(20, 5, l)..frame();
      // moved twice in the frame, the third move waits for the next
      expect(v.shown, items(2, 7));
      expect(l.debugNeedsLayout, isTrue);
      expect(v.owner.hasWork, isTrue);
      v.frame();
      expect(v.shown, items(3, 8));
    });

    test('its properties read back as set, the defaults until then', () {
      final l = list(Items(), 7);
      expect(
        (l.itemCount, l.itemExtent, l.cacheExtent, l.stickToBottom),
        (7, null, 3, false),
      );
      expect(
        l.background,
        const Pen(fg: Color.defaultColor, bg: Color.defaultColor),
      );
      l
        ..itemExtent = 2
        ..cacheExtent = 1
        ..stickToBottom = true
        ..background = const Pen(bg: Color.rgb(1, 2, 3));
      expect(
        (l.itemExtent, l.cacheExtent, l.stickToBottom, l.background),
        (2, 1, true, const Pen(bg: Color.rgb(1, 2, 3))),
      );
    });
  });
}

/// Builds item i as a [Block] like [Items], and leaves an item it is told
/// to drop in the list.
final class _Keeper implements ListItemManager {
  late final RenderList list;
  final dropped = <int>[];

  @override
  void buildItem(int index) => list.insertItem(Block('item $index', 1), index);

  @override
  void dropItem(RenderObject item) =>
      dropped.add((item.parentData as ListParentData).index);
}

/// Builds item i as a text `note <i>` that is its own repaint boundary.
final class _Boundaries implements ListItemManager {
  _Boundaries(this.list, this.notes, this.pen);

  final RenderList Function() list;
  final Map<int, RenderText> notes;
  final int pen;

  @override
  void buildItem(int index) => list().insertItem(
    notes[index] = RenderText('note $index', pen, boundary: true),
    index,
  );

  @override
  void dropItem(RenderObject item) => list().remove(item);
}
