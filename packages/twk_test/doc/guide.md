# twk_test guide

How to write a test with twk_test. The [README](../README.md) says what the
package is for; [screen.md](screen.md) covers reading the screen, matchers,
finders and frames, and [libraries.md](libraries.md) the rest of the package.

The testing package for widgets of [twk](https://pub.dev/packages/twk): a test
runs the real app — `runApp`'s binding on a terminal in memory — under a fake
clock. Keys, the mouse and pasted text go in as the bytes a terminal sends,
decoded by the core's parser, and the screen is rebuilt from the frames' bytes
by a strict terminal emulator, which matchers and finders read.

```sh
dart pub add dev:twk_test
```

## Writing a test

```dart
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk('Enter submits what was typed', (t) async {
    await t.pumpWidget(const MyForm(), size: (40, 10));
    await t.type('привет');
    await t.press('enter');
    await t.pump();
    expect(t.lines.first, 'sent: привет');
    expect(t.cell(0, 0).fg, Color.green);
  });
}
```

`testTwk(description, body)` is a `test` of package:test, and `body` gets a
`TwkTester`. Every call of the tester returns a future to await. Each call
runs the app's microtasks before it returns.

### The app

- `pumpWidget(widget, size: (columns, rows), mode: ScreenMode.inline)`: the
  first call starts the app on an 80 × 24 terminal in the fullscreen mode,
  unless `size` and `mode` say otherwise. A later call shows the new widget in
  place of the old one (elements whose widgets match keep their state). Given
  another `size`, it resizes the terminal first. Then it pumps (see below).
- The first call also takes `history`, lines the screen shows before an app in
  the inline mode, which the app must not write over. It takes `kittyKeyboard`
  (the terminal has the kitty keyboard protocol on), `backgroundRgb`,
  `multiplexer` (the app runs inside tmux or GNU screen, so what it sends
  through them, the clipboard and notifications, comes wrapped for them) and
  `notifications` (the protocol the terminal shows desktop notifications in,
  by default none: `AppBinding.notify` then writes nothing, and with
  `NotificationProtocol.osc777` its bytes are in `terminal.frames`),
  `graphics` (the protocol the terminal shows images in, by default
  `GraphicsProtocol.none`, which leaves their cells blank; through the
  `multiplexer` as a terminal's go) and `cellPixels` (a cell's size in pixels,
  width and height, as the terminal reports it, the emulator's too; without it
  the terminal reports none and the emulator's cells are 10 × 20) too, and
  passes `maxFps`, `maxInlineRows`, `clearInlineOnExit` and `exitOnCtrlC` to
  the binding. `Multiplexer`, `NotificationProtocol` and `GraphicsProtocol`
  are twk_core's, which `package:twk/twk.dart` exports with the rest a
  `HeadlessTerminal` is made with.
- `quit()` quits the app and runs it until it has ended: the terminal is
  restored and the tree unmounted. `isRunning` says whether the app is still
  running. `binding` (the `AppBinding`), `terminal` (its `frames`), `logs`
  (the app's `LogSink`) and `stderrLines` (what the app wrote to stderr: its
  warnings and errors once it ended) are there to look at.
- `act(fn)` runs `fn` as the app's own code runs, and pumps a frame: how a
  test changes what the app listens to (a controller, a notifier, a cubit) and
  sees the frame that follows. A timer `fn` starts waits for the clock, and
  what it prints or logs goes to `logs`.

### Time

The app's timers, frames and the pause after a lone ESC wait for the clock, a
`FakeClock` (`t.clock`):

- `pump()` moves the clock on by one frame gap (a second over `maxFps`, 16.666
  ms at 60): a frame asked for before the call has run when it returns.
  `pump(duration)` moves it by `duration`, running everything due by then in
  order: timers, frames, input timeouts.
- Frames are spaced by the clock: `setState` calls between two frames make one
  build, `1 / maxFps` after the frame before. `pumpWidget(..., duration:
  Duration.zero)` runs only the app's first frame, at time zero.
- `t.clock.elapsed` is the time since the test began.
- `pumpUntilIdle()` pumps one frame gap after another until the app is idle: a
  gap passes in which it writes no frame, and none of its timers waits. A
  frame the app asked for is such a timer, and so is the next tick of an
  animation. If the app is still busy after `timeout` (10 s on the clock by
  default), the call fails the test. The message says how many frames the app
  wrote and lists the timers that wait, each with when it is due and the first
  lines of the stack it was started from, then shows the screen and the render
  tree. An app with a timer that never stops (a spinner, a poll) never becomes
  idle: pump such an app with `pump(duration)`. One whose animations end (an
  `AnimationController` at the end of its run or stopped, a spinner removed)
  has no timer left and goes idle again, which `t.clock.pendingTimers` shows.

Only timers and microtasks of the app are fake: `Stopwatch()` and
`DateTime.now()` read real time in the app too. The binding spaces frames by
`AppBinding(clock:)`, which the tester sets to `t.clock.stopwatch`, and its
wall time, `AppBinding.now()`, is `pumpWidget(startTime:)`
(`TwkTester.defaultStartTime` by default) moved on by that clock: what an app
draws of the time from it is the same on every run. Code of the test itself
keeps real time. The clock does not wait for real I/O: a file the app reads
arrives whenever the operating system delivers it.

### Input

- `type('text')` sends the UTF-8 bytes of the text as one read, which the
  parser makes into a key for each character. `input(bytes)` sends raw bytes.
- `press('ctrl+s')` sends the bytes a terminal sends for each key, a read
  each. The keys are named as twk's key bindings name them
  (`KeyCombo.parseSequence`), one space between two keys (`'g g'`, `'ctrl+x
  ctrl+s'`). Each key is its modifiers and then its name, joined by `+`. The
  modifiers are `ctrl`, `alt`, `shift` and `super`, in any order, each once. A
  name is either one character, which stands for itself (`a`, `?`, `я`, `+`,
  which comes last: `ctrl++`), or one of these, in lower case: `space`,
  `enter`, `tab`, `backspace`, `escape`, `up`, `down`, `left`, `right`,
  `home`, `end`, `pageup`, `pagedown`, `insert`, `delete`, `f1` to `f12`;
  `esc` is `escape` too, as the key hints show it. Only a character has a
  case: `A` is `shift+a`, which types the capital, and `ctrl+A` is
  `ctrl+shift+a`. Shift alone with a character that has no case (`shift+1`,
  `shift+space`) names no key.
  - A name that is not one throws a `FormatException` naming the part that is
    wrong, and the name meant where that is plain (`Enter`, `ret`, `cmd`).
  - The event is what the parser makes of the bytes: `ctrl+i` arrives as Tab,
    as on a real terminal.
  - Without the kitty protocol, some keys have no bytes of their own
    (Ctrl+Shift with a letter, Ctrl+Enter, Super, Alt and Shift with a
    character that has no case). Pressing one throws an `ArgumentError`; a
    test of such a key passes `kittyKeyboard: true` to `pumpWidget`.
  - Escape without the protocol is a lone ESC, which the parser resolves only
    after a pause. So `press('escape')` moves the clock on by the escape
    timeout, 30 ms.
- `paste(text)` sends a bracketed paste.
- `mouse(MouseKind.down, x, y, button: 2, modifiers: Mod.ctrl)` sends an SGR
  mouse report, and `click(x, y)` sends a press and a release. Neither works
  in the inline mode, where the terminal keeps the mouse for itself.
- `pointerShape` is the shape the app gave the mouse pointer last (OSC 22), on
  a terminal that shows them: `pumpWidget(pointerShapes: true)`, without which
  it throws a `StateError`; `PointerShape.arrow` where it shows the terminal's
  default.
- `resize(columns, rows)` resizes the terminal. The app gets a `ResizeEvent`,
  and the next frame repaints the screen.

A lone ESC typed with `type('\x1b')` stays pending in the parser. It becomes
the Escape key after `pump(const Duration(milliseconds: 30))`, with the kitty
protocol too, unless more input comes first. With the protocol, ESC and any
byte after it (`type('\x1b[')`) is a sequence cut by a slow link, since
Alt+key is `CSI u` there, and waits 500 ms; only a lone ESC waits the 30 ms.


### Errors and the end of a test

- If the app ends with an error, the tester call during which it ended throws
  that error (for example a `WidgetError` from an `InputListener`). A build
  that fails does not end the app: it shows an `ErrorWidget`, and the error is
  in `logs`.
- When `body` returns, an app still running is quit, and the rest of its
  frames go through the emulator. An error the app ended with that no call
  threw fails the test, and so do bytes the emulator rejects. If the test had
  already failed, its own error is the one reported.
