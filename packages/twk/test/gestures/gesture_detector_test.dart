// Gestures in an app: taps, double taps and long presses on the fake
// clock, drags, nested detectors competing for a press, the order a tap
// that waited is told in, errors, and what the terminal is to report.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
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
  String moved(DragDetails d) => '${at(d.event)} ${d.dx},${d.dy}';
  return Positioned(
    left: left,
    top: top,
    width: width,
    height: height,
    child: GestureDetector(
      onTap: tap ? (e) => log.add('$name tap ${at(e)}') : null,
      onDoubleTap: double ? (e) => log.add('$name double ${at(e)}') : null,
      onLongPress: long ? (e) => log.add('$name long ${at(e)}') : null,
      onLongPressEnd: long ? (e) => log.add('$name long end ${at(e)}') : null,
      onDragStart: drag ? (d) => log.add('$name start ${moved(d)}') : null,
      onDragUpdate: drag ? (d) => log.add('$name update ${moved(d)}') : null,
      onDragEnd: drag ? (d) => log.add('$name end ${moved(d)}') : null,
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
    expect(log, ['d double 2,1']);

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
    expect(log, ['tap tap 1,0', 'double double 1,0']);
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
    expect(log, ['d long 1,1']);
    await t.mouse(MouseKind.drag, 15, 4);
    await t.mouse(MouseKind.up, 15, 4);
    expect(log, ['d long 1,1', 'd long end 13,3']);

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
    expect(log, ['d long 4,0', 'd long end 4,0']);

    // a release the terminal did not report: the next press ends the long
    // press where the mouse was last
    log.clear();
    await t.mouse(MouseKind.down, 3, 2);
    await t.mouse(MouseKind.drag, 4, 2);
    await t.pump(ms * 500);
    await t.mouse(MouseKind.down, 5, 2);
    await t.mouse(MouseKind.up, 5, 2);
    expect(log, ['d long 2,1', 'd long end 2,1', 'd tap 3,1']);
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
      'd end 13,3 0,0',
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
      'd end 2,1 0,0',
      'd tap 3,1',
    ]);
  });

  test('drag details are equal when their events and moves are, and '
      'describe themselves', () {
    // not constants, which are one object when equal
    final x = int.parse('4');
    final press = PointerEvent(MouseKind.drag, x, 1, screenX: x, screenY: 1);
    final details = DragDetails(press, dx: 1, dy: -1);
    expect((details.x, details.y), (4, 1));
    expect(details, DragDetails(press, dx: 1, dy: -1));
    expect(details.hashCode, DragDetails(press, dx: 1, dy: -1).hashCode);
    expect(details, isNot(DragDetails(press, dx: 1)));
    expect('$details', 'Drag($press, 1,-1)');
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
      'outer end 4,2 0,0',
      'outer long 3,2',
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
      'inner end 7,2 5,1',
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
      'outer long 3,3',
      'outer long end 3,2',
      'inner long 1,1',
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
      'b end 2,1 0,0',
      'a tap 1,1',
      'a long 2,1',
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
            onTap: (_) => throw StateError('tap'),
            onDoubleTap: (_) {},
            child: const Text('a'),
          ),
          GestureDetector(onTap: (_) {}, child: const Text('b')),
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
              "Column → GestureDetector-[<'a'>] → Listener",
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
            onLongPress: (_) => throw StateError('long'),
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
              'Column → GestureDetector → Listener',
            )
            .having((e) => '${e.error}', 'error', 'Bad state: long'),
      ),
    );
  });

  testTwk('the terminal reports presses and releases for taps, motion with '
      'a button held too for long presses and drags; nothing for a '
      'detector with no callback', (t) async {
    void none(Object _) {}
    await t.pumpWidget(
      Host(
        key: host,
        (s) => switch (s.step) {
          0 => const GestureDetector(child: Text('nothing')),
          1 => GestureDetector(onDoubleTap: none, child: const Text('tap')),
          2 => GestureDetector(onLongPressEnd: none, child: const Text('long')),
          _ => GestureDetector(onDragEnd: none, child: const Text('drag')),
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
}
