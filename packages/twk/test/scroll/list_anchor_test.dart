// A scrolled ListView keeps what it shows in place as items are inserted
// or removed before the first item it shows, by the keys of its items: in
// a list scrolled down, items inserted above the window; in a reverse
// list (a chat) scrolled up, older messages loaded above the window, and
// new ones coming at index 0. At its start, or stuck to its end, it keeps
// that as before.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// `item <from>` to `item <to - 1>`.
List<String> items(int from, int to) => [
  for (var i = from; i < to; i++) 'item $i',
];

/// A list of the items [ids], each keyed by its id, item `i` as tall as
/// [rows] gives.
Widget list(
  List<int> ids, {
  ScrollController? controller,
  bool reverse = false,
  bool keyed = true,
  bool find = false,
  int Function(int id)? rows,
}) => ListView.builder(
  reverse: reverse,
  autofocus: true,
  controller: controller,
  itemCount: ids.length,
  findChildIndexCallback: find
      ? (key) {
          final at = ids.indexOf((key as ValueKey<int>).value);
          return at < 0 ? null : at;
        }
      : null,
  itemBuilder: (_, i) {
    final id = ids[i];
    final n = rows?.call(id) ?? 1;
    return Text(
      n == 1
          ? 'item $id'
          : [for (var r = 0; r < n; r++) 'item $id.$r'].join('\n'),
      key: keyed ? ValueKey(id) : null,
    );
  },
);

/// The ids `from` to `to - 1`.
List<int> ids(int from, int to) => [for (var i = from; i < to; i++) i];

