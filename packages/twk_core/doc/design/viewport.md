# twk_core design: §1.13 Fixed viewport

[The design](README.md)

`TwkApp(terminal, viewport: Viewport.fixed(left, top, width, height))`
lays the tree out at that rectangle and draws it there, on whichever
screen the terminal is on (the normal one with
`TerminalOptions(alternateScreen: false)`): an app beside a shell's output, a status panel in a
corner. Nothing outside the rectangle is written, in the same presenter
(`Presenter(viewport:)`, `Screen(viewport:)`):

* cells are addressed with the offset (`CUP`, `CHA`; `CR` only where the
  viewport starts at the first column); no `ED 2`; `EL`, `ICH` and `DCH`
  only where the viewport ends at the screen's right edge, `ECH`
  elsewhere;
* a scroll stays inside: `DECSTBM` with `SU`/`SD` only where the viewport
  is as wide as the screen, `DECSLRM` margins at its columns where the
  terminal has them, else the rows are written again;
* a glyph terminals may draw wider (`kUncertain`) that could reach past
  its right edge is drawn as blanks;
* each frame turns autowrap off while it draws and on again at its end;
  the first frame saves the cursor (`DECSC`), and each frame that leaves
  it hidden puts it back (`DECRC`), as handing the terminal back
  (`leave`, at the end of `run()` and on `suspend`) does, so the cursor
  of the shell around it stays where it was;
* a resize cuts the rectangle to the screen (down to nothing) and gives
  the part cut off back as the screen grows; the viewport is painted
  again in full on every resize;
* mouse events come in its coordinates, those outside it dropped; drags
  and the release of a button pressed inside it come at the nearest cell
  inside. On the normal screen a `Terminal` reports the mouse only with
  `TerminalOptions(normalScreenMouse: true)` (`HeadlessTerminal` too);
* `commit` throws: the viewport has no history above it; and
  `clearInlineOnExit` is the inline mode's.

On plain output ([§1.7](terminal.md)) the viewport is laid out at its own size, neither
cut nor placed, and its last frame written as lines like any other.
