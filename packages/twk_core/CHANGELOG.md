# Changelog

## Unreleased

Added:

- Debug-mode asserts for the layout contract of a `RenderObject`: a size
  from `performLayout` outside the constraints, a child painted by
  `paintChild` before it was laid out (it painted 0 x 0, unseen), and
  `markNeedsLayout` on an object from inside its own `performLayout` (the
  mark was lost when the layout ended) each fail with a hint.

Fixed:

- An app on a pseudo-terminal of no size (one `script` opens with no
  terminal around it: a background job, CI) has it for its terminal, as
  wide and tall as `COLUMNS` and `LINES` say, else 80 × 24; it ran as plain
  output, by `stdout.hasTerminal`, which such a terminal fails. A stdout a
  test puts in (`IOOverrides`) that says it is a terminal by `hasTerminal`
  still is one, and `/dev/null` is none: an app with its output there runs
  as plain output. `twk shell` (`TerminalShell.start`) serves such a
  terminal too.

Added:

- `stdioIsTerminal()`: whether stdout, or stderr, is a terminal, as an app
  of the core takes it: a pseudo-terminal of no size is one, `/dev/null`,
  a character device, is not.

- `RenderList.jumpToIndex(rows:)`: the item at the top part way into it,
  `rows` of it above the window.

## 0.3.0

Breaking:

- `BoxConstraints` takes its bounds by name: `BoxConstraints(maxWidth: n)`, a
  bound left out limiting nothing. `minW`, `maxW`, `minH`, `maxH`, `constrainW`
  and `constrainH` are `minWidth`, `maxWidth`, `minHeight`, `maxHeight`,
  `constrainWidth` and `constrainHeight`.
- `Flex`, `Row`, `Column`, `Wrap`, `RenderFlex` and `RenderWrap`: `gap` and
  `runGap` are `spacing` and `runSpacing`.
- `log`, `LogLevel`, `LogRecord` and `LogSink` moved from `twk_core.dart` to
  `package:twk_core/terminal.dart` (and `package:twk/log.dart`).
- `AppFrame` and `ShellFrame` replace the integer constants of `Wire`, which
  keeps `protocol` and `maxPayload`. The bytes on the wire are unchanged.
- A process has one terminal: `Terminal.open` on its own stdio throws a
  `TerminalException` while another is open there and not suspended, and
  `resume` while another has it. Terminals over a link are independent.
- An app in the background stops until it has the terminal: `app &` until `fg`.
  `timeout ./app` stops it too, and it ends at the timeout without opening; use
  `timeout --foreground ./app`.

Added:

- `TwkApp(maxInputFps:)`, the cap on frames that input asks for: 120 by default,
  `maxFps` in a remote session or where `maxFps` is below 60.
- `RenderParagraph.keepsPaint`: the paragraph is a repaint boundary that repaints
  only the rows that differ. It must not be drawn over other objects' glyphs or
  be the tree's root. `RenderParagraph(autoKeepsPaint:)`, which `Text` sets, turns
  to it at eight rows or more, after layouts that held its size.
- `TextPainter.prepare` and `draw`, which `paint` is both, and `tracksDamage` with
  `changedRows`.
- `TerminalInfo.remote`, from `TerminalDeclaration.remote` or `SSH_TTY` and
  `SSH_CONNECTION`. `DeclaringLink` and `TerminalDeclaration` are exported.
  `HeadlessTerminal(remote:)` for tests.
- `BoxConstraints.loose`, `expand`, `copyWith`, `loosen`, `enforce`, `tighten`,
  `deflate`, `widthConstraints` and `heightConstraints`, `hasTightWidth`,
  `hasBoundedWidth` and `hasInfiniteWidth` (and for the height), `biggest` and
  `smallest` (a `({int width, int height})`).
- `EdgeInsets.symmetric` and `EdgeInsets.fromLTRB`.
- `RenderList(padding:)`, an `EdgeInsets` around the items that scrolls with them.
- `StyleTable.nearBlank` and `StyleTable.ownPen`.

Changed:

- Frames keep to a grid of `maxFps`; a frame late by a gap or more starts it
  again.
- A frame of a type the receiver does not know is ignored and logged (`twk.wire`)
  on both sides, once a type on a connection.
- A welcome or a size frame of the wrong shape ends the link with a
  `TerminalException`, which `SocketLink.connect` throws.
- SIGHUP restores the terminal and exits with 129 on Linux and macOS. One the
  process was started ignoring (`nohup`) stays ignored.
- `kill -TSTP` does nothing while the app has the terminal on Linux and macOS.
  Ctrl+Z stops the app for the shell as before.
- `StdioLink` writes without blocking on Linux and macOS, through a descriptor of
  its own, and keeps what the terminal does not take.
- `Terminal.close` restores the modes when its terminal took nothing for a
  second, or after five seconds on a link that can't say.
