# Changelog

## Unreleased

Breaking:

- `TwkApp(clock:)` takes a `Clock`, not a `Stopwatch`; `TwkApp.clock` is a
  `Clock`. A frame that waits is started with `clock.timer`, so a clock that
  moves when told to spaces the frames and holds the timers.

Added:

- `Clock` (an `int` of microseconds, `timer`, `periodic`; `ClockElapsed` reads
  it as a `Duration`) and `SystemClock`, the real one, the default.
- Keys of the kitty keyboard protocol. `KeyCode.modifier`, `KeyCode.lock` and
  `KeyCode.media`, and `KeyEvent.kittyCode` (`KittyKey` has the codes and
  their names): with the protocol's flag 8 the parser reads Shift, Ctrl, Alt,
  Super, Hyper and Meta (left and right), the ISO level shifts, Caps, Num and
  Scroll Lock and the media keys, with their repeats and releases (flag 2), as
  `KeyEvent`s. A shortcut cannot name them. `KeyEvent.baseChar` is the
  character of the same key on a US layout, from the alternate keys flag:
  Ctrl and the key that types `с` is `c`. `KeyEvent ==` and `hashCode` leave
  it out, so `key == ctrlC` holds on a Russian layout too. `Terminal` pushes
  `KittyKeyboardFlags.alternateKeys` with disambiguation always, whatever
  `TerminalOptions.kittyKeyboardFlags` says; `TerminalInfo.kittyKeyboardFlags`
  is 5 by default.
- Pixel mouse: where the terminal answers DECRQM for SGR-Pixels (mode 1016)
  and a cell's size is known, the mouse is reported in pixels and
  `InputParser` divides them into the cell and `MouseEvent.offsetX` and
  `offsetY` (pixels into the cell; null where the terminal reports cells).
  `TerminalOptions.pixelMouse` (true) turns it off, `TerminalInfo.pixelMouse`
  says. A cell's size comes from `CSI 16 t`, else the tty (`ws_xpixel`,
  `ws_ypixel`, through `PixelSizedLink`), else `CSI 14 t` over the size in
  cells, and is asked again at each resize, over a socket or ssh too, so
  `TerminalCaps.cellPixelWidth` is known on more terminals and follows a font
  change. `MouseTrackingBackend.cellPixels` passes it on through a wrapper of
  a `Terminal`. `mouseTrackingSequence(pixels:)`.
- kitty's images: `ImageKeep` and `TerminalImage(keep:)` leave the images of
  one keep on the terminal while no placement shows them, so that one shown
  again is placed and not sent; they are deleted once the keep is let go of
  (`kept = false`) and on leaving the screen.
- kitty's animation: `TerminalImage(animation:)` takes an `ImageAnimation`
  (the PNG files of the frames after the first, each frame's time, the
  plays), which the presenter sends once with the image to a terminal that
  plays it (`TerminalCaps.kittyAnimation`); `TerminalImage.playing` stops it
  where it is and runs it again. `ImageAnimation.loading` takes its frames as
  they are made (`add`, then `finish`): the terminal plays those it has and
  waits at the last for more. `Terminal.open` sets the capability for kitty
  alone (by XTVERSION, else by `KITTY_WINDOW_ID`); Konsole and Ghostty take
  kitty's images but are not known to play them, and get the first frame.
- `TerminalInfo.sextants` and `sextantsFor`: whether the terminal is known to
  draw the block sextants (U+1FB00..1FB3B) itself: kitty 0.19.3 on, foot,
  Ghostty 1.0 on, WezTerm 20210814 on, Konsole 22.04 on, VTE 0.78 on, Contour
  0.3.1 on, Rio 0.4.6 on; not inside tmux or screen. An unknown terminal is
  false.
- Terminology and fbterm: the probe asks the tertiary device attributes (DA3)
  and a terminal that answers Terminology's gets 256 colors, over ssh or under
  sudo as well; `colorModeFor` gives 256 colors to `TERM=terminology` and
  `fbterm`.
