# twk_core design: §1.8 Flutter-like layer

[The design](README.md)

## The render tree

`render/render.dart` is a retained render tree, one library in part files by
topic beside it (`object.dart`, the render object and what it is made of;
`pipeline.dart`, the `PipelineOwner`; `boxes.dart`, `decoration.dart`,
`flex.dart`, `stack.dart`, `grid.dart`, `wrap.dart`, `text.dart`,
`log.dart`, `viewport.dart`, `list.dart`, `effect.dart`, `error_box.dart`,
`debug_paint.dart`), so that its private names reach across them. The widget
layer of [`packages/twk`](../../../twk/doc/reference/README.md) sits on it
as Flutter's does: elements create these objects and set their properties,
and widgets know nothing about diffs, bytes or terminals.

## Layout

Layout is `BoxConstraints` down / sizes up (`BoxConstraints.tight`,
`.tightFor(width:, height:)`; `BoxConstraints.unbounded` is an extent no
screen reaches). An object is a *relayout boundary* when its size can't
change its parent's layout: its constraints are tight, it is
`sizedByParent` (`RenderBox`, `RenderText`, `RenderLog`, `RenderDivider`,
`RenderList`, and `RenderPositionedBox` without factors), it is the root,
or its parent
lays it out without `parentUsesSize`. Every `layout()` call decides it
again, so a change of constraints moves the boundary. `markNeedsLayout()`
marks the object and its ancestors up to the nearest boundary, which goes
on the owner's list of layout roots; `flushLayout` lays the root out when
the screen size is new, then each marked boundary, outermost first, within
the constraints it had (one an ancestor laid out on the way is skipped),
then, pass by pass and the same way, the boundaries that layout callbacks
(below) marked meanwhile, until a pass marks none: what is painted next
has all been laid out. After 100 passes what is still marked waits for
the next frame, and the boundary whose layout marked it last shows and
reports an error that says the layout does not settle. Like `flushPaint`
it reuses its lists and allocates nothing once warmed up. A boundary whose size changed (one its parent doesn't use) has the
parent repaint the cells it left; a boundary marked while detached is
queued when it is attached again.

## Parent data

What a parent keeps on each child is the child's `parentData`, of the
kind the parent's `setupParentData` gives a child it adopts: its offset,
in a flex (`FlexParentData`) its siblings, flex factor and fit, in a
stack (`StackParentData`) its siblings and where it is pinned, in a
grid (`GridParentData`) its siblings and the cells it takes, in a wrap
(`WrapParentData`) its siblings, and in a lazy list (`ListParentData`)
its siblings and its index. An
object with one child mixes in `RenderObjectWithChildMixin` (setting
`child` drops the old one and adopts the new); one with a list mixes in
`ContainerRenderObjectMixin` (`insert(child, after:)`, `add`, `addAll`,
`move(child, after:)`, `remove`, `removeAll`, `firstChild`, `lastChild`,
`childBefore`, `childAfter`, `childCount`), whose list is linked through
the children's parent data (`ContainerParentDataMixin`): inserting,
moving and removing take the same time at any position, walking the list
allocates nothing, and a change to it lays the parent out again.

## The objects

Besides `RenderFlex`, `RenderStack`, `RenderGrid`, `RenderWrap`,
`RenderParagraph` (below), and `RenderLog`, `RenderViewport`,
`RenderList` and `RenderEffect` (under Paint), the objects are:

* `RenderBox` is as big as the constraints allow, fills itself with a pen
  and insets its child by `padX` and `padY`; `RenderText` is as wide and
  one row tall: one line in one pen, shaped once per change and cut off at
  its right edge. Both can be repaint boundaries;
* `RenderPadding` insets its child by an `EdgeInsets` (`.all`, `.x`, `.y`,
  `.only`, `zero`) and is as big as the child and the padding, within its
  constraints;
* `RenderPositionedBox` places its child, laid out with no minimum, as an
  `Alignment` says (`x` and `y` each -1, 0 or 1; `center`, `topLeft` and
  the seven others): in the middle the odd cell goes after the child, and
  a child bigger than the box sticks out by the odd cell more after it.
  The box is as big as the constraints allow, or along an axis with an
  integer `widthFactor` / `heightFactor` that many times as long as its
  child;
* `RenderConstrainedBox` lays its child out within `additionalConstraints`,
  each limit kept within its own constraints, and is as big as the child
  (without one, as small as both allow);
* `RenderFractionallySizedBox` lays its child out at fractions of the
  most room it may take: `widthFactor` of its max width wide and
  `heightFactor` of its max height tall (finite, 0 or more), each rounded
  to the nearest cell, a half up (a third of 10 cells is 3, a half of 5
  is 3). Along an axis without a factor, or one its constraints leave
  unbounded, the child is laid out within them. The box is as big as the
  constraints allow, along an unbounded axis as long as its child
  (without one, as short as they allow), and places the child as its
  `alignment` says; a child bigger than the box (a factor above 1) sticks
  out and is cut off;
* `RenderIntrinsicWidth` makes its child as wide as the child would like
  to be: its max intrinsic width at the most height the box may have,
  rounded up to a multiple of `stepWidth` when given, within the
  constraints (a tight width stays as it is); with `stepHeight` the child
  is also as tall as it would like to be at that width, rounded up to a
  multiple of it. `RenderIntrinsicHeight` makes its child as tall as it
  would like to be at the most width the box may have, within the
  constraints (a tight height stays as it is), so a row under it whose
  children stretch across it is as tall as its tallest child. Both are as
  big as their child; without one, as small as the constraints allow;
* `RenderDecoratedBox` is a box with a border: a `background` pen
  (null leaves what is under it), a `border` (`BoxBorder`: a `BorderType`
  — `single`, `rounded`, `double`, `heavy`, `ascii`, or `none`, blank
  lines in their pen — and a pen for each side that has one), `titles`
  (`BoxTitle`) on its top and bottom edges and `padding` inside the
  border. Its `insets` are a cell for each side with a border, a row for
  an edge with titles but no border, and the padding; the child is laid
  out within the constraints less them, at `inner`. It is as big as its
  child and insets and as wide as its titles, within its constraints;
  without a child as big as they allow (as small along an axis they leave
  unbounded). A corner is drawn where both its sides have a border, in the
  pen of the top or the bottom one. A border with `merge` draws each of
  its cells once, merged with the line already in it (below): it joins the
  lines it meets or crosses, leaving the text drawn in their cells (the
  titles of a box whose edge it shares), the end of a side without a
  neighbour joins a line it lands on without reaching past it (`┬`, not
  `┼`), and the background goes under the merged lines, keeping them, and
  fills the rest. The y of a title's `Alignment` picks its edge, the x its
  place: those aligned left go one after another from the left end, a cell
  apart, those aligned right likewise up to the right end, those in the
  center in the middle between them. The left ones get their room first,
  then the right ones from the last, then those in the center; one that
  doesn't fit is cut off where a glyph ends, with `…` after it where that
  fits. New pens, a new type or `merge` only repaint it;
* `RenderDivider` is a line of a `BorderType` in a pen across the room it
  gets: a row as wide as the constraints allow (`Axis.horizontal`) or a
  column as tall (`vertical`), as short as they allow along an axis they
  leave unbounded, in the middle of more rows (columns), the odd one after
  it. With `merge` it joins the lines it crosses, leaving the text in
  their cells, and each end joins a line it lands on without reaching
  past it (`├───┤` across a box); like a new pen or type, `merge` only
  repaints it.

## Box drawing

Box drawing is East Asian ambiguous: where the canvas draws a type's
pieces two columns wide, both draw `BorderType.ascii` instead.
`BorderType.glyph(up:, right:, down:, left:)` gives the piece for any set
of arms, joints included. Both, like `RenderParagraph`, take `Pen` values
rather than ids and look them up in the style table they are painted
with, once per table (a widget has none when it builds); painting them
again allocates nothing.

Both merge through `Canvas.mergeRun(x, y, run, pen, under:, trimFirst:,
trimLast:)`, which draws pieces of line one column each, as `run` does,
but merged with the line already in each cell: the cell gets the piece
that reaches out wherever either of them does, an arm both have in the
weight of the new one. Light (`single`, `rounded`), heavy and double lines
keep their own weights where Unicode has a piece for the mix: light and
heavy always, light and double where the arms across share a weight and so
do those down (`╞`, `╥`, `╪`); elsewhere every arm takes the weight of the
new piece (`━` over `║` is `╋`, `┌` over `═` is `┬`). The piece drawn, or
the one in the cell where the new one adds nothing to it, is kept as it
is, so a round corner stays round; dashed pieces (`┄`, `┆`) merge as solid
ones. ASCII pieces (`-`, `|`, and `+`, which reaches out all four ways)
merge only with each other, so boxes drawn in ASCII where box drawing is
two columns wide merge too, and box drawing only with box drawing, so a
hyphen in text never becomes `┼`. A cell that holds text (any glyph but a
blank or a piece of line, a wide one whole) keeps it and its style, so a
line merged over the edge of a box joins its lines and leaves its titles;
a glyph drawn that is no piece of line is drawn as `run` draws it. Where
its cell holds a line to merge with, the first piece drops the arms
`trimFirst` names and the last one those of `trimLast`: the end of a line
meets another in a joint (`├`, not `┼`). `under` paints each cell with
that pen first, under the line or the text it keeps, keeping its glyph.
Only lines drawn before in the same cells merge: boxes and dividers laid
over one another (in a `RenderStack`), not a divider inside a box's child,
which stays inside the border. Since a merging border draws each cell
once, where pens that leave a color to the cell (`null`, alpha) differ
from side to side, a merged corner is the top or bottom pen over the
background, where an unmerged one is that pen over the side's; with one
pen for every side, or pens that set every color, a box over nothing looks
the same merged or not.

## `RenderFlex`

`RenderFlex` lays its children out one after another along `direction`,
`gap` cells apart. The inflexible ones (`FlexParentData.flex` 0) come
first, each as long as it wants up to the whole main axis; the flexible
ones share the cells left by their flex factors, in whole cells, those left
over going to the first of them, and fill their share (`FlexFit.tight`) or
take what they want of it (`loose`). `mainAxisSize` makes the flex as long
as it may be (`max`) or as its children and gaps (`min`).
`mainAxisAlignment` puts the children at the `start`, the `end` or the
`center` (the odd cell after them), or shares the free cells out between
them (`spaceBetween`), around each (`spaceAround`) or before, between and
after them (`spaceEvenly`), in whole cells, those left over to the first
spaces, on top of the gaps. `crossAxisAlignment` puts each child at the
`start`, the `end` or the `center` (the odd cell after it), or makes it
as thick as the flex may be (`stretch`). Children that don't fit are cut
off at the bounds of the flex and, in debug, reported once as a warning
through `log()`. Along an unbounded main axis (in a `RenderViewport`)
there are no cells to share: each child is as long as it wants, the
flexible ones too, and the flex as long as they are, whatever its
`mainAxisSize`. `RenderColumn` and `RenderRow` are flexes of children
each of a fixed height or width, or `null` for a flexible one, stretched
across.

## `RenderStack`

`RenderStack` lays its children out on top of each other and paints them
in order, a later one over an earlier one. Those that are not positioned
(`StackParentData.isPositioned`: no edge or size set) come first, laid
out as big as they want up to the stack's maximum (`StackFit.loose`), as
big as the stack may be (`expand`) or within its constraints
(`passthrough`), and placed by its `alignment`. The stack is as big as
the biggest of them within its constraints, or with none as big as the
constraints allow (as small along an axis they leave unbounded). Then
each positioned child, along each axis: with both edges set, exactly as
long as the cells between them; with its size set, that long; otherwise
as long as it wants up to the stack's length less the one edge set
(Flutter leaves it unbounded there). It goes where its edge says, or
with neither edge where the alignment puts it; an edge may be negative,
and whatever sticks out of the stack is cut off.

## `RenderGrid`

`RenderGrid` lays its children out in the cells of its `columns` and
`rows`, tracks `columnGap` columns and `rowGap` rows apart (CSS grid,
simplified). A `GridTrack` is `.fixed(n)` cells long, `.fr(f)` parts of
the cells the other tracks leave, or as long as the children in it ask
for (`.content()`); a fraction or content track takes at least `min`
cells and at most `max`. A child takes `rowSpan` rows from `row` and
`columnSpan` columns from `column`, counted from 0 at the top left
(`GridParentData`). One with neither a row nor a column goes in the
cells after the child before it (the first at the top left), or from the
first column on the next row when they would reach past the last column
(without columns, each on a row of its own); cells another child takes
are not skipped. Tracks past the end of a list, up to the last a child
takes, are content tracks. The columns are sized first, then the rows
at the widths of the columns each child spans, each axis the same way:
a fixed track takes its cells, a content track what the children in it
alone need (their min intrinsic size) and a fraction track its `min`; a
child that spans tracks grows the content tracks it spans by even parts
of what it needs beyond them, those that span fewer tracks first, unless
it spans a fraction track. Then the content tracks grow by even parts of
the cells left towards what their children want (their max intrinsic
size, a spanning child's spread the same way), and the fraction tracks
share the cells the others leave by their fractions; a share beyond a
track's bounds holds it at the bound and the others share the rest (as
CSS resolves flexible lengths). Cells are shared in whole cells, those
left over going to the first tracks. Along an unbounded axis the grid is
as long as its children want, its fraction tracks stretched to the least
the constraints allow if that is longer. Each child is laid out exactly
as big as its cells and the gaps between them. The grid is as big as its
tracks and gaps within its constraints; what doesn't fit is cut off at
its bounds and, in debug, reported once as a warning through `log()`.
Children that overlap are painted in order, a later one over an earlier
one.

## `RenderWrap`

`RenderWrap` lays its children out in runs (Yoga's flexWrap): one after
another along `direction`, `gap` cells apart, each as long as it wants up
to the whole main axis, until the next would not fit; that one starts a
new run, `runGap` cells on across the main axis. Each run is as thick as
its thickest child. `alignment` places the children of each run along it
and `runAlignment` the runs across the wrap, each a `WrapAlignment`: at
the `start`, the `end` or the `center` (the odd cell after them), or with
the free cells between them (`spaceBetween`), around each
(`spaceAround`) or before, between and after them (`spaceEvenly`), in
whole cells, those left over to the first spaces. `crossAxisAlignment`
(`WrapCrossAlignment`) puts each child at the `start`, the `end` or the
`center` of its run (the odd cell after it). The wrap is as long as its
longest run and as thick as its runs and the gaps between them, or as the
constraints ask if that is more, and `alignment` shares out what a run
leaves of that length. Along an unbounded main axis (in a
`RenderViewport`) nothing wraps: the children make one run. Runs that
don't fit are cut off at its bounds and, in debug, reported once as a
warning through `log()`.

## `RenderParagraph`

`RenderParagraph` holds spans as `(text, Pen)` records, split into
clusters once per change with the owner's segmenter (the canvas's), so a
line is drawn exactly as wide as it was measured; it is as wide as its
widest line and as tall as its lines, within its constraints. No line
splits a grapheme: a wide glyph that doesn't fit goes to the next line,
and in legacy mode the clusters of one grapheme (a ZWJ sequence, a flag)
stay together. A line break of the text (LF, CR, CR LF, VT, FF, NEL, LS,
PS) ends a line; as on the canvas, a tab is one blank and other controls
take no room.

* `wrap`: `TextWrap.word` breaks after spaces (they hang at the end of a
  line: neither counted nor drawn), after a hyphen inside a word (not in
  `-v`, `--`, `-1`), after a zero width space, and between two CJK
  characters (ideographs, kana, Hangul syllables), but not before closing
  punctuation, a small kana or the prolonged sound mark, nor after an
  opening bracket; a word longer than the line breaks between graphemes.
  `grapheme` breaks between any two graphemes, `none` only where the text
  breaks lines;
* `overflow`, for a line too long and for text beyond `maxLines`:
  `TextOverflow.clip` cuts it off; `ellipsis`, `ellipsisStart` and
  `ellipsisMiddle` put `…` (as wide as the ambiguous width) in place of the
  end, the start or the middle of a line, with no space next to it, in the
  pen of the text it replaces next to what is kept. Beyond `maxLines`,
  `ellipsis` keeps the first lines, the last running on to the next line
  break of the text and ending in `…`; `ellipsisStart` keeps the last
  lines, the first starting with `…`; `ellipsisMiddle` keeps lines from
  both ends around one `head…tail` line;
* `align`: `TextAlign.left`, `center` (the odd cell after the line),
  `right`, `start` and `end`, the edges the line's paragraph starts and
  ends at (left and right, or in visual order, below, right and left for
  a paragraph that runs right to left), or `justify`, which stretches
  each line that wrapping ended and that has no ellipsis by the cells it
  lacks, after the spaces between its words (not its indent), the odd
  ones to the first gaps, in the pen of the space; the lines it leaves go
  to the start. A line wider than the paragraph starts at the edge its
  paragraph starts at;
* the order of the text: the owner's `textOrder` (`TextOrder.logical` until
  set; setting it lays the tree out and paints it again), which `TwkApp`
  sets as the terminal needs (`TerminalInfo.bidi`, [§1.7](terminal.md)). In
  `logical` order a line is drawn as stored, every paragraph left to right,
  for a terminal that reorders right-to-left text itself. In `visual` order,
  for one that doesn't, each line, broken as stored, is drawn as UAX #9
  orders it ([§1.5](unicode.md)): its right-to-left runs reversed by
  grapheme, the clusters a legacy-mode grapheme is drawn in kept in order,
  single-code-point glyphs at an odd level mirrored (`(` drawn as `)`), an
  ellipsis at the lower level beside it, a right-to-left line justified from
  the right. Text without right-to-left characters pays a scan per change in
  visual order and nothing in logical order;
