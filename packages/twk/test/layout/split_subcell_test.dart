// A SplitView's divider, and a DockArea's, dragged where the terminal
// reports the pointer in pixels: the share follows the part of a cell the
// pointer moved, the cells the panes get staying whole; with whole cells
// reported, as before.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import 'view.dart' show Fill;

Widget split(SplitController c) => Theme.terminal(
  child: SplitView(
    controller: c,
    panes: const [
      SplitPane(child: Fill('a')),
      SplitPane(child: Fill('b')),
    ],
  ),
);

void main() {
  testTwk('a divider keeps the part of a cell the pointer moved in the '
      'shares', (t) async {
    final c = SplitController();
    addTearDown(c.dispose);
    await t.pumpWidget(
      split(c),
      size: (21, 2),
      cellPixels: (10, 20),
      pixelMouse: true,
    );
    // 20 own cells; pressed 10.55 cells along, dragged to 14.85
    await t.mouse(MouseKind.down, 10, 1, offsetX: 5);
    await t.mouse(MouseKind.drag, 14, 0, offsetX: 8);
    await t.pump();
    expect(t.lines.first, 'aaaaaaaaaaaaaa│bbbbbb');
    expect(c.sizes, [14, 6]);
    expect(c.fractions[0], closeTo(14.3 / 20, 1e-9));
    expect(c.fractions[1], closeTo(5.7 / 20, 1e-9));
    // back to a little before the press: the cells go back to 10
    await t.mouse(MouseKind.drag, 10, 0, offsetX: 1);
    await t.pump();
    expect(c.sizes, [10, 10]);
    expect(c.fractions[0], closeTo(9.6 / 20, 1e-9));
    await t.mouse(MouseKind.up, 10, 0, offsetX: 1);
  });

  testTwk('held back by its least, a pane keeps no part of a cell', (
    t,
  ) async {
    final c = SplitController();
    addTearDown(c.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: SplitView(
          controller: c,
          panes: const [
            SplitPane(child: Fill('a')),
            SplitPane(child: Fill('b'), minSize: 6),
          ],
        ),
      ),
      size: (21, 2),
      cellPixels: (10, 20),
      pixelMouse: true,
    );
    await t.mouse(MouseKind.down, 10, 1, offsetX: 5);
    await t.mouse(MouseKind.drag, 20, 0, offsetX: 5);
    await t.pump();
    expect(c.sizes, [14, 6]);
    expect(c.fractions[0], closeTo(14 / 20, 1e-9));
  });

  testTwk('with whole cells reported the shares are whole cells', (t) async {
    final c = SplitController();
    addTearDown(c.dispose);
    await t.pumpWidget(split(c), size: (21, 2), cellPixels: (10, 20));
    await t.mouse(MouseKind.down, 10, 1);
    await t.mouse(MouseKind.drag, 14, 0);
    await t.pump();
    expect(c.fractions, [0.7, 0.3]);
  });

  testTwk('a dock divider keeps it too', (t) async {
    final c = DockController(
      DockLayout(
        root: DockSplit(Axis.horizontal, [
          DockTabs(['a']),
          DockTabs(['c']),
        ]),
      ),
    );
    addTearDown(c.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: DockArea(
          controller: c,
          panels: const [
            DockPanel(id: 'a', title: 'A', child: Text('a body')),
            DockPanel(id: 'c', title: 'C', child: Text('c body')),
          ],
        ),
      ),
      size: (40, 12),
      cellPixels: (10, 20),
      pixelMouse: true,
    );
    await t.mouse(MouseKind.down, 20, 5, offsetX: 5);
    await t.mouse(MouseKind.drag, 25, 5, offsetX: 8);
    await t.pump();
    await t.mouse(MouseKind.up, 25, 5, offsetX: 8);
    final fractions = (c.layout.root! as DockSplit).fractions;
    expect(fractions[0], closeTo(25.3 / 39, 1e-9));
    expect(fractions[1], closeTo(13.7 / 39, 1e-9));
  });
}
