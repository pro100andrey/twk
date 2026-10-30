# twk reference: `scroll`

[The reference](README.md) · `lib/src/scroll/`, `test/scroll/`

## `Scrollable`

`Scrollable(viewportBuilder:, scrollDirection:, controller:, focusNode:,
autofocus:, canRequestFocus:, keyHints: true, reverse: false)`, which
scrolls the viewport its builder builds (`viewportBuilder(context,
position)`): a stop of Tab unless `canRequestFocus` is false, it scrolls
while it or a widget inside it has the focus (which takes first the keys it
uses) Up and Down (Left and Right along a horizontal axis) a cell, Page Up
and Page Down a window, Home and End to the ends, each without modifiers, a
key that would not move it, at an end, going on to the nodes above; while
the focus is in it the keys that would move it now are among those a
`KeyHintsBar` shows, unless `keyHints` is false: `scroll` for the arrows, `a
window` for Page Up and Page Down, `the ends` for Home and End, those back
left out at the start, those on at the end, and all of them with nothing to
scroll; a notch of the wheel over it scrolls `Scrollable.wheelStep` (3)
cells (along a horizontal axis the horizontal wheel's, or the vertical one's
for a mouse without one), the innermost scrollable under the mouse alone,
and while one is mounted the terminal reports presses and the wheel
(`gestures`). Its `ScrollPosition`, a `ChangeNotifier` whose listeners are
told when the offset or the extents change: `offset` in cells, kept from 0
to `maxOffset` once the viewport told it the extents (`applyExtents`; an
offset set before is kept until then; a viewport that settles its offset
itself as it lays out, as a `ListView`'s does, gives the `offset` it settled
at, taken without a `ScrollUpdateNotification`), `viewportExtent`, `metrics`
(`ScrollMetrics`: also `extentAfter`, `atStart`, `atEnd`), `jumpTo`, and
`ensureVisible(renderObject)`, which scrolls the least that shows a render
object inside the viewport, its start when it is longer than the window (an
`ArgumentError` when it is not inside);

## `Scrollable.of`

`Scrollable.of` (`maybeOf`) finds it from below. A
`ScrollController(initialOffset:)` given to a scrollable reads and moves its
position (`offset`, `position`, `hasClients`, `jumpTo`,
`ensureVisible(context)`), its listeners told when the position's are; given
to two at once it moves both, and `position` and `offset` fail. With
`ScrollController(stickToEnd: true)` any scrollable it is given to (a
`SingleChildScrollView` too) starts at the end, unless `initialOffset` says
otherwise, and keeps showing the end as its content grows while the window
shows the end, as a log or a chat does; a key, the wheel or `jumpTo` away
from the end lets go, and back at the end it sticks again. The end is the
one End scrolls to. A `reverse` scrollable shows the start of its content at
the end of its axis, at the bottom (the right), the offset growing as the
window goes up (left), the keys, the wheel and a `Scrollbar` going the way
they go on the screen.

## `Scrollable.ensureVisible`

`Scrollable.ensureVisible(context)` scrolls each scrollable above the
context, the nearest first. A move by `jumpTo`, a key or the wheel sends a
`ScrollUpdateNotification` (`scrollDelta`) up from the scrollable, and a key
or the wheel that would go past an end an `OverscrollNotification`
(`overscroll`), each a `ScrollNotification` with its `metrics` and its
`depth`, the scrollables it went past on its way to the listener.

## `SingleChildScrollView`