* new text is split and laid out again; the same text with new pens is
  only repainted, as is a new `align`; a new `wrap`, `overflow` or
  `maxLines` lays it out again. Painting it again allocates nothing.
  `RenderText` is the leaner object for one line in one pen, drawn as
  stored in either order;
* `textRangeAt(x, y)` is the text at a cell as the last layout placed
  it, as offsets `(start, end)` into the spans' text joined, in UTF-16
  code units: the cluster drawn there, at either cell of a wide one (at
  an ellipsis the clusters it stands for, in a gap a justified row
  stretches the space before it); left of a row's text the empty range
  where the row starts, right of it and past the width the empty range
  where the next row starts (after the spaces the row hangs and its line
  break; right of the last row the end of the text); `(0, 0)` above the
  first row and the end below the last. What takes no cell (a
  zero-width control, the CR of CR LF) goes with the cluster after it,
  so the ranges tile the text; in visual order a cell gives the cluster
  drawn there, the empty ranges at the edges staying those of the row's
  start and the next row's. The widget layer selects text with it.
  Where each cluster starts in the text is found the first time it is
  asked after the text was split, and kept through layouts at other
  widths and new pens, so a layout pays nothing for it.

## Intrinsic sizes

Before laying a child out, a parent may ask what it would like to be:
`getMinIntrinsicWidth(height)`, `getMaxIntrinsicWidth(height)`,
`getMinIntrinsicHeight(width)` and `getMaxIntrinsicHeight(width)` (what
wrapping text, a table's column widths or a shrink-to-fit box need),
worked out by the object's `compute…` overrides without laying anything
out. Text is measured with the `PipelineOwner`'s `segmenter` — the
canvas's own (`PipelineOwner(…, segmenter: screen.canvas.segmenter)`), so
wide, uncertain and ambiguous glyphs count as the text mode and ambiguous
width of the screen draw them. `RenderText` answers with the columns its
text is drawn in (min and max agree) and one row. `RenderParagraph`'s min
width is the widest piece no line break can split (with `TextWrap.none`,
its widest line), its max width its widest line unwrapped, and its height
the lines it has at a width, at most `maxLines`. `RenderBox` and
`RenderPadding` add their padding to the child's answers,
`RenderPositionedBox` multiplies them by its factors, and
`RenderConstrainedBox` keeps them within its additional constraints (where
those are tight and bounded it answers with their extent without asking
the child; where their minimum is unbounded it passes the child's answers
on). `RenderFractionallySizedBox` asks for the fewest cells whose
fraction gives its child what it asks for at its fraction of the other
extent (along an axis without a factor, for what the child asks for).
`RenderIntrinsicWidth` asks for its child's max width (min and max
alike) and for the heights its child asks for at the width given, or at
that max width where the width is unbounded, each rounded up to its
step; `RenderIntrinsicHeight` for its child's max height (min and max
alike) and for the widths its child asks for at the height given, or at
that max height where the height is unbounded. `RenderDecoratedBox`
adds its insets to the child's answers, its max width at least as wide
as its titles (its min width leaves them out: they can be cut off);
`RenderDivider` asks for a row (a column) across its line and nothing
along it; a `RenderStack` asks for what the biggest of its children that
are not positioned asks for. A `RenderFlex` asks along its main axis for
its inflexible children and gaps plus the fewest cells whose shares give
each flexible child what it asks for, and across it for the most any
child asks for at the length it would get. A `RenderGrid` asks for its
gaps and tracks: a fixed track for its cells, a content track for what
its children need (min) or want (max), and the fraction tracks for the
fewest cells per part that give each of them, and each child spanning
one, what it asks for; its rows at the widths its columns get at the
width given. A `RenderWrap` asks along its main axis for the most a
child asks for (min) or for all its children in one run and the gaps
(max), and across it for the runs its children make at the length
given, each child as long as its max intrinsic size up to that length,
each run as thick as the most a child of it asks for there, and the
gaps between the runs. A `RenderLog` scrolls and asks for nothing. Each object
keeps its last answer of each kind, with the argument it was for, until
`markNeedsLayout`, which clears them, as attaching to an owner does
(allocation-free once warmed up); when an answer had been asked for, the
mark goes on to the parent past a relayout boundary, since the parent's
layout may have used it. A new text marks layout for that reason.

