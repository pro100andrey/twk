// The edges a Window lights while the mouse is over them are drawn in
// eighths of a cell (`▏ ▕ ▁`, `▛ ▜`). On a terminal that takes the East
// Asian ambiguous characters for two columns those are two columns wide:
// the edge must still be lit in every cell of it, by other marks, as the
// glyph paths that check a mark's width do. Review finding 6 of the
// architecture review; waits for arch-theme-marks.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../text/ambiguous.dart';

Widget windows(WindowController c) => Theme.terminal(
  child: WindowLayer(
    frame: WindowFrame.raised,
    windows: [Window(title: 'Alpha', controller: c, child: const Text('x'))],
    child: const Text('app'),
  ),
);

WindowController window() =>
    WindowController(left: 2, top: 1, width: 20, height: 5);

/// The bottom right corner lit: the bottom edge from column 2 to 20 and
/// the right edge in column 21, rows 2 to 5; 20 cells of row 5.
const corner = (21, 5);

void main() {
  testTwk('guard: where eighths are one column, the bottom right corner lights '
      'every cell of the bottom and right edges', (t) async {
    final c = window();
    addTearDown(c.dispose);
    await t.pumpWidget(windows(c), size: (40, 10));
    await t.mouse(MouseKind.move, corner.$1, corner.$2);
    await t.pump();
    expect(t.lines[5].substring(2).trim().length, 20);
    for (var y = 2; y <= 5; y++) {
      expect(t, hasTextAt(21, y, '▕'));
    }
  });

  test('on a terminal with wide ambiguous characters, the bottom right corner '
      'lights every cell of the bottom and right edges', () async {
    final c = window();
    final app = await WideApp.start(windows(c), width: 40, height: 10);
    app.terminal.type('\x1b[<35;${corner.$1 + 1};${corner.$2 + 1}M');
    await app.settle();
    await app.settle();
    final lines = app.lines();
    await app.quit();
    c.dispose();
    // the cells of row 5 from column 2: a mark a column each, 20 of them
    expect(
      lines[5].substring(2).replaceAll(' ', '').runes.length,
      20,
      reason: 'row 5: [${lines[5]}]',
    );
  }, skip: 'probable bug confirmed: arch-theme-marks');

  test('on a terminal with wide ambiguous characters, the left edge is lit '
      'in every row', () async {
    final c = window();
    final app = await WideApp.start(windows(c), width: 40, height: 10);
    app.terminal.type('\x1b[<35;3;4M');
    await app.settle();
    await app.settle();
    final lines = app.lines();
    await app.quit();
    c.dispose();
    for (var y = 2; y <= 5; y++) {
      expect(
        lines[y].length > 2 && lines[y][2] != ' ',
        isTrue,
        reason: 'column 2 of row $y: [${lines[y]}]',
      );
    }
  }, skip: 'probable bug confirmed: arch-theme-marks');
}
