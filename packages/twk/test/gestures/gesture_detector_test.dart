// Gestures in an app: taps, double taps and long presses on the fake
// clock, drags, nested detectors competing for a press, the order a tap
// that waited is told in, errors, and what the terminal is to report.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show MouseTracking, MouseTrackingBackend;
import 'package:twk_test/twk_test.dart';

const ms = Duration(milliseconds: 1);

/// The cell of [e], with its button when not the left one.
String at(PointerEvent e) =>
    '${e.x},${e.y}${e.button == 0 ? '' : ' b${e.button}'}';

/// A [GestureDetector] at [left], [top] of a [Stack], [width] × [height]
/// cells and opaque, with a callback for each of [gestures] (`tap`,
/// `double`, `long`, `drag`) that tells [log] the gesture as `name gesture
/// x,y`, a drag with the cells it moved.
Widget detector(
  List<String> log,
  String name, {
  required int left,
  required int top,
  required int width,
  required int height,
  Set<String> gestures = const {'tap'},
  Set<int> buttons = const {0},
  Widget? child,
}) {
  final tap = gestures.contains('tap');
  final double = gestures.contains('double');
  final long = gestures.contains('long');
  final drag = gestures.contains('drag');
  String moved(PointerEvent e, [CellOffset d = (dx: 0, dy: 0)]) =>
      '${at(e)} ${d.dx},${d.dy}';
  return Positioned(
    left: left,
    top: top,
    width: width,
    height: height,
    child: GestureDetector(
      onTapUp: tap ? (d) => log.add('$name tap ${at(d.event)}') : null,
      onDoubleTap: double ? () => log.add('$name double') : null,
      onLongPress: long ? () => log.add('$name long') : null,
      onLongPressEnd: long ? (e) => log.add('$name long end ${at(e)}') : null,
      onPanStart: drag ? (d) => log.add('$name start ${moved(d.event)}') : null,
      onPanUpdate: drag
          ? (d) => log.add('$name update ${moved(d.event, d.delta)}')
          : null,
      onPanEnd: drag ? (d) => log.add('$name end ${at(d.event)}') : null,
      buttons: buttons,
      behavior: HitTestBehavior.opaque,
      child: child,
    ),
  );
}

/// Shows what [builder] builds from its state, which changes it.
final class Host extends StatefulWidget {
  const Host(this.builder, {super.key});

  final Widget Function(HostState state) builder;

  @override
  State<Host> createState() => HostState();
}

final class HostState extends State<Host> {
  var step = 0;

  void change(int to) => setState(() => step = to);

  @override
  Widget build(BuildContext context) => widget.builder(this);
}

final host = GlobalKey<HostState>();

/// The mouse modes written so far, `?1002h` and the like, in order.
List<String> mouseModes(TwkTester t) => [
  for (final m in RegExp(r'\x1b\[\?(100[0236])([hl])').allMatches(
    latin1.decode([for (final f in t.terminal.frames) ...f]),
  ))
    '?${m[1]}${m[2]}',
];

