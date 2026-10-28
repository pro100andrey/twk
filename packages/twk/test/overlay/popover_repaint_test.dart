// An open popover repaints with the overlay only its own rows, not all of
// the overlay: a label rebuilt under it or in it repaints its row and the
// popover's rows (the rows between them with them: a boundary repaints a
// span of rows); a spinner, a repaint boundary, its own cells, the popover
// over them where it covers them. A target that moves takes the popover
// along in the same frame, the rows it was on and those it goes to
// repainted, whether it moves in the overlay's boundary, to rows the
// frame would not repaint, or in a window that repaints on its own. What
// shows is what a whole repaint shows.
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../data/shot.dart' show Counted, PaintCount;

const _width = 20;
const _height = 10;

/// Where the label or spinner that changes is.
enum Where {
  /// In the top row, which the popover does not cover.
  top,

  /// At the right end of a row the popover covers, beside it.
  covered,

  /// In the popover's first row.
  inside,
}

/// The rows under an open popover and in it, each with a counter of its
/// paints: [under] those of the overlay, [inside] the popover's three.
final class Scene {
  final List<PaintCount> under = [
    for (var i = 0; i < _height; i++) PaintCount(),
  ];
  final List<PaintCount> inside = [for (var i = 0; i < 3; i++) PaintCount()];

  /// The number the label that changes shows.
  final ValueNotifier<int> tick = ValueNotifier(0);

  /// The rows of [under] and of [inside] that painted while [change] ran.
  Future<List<List<int>>> painted(Future<void> Function() change) async {
    final u = [for (final c in under) c.paints];
    final p = [for (final c in inside) c.paints];
    await change();
    return [
      [
        for (var i = 0; i < under.length; i++)
          if (under[i].paints != u[i]) i,
      ],
      [
        for (var i = 0; i < inside.length; i++)
          if (inside[i].paints != p[i]) i,
      ],
    ];
  }

  /// What changes, three cells wide: a label or a spinner.
  Widget changing({required bool spinner}) => SizedBox(
    width: 3,
    height: 1,
    child: spinner
        ? const Spinner()
        : ValueListenableBuilder<int>(
            valueListenable: tick,
            builder: (_, n, _) => Text('#$n'),
          ),
  );

  /// A row saying [label], counted by [count], what changes at its end
  /// when [changes].
  Widget row(
    String label,
    PaintCount count, {
    Widget? changes,
    bool atEnd = false,
  }) => Row(
    children: [
      if (changes != null && !atEnd) changes else Text(label),
      Expanded(child: Counted(count)),
      if (changes != null && atEnd) changes,
    ],
  );

  /// The overlay: the popover's anchor in row 1, the popover under it in
  /// rows 2 to 4, eight cells wide; what changes [where], [beforeAnchor]
  /// blank rows above the anchor's row.
  Widget build(
    Where where, {
    bool spinner = false,
    ValueListenable<int>? beforeAnchor,
  }) {
    final changes = changing(spinner: spinner);
    return Overlay(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row('top', under[0], changes: where == Where.top ? changes : null),
          SizedBox(
            height: 1,
            child: Row(
              children: [
                if (beforeAnchor != null)
                  ValueListenableBuilder<int>(
                    valueListenable: beforeAnchor,
                    builder: (_, n, _) => SizedBox(width: n),
                  ),
                Popover(
                  open: true,
                  popover: SizedBox(
                    width: 8,
                    height: 3,
                    child: Column(
                      children: [
                        for (var j = 0; j < 3; j++)
                          row(
                            'p$j',
                            inside[j],
                            changes: where == Where.inside && j == 0
                                ? changes
                                : null,
                          ),
                      ],
                    ),
                  ),
                  child: const Text('anchor'),
                ),
                Expanded(child: Counted(under[1])),
              ],
            ),
          ),
          for (var i = 2; i < _height; i++)
            row(
              'u$i',
              under[i],
              changes: where == Where.covered && i == 3 ? changes : null,
              atEnd: true,
            ),
        ],
      ),
    );
  }
}

/// The cells and the styles of the screen.
(Uint32List, Uint32List) shown(TwkTester t) {
  final s = t.binding.twkApp.screen.surface;
  return (Uint32List.fromList(s.cells), Uint32List.fromList(s.styles));
}

/// Expects what shows to be what shows painted again whole.
Future<void> expectWhole(TwkTester t, String reason) async {
  final (cells, styles) = shown(t);
  t.binding.twkApp.owner.markAllDirty();
  await t.pump();
  final (wholeCells, wholeStyles) = shown(t);
  expect(cells, wholeCells, reason: reason);
  expect(styles, wholeStyles, reason: reason);
}

/// The rows under the popover and in it that each step of a label
/// rebuilt in a place paints: its own and the popover's, rows 2 to 4, and
/// those between; before, all ten and the popover's three.
const Map<Where, List<List<int>>> _expected = {
  Where.top: [
    [0, 1, 2, 3, 4],
    [0, 1, 2],
  ],
  Where.covered: [
    [2, 3, 4],
    [0, 1, 2],
  ],
  Where.inside: [
    [2, 3, 4],
    [0, 1, 2],
  ],
};

