// A key hints bar from fixed (key, hint) pairs: drawn, joined and cut as the
// bar of the keys in force is, and pressable the same, with nothing bound.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// Keys that arrive at the app's focus, noted in [seen].
Widget app(List<String> seen, Widget bar) => Focus(
  autofocus: true,
  onKeyEvent: (node, event) {
    seen.add('${KeyCombo.fromEvent(event)}');
    return KeyEventResult.handled;
  },
  child: bar,
);

const pairs = [
  ('ctrl+s', 'save'),
  ('up', 'move'),
  ('down', 'move'),
  ('g g', 'top'),
  ('f1', ''),
];

void main() {
  testTwk('draws the pairs as the bar of the keys in force does: joined, a '
      'sequence whole, a key without a hint alone; no focus needed', (t) async {
    await t.pumpWidget(const KeyHintsBar.fromPairs(pairs), size: (60, 1));
    expect(t.lines, ['ctrl+s save   ↑↓ move   g g top   f1']);
    await t.pumpWidget(
      const KeyHintsBar.fromPairs(pairs, joinKeys: false, separator: ' | '),
      size: (70, 1),
    );
    expect(t.lines, ['ctrl+s save | ↑ move | ↓ move | g g top | f1']);
  });

  testTwk('is cut with an ellipsis as the other bar is', (t) async {
    await t.pumpWidget(const KeyHintsBar.fromPairs(pairs), size: (10, 1));
    expect(t.lines, ['ctrl+s sa…']);
  });

  testTwk('pressable: a click presses the key, a sequence key by key, though '
      'nothing binds it; not pressable, no mouse', (t) async {
    final seen = <String>[];
    await t.pumpWidget(
      app(seen, const KeyHintsBar.fromPairs(pairs, pressable: true)),
      size: (60, 1),
    );
    int at(String s) => t.lines.first.indexOf(s);
    await t.click(at('ctrl+s'), 0);
    await t.click(at('top'), 0);
    await t.click(at('↓'), 0);
    expect(seen, ['ctrl+s', 'g', 'g', 'down']);
    // the blanks between entries, and a hint of joined keys, press nothing
    await t.click(at('save') + 6, 0);
    await t.click(at('move'), 0);
    expect(seen, hasLength(4));
    // not pressable: a click presses nothing
    await t.pumpWidget(app(seen, const KeyHintsBar.fromPairs(pairs)));
    await t.click(0, 0);
    expect(seen, hasLength(4));
  });
}
