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
- What animates in is not there after one `t.pump()`: a dialog fades in
  over 160 ms (`showDialog(fadeIn:)`), a tooltip over 100 ms
  (`Tooltip(fadeIn:)`), and a toast slides in over 200 ms, with no
  `fadeIn` to set. Pump past it, `t.pump(const Duration(milliseconds: 200))`;
  a dialog and a tooltip shown with `fadeIn: Duration.zero` need none.
- `type('text')` sends text as one read; `press('enter')`,
  `press('tab space')`, `press('ctrl+x ctrl+s')` send each key as a read
  of its own. `click(x, y)`, `clickOn(finder)` and `mouse(...)` work full
  screen (`t.mouse(MouseKind.wheelDown, x, y)` turns the wheel);
  `resize(columns, rows)`.
- `t.act(() => notifier.value = 1)` changes what the app listens to (a
  controller, a notifier, a cubit) in the app's zone and pumps the frame
  that follows. Given an async function, it moves the clock on as far as
  the function waits first. `t.clock.run(() => Timer(...))` starts a
  timer on the fake clock from the test's own code; `t.pump(duration)`
  fires it.

## Keys

`press` names keys as `KeyBindings` does: the modifiers, then the name,
joined by `+` (`ctrl+shift+left`), a space between two keys (`'g g'`).
A name is one character, which stands for itself (`a`, `?`, and `A` for
`shift+a`), or one of `space`, `enter`, `tab`, `backspace`, `escape`,
`up`, `down`, `left`, `right`, `home`, `end`, `pageup`, `pagedown`,
`insert`, `delete` and `f1` to `f12`, in lower case; Escape is `esc` too,
as the key hints show it. A name that is not one throws, naming the one
meant: `Enter` is `enter`, `ret` is `enter`. Without the kitty protocol
`press('escape')` moves the clock on by 30 ms, the pause after which a
terminal's lone ESC is the Escape key; with
`pumpWidget(..., kittyKeyboard: true)` Escape is a sequence of its own and
the clock stays. A lone ESC typed there still waits those 30 ms, but ESC and
a byte after it (a cut arrow, `\x1b[`) wait 500 ms, as a started sequence
does.

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
- What a `LayoutBuilder` builds is built in the frame after its layout, so
  what its build changes in the bindings and the focus (a `KeyBindings`
  below it, the key hints) is built in the frame after, which is asked for
  at once: after a `resize`, a pump more before reading the hints.
- What the app waits for in real time (a file, a process, a socket) is
  not on the clock at all: `waitUntil(condition, what, between: t.pump)`
  pumps until `condition` holds, and `waitFor(future, what)` awaits a
  future, each within a bound of real time that fails naming `what`
  instead of a test that hangs.

## Reading the screen

- `t.lines` (rows without their trailing blanks), `t.scrollback`
  (inline), `t.cell(x, y)`, `t.cursor`.
- One widget's part of the screen: `t.linesOf(finder)` gives the rows of
  its cells, `t.linesIn((x:, y:, width:, height:))` those of a rectangle
  (`t.rect(finder)` gives one), from its first column and without the
  blanks that end a row; a wide glyph cut by the region's edge is left out,
  so the rows are exactly its cells. `containsLine(line, within: finder)`
  and `hasTextAt(x, y, text, within: finder)` read the region alone, `x`
  and `y` from its first cell: a list's row in a screen of two panes that
  both show it.
- Matchers: `containsLine` (a line, or a matcher of one:
  `containsLine(contains('saved'))`), `hasTextAt(x, y, text)`,
  `styleAt(x, y, hasFg(Color.red))` with `hasAttr` and `hasBg`,
  `cursorAt(x, y)`, `matchesScreen('''…''')` for the whole screen, and
  `matchesScreenFile('test/goldens/form.txt')` for golden files written
  with `TWK_UPDATE_GOLDENS=1`. The path is from the root of the package of
  the test file that calls it (the directory with its `pubspec.yaml`), not
  from the directory `dart test` runs in; where that package is not found it
  throws, saying to pass an absolute path. A golden holds the styles too;
  `styles: false` compares the text alone.
