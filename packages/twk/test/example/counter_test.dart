// The counter of example/counter.dart, full screen and inline: Up counts,
// q quits.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../../example/counter.dart' show Counter;

void main() {
  testTwk('full screen, the box fills the terminal and Up counts', (t) async {
    await t.pumpWidget(const Counter(), size: (24, 6));
    expect(
      t,
      matchesScreen('''
╭──────────────────────╮
│                      │
│ Count: 0             │
│                      │
│                      │
╰── up: count  q: quit ╯
'''),
    );

    await t.press('up up up');
    await t.pump();
    expect(t, containsLine('│ Count: 3             │'));
    expect(t, styleAt(2, 2, hasAttr(Attr.dim)));
    expect(t, styleAt(9, 2, allOf(hasAttr(Attr.bold), hasFg(Color.green))));
  });

  testTwk('q quits', (t) async {
    await t.pumpWidget(const Counter());
    await t.press('q');
    expect(t.isRunning, isFalse);
  });

  testTwk('inline, the box is as tall as its text, below the history, and '
      'stays there when q quits', (t) async {
    await t.pumpWidget(
      const Counter(),
      size: (44, 10),
      mode: ScreenMode.inline,
      history: [r'$ dart run example/counter.dart --inline'],
    );
    await t.press('up');
    await t.pump();
    await t.press('q');
    expect(t.isRunning, isFalse);
    expect(
      t,
      matchesScreen(r'''
$ dart run example/counter.dart --inline
╭──────────────────────────────────────────╮
│                                          │
│ Count: 1                                 │
│                                          │
╰────────────────────── up: count  q: quit ╯
'''),
    );
  });
}
