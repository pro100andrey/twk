// ListView parity with the lists of other frameworks: a reverse list, item
// 0 at the bottom, scrolled by the keys, the wheel and a scrollbar the way
// the screen shows it, its items at the bottom of the window while they do
// not fill it, keeping the bottom as items come while it shows it; a
// separated list, its separators built as they come into view and left out
// of the semantics; a ScrollController that sticks to the end of a
// SingleChildScrollView and a ListView while they show it.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// `item <from>` down to `item <to + 1>`, as a reverse list shows them.
List<String> down(int from, int to) => [
  for (var i = from; i > to; i--) 'item $i',
];

/// `item <from>` to `item <to - 1>`.
List<String> items(int from, int to) => [
  for (var i = from; i < to; i++) 'item $i',
];

/// A column of [count] rows, `item 0` on.
Widget column(int count) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [for (var i = 0; i < count; i++) Text('item $i')],
);

/// A cell as text: its glyph, after `~` when it is in reverse video.
String cellText(VtCell cell) =>
    '${cell.attrs & Attr.reverse != 0 ? '~' : ''}${cell.text}';

/// The cells of column [x], rows 0 to [rows] - 1.
List<String> cellsDown(TwkTester t, int x, int rows) => [
  for (var y = 0; y < rows; y++) cellText(t.cell(x, y)),
];

/// [n] blank cells of a track.
List<String> track(int n) => [for (var i = 0; i < n; i++) ' '];

/// [n] cells of a thumb.
List<String> thumb(int n) => [for (var i = 0; i < n; i++) '~ '];

