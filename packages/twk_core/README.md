# twk_core

A terminal rendering core for Dart with no dependencies beyond `dart:*`.
It keeps the screen as a packed cell buffer, works out which cells
changed, and writes the fewest bytes the terminal needs to show them.
Under that sit its own Unicode segmentation, an input parser, terminal
backends for Linux, macOS, Windows and the web, and a retained render
tree.

It is the core of [twk](https://pub.dev/packages/twk), Flutter-like
widgets for terminal UIs. Use `twk` to build an app from widgets; use
`twk_core` directly for your own render objects, a frame loop without a
widget layer, or a command-line tool that only needs to write styled
lines and read keys.

## Features

- **A frame with no changes writes 0 bytes.** A repaint touches only the
  cells that changed, and the presenter compares only damaged spans.
- **Next to nothing is allocated per frame.** Cells are typed arrays;
  styles and glyphs are interned.
- **Few bytes on the wire.** Frames are atomic (DEC 2026) and use
  hardware scrolling (`DECSTBM` with `SU`/`SD`, DECSLRM), character
  insert and delete, `REP`, `ECH` and `EL`.
- **Unicode-correct.** Grapheme segmentation (UAX #29), widths, and
  bidirectional text (UAX #9). Where a terminal disagrees about a
  character's width, the damage never leaves that glyph's cells.
- **Three screen modes:**
  - fullscreen on the alternate screen;
  - inline, a region under the shell's history that grows with its
    content and commits finished lines into the scrollback;
  - a fixed viewport, a rectangle of the screen outside which nothing is
    written.
- **Images** in reserved cells, with kitty graphics, sixel or iTerm2.
- **Plain text** where the output is no terminal (a pipe, CI): no escape
  sequences, and the last frame written as lines.
- **Input:** keys (the kitty keyboard protocol where the terminal has it),
  the mouse, bracketed paste, focus, resize, and the terminal's color
  scheme.
- **Anywhere a byte stream goes:** a `Terminal` over any link
  (`TerminalLink`), and a dart2wasm build for the web onto xterm.js.

## Getting started

```sh
dart pub add twk_core
```

A render tree on the terminal: a counter that Space moves on, q to quit
([example/main.dart](example/main.dart)):

```dart
import 'package:twk_core/twk_core.dart';

Future<void> main() async {
  final app = TwkApp(await Terminal.open());
  final styles = app.screen.styles;
  final hint = styles.pen(const Pen(fg: Color.brightBlack));
  final count = styles.pen(const Pen(fg: Color.green, attrs: Attr.bold));

  final label = RenderText('Pressed 0 times', count);
  final root = RenderBox(
    pen: styles.pen(const Pen()),
    padX: 2,
    padY: 1,
    child: RenderColumn(<(RenderObject, int?)>[
      (RenderText('Space counts, q quits', hint), 1),
      (label, 1),
    ]),
  );

  var pressed = 0;
  await app.run(root, (event) {
    if (event is! KeyEvent) {
      return;
    }
    if (event.char == 'q') {
      app.quit();
    } else if (event.char == ' ') {
      label.text = 'Pressed ${++pressed} times';
    }
  });
}
```

`TerminalOptions(alternateScreen: false)` runs the same tree inline, below
the shell's prompt. [example/chat_demo.dart](example/chat_demo.dart) is a
larger app, an agent chat with a scrolling log, in either mode.

### Without a screen

`package:twk_core/terminal.dart` is the terminal without the render tree
and the frame loop, for a logger, a prompt or a tool that writes lines.
It compiles in about two thirds of the time:

```dart
import 'package:twk_core/terminal.dart';

Future<void> main() async {
  final terminal = await Terminal.open(
    const TerminalOptions(alternateScreen: false, mouse: false),
  );
  final styles = StyleTable(colorMode: terminal.info.colorMode);
  final ask = styles.style(fg: Color.yellow, attrs: Attr.bold);
  final line = LineEncoder(styles, ansi: !terminal.info.plain)
    ..text(ask, 'Continue?')
    ..text(0, ' [y/n] ')
    ..end();
  terminal.write(line.out.view);
  final key = await terminal.events.firstWhere((e) => e is KeyEvent);
  await terminal.close();
  print(key == const KeyEvent(KeyCode.char, char: 'y') ? 'yes' : 'no');
}
```

## Testing

`HeadlessTerminal` is a terminal in memory to run an app on in a test, and
`renderToString` paints a render tree once to text. The
[twk_test](https://github.com/pro100andrey/twk/tree/main/packages/twk_test)
package adds a tester on a fake clock and a strict terminal emulator to
hold the bytes to.

## Platforms

- **Linux:** the process's terminal through `dart:io`, raw mode through
  termios, `SIGWINCH` or the in-band resize report.
- **macOS:** the same POSIX path, with macOS's `termios` layout.
- **Windows:** the console in virtual terminal mode, through `dart:ffi` to
  kernel32.
- **The web:** dart2wasm, with xterm.js as the terminal.

Anywhere else, a `Terminal` over a `TerminalLink` you provide, such as a
socket or an SSH channel.

macOS and Windows are written for but not yet run by the author; reports
of how they behave are welcome. The
[limitations](https://github.com/pro100andrey/twk/blob/main/packages/twk_core/doc/design/limitations.md)
list what is known.

## Learn more

- [Design](https://github.com/pro100andrey/twk/blob/main/packages/twk_core/doc/design/README.md):
  how the cells, the presenter, Unicode, input and the screen modes work;
  how the core is tested and benchmarked; its limitations.
- [The twk repository](https://github.com/pro100andrey/twk): the widget
  layer, the gallery and the other packages built on the core.

## License

MIT. The bundled Unicode data keeps its own license; see
[NOTICE](NOTICE).
