# Other libraries

What the package offers beside `testTwk`. The [guide](guide.md) covers writing
a test.

## Other libraries

- `package:twk_test/vt.dart` (`Vt`, `VtCell`, `VtImage`) is the emulator;
  twk_core's own tests are held to it. A `VtCell` prints as a snapshot with
  styles shows it (`[bold]a[/]`). A DCS or APC string ends at ST alone: a
  sixel image (DCS) and a kitty graphics command (APC `G`) are taken as a
  terminal takes them, what a `DCS tmux;` string holds as the terminal outside
  tmux takes it (an ESC ESC in it is one ESC, and an ESC not doubled is an
  error), and any other changes nothing on the screen. Images (`images`):
  kitty's, transmitted and kept by id (`kittyImages`, their bytes), placed,
  moved with their cells as they scroll and staying over them as text is
  written there, deleted, and freed by `ED 2`; sixel images, sized by their
  raster attributes over cells of `cellPixelWidth` × `cellPixelHeight` (10 ×
  20 by default), the cursor left after them as DEC mode 8452 says; iTerm2's
  (OSC 1337 `File=`); the pixels of the last two taken away with what is
  written or erased in their cells. The queries of sizes in pixels (`CSI 14
  t`, `16 t`, `18 t`) are taken, unanswered.
- `screenFrames(width, height, writes)` plays a program's writes to a terminal
  (`TerminalWrite`s: an output or a resize, at a time) through the emulator,
  and gives a `ScreenFrame` after each output that leaves no synchronized
  update open: its time, size, rows, the cursor, and what the emulator could
  not take up to it. twk_dev's `Cast.writes` are a recording's, which so
  becomes a regression test.
- `package:twk_test/vt_terminal.dart` (`VtTerminal`) is a terminal backend in
  the inline mode that feeds its output to the emulator, below lines printed
  before the app ran.
- `package:twk_test/cli.dart` (`FakeCliTerminal`, and `FakeClock` and `Vt`
  again) is the terminal a test of a program on twk's console
  (`package:twk/cli.dart`) hands a `Cli` or `Cli.run`'s `open:`: it captures
  what is written, answers the plain prompts a line each, types keys into the
  interactive ones, and shows the inline session's screen through the
  emulator.
- `Shot(widget, columns, rows)` shows a widget tree without an app: on a
  screen of its own, built, laid out and painted as a frame is, each frame
  written to an emulator (`vt`). No binding, clock or input: a frame runs when
  `pump(widget)` or `frame()` is called. `rows`, `colors(y)` (each cell's
  glyph, color and background), `attrs(y)` and `anyWide` read the emulator
  back; `owner`, `pipeline`, `root` and `top` are the tree's.
  `Shot.render(renderObject, columns, rows)` shows a render object no widget
  made, and with `under: '.'` fills the screen with that character first,
  which a repaint boundary that leaves a cell unpainted shows. Both take
  `ambiguousWidth`, the screen's and the emulator's.
- The screen as text, as the matchers and their failure messages give it:
  `rowText(vt, y, styles: true)` and `screenRows(vt)` (rows plain or with
  styles marked), `describeScreen(vt)` and `describeApp(vt, root)` (the screen
  numbered, plain unless `describeScreen(vt, styles: true)`, and the render
  tree), `styleOf(cell)`, `markedCell(cell)`, `colorName(color)`,
  `colorOf(color)` and `attrNames(attrs)`.
- `FakeStderr` stands in for stderr under `IOOverrides`: it keeps each write
  (`writes`) and their lines (`lines`), each write after what its `tag` says
  when it comes (`FakeStderr(tag: () => 'on screen')`).
- `FakeClock` works on its own too. `run(body)` runs code in its zone, and
  `elapse(duration)` fires the zone's timers as the clock reaches them.
  `flushMicrotasks()` runs the zone's microtasks. It also lets the real event
  loop run its own, since code awaiting a future completed outside the zone
  resumes there. `stopwatch` is a `Stopwatch` that reads the clock.
  `pendingTimers` counts the timers that wait, `nextTimerDue` is the time the
  next of them fires at, and `describeTimers()` lists them, each with when it
  is due and where it was started.
- A program a test runs in a process of its own (a signal, a crash, a
  pseudo-terminal, a VM service) is compiled once per suite, in `setUpAll`, by
  `compiledProgram(path, packages: ..., cache: ...)`, and run as `dart
  <kernel>`: a kernel without the platform, kept in the directory `cache`
  names (`.dart_tool/twk_test/programs`, say) with the names of the files it
  was compiled from and a hash of what they hold. A later run with them
  unchanged compiles nothing; one of them edited, added or gone, or another
  Dart, compiles it again. `defines` are the `-D` declarations it is compiled
  with, a kernel of their own.
- A process a test starts ends with the test, however the test ends (it
  returns, fails, throws or times out): `startProcess` and `runProcess` are
  `Process.start` and `Process.run` with a tear-down that kills the process if
  it still runs then and waits for its exit, with a bound. `group: true`, for
  a process that starts processes of its own (a shell, `dart` running an app,
  a compiler), starts it on Linux in a session and process group of its own
  (`setsid`), seen to lead it before it runs, and the tear-down kills that
  group too, even once the process itself has ended. Nothing else is
  signalled: no process is looked for by name, environment or listing, and
  every signal goes through one guard, which refuses a pid that is not the
  process started, 0, 1, -1, and any group but the one made for it, never the
  runner's own.
