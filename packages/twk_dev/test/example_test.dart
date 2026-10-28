// The tally of example/tally.dart, the app the README walks through the
// tools with: Up and Down choose a line, + and - count it, each count in
// the app's log, q quits; a hot reload's reassemble keeps the counts.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../example/tally.dart' show Tally;

const _names = ['coffee', 'tea', 'water'];

void main() {
  testTwk('a line for each name, the first chosen; + and - count the line '
      'chosen, as a number and a bar, Up and Down choose', (t) async {
    await t.pumpWidget(const Tally(_names), size: (32, 6));
    expect(
      t,
      matchesScreen('''
╭ tally ───────────────────────╮
│ › coffee     0               │
│   tea        0               │
│   water      0               │
│                              │
╰─────────── + - count  q quit ╯
'''),
    );

    await t.press('+ + down + + + - up up');
    await t.pump();
    expect(
      t,
      matchesScreen('''
╭ tally ───────────────────────╮
│   coffee     2 ■■            │
│   tea        2 ■■            │
│ › water      0               │
│                              │
╰─────────── + - count  q quit ╯
'''),
    );
    expect(t, styleAt(4, 3, hasAttr(Attr.bold)));
    expect(t, styleAt(4, 1, isNot(hasAttr(Attr.bold))));
    expect(t, styleAt(17, 1, hasFg(Color.green)));
  });

  testTwk('- stops at 0', (t) async {
    await t.pumpWidget(const Tally(_names), size: (32, 6));
    await t.press('- + - -');
    await t.pump();
    expect(t, containsLine('│ › coffee     0               │'));
  });

  testTwk('each count goes to the log', (t) async {
    await t.pumpWidget(const Tally(_names));
    await t.press('+ down + + -');
    await t.pump();
    expect(
      [for (final r in t.logs.records) r.message],
      [
        'coffee: 1',
        'tea: 1',
        'tea: 2',
        'tea: 1',
      ],
    );
  });

  testTwk('the counts and the line chosen are kept by a reassemble, which a '
      'hot reload calls', (t) async {
    await t.pumpWidget(const Tally(_names), size: (32, 6));
    await t.press('down + + +');
    await t.pump();
    t.binding.reassemble();
    await t.pump();
    expect(t, containsLine('│ › tea        3 ■■■           │'));
  });

  testTwk('q quits', (t) async {
    await t.pumpWidget(const Tally(_names));
    await t.press('q');
    expect(t.isRunning, isFalse);
  });
}
