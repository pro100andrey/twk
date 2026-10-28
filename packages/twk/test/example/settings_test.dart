// The settings of example/settings.dart: the menu bar by the keys and by
// the mouse, the tabs, the form of switches, checkboxes and radio buttons
// saved and reverted, the context menu at the mouse and at the focus, the
// cache cleared only once a dialog confirms it, a spinner while it is,
// then a toast and a desktop notification; Ctrl+Q and File ▸ Quit quit.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../../example/settings.dart' show SettingsApp, clearingTime;

/// The terminal the tests run the app on.
const size = (72, 13);

/// How long a switch's knob takes to run to its other end, and some.
const knob = Duration(milliseconds: 200);

/// How long a toast takes to slide in, and some.
const slide = Duration(milliseconds: 300);

/// How long a menu takes to fade in, and some.
const fade = Duration(milliseconds: 150);

/// Presses each of [keys], a frame after each.
Future<void> press(TwkTester t, String keys) async {
  for (final key in keys.split(' ')) {
    await t.press(key);
    await t.pump();
  }
}

/// Clicks [x], [y] with [button] and pumps a frame.
Future<void> click(TwkTester t, int x, int y, {int button = 0}) async {
  await t.click(x, y, button: button);
  await t.pump();
}

/// The text of the [width] × [height] cells from [x], [y] on, a line for
/// each row.
List<String> textAt(TwkTester t, int x, int y, int width, int height) => [
  for (final line in t.lines.sublist(y, y + height))
    line.padRight(x + width).substring(x, x + width),
];

/// The theme the app takes on the tests' terminal, a dark one.
const ThemeData theme = ThemeData.dark;

/// Whether the row [y] shows the focus from the column [x] on: a tab
/// filled with the primary color, a setting on the selection's color.
Matcher focusedAt(int x, int y) => styleAt(
  x,
  y,
  anyOf(hasBg(theme.primary.fg!), hasBg(theme.selection.bg!)),
);

/// Whether the cell [x], [y] is in the theme's muted color: what is
/// disabled, or says little.
Matcher mutedAt(int x, int y) => styleAt(x, y, hasFg(theme.muted.fg!));

/// Whether the button at the column [x] of the row [y] has the focus: its
/// chip filled with the primary color.
Matcher buttonFocusedAt(int x, int y) =>
    styleAt(x, y, hasBg(theme.primary.fg!));

/// The status bar.
String status(TwkTester t) => t.lines.last;