- Finders as in Flutter: `find.text`, `find.textContaining`, `find.byType`,
  `find.byKey`,
  `find.byWidgetPredicate`, `find.descendant` and `find.ancestor`, with
  `findsOneWidget`, `findsNothing`, `findsNWidgets(n)`. `find` is a
  constant, not the tester's: what it finds is the app's under test.
  `find.text('Save')` finds a `Text` whose whole string, or whose spans
  joined, is `Save`, not one that contains it, and only a `Text`: a
  `Button` draws its label itself, and is found by type or predicate.
  `find.textContaining('Sav')` finds a match of a `String` or a `RegExp`
  in the same text.
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

## In a real terminal

`testTwk` runs the app in the test's own process, on a screen the tester
keeps. What it cannot show is the app as `runApp` runs it: the process, the
terminal's modes and the bytes it writes (what `runApp` does with them is in
[Running an app](running.md)). For that the test runs the app in a
pseudo-terminal, twk_term's `Pty`, and reads what it writes through
twk_term's emulator, `TerminalEmulator`, as a terminal would:
`compiledProgram` of twk_test compiles the app once, `waitUntil` and
`waitFor` wait for the screen and for the exit in real time, within a bound
that fails saying what was waited for, never a sleep, and the tear-down
kills the one process the test started, through its `Pty`.

<!-- file: packages/twk_term/test/example/run_app_test.dart -->
```dart
@TestOn('linux || mac-os')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk_term/twk_term.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  late String counter;

  setUpAll(() async {
    // compiled once, and again only when its sources change
    counter = await compiledProgram(
      '../twk/example/counter.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    );
  });

  test('the counter counts on Up and quits on q', () async {
    final screen = TerminalEmulator(width: 40, height: 6);
    final pty = Pty.start(
      Platform.resolvedExecutable,
      [counter],
      width: 40,
      height: 6,
    );
    final output = pty.output.listen(screen.feed);
    // ends this process and no other, whatever the test does
    addTearDown(() async {
      pty
        ..kill(ProcessSignal.sigkill)
        ..close();
      await output.cancel();
    });

    await waitUntil(() => screen.text.contains('Count: 0'), 'the first frame');
    pty.write(utf8.encode('\x1b[A'));
    await waitUntil(() => screen.text.contains('Count: 1'), 'the count');
    pty.write(utf8.encode('q'));
    // the VM takes the end first while a Process of the test runs: where
    // Pty cannot tell the code then (Linux before 6.15), it is null
    expect(
      await waitFor(pty.exitCode, 'the exit'),
      Pty.tellsExitCode ? 0 : anyOf(0, isNull),
    );
  });
}
```

The app is a program of its own, with a `main` that calls `runApp`; the
test needs `twk_term` among its `dev_dependencies`, and runs on Linux and
macOS. A program that needs no terminal, a command-line tool whose output
is what is wanted, is started with twk_test's `startProcess` or
`runProcess` instead, which end it with the test too.

To see an app in a real terminal without writing a test, twk_dev has the
commands for it: `twk record` runs the app in a terminal and writes the
session (`--keys` its input too), `twk play` plays it back, and `twk tape`
runs a script of what to type and what to wait for (`Wait /regexp/`) and
writes the session and the screens it names. A recording is a regression
test too, played through the emulator with twk_test's `screenFrames`. Their
options are in [twk_dev's guide](https://github.com/pro100andrey/twk/blob/main/packages/twk_dev/doc/record-play.md).

## Time

No test waits on the wall clock. Only the app's timers and frames are on
the fake clock: `DateTime.now()` and `Stopwatch()` read real time. A
widget that shows the time reads `AppBinding.of(context).now()` instead:
the app's start time moved on by its clock, which in a test starts at
`pumpWidget(startTime:)` (`TwkTester.defaultStartTime`, 1 January 2026,
by default) and moves as the test pumps, so the screen is the same on
every run. A `Calendar`, a `DatePicker` and a `Heatmap` given no date of
their own take today from it; a `CalendarController()` given no cursor
still reads `DateTime.now()`, so give it one in a test. `pumpUntilIdle()` pumps until no frame and no timer waits, so
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

An error the app logged fails the test when it ends, unless the test
takes it: `t.takeErrors()` hands over the `LogRecord`s at `LogLevel.error`
logged since its last call. A build that threw is shown in place and the
next frame may build over it, so a test that passes has seen none, or said
it expected them. What the app logs as it quits counts too: a test that
expects that takes it after `await t.quit()`.

The rest of the tester — frames recorded and written as a trace, a widget
drawn without an app (`Shot`), processes a test starts — is in
[twk_test's README](https://pub.dev/packages/twk_test).
