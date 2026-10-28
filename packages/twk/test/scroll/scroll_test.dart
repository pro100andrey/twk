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
      await t.mouse(MouseKind.wheelDown, 2, 1);
      expect((outer.offset, inner.offset), (0, 6));
      await t.mouse(MouseKind.wheelDown, 2, 6);
      expect((outer.offset, inner.offset), (3, 6));
      await t.mouse(MouseKind.wheelUp, 2, 6);
      await t.mouse(MouseKind.wheelUp, 2, 6);
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
      expect((across.offset, down.offset), (3, 0));
      await t.mouse(MouseKind.wheelDown, 2, 1);
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
      expect((list.offset, row.offset), (3, 0));
      await t.mouse(MouseKind.wheelUp, 2, 1);
      expect(list.offset, 0);
      await t.mouse(MouseKind.wheelRight, 2, 0);
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
      expect(controller.offset, 3);
      await t.mouse(MouseKind.wheelRight, 1, 0);
      expect(controller.offset, 6);
      await t.mouse(MouseKind.wheelLeft, 1, 0);
      await t.pump();
      expect(t.lines, ['3456789012', '']);
    });

    testTwk('keeps its offset within its content as the content and the '
        'window change', (t) async {
      final controller = ScrollController(initialOffset: 100);
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
        heard.add('${p.offset}/${p.maxOffset}/${p.viewportExtent}');
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
        const ScrollMetrics(offset: 3, maxOffset: 4, viewportExtent: 6),
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
    /// [ms] milliseconds of the app's clock; returns how far it moved.
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
      return controller.offset - from;
    }

    testTwk('a notch scrolls three cells however fast they come, without an '
        'acceleration', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        SingleChildScrollView(controller: controller, child: column(100)),
        size: (20, 5),
      );
      expect(
        [
          for (final ms in [0, 10, 10, 2, 10])
            await notch(t, controller, MouseKind.wheelDown, ms),
        ],
        [3, 3, 3, 3, 3],
      );
    });

    testTwk('with a WheelAcceleration, the notches of a streak scroll the '
        'further the faster they come, up to its max; one after a pause, '
        'or the other way, starts a streak, and one of a burst goes as far '
        'as the one before', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        SingleChildScrollView(
          controller: controller,
          wheelAcceleration: const WheelAcceleration(),
          child: column(1000),
        ),
        size: (20, 5),
      );
      final moves = [
        for (final (kind, ms) in [
          (MouseKind.wheelDown, 0),
          (MouseKind.wheelDown, 10),
          (MouseKind.wheelDown, 10),
          (MouseKind.wheelDown, 2),
          (MouseKind.wheelDown, 200),
          (MouseKind.wheelDown, 50),
          (MouseKind.wheelDown, 50),
          (MouseKind.wheelDown, 50),
          (MouseKind.wheelDown, 50),
          (MouseKind.wheelUp, 10),
          (MouseKind.wheelUp, 2),
          (MouseKind.wheelUp, 120),
        ])
          await notch(t, controller, kind, ms),
      ];
      // 10 ms apart: the max, 6; 50 ms: 1.76, a cell carried every 4th;
      // 122 ms: 1.25
      expect(moves, [3, 18, 18, 18, 3, 5, 5, 5, 6, -3, -3, -3]);
      expect(
        const WheelAcceleration(max: 4).factor(
          const Duration(milliseconds: 10),
        ),
        4,
      );
      expect(
        const WheelAcceleration().factor(const Duration(milliseconds: 100)),
        closeTo(1.3165, 0.0001),
      );
    });

    testTwk('a streak goes on through the wheel over a scrollbar of the '
        'view', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        Scrollbar(
          child: SingleChildScrollView(
            controller: controller,
            wheelAcceleration: const WheelAcceleration(),
            child: column(1000),
          ),
        ),
        size: (20, 5),
      );
      await t.mouse(MouseKind.wheelDown, 2, 2);
      await t.pump(const Duration(milliseconds: 10));
      await t.mouse(MouseKind.wheelDown, 19, 2);
      expect(controller.offset, 21);
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
                'update $scrollDelta to ${m.offset}/${m.maxOffset}',
              OverscrollNotification(:final overscroll) =>
                'over $overscroll at ${m.offset}',
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
      await t.mouse(MouseKind.wheelDown, 1, 1);
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
        heard.add('$name ${n.depth} ${n.metrics.offset}');
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
            offset: 1,
            maxOffset: 3,
            viewportExtent: 2,
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
      const m = ScrollMetrics(offset: 8, maxOffset: 6, viewportExtent: 4);
      expect(m.extentAfter, 0);
      expect(m.atEnd, isTrue);
    });

    test('are equal, with the same hash, when their offsets, extents and '
        'axes are', () {
      // made apart, not as constants, which are one object
      ScrollMetrics at(int offset) =>
          ScrollMetrics(offset: offset, maxOffset: 6, viewportExtent: 4);
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
            offset: 2,
            maxOffset: 6,
            viewportExtent: 4,
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
      metrics: const ScrollMetrics(offset: 1, maxOffset: 6, viewportExtent: 4),
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

  group('WheelAcceleration', () {
    test('two are equal, with the same hash, when their streaks and their '
        'largest factors are', () {
      // made apart, not as constants, which are one object
      WheelAcceleration of(int ms) =>
          WheelAcceleration(streak: Duration(milliseconds: ms));
      final a = of(100);
      final b = of(100);
      expect(identical(a, b), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(
          const WheelAcceleration(streak: Duration(milliseconds: 100), max: 3),
        ),
      );
      expect(a, isNot(of(150)));
    });

    test('says its streak and its largest factor in its toString', () {
      expect(
        '${const WheelAcceleration()}',
        'WheelAcceleration(streak 150 ms, max 6.0)',
      );
    });
  });
}
