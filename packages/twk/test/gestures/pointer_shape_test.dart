// MouseRegion.cursor: the pointer's shape (OSC 22) of the deepest region
// the mouse is in that has one, written as it changes, with the mouse or
// with a frame; the app's arrow when the mouse leaves them, the terminal's
// own when the app ends; nothing written, nor the mouse's motion asked
// for, where the terminal is not known to show it.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show MouseTracking;

import 'shape_run.dart';

/// A region at [left], [top], [width] × [height] cells, in [cursor].
Widget _region(
  PointerShape? cursor, {
  required int left,
  required int top,
  required int width,
  required int height,
  Widget? child,
}) => Positioned(
  left: left,
  top: top,
  width: width,
  height: height,
  child: MouseRegion(cursor: cursor, child: child),
);

/// Shows what [child] builds for the step it is at, from 0, which
/// [_StepsState.next] moves on.
final class _Steps extends StatefulWidget {
  const _Steps(this.child, {super.key});

  final Widget Function(int step) child;

  @override
  State<_Steps> createState() => _StepsState();
}

final class _StepsState extends State<_Steps> {
  var _step = 0;

  void next() => setState(() => _step++);

  @override
  Widget build(BuildContext context) => widget.child(_step);
}

void main() {
  test("set once as the mouse comes in, the app's arrow when it goes out, "
      "the terminal's own as the app ends", () async {
    final run = ShapeRun(
      Stack(
        children: [
          _region(PointerShape.text, left: 2, top: 1, width: 5, height: 2),
        ],
      ),
    );
    await run.start();
    expect(run.term.mouseTracking, MouseTracking.motion);
    await run.move(0, 0);
    expect(run.shapes(), isEmpty);
    await run.move(3, 1);
    expect(run.written(), contains('\x1b]22;text\x1b\\'));
    await run.move(6, 2);
    expect(run.shapes(), isEmpty);
    await run.move(10, 3);
    expect(run.shapes(), ['default']);
    await run.quit();
    expect(run.shapes(), ['']);
  });

  test('of the deepest region with a cursor, one without it in that of '
      'the region around it', () async {
    final run = ShapeRun(
      Stack(
        children: [
          _region(
            PointerShape.pointer,
            left: 0,
            top: 0,
            width: 12,
            height: 4,
            child: Stack(
              children: [
                _region(null, left: 0, top: 0, width: 4, height: 4),
                _region(
                  PointerShape.ewResize,
                  left: 6,
                  top: 0,
                  width: 2,
                  height: 4,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    await run.start();
    await run.move(10, 0);
    expect(run.shapes(), ['pointer']);
    await run.move(1, 1);
    expect(run.shapes(), isEmpty);
    await run.move(7, 1);
    expect(run.shapes(), ['ew-resize']);
    await run.move(9, 1);
    expect(run.shapes(), ['pointer']);
    await run.move(15, 1);
    expect(run.shapes(), ['default']);
    await run.quit();
  });

  test('changed by a frame that moves a region under the mouse or away, '
      'gives it another cursor or removes it', () async {
    final key = GlobalKey<_StepsState>();
    final run = ShapeRun(
      _Steps(
        key: key,
        (step) => Stack(
          children: [
            if (step < 5)
              _region(
                step < 2 ? PointerShape.grab : PointerShape.move,
                left: step == 1 || step == 2 || step == 4 ? 0 : 10,
                top: 0,
                width: 4,
                height: 4,
              ),
          ],
        ),
      ),
    );
    await run.start();
    await run.move(1, 1);
    expect(run.shapes(), isEmpty);
    final shapes = <List<String>>[];
    for (var i = 0; i < 5; i++) {
      await run.act(key.currentState!.next);
      shapes.add(run.shapes());
    }
    expect(shapes, [
      ['grab'],
      ['move'],
      ['default'],
      ['move'],
      ['default'],
    ]);
    expect(run.term.mouseTracking, MouseTracking.off);
    await run.quit();
  });

  test('put back as the terminal showed it when the app ends with the '
      'mouse in a region', () async {
    final run = ShapeRun(
      Stack(
        children: [
          _region(PointerShape.wait, left: 0, top: 0, width: 4, height: 4),
        ],
      ),
    );
    await run.start();
    await run.move(1, 1);
    expect(run.shapes(), ['wait']);
    await run.quit();
    expect(run.term.closed, isTrue);
    expect(run.shapes(), ['']);
  });

  test(
    'an I-beam over a SelectionArea, the arrow over a scrollbar in it',
    () async {
      final run = ShapeRun(
        SelectionArea(
          child: Scrollbar(
            child: SingleChildScrollView(
              child: Column(
                children: [for (var i = 0; i < 10; i++) Text('line $i')],
              ),
            ),
          ),
        ),
      );
      await run.start();
      await run.move(2, 1);
      expect(run.shapes(), ['text']);
      await run.move(19, 1);
      expect(run.shapes(), ['default'], reason: 'the scrollbar');
      await run.move(10, 2);
      expect(run.shapes(), ['text']);
      await run.quit();
    },
  );

  test('nothing where the terminal is not known to show it: a cursor alone '
      'asks for no motion', () async {
    final run = ShapeRun(
      Stack(
        children: [
          _region(PointerShape.text, left: 0, top: 0, width: 4, height: 4),
        ],
      ),
      shows: false,
    );
    await run.start();
    expect(run.term.mouseTracking, MouseTracking.off);
    await run.move(1, 1);
    await run.move(10, 1);
    await run.quit();
    expect(run.written(), isNot(contains('\x1b]22;')));
  });
}