- A repaint boundary's cells do not depend on what was painted in them before: it
  fills with its pen. `Canvas.fill` keeps what is under a pen of no foreground.
- `Canvas.mergeRun` returns the columns it advanced and keeps a wide glyph whole.
- `RenderLog.add` asks for a frame only when the line can show.
- A jump in a `RenderList` with an `itemExtent` takes one division.
- The presenter writes fewer bytes over blanks and compares fewer cells once rows
  stop shifting.

Fixed:

- Images on Konsole, in an inline region and in a fixed viewport: pixels left
  behind, a region not printed again, the saved cursor overwritten, a moved
  placement keeping its old background.
- A `RenderEffect` keeps a two-column glyph across its edge whole.
- A `TextPainter` paints spans given since the layout whether or not a query came
  first.
- A box title with a line break stays whole when its pen changes.
- A `RenderWrap` with no children and `spaceAround` no longer divides by zero.
- `bidiMirror` finds U+1DB03 to U+1DB09.

## 0.2.0

- On Windows Ctrl+Space (and Ctrl+@) reaches the app as NUL again, as it
  did through dart:io's stdin: the console's VT input mode makes it the key
  2 pressed with Ctrl and no character, which the terminal's own reader of
  the console left out.

- On Windows the keys read from the console are encoded to UTF-8 in one
  pass, where they went through a `String`, `utf8.encode` and a copy: a
  read of 512 keys of ASCII, sent to the isolate that listens, takes
  2.5 µs where it took 3.9.

- `package:twk_core/libc.dart`, new: the libc calls twk's packages share
  on Linux and macOS (`poll` and `PollFd`, `read`, `write`, `pipe`,
  `close`, `ioctl` with `fionread`, `tcgetattr` and `tcsetattr`, `calloc`
  and `free`, `errno`), bound once with `@Native` and looked up on their
  first call. The core's reader of the terminal and its raw mode use it,
  as do twk_term's `Pty` and twk's file watch, where each bound its own.
  The kernel32 calls of `WindowsConsole` and `WindowsInput` are now bound
  in one place too, inside the core.

- A `TextPainter` (and a `RenderParagraph`) with `maxLines` 1 and
  `TextOverflow.ellipsis` splits and measures only the head of its text, the
  first columns its first line shows, and the rest only when asked (a
  wider layout, `minIntrinsicWidth`, `maxIntrinsicWidth`): a line of 20 000
  characters cut at the screen's width costs what the screen shows, not the
  line. What is painted, the size and the answers of `cellAt`,
  `textRangeAt` and `columnsOf` are as they were. A start or middle
  ellipsis, a clip and text in visual order with right-to-left characters
  are laid out from all of it. `TextPainter.debugHeadOnly` and
  `debugForceFull` are for tests.

- `mayReorder(String)` is public: whether a string has a character UAX #9
  may draw out of logical order (a right-to-left letter, an Arabic number,
  a right-to-left embedding, override or isolate), skipping at once the
  code units below U+0590. The paragraph's layout and the editing fields
  shared two copies of it, now one.

- `Canvas.text` and `Canvas.run` say in their documentation that they draw
  the string in stored order, for marks, digits and box glyphs, and that
  the text of a user goes through a `TextPainter`, which draws it as it
  reads in visual order.

- In visual order the `BoxTitle`s of a `RenderDecoratedBox` read as a `Text`
  does: a right-to-left title was drawn in stored order, and is now drawn by
  a `TextPainter` the box keeps for it, laid out when the room it is shown
  in or the text order changes, its ellipsis where the paragraph puts it. A
  title is cut and ellipsized in the same columns as before; the place it is
  shown in is unchanged.

- `breakLines`, the lines a text breaks into as a paragraph breaks it.

- An `Align` or a `Center` on an axis of any length is as long as its child,
  as in Flutter: in a scroll view or a list's row it took 1 << 30 rows.

- With the kitty keyboard protocol a lone ESC waits
  `TerminalOptions.escapeTimeout`, as without it, where it waited 500 ms.

Breaking:

- A cell's style id is a `StyleId`, an extension type over int, apart from
  a pen id, which stays an int: `styles.compose(pen, style)` with the
  arguments swapped, a cell's style given to `Canvas.text` as the pen, or a
  pen to `Canvas.runStyled` no longer compile (they painted the wrong style,
  and only a debug assert caught some). Typed with it:
  `StyleTable.style`, `compose`, `blankStyleOf`, `opaqueStyleOf` (which
  answers `StyleId.none`, not -1, for a pen whose style depends on the
  cell underneath), `fgOf`, `bgOf`, `underlineColorOf`, `attrsOf`,
  `linkIdOf`, `linkOf`, `erasable`, `sgrFromReset`, `transition` and the
  `mark` of `sweep`; `Canvas.runStyled`, `runRangeStyled`;
  `Surface.clear`, `scrollRows`, `scrollRect` and the style callback of
  `markCells` (`CellKeeper`); `LineEncoder.text`;
  `RenderEffect.effectCell` and `effectStyle`. `Surface.styles` stays a
  `Uint32List`: `StyleId(surface.styles[i])` reads one, `.value` stores
  one. `StyleId.base` is the style of all defaults, where 0 was. The type
  is erased: no cost at run time.

