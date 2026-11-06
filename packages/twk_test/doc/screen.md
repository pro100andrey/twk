# Reading the screen

The screen, its matchers, finders and recorded frames. Part of the
[guide](guide.md); the [README](../README.md) says what the package is for.

## The screen

- `lines` gives the screen's rows as text, without the blanks that end them,
  with a wide glyph shown once.
- `scrollback` gives the lines scrolled off the top in the inline mode, oldest
  first.
- `linesIn(region)` gives the rows of a rectangle `(x:, y:, width:, height:)`,
  as `rect` gives one, as `lines` gives the screen's, from the rectangle's
  first column: `t.linesIn((x: 12, y: 0, width: 12, height: 3))`. As many rows
  and columns are read as the screen has. `t.linesOf(finder)` gives those of
  the cells of a widget.
- `cell(x, y)` gives one cell: `text` (`''` for the right half of a wide
  glyph), `fg`, `bg`, `ul` (the underline color) and `attrs`. The colors and
  attributes are numbered as `Color` and `Attr` number them, with `0` for the
  terminal's default color: `expect(t.cell(0, 0).fg, Color.red)`,
  `expect(t.cell(0, 0).attrs, Attr.bold)`. `fgColor`, `bgColor` and `ulColor`
  give the colors as `Color`s, `Color.defaultColor` for `0`.
- `cursor` is the cursor's (column, row) and `cursorVisible` whether it is
  shown.
- `vt` is the emulator itself (`Vt`).
- `written()` is what the app wrote to the terminal, as text: the bytes of
  every frame decoded as UTF-8, a byte that is not as U+FFFD; and
  `written(since: n)` those of the frames from `terminal.frames[n]` on. It is
  where a test looks for what the screen does not show: a mode set, the
  clipboard written (OSC 52), a notification, a scroll.

The emulator is strict: a sequence it does not know, text that wraps or
scrolls the screen, a write to the inline mode's history, an absolute row in
the inline mode, or an image it can't take (a kitty command without `q=2`, a
placement of an image not sent, not sized in cells or without `C=1`; an image
over text, past the screen or one that scrolls it) throws when the screen is
read. A `Vt` of your own that replays what a real program wrote, a recorded
session, is made with `Vt(width, height, strict: false)`: what it does not
take is then kept in `vt.errors`, not thrown. `t.vt.images` lists the images
on the screen (`VtImage`: the protocol, a kitty image's id and placement, its
bytes, the cells it still has and, for kitty, the part shown), top to bottom.

## Matchers

The matchers of the screen take the tester: `expect(t, containsLine('ok'))`.

- `containsLine(line)`: a row of the screen is `line`, as `lines` gives the
  rows. Given a matcher (`startsWith('sent:')`), a row it matches.
- `hasTextAt(x, y, text)`: the cells from column `x` of row `y` on show
  `text`. As many cells are read as `text` is wide.
- `within:` on both, a finder, or `withinRect:`, a rectangle (a `CellRect`, as
  `t.rect(finder)` gives one; not both), limits them to the cells of a widget
  or a region, so a title printed twice on a row, in a list and in a panel, is
  matched in the one: `expect(t, containsLine('> one', within:
  find.byType(ListView)))`. For `hasTextAt` `x` and `y` count from the
  region's first cell, and the cells read stop at its edge. A match that fails
  says where the screen shows the text outside the region, if it does: `has
  none in the cells (12, 0), 5×3, but the screen shows '> one' at column 0,
  row 1`.
- `styleAt(x, y, matcher)`: the cell at column `x` of row `y` matches
  `matcher`. The matchers of a cell are `hasAttr(Attr.bold)` (every attribute
  given; an underline matches only the same kind of underline),
  `hasFg(Color.red)` and `hasBg(color)`. They take a cell on its own too:
  `expect(t.cell(0, 0), hasFg(Color.red))`.
- `cursorAt(x, y)`: the cursor is shown, at column `x` of row `y`.
- `matchesScreen(snapshot)`: the screen is `snapshot`, a string in the test
  whose lines are the rows of the screen from the top. The blanks that end a
  line and the empty lines that end the screen don't count, on either side:

  ```dart
  expect(t, matchesScreen('''
  sent: привет
  [x] done
  '''));
  ```

  Indentation counts, so the snapshot's lines start at the start of the line
  in the source.
- `matchesScreen(snapshot, styles: true)` compares styles too. Each run of
  cells of one style is in `[style]…[/]`: `[bold]sent:[/] привет [red on
  #102030]ok[/]`.
  - A style lists the attributes first, by their names in `Attr` (`bold`,
    `curlyUnderline`). Then come the color, `on` and the background, and `ul=`
    and the color of the underline. Each is left out when it is the default.
  - A color has its name in `Color` (`red`, `brightBlack`, and `brightRed` and
    so on for 9 to 14), `indexed(n)` for the rest of the palette, or `#rrggbb`
    for a 24-bit color.
  - A `[` of the text is written `[[`.
  - A space shows only its background, unless it has an attribute that shows
    on a blank (`Attr.visibleOnBlank`: underlines, reverse, strike, overline).
    Between two cells of one style with that background, the space is in their
    run. Elsewhere its style is its background, and spaces with no background
    at the end of a row are left out.