## Changing the tree in layout

An object may change what is below it while it is laid out (the widget
layer's `LayoutBuilder` builds its child there, for its constraints):
`invokeLayoutCallback(callback)`, called in its `performLayout` before it
lays its children out, runs a callback that may adopt, replace and drop
children of the object and of those below it. The marks that makes stop at
the object, or at the relayout boundaries below it (the items of a
`RenderList` with an `itemExtent`, the list itself), which `flushLayout`
lays out after it in the same flush: what changed is laid out before
anything is painted, leaving no layout for the next frame. When an intrinsic
size the object answered before comes out different afterwards, its parent
may have laid it out by the old answer: the parent is laid out again on the
next frame, or the object itself when it is the root (an inline region is
sized by the root's max intrinsic height, [§1.12](inline.md)). A parent that
asked for no intrinsic size is not.

## Paint

Paint: `markNeedsPaint()` marks the nearest repaint boundary, which,
marked from inside, forgets what it painted (`invalidatePaintCache`: a
`RenderLog`, a `RenderViewport` or a `RenderList` then paints all of
itself instead of scrolling); a frame repaints only dirty boundaries (a boundary repaints
over its own previous output, so its background must be opaque, unless
it keeps an underlay, `keepsUnderlay`: its parent painting it, the owner
keeps the styles of the cells under it, and puts back those of the rows
it repaints on its own before it repaints them, so that it paints over
what is under it with no background of its own: a field or a gauge on a
dialog, a selected row, a gradient. Put back by the owner, for one that
paints every cell of the rows it repaints; one that keeps cells and
moves them (a text area) says `putsUnderlayBack` false and puts it back
itself under the cells it paints (`putUnderlayBack`), moving rows only
where every row of its underlay is alike (`underlayRowsAlike`), else
repainting them; a log's kept, moved cells would be overwritten otherwise.
A `RenderViewport` or a `RenderList` that scrolls by moving the rows of
the surface moves what the boundaries inside it keep by as many rows
(the owner lists the boundaries that keep one): the cells under them
went with them, and a field scrolled, then focused and left, would
otherwise keep its focus's background;
measured, a field typed into costs what it did, eight gauges moving every
frame some 13 % more, the copies and the pens composed over the cells
under them. A root that isn't a boundary starts from blank cells), and
`RenderLog` scrolls by
moving rows on the surface (when all of it is visible and nothing paints
over it) and painting only the exposed rows and newly appended lines
(its lines are append-only; `repaintAll()` when the pens of lines
already shown change).
Every object is painted clipped to its own bounds and its ancestors'
(`paintChild` clips each child, and a boundary repainted on its own is
clipped by every ancestor), so a child that sticks out of its parent is
cut off at the parent's edge without a clipping object: there is no
`RenderClip` or `ClipRect`. Where children overlap (a `RenderStack`, a
`RenderGrid`), a boundary repainted on its own would cover the later
children over it: the ancestors that paint over its cells (`paintsOver`)
paint that again, clipped to those cells, the nearest first
(`paintOver`; a stack or a grid paints its later children that reach
them, which forget what they painted before). Such a boundary forgets
its own paint state first, so a `RenderLog` under a panel repaints its
rows instead of moving them, which would drag the panel's cells along.
See `example/chat_demo.dart`.

## `RenderViewport`

`RenderViewport` is a window onto one child laid out with no limit
along its `axis` and within the constraints across it, as big as the
child within its own constraints: the first `scrollOffset` cells of the
child are scrolled off its start. Each layout keeps the offset from 0
to the child's extent less the viewport's and tells `onExtents(viewport,
content)` both; set after a layout, the offset is kept within them and
moves the child at once, so a hit test or an ensure-visible sees it
before the next frame. It is a repaint boundary, filled under the child
with `background` (by default the terminal's own colors), which must be
opaque, and is hit anywhere in it. When it only scrolled since it last
painted, along a vertical axis by less than its height, all of it inside
the canvas's clip and nothing painted over it, it shifts its rows on the
surface and declares the scroll (`Surface.scrollRect`), so the terminal
scrolls in hardware (`DECSTBM + SU/SD`, between DECSLRM margins where
the view is narrower than the screen and the terminal has them), and
paints only the rows the scroll exposed; the repaint boundaries inside
it marked for paint meanwhile repaint on their own. Scrolled back to
where it was before a frame, it paints nothing; scrolled along a
horizontal axis, cut off, painted over, laid out, or with an object
inside it marked for paint that no repaint boundary inside it holds, it
paints all of itself.

## `RenderList`

`RenderList` is a window onto a list of `itemCount` items one below
another, each as wide as the list and as tall as it likes, or
`itemExtent` rows: only the items in the window and `cacheExtent` (3)
rows past either edge of it exist, near either end those up to a window
past the edge. Its `ListItemManager` (`items`: the widget layer's
element) builds them as they come into the window (`buildItem(index)`,
which puts the item's render object in with `insertItem(item, index)`;
`moveItem` gives an item another index, kept in its `ListParentData`)
and drops them as they leave it (`dropItem`), in the list's layout
callbacks. An item's height is measured when it is laid out and
remembered until the list's width changes; the items never laid out are
taken to be as tall as those measured are on average, so
`scrollOffset`, the rows of the items above the window, and the extent
of the content, which `onMetrics(viewport, content, offset)` gets each
layout with the window's and the offset the window settled at, are
estimates where the list has not been, which change as it measures
items while the item at the top of the window stays where it is.
Setting `scrollOffset` moves the items at once, so a hit test sees them
where they will be, and the window in the next layout, in place of a
move to an item (`jumpToIndex`, `showIndex`, below) asked for since the
last layout, even to the offset the list is at; a move to an item takes
the place of an offset set before it, so of the two the later wins. A
move of the window by at most its height is exact, the items it passes
laid out; a longer one goes to where the estimate puts the offset,
building nothing on the way; one to 0, or to the end of the content as
the last layout had it, to the start or the end. `jumpToIndex` shows an item at the top, `showIndex` scrolls the
least that shows it; while `stickToBottom` is set and the window shows
the end, it keeps showing the end as items are added or grow, and such
a list starts at the end. It takes all the room it is given, which must
be bounded (it shows the error otherwise), and is a repaint boundary
filled with `background` under the items, which must be opaque. When its
window moved since it last painted, by less than its height, all of it
on the surface and nothing painted over it, it shifts its rows and
declares the scroll (`Surface.scrollRect`), so that the terminal
scrolls in hardware, then paints the rows the scroll exposed and those
of the items built, laid out again or moved otherwise since; the repaint
boundaries inside it marked for paint repaint on their own, and
anything else inside it marked for paint other than by its layout has
it paint all of itself.

## `RenderEffect`

`RenderEffect` shows its child, as big as it, through an effect over
the cells of its bounds (the widget layer's `Effect`): a subclass says
whether it changes anything (`hasEffect`) and what each cell shows
(`effectCell(x, y, glyph, style, underGlyph, underStyle)`, setting
`effectGlyph` and `effectStyle`) of what the child painted there and
what was under it. It is a repaint boundary that keeps both for each
cell: a new frame of the effect (`markNeedsPaint` on it) is shown from
what it kept, painting neither the child nor what is under it; a mark
inside the child puts back what was under it and paints the child again,
so the child need not be opaque; what a repaint boundary inside it
repaints on its own is kept and shown through the effect. A two-column
glyph is kept whole, or blanked where half of it is left. Without an
effect the child shows as it paints.

## Hit testing

Hit testing finds the objects at a cell, as the tree was laid out last:
`owner.hitTest(result, x, y)` empties a `HitTestResult` and has the root's
`hitTest(result, x, y)` fill it. An object adds nothing for a cell
outside its bounds, so a child is cut off at its parent's edge, and every
ancestor's, as paint cuts it. Inside, it asks its children
(`hitTestChildren`), each at the cell less the child's offset, the one
painted last (on top) first, until one is hit, then adds itself after
them as its `hitTestBehavior` says: `HitTestBehavior.opaque` is hit
anywhere in it (`hitTestSelf`) and hides what it covers; `translucent` is
added anywhere in it but hit only where a child is, so the siblings it
covers are asked too; `deferToChild` is hit only where a child is. The
behaviour is the object's own, as what it paints is: any object is opaque
unless it says otherwise, those with children (the two mixins) defer to
them, `RenderBox` fills its cells and is opaque, and a
`RenderDecoratedBox` is opaque with a background and without one is hit
on its border and its titles only, leaving the cells it doesn't draw to
what is seen through them. Another object says otherwise by overriding
`hitTestBehavior`, or `hitTestSelf` to answer for each cell. An object
that shows an error is hit anywhere in it, its children not asked. The
result holds the objects hit with the cell in each one's coordinates
(`result[i]`, `xAt(i)`, `yAt(i)`), the deepest first and the root last,
a translucent object before what was hit under it; it is meant to be
kept: `reset()` keeps its storage (`capacity`), which doubles only when
a hit test finds more objects than it has room for, so a hit test per
mouse move allocates nothing once warmed up.

## Diagnostics

Diagnostics (`render/diagnostics.dart`): a render object describes
itself when asked, and a frame never asks. `describe()` is a
`DiagnosticsNode` of it and the objects below it: its type; the
properties its `debugFillProperties` adds, those at their default left
out; those its parent keeps on it (`ParentData.debugFillProperties`: a
flex factor and a loose fit, a fixed extent, a stack child's edges, a
grid child's row, column and spans); its offset in the parent and the
constraints of its last layout (`tight`, or ranges such as
`0..80×0..∞`); the error it shows in its place, if any (below); its size
once laid out; and flags: ◆ repaint boundary, ◇ relayout boundary, ⟳
needs layout, ✎ needs paint, ⇥ overflow (a flex or a grid whose
children don't fit, `overflow: 2 rows`), ✗ error; the widget layer's
elements add ✱ needs build. A node's `toString()` is one line,
`Name-key ‹props›`; `toStringDeep()` the tree under box-drawing guides,
the sizes in a column after the widest line (aligned on the ×) followed
by the flags' symbols, a run of `fold` (5) or more siblings of the same
name as one line (`… 19 MessageView`), and a legend of the symbols
shown; `toJson()` the same as JSON. Values are
written by `describeValue`, `describeText` (quoted, escaped, cut off with
`…` after 24 columns), `describePen` (`bold red on blue`, `black/50%`,
`ul:red`, `link`), `describeColor`, `describeConstraints`,
`describeInsets` (as CSS writes them: `0 1`) and `describeAlignment`.
`constraints`, `debugNeedsLayout`, `debugNeedsPaint` and `debugError`
tell an object's state.

## Debug paints

Debug paints, flags of a `PipelineOwner` (an app's `TwkApp.owner`), off by
default (on from the start where `TWK_DEBUG` names `rainbow` or `relayout`,
[§1.7](terminal.md)), when they cost a frame nothing measurable: with
`debugRepaintRainbow` each repaint of a repaint boundary, or of the root on
its own, blends the next of 12 hues over the background of the cells it
covered (its bounds, cut where its ancestors cut it), keeping their glyphs,
text colours and attributes, so an area that changes colour repainted and
one that keeps it did not. With `debugRelayoutHighlight` each repaint
outlines the objects in it laid out since the last one: the backgrounds of
the cells along their edges, in one tint per frame that lays anything out,
the next of a cycle; an outline stays until its cells repaint. Turning
either on or off repaints everything; while one is on, a boundary repaints
all of its cells (a `RenderLog` doesn't scroll in hardware), so frames cost
many more bytes. In 16 colours a tint may round away.

## Errors

Errors: what an object's `performLayout` or `paint` (or `paintsOver`,
`paintOver`) throws stays in it. The object shows the message in white
on red in its place, cut off at its bounds: after a layout that threw it
is as big as the message within its constraints and shows it until it
lays out without throwing; after a paint, until it is marked for paint
or laid out again. The rest of the frame is laid out and painted as if
nothing happened: a boundary whose paint threw is painted again, since
the paint may have left the canvas moved or clipped, and a repaint
boundary inside an object that shows an error doesn't paint over it.
The `PipelineOwner` reports each error to `onError(object, phase,
error, stack)` (`RenderPhase.layout` or `paint`), once while the object
throws the same one; without `onError` the first error of a
`flushLayout` or `flushPaint` is thrown once the flush has ended, the
tree left showing them all, and one outside a flush at once. In the
inline mode `TwkApp` reports to the same `onError` what sizing the
region and committing throw ([§1.12](inline.md)).
`RenderErrorBox` is that block on its own: a message broken between
words, as wide as its longest line and as tall as its lines, within its
constraints.