void main() {
  testTwk('a press of a button it takes released over it is a tap, '
      'wherever the mouse went between; released elsewhere, or of another '
      'button, none', (t) async {
    final log = <String>[];
    Widget app(Set<int> buttons) => Stack(
      children: [
        detector(
          log,
          'd',
          left: 2,
          top: 1,
          width: 6,
          height: 2,
          buttons: buttons,
        ),
      ],
    );
    await t.pumpWidget(app(const {0}), size: (20, 5));
    await t.click(3, 2);
    await t.mouse(MouseKind.down, 2, 1);
    await t.mouse(MouseKind.drag, 15, 4);
    await t.mouse(MouseKind.up, 7, 2);
    await t.mouse(MouseKind.down, 3, 1);
    await t.mouse(MouseKind.up, 12, 1);
    await t.click(3, 1, button: 2);
    expect(log, ['d tap 1,1', 'd tap 5,1']);

    log.clear();
    await t.pumpWidget(app(const {0, 2}));
    await t.click(3, 1, button: 2);
    await t.click(4, 1);
    await t.click(4, 1, button: 1);
    expect(log, ['d tap 1,0 b2', 'd tap 2,0']);
  });

  testTwk('onTap, onDoubleTap and onLongPress are VoidCallbacks: a tap tells '
      'onTapDown at the press, then onTapUp with the release and its button, '
      'then onTap, with an onDoubleTap and a long press as well', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Stack(
        children: [
          Positioned(
            left: 2,
            top: 1,
            width: 6,
            height: 2,
            child: GestureDetector(
              buttons: const {0, 2},
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => log.add(
                'down ${d.localPosition.dx},${d.localPosition.dy} '
                '${d.globalPosition.dx},${d.globalPosition.dy}',
              ),
              onTapUp: (d) => log.add('up ${at(d.event)}'),
              onTap: () => log.add('tap'),
              onLongPress: () => log.add('long'),
            ),
          ),
        ],
      ),
      size: (20, 5),
    );
    await t.click(3, 2);
    expect(log, ['down 1,1 3,2', 'up 1,1', 'tap']);

    log.clear();
    await t.click(4, 1, button: 2);
    // the left button alone tells the press; the right one its release
    expect(log, ['up 2,0 b2', 'tap']);

    log.clear();
    await t.mouse(MouseKind.down, 3, 1);
    await t.pump(const Duration(milliseconds: 500));
    await t.mouse(MouseKind.up, 3, 1);
    expect(log, ['down 1,0 3,1', 'long']);
  });

  testTwk('with an onDoubleTap, a tap waits for the next press: a tap of '
      'the same button within the interval is a double tap, else the first '
      'is told when the interval is over', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Stack(
        children: [
          detector(
            log,
            'd',
            left: 2,
            top: 1,
            width: 6,
            height: 2,
            gestures: const {'tap', 'double'},
            buttons: const {0, 2},
          ),
        ],
      ),
      size: (20, 5),
    );
    await t.click(3, 2);
    expect(log, isEmpty);
    await t.pump(ms * 299);
    await t.click(4, 2);
    expect(log, ['d double']);

    log.clear();
    await t.click(3, 2);
    await t.pump(ms * 299);
    expect(log, isEmpty);
    await t.pump(ms);
    expect(log, ['d tap 1,1']);
    await t.click(4, 2);
    await t.pump(ms * 300);
    expect(log, ['d tap 1,1', 'd tap 2,1']);

    // the next press of another button, or released elsewhere: the first
    // tap is told before what follows
    log.clear();
    await t.click(3, 2);
    await t.click(3, 2, button: 2);
    await t.pump(ms * 300);
    await t.click(3, 2);
    await t.mouse(MouseKind.down, 3, 2);
    await t.mouse(MouseKind.up, 15, 4);
    expect(log, ['d tap 1,1', 'd tap 1,1 b2', 'd tap 1,1']);
  });

  testTwk('a tap tells nothing until the interval is over only with an '
      'onDoubleTap; with no onTap, a single tap tells nothing', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Stack(
        children: [
          detector(log, 'tap', left: 0, top: 0, width: 4, height: 1),
          detector(
            log,
            'double',
            left: 5,
            top: 0,
            width: 4,
            height: 1,
            gestures: const {'double'},
          ),
        ],
      ),
      size: (20, 5),
    );
    await t.click(1, 0);
    expect(log, ['tap tap 1,0']);
    await t.click(6, 0);
    await t.pump(ms * 300);
    await t.click(6, 0);
    await t.pump(ms * 100);
    await t.click(6, 0);
    expect(log, ['tap tap 1,0', 'double double']);
  });

  testTwk('a press held with the mouse over it is a long press, the end '
      'told at the release wherever it is, and no tap; released sooner, a '
      'tap', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Stack(
        children: [
          detector(
            log,
            'd',
            left: 2,
            top: 1,
            width: 6,
            height: 2,
            gestures: const {'tap', 'long'},
          ),
        ],
      ),
      size: (20, 5),
    );
    await t.mouse(MouseKind.down, 3, 2);
    await t.pump(ms * 499);
    expect(log, isEmpty);
    await t.pump(ms);
    expect(log, ['d long']);
    await t.mouse(MouseKind.drag, 15, 4);
    await t.mouse(MouseKind.up, 15, 4);
    expect(log, ['d long', 'd long end 13,3']);

    log.clear();
    await t.mouse(MouseKind.down, 3, 2);
    await t.pump(ms * 400);
    await t.mouse(MouseKind.up, 3, 2);
    await t.pump(ms * 400);
    expect(log, ['d tap 1,1']);

    // the mouse elsewhere when the time comes: none; moved within, where
    // it is
    log.clear();
    await t.mouse(MouseKind.down, 3, 2);
    await t.mouse(MouseKind.drag, 15, 4);
    await t.pump(ms * 500);
    await t.mouse(MouseKind.up, 15, 4);
    await t.mouse(MouseKind.down, 3, 2);
    await t.mouse(MouseKind.drag, 6, 1);
    await t.pump(ms * 500);
    await t.mouse(MouseKind.up, 6, 1);
    expect(log, ['d long', 'd long end 4,0']);

    // a release the terminal did not report: the next press ends the long
    // press where the mouse was last
    log.clear();
    await t.mouse(MouseKind.down, 3, 2);
    await t.mouse(MouseKind.drag, 4, 2);
    await t.pump(ms * 500);
    await t.mouse(MouseKind.down, 5, 2);
    await t.mouse(MouseKind.up, 5, 2);
    expect(log, ['d long', 'd long end 2,1', 'd tap 3,1']);
  });

  testTwk('a press is a drag once the mouse moves to another cell: the '
      'start where it was pressed, each cell it moves to with how far, the '
      'end at the release; no long press, no tap', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Stack(
        children: [
          detector(
            log,
            'd',
            left: 2,
            top: 1,
            width: 6,
            height: 2,
            gestures: const {'tap', 'long', 'drag'},
          ),
        ],
      ),
      size: (20, 5),
    );
    await t.mouse(MouseKind.down, 3, 2);
    await t.mouse(MouseKind.drag, 3, 2);
    await t.pump(ms * 100);
    await t.mouse(MouseKind.drag, 4, 2);
    await t.mouse(MouseKind.drag, 6, 1);
    await t.pump(ms * 600);
    await t.mouse(MouseKind.drag, 6, 1);
    await t.mouse(MouseKind.drag, 15, 4);
    await t.mouse(MouseKind.up, 15, 4);
    expect(log, [
      'd start 1,1 0,0',
      'd update 2,1 1,0',
      'd update 4,0 2,-1',
      'd update 13,3 9,3',
      'd end 13,3',
    ]);

    // a release the terminal did not report: the next press ends the drag
    // where the mouse was last
    log.clear();
    await t.mouse(MouseKind.down, 3, 2);
    await t.mouse(MouseKind.drag, 4, 2);
    await t.mouse(MouseKind.down, 5, 2);
    await t.mouse(MouseKind.up, 5, 2);
    expect(log, [
      'd start 1,1 0,0',
      'd update 2,1 1,0',
      'd end 2,1',
      'd tap 3,1',
    ]);
  });

  test('drag details are equal when their events and moves are, give the '
      'cell in the detector and on the screen, and describe themselves', () {
    // not constants, which are one object when equal
    final x = int.parse('4');
    final press = PointerEvent(
      MouseKind.drag,
      x,
      1,
      screenX: x + 10,
      screenY: 3,
    );
    final start = DragStartDetails(press);
    expect(start.localPosition, (dx: 4, dy: 1));
    expect(start.globalPosition, (dx: 14, dy: 3));
    expect(start, DragStartDetails(press));
    expect(start.hashCode, DragStartDetails(press).hashCode);
    expect('$start', 'DragStartDetails($press)');

    final update = DragUpdateDetails(press, delta: (dx: 1, dy: -1));
    expect(update.localPosition, (dx: 4, dy: 1));
    expect(update.globalPosition, (dx: 14, dy: 3));
    expect(update, DragUpdateDetails(press, delta: (dx: 1, dy: -1)));
    expect(
      update.hashCode,
      DragUpdateDetails(press, delta: (dx: 1, dy: -1)).hashCode,
    );
    expect(update, isNot(DragUpdateDetails(press, delta: (dx: 1, dy: 0))));
    expect(DragUpdateDetails(press).delta, (dx: 0, dy: 0));
    expect('$update', 'DragUpdateDetails($press, 1,-1)');

    final end = DragEndDetails(press);
    expect(end.localPosition, (dx: 4, dy: 1));
    expect(end.globalPosition, (dx: 14, dy: 3));
    expect(end, DragEndDetails(press));
    expect(end.hashCode, DragEndDetails(press).hashCode);
    expect('$end', 'DragEndDetails($press)');
  });

  testTwk('detectors one inside another: each gesture goes to the deepest '
      'that recognises it, the mouse over it for a tap or a long press, '
      'and a press is one gesture', (t) async {
    final log = <String>[];
    Widget nested(Set<String> outer, Set<String> inner) => Stack(
      children: [
        detector(
          log,
          'outer',
          left: 0,
          top: 0,
          width: 12,
          height: 4,
          gestures: outer,
          buttons: const {0, 2},
          child: Stack(
            children: [
              detector(
                log,
                'inner',
                left: 2,
                top: 1,
                width: 4,
                height: 2,
                gestures: inner,
              ),
            ],
          ),
        ),
      ],
    );
    await t.pumpWidget(
      nested(const {'tap', 'long', 'drag'}, const {'tap'}),
      size: (20, 5),
    );
    await t.click(3, 2);
    await t.click(3, 2, button: 2);
    await t.mouse(MouseKind.down, 3, 2);
    await t.mouse(MouseKind.drag, 4, 2);
    await t.mouse(MouseKind.up, 4, 2);
    await t.mouse(MouseKind.down, 3, 2);
    await t.pump(ms * 500);
    await t.mouse(MouseKind.up, 3, 2);
    expect(log, [
      'inner tap 1,1',
      'outer tap 3,2 b2',
      'outer start 3,2 0,0',
      'outer update 4,2 1,0',
      'outer end 4,2',
      'outer long',
      'outer long end 3,2',
    ]);

    log.clear();
    await t.pumpWidget(nested(const {'tap'}, const {'drag'}));
    await t.click(3, 2);
    await t.mouse(MouseKind.down, 3, 2);
    await t.mouse(MouseKind.drag, 4, 2);
    await t.mouse(MouseKind.up, 9, 3);
    // released off the inner one, over the outer one
    await t.mouse(MouseKind.down, 3, 2);
    await t.mouse(MouseKind.up, 9, 3);
    expect(log, [
      'outer tap 3,2',
      'inner start 1,1 0,0',
      'inner update 2,1 1,0',
      'inner end 7,2',
      'outer tap 9,3',
    ]);

    // held with the mouse off the inner one: the outer long press
    log.clear();
    await t.pumpWidget(nested(const {'tap', 'long'}, const {'tap', 'long'}));
    await t.mouse(MouseKind.down, 3, 2);
    await t.mouse(MouseKind.drag, 3, 3);
    await t.pump(ms * 500);
    await t.mouse(MouseKind.up, 3, 2);
    await t.mouse(MouseKind.down, 3, 2);
    await t.pump(ms * 500);
    await t.mouse(MouseKind.up, 3, 2);
    expect(log, [
      'outer long',
      'outer long end 3,2',
      'inner long',
      'inner long end 1,1',
    ]);
  });

  testTwk('a tap that waits for a second one is told before any gesture '
      'that follows, of its detector or another', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Stack(
        children: [
          detector(
            log,
            'a',
            left: 0,
            top: 0,
            width: 4,
            height: 2,
            gestures: const {'tap', 'double', 'long'},
          ),
          detector(
            log,
            'b',
            left: 10,
            top: 0,
            width: 4,
            height: 2,
            gestures: const {'tap', 'drag'},
          ),
        ],
      ),
      size: (20, 5),
    );
    await t.click(1, 1);
    await t.click(11, 1);
    await t.click(1, 1);
    await t.mouse(MouseKind.down, 11, 1);
    await t.mouse(MouseKind.drag, 12, 1);
    await t.mouse(MouseKind.up, 12, 1);
    await t.click(1, 1);
    await t.mouse(MouseKind.down, 2, 1);
    await t.pump(ms * 500);
    await t.mouse(MouseKind.up, 2, 1);
    expect(log, [
      'a tap 1,1',
      'b tap 1,1',
      'a tap 1,1',
      'b start 1,1 0,0',
      'b update 2,1 1,0',
      'b end 2,1',
      'a tap 1,1',
      'a long',
      'a long end 2,1',
    ]);
  });

  testTwk('a detector removed is told nothing more: not the tap that '
      'waits, not the rest of its drag', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Host(
        key: host,
        (s) => Stack(
          children: [
            if (s.step == 0)
              detector(
                log,
                'd',
                left: 0,
                top: 0,
                width: 4,
                height: 2,
                gestures: const {'tap', 'double', 'drag'},
              ),
          ],
        ),
      ),
      size: (20, 5),
    );
    await t.click(1, 1);
    host.currentState!.change(1);
    await t.pump();
    await t.pump(ms * 300);
    expect(log, isEmpty);

    host.currentState!.change(0);
    await t.pump();
    await t.mouse(MouseKind.down, 1, 1);
    await t.mouse(MouseKind.drag, 2, 1);
    host.currentState!.change(1);
    await t.pump();
    await t.mouse(MouseKind.drag, 3, 1);
    await t.mouse(MouseKind.up, 3, 1);
    expect(log, ['d start 1,1 0,0', 'd update 2,1 1,0']);
  });

  testTwk('what a gesture callback throws ends the app, in the detector '
      'whose callback it is, from a timer too', (t) async {
    await t.pumpWidget(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            key: const ValueKey('a'),
            onTap: () => throw StateError('tap'),
            onDoubleTap: () {},
            child: const Text('a'),
          ),
          GestureDetector(onTap: () {}, child: const Text('b')),
        ],
      ),
    );
    await t.click(0, 0);
    await expectLater(
      t.click(0, 1),
      throwsA(
        isA<WidgetError>()
            .having(
              (e) => e.path,
              'path',
              "Column → GestureDetector-[<'a'>] → HandOver → MouseRegion",
            )
            .having((e) => '${e.error}', 'error', 'Bad state: tap'),
      ),
    );
  });

  testTwk('what a long press throws ends the app, in its detector', (
    t,
  ) async {
    await t.pumpWidget(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () => throw StateError('long'),
            child: const Text('a'),
          ),
        ],
      ),
    );
    await t.mouse(MouseKind.down, 0, 0);
    await expectLater(
      t.pump(ms * 500),
      throwsA(
        isA<WidgetError>()
            .having(
              (e) => e.path,
              'path',
              'Column → GestureDetector → HandOver → MouseRegion',
            )
            .having((e) => '${e.error}', 'error', 'Bad state: long'),
      ),
    );
  });

  testTwk('the terminal reports presses and releases for taps, motion with '
      'a button held too for long presses and drags; nothing for a '
      'detector with no callback', (t) async {
    void none() {}
    await t.pumpWidget(
      Host(
        key: host,
        (s) => switch (s.step) {
          0 => const GestureDetector(child: Text('nothing')),
          1 => GestureDetector(onDoubleTap: none, child: const Text('tap')),
          2 => GestureDetector(
            onLongPressEnd: (_) => none(),
            child: const Text('long'),
          ),
          _ => GestureDetector(
            onPanEnd: (_) => none(),
            child: const Text('drag'),
          ),
        },
      ),
    );
    expect(mouseModes(t), isEmpty);
    host.currentState!.change(1);
    await t.pump();
    expect(mouseModes(t), ['?1000h', '?1006h']);
    host.currentState!.change(2);
    await t.pump();
    expect(mouseModes(t).skip(2), ['?1000l', '?1002h']);
    host.currentState!.change(3);
    await t.pump();
    expect(mouseModes(t), hasLength(4));
  });

  group('the pointer follows the press', () {
    Widget themed(PointerMode mode, Widget child) => Theme(
      data: const ThemeData.terminal(
        Brightness.dark,
      ).copyWith(pointerMode: mode),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 10, height: 1, child: child),
      ),
    );

    Future<PointerShape?> shapeOver(
      TwkTester t,
      Widget detector, {
      PointerMode mode = PointerMode.on,
      int x = 1,
    }) async {
      await t.pumpWidget(
        themed(mode, detector),
        size: (20, 3),
        pointerShapes: true,
      );
      await t.mouse(MouseKind.move, x, 0);
      await t.pump();
      return t.pointerShape;
    }

    const blank = Text('          ');

    testTwk('onTap and onTapDown show the hand, by the theme', (t) async {
      final tap = GestureDetector(onTap: () {}, child: blank);
      expect(await shapeOver(t, tap), PointerShape.pointer);
      final down = GestureDetector(onTapDown: (_) {}, child: blank);
      expect(await shapeOver(t, down), PointerShape.pointer);
    });

    testTwk('PointerMode.off shows none', (t) async {
      final tap = GestureDetector(onTap: () {}, child: blank);
      expect(
        await shapeOver(t, tap, mode: PointerMode.off),
        PointerShape.arrow,
      );
    });

    testTwk('a double tap alone, a drag and another button show none', (
      t,
    ) async {
      final double = GestureDetector(onDoubleTap: () {}, child: blank);
      expect(await shapeOver(t, double), PointerShape.arrow);
      final drag = GestureDetector(onPanUpdate: (_) {}, child: blank);
      expect(await shapeOver(t, drag), PointerShape.arrow);
      final right = GestureDetector(
        buttons: const {2},
        onTap: () {},
        child: blank,
      );
      expect(await shapeOver(t, right), PointerShape.arrow);
    });

    testTwk('cursor replaces the hand, whatever the theme, and is over all '
        'of a detector without a tap', (t) async {
      final grab = GestureDetector(
        cursor: PointerShape.grab,
        onTap: () {},
        child: blank,
      );
      expect(
        await shapeOver(t, grab, mode: PointerMode.off),
        PointerShape.grab,
      );
      final drag = GestureDetector(
        cursor: PointerShape.move,
        onPanUpdate: (_) {},
        child: blank,
      );
      expect(await shapeOver(t, drag), PointerShape.move);
    });

    testTwk('tapAt narrows the hand and the tap; a press outside goes to the '
        'detector around', (t) async {
      final log = <String>[];
      final row = GestureDetector(
        onTap: () => log.add('around'),
        cursor: PointerShape.arrow,
        child: GestureDetector(
          tapAt: (x, _) => x < 3,
          onTapUp: (tap) => log.add('tap ${tap.localPosition.dx}'),
          child: blank,
        ),
      );
      expect(await shapeOver(t, row), PointerShape.pointer);
      await t.mouse(MouseKind.move, 6, 0);
      await t.pump();
      expect(t.pointerShape, PointerShape.arrow);
      await t.click(1, 0);
      await t.click(6, 0);
      await t.pump();
      expect(log, ['tap 1', 'around']);
    });

    testTwk('onTapDown is not told of a left press while another button is '
        'held, which no tap comes of', (t) async {
      final log = <String>[];
      await t.pumpWidget(
        GestureDetector(
          buttons: const {0, 2},
          onTapDown: (e) => log.add('down'),
          child: const Text('press'),
        ),
        size: (20, 2),
      );
      await t.mouse(MouseKind.down, 1, 0, button: 2);
      await t.mouse(MouseKind.down, 1, 0);
      await t.mouse(MouseKind.up, 1, 0);
      await t.mouse(MouseKind.up, 1, 0, button: 2);
      expect(log, isEmpty);
    });

    testTwk('onTapDown is told at the press, apart from the taps inside and '
        'around it; outside tapAt it is not told', (t) async {
      final log = <String>[];
      await t.pumpWidget(
        themed(
          PointerMode.auto,
          GestureDetector(
            onTap: () => log.add('around'),
            child: GestureDetector(
              tapAt: (x, _) => x < 3,
              onTapDown: (tap) => log.add('down ${tap.localPosition.dx}'),
              child: blank,
            ),
          ),
        ),
        size: (20, 3),
      );
      await t.mouse(MouseKind.down, 1, 0);
      expect(log, ['down 1']);
      await t.mouse(MouseKind.up, 1, 0);
      await t.pump();
      expect(log, ['down 1', 'around']);
      log.clear();
      await t.mouse(MouseKind.down, 6, 0);
      expect(log, isEmpty);
      await t.mouse(MouseKind.up, 6, 0);
      await t.pump();
      expect(log, ['around']);
    });

    testTwk('a tap is pressed and released on cells of tapAt: a release off '
        'them tells no onTap', (t) async {
      final log = <String>[];
      await t.pumpWidget(
        themed(
          PointerMode.auto,
          GestureDetector(
            tapAt: (x, _) => x < 3,
            onTapUp: (tap) => log.add('tap ${tap.localPosition.dx}'),
            child: blank,
          ),
        ),
        size: (20, 3),
      );
      await t.mouse(MouseKind.down, 1, 0);
      await t.mouse(MouseKind.up, 6, 0);
      await t.pump();
      expect(log, isEmpty);
      await t.mouse(MouseKind.down, 1, 0);
      await t.mouse(MouseKind.up, 2, 0);
      await t.pump();
      expect(log, ['tap 2']);
    });

    testTwk('an arrow asks for no motion, another shape does', (t) async {
      MouseTracking tracking() =>
          (t.binding.twkApp.terminal as MouseTrackingBackend).mouseTracking;
      await t.pumpWidget(
        themed(
          PointerMode.auto,
          GestureDetector(
            cursor: PointerShape.arrow,
            onTap: () {},
            child: blank,
          ),
        ),
        size: (20, 3),
        pointerShapes: true,
      );
      expect(tracking(), MouseTracking.buttons);
      await t.pumpWidget(
        themed(
          PointerMode.auto,
          GestureDetector(
            cursor: PointerShape.grab,
            onTap: () {},
            child: blank,
          ),
        ),
        size: (20, 3),
        pointerShapes: true,
      );
      expect(tracking(), MouseTracking.motion);
    });
  });
}
