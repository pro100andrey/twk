// The chat of example/interactive.dart, full screen and inline: typing and
// sending, the list following the messages that come, Tab and clicks
// moving the focus, the wheel and the scrollbar, the keys shown with the
// mouse left to the terminal; Ctrl+C quits.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show MouseTracking, MouseTrackingBackend;
import 'package:twk_test/twk_test.dart';

import '../../example/interactive.dart' show Chat;

/// The panes' top left corners on a terminal 60 columns wide: the
/// messages, the people and the field.
const messages = (0, 0);
const people = (48, 0);
const field = (0, 10);

/// Whether the border of the pane at [corner] shows it has the focus.
Matcher focused((int, int) corner) =>
    styleAt(corner.$1, corner.$2, hasFg(theme.primary.fg!));

/// What the terminal reports of the mouse.
MouseTracking tracking(TwkTester t) =>
    (t.binding.twkApp.terminal as MouseTrackingBackend).mouseTracking;

/// The messages the list shows.
List<String> shown(TwkTester t) => [
  for (final line in t.lines.sublist(1, 9)) line.substring(2, 46).trimRight(),
];

/// The theme the app takes on the tests' terminal, a dark one: twk's own.
const ThemeData theme = ThemeData.dark;

void main() {
  testTwk('full screen, the newest messages at the end of the list, the '
      'field focused', (t) async {
    await t.pumpWidget(
      const Chat(),
      size: (60, 14),
      backgroundRgb: 0x16181d,
    );
    expect(
      t,
      matchesScreen('''
╭ Messages ────────────────────────────────────╮╭ People ──╮
│ ann: lunch at noon?                          ││  ann     │
│ bob: the release notes are up for review     ││  bob     │
│ cleo: who is on call this week?              ││  cleo    │
│ dev: me, ping me if anything breaks          ││  dev     │
│ eve: morning all                             ││  eve     │
│ finn: is the build green?                    ││  finn    │
│ gus: it is now, my bad                       ││  gus     │
│ hal: lunch at noon?                          ││  hal     │
╰──────────────────────────────────────────────╯╰──────────╯
╭ Write ───────────────────────────────────────────────────╮
│ a message, Enter sends it                                │
╰──────────────────────────────────────────────────────────╯
 tab next pane  enter send  f1 help  ctrl+c quit
'''),
    );
    expect(t, focused(field));
    expect(t, isNot(focused(messages)));
    expect(t, isNot(focused(people)));
    expect(t, cursorAt(2, 11));
    expect(t, styleAt(2, 8, allOf(hasAttr(Attr.bold), hasFg(Color.cyan))));
    // the scrollbar's thumb, at the end of its track
    expect(t, styleAt(46, 8, hasAttr(Attr.reverse)));
    expect(t, styleAt(46, 1, isNot(hasAttr(Attr.reverse))));
  });

  testTwk('Enter sends what is typed to the end of the list and empties the '
      'field; a blank message is not sent', (t) async {
    await t.pumpWidget(
      const Chat(),
      size: (60, 14),
      backgroundRgb: 0x16181d,
    );
    await t.type('hello there');
    await t.pump();
    expect(t, hasTextAt(2, 11, 'hello there'));
    expect(t, cursorAt(13, 11));

    // scrolled up, the list goes back to the end
    await t.mouse(MouseKind.wheelUp, 10, 4);
    await t.pump();
    expect(shown(t).last, 'eve: morning all');
    await t.press('enter');
    await t.pump();
    expect(shown(t).last, 'you: hello there');
    expect(t, styleAt(2, 8, allOf(hasAttr(Attr.bold), hasFg(Color.green))));
    expect(t, hasTextAt(2, 11, 'a message, Enter sends it'));

    final before = shown(t);
    await t.type('   ');
    await t.press('enter');
    await t.pump();
    expect(shown(t), before);
  });

  testTwk('the list keeps showing the messages that come while it shows the '
      'end; scrolled up by the wheel it stays, and follows again at the '
      'end', (t) async {
    await t.pumpWidget(
      const Chat(),
      size: (60, 14),
      backgroundRgb: 0x16181d,
    );
    await t.pump(const Duration(seconds: 2));
    expect(shown(t).last, 'ann: the release notes are up for review');

    await t.mouse(MouseKind.wheelUp, 10, 4);
    await t.pump();
    final scrolled = shown(t);
    expect(scrolled.last, 'finn: is the build green?');
    await t.pump(const Duration(seconds: 2));
    expect(shown(t), scrolled, reason: 'a message came, the list stayed');

    await t.mouse(MouseKind.wheelDown, 10, 4);
    await t.mouse(MouseKind.wheelDown, 10, 4);
    await t.pump();
    expect(shown(t).last, 'bob: who is on call this week?');
    await t.pump(const Duration(seconds: 2));
    expect(shown(t).last, 'cleo: me, ping me if anything breaks');
  });

  testTwk('Tab moves the focus from the field to the messages, the people '
      'and back, Shift+Tab the other way; the keys go to the pane focused, '
      'Enter on a name mentions it in the field', (t) async {
    await t.pumpWidget(
      const Chat(),
      size: (60, 14),
      backgroundRgb: 0x16181d,
    );
    await t.type('hi ');
    await t.press('tab');
    await t.pump();
    expect(t, focused(messages));
    expect(t, isNot(focused(field)));
    expect(t.cursorVisible, isFalse);
    await t.press('up');
    await t.pump();
    expect(shown(t).last, 'gus: it is now, my bad');

    await t.press('tab');
    await t.pump();
    expect(t, focused(people));
    await t.press('down');
    await t.pump();
    expect(t, styleAt(50, 2, hasBg(theme.selection.bg!)), reason: 'bob');

    await t.press('tab');
    await t.pump();
    expect(t, focused(field));
    await t.press('shift+tab shift+tab');
    await t.pump();
    expect(t, focused(messages));
    await t.press('tab');
    await t.pump();
    expect(t, focused(people));
    await t.press('enter');
    await t.pump();
    expect(t, focused(field));
    expect(t, hasTextAt(2, 11, 'hi @bob '));
    expect(t, cursorAt(10, 11));
  });

  testTwk('a click gives the focus to the pane clicked', (t) async {
    await t.pumpWidget(
      const Chat(),
      size: (60, 14),
      backgroundRgb: 0x16181d,
    );
    await t.click(20, 4);
    await t.pump();
    expect(t, focused(messages));
    expect(t, isNot(focused(field)));

    await t.click(51, 3);
    await t.pump();
    expect(t, focused(people));
    expect(
      t,
      styleAt(50, 3, hasBg(theme.selection.bg!)),
      reason: 'cleo clicked',
    );

    await t.click(30, 11);
    await t.pump();
    expect(t, focused(field));
    expect(t, cursorAt(2, 11));
  });

  testTwk("the scrollbar's thumb dragged scrolls the list, which takes the "
      'focus', (t) async {
    await t.pumpWidget(
      const Chat(),
      size: (60, 14),
      backgroundRgb: 0x16181d,
    );
    await t.mouse(MouseKind.down, 46, 8);
    await t.mouse(MouseKind.drag, 46, 1);
    await t.mouse(MouseKind.up, 46, 1);
    await t.pump();
    expect(shown(t).first, 'ann: morning all');
    expect(t, styleAt(46, 1, hasAttr(Attr.reverse)));
    expect(t, focused(messages));
  });

  testTwk('F1 shows the keys in place of the panes, the mouse left to the '
      'terminal; F1 again brings the panes back, with what was typed', (
    t,
  ) async {
    await t.pumpWidget(
      const Chat(),
      size: (60, 14),
      backgroundRgb: 0x16181d,
    );
    expect(tracking(t), MouseTracking.drags);
    await t.type('a draft');
    await t.press('f1');
    await t.pump();
    expect(
      t,
      matchesScreen('''
╭ Keys ────────────────────────────────────────────────────╮
│ tab, shift+tab  the next pane, the one before            │
│ enter           send the message, mention the name       │
│ ↑ ↓ pgup pgdn   scroll the messages, move in the names   │
│ home, end       to the first, to the last                │
│ click           focus the pane                           │
│ wheel, drag     scroll the list under the mouse          │
│ f1              back to the chat                         │
│ ctrl+c          quit                                     │
│                                                          │
│ Nothing here uses the mouse: select text as in any       │
│ terminal.                                                │
╰──────────────────────────────────────────────────────────╯
 tab next pane  enter send  f1 back  ctrl+c quit
'''),
    );
    expect(tracking(t), MouseTracking.off);
    expect(t.written(), endsWith('\x1b[?1002l\x1b[?1006l'));

    await t.press('f1');
    await t.pump();
    expect(tracking(t), MouseTracking.drags);
    expect(t, hasTextAt(2, 11, 'a draft'));
    expect(t, focused(field));
  });

  testTwk('Ctrl+C quits', (t) async {
    await t.pumpWidget(
      const Chat(),
      size: (60, 14),
      backgroundRgb: 0x16181d,
    );
    await t.press('ctrl+c');
    expect(t.isRunning, isFalse);
  });

  testTwk('inline, 16 rows below the history, the mouse left to the '
      'terminal; Tab and typing work, and the chat stays when Ctrl+C '
      'quits', (t) async {
    await t.pumpWidget(
      const SizedBox(height: 16, child: Chat()),
      size: (60, 24),
      mode: ScreenMode.inline,
      history: [r'$ dart run example/interactive.dart --inline'],
      backgroundRgb: 0x16181d,
    );
    await t.type('hi all');
    await t.press('enter');
    await t.press('tab');
    await t.pump();
    await t.press('ctrl+c');
    expect(t.isRunning, isFalse);
    expect(
      t,
      matchesScreen(r'''
$ dart run example/interactive.dart --inline
╭ Messages ────────────────────────────────────╮╭ People ──╮
│ hal: it is now, my bad                       ││  ann     │
│ ann: lunch at noon?                          ││  bob     │
│ bob: the release notes are up for review     ││  cleo    │
│ cleo: who is on call this week?              ││  dev     │
│ dev: me, ping me if anything breaks          ││  eve     │
│ eve: morning all                             ││  finn    │
│ finn: is the build green?                    ││  gus     │
│ gus: it is now, my bad                       ││  hal     │
│ hal: lunch at noon?                          ││          │
│ you: hi all                                  ││          │
╰──────────────────────────────────────────────╯╰──────────╯
╭ Write ───────────────────────────────────────────────────╮
│ a message, Enter sends it                                │
╰──────────────────────────────────────────────────────────╯
 tab next pane  enter send  f1 help  ctrl+c quit
'''),
    );
    expect(t.written(), isNot(contains('\x1b[?100')));
  });
}