void main() {
  testTwk('the settings of the first tab under the menu bar and the tabs, '
      'the tabs focused; the status bar says all is saved', (t) async {
    await t.pumpWidget(
      const SettingsApp(),
      size: size,
      backgroundRgb: 0x16181d,
    );
    expect(
      t,
      matchesScreen('''
 File  View  Tools
 General  Editor  Privacy
╭──────────────────────────────────────────────────────────────────────╮
│ ▐  ●▌ save automatically                                             │
│ [x] check for updates                                                │
│                                                                      │
│ On startup, open                                                     │
│ (●) the files open last                                              │
│ ( ) an empty window                                                  │
│ ( ) the welcome page                                                 │
│                                                                      │
╰──────────────────────────────────────────────────────────────────────╯
 saved                                f10 menu  ctrl+s save  ctrl+q quit
'''),
    );
    expect(t, focusedAt(1, 1), reason: 'General, the bar focused');
    expect(t, mutedAt(1, 12), reason: 'saved, muted');
  });

  testTwk('Right and Left switch the tabs; Tab goes on to the settings of '
      'the tab shown, and from the last back to the tabs', (t) async {
    await t.pumpWidget(
      const SettingsApp(),
      size: size,
      backgroundRgb: 0x16181d,
    );
    await press(t, 'right');
    expect(t, hasTextAt(2, 3, '[ ] wrap lines'));
    expect(t, hasTextAt(2, 8, '(●) 2 spaces  ( ) 4 spaces  ( ) a tab'));
    expect(t, focusedAt(10, 1), reason: 'Editor');
    await press(t, 'right');
    expect(t, hasTextAt(2, 3, '▐  ●▌ send crash reports'));
    expect(t, hasTextAt(2, 6, 'The cache holds 128 files.'));
    await press(t, 'right');
    expect(t, hasTextAt(2, 3, '▐  ●▌ save automatically'));
    await press(t, 'left');
    expect(t, hasTextAt(2, 3, '▐  ●▌ send crash reports'));

    await press(t, 'tab');
    expect(t, focusedAt(2, 3), reason: 'the switch');
    expect(t, isNot(focusedAt(18, 1)));
    await press(t, 'tab');
    expect(t, focusedAt(2, 4), reason: 'the checkbox');
    await press(t, 'tab');
    expect(t, buttonFocusedAt(2, 7), reason: 'the button');
    await press(t, 'tab');
    expect(t, focusedAt(18, 1), reason: 'Privacy, the bar focused');
  });

  testTwk('Alt+V opens the View menu, the tab shown checked; a mnemonic '
      'shows another; F10 and Right open it too', (t) async {
    await t.pumpWidget(
      const SettingsApp(),
      size: size,
      backgroundRgb: 0x16181d,
    );
    await press(t, 'alt+v');
    await t.pump(fade);
    expect(textAt(t, 6, 1, 13, 5), [
      '             ',
      '▎ ✓ General  ',
      '    Editor   ',
      '    Privacy  ',
      '             ',
    ]);
    await press(t, 'p');
    expect(t, hasTextAt(2, 3, '▐  ●▌ send crash reports'));
    expect(t, focusedAt(18, 1), reason: 'the focus back on the tabs');

    await press(t, 'f10 right');
    await t.pump(fade);
    expect(t, hasTextAt(6, 4, '  ✓ Privacy'));
    await press(t, 'e');
    expect(t, hasTextAt(2, 3, '[ ] wrap lines'));
  });

  testTwk('a click on a title opens its menu, each item with its key, '
      'Revert muted while nothing changed; a click on an item chooses '
      'it', (t) async {
    await t.pumpWidget(
      const SettingsApp(),
      size: size,
      backgroundRgb: 0x16181d,
    );
    await click(t, 2, 0);
    await t.pump(fade);
    expect(textAt(t, 0, 1, 18, 6), [
      '                  ',
      '  Save    ctrl+s  ',
      '  Revert          ',
      ' ──────────────── ',
      '  Quit    ctrl+q  ',
      '                  ',
    ]);
    expect(t, mutedAt(2, 3), reason: 'Revert');
    expect(t, isNot(mutedAt(2, 2)), reason: 'Save');
    await click(t, 4, 3);
    expect(t, containsLine(contains('Revert')), reason: 'not chosen');

    await click(t, 4, 2);
    expect(t, hasTextAt(2, 3, '▐  ●▌ save automatically'), reason: 'closed');
    await t.pump(slide);
    expect(t, containsLine(contains('▌ The settings are saved.  ')));
  });

  testTwk('a change marks the form modified; Ctrl+S saves it, which a '
      'toast says; changed again, on any tab, File ▸ Revert puts back what '
      'was saved', (t) async {
    await t.pumpWidget(
      const SettingsApp(),
      size: size,
      backgroundRgb: 0x16181d,
    );
    await press(t, 'tab space');
    await t.pump(knob);
    expect(t, hasTextAt(2, 3, '▐●  ▌ save automatically'));
    expect(status(t), startsWith(' modified '));
    expect(t, styleAt(1, 12, hasFg(theme.warning.fg!)));
    await click(t, 3, 4);
    expect(t, hasTextAt(2, 4, '[ ] check for updates'));
    await press(t, 'tab down');
    expect(t, hasTextAt(2, 8, '(●) an empty window'));

    await press(t, 'ctrl+s');
    expect(status(t), startsWith(' saved '));
    await t.pump(slide);
    expect(t, containsLine(contains('▌ The settings are saved.  ')));

    await press(t, 'down');
    expect(t, hasTextAt(2, 9, '(●) the welcome page'));
    await click(t, 3, 3);
    await t.pump(knob);
    expect(t, hasTextAt(2, 3, '▐  ●▌ save automatically'));
    await click(t, 12, 1);
    await click(t, 3, 3);
    expect(t, hasTextAt(2, 3, '[x] wrap lines'));
    expect(status(t), startsWith(' modified '));

    await press(t, 'f10 r');
    expect(t, hasTextAt(2, 3, '[ ] wrap lines'));
    expect(status(t), startsWith(' saved '));
    await click(t, 3, 1);
    await t.pump(knob);
    expect(t, hasTextAt(2, 3, '▐●  ▌ save automatically'));
    expect(t, hasTextAt(2, 4, '[ ] check for updates'));
    expect(t, hasTextAt(2, 8, '(●) an empty window'));
  });

  testTwk('a right click on the settings opens the context menu at the '
      'mouse; Shift+F10 opens it under the setting focused, and Escape '
      'gives the focus back', (t) async {
    await t.pumpWidget(
      const SettingsApp(),
      size: size,
      backgroundRgb: 0x16181d,
    );
    await click(t, 30, 8, button: 2);
    await t.pump(fade);
    // above the mouse, where it does not fit below
    expect(textAt(t, 30, 3, 28, 6), [
      '                            ',
      '  Save              ctrl+s  ',
      '  Revert                    ',
      ' ────────────────────────── ',
      '  Clear the cache…          ',
      '                            ',
    ]);
    await press(t, 'escape');

    await press(t, 'tab space');
    await press(t, 'shift+f10');
    await t.pump(fade);
    expect(textAt(t, 2, 4, 28, 6), [
      '                            ',
      '▎ Save              ctrl+s  ',
      '  Revert                    ',
      ' ────────────────────────── ',
      '  Clear the cache…          ',
      '                            ',
    ]);
    await press(t, 'escape');
    expect(t, focusedAt(2, 3), reason: 'the switch');
    await press(t, 'shift+f10 r');
    await t.pump(knob);
    expect(t, hasTextAt(2, 3, '▐  ●▌ save automatically'), reason: 'reverted');
  });

  testTwk('clearing the cache asks first: Cancel, focused, and Escape keep '
      'the files', (t) async {
    await t.pumpWidget(
      const SettingsApp(),
      size: size,
      backgroundRgb: 0x16181d,
    );
    await press(t, 'alt+t enter');
    // the dialog fades in
    await t.pump(slide);
    expect(textAt(t, 17, 3, 38, 7), [
      '                                      ',
      '  Clear the cache                     ',
      '  Delete the 128 files of the cache?  ',
      '  This cannot be undone.              ',
      '                                      ',
      '   Cancel    Delete                   ',
      '                                      ',
    ]);
    expect(t, buttonFocusedAt(20, 8), reason: 'Cancel');
    expect(t, styleAt(30, 8, hasFg(theme.error.fg!)), reason: 'Delete');
    await press(t, 'enter');
    expect(t, isNot(containsLine(contains('Clear the cache'))));
    expect(t, focusedAt(1, 1), reason: 'the focus back on the tabs');

    await click(t, 20, 1);
    await click(t, 5, 7);
    await t.pump(slide);
    expect(t, containsLine(contains('Delete the 128 files of the cache?')));
    await press(t, 'escape');
    await t.pump(clearingTime);
    expect(t, hasTextAt(2, 6, 'The cache holds 128 files.'));
    expect(status(t), isNot(contains('clearing')));
  });

  testTwk('confirmed, the cache is cleared while a spinner turns in the '
      'status bar; then a toast says it is done, and a desktop '
      'notification', (t) async {
    await t.pumpWidget(
      const SettingsApp(),
      size: size,
      notifications: NotificationProtocol.osc777,
      backgroundRgb: 0x16181d,
    );
    await click(t, 20, 1);
    await click(t, 5, 7);
    await press(t, 'tab');
    await t.pump(slide);
    expect(t, styleAt(30, 8, hasBg(theme.error.fg!)), reason: 'Delete');
    await press(t, 'enter');
    expect(status(t), contains(' clearing the cache… '));
    final spinner = status(t)[16];
    await t.pump(const Duration(milliseconds: 100));
    expect(status(t)[16], isNot(spinner));
    expect(t, mutedAt(3, 7), reason: 'the button');
    await press(t, 'alt+t');
    await t.pump(fade);
    expect(t, mutedAt(14, 2), reason: 'the item');
    await press(t, 'escape');
    expect(t.written(), isNot(contains('\x1b]777')));

    await t.pump(clearingTime);
    await t.pump(slide);
    expect(
      t,
      matchesScreen('''
 File  View  Tools
 General  Editor  Privacy
╭──────────────────────────────────────────────────────────────────────╮
│ ▐  ●▌ send crash reports                                             │
│ [ ] share usage statistics                                           │
│                                                                      │
│ The cache is empty.                                                  │
│  Clear the cache…                                                    │
│                        ▌                                             │
│                        ▌ The cache is cleared: 128 files deleted.    │
│                        ▌                                             │
╰──────────────────────────────────────────────────────────────────────╯
 saved                                f10 menu  ctrl+s save  ctrl+q quit
'''),
    );
    expect(
      RegExp('\x1b]777;notify;.*?\x1b\\\\')
          .allMatches(t.written())
          .map((m) => m[0]),
      [
        '\x1b]777;notify;Settings;The cache is cleared: 128 files deleted.\x1b\\',
      ],
    );
    await t.pump(const Duration(seconds: 3));
    expect(t, isNot(containsLine(contains('cleared'))));
  });

  testTwk('Ctrl+Q quits', (t) async {
    await t.pumpWidget(
      const SettingsApp(),
      size: size,
      backgroundRgb: 0x16181d,
    );
    await t.press('ctrl+q');
    expect(t.isRunning, isFalse);
  });

  testTwk('File ▸ Quit quits', (t) async {
    await t.pumpWidget(
      const SettingsApp(),
      size: size,
      backgroundRgb: 0x16181d,
    );
    await press(t, 'alt+f');
    await t.press('q');
    expect(t.isRunning, isFalse);
  });
}