- `TerminalInfo.terminalVersion`: the name and version the terminal told by
  XTVERSION (`kitty(0.39.1)`), empty where it did not tell.
- The cursor's color. `TerminalInfo.cursorRgb` is the terminal's (OSC 12),
  null where it did not answer, and the input parser reads `OSC 12` replies
  as `ColorReport(which: 12)`; `HeadlessTerminal(cursorRgb:)`. The probe's
  bytes change by that query. `Presenter.cursorColor` sets the visible
  cursor's color (`OSC 12`, `OSC 112` putting the terminal's own back): an RGB
  color as it is, a palette color as the RGB the core knows for it, nothing
  where colors are off. `TwkApp` gives it back on exit and when the terminal
  is handed over.
- Under a visible block cursor (`CursorShape.block`, `blinkingBlock`,
  `terminalDefault`) the presenter writes a blank cell in its own foreground:
  Konsole paints the block in the foreground of the cell under it, so the
  cursor changed color after a Backspace. A bar, an underline or no cursor
  change nothing.
- `CountingBackend`, which `Terminal` and `HeadlessTerminal` implement: the
  bytes read (`bytesRead`, `bytesReadAtOpen`), whether the parser holds some
  (`inputPending`), a call at the end of each read (`onRead`) and the bytes
  accepted for writing (`bytesWritten`). `TwkApp` has `quitting` (whether
  `quit` was called), `inputRead`, `scheduled`, `frameDue`, `framesRun`,
  `frameEnd`, `inputPending` and `onInputSettled`: what a program that drives
  the app syncs on. `quit` has the settled acknowledgement go out before
  `run` hands the terminal back.
- `stdioIsTerminal()`: whether stdout, or stderr, is a terminal, as an app of
  the core takes it: a pseudo-terminal of no size is one, `/dev/null` is not.
- `RenderList.jumpToIndex(rows:)`: the item at the top part way into it,
  `rows` of it above the window.
- The overflow marker. A `RenderFlex`, `RenderWrap` or `RenderGrid` whose
  content needs more room than it has paints, in debug mode, over the edge it
  is cut off at: a yellow hatch `▚` down the right edge or along the bottom
  one (`/` where the terminal draws `▚` two cells wide), and the cells cut off,
  `+3`, in the corner. It is on while asserts are, and elsewhere where
  `PipelineOwner.debugOverflowIndicator` is set (`debugOverflowIndicatorByDefault`
  for the owners made afterwards; `TWK_DEBUG=overflow`; the debug key `w` of
  twk). `overflowIntended` on the three render objects says a box clips on
  purpose: no marker, no warning. The warning carries an `OverflowReport`
  (`LogData`, in `terminal.dart` and `package:twk/log.dart`, which
  `LogRecord.toJson` and the twk console leave out as not an error to print).
  Output that is data has no marker: `renderToString`, the inline commits
  (`TwkApp.commit`), `Shot`'s captures and plain output (a pipe, a file, CI);
  `PipelineOwner.forData` makes such an owner. `debugAssertsEnabled` (re-
  exported by twk) says whether asserts are on. `PipelineOwner.onObjectLog`
  gives a binding the render object that raised each warning of the tree.
- In a debug run a `RenderFlex` logs a warning, once, when a flexible child
  (`Expanded`, `Flexible`) is laid out by its content because the main axis is
  unbounded, and `Canvas.text` logs, once per character, a control character
  it drops (`Canvas.onDroppedControl`): for an ESC (which leaves `[31m` as
  letters) it points at `Text` with spans, for a newline or a carriage return
  at text split into lines.
