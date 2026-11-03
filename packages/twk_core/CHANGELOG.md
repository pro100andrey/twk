# Changelog

## Unreleased

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
