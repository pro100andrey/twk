# The emulator and its host interface

The [README](../README.md) is where to start. This is how a host of its own
drives the emulator.

Three parts: the emulator (`lib/src/emulator/`), the pseudo-terminal the
program runs in (`lib/src/pty/`, Linux and macOS, through `dart:ffi` alone),
and the `TerminalView` widget that shows a program and gives it the keys, the
mouse, pastes, the focus and its size (`lib/src/view/`).

The emulator alone, for a host of its own:

```dart
final pty = Pty.start('bash', ['-l'], width: 80, height: 24);
final term = TerminalEmulator(
  width: 80,
  height: 24,
  onOutput: pty.write, // answers, keys, mouse reports, pasted text
  onEvent: (event) => switch (event) {
    TitleChanged(:final title) => window.title = title,
    // any program in the terminal may send one, over ssh too: ask, or
    // take it only from a program the user trusts
    ClipboardWrite(:final text) when allowClipboard() => clipboard.set(text),
    BellRang() => flash(),
    _ => null,
  },
);
pty.output.listen(term.feed); // what the program writes
term.paint(canvas, x: 0, y: 0); // its screen, in a widget's paint
term.sendKey(const KeyEvent(KeyCode.up)); // in the program's modes
```

What the pseudo-terminal and the view need, and nothing they don't:

- **In**: `feed(bytes)` with each read from the program; a sequence or a
  character may be split anywhere between reads.
- **Out**: `onOutput(Uint8List)` with every byte for the program, written to
  it in order: answers come during `feed`, input when the host calls `sendKey`
  (as `KeyEvent`s of the core, in the program's kitty flags, `keyboardFlags`,
  or else its DECCKM and LNM), `sendText`, `sendPaste` (bracketed in mode
  2004, line breaks as CR, an end marker inside taken out), `sendFocus` (false
  when mode 1004 is off), `sendMouse` (cell coordinates; false when the
  program doesn't track the mouse — the host's for selection and the
  scrollback then — except the wheel going as arrow keys on the alternate
  screen in mode 1007) and `answerClipboard` after a `ClipboardRead`.
- **Events**: `onEvent(TerminalEvent)`, during `feed`, in the order asked:
  `TitleChanged`, `IconNameChanged`, `BellRang`, `ClipboardWrite`,
  `ClipboardRead`, `ModeChanged` (every mode that changes, the ones that
  change what the host sends or shows among them), `CursorShapeChanged`,
  `WorkingDirectoryChanged`, `NotificationRequested`, `ProgressChanged`,
  `PromptMarked`, `ColorsChanged`, `ResizeRequested`, `PointerShapeChanged`.
- **The screen as cells**: `line(y)` (`TerminalLine`: per column a glyph word
  — a `GlyphTable` id with `kWide`, `kCont` and `kUncertain` as a `Surface`
  keeps them — and a `StyleTable` style id; `wrapped` where the text runs on),
  `scrollbackLine(i)`, `cellAt`, `cellText`, `styleAt`, `lineText`, `text`;
  `styles` and `glyphs`, the tables the ids are in (a host can pass its
  canvas's own, so the cells copy as they are). `paint(canvas, x:, y:,
  scrollOffset:)` draws the screen with a `Canvas` — its translation and clip
  apply, pens and glyph ids are carried over to the canvas's tables once each,
  `scrollOffset` lines back in the scrollback, the program's default text
  color and background in `fg:` and `bg:` (the host terminal's own by default;
  the emulator's state untouched); `paintLine(canvas, line, x:, y:, fg:, bg:)`
  one row, or a copy of one. The cursor is left to the view: `cursorX`,
  `cursorY`, `wrapPending`, `cursorVisible`, `cursorShape`, `cursorColor`.
- **What moved**: `onScrolled(top, bottom, n)` as rows of the screen shown
  move (a line feed at the bottom margin, IND, RI, SU, SD, IL, DL), so a view
  moves what it painted of them instead of painting them again;
  `scrollbackAdded`, the lines that have gone into the scrollback, by which a
  view scrolled back keeps its lines in place.
- **State**: `mode(TerminalMode)`, `mouseProtocol`, `mouseEncoding`,
  `alternateScreen`, `margins`, `title`, `iconName`, `workingDirectory`,
  `palette`, `foregroundColor` and `backgroundColor` (the program's, or the
  host's `defaultForeground` and `defaultBackground`, which OSC 10 and 11
  report and CSI ? 996 n's dark or light is of: `TerminalView` keeps them at
  the colors it paints the defaults in).
- **Size**: `resize(width, height)`; `Pty.resize` tells the program
  (TIOCSWINSZ, SIGWINCH).

While `TerminalMode.synchronizedOutput` is set the program is drawing a frame:
a view shows the screen as it was until the mode is reset (or a timeout
passes).
