# twk reference: `layout`

[The reference](README.md) · `lib/src/layout/`, `test/layout/`

## `Padding`

`Padding`, `Align`, `Center`, `SizedBox` (`.expand`, `.shrink`),
`ConstrainedBox`;

## `FractionallySizedBox`

`FractionallySizedBox`, which makes its child a `widthFactor` and a
`heightFactor` of the room there is, each rounded to the nearest cell, a
half up (all of the room along an axis without one), and places it by an
`alignment`;

## `IntrinsicWidth`

`IntrinsicWidth`, which makes its child as wide as its content would like to
be within the room there is, rounded up to a multiple of `stepWidth`, and
with a `stepHeight` as tall as it would like to be at that width, rounded up
to a multiple of it;

## `IntrinsicHeight`

`IntrinsicHeight`, which makes its child as tall as its content would like
to be within the room there is (a `Row` under it with
`CrossAxisAlignment.stretch` makes its children as tall as the tallest);

## `Box`

`Box` (a `style` that fills it, a `Border` (`.all`) with a style per side,
which with `merge` joins the lines drawn before it where it meets or crosses
them, so that boxes stacked to share an edge join in `┬ ├ ┼`, and leaves the
text drawn in those cells, the titles of a box whose edge it shares,
`BorderTitle`s on its top and bottom edges, `padding`: the core's
`RenderDecoratedBox`), `Divider` and `VerticalDivider` (with `merge`,
joining the lines they cross and leaving the text in their cells, each end
meeting a line it lands on in a joint: `├───┤` across a `Box` it is stacked
on);

## `Flex`

`Flex`, `Row` and `Column` with a `gap` (along an unbounded main axis, as in
a `SingleChildScrollView`, each child, flexible or not, as long as it likes,
and the flex as long as its children, whatever its `mainAxisSize`);

## `Flexible`

`Flexible` (a share of the cells the inflexible children leave, by its flex
factor, taken whole with `FlexFit.tight` or as much as the child wants with
`loose`), `Expanded` (a tight `Flexible`), `Spacer`;

## `Stack`

`Stack`, with an `alignment` and a fit for the children that are not
positioned, and `Positioned` (`.fill`), which pins a child to its edges in
cells;

## `Grid`

`Grid`, with `columns` and `rows` of `GridTrack`s (`.fixed`, and `.fr` and
`.content` with a `min` and a `max`) and a `columnGap` and a `rowGap`, and
`GridPlacement`, which puts a child in its cells, from its `row` and
`column` across a `rowSpan` and a `columnSpan` (without one a child goes
after the one before it);

## `Wrap`

