// The mouse in an app: Listeners and MouseRegions found by hit test, the
// order they are told in, a press capturing what follows it, the wheel to
// the nearest Listener that scrolls, enter and exit across overlapping
// regions and frames, and the terminal reporting only what is used.
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show MouseTracking, MouseTrackingBackend;
import 'package:twk_test/twk_test.dart';

import '../framework/harness.dart' show Tree;

/// What [log] is told, as `name kind x,y` with the cell in the coordinates
/// of the widget.
PointerEventListener record(List<String> log, String name) =>
    (e) => log.add('$name ${e.kind.name} ${e.x},${e.y}');

/// What [log] is told, as `name what x,y`; see [record].
PointerEventListener recordAs(List<String> log, String name, String what) =>
    (e) => log.add('$name $what ${e.x},${e.y}');

/// A [Listener] at [left], [top] of a [Stack], [width] × [height] cells,
/// telling [log] each event as [name]; see [record].
Widget listener(
  List<String> log,
  String name, {
  required int left,
  required int top,
  required int width,
  required int height,
  HitTestBehavior behavior = HitTestBehavior.opaque,
  bool scroll = true,
  Axis? scrollAxis,
  Widget? child,
}) {
  final r = record(log, name);
  return Positioned(
    left: left,
    top: top,
    width: width,
    height: height,
    child: Listener(
      onDown: r,
      onUp: r,
      onMove: r,
      onDrag: r,
      onScroll: scroll ? r : null,
      scrollAxis: scrollAxis,
      behavior: behavior,
      child: child,
    ),
  );
}

/// A [MouseRegion] at [left], [top] of a [Stack], [width] × [height]
/// cells, telling [log] each enter, exit and hover as [name]; see
/// [recordAs]. Its [behavior] is the default unless given.
Widget region(
  List<String> log,
  String name, {
  required int left,
  required int top,
  required int width,
  required int height,
  HitTestBehavior? behavior,
  Widget? child,
}) {
  final enter = recordAs(log, name, 'enter');
  final exit = recordAs(log, name, 'exit');
  final hover = recordAs(log, name, 'hover');
  return Positioned(
    left: left,
    top: top,
    width: width,
    height: height,
    child: behavior == null
        ? MouseRegion(
            onEnter: enter,
            onExit: exit,
            onHover: hover,
            child: child,
          )
        : MouseRegion(
            onEnter: enter,
            onExit: exit,
            onHover: hover,
            behavior: behavior,
            child: child,
          ),
  );
}

/// Gives the [InputListener]s' mouse events to [log] as `input kind x,y`,
/// and takes them.
Widget inputs(List<String> log, Widget child) => InputListener(
  onEvent: (e) {
    if (e is MouseEvent) {
      log.add('input ${e.kind.name} ${e.x},${e.y}');
      return true;
    }
    return false;
  },
  child: child,
);

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
  for (final m in RegExp(r'\x1b\[\?(100[0236])([hl])').allMatches(t.written()))
    '?${m[1]}${m[2]}',
];