- Debug-mode asserts for layout and paint, each failing with a hint: a size
  from `performLayout` outside the constraints; a child painted by
  `paintChild` before it was laid out; `markNeedsLayout` from inside the
  object's own `performLayout`; `RenderObject.width` or `height` read by a
  parent in its own layout after the child was laid out without
  `parentUsesSize: true`; a `paint` that calls `Canvas.save()` without
  `restore()` (`Canvas.debugSaveDepth`); an object that marks itself for paint
  inside its own `paint` in three paints in a row; a `BoxConstraints` with a
  negative bound, and `Canvas.fill` or `Canvas.clipRect` with a negative width
  or height. `PipelineOwner.debugCheckIntrinsics` (off by default,
  `debugCheckIntrinsicsByDefault`) asserts that the intrinsic sizes of an
  object are not negative and a minimum is not above its maximum.
  `Surface.debugRepairWide` logs as an error, and blanks, a wide glyph split
  in the damaged cells by a painter that writes `Surface.cells` itself.

Changed:

- A short text laid out is cheaper, edited or new: a short edit splits the
  text again whole rather than finding where it changed, and where lines may
  break by word is found only when a line does not fit.
- A repaint boundary (or the root) repaints the places of what was marked in
  it, each on its own, not one band of rows across its whole width: a row of
  text changed beside an unchanged panel no longer repaints the panel, nor has
  the presenter compare its cells. Rows across, as before, where a wide glyph
  lies across a place's side, under an underlay, where the boundary is
  overlapped or marked whole, and past 8 places. A mark below a `RenderEffect`
  is cheaper too.
- A `RenderParagraph` that keeps its paint by itself (`autoKeepsPaint`, which
  `Text` sets) turns plain after four paints in a row of seven eighths of its
  rows or more, as a text of a fixed size whose lines all change at each edit
  gives (a log's tail): keeping saved it nothing and cost 5 to 6 %. It tries
  again after a while. `keepsPaint` never turns.
- kitty's protocol: an image that replaces another is placed before the old
  one is deleted, so that a terminal that draws in between (Konsole) never
  shows the cells empty: an animated GIF drawn frame by frame no longer
  flickers there.

Fixed:

- Konsole 26.04 and later gets synchronized output (DEC 2026): it honours the
  mode but answers no DECRQM, so the probe took it for a terminal without
  and every frame there could be shown half drawn. What a terminal does
  without answering a query is now read from one identification of it (the
  name it tells, else its own `TERM`, else its `TERM_PROGRAM`, else
  `KONSOLE_VERSION` or `VTE_VERSION`) and one table of known terminals,
  where the version thresholds of Konsole and VTE (notifications, REP,
  pointer shapes, progress, sextants, bidi, Konsole's lines) are written
  once. So Konsole told by its name over ssh, where `KONSOLE_VERSION` is not
  passed on, now gets its pointer shapes, progress and sextants too, and a
  terminal started from Konsole that names itself (VS Code's) no longer
  gets Konsole's lines or notifications by the variable it inherited.
- On a terminal without synchronized output (DEC 2026) a scroll view
  narrower than the screen no longer tears while the frame is drawn: its
  rectangle was scrolled as whole rows and the cells beside it (a sidebar,
  a file list) were written back only afterwards, so a terminal that drew
  mid-frame showed them moved with the rows. There it is now re-diffed
  instead, as on a terminal with DECSLRM it is scrolled within margins.
- A second `Terminal.open` while the first is still opening is refused with
  its own message (await the first), not the one for a terminal that can be
  suspended or closed.
- Reading whether SIGHUP is ignored no longer reads address 0 when the
  allocation fails.
- An app on a pseudo-terminal of no size (one `script` opens with no terminal
  around it: a background job, CI) has it for its terminal, as wide and tall
  as `COLUMNS` and `LINES` say, else 80 × 24; it ran as plain output. A stdout
  a test puts in (`IOOverrides`) that says it is a terminal still is one, and
  `/dev/null` is none: an app with its output there runs as plain output.
  `twk shell` (`TerminalShell.start`) serves such a terminal too.

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
