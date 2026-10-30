# twk_core design: §1.12 Inline mode

[The design](README.md)

`TerminalOptions(alternateScreen: false)` runs the app in a region of the
normal screen instead of on the alternate one: an equal of the fullscreen
mode (which stays the default) for prompts, progress views and agents
whose output belongs in the terminal's history. `TwkApp` lays the tree out
in that region:

* it starts on the line the cursor is on (the probe asks where with
  `CSI 6 n`; after text on that line, or with no answer, on the next line)
  and is as tall as the root's max intrinsic height at the terminal's
  width: at least one row, at most `maxInlineRows` or the terminal's
  height;
* it grows as the content does: line feeds below its last row make room,
  so once it reaches the bottom of the screen the history above scrolls up
  into the scrollback. It shrinks only on `shrinkRegion()`, so content
  that comes and goes doesn't make it jump; the rows it leaves are erased;
* no row above it is ever written but by `commit` (below), and no row is
  addressed absolutely (the region doesn't know which screen row it is
  on): every cursor move is relative (`CUU`/`CUD` with `CR`, `CHA` or
  `CUF`/`CUB`, never `CUP`); a scroll inside it is a `DL` at the row the
  moving block loses and an `IL` at the row it gains, which leaves every
  row outside the block where it was (no `DECSTBM`, no `DECSLRM`); a full
  frame erases from its first row down (`ED 0`), not the whole screen;
* a resize repaints it from scratch at the new size: the terminal keeps the
  cursor on its line while it cuts or reflows the rows around it, so moving
  up by the cursor's row in the region finds the region's first row again
  (or the screen's first row, if the screen got so short that it went into
  the scrollback);
* `commit(content)` puts finished content in above it as lines of the
  terminal's history: a
  `RenderParagraph` of finished messages, a log, results, or any render
  object, laid out at the terminal's width, as tall as its max intrinsic
  height there, painted and written in the synchronized update of the
  region's frame. Nothing writes those lines again, so the terminal's
  scrollback and selection work on them. They go in with `IL` at the
  region's first row after line feeds below its last row made room, so
  the region moves down as it is, as many at a time as the screen has rows
  besides the region's (`Presenter.screenHeight`, which `TwkApp` keeps
  up to date); when it has none (or on a full frame) they are printed
  from the region's first row down and the region is drawn again below
  them. A frame writes at most 256 committed rows, so a burst of
  thousands holds neither input nor the region up, and what still waits
  when `run()` ends is written before the region is left. The widget
  layer's `Static` commits the items it is given so, and asks for a
  `shrinkRegion()` in the build that commits them (`beforeLayout`), which
  that frame takes: the rows of what left the region in the same build
  take the committed rows, instead of the history scrolling up while the
  region keeps blank rows. Underneath,
  `Screen.commit` and `Presenter.commit` take rows of a `Surface`;
* what the root's max intrinsic height throws while the region is sized, and
  what a commit's sizing, layout or paint throws, ends `run()` unless the
  `owner` has `onError` ([§1.8](render.md)). Then the region's error is
  reported there as the root's, in `RenderPhase.layout`, once while it is
  the same: the region keeps its height (1 row on the first frame, within
  its limits) and a `shrinkRegion()` waits for a frame that sizes it. A
  commit's is reported once as the commit's, in the phase it threw in
  (sizing as `RenderPhase.layout`), and a `RenderErrorBox` with the message,
  at the terminal's width and as tall as the message there, goes to the
  history in its place. The region and later commits go on;
* when `run()` ends it stays on the screen with the cursor at the start of
  the line below it, or with `clearInlineOnExit` it is erased and the
  cursor is back on its first row;
* the mouse stays the terminal's (`TerminalOptions.mouse` and a switch of
  `mouseTracking` are ignored on the normal screen unless
  `normalScreenMouse` is set, which a fixed viewport, [§1.13](viewport.md),
  wants): its wheel scrolls the scrollback and its selection works, and
  mouse reports would give screen rows, which the region doesn't know.

The rest — damage, the diff, SGR, ICH/DCH, REP, DEC 2026 — works as in
the fullscreen mode, in the same presenter (`Presenter.inline`).
