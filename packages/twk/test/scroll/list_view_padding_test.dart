// A ListView's padding scrolls with the items, as Flutter's does: the rows
// above the first item and below the last are part of the scrollable
// extent, the columns on either side inset every item and stay; a jump to
// an item, a move to keep one in view, a reverse list and the scrollbar all
// count the padding in. Whatever way the list is made, with measured
// heights or an itemExtent.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// `item <from>` to `item <to - 1>`.
List<String> items(int from, int to) => [
  for (var i = from; i < to; i++) 'item $i',
];

List<int> range(int from, int to) => [for (var i = from; i < to; i++) i];

const pad = EdgeInsets.only(top: 2, bottom: 1);

void main() {
  group('rows', () {
    testTwk('scroll with the items: the extent is theirs and the padding', (
      t,
    ) async {
      final controller = ScrollController();
      await t.pumpWidget(
        ListView.builder(
          padding: pad,
          controller: controller,
          itemCount: 10,
          itemBuilder: (_, i) => Text('item $i'),
        ),
        size: (20, 5),
      );
      expect(t.lines, ['', '', 'item 0', 'item 1', 'item 2']);
      expect(controller.position.maxScrollExtent, 8);

      controller.jumpTo(1);
      await t.pump();
      expect(t.lines, ['', 'item 0', 'item 1', 'item 2', 'item 3']);

      controller.jumpTo(8);
      await t.pump();
      expect(t.lines, ['item 6', 'item 7', 'item 8', 'item 9', '']);

      controller.jumpTo(0);
      await t.pump();
      expect(t.lines, ['', '', 'item 0', 'item 1', 'item 2']);
    });

    testTwk('the keys end at the padding: End shows the trailing rows, Home '
        'the leading ones', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        ListView.builder(
          autofocus: true,
          padding: pad,
          controller: controller,
          itemCount: 10,
          itemBuilder: (_, i) => Text('item $i'),
        ),
        size: (20, 5),
      );
      await t.press('end');
      await t.pump();
      expect(controller.offset, 8);
      expect(t.lines, ['item 6', 'item 7', 'item 8', 'item 9', '']);
      await t.press('home');
      await t.pump();
      expect(controller.offset, 0);
      expect(t.lines, ['', '', 'item 0', 'item 1', 'item 2']);
    });

    testTwk('every constructor takes it, an itemExtent or measured heights', (
      t,
    ) async {
      // the widget, and the index of its last item
      final lists = <String, (Widget, int)>{
        'children': (
          ListView(
            autofocus: true,
            padding: pad,
            children: [for (var i = 0; i < 10; i++) Text('item $i')],
          ),
          9,
        ),
        'builder': (
          ListView.builder(
            autofocus: true,
            padding: pad,
            itemCount: 10,
            itemBuilder: (_, i) => Text('item $i'),
          ),
          9,
        ),
        'builder with itemExtent': (
          ListView.builder(
            autofocus: true,
            padding: pad,
            itemExtent: 1,
            itemCount: 10,
            itemBuilder: (_, i) => Text('item $i'),
          ),
          9,
        ),
        'separated': (
          ListView.separated(
            autofocus: true,
            padding: pad,
            itemCount: 5,
            itemBuilder: (_, i) => Text('item ${2 * i}'),
            separatorBuilder: (_, i) => Text('item ${2 * i + 1}'),
          ),
          8,
        ),
      };
      for (final MapEntry(:key, :value) in lists.entries) {
        final (list, last) = value;
        await t.pumpWidget(
          SizedBox(key: ValueKey(key), child: list),
          size: (20, 5),
        );
        expect(t.lines, ['', '', 'item 0', 'item 1', 'item 2'], reason: key);
        await t.press('end');
        await t.pump();
        expect(t.lines, [...items(last - 3, last + 1), ''], reason: key);
      }
    });

    testTwk('with an itemExtent, items taller than a row and the padding '
        'add up', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        ListView.builder(
          padding: pad,
          itemExtent: 2,
          controller: controller,
          itemCount: 1000,
          itemBuilder: (_, i) => Text('item $i'),
        ),
        size: (20, 5),
      );
      // 2 + 2000 + 1 rows, 5 in view
      expect(controller.position.maxScrollExtent, 2003 - 5);
      expect(t.lines, ['', '', 'item 0', '', 'item 1']);
      controller.jumpTo(1002);
      await t.pump();
      expect(t.lines, ['item 500', '', 'item 501', '', 'item 502']);
    });

    testTwk('with measured heights, the extent is the padding and the '
        'items measured', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        ListView.builder(
          padding: pad,
          controller: controller,
          itemCount: 4,
          itemBuilder: (_, i) =>
              Text([for (var k = 0; k <= i % 2; k++) 'item $i.$k'].join('\n')),
        ),
        size: (20, 5),
      );
      // 2 + (1 + 2 + 1 + 2) + 1
      expect(controller.position.maxScrollExtent, 2 + 6 + 1 - 5);
      expect(t.lines, ['', '', 'item 0.0', 'item 1.0', 'item 1.1']);
    });

    testTwk('builds no more than the rows of the window and the cache '
        'reach', (t) async {
      final built = <int>[];
      await t.pumpWidget(
        ListView.builder(
          padding: pad,
          itemCount: 100000,
          itemBuilder: (_, i) {
            built.add(i);
            return Text('item $i');
          },
        ),
        size: (20, 5),
      );
      // two rows of padding in the window: two items fewer than 0 to 7
      expect(built, range(0, 6));
    });

    testTwk('the scrollbar counts the padding in: its thumb is the '
        'window of the items and the padding', (t) async {
      List<String> track() => [for (final line in t.lines) line[19]];
      Widget list({required int count, EdgeInsets? padding}) => Scrollbar(
        slim: true,
        child: ListView.builder(
          padding: padding,
          itemCount: count,
          itemBuilder: (_, i) => Text('item $i'),
        ),
      );
      // 30 items in 10 rows: 3 of the 10 cells of the track for the thumb
      await t.pumpWidget(list(count: 30), size: (20, 10));
      final plain = track();
      expect(plain.where((c) => c == '┃').length, 3);
      // 20 items and 10 rows of padding are as many rows
      await t.pumpWidget(
        list(padding: const EdgeInsets.symmetric(vertical: 5), count: 20),
      );
      expect(track(), plain);
    });

    testTwk('a new padding is taken by the list that is there', (t) async {
      Widget list(EdgeInsets padding) => ListView.builder(
        padding: padding,
        itemCount: 10,
        itemBuilder: (_, i) => Text('item $i'),
      );
      await t.pumpWidget(list(EdgeInsets.zero), size: (20, 5));
      expect(t.lines, items(0, 5));
      await t.pumpWidget(list(pad));
      expect(t.lines, ['', '', 'item 0', 'item 1', 'item 2']);
      await t.pumpWidget(list(const EdgeInsets.only(left: 3)));
      expect(t.lines, [for (final l in items(0, 5)) '   $l']);
    });
  });

  group('columns', () {
    testTwk('inset every item and do not scroll', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        ListView.builder(
          padding: const EdgeInsets.only(left: 2, right: 3),
          controller: controller,
          itemCount: 20,
          itemBuilder: (_, i) =>
              Text('item $i ${'x' * 30}', wrap: TextWrap.none, maxLines: 1),
        ),
        size: (20, 3),
      );
      // 15 columns of text, the first two empty
      expect(t.lines, [
        '  item 0 xxxxxxxx',
        '  item 1 xxxxxxxx',
        '  item 2 xxxxxxxx',
      ]);
      controller.jumpTo(5);
      await t.pump();
      expect(t.lines.first, '  item 5 xxxxxxxx');
    });
  });

  group('moves', () {
    testTwk('jumpToIndex puts the item at the top, at its offset and the '
        'leading rows', (t) async {
      final controller = ListController();
      await t.pumpWidget(
        ListView.builder(
          padding: pad,
          controller: controller,
          itemCount: 100,
          itemBuilder: (_, i) => Text('item $i'),
        ),
        size: (20, 5),
      );
      controller.jumpToIndex(40);
      await t.pump();
      expect(t.lines, items(40, 45));
      expect(controller.offset, 42);

      // the first item at the top, the leading rows scrolled away
      controller.jumpToIndex(0);
      await t.pump();
      expect(t.lines, items(0, 5));
      expect(controller.offset, 2);
    });

    testTwk('jumpToIndex before the first layout is as one after', (t) async {
      final controller = ListController()..jumpToIndex(40);
      await t.pumpWidget(
        ListView.builder(
          padding: pad,
          itemExtent: 1,
          controller: controller,
          itemCount: 100,
          itemBuilder: (_, i) => Text('item $i'),
        ),
        size: (20, 5),
      );
      expect(t.lines, items(40, 45));
      expect(controller.offset, 42);
    });

    testTwk('ensureIndexVisible moves the least', (t) async {
      final controller = ListController();
      await t.pumpWidget(
        ListView.builder(
          padding: pad,
          controller: controller,
          itemCount: 100,
          itemBuilder: (_, i) => Text('item $i'),
        ),
        size: (20, 5),
      );
      controller.ensureIndexVisible(1);
      await t.pump();
      expect(controller.offset, 0);
      controller.ensureIndexVisible(10);
      await t.pump();
      expect(t.lines, items(6, 11));
      expect(controller.offset, 8);
      controller.ensureIndexVisible(7);
      await t.pump();
      expect(controller.offset, 8);
      controller.ensureIndexVisible(3);
      await t.pump();
      expect(t.lines, items(3, 8));
      expect(controller.offset, 5);
    });
  });

  group('a reverse list', () {
    // item 0 at the bottom; the screen's top padding stays at the top, the
    // bottom one where the list starts
    Widget chat({ScrollController? controller, int count = 10}) =>
        ListView.builder(
          reverse: true,
          padding: pad,
          controller: controller,
          itemCount: count,
          itemBuilder: (_, i) => Text('item $i'),
        );

    testTwk('starts at the bottom, the bottom padding below item 0, and '
        'ends at the top padding', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(chat(controller: controller), size: (20, 5));
      expect(t.lines, ['item 3', 'item 2', 'item 1', 'item 0', '']);
      expect(controller.offset, 0);
      expect(controller.position.maxScrollExtent, 8);

      controller.jumpTo(8);
      await t.pump();
      expect(t.lines, ['', '', 'item 9', 'item 8', 'item 7']);

      controller.jumpTo(1);
      await t.pump();
      expect(t.lines, ['item 4', 'item 3', 'item 2', 'item 1', 'item 0']);
    });

    testTwk('items that do not fill the window are at its bottom, the '
        'padding around them', (t) async {
      await t.pumpWidget(chat(count: 2), size: (20, 8));
      expect(t.lines, ['', '', '', '', '', 'item 1', 'item 0', '']);
    });

    testTwk('jumpToIndex puts the item at the bottom, below it the '
        'rows after it', (t) async {
      final controller = ListController();
      await t.pumpWidget(
        ListView.builder(
          reverse: true,
          padding: pad,
          controller: controller,
          itemCount: 100,
          itemBuilder: (_, i) => Text('item $i'),
        ),
        size: (20, 5),
      );
      controller.jumpToIndex(10);
      await t.pump();
      expect(t.lines, [for (var i = 14; i >= 10; i--) 'item $i']);
      // the bottom padding and the ten items below the window
      expect(controller.offset, 11);

      // item 0 at the bottom of the window, the padding below it scrolled
      // away
      controller.jumpToIndex(0);
      await t.pump();
      expect(t.lines, ['item 4', 'item 3', 'item 2', 'item 1', 'item 0']);
      expect(controller.offset, 1);
    });
  });
}
