// The counter of example/counter.dart: Up counts, q quits.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../../../example/hooks/counter.dart' show Counter;

void main() {
  testTwk('Up counts', (t) async {
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
    expect(t, styleAt(9, 2, allOf(hasAttr(Attr.bold), hasFg(Color.green))));
  });

  testTwk('q quits', (t) async {
    await t.pumpWidget(const Counter());
    await t.press('q');
    expect(t.isRunning, isFalse);
  });
}
