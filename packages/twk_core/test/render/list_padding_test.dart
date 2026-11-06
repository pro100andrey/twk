// A list's padding scrolls with its items: the rows above the first and
// below the last are part of the content, and the columns on either side
// inset every item.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

import 'list_test.dart' show Items, View, items, range;

/// A list of [count] items one row tall, or [itemExtent], inside [padding].
RenderList padded(
  Items built,
  int count,
  EdgeInsets padding, {
  List<(int, int, int)>? metrics,
  int? itemExtent,
  bool stickToBottom = false,
}) => built.list = RenderList(
  items: built,
  itemCount: count,
  itemExtent: itemExtent,
  stickToBottom: stickToBottom,
  padding: padding,
  onMetrics: (v, c, o) => metrics?.add((v, c, o)),
);

const pad = EdgeInsets.only(top: 2, bottom: 1);

void main() {
  group('rows', () {
    test('the leading rows are the start of the content and scroll away, '
        'the trailing ones come after the last item', () {
      final metrics = <(int, int, int)>[];
      final l = padded(Items(), 10, pad, metrics: metrics);
      final v = View(20, 5, l)..frame();
      // two rows, ten items, one row
      expect(metrics, [(5, 13, 0)]);
      expect(v.shown, ['', '', 'item 0', 'item 1', 'item 2']);

      l.scrollOffset = 1;
      v.frame();
      expect(v.shown, ['', 'item 0', 'item 1', 'item 2', 'item 3']);
      expect(metrics.last, (5, 13, 1));

      l.scrollOffset = 2;
      v.frame();
      expect(v.shown, items(0, 5));

      l.scrollOffset = 8;
      v.frame();
      expect(v.shown, ['item 6', 'item 7', 'item 8', 'item 9', '']);
      expect(metrics.last, (5, 13, 8));

      // the very top shows the leading rows empty again
      l.scrollOffset = 0;
      v.frame();
      expect(v.shown, ['', '', 'item 0', 'item 1', 'item 2']);
      expect(metrics.last.$3, 0);
    });

    test('the end is the content less the window, trailing rows shown', () {
      final metrics = <(int, int, int)>[];
      final l = padded(Items(), 10, pad, metrics: metrics);
      final v = View(20, 5, l)..frame();
      // past the end is the end
      l.scrollOffset = 100;
      v.frame();
      expect(metrics.last, (5, 13, 8));
      expect(v.shown, ['item 6', 'item 7', 'item 8', 'item 9', '']);
    });

    test('padding bigger than the window leaves it empty at either end', () {
      final l = padded(Items(), 3, const EdgeInsets.symmetric(vertical: 6));
      final v = View(20, 5, l)..frame();
      expect(v.shown, ['', '', '', '', '']);
      l.scrollOffset = 100;
      v.frame();
      expect(v.shown, ['', '', '', '', '']);
      l.scrollOffset = 6;
      v.frame();
      expect(v.shown, ['item 0', 'item 1', 'item 2', '', '']);
      l.scrollOffset = 9;
      v.frame();
      expect(v.shown, ['', '', '', '', '']);
    });

    test('items that do not fill the window are at its top, the padding '
        'around them', () {
      final metrics = <(int, int, int)>[];
      final l = padded(
        Items(),
        2,
        const EdgeInsets.symmetric(vertical: 1),
        metrics: metrics,
      );
      final v = View(20, 6, l)..frame();
      expect(metrics, [(6, 4, 0)]);
      expect(v.shown, ['', 'item 0', 'item 1', '', '', '']);
    });

    test('an empty list has no content, the padding with it', () {
      final metrics = <(int, int, int)>[];
      final l = padded(Items(), 0, pad, metrics: metrics);
      final v = View(20, 5, l)..frame();
      expect(metrics, [(5, 0, 0)]);
      expect(v.shown, ['', '', '', '', '']);
    });

    test('a list that sticks to the bottom shows the trailing rows', () {
      final metrics = <(int, int, int)>[];
      final l = padded(
        Items(),
        10,
        pad,
        metrics: metrics,
        stickToBottom: true,
      );
      final v = View(20, 5, l)..frame();
      expect(v.shown, ['item 6', 'item 7', 'item 8', 'item 9', '']);
      expect(metrics.last, (5, 13, 8));
      // an item added shows below the old last one, still at the end
      l.itemCount = 11;
      v.frame();
      expect(v.shown, ['item 7', 'item 8', 'item 9', 'item 10', '']);
      expect(metrics.last, (5, 14, 9));
    });

    test('items measured at their own heights add up with the padding', () {
      final metrics = <(int, int, int)>[];
      final l = padded(Items((i) => i % 2 + 1), 4, pad, metrics: metrics);
      final v = View(20, 5, l)..frame();
      // 1 + 2 + 1 + 2 rows of items
      expect(metrics, [(5, 9, 0)]);
      l.scrollOffset = 4;
      v.frame();
      expect(v.shown, ['item 1.1', 'item 2', 'item 3', 'item 3.1', '']);
      expect(metrics.last, (5, 9, 4));
    });
  });

  group('columns', () {
    test('left and right inset every item and do not scroll', () {
      final built = Items();
      final l = padded(
        built,
        10,
        const EdgeInsets.only(left: 2, right: 3, top: 1),
      );
      final v = View(20, 5, l)..frame();
      expect(
        built.blocks[0]!.constraints,
        const BoxConstraints(minWidth: 15, maxWidth: 15),
      );
      expect(v.shown, ['', '  item 0', '  item 1', '  item 2', '  item 3']);
      expect((built.blocks[0]!.parentData as ListParentData).dx, 2);

      l.scrollOffset = 4;
      v.frame();
      expect(v.shown.first, '  item 3');
    });

    test('a new padding lays the items out again within it', () {
      final built = Items();
      final l = padded(built, 10, EdgeInsets.zero);
      final v = View(20, 5, l)..frame();
      expect(v.shown, items(0, 5));
      l.padding = const EdgeInsets.only(left: 4);
      v.frame();
      expect(v.shown.first, '    item 0');
      expect(built.blocks[0]!.width, 16);
      l.padding = EdgeInsets.zero;
      v.frame();
      expect(v.shown, items(0, 5));
    });
  });

  group('moves', () {
    test('an item is at its offset plus the leading rows: jumpToIndex puts '
        'it at the top of the window', () {
      final metrics = <(int, int, int)>[];
      final l = padded(Items(), 10, pad, metrics: metrics);
      final v = View(20, 5, l)..frame();
      l.jumpToIndex(3);
      v.frame();
      expect(v.shown, items(3, 8));
      expect(metrics.last, (5, 13, 5));

      // the first item at the top, the leading rows scrolled away
      l.jumpToIndex(0);
      v.frame();
      expect(v.shown, items(0, 5));
      expect(metrics.last.$3, 2);
    });

    test('showIndex moves the least that shows the item', () {
      final metrics = <(int, int, int)>[];
      final l = padded(Items(), 10, pad, metrics: metrics);
      final v = View(20, 5, l)..frame();
      // item 0 is in view with the leading rows: no move
      l.showIndex(0);
      v.frame();
      expect(metrics.last.$3, 0);
      l.showIndex(2);
      v.frame();
      expect(metrics.last.$3, 0);
      // below the window: its bottom at the window's
      l.showIndex(4);
      v.frame();
      expect(v.shown, items(0, 5));
      expect(metrics.last.$3, 2);
      // the last item, with the rows after it
      l.showIndex(9);
      v.frame();
      expect(v.shown, ['item 6', 'item 7', 'item 8', 'item 9', '']);
      expect(metrics.last.$3, 8);
      // above it: its top at the window's
      l.showIndex(2);
      v.frame();
      expect(v.shown, items(2, 7));
      expect(metrics.last.$3, 4);
      // the first item, with the rows before it
      l.showIndex(0);
      v.frame();
      expect(v.shown, ['', '', 'item 0', 'item 1', 'item 2']);
      expect(metrics.last.$3, 0);
    });

    for (final fixed in <int?>[null, 3]) {
      test('a jump further than a window shows what walking there does, '
          'with ${fixed == null ? 'measured' : 'fixed'} heights', () {
        const padding = EdgeInsets.only(top: 4, bottom: 3);
        final total = fixed == null ? 1007 : 3007;
        for (final offset in [1, 4, 5, 9, 700, total - 6, total, total + 5]) {
          final jumped = <(int, int, int)>[];
          final walked = <(int, int, int)>[];
          final a = padded(
            Items(),
            1000,
            padding,
            metrics: jumped,
            itemExtent: fixed,
          );
          final b = padded(
            Items(),
            1000,
            padding,
            metrics: walked,
            itemExtent: fixed,
          );
          final va = View(20, 5, a)..frame();
          final vb = View(20, 5, b)..frame();
          a.scrollOffset = offset;
          va.frame();
          for (var o = 0; o < offset;) {
            o = o + 5 > offset ? offset : o + 5;
            b.scrollOffset = o;
            vb.frame();
          }
          expect(va.shown, vb.shown, reason: 'offset $offset');
          expect(jumped.last, walked.last, reason: 'offset $offset');
          // and back to the top, further than a window
          a.scrollOffset = 0;
          va.frame();
          expect(va.shown, ['', '', '', '', 'item 0']);
        }
      });
    }

    test('with an item extent, the item at an offset is the offset less the '
        'leading rows, divided', () {
      final metrics = <(int, int, int)>[];
      final l = padded(
        Items(),
        1000,
        const EdgeInsets.only(top: 3),
        metrics: metrics,
        itemExtent: 2,
      );
      final v = View(20, 5, l)..frame();
      expect(metrics, [(5, 2003, 0)]);
      l.scrollOffset = 1003;
      v.frame();
      expect(v.shown.first, 'item 500');
      l.scrollOffset = 1004;
      v.frame();
      expect(v.shown.first, 'item 500.1');
      l.scrollOffset = 1005;
      v.frame();
      expect(v.shown.first, 'item 501');
    });
  });

  group('building', () {
    test('builds the items the window and the cache reach, the padding '
        'taking its rows of them', () {
      final built = Items();
      View(20, 5, padded(built, 100000, pad)).frame();
      // rows 0 to 4 of the window and 3 of cache: 6 rows of items
      expect(built.built, range(0, 6));

      final flat = Items();
      View(20, 5, padded(flat, 100000, EdgeInsets.zero)).frame();
      expect(flat.built, range(0, 8));
    });

    test('with an item extent, builds the same', () {
      final built = Items();
      View(20, 5, padded(built, 100000, pad, itemExtent: 1)).frame();
      expect(built.built, range(0, 6));
    });
  });
}
