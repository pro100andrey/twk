// A ListView in an app: of a hundred thousand items it builds those in view
// and a few rows past them; items as tall as they like, scrolled by the
// keys, the wheel and its controller a row at a time; it follows the end
// while it sticks to the bottom; keyed items keep their State scrolled out
// and back and follow their keys to new indices; a one-row scroll is a
// hardware scroll.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// `item <from>` to `item <to - 1>`.
List<String> items(int from, int to) => [
  for (var i = from; i < to; i++) 'item $i',
];

List<int> range(int from, int to) => [for (var i = from; i < to; i++) i];

/// Item [i], [rows] rows: `item <i>`, then `item <i>.<k>` on row k.
Widget block(int i, int rows) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    for (var k = 0; k < rows; k++) Text(k == 0 ? 'item $i' : 'item $i.$k'),
  ],
);

/// Shows `<label>`; logs `+<label>` when its State is made and `-<label>`
/// when it is disposed.
final class Tally extends StatefulWidget {
  const Tally(this.label, this.log, {super.key});

  final String label;
  final List<String> log;

  @override
  State<Tally> createState() => _TallyState();
}

final class _TallyState extends State<Tally> {
  @override
  void initState() {
    super.initState();
    widget.log.add('+${widget.label}');
  }

  @override
  void dispose() {
    widget.log.add('-${widget.label}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(widget.label);
}

/// A label the items below it read.
final class Label extends InheritedWidget {
  const Label(this.value, {required super.child, super.key});

  final String value;

  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Label>()!.value;

  @override
  bool updateShouldNotify(Label oldWidget) => value != oldWidget.value;
}

void main() {
  testTwk('of a hundred thousand items, builds those in view and the cache '
      'rows below them, and those it is scrolled to', (t) async {
    final built = <int>[];
    final controller = ScrollController();
    await t.pumpWidget(
      ListView.builder(
        itemCount: 100000,
        controller: controller,
        itemBuilder: (_, i) {
          built.add(i);
          return Text('item $i');
        },
      ),
      size: (20, 5),
    );
    expect(t.lines, items(0, 5));
    expect(built, range(0, 8));
    expect(controller.position.maxOffset, 100000 - 5);

    built.clear();
    controller.jumpTo(controller.position.maxOffset);
    await t.pump();
    expect(t.lines, items(99995, 100000));
    expect(built, unorderedEquals(range(99992, 100000)));

    built.clear();
    controller.jumpTo(50000);
    await t.pump();
    expect(t.lines, items(50000, 50005));
    expect(built, unorderedEquals(range(49997, 50008)));
  });

  testTwk('Down and Up scroll items as tall as they like a row, PageDown '
      'and PageUp a window, End and Home to the ends, while it has the '
      'focus', (t) async {
    final controller = ScrollController();
    await t.pumpWidget(
      ListView.builder(
        itemCount: 30,
        controller: controller,
        itemBuilder: (_, i) => block(i, i % 3 + 1),
      ),
      size: (20, 5),
    );
    expect(t.lines, ['item 0', 'item 1', 'item 1.1', 'item 2', 'item 2.1']);
    await t.press('tab');
    final shown = <List<String>>[];
    for (final key in ['down', 'down', 'up', 'pagedown', 'end', 'home']) {
      await t.press(key);
      await t.pump();
      shown.add(t.lines);
    }
    expect(shown, [
      ['item 1', 'item 1.1', 'item 2', 'item 2.1', 'item 2.2'],
      ['item 1.1', 'item 2', 'item 2.1', 'item 2.2', 'item 3'],
      ['item 1', 'item 1.1', 'item 2', 'item 2.1', 'item 2.2'],
      ['item 3', 'item 4', 'item 4.1', 'item 5', 'item 5.1'],
      ['item 28', 'item 28.1', 'item 29', 'item 29.1', 'item 29.2'],
      ['item 0', 'item 1', 'item 1.1', 'item 2', 'item 2.1'],
    ]);
    // 30 items, 1 + 2 + 3 rows in each three
    expect(controller.position.maxOffset, 60 - 5);
  });

  testTwk('the wheel over it scrolls it three rows', (t) async {
    final controller = ScrollController();
    await t.pumpWidget(
      ListView.builder(
        itemCount: 100,
        controller: controller,
        itemBuilder: (_, i) => Text('item $i'),
      ),
      size: (20, 5),
    );
    await t.mouse(MouseKind.wheelDown, 1, 1);
    await t.pump();
    expect(controller.offset, 3);
    expect(t.lines, items(3, 8));
  });

  testTwk('keeps showing the end as items are added while it sticks to the '
      'bottom and shows it, which it starts at', (t) async {
    // a window of 3 rows, too few for the presenter to find a scroll itself
    Widget view(int count) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 3,
          child: ListView.builder(
            itemCount: count,
            stickToBottom: true,
            autofocus: true,
            itemBuilder: (_, i) => Text('item $i'),
          ),
        ),
        const Text('below'),
      ],
    );
    await t.pumpWidget(view(20), size: (20, 5));
    expect(t.lines.take(4), [...items(17, 20), 'below']);
    final from = t.terminal.frames.length;
    await t.pumpWidget(view(21));
    expect(t.lines.take(4), [...items(18, 21), 'below']);
    final bytes = t.written(since: from);
    expect(bytes, contains('\x1b[1;3r\x1b[S'));
    expect(bytes, isNot(contains('item 19')));

    await t.press('up');
    await t.pumpWidget(view(23));
    expect(t.lines.take(3), items(17, 20));
    await t.press('end');
    await t.pumpWidget(view(24));
    expect(t.lines.take(3), items(21, 24));
  });

  testTwk('an item with a key keeps its State scrolled out of view and '
      'back; one without is built anew', (t) async {
    final log = <String>[];
    final controller = ScrollController();
    await t.pumpWidget(
      ListView.builder(
        itemCount: 1000,
        controller: controller,
        cacheExtent: 0,
        itemBuilder: (_, i) =>
            Tally('$i', log, key: i.isEven ? ValueKey(i) : null),
      ),
      size: (20, 3),
    );
    expect(log, ['+0', '+1', '+2']);
    log.clear();
    controller.jumpTo(100);
    await t.pump();
    expect(t.lines, ['100', '101', '102']);
    expect(log, ['+100', '+101', '+102', '-1']);
    log.clear();
    controller.jumpTo(0);
    await t.pump();
    expect(t.lines, ['0', '1', '2']);
    expect(log, ['+1', '-101']);
  });

  testTwk('keeps at most maxKept keyed items, letting go of the one that '
      'left the view longest ago', (t) async {
    final log = <String>[];
    final controller = ScrollController(initialOffset: 10);
    await t.pumpWidget(
      ListView.builder(
        itemCount: 1000,
        controller: controller,
        cacheExtent: 0,
        maxKept: 2,
        itemBuilder: (_, i) => Tally('$i', log, key: ValueKey(i)),
      ),
      size: (20, 1),
    );
    for (var i = 11; i <= 13; i++) {
      controller.jumpTo(i);
      await t.pump();
    }
    expect(log, ['+10', '+11', '+12', '+13', '-10']);
    controller.jumpTo(11);
    await t.pump();
    expect(log, hasLength(5));
    expect(t.lines, ['11']);
  });

  testTwk('an item with a key takes its element to its new index as items '
      'are inserted above it or moved', (t) async {
    final log = <String>[];
    final keys = [for (var i = 0; i < 10; i++) 'k$i'];
    Widget view() => ListView.builder(
      itemCount: keys.length,
      itemBuilder: (_, i) => Tally(keys[i], log, key: ValueKey(keys[i])),
    );
    await t.pumpWidget(view(), size: (20, 3));
    expect(log, ['+k0', '+k1', '+k2', '+k3', '+k4', '+k5']);
    keys.insert(0, 'new');
    await t.pumpWidget(view());
    expect(t.lines, ['new', 'k0', 'k1']);
    expect(log, ['+k0', '+k1', '+k2', '+k3', '+k4', '+k5', '+new']);
    keys
      ..[0] = 'k1'
      ..[2] = 'new';
    await t.pumpWidget(view());
    expect(t.lines, ['k1', 'k0', 'new']);
    expect(log, hasLength(7));
  });

  testTwk('scrolled a row while all of it is on the screen, it has the '
      'terminal scroll in hardware and writes only the row brought in', (
    t,
  ) async {
    await t.pumpWidget(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 3,
            child: ListView.builder(
              itemCount: 100000,
              autofocus: true,
              itemBuilder: (_, i) => Text('item $i'),
            ),
          ),
          const Text('below'),
        ],
      ),
      size: (20, 8),
    );
    final from = t.terminal.frames.length;
    await t.press('down');
    await t.pump();
    final bytes = t.written(since: from);
    expect(bytes, contains('\x1b[1;3r\x1b[S'));
    expect(bytes, contains('item 3'));
    expect(bytes, isNot(contains('item 2')));
    expect(t.lines.take(4), [...items(1, 4), 'below']);

    final back = t.terminal.frames.length;
    await t.press('up');
    await t.pump();
    expect(t.written(since: back), contains('\x1b[1;3r\x1b[T'));
    expect(t.lines.take(4), [...items(0, 3), 'below']);
  });

  testTwk('a ListController moves it to an item, built or not', (t) async {
    final controller = ListController();
    await t.pumpWidget(
      ListView.builder(
        itemCount: 1000,
        controller: controller,
        itemBuilder: (_, i) => Text('item $i'),
      ),
      size: (20, 5),
    );
    controller.jumpToIndex(500);
    await t.pump();
    expect(t.lines, items(500, 505));
    expect(controller.offset, 500);
    controller.ensureIndexVisible(503);
    await t.pump();
    expect(t.lines, items(500, 505));
    controller.ensureIndexVisible(510);
    await t.pump();
    expect(t.lines, items(506, 511));
    expect(controller.offset, 506);
    controller.ensureIndexVisible(2);
    await t.pump();
    expect(t.lines, items(2, 7));
  });

  testTwk('of a move of the wheel and a ListController request in one '
      'frame, which builds the list again, the later wins', (t) async {
    final controller = ListController();
    Widget view(int count) => ListView.builder(
      itemCount: count,
      controller: controller,
      itemBuilder: (_, i) => Text('item $i'),
    );
    await t.pumpWidget(view(20), size: (20, 5));
    controller.jumpToIndex(15);
    await t.pump();
    expect(t.lines, items(15, 20));

    await t.mouse(MouseKind.wheelUp, 1, 1);
    controller.ensureIndexVisible(20);
    await t.pumpWidget(view(21));
    expect(t.lines, items(16, 21));
    expect(controller.offset, 16);

    controller.ensureIndexVisible(21);
    await t.mouse(MouseKind.wheelUp, 1, 1);
    await t.pumpWidget(view(22));
    expect(t.lines, items(13, 18));
    expect(controller.offset, 13);

    // the wheel back to where the list is, after the request
    await t.mouse(MouseKind.wheelDown, 1, 1);
    controller.jumpToIndex(0);
    await t.mouse(MouseKind.wheelUp, 1, 1);
    await t.pumpWidget(view(23));
    expect(t.lines, items(13, 18));
    expect(controller.offset, 13);
  });

  testTwk('a ListController request made as the list tells its position '
      'where it settled moves it in the same frame', (t) async {
    final controller = ListController();
    var asked = false;
    controller.addListener(() {
      if (!asked && controller.offset == 50) {
        asked = true;
        controller.jumpToIndex(70);
      }
    });
    await t.pumpWidget(
      ListView.builder(
        itemCount: 100,
        controller: controller,
        itemBuilder: (_, i) => Text('item $i'),
      ),
      size: (20, 5),
    );
    controller.jumpToIndex(50);
    await t.pump();
    expect(t.lines, items(70, 75));
    expect(controller.offset, 70);
  });

  testTwk('a ListController keeps the latest request made while it has no '
      'list for the next list mounted, in place of its offset; a jumpTo '
      'after it drops it', (t) async {
    final controller = ListController(initialOffset: 30)
      ..jumpToIndex(500)
      ..ensureIndexVisible(80);
    Widget view() => ListView.builder(
      itemCount: 1000,
      controller: controller,
      itemBuilder: (_, i) => Text('item $i'),
    );
    await t.pumpWidget(view(), size: (20, 5));
    expect(t.lines, items(76, 81));
    expect(controller.offset, 76);

    // taken by that list only
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(view());
    expect(t.lines, items(30, 35));

    await t.pumpWidget(const SizedBox());
    controller
      ..jumpToIndex(500)
      ..jumpTo(0);
    await t.pumpWidget(view());
    expect(t.lines, items(30, 35));
  });

  testTwk('ensureVisible scrolls the least that shows an item', (t) async {
    final controller = ScrollController();
    final seven = GlobalKey();
    await t.pumpWidget(
      ListView.builder(
        itemCount: 100,
        controller: controller,
        itemBuilder: (_, i) => Text('item $i', key: i == 7 ? seven : null),
      ),
      size: (20, 5),
    );
    controller.ensureVisible(seven.currentContext!);
    await t.pump();
    expect(controller.offset, 3);
    expect(t.lines, items(3, 8));
  });

  testTwk('an item a GlobalKey takes out of the list goes with its State, '
      'and the list builds what is in its place', (t) async {
    final log = <String>[];
    final key = GlobalKey();
    Widget view({required bool inList}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 3,
          child: ListView.builder(
            itemCount: 10,
            itemBuilder: (_, i) => i == 1 && inList
                ? Tally('tally', log, key: key)
                : Text('item $i'),
          ),
        ),
        if (!inList) Tally('tally', log, key: key),
      ],
    );
    await t.pumpWidget(view(inList: true), size: (20, 5));
    expect(t.lines.take(3), ['item 0', 'tally', 'item 2']);
    await t.pumpWidget(view(inList: false));
    expect(t.lines.take(4), ['item 0', 'item 1', 'item 2', 'tally']);
    await t.pumpWidget(view(inList: true));
    expect(t.lines.take(4), ['item 0', 'tally', 'item 2', '']);
    expect(log, ['+tally']);
  });

  testTwk('an item whose builder throws shows the error in its place', (
    t,
  ) async {
    await t.pumpWidget(
      ListView.builder(
        itemCount: 10,
        itemBuilder: (_, i) =>
            i == 1 ? throw StateError('no item 1') : Text('item $i'),
      ),
      size: (30, 3),
    );
    expect(t.lines, ['item 0', 'Bad state: no item 1', 'item 2']);
    expect(t.logs.records.map((r) => '${r.error}'), ['Bad state: no item 1']);
  });

  testTwk('builds its items again when it is built again; a list of '
      'children', (t) async {
    await t.pumpWidget(
      ListView(children: const [Text('a'), Text('b')]),
      size: (20, 3),
    );
    expect(t.lines, ['a', 'b', '']);
    await t.pumpWidget(
      ListView(children: const [Text('c'), Text('d'), Text('e'), Text('f')]),
    );
    expect(t.lines, ['c', 'd', 'e']);
    await t.pumpWidget(ListView(children: const [Text('g')]));
    expect(t.lines, ['g', '', '']);
  });

  testTwk('builds its items again when an inherited widget its builder '
      'depends on changes', (t) async {
    final list = ListView.builder(
      itemCount: 10,
      itemBuilder: (context, i) => Text('${Label.of(context)} $i'),
    );
    await t.pumpWidget(Label('a', child: list), size: (20, 2));
    expect(t.lines, ['a 0', 'a 1']);
    await t.pumpWidget(Label('b', child: list));
    expect(t.lines, ['b 0', 'b 1']);
  });

  testTwk('fills its window with its style over the theme', (t) async {
    const blue = Color.rgb(0, 0, 200);
    await t.pumpWidget(
      Theme(
        data: ThemeData.dark,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 2, child: ListView(children: const [Text('a')])),
            SizedBox(
              height: 2,
              child: ListView(
                style: const Style(bg: blue),
                children: const [Text('b')],
              ),
            ),
          ],
        ),
      ),
      size: (20, 4),
    );
    expect(t, styleAt(15, 1, hasBg(ThemeData.dark.background.bg!)));
    expect(t, styleAt(15, 3, hasBg(blue)));
  });
}
