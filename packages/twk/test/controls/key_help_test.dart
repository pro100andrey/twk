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
}
