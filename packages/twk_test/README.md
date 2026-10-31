# twk_test

The testing package for widgets of [twk](https://pub.dev/packages/twk):
a test runs the real app — `runApp`'s binding on a terminal in memory —
under a fake clock. Keys, the mouse and pasted text go in as the bytes a
terminal sends, decoded by the core's parser, and the screen is rebuilt
from the frames' bytes by a strict terminal emulator, which matchers and
finders read.

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

- `pumpWidget(widget, size: (columns, rows), mode: ScreenMode.inline)`:
  the first call starts the app on an 80 × 24 terminal in the fullscreen
  mode, unless `size` and `mode` say otherwise. A later call shows the new
  widget in place of the old one (elements whose widgets match keep their
  state). Given another `size`, it resizes the terminal first. Then it
  pumps (see below).
- The first call also takes `history`, lines the screen shows before an
  app in the inline mode, which the app must not write over. It takes
  `kittyKeyboard` (the terminal has the kitty keyboard protocol on),
  `backgroundRgb`, `multiplexer` (the app runs inside tmux or GNU
  screen, so what it sends through them, the clipboard and
  notifications, comes wrapped for them) and `notifications` (the
  protocol the terminal shows desktop notifications in, by default
  none: `AppBinding.notify` then writes nothing, and with
  `NotificationProtocol.osc777` its bytes are in `terminal.frames`),
  `graphics` (the protocol the terminal shows images in, by default
  `GraphicsProtocol.none`, which leaves their cells blank; through the
  `multiplexer` as a terminal's go) and `cellPixels` (a cell's size in
  pixels, width and height, as the terminal reports it, the emulator's
  too; without it the terminal reports none and the emulator's cells are
  10 × 20) too, and passes `maxFps`, `maxInlineRows`, `clearInlineOnExit`
  and `exitOnCtrlC` to the binding. `Multiplexer`, `NotificationProtocol`
  and `GraphicsProtocol` are twk_core's, which `package:twk/twk.dart`
  exports with the rest a `HeadlessTerminal` is made with.
- `quit()` quits the app and runs it until it has ended: the terminal is
  restored and the tree unmounted. `isRunning` says whether the app is
  still running. `binding` (the `AppBinding`), `terminal` (its `frames`),
  `logs` (the app's `LogSink`) and `stderrLines` (what the app wrote to
  stderr: its warnings and errors once it ended) are there to look at.
- `act(fn)` runs `fn` as the app's own code runs, and pumps a frame: how
  a test changes what the app listens to (a controller, a notifier, a
  cubit) and sees the frame that follows. A timer `fn` starts waits for
  the clock, and what it prints or logs goes to `logs`.

### Time

The app's timers, frames and the pause after a lone ESC wait for the clock,
a `FakeClock` (`t.clock`):

- `pump()` moves the clock on by one frame gap (a second over `maxFps`,
  16.666 ms at 60): a frame asked for before the call has run when it
  returns. `pump(duration)` moves it by `duration`, running everything due
  by then in order: timers, frames, input timeouts.
- Frames are spaced by the clock: `setState` calls between two frames make
  one build, `1 / maxFps` after the frame before. `pumpWidget(...,
  duration: Duration.zero)` runs only the app's first frame, at time zero.
- `t.clock.elapsed` is the time since the test began.
- `pumpUntilIdle()` pumps one frame gap after another until the app is
  idle: a gap passes in which it writes no frame, and none of its timers
  waits. A frame the app asked for is such a timer, and so is the next tick
  of an animation. If the app is still busy after `timeout` (10 s on the
  clock by default), the call fails the test. The message says how many
  frames the app wrote and lists the timers that wait, each with when it
  is due and the first lines of the stack it was started from, then shows
  the screen and the render tree. An app with a timer that never stops (a spinner, a
  poll) never becomes idle: pump such an app with `pump(duration)`. One
  whose animations end (an `AnimationController` at the end of its run
  or stopped, a spinner removed) has no timer left and goes idle again,
  which `t.clock.pendingTimers` shows.

Only timers and microtasks of the app are fake: `Stopwatch()` and
`DateTime.now()` read real time in the app too. The binding spaces frames
by `AppBinding(clock:)`, which the tester sets to `t.clock.stopwatch`. Code
of the test itself keeps real time. The clock does not wait for real I/O:
a file the app reads arrives whenever the operating system delivers it.

### Input

- `type('text')` sends the UTF-8 bytes of the text as one read, which the
  parser makes into a key for each character. `input(bytes)` sends raw
  bytes.
- `press('ctrl+s')` sends the bytes a terminal sends for each key, a
  read each. The keys are named as twk's key bindings name them
  (`KeyCombo.parseSequence`), one space between two keys (`'g g'`,
  `'ctrl+x ctrl+s'`). Each key is its modifiers and then its name, joined
  by `+`. The modifiers are `ctrl`, `alt`, `shift` and `super`, in any
  order, each once. A name is either one character, which stands for
  itself (`a`, `?`, `я`, `+`, which comes last: `ctrl++`), or one of
  these, in lower case: `space`, `enter`, `tab`, `backspace`, `escape`,
  `up`, `down`, `left`, `right`, `home`, `end`, `pageup`, `pagedown`,
  `insert`, `delete`, `f1` to `f12`. Only a character has a case: `A`
  is `shift+a`, which types the capital, and `ctrl+A` is
  `ctrl+shift+a`. Shift alone with a character that has no case
  (`shift+1`, `shift+space`) names no key.
  - A name that is not one throws a `FormatException` naming the part
    that is wrong, and the name meant where that is plain (`Enter`,
    `esc`, `cmd`).
  - The event is what the parser makes of the bytes: `ctrl+i` arrives as
    Tab, as on a real terminal.
  - Without the kitty protocol, some keys have no bytes of their own
    (Ctrl+Shift with a letter, Ctrl+Enter, Super, Alt and Shift with a
    character that has no case). Pressing one throws an `ArgumentError`;
    a test of such a key passes `kittyKeyboard: true` to `pumpWidget`.
  - Escape without the protocol is a lone ESC, which the parser resolves
    only after a pause. So `press('escape')` moves the clock on by the
    escape timeout, 30 ms.
- `paste(text)` sends a bracketed paste.
- `mouse(MouseKind.down, x, y, button: 2, modifiers: Mod.ctrl)` sends an
  SGR mouse report, and `click(x, y)` sends a press and a release. Neither
  works in the inline mode, where the terminal keeps the mouse for itself.
- `resize(columns, rows)` resizes the terminal. The app gets a
  `ResizeEvent`, and the next frame repaints the screen.

A lone ESC typed with `type('\x1b')` stays pending in the parser. It
becomes the Escape key after `pump(const Duration(milliseconds: 30))`
(500 ms with the kitty protocol), unless more input comes first.

### The screen

- `lines` gives the screen's rows as text, without the blanks that end
  them, with a wide glyph shown once.
- `scrollback` gives the lines scrolled off the top in the inline mode,
  oldest first.
- `linesIn(region)` gives the rows of a rectangle `(x:, y:, width:,
  height:)`, as `rect` gives one, as `lines` gives the screen's, from the
  rectangle's first column: `t.linesIn((x: 12, y: 0, width: 12, height:
  3))`. As many rows and columns are read as the screen has.
  `t.linesOf(finder)` gives those of the cells of a widget.
- `cell(x, y)` gives one cell: `text` (`''` for the right half of a wide
  glyph), `fg`, `bg`, `ul` (the underline color) and `attrs`. The colors
  and attributes are numbered as `Color` and `Attr` number them, with `0`
  for the terminal's default color:
  `expect(t.cell(0, 0).fg, Color.red)`,
  `expect(t.cell(0, 0).attrs, Attr.bold)`. `fgColor`, `bgColor` and
  `ulColor` give the colors as `Color`s, `Color.defaultColor` for `0`.
- `cursor` is the cursor's (column, row) and `cursorVisible` whether it is
  shown.
- `vt` is the emulator itself (`Vt`).
- `written()` is what the app wrote to the terminal, as text: the bytes
  of every frame decoded as UTF-8, a byte that is not as U+FFFD; and
  `written(since: n)` those of the frames from `terminal.frames[n]` on.
  It is where a test looks for what the screen does not show: a mode
  set, the clipboard written (OSC 52), a notification, a scroll.

The emulator is strict: a sequence it does not know, text that wraps or
scrolls the screen, a write to the inline mode's history, an absolute
row in the inline mode, or an image it can't take (a kitty command
without `q=2`, a placement of an image not sent, not sized in cells or
without `C=1`; an image over text, past the screen or one that scrolls
it) throws when the screen is read. A `Vt` of your own that replays what a real
program wrote, a recorded session, is made with `Vt(width, height,
strict: false)`: what it does not take is then kept in `vt.errors`, not
thrown. `t.vt.images` lists the images on
the screen (`VtImage`: the protocol, a kitty image's id and placement,
its bytes, the cells it still has and, for kitty, the part shown), top
to bottom.

### Matchers

The matchers of the screen take the tester: `expect(t, containsLine('ok'))`.

- `containsLine(line)`: a row of the screen is `line`, as `lines` gives
  the rows. Given a matcher (`startsWith('sent:')`), a row it matches.
- `hasTextAt(x, y, text)`: the cells from column `x` of row `y` on show
  `text`. As many cells are read as `text` is wide.
- `within:` on both, a finder or a rectangle, limits them to the cells of
  a widget or a region, so a title printed twice on a row, in a list and
  in a panel, is matched in the one: `expect(t, containsLine('> one',
  within: find.byType(ListView)))`. For `hasTextAt` `x` and `y` count from
  the region's first cell, and the cells read stop at its edge. A match
  that fails says where the screen shows the text outside the region, if
  it does: `has none in the cells (12, 0), 5×3, but the screen shows '> one'
  at column 0, row 1`.
- `styleAt(x, y, matcher)`: the cell at column `x` of row `y` matches
  `matcher`. The matchers of a cell are `hasAttr(Attr.bold)` (every
  attribute given; an underline matches only the same kind of underline),
  `hasFg(Color.red)` and `hasBg(color)`. They take a cell on its own too:
  `expect(t.cell(0, 0), hasFg(Color.red))`.
- `cursorAt(x, y)`: the cursor is shown, at column `x` of row `y`.
- `matchesScreen(snapshot)`: the screen is `snapshot`, a string in the
  test whose lines are the rows of the screen from the top. The blanks
  that end a line and the empty lines that end the screen don't count,
  on either side:

  ```dart
  expect(t, matchesScreen('''
  sent: привет
  [x] done
  '''));
  ```

  Indentation counts, so the snapshot's lines start at the start of the
  line in the source.
- `matchesScreen(snapshot, styles: true)` compares styles too. Each run of
  cells of one style is in `[style]…[/]`:
  `[bold]sent:[/] привет [red on #102030]ok[/]`.
  - A style lists the attributes first, by their names in `Attr`
    (`bold`, `curlyUnderline`). Then come the color, `on` and the
    background, and `ul=` and the color of the underline. Each is left
    out when it is the default.
  - A color has its name in `Color` (`red`, `brightBlack`, and
    `brightRed` and so on for 9 to 14), `indexed(n)` for the rest of the
    palette, or `#rrggbb` for a 24-bit color.
  - A `[` of the text is written `[[`.
  - A space shows only its background, unless it has an attribute that
    shows on a blank (`Attr.visibleOnBlank`: underlines, reverse, strike,
    overline). Between two cells of one style with that background, the
    space is in their run. Elsewhere its style is its background, and
    spaces with no background at the end of a row are left out.
- `matchesScreenFile(path)`: the screen is the one the file at `path`
  holds (a golden file), relative to the package. A whole screen of a
  themed app is a run of styles in nearly every cell, which inline marks
  make unreadable, so the file keeps the text and the styles apart:

  ```text
  screen 14×3, cursor hidden
  text
  │sent: привет  │
  │[x] 界        │
  │              │
  styles
  │aaaaa         │
  │bbbcbb        │
  │              │
  legend
  a bold
  b red on #010203
  c on #010203
  ```

  Each row is between `│`, so that no editor drops its blanks; the text a
  wide glyph once, the styles a character a cell, a space for no style.
  The legend names each character's style as `matchesScreen` does, a
  hyperlink as `link=` and its target, and a space that shows only its
  background by the background alone. The size and the cursor count;
  images do not. The characters are letters, digits and the rest of
  ASCII first, then letters of other scripts a column wide: about 2000,
  enough for a picture drawn in blocks; a screen of more styles fails.

  Run the tests with `TWK_UPDATE_GOLDENS=1` to write the files from the
  screens instead (`TWK_UPDATE_GOLDENS=1 dart test`): the matcher then
  writes and matches. A style keeps the character the file gave it, so
  the diff of a file written again is what changed. One that fails lists
  the rows whose text differs, the rows whose styles differ (`?` for a
  style the file has no character for), and the first cells whose style
  differs, with both styles.

When a matcher of the screen fails, the message says what the screen has
instead: the line it lacks, the text or style found at the cell, where the
cursor is, or the rows that differ from the snapshot (`-` the snapshot's,
`+` the screen's). Then it shows the screen, rows numbered, as text, or
for `styleAt` with the styles marked as above, with the empty rows at
the end summed up (`matchesScreen(styles: true)` leaves it out: its diff
shows it). Then
comes the widget tree, from the widget `pumpWidget` showed down, as
twk's `debugDumpTree` prints it (`none` before the first frame and once
the app ended), and last the render tree, from the binding's root render
object down, which alone shows each render object's offset, constraints
and flags.

```text
Expected: the cell at column 0, row 0: fg red
  Actual: TwkTester:<fullscreen, 20×3>
   Which: has 'S' there, which is bold yellow

          screen 20×3:
          0│[bold yellow]Save[/]  [reverse]Cancel[/]
          (rows 1–2 blank)

          widget tree:
          Text ‹"Save  Cancel", spans: 3› 20×3

          render tree:
          _RenderView ‹constraints: tight›                                  20×3 ◇
          └─ RenderParagraph ‹"Save  Cancel", spans: 3, constraints: tight› 20×3 ◇

          ◇ relayout boundary
```

### Finders

Finders look for the app's widgets: those of the widget `pumpWidget`
showed and those below it, in the order of the tree, not the binding's
own. They work only inside `testTwk` (a `StateError` outside it or before
`pumpWidget`) and find nothing before the app's first frame or once it
ended.

- `find.byType(Text)` (exactly the type, not its subtypes),
  `find.byKey(key)`, `find.text('Save')` (a `Text`'s string, or the spans
  of a `Text.rich` joined) and `find.byWidgetPredicate(predicate,
  description:)`.
- `find.descendant(of:, matching:)`, what `matching` finds below what
  `of` finds (not itself), and `find.ancestor(of:, matching:)`, what it
  finds above, the nearest first, up to the widget `pumpWidget` showed.
- `.first`, `.last` and `.at(index)` pick one of what a finder finds.

`findsNothing`, `findsOneWidget`, `findsWidgets` and `findsNWidgets(n)`
count what a finder finds: `expect(find.text('Save'), findsOneWidget)`.
A count that fails lists what was found, each with its cells
(`Tile-[<'save'>] at (3, 3), 6×1`), then the widget tree.

The tester reads the one widget a finder finds, a `StateError` naming
what it found when it found none or more: `t.element(finder)`,
`t.widget<T>(finder)`, `t.state<T>(finder)`, `t.renderObject<T>(finder)`
(of the widget, or of the nearest widget below it that has one), and
`t.rect(finder)`, its cells `(x:, y:, width:, height:)` as it was laid out
last: those of the screen, or in the inline mode of the region, row 0
its first, and `t.linesOf(finder)`, the rows of those cells as text. `t.clickOn(finder, button: 0)` clicks the cell in the middle
of those the widget shows, cut where a render object above it cuts them,
as a hit test does (a `StateError` when it shows none); like `click`, it
does not work in the inline mode.

### Frames

`t.frames` are the app's writes to the terminal so far, in order
(`RecordedFrame`): its `number` (from 1), its `time` on the clock, its `bytes` and the `lines`
of the screen it left, replayed on an emulator of their own that resizes
where the terminal did. A frame prints as `frame 3 at 0.050 s, 120
bytes:` and the screen as a failing matcher shows it.

A test that fails prints the last frames of its app that changed the
screen, as text, 3 of them, or as many as `testTwk(..., framesOnFailure:
n)` says (0 for none). Then it prints the app's log (`logs`), its last 20
records: what the app printed, the warnings of a layout that overflowed,
the error of a build that threw, which the screen shows none of.

`t.writeTrace(path)` writes the frames so far as an output trace, each at
its time on the clock, at the size the terminal had when the app started,
with no resizes and no inline history; `addTearDown(() =>
t.writeTrace(path))` keeps the frames of a test that fails. In a
checkout of the [twk repository](https://github.com/pro100andrey/twk),
`dart run tool/replay.dart --fullscreen --trace file` shows the last
screen, with `--step` each frame's and with `--frame=N` frame N's.

### Errors and the end of a test

- If the app ends with an error, the tester call during which it ended
  throws that error (for example a `WidgetError` from an `InputListener`).
  A build that fails does not end the app: it shows an `ErrorWidget`, and
  the error is in `logs`.
- When `body` returns, an app still running is quit, and the rest of its
  frames go through the emulator. An error the app ended with that no call
  threw fails the test, and so do bytes the emulator rejects. If the test
  had already failed, its own error is the one reported.

## Other libraries

- `package:twk_test/vt.dart` (`Vt`, `VtCell`, `VtImage`) is the
  emulator; twk_core's own tests are held to it. A `VtCell` prints as a snapshot with styles shows it
  (`[bold]a[/]`). A DCS or APC string ends at ST alone: a sixel image
  (DCS) and a kitty graphics command (APC `G`) are taken as a terminal
  takes them, what a `DCS tmux;` string holds as the terminal outside
  tmux takes it (an ESC ESC in it is one ESC, and an ESC not doubled is
  an error), and any other changes nothing on the screen. Images
  (`images`): kitty's, transmitted and kept by id (`kittyImages`, their
  bytes), placed, moved with their cells as they scroll and staying over
  them as text is written there, deleted, and freed by `ED 2`; sixel
  images, sized by their raster attributes over cells of
  `cellPixelWidth` × `cellPixelHeight` (10 × 20 by default), the cursor
  left after them as DEC mode 8452 says; iTerm2's (OSC 1337 `File=`);
  the pixels of the last two taken away with what is written or erased
  in their cells. The queries of sizes in pixels (`CSI 14 t`, `16 t`,
  `18 t`) are taken, unanswered.
- `screenFrames(width, height, writes)` plays a program's writes to a
  terminal (`TerminalWrite`s: an output or a resize, at a time) through
  the emulator, and gives a `ScreenFrame` after each output that leaves no
  synchronized update open: its time, size, rows, the cursor, and what
  the emulator could not take up to it. twk_dev's `Cast.writes` are a
  recording's, which so becomes a regression test.
- `package:twk_test/vt_terminal.dart` (`VtTerminal`) is a terminal backend
  in the inline mode that feeds its output to the emulator, below lines
  printed before the app ran.
- `package:twk_test/cli.dart` (`FakeCliTerminal`, and `FakeClock` and
  `Vt` again) is the terminal a test of a program on twk's console
  (`package:twk/cli.dart`) hands a `Cli` or `Cli.run`'s `open:`: it
  captures what is written, answers the plain prompts a line each, types
  keys into the interactive ones, and shows the inline session's screen
  through the emulator.
- `Shot(widget, columns, rows)` shows a widget tree without an app: on a
  screen of its own, built, laid out and painted as a frame is, each
  frame written to an emulator (`vt`). No binding, clock or input: a
  frame runs when `pump(widget)` or `frame()` is called. `rows`,
  `colors(y)` (each cell's glyph, color and background), `attrs(y)` and
  `anyWide` read the emulator back; `owner`, `pipeline`, `root` and
  `top` are the tree's. `Shot.render(renderObject, columns, rows)` shows
  a render object no widget made, and with `under: '.'` fills the screen
  with that character first, which a repaint boundary that leaves a
  cell unpainted shows. Both take `ambiguousWidth`, the screen's and the
  emulator's.
- The screen as text, as the matchers and their failure messages give
  it: `rowText(vt, y, styles: true)` and `screenRows(vt)` (rows plain or
  with styles marked), `describeScreen(vt)` and `describeApp(vt, root)`
  (the screen numbered, and the render tree), `styleOf(cell)`,
  `markedCell(cell)`, `colorName(color)`, `colorOf(color)` and
  `attrNames(attrs)`.
- `FakeStderr` stands in for stderr under `IOOverrides`: it keeps each
  write (`writes`) and their lines (`lines`), each write after what its
  `tag` says when it comes (`FakeStderr(tag: () => 'on screen')`).
- `FakeClock` works on its own too. `run(body)` runs code in its zone, and
  `elapse(duration)` fires the zone's timers as the clock reaches them.
  `flushMicrotasks()` runs the zone's microtasks. It also lets the real
  event loop run its own, since code awaiting a future completed outside
  the zone resumes there. `stopwatch` is a `Stopwatch` that reads the
  clock. `pendingTimers` counts the timers that wait, `nextTimerDue`
  is the time the next of them fires at, and `describeTimers()` lists
  them, each with when it is due and where it was started.
- A program a test runs in a process of its own (a signal, a crash, a
  pseudo-terminal, a VM service) is compiled once per suite, in
  `setUpAll`, by `compiledProgram(path, packages: ..., cache: ...)`, and
  run as `dart <kernel>`: a kernel without the platform, kept in the
  directory `cache` names (`.dart_tool/twk_test/programs`, say) with
  the names of the files it was compiled from and a hash of what they
  hold. A later run with them unchanged compiles nothing; one of them
  edited, added or gone, or another Dart, compiles it again. `defines` are the `-D` declarations it is compiled
  with, a kernel of their own.
- A process a test starts ends with the test, however the test ends
  (it returns, fails, throws or times out): `startProcess` and
  `runProcess` are `Process.start` and `Process.run` with a tear-down
  that kills the process if it still runs then and waits for its exit,
  with a bound. `group: true`, for a process that starts processes of
  its own (a shell, `dart` running an app, a compiler), starts it on
  Linux in a session and process group of its own (`setsid`), seen to
  lead it before it runs, and the tear-down kills that group too, even
  once the process itself has ended. Nothing else is signalled: no
  process is looked for by name, environment or listing, and every
  signal goes through one guard, which refuses a pid that is not the
  process started, 0, 1, -1, and any group but the one made for it,
  never the runner's own.

## Contributing

How the package is tested, and the checks a change passes, are in the
[twk repository](https://github.com/pro100andrey/twk): its
[CONTRIBUTING.md](https://github.com/pro100andrey/twk/blob/main/CONTRIBUTING.md).

## License

MIT, copyright 2026 Andrii Ivanov: [LICENSE](LICENSE).