Added:

- `TextPainter`, the layout engine of `RenderParagraph` on its own, with no
  render tree: `layout(constraints, segmenter:, order:)` sets `width` and
  `height`, `paint(canvas, x, y)` draws at any place, and it answers
  `textRangeAt`, `cellAt`, `columnsOf` and the intrinsic sizes. It reads no
  owner: the segmenter and the text order are given to it, and its setters
  record what they invalidated (`takeInvalidation`: `TextInvalidation.none`,
  `paint` or `layout`). `RenderParagraph` owns one and draws and answers
  as before.
- `RenderParagraph.columnsOf(start, end, y)`, the reverse of `textRangeAt`:
  the columns of a row that draw a range of the text, as the last layout
  placed it (reordered in visual order, cut, justified), or null where none
  does. `cellAt` and it walk a row in one walk, so they read one model of
  it.

Fixed:

- The process's own terminal reads its input itself, in an isolate that
  waits on it beside a wake object, rather than through dart:io's `stdin`,
  which closed the input when the terminal let it go: fd 0 polled beside a
  pipe on Linux and macOS, the console's input buffer waited on beside an
  event on Windows (its key records, the console's VT sequences in its VT
  input mode, as UTF-8). A program started after an app or a session ended
  (`ProcessStartMode.inheritStdio`) reads what is typed again, where it got
  "Bad file descriptor", and a terminal opened again in the same process
  reads keys. Paused or closed, it reads nothing more from that moment,
  even while its isolate is still starting, and nothing of it keeps the
  process alive. A reading isolate that fails ends the input with a
  `TerminalException`. On Linux and macOS it reads what fd 0 has before it
  waits, as dart:io does: a paste goes through faster than through
  dart:io's `stdin` (8 MB through a pseudo-terminal in 67 ms, against 77),
  a key as fast.

## 0.1.0

The first release.

- `TwkApp`, the frame loop: input, layout and paint of what changed, one
  write per frame with backpressure; fullscreen, inline under the shell's
  history (`commit`, `shrinkRegion`) and in a fixed `Viewport`; the last
  frame as plain text where the output is no terminal.
- `Screen`, `Surface` and `Canvas`: a packed cell buffer, interned glyphs
  (`GlyphTable`) and styles (`StyleTable`, `Pen`, `Color`, `Attr`), drawn
  through clips and translations; images in reserved cells
  (`TerminalImage`, `ImagePlacement`) with kitty graphics, sixel or
  iTerm2. A pen is the table's for good, a style until the table is
  swept: `Screen.render` frees the styles no cell has once twice as many
  are in use as after the last sweep (`StyleTable.sweep`, `sweeps`), so a
  screen of ever new colors keeps those it shows; `Canvas.runStyled`
  draws in a style as it is, with no pen. The glyphs of several code
  points are swept the same way (`GlyphTable.sweep`, `sweeps`), and what
  keeps cells of a surface beyond it registers to be marked
  (`Surface.keep`, `CellKeeper`).
- `Presenter`: the damaged spans diffed against what the terminal shows
  and written with DEC 2026, scroll regions, `ICH`/`DCH`, `REP`, `ECH`
  and `EL`, as `TerminalCaps` allow.
- The render tree: `RenderObject`, `PipelineOwner`, boxes, text and
  paragraphs, padding and constraints, flex, stack, grid, wrap, lists,
  logs and viewports, effects, and diagnostics.
- `Terminal`: the process's terminal on Linux, macOS and Windows, or one
  over a `TerminalLink`; a capability probe, raw mode, resizes, the
  terminal restored on every exit path; titles, progress, notifications,
  the clipboard, links and pointer shapes.
- `InputParser` and `InputEvent`s: keys (with the kitty keyboard
  protocol), the mouse, paste, focus, resize and color scheme reports;
  what it holds of a paste or an unterminated sequence bounded
  (`pasteLimit`, `sequenceLimit`), a longer paste in pieces
  (`PasteEvent.more`).
- Unicode: grapheme segmentation, widths in two modes (`TextSegmenter`,
  `stringWidth`, `fitText`, `breakLines`) and bidirectional text (`BidiText`).
- `package:twk_core/terminal.dart`: the terminal, styles, input and lines
  of text without the render tree.
- `HeadlessTerminal`, `renderToString` and `LineEncoder`, for tests and
  one-off output.