`Wrap(direction:, alignment:, runAlignment:, crossAxisAlignment:, gap: 0,
runGap: 0, children:)` (the core's `RenderWrap`), which lays its children
out one after another along `direction`, `gap` cells apart, each as long as
it likes up to the whole main axis, and starts a new run `runGap` cells on
where the next does not fit (tags, buttons, hints that flow onto the next
row as the terminal narrows): `alignment` places the children of each run in
the cells it leaves and `runAlignment` the runs (`WrapAlignment`: `start`,
`end`, `center`, `spaceBetween`, `spaceAround`, `spaceEvenly`),
`crossAxisAlignment` each child in its run (`WrapCrossAlignment`: `start`,
`end`, `center`); it is as long as its longest run and as thick as its runs,
or as the constraints ask if that is more, and along an unbounded main axis
its children make one run;

## `SplitView`

`SplitView(panes:, direction:, controller:, shareEdges: false, type:,
style:, focusedStyle:, pointerShapes: true)`, its `SplitPane(child:,
minSize: 1, maxSize:, collapsible: false)`s side by side or one below
another, a divider line between each two: the panes share the cells the
dividers leave by the fractions of a `SplitController`, kept across resizes,
each at least its `minSize` and at most its `maxSize` (cells all of them
leave at their most stay empty after the last, and a room short of their
least is shared by those). A divider dragged with the left button follows
the mouse, collapsing a `collapsible` pane dragged past half its least and
expanding it dragged back out; Tab gives a divider the focus (between the
panes on either side of it), and then Left and Right (Up and Down between
panes one below another) move it a cell, collapsing a collapsible pane it
moves past the least of and expanding a collapsed one, and Home and End as
far as it goes, the arrows hinted in a `KeyHintsBar`; focused or dragged, it
is drawn in `focusedStyle` (the theme's `primary`) over `style`. With
`pointerShapes`, where the terminal shows the pointer's shape, the pointer
over a divider is `ewResize` (`nsResize` between panes one below another),
and the terminal reports all motion; false leaves the pointer to the regions
around the view. A collapsed pane gets no cells and is not painted, hit or
focusable, its dividers kept. A move sets the controller's `fractions` from
the sizes it leaves, a pane it collapses keeping its share; an app saves and
restores `fractions` and `collapsed` (`collapse`, `expand`, `isCollapsed`;
an `ArgumentError` for fractions that are not shares, a `RangeError` for no
pane), and `sizes` are the cells each pane got. The dividers join the lines
in their cells, the dividers of a split view filling a pane beside them too
(`├ ┤ ┼`); with `shareEdges` the panes are laid out over the dividers' cells
as well, so that boxes in them with `Border(merge: true)` share their edges
along them (`┬ ├ ┤ ┴`, the boxes of a split view inside a pane too), the
divider joining their lines only, so that the `BorderTitle`s on them stay (a
blank in a title takes the line). Along an unbounded axis it is as long as
its panes want (their max intrinsic sizes).

## `Shadow`

`Shadow(shadow: BoxShadow(dx: 2, dy: 1, color: Color.rgb(0, 0, 0), alpha:
0x80), child:)` casts a drop shadow: it is as big as its child and the cells
the shadow takes beside it (`BoxShadow.insets`; a negative offset casts it
left or up), whose glyphs and attributes stay, their background and text
color blended with the shadow's color as a `ModalBarrier` blends them, text
in the default color drawn faint while the terminal has not told that color;
what repaints on its own under it is darkened again, a two-column glyph its
edge cuts stays whole, and the mouse goes through it to what is under it.

## `DockArea`

`DockArea(controller:, panels:)` shows `DockPanel(id:, title:, child:)`s
where its `DockController`'s `DockLayout(root:, windows:)` puts them: docked
in a tree of `DockSplit`s (`direction`, `children`, `fractions`), each a
`SplitView` whose dividers set its shares in the layout, and `DockTabs`
groups (`panels`, `selected`), each a `TabBar` over a `TabView`, or floating
in the windows of a `WindowLayer` over them (`DockWindow(panel, left:, top:,
width:, height:)`, their moves and resizes set in the layout). The left
button dragging a group's tab bar drags its selected panel, a chip with its
title following the mouse; over a group the drag shows five targets in its
middle (`◀ ▶ ▲ ▼` for its sides, `■` for its tabs; `■` alone over an area
with none docked), over one of them the cells the panel would take outlined
with its title. Released on a target the panel docks there, elsewhere it
floats in a window half the area; a window's title bar dragged onto a target
docks its panel back. A panel keeps its state as it moves (a `GlobalKey` of
its own takes its element along).

## `DockController`

`DockController([layout])`: `dock(panel, beside:, side: DockSide.center)`
(`left`, `right`, `top`, `bottom`: a group of its own beside the one of
`beside`, joining the split that one is in when it is along the same axis,
the two sharing its share; `center`: its last tab, selected; with `beside`
null, on a side of all of the panels), `float(panel, left:, top:, width: 40,
height: 12)`, `select`, `remove`, and `layout` set to restore one;

## `DockLayout.toJson`

`DockLayout.toJson()` and `DockLayout.fromJson(json)` save it and read it
back (a `FormatException` for JSON that is not one). Panels the layout names
that the area has not are taken out of it.

## `Container`

`Container(alignment:, padding:, color:, decoration:, foregroundDecoration:,
width:, height:, constraints:, margin:, child:)` puts `Align`, `Padding`,
`ColoredBox`, `DecoratedBox` and `ConstrainedBox` together as Flutter's
does: the child placed by `alignment`, the padding inside the decoration,
the foreground decoration over them, `width` and `height` tightening
`constraints`, and the margin outside it all, a border taking cells of its
own inside the margin (`color` is a decoration that fills the box: one of
the two is given).

## `ColoredBox`

`ColoredBox(color:, child:)` fills its cells with a color under its child,
as big as the child, or without one as small as the constraints allow.

## `DecoratedBox`

`DecoratedBox(decoration:, position: DecorationPosition.background, child:)`
draws a `BoxDecoration(style:, border:, titles:, gradient:)`: under the
child a `Box` of it, the style filling it, the border around the child, the
titles on its edges and a gradient under it all (`GradientBackground`); over
it (`DecorationPosition.foreground`) the border and the titles over the
child's edges, the mouse passing them by, the child taking the whole box
with the constraints the box was given, the style not filled but giving the
lines and the titles the colors theirs leave unset, and a gradient coloring
the child's text (`GradientForeground`).

## `LimitedBox`

`LimitedBox(maxWidth:, maxHeight:, child:)` limits its child only along an
axis the constraints leave unbounded (in a `Column`, a scrolled list);

## `OverflowBox`

`OverflowBox(alignment: Alignment.center, minWidth:, maxWidth:, minHeight:,
maxHeight:, child:)` lays its child out within those limits, its own
constraints where one is not given, as big as its constraints allow, and
`SizedOverflowBox(size:, alignment:, child:)` is `size` big as far as its
constraints allow and lays the child out within its own constraints, as
though it were not there: each places the child by `alignment`, sticking out
on the side it says and cut off at the box's edges.

## `Transform.translate`

`Transform.translate(offset: (dx, dy), transformHitTests: true, child:)`
shows its child moved by whole cells, laid out where it was, the mouse
finding it where it shows (with `transformHitTests: false`, where it would
be unmoved): a terminal's cells neither turn nor scale, so this is the only
transform (`FractionalTranslation` moves by shares of the size).

## `CustomPaint`

`CustomPaint(painter:, foregroundPainter:, size: (0, 0), child:)` paints
cells of the app's own: a `CellPainter`'s `paint(canvas, width, height)`
under the child and the foreground painter's over it, on the frame's
`Canvas` with its origin at the top left and clipped to it (what a painter
does to the canvas undone after it), as big as the child, or without one as
`size` within the constraints; it repaints, building and laying out nothing,
when a new painter's `shouldRepaint(old)` says so (or it is of another type)
and whenever the `Listenable` a painter was made with
(`CellPainter(repaint:)`) notifies, and a painter's `hitTest(x, y)` says
where it is hit (by default the painter in every cell the child leaves, the
foreground painter in none, a cell where the foreground painter is hit
hiding the child).

## `Offstage`

`Offstage(offstage: true, child:)` lays its child out and keeps its elements
and states, but paints nothing of it (a repaint boundary in it that repaints
on its own shows nothing), lets no cell of it be hit, keeps the focus from
its nodes (an `ExcludeFocus`, `focus`: one focused loses it as it goes
offstage, Tab passes them by) and leaves it out of what a screen reader
reads (an `ExcludeSemantics`, `semantics`), as small as the constraints
allow;

## `Visibility`

`Visibility(visible: true, replacement: SizedBox.shrink(), maintainState:
false, maintainSize: false, child:)` shows `replacement` in place of a child
it hides, the child leaving the tree, or with `maintainState` an `Offstage`
of it, and with `maintainSize` as well the child keeping its room.

## `ExpansionTile`

`ExpansionTile(title:, child:, subtitle:, trailing:, initiallyExpanded:
false, controller:, onExpansionChanged:, duration: 150 ms, indent: 2,
focusNode:, headerStyle:, expandedHeaderStyle:, hoverStyle:)` is a section
that folds: a header row, `▶` while collapsed and `▼` while expanded (in the
theme's `muted` and `primary`), then `title` with `subtitle` under it in
`muted` and `trailing` (a count, a badge) at its right end, over `child`,
`indent` cells in, which is built only while it is expanded or folding: it
unfolds from the header down a row at a time over `duration` and folds back
up the same way, at once with a zero duration or outside an app. The header
is one stop of the focus: Enter (hinted) or Space toggles it, Right expands
and Left collapses it, passing the key on where it is so already, and a
click toggles and focuses it; a focus in the child as it collapses goes to
the header, and Tab passes what is folding by. Its header's styles are the
theme's text, `headerStyle`, `expandedHeaderStyle` while expanded,
`hoverStyle` (the theme's `surface` as background) under the mouse and the
theme's `selection` while focused. An `ExpansionController(expanded: false)`
(`expanded`, `expand`, `collapse`, `toggle`) opens and closes it from
elsewhere, one of its own when none is given, and `onExpansionChanged` is
told of each change, by a key, a click or the controller; a screen reader
reads the header as a button, `expanded` or `collapsed`.

## `Accordion`

`Accordion(children:, allowMultiple: false, initiallyExpanded:)` stacks
`ExpansionTile`s of which one is expanded at a time unless `allowMultiple`,
expanding one collapsing the one that was: the `initiallyExpanded`th at the
start, or where that is null the first tile that says `initiallyExpanded`
(with `allowMultiple`, each that does); a tile with a controller of its own
keeps it. Up and Down go from header to header.

## `RepaintBoundary`

`RepaintBoundary(child:)` makes its child a repaint boundary of the core, so
that a part that changes often is isolated: a mark inside it repaints it
alone, nothing around it, over what was under it (the cells the child leaves
show what is under it, kept as the core's `RenderEffect` keeps it); the
core's `EdgeInsets`, `Alignment`, `BorderType`, `Axis`, `MainAxisAlignment`,
`MainAxisSize`, `CrossAxisAlignment`, `FlexFit`, `StackFit`, `GridTrack`,
`GridTrackKind`, `WrapAlignment` and `WrapCrossAlignment`
