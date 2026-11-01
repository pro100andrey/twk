// A pressable key hints bar: a click on a key presses it, a sequence key by
// key, on the sign of a key joined with others that key, on a hint the key
// of an entry of one key; a bar left as it is listens to no mouse.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show MouseTracking, MouseTrackingBackend;
import 'package:twk_test/twk_test.dart';

import '../text/ambiguous.dart';

MouseTracking tracking(TwkTester t) =>
    (t.binding.twkApp.terminal as MouseTrackingBackend).mouseTracking;

/// Keys noted in [seen] as they are pressed, and a bar of their hints.
Widget bar(List<String> seen, {bool pressable = true}) => KeyBindings(
  {
    'ctrl+s': () => seen.add('save'),
    'up': () => seen.add('up'),
    'down': () => seen.add('down'),
    'g g': () => seen.add('top'),
  },
  hints: const {
    'ctrl+s': 'save',
    'up': 'move',
    'down': 'move',
    'g g': 'top',
  },
  child: Focus(
    autofocus: true,
    child: KeyHintsBar(pressable: pressable),
  ),
);

/// The column of [text] in the bar's row.
int at(TwkTester t, String text) => t.lines.first.indexOf(text);

void main() {
  testTwk('a click on a key presses it; on the sign of a joined key that '
      'key; on a hint the key of an entry of one; a sequence key by key', (
    t,
  ) async {
    final seen = <String>[];
    await t.pumpWidget(bar(seen), size: (50, 1));
    expect(t.lines, ['ctrl+s save   ↑↓ move   g g top']);
    await t.click(at(t, 'ctrl+s'), 0);
    await t.click(at(t, '↓'), 0);
    await t.click(at(t, '↑'), 0);
    await t.click(at(t, 'top'), 0);
    expect(seen, ['save', 'down', 'up', 'top']);
    // the hint of the joined arrows presses neither
    await t.click(at(t, 'move'), 0);
    // the blanks between entries press nothing
    await t.click(at(t, 'save') + 6, 0);
    expect(seen, hasLength(4));
  });

  test('on a terminal that takes the arrows for two columns, a click '
      'presses the key drawn under it', () async {
    final seen = <String>[];
    final app = await WideApp.start(bar(seen), width: 50, height: 1);
    // ctrl+s save, then ↑↓ in columns 14-17, move, then g g top from 26
    await app.click(17, 0);
    await app.click(32, 0);
    await app.click(14, 0);
    await app.quit();
    expect(seen, ['down', 'top', 'up']);
  });

  testTwk('a bar that is not pressable has the terminal report no mouse', (
    t,
  ) async {
    final seen = <String>[];
    await t.pumpWidget(bar(seen, pressable: false), size: (50, 1));
    expect(tracking(t), MouseTracking.off);
    await t.pumpWidget(bar(seen), size: (50, 1));
    expect(tracking(t), isNot(MouseTracking.off));
  });

  testTwk('the ellipsis of a cut bar presses nothing: not in a hint it cuts, '
      'not in a key name', (t) async {
    final seen = <String>[];
    await t.pumpWidget(bar(seen), size: (10, 1));
    expect(t.lines, ['ctrl+s sa…']);
    // the shown letters of the hint still press, the ellipsis does not
    await t.click(8, 0);
    expect(seen, ['save']);
    await t.click(9, 0);
    expect(seen, ['save']);
    await t.pumpWidget(bar(seen), size: (4, 1));
    expect(t.lines, ['ctr…']);
    await t.click(2, 0);
    await t.click(3, 0);
    expect(seen, ['save', 'save']);
  });
}
