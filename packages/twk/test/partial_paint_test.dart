// A repaint boundary repaints only the rows of what was marked for paint
// in it. What paints by where other objects in it are still follows them:
// a popover its target, when the target moves in the same boundary; a
// split view's divider the dividers of a split view across it, which it
// joins. An Opacity those rows cut through mixes what repaints on its own
// in it from the frame after at the latest, in its other rows too.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import 'layout/view.dart' show Fill;

SplitPane pane(String char) => SplitPane(child: Fill(char));

/// Presses the left button at ([x], [y]), drags to ([tx], [ty]) and
/// releases it there, pumping a frame after each.
Future<void> drag(TwkTester t, int x, int y, int tx, int ty) async {
  await t.mouse(MouseKind.down, x, y);
  await t.pump();
  await t.mouse(MouseKind.drag, tx, ty);
  await t.pump();
  await t.mouse(MouseKind.up, tx, ty);
  await t.pump();
}

/// A popover's anchor [before] blank columns into a row of its own,
/// which is laid out again on its own when [before] changes.
Widget anchored(ValueNotifier<int> before) => Overlay(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('line 0'),
      SizedBox(
        width: 12,
        height: 1,
        child: Row(
          children: [
            ValueListenableBuilder<int>(
              valueListenable: before,
              builder: (_, n, _) => SizedBox(width: n),
            ),
            const Popover(open: true, popover: Text('pop'), child: Text('at')),
          ],
        ),
      ),
      for (var i = 0; i < 4; i++) Text('below $i'),
    ],
  ),
);

/// An Opacity over a spinner below a row of text, beside [label].
Widget faded(String label) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    const SizedBox(
      width: 4,
      child: Opacity(
        opacity: 0.5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('top'),
            Spinner(
              style: Style(
                fg: Color.rgb(255, 255, 255),
                bg: Color.rgb(0, 0, 200),
              ),
            ),
          ],
        ),
      ),
    ),
    // laid out on its own: repainting its row only
    SizedBox(width: 8, height: 1, child: Text(label)),
  ],
);

void main() {
  testTwk('an Opacity that rows of a repaint cut through mixes what repaints '
      'on its own in it', (t) async {
    await t.pumpWidget(faded('one'), size: (12, 4));
    final mixed = (t.cell(0, 1).fg, t.cell(0, 1).bg);
    expect(mixed.$2, isNot(const Color.rgb(0, 0, 200).value));
    // row 0 repaints, the Opacity's top row with it
    await t.pumpWidget(faded('two'));
    expect(t, hasTextAt(4, 0, 'two'));
    for (var step = 0; step < 3; step++) {
      // the spinner turns: it repaints on its own, mixed from the frame
      // after the label's at the latest
      await t.pump(const Duration(milliseconds: 80));
      await t.pump();
      expect((t.cell(0, 1).fg, t.cell(0, 1).bg), mixed);
    }
  });

  testTwk('a popover follows its target moved in the same boundary', (
    t,
  ) async {
    final before = ValueNotifier(1);
    addTearDown(before.dispose);
    await t.pumpWidget(anchored(before), size: (12, 8));
    await t.pump();
    expect(t, hasTextAt(1, 1, 'at'));
    expect(t, hasTextAt(0, 2, 'bpop'));
    // the row is laid out again, and repainted: not the popover's rows
    before.value = 5;
    await t.pump();
    expect(t, hasTextAt(5, 1, 'at'));
    expect(t, hasTextAt(0, 2, 'belowpop'));
    before.value = 0;
    await t.pump();
    expect(t, hasTextAt(0, 1, 'at'));
    expect(t, hasTextAt(0, 2, 'popow 0'));
  });

  testTwk('a divider joins the dividers of the split view across it that '
      'moved', (t) async {
    await t.pumpWidget(
      SplitView(
        direction: Axis.vertical,
        panes: [
          SplitPane(child: SplitView(panes: [pane('a'), pane('b')])),
          pane('c'),
        ],
      ),
      size: (9, 5),
    );
    expect(t.lines, [
      'aaaa│bbbb',
      'aaaa│bbbb',
      '────┴────',
      'ccccccccc',
      'ccccccccc',
    ]);
    // the inner split is laid out on its own: the joint below it moves
    await drag(t, 4, 0, 6, 0);
    expect(t.lines[0], 'aaaaaa│bb');
    expect(t.lines[2], '──────┴──');
  });
}
