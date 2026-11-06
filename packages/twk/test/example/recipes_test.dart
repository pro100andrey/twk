// The recipes' tests: the Recipes guide.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../../example/guides/recipes.dart';

void main() {
  testTwk('a dialog asks first, a toast says it is done', (t) async {
    await t.pumpWidget(app, size: (40, 12));
    await t.press('enter');
    // a dialog fades in over 160 ms: at its first frame it is not seen yet
    await t.pump(const Duration(milliseconds: 200));
    expect(t, containsLine(contains('Delete the file?')));
    // Cancel has the focus: Shift+Tab goes back to Delete
    await t.press('shift+tab enter');
    // a toast slides in from the right over 200 ms
    await t.pump(const Duration(milliseconds: 300));
    expect(t, containsLine(contains('Deleted.')));
  });

  testTwk('the table sorts by a click on a title', (t) async {
    await t.pumpWidget(
      entryTable(const [Entry('b.txt', 10), Entry('a.txt', 200)]),
      size: (20, 4),
    );
    await t.clickOn(find.text('name'));
    await t.pump();
    expect(
      t,
      matchesScreen('''
name ▴     size
a.txt       200
b.txt        10
'''),
    );
    await t.press('down enter');
    expect(t.logs.records.last.message, 'open a.txt');
  });

  testTwk('inline, the lines sent go to the scrollback', (t) async {
    await t.pumpWidget(
      const Prompt(),
      size: (30, 3),
      mode: ScreenMode.inline,
      history: [r'$ my_app'],
    );
    for (final line in ['one', 'two', 'three']) {
      await t.type(line);
      await t.press('enter');
      await t.pump();
    }
    expect(t.scrollback, [r'$ my_app', '> one']);
    expect(t.lines, ['> two', '> three', '']);
  });

  testTwk('the clock moves only when the test moves it', (t) async {
    await t.pumpWidget(const Uptime());
    await t.pump(const Duration(seconds: 3));
    expect(t, containsLine('up 3s'));
  });
}
