// Scrolling in an app: a SingleChildScrollView moved by the keys while it
// has the focus, by the wheel over it and by its controller, its offset
// kept within its content; the wheel's acceleration on the fake clock;
// ensureVisible; the notifications it sends up; and a one-row scroll
// written as a hardware scroll.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// `item <from>` to `item <to - 1>`.
List<String> items(int from, int to) => [
  for (var i = from; i < to; i++) 'item $i',
];

/// A column of [count] rows, `item 0` on; the row [key] is given, if any,
/// is [keyed].
Widget column(int count, {GlobalKey? key, int keyed = -1}) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    for (var i = 0; i < count; i++)
      Text('item $i', key: i == keyed ? key : null),
  ],
);

/// [children] one below another, as wide as the column.
Widget rows(List<Widget> children) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: children,
);

/// Calls [onBuild] with its context as it builds.
final class Probe extends StatelessWidget {
  const Probe(this.onBuild, {super.key});

  final void Function(BuildContext context) onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild(context);
    return const Text('probe');
  }
}

/// What [f] returns, or what it throws.
Object? _caught(Object? Function() f) {
  try {
    return f();
    // the error is what is checked
    // ignore: avoid_catches_without_on_clauses
  } catch (e) {
    return e;
  }
}

/// A notification of a scrollable of an app's own.
final class Settled extends ScrollNotification {
  Settled({required super.metrics, required super.context});
}