- `matchesScreenFile(path, {styles = true})`: the screen is the one the file
  at `path` holds (a golden file); a relative `path` is from the root of the
  calling test's package, wherever the suite is run from: the package of the
  file the call is in, found from the stack (the nearest `pubspec.yaml` above
  it), so a helper in another package's `test/` that calls it reads from that
  package; an absolute `path` is as it is. With `styles: false` the size,
  cursor and text are compared and the styles are not. A whole screen of a
  themed app is a run of styles in nearly every cell, which inline marks make
  unreadable, so the file keeps the text and the styles apart:

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

  Each row is between `│`, so that no editor drops its blanks; the text a wide
  glyph once, the styles a character a cell, a space for no style. The legend
  names each character's style as `matchesScreen` does, a hyperlink as `link=`
  and its target, and a space that shows only its background by the background
  alone. The size and the cursor count; images do not. The characters are
  letters, digits and the rest of ASCII first, then letters of other scripts a
  column wide: about 2000, enough for a picture drawn in blocks; a screen of
  more styles fails.

  Run the tests with `TWK_UPDATE_GOLDENS=1` to write the files from the
  screens instead (`TWK_UPDATE_GOLDENS=1 dart test`): the matcher then writes
  and matches. A style keeps the character the file gave it, so the diff of a
  file written again is what changed. One that fails lists the rows whose text
  differs, the rows whose styles differ (`?` for a style the file has no
  character for), and the first cells whose style differs, with both styles.

When a matcher of the screen fails, the message says what the screen has
instead: the line it lacks, the text or style found at the cell, where the
cursor is, or the rows that differ from the snapshot (`-` the snapshot's, `+`
the screen's). Then it shows the screen, rows numbered, as text, or for
`styleAt` with the styles marked as above, with the empty rows at the end
summed up (`matchesScreen(styles: true)` leaves it out: its diff shows it).
Then comes the widget tree, from the widget `pumpWidget` showed down, as twk's
`debugDumpApp` prints it (`none` before the first frame and once the app
ended), and last the render tree, from the binding's root render object down,
which alone shows each render object's offset, constraints and flags.

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

## Finders

Finders look for the app's widgets: those of the widget `pumpWidget` showed
and those below it, in the order of the tree, not the binding's own. They work
only inside `testTwk` (a `StateError` outside it or before `pumpWidget`) and
find nothing before the app's first frame or once it ended.

- `find.byType(Text)` (exactly the type, not its subtypes), `find.byKey(key)`,
  `find.text('Save')` (a `Text`'s string, or the spans of a `Text.rich`
  joined), `find.textContaining('Sav')` (a match in them, of a `String` or a
  `RegExp`) and `find.byWidgetPredicate(predicate, description:)`.
- `find.descendant(of:, matching:)`, what `matching` finds below what `of`
  finds (not itself), and `find.ancestor(of:, matching:)`, what it finds
  above, the nearest first, up to the widget `pumpWidget` showed.
- `.first`, `.last` and `.at(index)` pick one of what a finder finds.

`findsNothing`, `findsOneWidget`, `findsWidgets` and `findsNWidgets(n)` count
what a finder finds: `expect(find.text('Save'), findsOneWidget)`. A count that
fails lists what was found, each with its cells (`Tile-[<'save'>] at (3, 3),
6×1`), then the widget tree.

The tester reads the one widget a finder finds, a `StateError` naming what it
found when it found none or more: `t.element(finder)`, `t.widget<T>(finder)`,
`t.state<T>(finder)`, `t.renderObject<T>(finder)` (of the widget, or of the
nearest widget below it that has one), and `t.rect(finder)`, its cells `(x:,
y:, width:, height:)` as it was laid out last: those of the screen, or in the
inline mode of the region, row 0 its first, and `t.linesOf(finder)`, the rows
of those cells as text. `t.clickOn(finder, button: 0)` clicks the cell in the
middle of those the widget shows, cut where a render object above it cuts
them, as a hit test does (a `StateError` when it shows none); like `click`, it
does not work in the inline mode.

## Frames

`t.frames` are the app's writes to the terminal so far, in order
(`RecordedFrame`): its `number` (from 1), its `time` on the clock, its `bytes`
and the `lines` of the screen it left, replayed on an emulator of their own
that resizes where the terminal did. A frame prints as `frame 3 at 0.050 s,
120 bytes:` and the screen as a failing matcher shows it.

A test that fails prints the last frames of its app that changed the screen,
as text, 3 of them, or as many as `testTwk(..., framesOnFailure: n)` says (0
for none). Then it prints the app's log (`logs`), its last 20 records: what
the app printed, the warnings of a layout that overflowed, the error of a
build that threw, which the screen shows none of.

`t.writeTrace(path)` writes the frames so far as an output trace, each at its
time on the clock, at the size the terminal had when the app started, with no
resizes and no inline history; `addTearDown(() => t.writeTrace(path))` keeps
the frames of a test that fails. In a checkout of the [twk
repository](https://github.com/pro100andrey/twk), `dart run tool/replay.dart
--fullscreen --trace file` shows the last screen, with `--step` each frame's
and with `--frame=N` frame N's.
