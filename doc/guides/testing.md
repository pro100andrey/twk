---
title: "Testing"
about: "An app tested on a terminal in memory, under a fake clock, with twk_test."
order: 7
---
# Testing

[twk_test](https://pub.dev/packages/twk_test) runs the real app — the
same `runApp` binding — on a terminal in memory, under a fake clock. Keys,
the mouse and pasted text go in as the bytes a terminal sends, and the
screen is rebuilt from the bytes the app wrote by a strict terminal
emulator, which the matchers read.

```sh
dart pub add dev:twk_test
```

The counter of [Getting started](getting-started.md), tested full screen
and inline:

<!-- file: packages/twk/test/example/counter_test.dart -->
```dart
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../../example/counter.dart' show Counter;

void main() {
  testTwk('full screen, the box fills the terminal and Up counts', (t) async {
    await t.pumpWidget(const Counter(), size: (24, 6));
    expect(
      t,
      matchesScreen('''
╭──────────────────────╮
│                      │
│ Count: 0             │
│                      │
│                      │
╰── up: count  q: quit ╯
'''),
    );

    await t.press('up up up');
    await t.pump();
    expect(t, containsLine('│ Count: 3             │'));
    expect(t, styleAt(2, 2, hasAttr(Attr.dim)));
    expect(t, styleAt(9, 2, allOf(hasAttr(Attr.bold), hasFg(Color.green))));
  });

  testTwk('q quits', (t) async {
    await t.pumpWidget(const Counter());
    await t.press('q');
    expect(t.isRunning, isFalse);
  });

  testTwk('inline, the box is as tall as its text, below the history, and '
      'stays there when q quits', (t) async {
    await t.pumpWidget(
      const Counter(),
      size: (44, 10),
      mode: ScreenMode.inline,
      history: [r'$ dart run example/counter.dart --inline'],
    );
    await t.press('up');
    await t.pump();
    await t.press('q');
    expect(t.isRunning, isFalse);
    expect(
      t,
      matchesScreen(r'''
$ dart run example/counter.dart --inline
╭──────────────────────────────────────────╮
│                                          │
│ Count: 1                                 │
│                                          │
╰────────────────────── up: count  q: quit ╯
'''),
    );
  });
}
```

## The tester

- `pumpWidget(app, size: (columns, rows))` starts the app, 80 × 24 by
  default; `mode: ScreenMode.inline` with `history:` lines above it. A
  later `pumpWidget` in the same test shows the new widget in place of
  the old, as a rebuild does: where the two match in type and key, the
  state stays, a field's text and a list's scroll with it. A test of
  another start begins with a widget of another type or key, or is a
  test of its own.
- Input draws nothing by itself: `await t.pump()` after `type`, `press`
  or a click, before reading the screen. `t.pump(duration)` moves the
  clock on by that much, running the app's timers, frames and animations
  due by then.
- What fades in is not there after one `t.pump()`: a dialog fades in over
  160 ms (`showDialog(fadeIn:)`), a toast and a tooltip too. Pump past it,
  `t.pump(const Duration(milliseconds: 200))`, or show it with
  `fadeIn: Duration.zero`.
- `type('text')` sends text as one read; `press('enter')`,
  `press('tab space')`, `press('ctrl+x ctrl+s')` send each key as a read
  of its own. `click(x, y)`, `clickOn(finder)` and `mouse(...)` work full
  screen (`t.mouse(MouseKind.wheelDown, x, y)` turns the wheel);
  `resize(columns, rows)`.
- `t.act(() => notifier.value = 1)` changes what the app listens to (a
  controller, a notifier, a cubit) in the app's zone and pumps the frame
  that follows. Given an async function, it moves the clock on as far as
  the function waits first.

## Keys

`press` names keys as `KeyBindings` does: the modifiers, then the name,
joined by `+` (`ctrl+shift+left`), a space between two keys (`'g g'`).
A name is one character, which stands for itself (`a`, `?`, and `A` for
`shift+a`), or one of `space`, `enter`, `tab`, `backspace`, `escape`,
`up`, `down`, `left`, `right`, `home`, `end`, `pageup`, `pagedown`,
`insert`, `delete` and `f1` to `f12`, in lower case; Escape is `esc` too,
as the key hints show it. A name that is not one throws, naming the one
meant: `Enter` is `enter`, `ret` is `enter`. `press('escape')` moves the
clock on by 30 ms, the pause after which a terminal's lone ESC is the
Escape key.

Keys sent with no pump between them are handled before the next build,
as a burst from a real terminal is: `press('enter space')` presses Space
on the screen before Enter's change was built. Pump between two keys
where the second needs what the first built.

## How many pumps

One `t.pump()` after the input draws everything the input changed, what
it changed through a future that waits for no timer too: each call of
the tester runs the app's microtasks before it returns, so a
`load().then(...)` that calls `setState` has run when the pump draws.

- A future that waits for a timer (`Future.delayed`, a debounce, a
  retry) is on the clock: `t.pump(duration)` past it.
- A change that the next frame starts (a widget that loads in
  `initState` or `didUpdateWidget`) takes a pump more: the first draws
  the frame that starts it, the second the frame its result asks for.
  `t.pumpUntilIdle()` pumps as many as it takes.
- What the app waits for in real time (a file, a process, a socket) is
  not on the clock at all: `waitUntil(condition, what, between: t.pump)`
  pumps until `condition` holds, and `waitFor(future, what)` awaits a
  future, each within a bound of real time that fails naming `what`
  instead of a test that hangs.

## Reading the screen

- `t.lines` (rows without their trailing blanks), `t.scrollback`
  (inline), `t.cell(x, y)`, `t.cursor`.
- Matchers: `containsLine` (a line, or a matcher of one:
  `containsLine(contains('saved'))`), `hasTextAt(x, y, text)`,
  `styleAt(x, y, hasFg(Color.red))` with `hasAttr` and `hasBg`,
  `cursorAt(x, y)`, `matchesScreen('''…''')` for the whole screen, and
  `matchesScreenFile` for golden files written with
  `TWK_UPDATE_GOLDENS=1`.
- Finders as in Flutter: `find.text`, `find.byType`, `find.byKey`,
  `find.byWidgetPredicate`, `find.descendant` and `find.ancestor`, with
  `findsOneWidget`, `findsNothing`, `findsNWidgets(n)`. `find` is a
  constant, not the tester's: what it finds is the app's under test.
  `find.text('Save')` finds a `Text` whose whole string, or whose spans
  joined, is `Save`, not one that contains it, and only a `Text`: a
  `Button` draws its label itself, and is found by type or predicate.
- What a finder finds, read: `t.widget<T>(finder)`, `t.state<T>(finder)`,
  `t.element(finder)`, `t.renderObject<T>(finder)`, and `t.rect(finder)`,
  its cells (`x`, `y`, `width`, `height`), which turns a widget's text
  into the cells to look at the style of.

The form of [Input and focus](input-and-focus.md), filled in from the
keys and with the mouse:

<!-- file: packages/twk/test/example/sign_in_test.dart -->
```dart
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../../example/guides/focus.dart' show SignIn;

void main() {
  testTwk('the name, Tab, the password, and Ctrl+S saves', (t) async {
    await t.pumpWidget(const SignIn(), size: (40, 10));
    await t.type('ann');
    await t.press('tab');
    await t.type('secret');
    await t.press('ctrl+s');
    await t.pump();
    expect(t, containsLine(contains('hi, ann')));
    expect(t, containsLine(contains('Password ••••••')));

    // the second field holds what the screen hides
    final password = t.widget<TextField>(find.byType(TextField).at(1));
    expect(password.controller!.text, 'secret');
  });

  testTwk('a click on the button with no name asks for one', (t) async {
    await t.pumpWidget(const SignIn(), size: (40, 10));
    // a Button draws its label itself: find.text finds Texts only
    final button = find.byWidgetPredicate(
      (w) => w is Button && w.label == 'Sign in',
      description: 'the Sign in button',
    );
    await t.clickOn(button);
    await t.pump();
    expect(find.text('a name, please'), findsOneWidget);

    // the status shows on the button's row, after it
    final status = t.rect(find.text('a name, please'));
    expect(status.y, t.rect(button).y);
    expect(t, hasTextAt(status.x, status.y, 'a name, please'));
  });
}
```

## Time

No test waits on the wall clock. Only the app's timers and frames are on
the fake clock: `DateTime.now()` and `Stopwatch()` read real time, so pass
dates in. `pumpUntilIdle()` pumps until no frame and no timer waits, so
it runs out the timers that end what a test may look for: a toast, which
shows for 3 s, and a highlight on a timer are gone when it returns. To
see them, pump by a duration shorter than theirs. An app with a periodic
timer or a spinner is never idle: pump it by a duration instead.

## When a test fails

A failing matcher shows the screen as text (`styleAt` with its styles
marked), the widget tree with each widget's size and the render tree. A
failing test then prints its last 3 frames that changed the screen
(`testTwk(..., framesOnFailure: n)`, 0 for none), and the app's log.
`pumpUntilIdle` that fails lists the timers that wait, each with where
it was started.

What the app prints does not reach the test's output while it passes,
as on a real terminal it would write over the screen: `print`, `log()`
and the warnings and errors the app reports (a layout that overflowed,
a build that threw) are in `t.logs.records` (`LogRecord`s: `message`,
`error`, `stack`), the last 20 of them printed when the test fails, and
what it wrote to stderr once it ended in `t.stderrLines`.

The rest of the tester — frames recorded and written as a trace, a widget
drawn without an app (`Shot`), processes a test starts — is in
[twk_test's README](https://pub.dev/packages/twk_test).