void main() {
  for (final where in Where.values) {
    testTwk('a label rebuilt ${where.name} repaints its row and the '
        "popover's", (t) async {
      final s = Scene();
      addTearDown(s.tick.dispose);
      await t.pumpWidget(s.build(where), size: (_width, _height));
      await t.pump();
      expect(t, hasTextAt(0, 1, 'anchor'));
      expect(t, hasTextAt(0, 2, where == Where.inside ? '#0' : 'p0'));
      for (var step = 1; step <= 3; step++) {
        final rows = await s.painted(() async {
          s.tick.value = step;
          await t.pump();
        });
        expect(rows, _expected[where], reason: 'step $step');
        await expectWhole(t, 'step $step');
      }
    });

    testTwk('a spinner ${where.name} repaints its own cells', (t) async {
      final s = Scene();
      addTearDown(s.tick.dispose);
      await t.pumpWidget(
        s.build(where, spinner: true),
        size: (_width, _height),
      );
      await t.pump();
      for (var step = 1; step <= 3; step++) {
        final shown = t.lines;
        // just past the step, the whole repaint after it in the same one
        final rows = await s.painted(
          () => t.pump(Duration(milliseconds: 80 * step + 1) - t.clock.elapsed),
        );
        expect(t.lines, isNot(shown), reason: 'the spinner turned');
        // the spinner repaints on its own, the popover over it where it
        // covers it
        expect(rows, [<int>[], <int>[]], reason: 'step $step');
        await expectWhole(t, 'step $step');
      }
    });
  }

  testTwk('a target moved in the same boundary takes the popover along in '
      'the same frame', (t) async {
    final s = Scene();
    final before = ValueNotifier(0);
    addTearDown(s.tick.dispose);
    addTearDown(before.dispose);
    await t.pumpWidget(
      s.build(Where.top, beforeAnchor: before),
      size: (_width, _height),
    );
    await t.pump();
    expect(t, hasTextAt(0, 2, 'p0'));
    for (final n in [5, 12, 3, 0]) {
      before.value = n;
      await t.pump();
      expect(t, hasTextAt(n, 1, 'anchor'), reason: 'moved to $n');
      expect(t, hasTextAt(n, 2, 'p0'), reason: 'moved to $n');
      await expectWhole(t, 'moved to $n');
    }
  });

  testTwk('a target moved to rows the frame does not repaint takes the '
      'popover there in the same frame', (t) async {
    final s = Scene();
    final above = ValueNotifier(0);
    addTearDown(s.tick.dispose);
    addTearDown(above.dispose);
    await t.pumpWidget(
      Overlay(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // laid out on its own: the frame repaints its rows only
            SizedBox(
              width: _width,
              height: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ValueListenableBuilder<int>(
                    valueListenable: above,
                    builder: (_, n, _) => SizedBox(height: n),
                  ),
                  const Popover(
                    open: true,
                    popover: Text('pop 0\npop 1\npop 2'),
                    child: Text('anchor'),
                  ),
                ],
              ),
            ),
            for (var i = 3; i < _height; i++)
              s.row('row $i', s.under[i], atEnd: true),
          ],
        ),
      ),
      size: (_width, _height),
    );
    await t.pump();
    expect(t.lines.take(6), [
      'anchor',
      'pop 0',
      'pop 1',
      'pop 2',
      'row 4',
      'row 5',
    ]);
    final frames = t.frames.length;
    final rows = await s.painted(() async {
      above.value = 2;
      await t.pump();
    });
    // in one frame, where a whole repaint has it
    expect(t.frames.sublist(frames), hasLength(1));
    expect(t.lines.take(6), ['', '', 'anchor', 'pop 0', 'pop 1', 'pop 2']);
    await expectWhole(t, 'moved');
    // the target's rows, those the popover was on and those it went to
    expect(rows.first, [3, 4, 5]);
    above.value = 0;
    await t.pump();
    // the rows it goes to are those it was on and the target's
    expect(t.lines.take(6), [
      'anchor',
      'pop 0',
      'pop 1',
      'pop 2',
      'row 4',
      'row 5',
    ]);
    await expectWhole(t, 'moved back');
  });

  testTwk('a target scrolled in a window that repaints on its own takes the '
      'popover along in the same frame', (t) async {
    final s = Scene();
    final controller = ScrollController();
    addTearDown(s.tick.dispose);
    addTearDown(controller.dispose);
    await t.pumpWidget(
      Overlay(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _width,
              height: 6,
              child: SingleChildScrollView(
                controller: controller,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < 4; i++) Text('line $i'),
                    const Popover(
                      open: true,
                      popover: Text('pop 0\npop 1'),
                      child: Text('anchor'),
                    ),
                    for (var i = 5; i < 12; i++) Text('line $i'),
                  ],
                ),
              ),
            ),
            for (var i = 6; i < _height; i++)
              s.row('row $i', s.under[i], atEnd: true),
          ],
        ),
      ),
      size: (_width, _height),
    );
    await t.pump();
    expect(t, hasTextAt(0, 4, 'anchor'));
    expect(t, hasTextAt(0, 5, 'pop 0'));
    expect(t, hasTextAt(0, 6, 'pop 1'));
    // the scroll offset, the row the popover goes to, and the rows under
    // the window that repaint: those it was on or goes to
    for (final (offset, at, rows) in [
      (2, 3, [6]),
      (4, 1, <int>[]),
      // the target above the window: the popover moved in under it
      (5, 0, <int>[]),
      (1, 4, <int>[]),
      (0, 5, [6]),
    ]) {
      final frames = t.frames.length;
      final reason = 'scrolled to $offset';
      final painted = await s.painted(() async {
        controller.jumpTo(offset);
        await t.pump();
      });
      expect(t.frames.sublist(frames), hasLength(1), reason: reason);
      if (offset < 5) {
        expect(t, hasTextAt(0, at - 1, 'anchor'), reason: reason);
      }
      expect(t, hasTextAt(0, at, 'pop 0'), reason: reason);
      expect(t, hasTextAt(0, at + 1, 'pop 1'), reason: reason);
      expect(painted.first, rows, reason: reason);
      await expectWhole(t, reason);
    }
  });
}