void main() {
  testTwk('a press, release, move or drag goes to each Listener hit there '
      'with a callback for it, the deepest first, the cell in its own '
      'coordinates; one that none takes goes to the InputListeners', (
    t,
  ) async {
    final log = <String>[];
    await t.pumpWidget(
      inputs(
        log,
        Stack(
          children: [
            listener(
              log,
              'outer',
              left: 2,
              top: 1,
              width: 10,
              height: 3,
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Listener(
                  onDown: record(log, 'inner'),
                  onUp: record(log, 'inner'),
                  child: const Text('inner'),
                ),
              ),
            ),
          ],
        ),
      ),
      size: (20, 5),
    );
    await t.click(7, 2);
    expect(log, [
      'inner down 1,1',
      'outer down 5,1',
      'inner up 1,1',
      'outer up 5,1',
    ]);

    log.clear();
    await t.mouse(MouseKind.move, 7, 2);
    await t.mouse(MouseKind.move, 3, 1);
    await t.mouse(MouseKind.move, 15, 1);
    await t.click(0, 0);
    expect(log, [
      'outer move 5,1',
      'outer move 1,0',
      'input move 15,1',
      'input down 0,0',
      'input up 0,0',
    ]);

    final events = <PointerEvent>[];
    await t.pumpWidget(
      Listener(
        onDown: events.add,
        behavior: HitTestBehavior.opaque,
        child: const SizedBox.expand(),
      ),
    );
    await t.mouse(MouseKind.down, 7, 2, button: 2, modifiers: Mod.ctrl);
    expect(events, [
      const PointerEvent(
        MouseKind.down,
        7,
        2,
        screenX: 7,
        screenY: 2,
        button: 2,
        modifiers: Mod.ctrl,
      ),
    ]);
    expect(events.single.ctrl, isTrue);
  });

  testTwk('after a press, drags and releases go to the Listeners it was hit '
      'in, wherever the mouse goes, until the last button is released', (
    t,
  ) async {
    final log = <String>[];
    await t.pumpWidget(
      inputs(
        log,
        Stack(
          children: [
            listener(log, 'a', left: 0, top: 0, width: 5, height: 1),
            listener(log, 'b', left: 5, top: 0, width: 5, height: 1),
          ],
        ),
      ),
      size: (20, 5),
    );
    await t.mouse(MouseKind.down, 1, 0);
    await t.mouse(MouseKind.drag, 7, 0);
    await t.mouse(MouseKind.drag, 15, 3);
    await t.mouse(MouseKind.up, 7, 0);
    await t.mouse(MouseKind.drag, 7, 0);
    // pressed where no Listener is: what follows goes to none
    await t.mouse(MouseKind.down, 15, 3);
    await t.mouse(MouseKind.drag, 1, 0);
    await t.mouse(MouseKind.up, 1, 0);
    expect(log, [
      'a down 1,0',
      'a drag 7,0',
      'a drag 15,3',
      'a up 7,0',
      'b drag 2,0',
      'input down 15,3',
      'input drag 1,0',
      'input up 1,0',
    ]);

    log.clear();
    await t.mouse(MouseKind.down, 1, 0);
    await t.mouse(MouseKind.down, 6, 0, button: 2);
    await t.mouse(MouseKind.up, 6, 0, button: 2);
    await t.mouse(MouseKind.drag, 6, 0);
    await t.mouse(MouseKind.up, 6, 0);
    await t.mouse(MouseKind.up, 6, 0);
    expect(log, [
      'a down 1,0',
      'a down 6,0',
      'a up 6,0',
      'a drag 6,0',
      'a up 6,0',
      'b up 1,0',
    ]);

    // a release the terminal did not report: the next press, or motion with
    // no button held, starts afresh
    log.clear();
    await t.mouse(MouseKind.down, 1, 0);
    await t.mouse(MouseKind.down, 6, 0);
    await t.mouse(MouseKind.up, 6, 0);
    await t.mouse(MouseKind.down, 1, 0);
    await t.mouse(MouseKind.move, 6, 0);
    await t.mouse(MouseKind.drag, 6, 0);
    expect(log, [
      'a down 1,0',
      'b down 1,0',
      'b up 1,0',
      'a down 1,0',
      'b move 1,0',
      'b drag 1,0',
    ]);
  });

  testTwk('the wheel goes to the deepest Listener hit there that scrolls, '
      'and to no other; with none, to the InputListeners', (t) async {
    final log = <String>[];
    final scrolls = <(int, int)>[];
    await t.pumpWidget(
      inputs(
        log,
        Stack(
          children: [
            listener(
              log,
              'outer',
              left: 0,
              top: 0,
              width: 10,
              height: 4,
              child: Stack(
                children: [
                  listener(log, 'inner', left: 0, top: 0, width: 4, height: 2),
                  listener(
                    log,
                    'still',
                    left: 5,
                    top: 0,
                    width: 4,
                    height: 2,
                    scroll: false,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 12,
              top: 0,
              width: 4,
              height: 4,
              child: Listener(
                onScroll: (e) => scrolls.add((e.scrollX, e.scrollY)),
                behavior: HitTestBehavior.opaque,
              ),
            ),
          ],
        ),
      ),
      size: (20, 5),
    );
    await t.mouse(MouseKind.wheelDown, 1, 1);
    await t.mouse(MouseKind.wheelUp, 6, 1);
    await t.mouse(MouseKind.wheelUp, 2, 3);
    await t.mouse(MouseKind.wheelDown, 18, 3);
    expect(log, [
      'inner wheelDown 1,1',
      'outer wheelUp 6,1',
      'outer wheelUp 2,3',
      'input wheelDown 18,3',
    ]);
    for (final kind in [
      MouseKind.wheelUp,
      MouseKind.wheelDown,
      MouseKind.wheelLeft,
      MouseKind.wheelRight,
    ]) {
      await t.mouse(kind, 13, 1);
    }
    expect(scrolls, [(0, -1), (0, 1), (-1, 0), (1, 0)]);
  });

  testTwk('a wheel along the axis the deepest Listener does not scroll on '
      'goes on to the nearest above that takes it, and back to the deepest '
      'where none does; one of no axis takes both', (t) async {
    final log = <String>[];
    // a view down around a view across; beside it a view across around
    // one of no axis around a view down; and a view across alone
    Widget nested(String name, Axis axis, {Widget? child}) => Stack(
      children: [
        listener(
          log,
          name,
          left: 0,
          top: 0,
          width: 4,
          height: 4,
          scrollAxis: axis,
          child: child,
        ),
      ],
    );
    await t.pumpWidget(
      inputs(
        log,
        Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: 4,
              height: 4,
              child: nested(
                'down',
                Axis.vertical,
                child: nested('across', Axis.horizontal),
              ),
            ),
            Positioned(
              left: 5,
              top: 0,
              width: 4,
              height: 4,
              child: nested(
                'across2',
                Axis.horizontal,
                child: Stack(
                  children: [
                    listener(
                      log,
                      'any',
                      left: 0,
                      top: 0,
                      width: 4,
                      height: 4,
                      child: nested('inner2', Axis.vertical),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 10,
              top: 0,
              width: 4,
              height: 4,
              child: nested('alone', Axis.horizontal),
            ),
          ],
        ),
      ),
      size: (20, 5),
    );
    for (final x in [1, 6, 11]) {
      await t.mouse(MouseKind.wheelDown, x, 1);
      await t.mouse(MouseKind.wheelRight, x, 1);
    }
    expect(log, [
      'down wheelDown 1,1',
      'across wheelRight 1,1',
      'inner2 wheelDown 1,1',
      'any wheelRight 1,1',
      // a mouse without a wheel across: the wheel down to a view across
      'alone wheelDown 1,1',
      'alone wheelRight 1,1',
    ]);
  });

  testTwk('where a Listener is hit is up to its behaviour: by default where '
      'its child is; opaque, anywhere in it; translucent, what it covers is '
      'hit too where its child is not', (t) async {
    final log = <String>[];
    Widget app(HitTestBehavior? behavior) => Stack(
      children: [
        listener(log, 'under', left: 0, top: 0, width: 10, height: 5),
        Positioned(
          left: 0,
          top: 0,
          width: 5,
          height: 3,
          child: behavior == null
              ? Listener(
                  onDown: record(log, 'over'),
                  child: const Box(border: Border.all()),
                )
              : Listener(
                  onDown: record(log, 'over'),
                  behavior: behavior,
                  child: const Box(border: Border.all()),
                ),
        ),
      ],
    );
    await t.pumpWidget(app(null), size: (20, 5));
    await t.mouse(MouseKind.down, 2, 1);
    await t.mouse(MouseKind.down, 0, 0);
    await t.pumpWidget(app(HitTestBehavior.opaque));
    await t.mouse(MouseKind.down, 2, 1);
    await t.pumpWidget(app(HitTestBehavior.translucent));
    await t.mouse(MouseKind.down, 2, 1);
    await t.mouse(MouseKind.down, 0, 0);
    expect(log, [
      'under down 2,1',
      'over down 0,0',
      'over down 2,1',
      'over down 2,1',
      'under down 2,1',
      'over down 0,0',
    ]);
  });

  testTwk('the regions the mouse leaves are told, then those it comes into, '
      'then those it moves in: an opaque one hides what it covers, a '
      'translucent one does not', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Stack(
        children: [
          region(log, 'back', left: 0, top: 0, width: 8, height: 3),
          region(log, 'front', left: 4, top: 1, width: 8, height: 3),
          region(
            log,
            'glass',
            left: 10,
            top: 0,
            width: 4,
            height: 4,
            behavior: HitTestBehavior.translucent,
          ),
        ],
      ),
      size: (20, 5),
    );
    await t.mouse(MouseKind.move, 1, 0);
    await t.mouse(MouseKind.move, 5, 1);
    await t.mouse(MouseKind.move, 10, 2);
    await t.mouse(MouseKind.move, 13, 3);
    await t.mouse(MouseKind.move, 15, 4);
    expect(log, [
      'back enter 1,0',
      'back hover 1,0',
      'back exit 5,1',
      'front enter 1,0',
      'front hover 1,0',
      'glass enter 0,2',
      'glass hover 0,2',
      'front hover 6,1',
      'front exit 9,2',
      'glass hover 3,3',
      'glass exit 5,4',
    ]);

    // a press, a drag, the wheel move the mouse too; only a move hovers
    log.clear();
    await t.mouse(MouseKind.down, 1, 0);
    await t.mouse(MouseKind.drag, 5, 1);
    await t.mouse(MouseKind.up, 5, 1);
    await t.mouse(MouseKind.wheelDown, 15, 4);
    expect(log, [
      'back enter 1,0',
      'back exit 5,1',
      'front enter 1,0',
      'front exit 11,3',
    ]);
  });

  testTwk('a region inside another: coming into the inner one enters both, '
      'the outer first; leaving it leaves the inner one first', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Stack(
        children: [
          region(
            log,
            'outer',
            left: 0,
            top: 0,
            width: 10,
            height: 4,
            child: Stack(
              children: [
                region(log, 'inner', left: 2, top: 1, width: 3, height: 2),
              ],
            ),
          ),
        ],
      ),
      size: (20, 5),
    );
    await t.mouse(MouseKind.move, 3, 2);
    await t.mouse(MouseKind.move, 8, 2);
    await t.mouse(MouseKind.move, 3, 1);
    await t.mouse(MouseKind.move, 15, 1);
    expect(log, [
      'outer enter 3,2',
      'inner enter 1,1',
      'inner hover 1,1',
      'outer hover 3,2',
      'inner exit 6,1',
      'outer hover 8,2',
      'inner enter 1,0',
      'inner hover 1,0',
      'outer hover 3,1',
      'inner exit 13,0',
      'outer exit 15,1',
    ]);
  });

  testTwk('a frame that moves a region away from the mouse or under it '
      'tells it so, with no hover', (t) async {
    final log = <String>[];
    final exits = <MouseKind>[];
    await t.pumpWidget(
      Host(
        key: host,
        (s) => Stack(
          children: [
            Positioned(
              left: s.step == 0 ? 0 : 10,
              top: 0,
              width: 4,
              height: 2,
              child: MouseRegion(
                onEnter: recordAs(log, 'r', 'enter'),
                onExit: (e) {
                  exits.add(e.kind);
                  recordAs(log, 'r', 'exit')(e);
                },
                onHover: recordAs(log, 'r', 'hover'),
              ),
            ),
          ],
        ),
      ),
      size: (20, 5),
    );
    await t.mouse(MouseKind.move, 1, 0);
    host.currentState!.change(1);
    await t.pump();
    host.currentState!.change(0);
    await t.pump();
    await t.mouse(MouseKind.down, 2, 1);
    host.currentState!.change(1);
    await t.pump();
    expect(log, [
      'r enter 1,0',
      'r hover 1,0',
      'r exit -9,0',
      'r enter 1,0',
      'r exit -8,1',
    ]);
    expect(exits, [MouseKind.move, MouseKind.drag]);
  });

  testTwk('a frame that moves a region away while the right button is held '
      'tells the exit as a drag of that button', (t) async {
    final exits = <PointerEvent>[];
    await t.pumpWidget(
      Host(
        key: host,
        (s) => Stack(
          children: [
            Positioned(
              left: s.step == 0 ? 0 : 10,
              top: 0,
              width: 4,
              height: 2,
              child: MouseRegion(onExit: exits.add),
            ),
          ],
        ),
      ),
      size: (20, 5),
    );
    await t.mouse(MouseKind.down, 1, 0, button: 2);
    host.currentState!.change(1);
    await t.pump();
    expect(exits.single.kind, MouseKind.drag);
    expect(exits.single.button, 2);
  });

  test('a pointer event says which modifiers are held, is equal to another '
      'that says the same, and describes itself', () {
    // not constants, which are one object when equal
    final x = int.parse('3');
    PointerEvent at(int modifiers) => PointerEvent(
      MouseKind.down,
      x,
      1,
      screenX: 5,
      screenY: 2,
      button: 1,
      modifiers: modifiers,
    );
    final e = at(Mod.alt | Mod.shift);
    expect((e.alt, e.shift, e.ctrl), (true, true, false));
    expect(e, at(Mod.alt | Mod.shift));
    expect(e.hashCode, at(Mod.alt | Mod.shift).hashCode);
    expect(e, isNot(at(Mod.alt)));
    expect('$e', 'Pointer(down 3,1 at 5,2 b1 m${Mod.alt | Mod.shift})');
  });

  testTwk('the terminal reports the mouse while a Listener or a MouseRegion '
      'is mounted, as much as its callbacks need, from the frame that mounts '
      'it to the one that unmounts it', (t) async {
    void none(PointerEvent e) {}
    await t.pumpWidget(
      Host(
        key: host,
        (s) => switch (s.step) {
          0 => const Listener(child: Text('nothing')),
          1 => Listener(onDown: none, onScroll: none, child: const Text('a')),
          2 => Listener(onDrag: none, child: const Text('b')),
          3 => MouseRegion(onExit: none, child: const Text('c')),
          4 => Column(
            children: [
              Listener(onDown: none, child: const Text('d')),
              MouseRegion(onHover: none, child: const Text('e')),
            ],
          ),
          _ => const Text('none'),
        },
      ),
    );
    expect(mouseModes(t), isEmpty, reason: 'no callback, no reports');
    final frames = t.terminal.frames;
    // what each step switched, in a write of its own: before the frame
    // that mounts, after the one that unmounts
    final steps = <String>[];
    for (var step = 1; step <= 5; step++) {
      final before = frames.length;
      host.currentState!.change(step);
      await t.pump();
      final wrote = [for (final f in frames.skip(before)) latin1.decode(f)];
      steps.add(
        switch (step) {
          5 => wrote.last,
          4 => wrote.firstWhere(
            (f) => f.startsWith('\x1b[?100'),
            orElse: () => '',
          ),
          _ => wrote.first,
        },
      );
    }
    expect(steps, [
      '\x1b[?1000h\x1b[?1006h',
      '\x1b[?1000l\x1b[?1002h',
      '\x1b[?1002l\x1b[?1003h',
      '',
      '\x1b[?1003l\x1b[?1006l',
    ]);
    expect(t.lines.first, 'none');
    final terminal = t.binding.twkApp.terminal as MouseTrackingBackend;
    expect(terminal.mouseTracking, MouseTracking.off);
  });

  testTwk("the inline mode keeps the mouse the terminal's, listeners or "
      'not', (t) async {
    await t.pumpWidget(
      MouseRegion(onHover: (_) {}, child: const Text('inline')),
      mode: ScreenMode.inline,
    );
    expect(mouseModes(t), isEmpty);
    expect(
      (t.binding.twkApp.terminal as MouseTrackingBackend).mouseTracking,
      MouseTracking.off,
    );
  });

  testTwk('an error a callback throws ends the app, in the widget whose '
      'callback it is', (t) async {
    await t.pumpWidget(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Listener(
            onDown: (_) => throw StateError('down'),
            child: const Text('click'),
          ),
        ],
      ),
    );
    await expectLater(
      t.click(0, 0),
      throwsA(
        isA<WidgetError>()
            .having((e) => e.path, 'path', 'Column → Listener')
            .having((e) => '${e.error}', 'error', 'Bad state: down'),
      ),
    );
  });

  testTwk('an error an enter throws ends the app, in the region', (t) async {
    await t.pumpWidget(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MouseRegion(
            key: const ValueKey('r'),
            onEnter: (_) => throw StateError('enter'),
            child: const Text('enter'),
          ),
        ],
      ),
    );
    await expectLater(
      t.mouse(MouseKind.move, 0, 0),
      throwsA(
        isA<WidgetError>().having(
          (e) => e.path,
          'path',
          "Column → MouseRegion-[<'r'>]",
        ),
      ),
    );
  });

  test('a widget whose build threw outside an app, which shows nothing, is '
      'not hit', () {
    final tree = Tree();
    runZonedGuarded(() => tree.pump(const _Throws()), (_, _) {});
    final nothing = tree.host.child!..layout(const BoxConstraints.tight(3, 1));
    expect(nothing.hitTest(HitTestResult(), 1, 0), isFalse);
  });
}

final class _Throws extends StatelessWidget {
  const _Throws();

  @override
  Widget build(BuildContext context) => throw StateError('boom');
}
