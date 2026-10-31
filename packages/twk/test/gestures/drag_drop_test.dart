// Drag and drop in an app: the data carried to the target under the mouse,
// highlighted while it is, the feedback following the mouse in the
// overlay; targets that reject the data by type or by onWillAccept, nested
// targets, a list reordered by drag, the press shared with gesture
// detectors, what the terminal is to report, lost releases, a draggable
// leaving the tree, errors.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import 'shape_run.dart';

/// The cell of [e].
String at(PointerEvent e) => '${e.x},${e.y}';

/// A [DragTarget] of [T] at [left], [top] of a [Stack], 8 × 2 cells,
/// showing [name] on its first row, then `:` and the data over it it would
/// accept, or `!` with data it would not; it tells [log] what it is asked
/// and told as `name what data x,y`, moves only with [moves], and accepts
/// what [accepts] says, all data of its type without it.
Widget target<T extends Object>(
  List<String> log,
  String name, {
  required int left,
  required int top,
  bool Function(T data)? accepts,
  bool moves = false,
}) => Positioned(
  left: left,
  top: top,
  width: 8,
  height: 2,
  child: DragTarget<T>(
    onWillAccept: (d) {
      log.add('$name will ${d.data} ${at(d.event)}');
      return accepts?.call(d.data) ?? true;
    },
    onAccept: (d) => log.add('$name accept ${d.data} ${at(d.event)}'),
    onLeave: (data) => log.add('$name leave $data'),
    onMove: moves
        ? (d) => log.add('$name move ${d.data} ${at(d.event)}')
        : null,
    builder: (context, candidate, rejected) => Text(
      candidate != null
          ? '$name:$candidate'
          : rejected != null
          ? '$name!'
          : name,
    ),
  ),
);

/// 'apple' at the top left of a [Stack], dragging 'apple' with '[apple]'
/// following the mouse and '.....' in its place; it tells [log] when the
/// drag starts, completes and is canceled.
Widget apple(List<String> log) => Positioned(
  left: 0,
  top: 0,
  child: Draggable<String>(
    data: 'apple',
    feedback: const Text('[apple]'),
    childWhenDragging: const Text('.....'),
    onDragStarted: () => log.add('started'),
    onDragCompleted: () => log.add('completed'),
    onDragCanceled: () => log.add('canceled'),
    child: const Text('apple'),
  ),
);

/// [children] in a [Stack] in an [Overlay].
Widget stage(List<Widget> children) =>
    Overlay(child: Stack(children: children));

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

/// A list of fruits that a drag reorders: a fruit dropped on another takes
/// its place, a row marked `▸` while a fruit is over it.
final class Fruits extends StatefulWidget {
  const Fruits({super.key});

  @override
  State<Fruits> createState() => _FruitsState();
}

final class _FruitsState extends State<Fruits> {
  final fruits = ['apple', 'banana', 'cherry', 'date'];

  @override
  Widget build(BuildContext context) => Overlay(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, fruit) in fruits.indexed)
          DragTarget<int>(
            key: ValueKey(fruit),
            onWillAccept: (d) => d.data != i,
            onAccept: (d) =>
                setState(() => fruits.insert(i, fruits.removeAt(d.data))),
            builder: (context, candidate, rejected) => Draggable<int>(
              data: i,
              feedback: Text('» $fruit «'),
              child: Text('${candidate != null ? '▸' : ' '} $fruit'),
            ),
          ),
      ],
    ),
  );
}

/// The mouse modes written so far, `?1002h` and the like, in order.
List<String> mouseModes(TwkTester t) => [
  for (final m in RegExp(r'\x1b\[\?(100[0236])([hl])').allMatches(
    latin1.decode([for (final f in t.terminal.frames) ...f]),
  ))
    '?${m[1]}${m[2]}',
];

