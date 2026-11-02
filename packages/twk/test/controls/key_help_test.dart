// showKeyHelp: the keys in force where it is called, with their hints, a
// line each, in a dialog that Escape closes; the keys of the screen under
// it, not the dialog's own.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// A screen with keys of its own and `?` for the help.
final class Editor extends StatelessWidget {
  const Editor({super.key});

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      'ctrl+s': () {},
      'up': () {},
      'down': () {},
      'g g': () {},
      'f2': () {},
      '?': () => showKeyHelp(context),
    },
    hints: const {
      'ctrl+s': 'save',
      'up': 'move',
      'down': 'move',
      'g g': 'top',
      '?': 'help',
    },
    child: const Focus(autofocus: true, child: Text('editor')),
  );
}

void main() {
  testTwk('the keys in force with their hints, a line each, in bold; Escape '
      'closes it', (t) async {
    await t.pumpWidget(
      const App(child: Editor()),
      size: (40, 12),
    );
    await t.press('?');
    await t.pumpUntilIdle();
    expect(t, containsLine(contains('Keys')));
    expect(t, containsLine(matches(r'ctrl\+s\s+save')));
    expect(t, containsLine(matches(r'↑↓\s+move')));
    expect(t, containsLine(matches(r'g g\s+top')));
    expect(t, containsLine(matches(r'\?\s+help')));
    expect(t.lines.join('\n'), isNot(contains('f2')), reason: 'no hint');
    final row = t.lines.indexWhere((l) => l.contains('save'));
    final x = t.lines[row].indexOf('ctrl+s');
    expect(t.cell(x, row).attrs & Attr.bold, Attr.bold);
    await t.press('escape');
    await t.pumpUntilIdle();
    expect(t.lines.join('\n'), isNot(contains('save')));
  });

  testTwk('the keys of each layer apart, the nearest first, a blank line '
      'between', (t) async {
    await t.pumpWidget(
      App(
        child: KeyBindings(
          {'q': () {}},
          hints: const {'q': 'quit'},
          child: Builder(
            builder: (context) => KeyBindings(
              {'ctrl+s': () {}, '?': () => showKeyHelp(context)},
              hints: const {'ctrl+s': 'save', '?': 'help'},
              child: const Focus(autofocus: true, child: Text('editor')),
            ),
          ),
        ),
      ),
      size: (40, 14),
    );
    await t.press('?');
    await t.pumpUntilIdle();
    final save = t.lines.indexWhere((l) => l.contains('save'));
    final help = t.lines.indexWhere((l) => l.contains('help'));
    final quit = t.lines.indexWhere((l) => l.contains('quit'));
    expect(save, isNonNegative);
    expect(help, save + 1);
    expect(quit, help + 2, reason: 'one blank line between the layers');
    expect(
      t.lines[help + 1].replaceAll(RegExp('[^ ]'), '').length,
      t.lines[help + 1].length,
      reason: 'the gap is blank inside the box',
    );
  });

  testTwk('its own Escape is the last line, a layer apart, even with no key '
      'in force', (t) async {
    await t.pumpWidget(
      const App(child: Editor()),
      size: (40, 14),
    );
    await t.press('?');
    await t.pumpUntilIdle();
    final help = t.lines.indexWhere((l) => l.contains('help'));
    final close = t.lines.indexWhere((l) => RegExp(r'esc\s+close').hasMatch(l));
    expect(close, help + 2, reason: "one blank line after the screen's keys");
    await t.press('escape');
    await t.pumpUntilIdle();
    await t.pumpWidget(
      App(
        child: Builder(
          builder: (context) => KeyBindings(
            {'x': () => showKeyHelp(context)},
            child: const Focus(autofocus: true, child: Text('bare')),
          ),
        ),
      ),
      size: (40, 10),
    );
    await t.press('x');
    await t.pumpUntilIdle();
    expect(t, containsLine(matches(r'esc\s+close')));
  });
}