void main() {
  group('a reverse list', () {
    testTwk('shows item 0 at the bottom, at offset 0; Up and PageUp scroll '
        'up to the items after it, Down back, Home to the last item and End '
        'to item 0', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        ListView.builder(
          reverse: true,
          itemCount: 30,
          controller: controller,
          itemBuilder: (_, i) => Text('item $i'),
        ),
        size: (20, 5),
      );
      expect(t.lines, down(4, -1));
      expect(controller.offset, 0);
      expect(controller.position.maxOffset, 25);
      await t.press('tab');
      final shown = <List<Object>>[];
      for (final key in ['up', 'up', 'down', 'pageup', 'home', 'end']) {
        await t.press(key);
        await t.pump();
        shown.add([controller.offset, t.lines]);
      }
      expect(shown, [
        [1, down(5, 0)],
        [2, down(6, 1)],
        [1, down(5, 0)],
        [6, down(10, 5)],
        [25, down(29, 24)],
        [0, down(4, -1)],
      ]);
    });

    testTwk('the wheel up scrolls it up three rows, and down back', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        ListView.builder(
          reverse: true,
          itemCount: 100,
          controller: controller,
          itemBuilder: (_, i) => Text('item $i'),
        ),
        size: (20, 5),
      );
      await t.mouse(MouseKind.wheelUp, 1, 1);
      await t.pump();
      expect(controller.offset, 3);
      expect(t.lines, down(7, 2));
      await t.mouse(MouseKind.wheelDown, 1, 1);
      await t.pump();
      expect(controller.offset, 0);
      expect(t.lines, down(4, -1));
    });

    testTwk('has its items at the bottom while they do not fill the '
        'window; keeps the bottom as items come at index 0 while it shows '
        'it, and the items it shows once scrolled up, until End', (t) async {
      final controller = ScrollController();
      // the messages, the oldest first: item 0, the newest, at the bottom
      Widget chat(int count) => ListView.builder(
        reverse: true,
        autofocus: true,
        itemCount: count,
        controller: controller,
        itemBuilder: (_, i) => Text('item ${count - 1 - i}'),
      );
      await t.pumpWidget(chat(2), size: (20, 5));
      expect(t.lines, ['', '', '', 'item 0', 'item 1']);
      await t.pumpWidget(chat(4));
      expect(t.lines, ['', 'item 0', 'item 1', 'item 2', 'item 3']);
      await t.pumpWidget(chat(7));
      expect(t.lines, items(2, 7));
      expect(controller.offset, 0);

      await t.press('up');
      await t.pump();
      expect(t.lines, items(1, 6));
      await t.pumpWidget(chat(9));
      expect(t.lines, items(1, 6));
      expect(controller.offset, 3);

      await t.press('end');
      await t.pumpWidget(chat(10));
      expect(t.lines, items(5, 10));
      expect(controller.offset, 0);

      // fewer again: at the bottom of the window
      await t.pumpWidget(chat(3));
      expect(t.lines, ['', '', 'item 0', 'item 1', 'item 2']);
    });

    testTwk('starts at the initial offset of its controller, from the '
        'bottom', (t) async {
      final controller = ScrollController(initialOffset: 4);
      await t.pumpWidget(
        ListView.builder(
          reverse: true,
          itemCount: 30,
          controller: controller,
          itemBuilder: (_, i) => Text('item $i'),
        ),
        size: (20, 5),
      );
      expect(controller.offset, 4);
      expect(t.lines, down(8, 3));
    });

    testTwk("a scrollbar's thumb is at the bottom of its track at offset 0, "
        'at its top at the end; a press above the thumb scrolls a window '
        'up', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        Scrollbar(
          child: ListView.builder(
            reverse: true,
            itemCount: 30,
            controller: controller,
            itemBuilder: (_, i) => Text('item $i'),
          ),
        ),
        size: (20, 10),
      );
      // 80 eighths of track, 27 of thumb
      expect(cellsDown(t, 19, 10), [...track(6), '▃', ...thumb(3)]);
      controller.jumpTo(20);
      await t.pump();
      expect(cellsDown(t, 19, 10), [...thumb(3), '~▅', ...track(6)]);
      expect(t.lines.first, 'item 29');

      controller.jumpTo(0);
      await t.pump();
      await t.click(19, 0);
      await t.pump();
      expect(controller.offset, 10);
      expect(t.lines.last, 'item 10');
    });

    testTwk('a drag of the thumb up scrolls it up', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        Scrollbar(
          child: ListView.builder(
            reverse: true,
            itemCount: 30,
            controller: controller,
            itemBuilder: (_, i) => Text('item $i'),
          ),
        ),
        size: (20, 10),
      );
      await t.mouse(MouseKind.down, 19, 8);
      await t.mouse(MouseKind.drag, 19, 0);
      await t.mouse(MouseKind.up, 19, 0);
      await t.pump();
      expect(controller.offset, 20);
      expect(t.lines.first, 'item 29');
    });

    testTwk('ensureVisible scrolls the least that shows an item above the '
        'window', (t) async {
      final controller = ScrollController();
      final six = GlobalKey();
      await t.pumpWidget(
        ListView.builder(
          reverse: true,
          itemCount: 30,
          controller: controller,
          itemBuilder: (_, i) => Text('item $i', key: i == 6 ? six : null),
        ),
        size: (20, 5),
      );
      controller.ensureVisible(six.currentContext!);
      await t.pump();
      expect(controller.offset, 2);
      expect(t.lines, down(6, 1));
    });

    testTwk('jumpToIndex puts the item at the bottom of the window, the edge '
        'the list reads from; one near the top end shows the end', (t) async {
      final controller = ListController();
      await t.pumpWidget(
        ListView.builder(
          reverse: true,
          itemCount: 30,
          controller: controller,
          itemBuilder: (_, i) => Text('item $i'),
        ),
        size: (20, 5),
      );
      controller.jumpToIndex(10);
      await t.pump();
      expect(t.lines, down(14, 9));
      expect(controller.offset, 10);
      controller.jumpToIndex(28);
      await t.pump();
      expect(t.lines, down(29, 24));
      expect(controller.offset, 25);
      controller.jumpToIndex(0);
      await t.pump();
      expect(t.lines, down(4, -1));
      expect(controller.offset, 0);
    });

    testTwk('a jumpToIndex asked before the list has the controller puts the '
        'item at the bottom as the list is first laid out, in place of the '
        'initial offset', (t) async {
      final controller = ListController(initialOffset: 4)..jumpToIndex(10);
      await t.pumpWidget(
        ListView.builder(
          reverse: true,
          itemCount: 30,
          controller: controller,
          itemBuilder: (_, i) => Text('item $i'),
        ),
        size: (20, 5),
      );
      expect(t.lines, down(14, 9));
      expect(controller.offset, 10);
    });

    testTwk('separated: jumpToIndex puts the item at the bottom, its '
        'separators above it', (t) async {
      final controller = ListController();
      await t.pumpWidget(
        ListView.separated(
          reverse: true,
          itemCount: 100,
          controller: controller,
          itemBuilder: (_, i) => Text('item $i'),
          separatorBuilder: (_, i) => const Text('--'),
        ),
        size: (20, 5),
      );
      controller.jumpToIndex(40);
      await t.pump();
      expect(t.lines, ['item 42', '--', 'item 41', '--', 'item 40']);
    });

    testTwk('an item taller than the window shows its bottom, to '
        'jumpToIndex and to ensureIndexVisible', (t) async {
      final controller = ListController();
      await t.pumpWidget(
        ListView.builder(
          reverse: true,
          itemCount: 30,
          controller: controller,
          itemBuilder: (_, i) => i == 10
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (var r = 0; r < 8; r++) Text('ten $r')],
                )
              : Text('item $i'),
        ),
        size: (20, 5),
      );
      final bottom = [for (var r = 3; r < 8; r++) 'ten $r'];
      controller.jumpToIndex(10);
      await t.pump();
      expect(t.lines, bottom);
      controller.jumpTo(0);
      await t.pump();
      controller.ensureIndexVisible(10);
      await t.pump();
      expect(t.lines, bottom);
      // from above it, the same
      controller.jumpTo(controller.position.maxOffset);
      await t.pump();
      controller.ensureIndexVisible(10);
      await t.pump();
      expect(t.lines, bottom);
    });

    testTwk('ensureIndexVisible scrolls the least that shows an item that '
        'fits', (t) async {
      final controller = ListController();
      await t.pumpWidget(
        ListView.builder(
          reverse: true,
          itemCount: 30,
          controller: controller,
          itemBuilder: (_, i) => Text('item $i'),
        ),
        size: (20, 5),
      );
      controller.ensureIndexVisible(8);
      await t.pump();
      expect(t.lines, down(8, 3));
      controller.ensureIndexVisible(2);
      await t.pump();
      expect(t.lines, down(6, 1));
    });

    testTwk('separated: a separator above each item but the last', (t) async {
      await t.pumpWidget(
        ListView.separated(
          reverse: true,
          itemCount: 3,
          itemBuilder: (_, i) => Text('item $i'),
          separatorBuilder: (_, i) => Text('-- $i'),
        ),
        size: (20, 6),
      );
      expect(t.lines, ['', 'item 2', '-- 1', 'item 1', '-- 0', 'item 0']);
    });
  });

  group('a separated list', () {
    testTwk('builds a separator between each two items, as they come into '
        'view', (t) async {
      final built = <String>[];
      final controller = ScrollController();
      await t.pumpWidget(
        ListView.separated(
          itemCount: 1000,
          controller: controller,
          itemBuilder: (_, i) {
            built.add('i$i');
            return Text('item $i');
          },
          separatorBuilder: (_, i) {
            built.add('s$i');
            return Text('-- $i');
          },
        ),
        size: (20, 5),
      );
      expect(t.lines, ['item 0', '-- 0', 'item 1', '-- 1', 'item 2']);
      // the window's five rows and the three of the cache
      expect(built, ['i0', 's0', 'i1', 's1', 'i2', 's2', 'i3', 's3']);
      expect(controller.position.maxOffset, 1999 - 5);

      built.clear();
      controller.jumpTo(1000);
      await t.pump();
      expect(t.lines, ['item 500', '-- 500', 'item 501', '-- 501', 'item 502']);
      expect(
        built,
        unorderedEquals([
          for (var c = 997; c < 1008; c++)
            if (c.isEven) 'i${c ~/ 2}' else 's${c ~/ 2}',
        ]),
      );

      built.clear();
      await t.press('tab');
      await t.press('down');
      await t.pump();
      expect(t.lines.first, '-- 500');
      expect(built, ['i504']);
    });

    testTwk('a ListController moves it to an item, never to a separator', (
      t,
    ) async {
      final controller = ListController();
      await t.pumpWidget(
        ListView.separated(
          itemCount: 100,
          controller: controller,
          itemBuilder: (_, i) => Text('item $i'),
          separatorBuilder: (_, i) => const Text('--'),
        ),
        size: (20, 5),
      );
      controller.jumpToIndex(40);
      await t.pump();
      expect(t.lines, ['item 40', '--', 'item 41', '--', 'item 42']);
      controller.ensureIndexVisible(45);
      await t.pump();
      expect(t.lines, ['item 43', '--', 'item 44', '--', 'item 45']);
    });

    testTwk('reads as a list of its items, the separators left out', (
      t,
    ) async {
      await t.pumpWidget(
        ListView.separated(
          itemCount: 3,
          itemBuilder: (_, i) => Text('item $i'),
          separatorBuilder: (_, i) => const Text('----'),
        ),
        size: (20, 5),
      );
      expect(t.binding.semantics.lines, [
        'list 3 items',
        'listitem item 0',
        'listitem item 1',
        'listitem item 2',
      ]);
    });

    testTwk('of no items, shows nothing', (t) async {
      await t.pumpWidget(
        ListView.separated(
          itemCount: 0,
          itemBuilder: (_, i) => Text('item $i'),
          separatorBuilder: (_, i) => const Text('--'),
        ),
        size: (20, 3),
      );
      expect(t.lines, ['', '', '']);
    });
  });

  group('a controller that sticks to the end', () {
    testTwk('keeps a SingleChildScrollView at the end as its content grows, '
        'starting there; scrolled up, it stays until End', (t) async {
      final controller = ScrollController(stickToEnd: true);
      Widget view(int count) => SingleChildScrollView(
        controller: controller,
        autofocus: true,
        child: column(count),
      );
      await t.pumpWidget(view(10), size: (20, 5));
      expect(t.lines, items(5, 10));
      await t.pumpWidget(view(12));
      expect(t.lines, items(7, 12));
      expect(controller.offset, 7);

      await t.press('up');
      await t.pumpWidget(view(14));
      expect(t.lines, items(6, 11));
      expect(controller.offset, 6);

      await t.press('end');
      await t.pumpWidget(view(15));
      expect(t.lines, items(10, 15));
    });

    testTwk('keeps a ListView at the end as items come; the wheel up leaves '
        'it, the wheel back down to the end sticks again', (t) async {
      final controller = ScrollController(stickToEnd: true);
      Widget view(int count) => ListView.builder(
        controller: controller,
        itemCount: count,
        itemBuilder: (_, i) => Text('item $i'),
      );
      await t.pumpWidget(view(20), size: (20, 5));
      expect(t.lines, items(15, 20));
      await t.pumpWidget(view(21));
      expect(t.lines, items(16, 21));

      await t.mouse(MouseKind.wheelUp, 1, 1);
      await t.pumpWidget(view(25));
      expect(t.lines, items(13, 18));

      // 13 + 3 + 3 + 3 = 22 rows above the window, 25 - 5 at most
      for (var i = 0; i < 3; i++) {
        await t.mouse(MouseKind.wheelDown, 1, 1);
      }
      await t.pump();
      expect(t.lines, items(20, 25));
      await t.pumpWidget(view(27));
      expect(t.lines, items(22, 27));
    });

    testTwk('keeps a reverse ListView at its end, offset 0 at the bottom, '
        'as items come at index 0, starting there; scrolled up, it stays on '
        'the items it shows until End', (t) async {
      final controller = ScrollController(stickToEnd: true);
      // the messages, the oldest first: item 0, the newest, at the bottom
      Widget chat(int count) => ListView.builder(
        reverse: true,
        autofocus: true,
        itemCount: count,
        controller: controller,
        itemBuilder: (_, i) => Text('item ${count - 1 - i}'),
      );
      await t.pumpWidget(chat(20), size: (20, 5));
      expect(t.lines, items(15, 20));
      expect(controller.offset, 0);
      await t.pumpWidget(chat(22));
      expect(t.lines, items(17, 22));
      expect(controller.offset, 0);

      await t.press('up');
      await t.pump();
      await t.pumpWidget(chat(25));
      expect(t.lines, items(16, 21));
      expect(controller.offset, 4);

      await t.press('end');
      await t.pumpWidget(chat(26));
      expect(t.lines, items(21, 26));
      expect(controller.offset, 0);
    });

    testTwk('a ListController that does moves a list showing its end to an '
        'item, which it then stays on', (t) async {
      for (final reverse in [false, true]) {
        final controller = ListController(stickToEnd: true);
        Widget view(int count) => ListView.builder(
          key: ValueKey(reverse),
          reverse: reverse,
          itemCount: count,
          controller: controller,
          itemBuilder: (_, i) => Text('item $i'),
        );
        await t.pumpWidget(view(30), size: (20, 5));
        controller.jumpToIndex(10);
        await t.pump();
        final shown = reverse ? down(14, 9) : items(10, 15);
        expect(t.lines, shown, reason: 'reverse: $reverse');
        // an item at the end: at the top of a reverse list, which moves
        // the items its indices are on
        if (!reverse) {
          await t.pumpWidget(view(31));
          expect(t.lines, shown);
        }
      }
    });

    testTwk('one that does not stays where it is', (t) async {
      final controller = ScrollController();
      Widget view(int count) =>
          SingleChildScrollView(controller: controller, child: column(count));
      await t.pumpWidget(view(10), size: (20, 5));
      controller.jumpTo(5);
      await t.pump();
      await t.pumpWidget(view(12));
      expect(t.lines, items(5, 10));
    });
  });
}