void main() {
  test('the details of a drag over a target are equal when their data and '
      'events are, and describe themselves', () {
    // not constants, which are one object when equal
    final x = int.parse('2');
    final drag = PointerEvent(MouseKind.drag, x, 0, screenX: x, screenY: 0);
    final details = DragTargetDetails('a', drag);
    expect(details, DragTargetDetails('a', drag));
    expect(details.hashCode, DragTargetDetails('a', drag).hashCode);
    expect(details, isNot(DragTargetDetails('b', drag)));
    expect('$details', 'DragTargetDetails(a, $drag)');
  });

  testTwk('a drag carries the data to the target the mouse is over, '
      'highlighted while it is, the feedback following the mouse in the '
      'overlay, the child replaced', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      stage([
        apple(log),
        target<String>(log, 'A', left: 10, top: 2, moves: true),
        target<String>(log, 'B', left: 20, top: 2, moves: true),
      ]),
      size: (30, 5),
    );
    await t.mouse(MouseKind.down, 1, 0);
    await t.mouse(MouseKind.drag, 12, 3);
    expect(log, ['started', 'A will apple 2,1', 'A move apple 2,1']);
    await t.pump();
    expect(
      t,
      matchesScreen('''
.....

          A:apple   B
           [apple]'''),
    );

    // over the feedback, which is not hit
    log.clear();
    await t.mouse(MouseKind.drag, 13, 3);
    expect(log, ['A move apple 3,1']);

    log.clear();
    await t.mouse(MouseKind.drag, 22, 3);
    expect(log, ['B will apple 2,1', 'A leave apple', 'B move apple 2,1']);
    await t.pump();
    expect(
      t,
      matchesScreen('''
.....

          A         B:apple
                     [apple]'''),
    );

    log.clear();
    await t.mouse(MouseKind.up, 23, 3);
    expect(log, ['B accept apple 3,1', 'completed']);
    await t.pump();
    expect(t, matchesScreen('apple\n\n          A         B'));
  });

  testTwk('a target rejects data of another type without asking, and what '
      'its onWillAccept says no to; dropped there, or on no target, the '
      'drag is canceled', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      stage([
        apple(log),
        target<int>(log, 'N', left: 10, top: 2, moves: true),
        target<String>(
          log,
          'S',
          left: 20,
          top: 2,
          accepts: (data) => data != 'apple',
          moves: true,
        ),
      ]),
      size: (30, 5),
    );
    await t.mouse(MouseKind.down, 1, 0);
    await t.mouse(MouseKind.drag, 12, 3);
    expect(log, ['started']);
    await t.pump();
    expect(t, hasTextAt(10, 2, 'N!        S '));

    await t.mouse(MouseKind.drag, 22, 3);
    expect(log, ['started', 'S will apple 2,1', 'S move apple 2,1']);
    await t.pump();
    expect(t, hasTextAt(10, 2, 'N         S!'));

    log.clear();
    await t.mouse(MouseKind.up, 22, 3);
    expect(log, ['S leave apple', 'canceled']);
    await t.pump();
    expect(t, matchesScreen('apple\n\n          N         S'));

    log.clear();
    await t.mouse(MouseKind.down, 1, 0);
    await t.mouse(MouseKind.drag, 5, 4);
    await t.mouse(MouseKind.up, 5, 4);
    expect(log, ['started', 'canceled']);
  });

  testTwk('of targets one inside another, the deepest that accepts gets '
      'the drop; those inside it that reject are told it left', (t) async {
    final log = <String>[];
    String label(String name, Object? candidate, Object? rejected) =>
        candidate != null
        ? '$name:$candidate'
        : rejected != null
        ? '$name!'
        : name;
    await t.pumpWidget(
      stage([
        apple(log),
        Positioned(
          left: 10,
          top: 1,
          width: 20,
          height: 4,
          child: DragTarget<String>(
            onWillAccept: (d) {
              log.add('O will ${d.data} ${at(d.event)}');
              return true;
            },
            onAccept: (d) => log.add('O accept ${d.data} ${at(d.event)}'),
            onLeave: (data) => log.add('O leave $data'),
            builder: (context, candidate, rejected) => Stack(
              children: [
                Text(label('O', candidate, rejected)),
                target<String>(
                  log,
                  'I',
                  left: 0,
                  top: 1,
                  accepts: (_) => false,
                ),
                target<String>(log, 'J', left: 10, top: 1),
              ],
            ),
          ),
        ),
      ]),
      size: (30, 5),
    );
    await t.mouse(MouseKind.down, 1, 0);
    await t.mouse(MouseKind.drag, 11, 3);
    expect(log, ['started', 'I will apple 1,1', 'O will apple 1,2']);
    await t.pump();
    expect(t.lines.skip(1).take(2), [
      '          O:apple',
      '          I!        J',
    ]);

    log.clear();
    await t.mouse(MouseKind.drag, 21, 3);
    expect(log, ['J will apple 1,1', 'I leave apple', 'O leave apple']);

    log.clear();
    await t.mouse(MouseKind.drag, 11, 3);
    await t.mouse(MouseKind.up, 11, 3);
    expect(log, [
      'I will apple 1,1',
      'O will apple 1,2',
      'J leave apple',
      'O accept apple 1,2',
      'I leave apple',
      'completed',
    ]);
  });

  testTwk('a list reordered by drag: a row dropped on another takes its '
      'place, and none dropped on itself', (t) async {
    await t.pumpWidget(const Fruits(), size: (20, 5));
    expect(t.lines.take(4), ['  apple', '  banana', '  cherry', '  date']);
    await t.mouse(MouseKind.down, 3, 0);
    await t.mouse(MouseKind.drag, 3, 2);
    await t.pump();
    expect(t.lines.take(4), ['  apple', '  banana', '» apple «', '  date']);
    await t.mouse(MouseKind.drag, 3, 3);
    await t.pump();
    // the row left is no longer marked
    expect(t.lines.take(4), ['  apple', '  banana', '  cherry', '» apple «']);
    await t.mouse(MouseKind.drag, 3, 2);
    await t.mouse(MouseKind.up, 3, 2);
    await t.pump();
    expect(t.lines.take(4), ['  banana', '  cherry', '  apple', '  date']);

    await t.mouse(MouseKind.down, 3, 1);
    await t.mouse(MouseKind.drag, 4, 1);
    await t.mouse(MouseKind.up, 4, 1);
    await t.pump();
    expect(t.lines.take(4), ['  banana', '  cherry', '  apple', '  date']);

    await t.mouse(MouseKind.down, 3, 3);
    await t.mouse(MouseKind.drag, 3, 0);
    await t.mouse(MouseKind.up, 3, 0);
    await t.pump();
    expect(t.lines.take(4), ['  date', '  banana', '  cherry', '  apple']);
  });

  testTwk('the feedback is placed in the overlay wherever the overlay is, '
      'as big as it likes, cut off at its edges', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Padding(
        padding: const EdgeInsets.only(left: 2, top: 1),
        child: stage([apple(log)]),
      ),
      size: (30, 5),
    );
    await t.mouse(MouseKind.down, 3, 1);
    await t.mouse(MouseKind.drag, 28, 4);
    await t.pump();
    expect(t.lines, ['', '  .....', '', '', '                           [ap']);
  });

  testTwk('a drag takes the press from the gesture detectors around it: '
      'their tap is not told; one inside it that drags takes it first', (
    t,
  ) async {
    final log = <String>[];
    await t.pumpWidget(
      Overlay(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: (e) => log.add('tap ${at(e)}'),
              child: Draggable<String>(
                data: 'outer',
                feedback: const Text('[outer]'),
                onDragStarted: () => log.add('outer started'),
                onDragCanceled: () => log.add('outer canceled'),
                child: const Text('outer'),
              ),
            ),
            Draggable<String>(
              data: 'around',
              feedback: const Text('[around]'),
              onDragStarted: () => log.add('around started'),
              child: GestureDetector(
                onDragStart: (d) => log.add('inner start ${at(d.event)}'),
                onDragEnd: (d) => log.add('inner end ${at(d.event)}'),
                child: const Text('inner'),
              ),
            ),
          ],
        ),
      ),
      size: (20, 3),
    );
    await t.click(1, 0);
    expect(log, ['tap 1,0']);
    log.clear();
    await t.mouse(MouseKind.down, 1, 0);
    await t.mouse(MouseKind.drag, 2, 0);
    await t.mouse(MouseKind.up, 2, 0);
    expect(log, ['outer started', 'outer canceled']);

    log.clear();
    await t.mouse(MouseKind.down, 1, 1);
    await t.mouse(MouseKind.drag, 2, 1);
    await t.mouse(MouseKind.up, 2, 1);
    await t.pump();
    expect(log, ['inner start 1,0', 'inner end 2,0']);
    expect(t.lines.take(2), ['outer', 'inner']);
  });

  testTwk('the terminal reports presses and releases, and motion with the '
      'button held only while a draggable is pressed', (t) async {
    final log = <String>[];
    await t.pumpWidget(stage([apple(log)]), size: (20, 3));
    expect(mouseModes(t), ['?1000h', '?1006h']);
    await t.mouse(MouseKind.down, 1, 0);
    await t.pump();
    expect(mouseModes(t).skip(2), ['?1000l', '?1002h']);
    await t.mouse(MouseKind.up, 1, 0);
    await t.pump();
    expect(mouseModes(t).skip(4), ['?1002l', '?1000h']);
    await t.mouse(MouseKind.down, 1, 0);
    await t.mouse(MouseKind.drag, 5, 1);
    await t.pump();
    expect(mouseModes(t).skip(6), ['?1000l', '?1002h']);
    await t.mouse(MouseKind.up, 5, 1);
    await t.pump();
    expect(mouseModes(t).skip(8), ['?1002l', '?1000h']);
    expect(log, ['started', 'canceled']);
  });

  testTwk('a drag whose release the terminal did not report is canceled at '
      'the next press, or at motion with no button held; a press not yet a '
      'drag is forgotten', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      stage([apple(log), target<String>(log, 'A', left: 10, top: 2)]),
      size: (30, 5),
    );
    await t.mouse(MouseKind.down, 1, 0);
    await t.mouse(MouseKind.drag, 12, 3);
    await t.mouse(MouseKind.down, 25, 4);
    expect(log, ['started', 'A will apple 2,1', 'A leave apple', 'canceled']);
    await t.mouse(MouseKind.up, 25, 4);
    await t.pump();
    expect(t, matchesScreen('apple\n\n          A'));

    log.clear();
    await t.mouse(MouseKind.down, 1, 0);
    await t.mouse(MouseKind.drag, 12, 3);
    await t.mouse(MouseKind.move, 13, 3);
    expect(log, ['started', 'A will apple 2,1', 'A leave apple', 'canceled']);
    await t.pump();
    expect(t, matchesScreen('apple\n\n          A'));

    // a press not yet a drag is forgotten too
    log.clear();
    await t.mouse(MouseKind.down, 0, 0);
    await t.mouse(MouseKind.down, 3, 0);
    await t.mouse(MouseKind.drag, 12, 3);
    await t.pump();
    expect(t, hasTextAt(9, 3, '[apple]'));
  });

  testTwk('a draggable that leaves the tree while dragged ends the drag: '
      'the feedback goes, the target is told it left', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      Host(
        key: host,
        (s) => stage([
          if (s.step == 0) apple(log),
          target<String>(log, 'A', left: 10, top: 2),
        ]),
      ),
      size: (30, 5),
    );
    await t.mouse(MouseKind.down, 1, 0);
    await t.mouse(MouseKind.drag, 12, 3);
    await t.pump();
    host.currentState!.change(1);
    await t.pump();
    await t.pump();
    expect(t, matchesScreen('\n\n          A'));
    await t.mouse(MouseKind.up, 12, 3);
    expect(log, ['started', 'A will apple 2,1', 'A leave apple']);
  });

  testTwk('what a target throws ends the app, in the target', (t) async {
    await t.pumpWidget(
      stage([
        apple([]),
        Positioned(
          left: 10,
          top: 2,
          child: DragTarget<String>(
            onAccept: (_) => throw StateError('drop'),
            builder: (context, candidate, rejected) => const Text('A'),
          ),
        ),
      ]),
      size: (30, 5),
    );
    await t.mouse(MouseKind.down, 1, 0);
    await t.mouse(MouseKind.drag, 10, 2);
    await expectLater(
      t.mouse(MouseKind.up, 10, 2),
      throwsA(
        isA<WidgetError>()
            .having(
              (e) => e.path,
              'path',
              endsWith('→ Positioned → DragTarget<String> → _Target'),
            )
            .having((e) => '${e.error}', 'error', 'Bad state: drop'),
      ),
    );
  });

  testTwk('a Draggable without an Overlay above fails to build, saying '
      'where to place one', (t) async {
    await t.pumpWidget(
      const Draggable<int>(data: 1, feedback: Text('1'), child: Text('1')),
    );
    const failed =
        'Draggable<int> failed to build: Bad state: no Overlay above '
        'Draggable<int>: place an Overlay above it, as App does around the '
        'whole app: App(child: …)';
    expect(
      [
        for (final r in t.logs.records)
          if (r.level == LogLevel.error) '${r.message}: ${r.error}',
      ],
      [failed],
    );
  });

  group('the pointer', () {
    /// A Draggable of 'a' at the top left, a target of numbers at the
    /// top right and one of strings under it, 6 × 2 cells each.
    Widget app({bool pointerShapes = true}) => Overlay(
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Draggable<String>(
              data: 'a',
              feedback: const Text('[a]'),
              pointerShapes: pointerShapes,
              child: const Text('drag'),
            ),
          ),
          Positioned(
            left: 10,
            top: 0,
            width: 6,
            height: 2,
            child: DragTarget<int>(builder: (_, _, _) => const Text('ints')),
          ),
          Positioned(
            left: 10,
            top: 2,
            width: 6,
            height: 2,
            child: DragTarget<String>(
              builder: (_, _, _) => const Text('words'),
            ),
          ),
        ],
      ),
    );

    test('grabs over it, grabbing while it is dragged, no-drop over a '
        'target that refuses it', () async {
      final run = ShapeRun(app());
      await run.start();
      await run.move(1, 0);
      expect(run.shapes(), ['grab']);
      await run.press(1, 0);
      expect(run.shapes(), isEmpty);
      await run.drag(2, 0);
      expect(run.shapes(), ['grabbing']);
      // off the draggable, still dragging
      await run.drag(5, 3);
      expect(run.shapes(), isEmpty);
      await run.drag(11, 1);
      expect(run.shapes(), ['no-drop']);
      await run.drag(11, 2);
      expect(run.shapes(), ['grabbing']);
      await run.release(11, 2);
      expect(run.shapes(), ['default']);
      await run.move(0, 0);
      expect(run.shapes(), ['grab']);
      await run.quit();
    });

    test('left alone with pointerShapes false', () async {
      final run = ShapeRun(app(pointerShapes: false));
      await run.start();
      await run.move(1, 0);
      await run.press(1, 0);
      await run.drag(2, 0);
      await run.drag(11, 1);
      await run.release(11, 1);
      await run.quit();
      // only the terminal's own given back as the app ends
      expect(run.shapes(), ['']);
    });
  });
}