void main() {
  group('SingleChildScrollView', () {
    testTwk('shows the start of a child taller than it, as wide as it is '
        'and as tall as its rows', (t) async {
      await t.pumpWidget(
        SingleChildScrollView(child: column(30)),
        size: (20, 5),
      );
      expect(t.lines, items(0, 5));
    });

    testTwk('padding is empty cells round the child that scroll with it', (
      t,
    ) async {
      final controller = ScrollController();
      await t.pumpWidget(
        SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(2, 1, 0, 2),
          child: column(6),
        ),
        size: (12, 5),
      );
      expect(t.lines, ['', '  item 0', '  item 1', '  item 2', '  item 3']);
      controller.jumpTo(99);
      await t.pump();
      expect(controller.offset, 4);
      expect(t.lines, ['  item 3', '  item 4', '  item 5', '', '']);
    });

    testTwk('Down and Up scroll it a row, PageDown and PageUp a window, End '
        'and Home to the ends, while it has the focus', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        SingleChildScrollView(controller: controller, child: column(30)),
        size: (20, 5),
      );
      await t.press('down');
      await t.pump();
      expect(controller.offset, 0);
      await t.press('tab');
      final offsets = <int>[];
      for (final key in [
        'down',
        'down',
        'up',
        'pagedown',
        'pagedown',
        'pageup',
        'end',
        'home',
      ]) {
        await t.press(key);
        offsets.add(controller.offset);
      }
      expect(offsets, [1, 2, 1, 6, 11, 6, 25, 0]);
      await t.press('pagedown');
      await t.pump();
      expect(t.lines, items(5, 10));
    });

    testTwk('a key that would not move it goes on to the focus nodes above, '
        'as do the keys of the other axis', (t) async {
      final above = <String>[];
      final controller = ScrollController();
      await t.pumpWidget(
        Focus(
          onKeyEvent: (node, event) {
            if (event.kind == KeyKind.press) {
              above.add(event.code.name);
            }
            return KeyEventResult.handled;
          },
          child: SingleChildScrollView(
            controller: controller,
            autofocus: true,
            child: column(8),
          ),
        ),
        size: (20, 5),
      );
      for (final key in ['up', 'home', 'down', 'left', 'end', 'pagedown']) {
        await t.press(key);
      }
      expect(controller.offset, 3);
      expect(above, ['up', 'home', 'left', 'pageDown']);
    });

    testTwk('the wheel over it scrolls it three rows, and the innermost of '
        'two under the mouse alone', (t) async {
      final outer = ScrollController();
      final inner = ScrollController();
      await t.pumpWidget(
        SingleChildScrollView(
          controller: outer,
          child: rows([
            SizedBox(
              height: 4,
              child: SingleChildScrollView(
                controller: inner,
                child: column(20),
              ),
            ),
            column(20),
          ]),
        ),
        size: (20, 8),
      );
      await t.mouse(MouseKind.wheelDown, 2, 1);
      await t.pump();
      await t.mouse(MouseKind.wheelDown, 2, 1);
      await t.pump();
      expect((outer.offset, inner.offset), (0, 6));
      await t.mouse(MouseKind.wheelDown, 2, 6);
      await t.pump();
      expect((outer.offset, inner.offset), (3, 6));
      await t.mouse(MouseKind.wheelUp, 2, 6);
      await t.pump();
      await t.mouse(MouseKind.wheelUp, 2, 6);
      await t.pump();
      expect((outer.offset, inner.offset), (0, 6));
      await t.pump();
      expect(t.lines.take(5), [...items(6, 10), 'item 0']);
    });

    testTwk('a wheel along the axis it does not scroll on goes to the '
        'nearest scrollable around it that does', (t) async {
      final across = ScrollController();
      final down = ScrollController();
      // a list down inside a view across
      await t.pumpWidget(
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: across,
          child: SizedBox(
            width: 40,
            child: SingleChildScrollView(
              controller: down,
              child: column(20),
            ),
          ),
        ),
        size: (10, 4),
      );
      await t.mouse(MouseKind.wheelRight, 2, 1);
      await t.pump();
      expect((across.offset, down.offset), (3, 0));
      await t.mouse(MouseKind.wheelDown, 2, 1);
      await t.pump();
      expect((across.offset, down.offset), (3, 3));
      // a view across inside a list down: the wheel down scrolls the list,
      // the wheel across the view
      final list = ScrollController();
      final row = ScrollController();
      await t.pumpWidget(
        SingleChildScrollView(
          key: const ValueKey('list'),
          controller: list,
          child: rows([
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: row,
              child: Text('0123456789' * 3),
            ),
            column(20),
          ]),
        ),
        size: (10, 4),
      );
      await t.mouse(MouseKind.wheelDown, 2, 0);
      await t.pump();
      expect((list.offset, row.offset), (3, 0));
      await t.mouse(MouseKind.wheelUp, 2, 1);
      await t.pump();
      expect(list.offset, 0);
      await t.mouse(MouseKind.wheelRight, 2, 0);
      await t.pump();
      expect((list.offset, row.offset), (0, 3));
    });

    testTwk('along a horizontal axis Left and Right scroll it a column, and '
        'either wheel three', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: controller,
          autofocus: true,
          child: Text('0123456789' * 3),
        ),
        size: (10, 2),
      );
      expect(t.lines, ['0123456789', '']);
      final offsets = <int>[];
      for (final key in ['right', 'right', 'left', 'down', 'end', 'home']) {
        await t.press(key);
        offsets.add(controller.offset);
      }
      expect(offsets, [1, 2, 1, 1, 20, 0]);
      await t.mouse(MouseKind.wheelDown, 1, 0);
      await t.pump();
      expect(controller.offset, 3);
      await t.mouse(MouseKind.wheelRight, 1, 0);
      await t.pump();
      expect(controller.offset, 6);
      await t.mouse(MouseKind.wheelLeft, 1, 0);
      await t.pump();
      await t.pump();
      expect(t.lines, ['3456789012', '']);
    });

    testTwk('keeps its offset within its content as the content and the '
        'window change', (t) async {
      final controller = ScrollController(initialScrollOffset: 100);
      Widget view(int count) =>
          SingleChildScrollView(controller: controller, child: column(count));
      await t.pumpWidget(view(30), size: (20, 5));
      expect(controller.offset, 25);
      expect(t.lines, items(25, 30));
      controller.jumpTo(40);
      expect(controller.offset, 25);
      controller.jumpTo(-2);
      expect(controller.offset, 0);
      controller.jumpTo(20);
      await t.pumpWidget(view(12));
      expect(controller.offset, 7);
      expect(t.lines, items(7, 12));
      await t.resize(20, 8);
      await t.pump();
      expect(controller.offset, 4);
      expect(t.lines, items(4, 12));
      await t.pumpWidget(view(3));
      expect(controller.offset, 0);
      expect(t.lines.take(4), [...items(0, 3), '']);
    });

    testTwk('fills its window with its style over the theme', (t) async {
      const blue = Color.rgb(0, 0, 200);
      await t.pumpWidget(
        Theme(
          data: ThemeData.dark,
          child: rows([
            SizedBox(height: 2, child: SingleChildScrollView(child: column(1))),
            SizedBox(
              height: 2,
              child: SingleChildScrollView(
                style: const Style(bg: blue),
                child: column(1),
              ),
            ),
          ]),
        ),
        size: (20, 4),
      );
      expect(t, styleAt(15, 1, hasBg(ThemeData.dark.background.bg!)));
      expect(t, styleAt(15, 3, hasBg(blue)));
    });

    testTwk('scrolled a row while all of it is on the screen, it has the '
        'terminal scroll in hardware and writes only the row brought in', (
      t,
    ) async {
      await t.pumpWidget(
        rows([
          SizedBox(
            height: 3,
            child: SingleChildScrollView(autofocus: true, child: column(10)),
          ),
          const Text('below'),
        ]),
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
  });

  group('ScrollController', () {
    testTwk('reads and moves the position, its listeners told of each move '
        'and of new extents; given to none or two, position fails', (
      t,
    ) async {
      final controller = ScrollController();
      expect(controller.hasClients, isFalse);
      expect(() => controller.position, throwsStateError);
      final heard = <String>[];
      void hear() {
        final p = controller.position;
        heard.add('${p.pixels}/${p.maxScrollExtent}/${p.viewportDimension}');
      }

      controller.addListener(hear);
      await t.pumpWidget(
        SingleChildScrollView(controller: controller, child: column(10)),
        size: (20, 4),
      );
      expect(controller.hasClients, isTrue);
      controller
        ..jumpTo(3)
        ..jumpTo(3);
      await t.pump();
      expect(t.lines, items(3, 7));
      await t.resize(20, 6);
      await t.pump();
      expect(heard, ['0/6/4', '3/6/4', '3/4/6']);
      expect(
        controller.position.metrics,
        const ScrollMetrics(
          pixels: 3,
          maxScrollExtent: 4,
          viewportDimension: 6,
        ),
      );

      controller.removeListener(hear);
      await t.pumpWidget(
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: controller,
                child: column(10),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: controller,
                child: column(10),
              ),
            ),
          ],
        ),
      );
      expect(() => controller.offset, throwsStateError);
      controller.jumpTo(2);
      await t.pump();
      expect(t.lines.first, 'item 2    item 2');
    });

    testTwk('a new controller takes the position over from the old', (
      t,
    ) async {
      final a = ScrollController();
      final b = ScrollController();
      Widget view(ScrollController c) =>
          SingleChildScrollView(controller: c, child: column(10));
      await t.pumpWidget(view(a), size: (20, 4));
      a.jumpTo(2);
      await t.pumpWidget(view(b));
      expect(a.hasClients, isFalse);
      expect(b.offset, 2);
      await t.pumpWidget(const SizedBox());
      expect(b.hasClients, isFalse);
    });

    testTwk('ensureVisible scrolls the least that shows a widget inside, its '
        'start when it is taller than the window', (t) async {
      final controller = ScrollController();
      final twelve = GlobalKey();
      final tall = GlobalKey();
      await t.pumpWidget(
        SingleChildScrollView(
          controller: controller,
          child: rows([
            column(20, key: twelve, keyed: 12),
            SizedBox(key: tall, height: 8),
            column(4),
          ]),
        ),
        size: (20, 5),
      );
      controller.ensureVisible(twelve.currentContext!);
      expect(controller.offset, 8);
      controller.ensureVisible(twelve.currentContext!);
      expect(controller.offset, 8);
      controller
        ..jumpTo(15)
        ..ensureVisible(twelve.currentContext!);
      expect(controller.offset, 12);
      controller.ensureVisible(tall.currentContext!);
      expect(controller.offset, 20);
      controller
        ..jumpTo(27)
        ..ensureVisible(tall.currentContext!);
      expect(controller.offset, 20);
      await t.pump();
      expect(t.lines, ['', '', '', '', '']);
    });

    testTwk('given to two scrollables, ensureVisible scrolls the one the '
        'widget is in', (t) async {
      final controller = ScrollController();
      final inSecond = GlobalKey();
      Widget view({Key? key}) => Expanded(
        child: SingleChildScrollView(
          controller: controller,
          child: rows([column(10), SizedBox(key: key, height: 1)]),
        ),
      );
      await t.pumpWidget(
        Column(
          children: [
            view(),
            view(key: inSecond),
          ],
        ),
        size: (20, 6),
      );
      controller.ensureVisible(inSecond.currentContext!);
      await t.pump();
      // the first stays at its top; the second shows its last row
      expect(t.lines, [
        'item 0',
        'item 1',
        'item 2',
        'item 8',
        'item 9',
        '',
      ]);
      final outside = GlobalKey();
      await t.pumpWidget(
        Column(
          children: [
            view(),
            view(key: inSecond),
            SizedBox(key: outside, height: 1),
          ],
        ),
        size: (20, 6),
      );
      expect(
        () => controller.ensureVisible(outside.currentContext!),
        throwsArgumentError,
      );
    });
  });

  testTwk('reverse turned the other way keeps the window on the items it '
      'showed; one that kept the end at the bottom keeps the end there', (
    t,
  ) async {
    final controller = ScrollController(stickToEnd: true);
    Widget app({required bool reverse}) => ListView(
      controller: controller,
      reverse: reverse,
      children: [for (final item in items(0, 20)) Text(item)],
    );
    await t.pumpWidget(app(reverse: false), size: (20, 4));
    controller.jumpTo(5);
    await t.pump();
    expect(t.lines, items(5, 9));
    await t.pumpWidget(app(reverse: true));
    expect(t.lines, items(5, 9).reversed);
    controller.jumpTo(controller.position.maxScrollExtent);
    await t.pumpWidget(app(reverse: false));
    expect(t.lines, items(16, 20), reason: 'the end, at the bottom');
    await t.pumpWidget(app(reverse: true));
    expect(t.lines, items(0, 4).reversed, reason: 'the end, at the bottom');
  });

  testTwk('Scrollable.ensureVisible scrolls each scrollable above, the '
      'nearest first; Scrollable.of finds the nearest position', (t) async {
    final outer = ScrollController();
    final inner = ScrollController();
    final target = GlobalKey();
    final first = GlobalKey();
    ScrollPosition? found;
    await t.pumpWidget(
      SingleChildScrollView(
        controller: outer,
        child: rows([
          column(10, key: first, keyed: 0),
          SizedBox(
            height: 3,
            child: SingleChildScrollView(
              controller: inner,
              child: rows([
                column(10, key: target, keyed: 7),
                Probe((context) => found = Scrollable.of(context)),
              ]),
            ),
          ),
          column(10),
        ]),
      ),
      size: (20, 5),
    );
    expect(identical(found, inner.position), isTrue);
    Scrollable.ensureVisible(target.currentContext!);
    expect((outer.offset, inner.offset), (8, 5));
    await t.pump();
    expect(t.lines, ['item 8', 'item 9', 'item 5', 'item 6', 'item 7']);
    expect(
      () => inner.ensureVisible(first.currentContext!),
      throwsArgumentError,
    );
  });

  group('the wheel', () {
    /// Turns the wheel [kind] a notch over a view of [controller]'s after
    /// [ms] milliseconds of the app's clock, and lets the frame that
    /// moves it run; returns how far it moved.
    Future<int> notch(
      TwkTester t,
      ScrollController controller,
      MouseKind kind, [
      int ms = 0,
    ]) async {
      if (ms > 0) {
        await t.pump(Duration(milliseconds: ms));
      }
      final from = controller.offset;
      await t.mouse(kind, 2, 2);
      await t.pump();
      return controller.offset - from;
    }

    testTwk('a notch scrolls three cells however fast they come, while '
        'the input is sparse', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        SingleChildScrollView(controller: controller, child: column(100)),
        size: (20, 5),
      );
      expect(
        [
          for (final ms in [0, 10, 10, 20, 10])
            await notch(t, controller, MouseKind.wheelDown, ms),
        ],
        [3, 3, 3, 3, 3],
      );
    });

    testTwk('the notches of a frame scroll it once, at the start of the '
        'frame, not as each comes', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        SingleChildScrollView(controller: controller, child: column(100)),
        size: (20, 5),
      );
      await t.mouse(MouseKind.wheelDown, 2, 2);
      await t.mouse(MouseKind.wheelDown, 2, 2);
      expect(controller.offset, 0);
      await t.pump();
      expect(controller.offset, 6);
    });

    testTwk('a burst of a trackpad, events 0 ms apart, turns dense: a row an '
        'event, one move a frame, growing within a stroke', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        SingleChildScrollView(controller: controller, child: column(1000)),
        size: (20, 5),
      );
      final moves = <int>[];
      for (var frame = 0; frame < 4; frame++) {
        final from = controller.offset;
        for (var i = 0; i < 20; i++) {
          await t.mouse(MouseKind.wheelDown, 2, 2);
        }
        await t.pump(const Duration(milliseconds: 8));
        moves.add(controller.offset - from);
      }
      // the first three events are sparse: 3 rows each, a pair under 2 ms
      // apart not yet twice; the rest a row an event, 1 + n / 30 times
      expect(moves.first, greaterThan(20));
      expect(moves.last, lessThan(3 * 20 + 1));
      expect(controller.offset, moves.reduce((a, b) => a + b));
    });

    testTwk('a ScrollConfiguration above a view gives it its own '
        'behavior; App.scrollBehavior gives the default of an app', (t) async {
      final plain = ScrollController();
      final fixed = ScrollController();
      await t.pumpWidget(
        App(
          scrollBehavior: const ScrollBehavior(step: 2),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  controller: plain,
                  child: column(100),
                ),
              ),
              Expanded(
                child: ScrollConfiguration(
                  behavior: const ScrollBehavior(step: 5),
                  child: SingleChildScrollView(
                    controller: fixed,
                    child: column(100),
                  ),
                ),
              ),
            ],
          ),
        ),
        size: (20, 5),
      );
      await t.mouse(MouseKind.wheelDown, 2, 2);
      await t.mouse(MouseKind.wheelDown, 15, 2);
      await t.pump();
      expect((plain.offset, fixed.offset), (2, 5));
    });

    testTwk('a behavior of a ScrollConfiguration changed reaches the view '
        'below it', (t) async {
      final controller = ScrollController();
      Widget view(int step) => ScrollConfiguration(
        behavior: ScrollBehavior(step: step),
        child: SingleChildScrollView(controller: controller, child: column(50)),
      );
      await t.pumpWidget(view(1), size: (20, 5));
      expect(await notch(t, controller, MouseKind.wheelDown), 1);
      await t.pumpWidget(view(4));
      expect(await notch(t, controller, MouseKind.wheelDown), 4);
    });

    testTwk('a key that moves the view drops what the wheel gathered for '
        'the frame', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        SingleChildScrollView(
          controller: controller,
          autofocus: true,
          child: column(100),
        ),
        size: (20, 5),
      );
      await t.mouse(MouseKind.wheelDown, 2, 2);
      await t.press('down');
      await t.pump();
      expect(controller.offset, 1);
    });

    testTwk('the wheel over a scrollbar of the view goes through the '
        "view's input", (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        Scrollbar(
          child: SingleChildScrollView(
            controller: controller,
            child: column(1000),
          ),
        ),
        size: (20, 5),
      );
      await t.mouse(MouseKind.wheelDown, 2, 2);
      await t.mouse(MouseKind.wheelDown, 19, 2);
      await t.pump();
      expect(controller.offset, 6);
    });
  });

  group('notifications', () {
    testTwk('a move by a key, the wheel or the controller sends a '
        'ScrollUpdateNotification up, and a key or the wheel past an end '
        'an OverscrollNotification', (t) async {
      final heard = <String>[];
      final controller = ScrollController();
      await t.pumpWidget(
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            final m = n.metrics;
            heard.add(switch (n) {
              ScrollUpdateNotification(:final scrollDelta) =>
                'update $scrollDelta to ${m.pixels}/${m.maxScrollExtent}',
              OverscrollNotification(:final overscroll) =>
                'over $overscroll at ${m.pixels}',
              _ => '$n',
            });
            return false;
          },
          child: SingleChildScrollView(
            controller: controller,
            autofocus: true,
            child: column(9),
          ),
        ),
        size: (20, 5),
      );
      await t.press('down');
      await t.mouse(MouseKind.wheelDown, 1, 1);
      await t.pump();
      await t.mouse(MouseKind.wheelDown, 1, 1);
      await t.pump();
      controller.jumpTo(0);
      await t.press('up');
      await t.press('pagedown');
      await t.press('pagedown');
      expect(heard, [
        'update 1 to 1/4',
        'update 3 to 4/4',
        'over 3 at 4',
        'update -4 to 0/4',
        'over -1 at 0',
        'update 4 to 4/4',
        'over 1 at 4',
        'over 5 at 4',
      ]);
    });

    testTwk('the depth counts the scrollables passed on the way up; a '
        'listener that returns true stops one', (t) async {
      final heard = <String>[];
      final inner = ScrollController();
      final outer = ScrollController();
      bool hear(String name, ScrollNotification n, {bool stop = false}) {
        heard.add('$name ${n.depth} ${n.metrics.pixels}');
        return stop;
      }

      var stop = false;
      await t.pumpWidget(
        NotificationListener<ScrollUpdateNotification>(
          onNotification: (n) => hear('top', n),
          child: SingleChildScrollView(
            controller: outer,
            child: rows([
              NotificationListener<ScrollNotification>(
                onNotification: (n) => hear('middle', n, stop: stop),
                child: SizedBox(
                  height: 2,
                  child: SingleChildScrollView(
                    controller: inner,
                    child: column(5),
                  ),
                ),
              ),
              column(10),
            ]),
          ),
        ),
        size: (20, 4),
      );
      inner.jumpTo(1);
      outer.jumpTo(2);
      stop = true;
      inner.jumpTo(2);
      expect(heard, ['middle 0 1', 'top 1 1', 'top 0 2', 'middle 0 2']);
      expect(
        ScrollUpdateNotification(
          metrics: const ScrollMetrics(
            pixels: 1,
            maxScrollExtent: 3,
            viewportDimension: 2,
          ),
          context: t.binding.focusManager.rootScope.context!,
          scrollDelta: 1,
        ).toString(),
        'ScrollUpdateNotification(depth 0, delta 1, '
        'ScrollMetrics(vertical 1 of 3, window 2))',
      );
    });
  });

  group('ScrollMetrics', () {
    testTwk('say how much of the content is after the window, and whether '
        'it shows either end', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        SingleChildScrollView(controller: controller, child: column(10)),
        size: (20, 4),
      );
      ScrollMetrics m() => controller.position.metrics;
      expect((m().extentAfter, m().atStart, m().atEnd), (6, true, false));
      controller.jumpTo(2);
      expect((m().extentAfter, m().atStart, m().atEnd), (4, false, false));
      controller.jumpTo(6);
      expect((m().extentAfter, m().atStart, m().atEnd), (0, false, true));
    });

    test('of an offset past the largest have nothing after the window', () {
      const m = ScrollMetrics(
        pixels: 8,
        maxScrollExtent: 6,
        viewportDimension: 4,
      );
      expect(m.extentAfter, 0);
      expect(m.atEnd, isTrue);
    });

    test('are equal, with the same hash, when their offsets, extents and '
        'axes are', () {
      // made apart, not as constants, which are one object
      ScrollMetrics at(int offset) => ScrollMetrics(
        pixels: offset,
        maxScrollExtent: 6,
        viewportDimension: 4,
      );
      final a = at(2);
      final b = at(2);
      expect(identical(a, b), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(at(3)));
      expect(
        a,
        isNot(
          const ScrollMetrics(
            pixels: 2,
            maxScrollExtent: 6,
            viewportDimension: 4,
            axis: Axis.horizontal,
          ),
        ),
      );
    });
  });

  testTwk('a position, its controller and its notifications say where the '
      'scrollable is in their toStrings', (t) async {
    final controller = ScrollController();
    expect('$controller', 'ScrollController(0 clients)');
    final heard = <String>[];
    await t.pumpWidget(
      NotificationListener<ScrollNotification>(
        onNotification: (n) {
          heard.add('$n');
          return false;
        },
        child: SingleChildScrollView(
          controller: controller,
          autofocus: true,
          child: column(10),
        ),
      ),
      size: (20, 4),
    );
    controller.jumpTo(2);
    await t.press('home');
    await t.press('up');
    expect('${controller.position}', 'ScrollPosition(vertical 0 of 6)');
    expect('$controller', 'ScrollController(offset 0)');
    String at(int offset) => 'ScrollMetrics(vertical $offset of 6, window 4)';
    expect(heard, [
      'ScrollUpdateNotification(depth 0, delta 2, ${at(2)})',
      'ScrollUpdateNotification(depth 0, delta -2, ${at(0)})',
      'OverscrollNotification(depth 0, overscroll -1, ${at(0)})',
    ]);
  });

  testTwk('a notification of its own says its type, its depth and where '
      'the scrollable is', (t) async {
    late BuildContext context;
    await t.pumpWidget(Probe((c) => context = c));
    final n = Settled(
      metrics: const ScrollMetrics(
        pixels: 1,
        maxScrollExtent: 6,
        viewportDimension: 4,
      ),
      context: context,
    );
    expect(
      '$n',
      'Settled(depth 0, ScrollMetrics(vertical 1 of 6, window 4))',
    );
  });

  testTwk('a controller disposed while a scrollable has it lets go of it, '
      'and the scrollable scrolls on without it', (t) async {
    final controller = ScrollController();
    await t.pumpWidget(
      SingleChildScrollView(
        controller: controller,
        autofocus: true,
        child: column(10),
      ),
      size: (20, 4),
    );
    controller.dispose();
    expect(controller.hasClients, isFalse);
    await t.press('down');
    await t.pump();
    expect(t.lines, items(1, 5));
  });

  testTwk('Scrollable.of with no scrollable above fails, naming the widget '
      'it was asked from; maybeOf gives null', (t) async {
    // what each gave in the build, an error caught as what it threw
    late final Object? maybe;
    late final Object? of;
    await t.pumpWidget(
      Probe((context) {
        maybe = Scrollable.maybeOf(context);
        of = _caught(() => Scrollable.of(context));
      }),
    );
    expect(maybe, isNull);
    expect(
      of,
      isA<StateError>().having(
        (e) => e.message,
        'message',
        'no Scrollable above Probe',
      ),
    );
  });
}
