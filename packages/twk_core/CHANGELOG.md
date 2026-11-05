# Changelog

## Unreleased

- A repaint boundary's cells do not depend on what was painted in them before: a
  viewport, a list, a log, or a box or text that is a boundary fills with its pen
  and, where that has no foreground, the terminal's own (`StyleTable.ownPen`),
  where text in a pen of no foreground took the colour of what scrolled away.
  `Canvas.fill` keeps what is under a pen of no foreground, as a highlight needs.
- A `RenderEffect` keeps a two-column glyph across its edge whole: the second
  half outside takes the first half's style, a half left alone is put back as a
  blank, and a repaint boundary in it under such a glyph shows its new paint,
  where it was lost until a whole repaint.

- What a `TextPainter` paints does not depend on a query asked before it: spans
  given since the layout are painted as `textRangeAt`, `cellAt` and `columnsOf`
  take them, where they showed only once a query had split them.

- A box title with a line break stays whole when its pen changes, where it was
  cut at the break.

- A `RenderWrap` with no children lays out whatever its alignments, where
  `spaceAround` across its runs divided by zero: a `Wrap` whose last child went
  turned into an error.

- A SIGTSTP from outside (`kill -TSTP`) does nothing while the app has the
  terminal on Linux and macOS, where it stopped the process with the terminal
  raw, on the alternate screen, the cursor hidden. Dart can't watch it, to give
  the terminal back first. Ctrl+Z stops the app for the shell as before.

- A terminal that reads nothing blocks nothing: on Linux and macOS `StdioLink`
  writes without blocking, through a descriptor of its own that the shell does
  not share, and keeps what is not taken, where `stdout` blocked
  the main isolate in write(2), with no timer, key or signal handled until the
  terminal read again: SIGTERM, Ctrl+C or an error ended nothing and left the
  terminal raw.

- SIGHUP restores the terminal and exits with 129 on Linux and macOS too, where
  it left it raw on the alternate screen; one the process was started ignoring
  (`nohup`) stays ignored. `Terminal.close` restores the modes when its terminal
  took nothing for a second, or after five seconds on a link that can't say,
  where a flush that did not end kept it for good; a slow terminal that reads
  gets all of the exit sequence.

- `bidiMirror` finds every character: the table was in the order of the Unicode
  data file, not by code point, so a right-to-left run left six characters from
  U+1DB03 to U+1DB09 unmirrored.

- `Canvas.mergeRun` says it returns the columns it advanced, two for a wide glyph
  of the run, and keeps a wide glyph whole: `under` leaves one the run's edge
  or the clip cuts in its own style, where it painted one half, and a wide
  glyph of the run is drawn as `Canvas.run` draws it, with its width, as the
  documentation said, where it took one cell and asserted.

- `TerminalInfo.remote`, whether the terminal is at the far end of a network: as
  it declares (`TerminalDeclaration.remote`), else by `SSH_TTY` or
  `SSH_CONNECTION` in its environment. `DeclaringLink` and `TerminalDeclaration`
  are exported for a link that knows. `HeadlessTerminal(remote:)` for tests.

Breaking:

- `BoxConstraints` takes its bounds by name, as Flutter's does, a bound left out
  limiting nothing: `BoxConstraints(maxW: n)`, where it was
  `BoxConstraints(0, n, 0, BoxConstraints.unbounded)`.
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
