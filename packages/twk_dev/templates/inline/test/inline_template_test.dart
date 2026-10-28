import 'package:inline_template/inline_template.dart';
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// Starts the chat inline in [rows] rows below the shell's prompt.
Future<void> start(TwkTester t, {int rows = 6}) => t.pumpWidget(
  const Chat(),
  size: (50, rows),
  mode: ScreenMode.inline,
  history: [r'$ dart run bin/main.dart'],
);

void main() {
  testTwk('a line sent shows above the field with a spinner, then the '
      'answer once the app has thought', (t) async {
    await start(t);
    await t.type('hello there');
    await t.press('enter');
    await t.pump();
    expect(t, containsLine('> hello there'));
    expect(find.byType(Spinner), findsOneWidget);

    await t.pump(thinking);
    expect(t, containsLine(answer('hello there')));
    expect(find.byType(Spinner), findsNothing);
  });

  testTwk('what was said goes to the scrollback, the field stays', (t) async {
    await start(t, rows: 3);
    for (final line in ['one', 'two']) {
      await t.type(line);
      await t.press('enter');
      await t.pump(thinking);
    }
    expect(t.scrollback, [
      r'$ dart run bin/main.dart',
      '> one',
      answer('one'),
      '> two',
    ]);
    expect(t.lines, [
      answer('two'),
      'say something, Enter sends it',
      // the field's keys first: Ctrl+Z puts back what was sent
      'enter submit   ctrl+z undo   ctrl+q quit',
    ]);
  });

  testTwk('the field takes q; Ctrl+Q quits', (t) async {
    await start(t);
    await t.type('q');
    await t.pump();
    expect(t, containsLine('q'));
    await t.press('ctrl+q');
    expect(t.isRunning, isFalse);
  });
}
