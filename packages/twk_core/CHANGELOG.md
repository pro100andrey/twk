# Changelog

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
  `stringWidth`, `fitText`) and bidirectional text (`BidiText`).
- `package:twk_core/terminal.dart`: the terminal, styles, input and lines
  of text without the render tree.
- `HeadlessTerminal`, `renderToString` and `LineEncoder`, for tests and
  one-off output.