`SingleChildScrollView(child:, scrollDirection:, controller:, style:,
focusNode:, autofocus:, canRequestFocus:, keyHints: true)`, a `Scrollable`,
shows one child laid out as long as it likes along the axis and within the
constraints across it (a `Column` in it as tall as its children) in a window
as big as the child within the constraints, filled with its `style` over the
theme's background and text (in a `Box` with a background of its own, given
that as its `style`); the window follows the position with no build (the
core's `RenderViewport`), and scrolled along a vertical axis while all of it
is on the screen, it has the terminal move the rows that stay in view and
paints only those the scroll brought in.

## `ListView`

`ListView(children:)` and `ListView.builder(itemCount:, itemBuilder:)` (an
`IndexedWidgetBuilder`), each with `itemExtent:`, `cacheExtent: 3`,
`maxKept: 64`, `stickToBottom: false`, `controller:`, `style:`,
`focusNode:`, `autofocus:`, `canRequestFocus:`, `keyHints: true` and
`reverse: false` (and `ListView.builder` `findChildIndexCallback:`), a
`Scrollable` of items one below another, each as wide as the list and as
tall as it likes, or `itemExtent` rows: only the items in the window and
`cacheExtent` rows past its edges are built, as they come into view, and
removed as they leave it, near either end those up to a window past the
edge, so a list of a hundred thousand items builds a window's worth (the
core's `RenderList`). Its items are built again when it is and when an
inherited widget the builder depended on changes; a builder that throws
shows the error in the item's place. The items never built are taken to be
as tall as those built are on average, so the offset and the extent of the
content its position has are estimates where the list has not been, which
change as it builds items while what it shows stays where it is; a move of a
window or less is exact, a longer one goes where the estimate puts it, Home
and End go to the ends. An item whose widget has a key keeps its element,
and its `State`, when it is scrolled out of view, the `maxKept` that left
the view last, and has it back at whatever index the builder builds a widget
with that key; an item a `GlobalKey` takes elsewhere leaves the list; one
without a key is built anew. With `stickToBottom`, or a controller that
sticks to the end (`stickToEnd`), it starts at the end and, while the window
shows the end, keeps showing it as items are added or grow, as a log or a
chat does. Scrolled away from its start and not stuck to its end, it keeps
what it shows in place as items are inserted or removed before it, by the
keys of its items: the first item in the window whose widget has a key
(`ValueKey(id)`) stays on its row, found among the items built, or as many
items on as the count changed by, or else by `findChildIndexCallback`
(`findItemIndexCallback` for `ListView.separated`), for items that move
further; a list whose items have no keys keeps its offset, and what it shows
moves.

## `ListView.separated`

`ListView.separated(itemCount:, itemBuilder:, separatorBuilder:,
findItemIndexCallback:, …)` builds a separator between each two items,
separator `i` between item `i` and item `i + 1`, as it builds the items, as
they come into view, a screen reader leaving the separators out, and a
`ListController` naming items, never separators.

## `ListView`

`ListView(reverse: true)` shows item 0 at the bottom and the others above
it, as a chat shows its messages, the newest first: offset 0 is the bottom,
Up, Page Up and the wheel up scroll on to the items after it, Home goes to
the last item and End to item 0, a `Scrollbar`'s thumb is at the bottom of
its track at offset 0, and items that do not fill the window sit at its
bottom; while the window shows the bottom it keeps showing it as items come
at index 0 (stuck to its end or not: the end of a reverse list is offset 0,
where End goes), and scrolled up it stays on the items it shows, also, by
their keys as above, as older ones load above them. It takes all the room it
is given, which must be bounded, filled with `style` over the theme's
background and text under the items; scrolled while all of it is on the
screen, it has the terminal move the rows that stay in view and paints those
the scroll brought in and those of the items that changed. A
`ListController`, a `ScrollController`, moves its lists to an item, built or
not, as they are next laid out: `jumpToIndex` to the top (in a reverse list
the bottom, the edge it reads from, an item taller than the window showing
its bottom), `ensureIndexVisible` the least that shows it; of a move to an
item and a move of the position (a key, the wheel, `jumpTo`) before the list
is next laid out, the later wins. Given to no list, it keeps the last move
to an item asked for until a list takes it, which makes that move as it is
first laid out, in place of `initialOffset`; a `jumpTo` meanwhile drops it.

## `Scrollbar`

`Scrollbar(child:, axis: Axis.vertical, visibility:
ScrollbarVisibility.always, hideAfter: 1 s, style:, slim: false,
trackStyle:)` (`slim`: the track a thin line in `trackStyle`, the theme's
`faint` by default, the thumb a heavy one at rest and the whole cell over
the line while the mouse is over the bar or drags its thumb) shows the
outermost `Scrollable` inside `child` that scrolls along `axis`, with no
controller (a vertical one and a horizontal one nested show both): a column
at the right edge of the child, or a row at its bottom, the child having the
rest of the room. The thumb is as long as the window is of the content, a
cell at least, and as far along the track as the window along the content,
exactly at its start and end at the ends, in eighths of a cell (block
elements; whole cells where the canvas draws those two columns wide),
estimates where the content's extent is one, as a `ListView`'s is where it
has not been. Dragging the thumb with the left button scrolls the content as
far as the thumb moves, wherever the mouse goes until the release; pressing
the track before or after the thumb scrolls a window that way; a press of
the bar is its own, a `GestureDetector` around it getting nothing of it, and
the wheel over the bar scrolls the scrollable.

## `ScrollbarVisibility.always`

`ScrollbarVisibility.always` shows the thumb while there is something to
scroll, `onScroll` from a move of the scrollable until `hideAfter` after the
last, on the app's clock, and while the thumb is dragged, and `never` shows
no bar, the child having all of the room. The thumb is in `style`'s
foreground and the track in its background, over the theme's `muted` and
`background`; the bar is a repaint boundary, a move that leaves the thumb
where it is painting nothing of it. `wheelAcceleration` on a `Scrollable`, a
`SingleChildScrollView` or a `ListView` (`WheelAcceleration(streak: 150 ms,
max: 6)`; by default `WheelAcceleration.none`, every notch `wheelStep`
cells) scrolls a notch further as the notches come faster: a notch on its
own and the first of a streak scroll `wheelStep` cells, one that comes the
same way within `streak` of the one before goes on the streak, times `1 +
0.8 (e^(r / 3) - 1)` up to `max`, r being 100 ms over the average time
between the last four notches of the streak; a notch less than 6 ms after
the one before goes as far as that one, and what a notch scrolls past a
whole cell is carried on to the next; timed on the app's clock.

## `LogView`

`LogView(controller:, wrap: false, showTime: true, showLevel: true,
selectable: true, scrollbar: ScrollbarVisibility.always, style:,
matchStyle:, currentMatchStyle:, focusNode:, autofocus:)` is `tail -f` for
an app, over a `LogController(maxLines: 10000, level: LogLevel.debug,
filter: '', query: '')`: lines added with `add(text, level:, time:)`
(`addAll`; `clear()`) follow the end while the view shows it; scrolled up it
stays on its lines and counts the new ones (`newLines`, ` ↓ 3 new lines ` at
its bottom right) until End, a click on the count or `follow()` takes it
back (`following`). It keeps `maxLines` lines, the oldest dropped (`length`,
`[i]`, each a `LogLine`: `number`, `text`, `level`, `time`), and shows those
at `level` and above whose text has `filter` in it, ignoring the case while
it is all in lower case (`shownLength`, `shownAt`), a filter typed on or a
higher level refining only the lines shown; `query` is found the same way,
its matches highlighted (`matchStyle`, the current one in
`currentMatchStyle`), `nextMatch()` and `previousMatch()`, and `n` and `N`
while there is a query (hinted), going round them. Each line is its time and
level tag (`DEBUG`, `INFO`, `WARN`, `ERROR` in the theme's `muted`, `info`,
`warning` and `error`, a debug line's text muted) and its text, wrapped with
`wrap`, else cut off and scrolled across by Left and Right
`LogView.sideStep` (4) columns at a time, as far as the widest line. The
scrollbar at its right shows the window of the lines shown, filtered or not
(`ScrollbarVisibility.never` for none). With `selectable`, below a
`SelectionArea` its lines are one `Selectable`: a drag past its top or
bottom scrolls on and selects the lines it scrolls through (up to
`LogView.selectReach`, 5000, lines above the window it was pressed in),
which stay selected and are copied when out of view, each line as it reads,
its time and level too, and the selection stays on its lines as lines are
added, dropped and filtered. A `ListView` underneath: a million lines cost
what the window does, and a line added while following is a hardware scroll
and a row (where the terminal has DECSLRM, or with the scrollbar `never`;
elsewhere the presenter scrolls whole rows and writes again the cells of the
scrollbar's column that differ, the core's design,
[§1.11](../../../twk_core/doc/design/components.md))
