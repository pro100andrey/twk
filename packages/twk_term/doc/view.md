# The view

The [README](../README.md) is where to start. This is `TerminalSession` and
`TerminalView`, the program in a widget.

```dart
import 'package:twk/twk.dart';
import 'package:twk_term/twk_term.dart';

final class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

final class _ShellState extends State<Shell> {
  // started at the view's size, at its first layout
  final _session = TerminalSession.start('bash', const []);

  @override
  void dispose() {
    _session.dispose(); // hangs up: SIGHUP for bash
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TerminalView(
    session: _session,
    autofocus: true,
    ignoredKeys: const ['ctrl+q'], // left to a KeyBindings above
    onTitleChanged: (title) => log('title: $title'),
  );
}
```

[`example/split_shells.dart`](../example/split_shells.dart) runs two shells
side by side in a `SplitView`: a click or Alt+1 and Alt+2 focus one, Ctrl+Q
quits.

`TerminalSession` is a program and the emulator of its terminal: what the
program writes is fed to `emulator`, what the emulator sends goes to the
program, its listeners are told after each piece of output and when the output
`ended`. `TerminalSession.start(executable, arguments, width:, height:,
workingDirectory:, environment:, includeParentEnvironment:, scrollbackLimit:,
textMode:)` runs it in a `Pty`, at once at the size given or, without one, at
the first `resize` — which the first layout of a view showing it calls, so the
program never sees another size (a shell that started at 80 columns and was
resized at once may print its first prompt for 80); what that start throws is
`error`, logged, and the session has ended. `TerminalSession(output:, input:,
onResize:)` is a program over any other byte link. `events` is a broadcast
stream of its `TerminalEvent`s, `exitCode` its exit code, `title` its title;
`dispose` hangs a pty up (SIGHUP) — a program that ignores it is the app's to
`pty.kill`.

`TerminalView(session:, focusNode:, autofocus:, ignoredKeys:, wheelLines:,
defaultStyle:, onTitleChanged:, onBell:, onClipboardWrite:, onClipboardRead:,
onEvent:)` shows the session's screen and is its terminal:

- **Size**: it takes all the room it gets (along an axis without a bound, the
  terminal's size) and resizes the session to it at each layout: SIGWINCH for
  the program.
- **Keys**: while it has the focus every key goes to the program (`sendKey`),
  Tab, Escape and Ctrl+C among them, except `ignoredKeys` (named as
  `KeyBindings` names them, `'ctrl+q'`), which go up to the nodes above, as do
  releases the program doesn't hear of. So Tab does not move the focus out of
  it: a click elsewhere, or a binding of an ignored key, does. A key brings a
  view scrolled back to the screen.
- **Pastes** go as typed, bracketed in mode 2004.
- **Focus**: the program is told (mode 1004) when the view gains or loses the
  focus, and when the app's terminal does.
- **Mouse**: a press focuses the view. While the program tracks the mouse it
  gets presses, releases, the wheel and, as its mode asks, motion, in the
  view's cells — the app's terminal reports motion only while a program wants
  it. Otherwise the wheel scrolls the scrollback `wheelLines` lines (3), or on
  the alternate screen sends as many Up or Down keys. Output while scrolled
  back leaves the lines shown in place.
- **Default colors**: the program's default text color and background are
  painted in `defaultStyle`'s `fg` and `bg` — by default the `Theme`'s text on
  its background, so the terminal is of a piece with a themed app
  (`Color.defaultColor` for the app's terminal's own). They are what the
  program is told when it asks (OSC 10, 11, and CSI ? 996 n for dark or
  light): a program choosing its colors by the background (vim's `background`,
  a `light` or `dark` theme) chooses them for the one it is shown on. A
  palette color is told as the emulator's `palette` has it, the app's
  terminal's default as the app learnt it (its text color only where it told
  it).
- **Cursor**: the terminal's cursor shows the program's, in its shape
  (DECSCUSR; its default, 0, is the app's terminal's own, whatever its user
  set — a block in the gallery design, which stands in for it), while the view
  has the focus, the program shows it and it is in view. The view places it
  with twk's `showCaret` and `hideCaret`, as a `TextField` does its caret, so
  a focus moving between fields and views within a frame leaves it at the one
  with the focus.
- **Synchronized output**: while the program draws a frame in mode 2026, the
  view shows the frame before, until the mode is reset or 150 ms passed.
- **The program asks** for a title, the bell, the clipboard: the callbacks are
  told (`onEvent` every event first); `onClipboardRead` answers with what it
  returns or completes with. Nothing is done without them.
- **Painting**: a repaint boundary that keeps a copy of each row as it painted
  it and paints only the rows that changed; rows the program scrolled (and
  those the wheel scrolled) move on the surface first (`Surface.scrollRect`),
  which the presenter replays as a hardware scroll (DECSTBM and SU or SD; with
  DECSLRM for a view narrower than the screen where the terminal has it), and
  the rows the move exposed are painted. Colors the program set with OSC 4, 10
  and 11 are reported back but not applied: cells keep palette indices, drawn
  in the app's terminal's palette, and the defaults in the view's. No
  selection with the mouse yet.
