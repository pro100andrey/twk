// A key pressed from code (AppBinding.pressKey): handled as one the
// terminal sent, by the bindings on the focus's key path, a sequence one
// key at a time; a capital letter as a terminal sends it; a tap on a hint
// of a bar of the app's own runs what its key is bound to.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// A row of the active keys' hints, each pressing its key when tapped.
final class HintRow extends StatelessWidget {
  const HintRow({super.key});

  @override
  Widget build(BuildContext context) {
    final binding = AppBinding.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      gap: 1,
      children: [
        for (final key in binding.focusManager.activeKeys)
          if (key.hint case final hint?)
            GestureDetector(
              onTap: (_) {
                for (final combo in [key.combo, ...key.then]) {
                  binding.pressKey(combo);
                }
              },
              child: Text(hint),
            ),
      ],
    );
  }
}

void main() {
  testTwk('a key pressed from code is bound as a key pressed is; the keys '
      'of a sequence one at a time', (t) async {
    final seen = <String>[];
    await t.pumpWidget(
      KeyBindings(
        {
          'ctrl+s': () => seen.add('save'),
          'g g': () => seen.add('top'),
        },
        child: const Focus(autofocus: true, child: Text('x')),
      ),
    );
    final binding = t.binding;
    await t.act(() => binding.pressKey(KeyCombo.parse('ctrl+s')));
    expect(seen, ['save']);
    await t.act(() {
      for (final key in KeyCombo.parseSequence('g g')) {
        binding.pressKey(key);
      }
    });
    expect(seen, ['save', 'top']);
  });

  testTwk('a capital letter comes as a terminal sends it, with Shift', (
    t,
  ) async {
    final events = <KeyEvent>[];
    await t.pumpWidget(
      Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          events.add(event);
          return KeyEventResult.handled;
        },
        child: const Text('x'),
      ),
    );
    await t.act(() => t.binding.pressKey(KeyCombo.parse('A')));
    expect(events, [
      const KeyEvent(KeyCode.char, char: 'A', modifiers: Mod.shift),
    ]);
  });

  testTwk('a tap on a hint of a bar of its own runs what the key is bound '
      'to', (t) async {
    final seen = <String>[];
    await t.pumpWidget(
      KeyBindings(
        {
          'ctrl+s': () => seen.add('save'),
          'ctrl+x ctrl+q': () => seen.add('quit'),
        },
        hints: const {'ctrl+s': 'save', 'ctrl+x ctrl+q': 'quit'},
        child: const Focus(autofocus: true, child: HintRow()),
      ),
      size: (20, 1),
    );
    expect(t.lines, ['save quit']);
    await t.clickOn(find.text('quit'));
    expect(seen, ['quit']);
    await t.clickOn(find.text('save'));
    expect(seen, ['quit', 'save']);
  });
}