void main() {
  group('a list scrolled down', () {
    testTwk('keeps the rows it shows as items are inserted above the '
        'window', (t) async {
      final controller = ScrollController(initialOffset: 10);
      await t.pumpWidget(
        list(ids(0, 50), controller: controller),
        size: (20, 5),
      );
      expect(t.lines, items(10, 15));
      await t.pumpWidget(
        list([-3, -2, -1, ...ids(0, 50)], controller: controller),
      );
      expect(t.lines, items(10, 15));
      expect(controller.offset, 13);
    });

    testTwk('and as items are removed above it', (t) async {
      final controller = ScrollController(initialOffset: 10);
      await t.pumpWidget(
        list(ids(0, 50), controller: controller),
        size: (20, 5),
      );
      await t.pumpWidget(
        list([0, 1, 5, 6, 7, 8, 9, ...ids(10, 50)], controller: controller),
      );
      expect(t.lines, items(10, 15));
      expect(controller.offset, 7);
    });

    testTwk('keeps its row within an item taller than one, the items '
        'inserted as tall as they like', (t) async {
      final controller = ScrollController();
      int rows(int id) => id.isEven ? 2 : 3;
      await t.pumpWidget(
        list(ids(0, 30), controller: controller, rows: rows),
        size: (20, 5),
      );
      // items 0 to 3 are 10 rows: offset 11 is the second row of item 4
      controller.jumpTo(11);
      await t.pump();
      final shown = t.lines;
      expect(shown.first, 'item 4.1');
      await t.pumpWidget(
        list([-2, -1, ...ids(0, 30)], controller: controller, rows: rows),
      );
      expect(t.lines, shown);
      expect(controller.offset, 16);
    });

    testTwk('finds where the item it shows went by findChildIndexCallback '
        'when it went further than the items built', (t) async {
      final controller = ScrollController(initialOffset: 10);
      await t.pumpWidget(
        list(ids(0, 50), controller: controller, find: true),
        size: (20, 5),
      );
      await t.pumpWidget(
        list(
          // and 5 more after it: not as many before it as came
          [...ids(-100, 0), ...ids(0, 55)],
          controller: controller,
          find: true,
        ),
      );
      expect(t.lines, items(10, 15));
      expect(controller.offset, 110);
    });

    testTwk('keeps the rows the next item it shows has when the first is '
        'removed', (t) async {
      final controller = ScrollController(initialOffset: 10);
      await t.pumpWidget(
        list(ids(0, 50), controller: controller),
        size: (20, 5),
      );
      await t.pumpWidget(
        list([...ids(0, 10), ...ids(11, 50)], controller: controller),
      );
      expect(t.lines, ['item 9', ...items(11, 15)]);
    });

    testTwk('without keys keeps its offset: what it shows moves', (t) async {
      final controller = ScrollController(initialOffset: 10);
      await t.pumpWidget(
        list(ids(0, 50), controller: controller, keyed: false),
        size: (20, 5),
      );
      await t.pumpWidget(
        list([-3, -2, -1, ...ids(0, 50)], controller: controller, keyed: false),
      );
      expect(t.lines, items(7, 12));
      expect(controller.offset, 10);
    });
  });

  testTwk('a list at its start shows the items inserted there', (t) async {
    final controller = ScrollController();
    await t.pumpWidget(
      list(ids(0, 50), controller: controller),
      size: (20, 5),
    );
    await t.pumpWidget(
      list([-2, -1, ...ids(0, 50)], controller: controller),
    );
    expect(t.lines, ['item -2', 'item -1', ...items(0, 3)]);
    expect(controller.offset, 0);
  });

  testTwk('a list stuck to its end keeps following it as items are '
      'inserted above', (t) async {
    final controller = ScrollController(stickToEnd: true);
    await t.pumpWidget(
      list(ids(0, 20), controller: controller),
      size: (20, 5),
    );
    expect(t.lines, items(15, 20));
    await t.pumpWidget(
      list([-1, ...ids(0, 22)], controller: controller),
    );
    expect(t.lines, items(17, 22));
    expect(controller.offset, controller.position.maxOffset);
  });

  group('a reverse chat', () {
    // the messages, the newest first: message 0 at the bottom
    testTwk('scrolled up keeps the rows it shows as 3 messages arrive', (
      t,
    ) async {
      final controller = ScrollController();
      await t.pumpWidget(
        list(ids(0, 30), controller: controller, reverse: true),
        size: (20, 5),
      );
      controller.jumpTo(10);
      await t.pump();
      final shown = t.lines;
      expect(shown, [for (var i = 14; i >= 10; i--) 'item $i']);
      await t.pumpWidget(
        list(
          [-3, -2, -1, ...ids(0, 30)],
          controller: controller,
          reverse: true,
        ),
      );
      expect(t.lines, shown);
      expect(controller.offset, 13);
    });

    testTwk('scrolled up keeps the rows it shows as older messages load '
        'above them', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        list(ids(0, 30), controller: controller, reverse: true),
        size: (20, 5),
      );
      // at the top: the oldest messages
      await t.press('home');
      await t.pump();
      final shown = t.lines;
      expect(shown, [for (var i = 29; i >= 25; i--) 'item $i']);
      await t.pumpWidget(
        list(ids(0, 40), controller: controller, reverse: true),
      );
      expect(t.lines, shown);
      expect(controller.offset, 25);
    });

    testTwk('at the bottom keeps the bottom as older messages load', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        list(ids(0, 30), controller: controller, reverse: true),
        size: (20, 5),
      );
      await t.pumpWidget(
        list(ids(0, 40), controller: controller, reverse: true),
      );
      expect(t.lines, [for (var i = 4; i >= 0; i--) 'item $i']);
      expect(controller.offset, 0);
    });

    testTwk('separated, finds where the message it shows went by '
        'findItemIndexCallback as older ones load and new ones arrive at '
        'once', (t) async {
      final controller = ScrollController();
      Widget chat(List<int> ids) => ListView.separated(
        reverse: true,
        autofocus: true,
        controller: controller,
        itemCount: ids.length,
        findItemIndexCallback: (key) {
          final at = ids.indexOf((key as ValueKey<int>).value);
          return at < 0 ? null : at;
        },
        separatorBuilder: (_, _) => const Text('-'),
        itemBuilder: (_, i) => Text('item ${ids[i]}', key: ValueKey(ids[i])),
      );
      await t.pumpWidget(chat(ids(0, 30)), size: (20, 5));
      await t.press('home');
      await t.pump();
      final shown = t.lines;
      expect(shown, ['item 29', '-', 'item 28', '-', 'item 27']);
      await t.pumpWidget(chat([-2, -1, ...ids(0, 130)]));
      expect(t.lines, shown);
    });
  });
}
