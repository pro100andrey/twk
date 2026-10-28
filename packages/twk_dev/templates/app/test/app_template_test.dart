import 'package:app_template/app_template.dart';
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk('the notes in a list, the first chosen and shown beside it', (
    t,
  ) async {
    await t.pumpWidget(const NotesApp(notes), size: (60, 12));
    expect(t, containsLine(startsWith(' $appName ')));
    expect(find.text('Hot reload'), findsOneWidget);
    expect(t, containsLine(contains('╭ Welcome ')));
    expect(t, containsLine('enter open   ctrl+q quit'));
  });

  testTwk('Down chooses the next note, Up the one before', (t) async {
    await t.pumpWidget(const NotesApp(notes), size: (60, 12));
    await t.press('down down');
    await t.pump();
    expect(t, containsLine(contains('╭ Code ')));

    await t.press('up');
    await t.pump();
    expect(t, containsLine(contains('╭ Keys ')));
  });

  testTwk('Enter opens the note, Escape goes back to the list', (t) async {
    await t.pumpWidget(const NotesApp(notes), size: (60, 12));
    await t.press('enter');
    await t.pump();
    expect(t, containsLine('esc back   ctrl+q quit'));
    // the note's border in the theme's primary color, the list's not: the
    // terminal of the test says no background, so the app is in its own
    // colors, where that is blue
    expect(t, styleAt(24, 1, hasFg(Color.blue)));
    expect(t, styleAt(0, 1, isNot(hasFg(Color.blue))));

    await t.press('escape down');
    await t.pump();
    expect(t, containsLine(contains('╭ Keys ')));
  });

  testTwk('Ctrl+Q quits', (t) async {
    await t.pumpWidget(const NotesApp(notes));
    await t.press('ctrl+q');
    expect(t.isRunning, isFalse);
  });
}
