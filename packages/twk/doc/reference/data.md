# twk reference: `data`

[The reference](README.md) · `lib/src/data/`, `test/data/`

## `DotCanvas`

`DotCanvas`: shapes (`Shape.points`, `.line`, `.rectangle`, `.circle`,
`.polyline`) in data coordinates and labels, in layers, drawn finer than the
cells with a `Marker` (braille, half blocks, quadrants, sextants, octants, a
dot, a block, a bar or a glyph of one's own); its `RenderDotCanvas`,
`DotGrid` and `DotPainter`. Charts and gauges: `Sparkline`, values as bars
of eighth blocks, the newest at the right;

## `Gauge`

`Gauge` and `LineGauge`, a ratio with a label (`LineGauge(segmented: true)`
a column a cell, `▍`, instead of a line: a meter of segments);

## `BarChart`

`BarChart`, `Bar`s in `BarGroup`s, up or across, with their values and
labels;

## `Chart`

`Chart`, `Dataset`s as dots or lines against two `ChartAxis`es with ticks,
labels and titles, and a legend at a `LegendPosition`. Each is a repaint
boundary with a render object of its own (`RenderSparkline` and so on).

## `Calendar`

`Calendar`, a month in weeks laid out as util-linux `cal`: six rows of weeks
from any `firstWeekday` under the weekdays' names and, with `showHeader`,
the month's name and year, 20 columns by 8 rows, 23 columns with
`showWeekNumbers` (ISO 8601: a row is numbered by its fourth day), a row
less without the header; with `showOutsideDays` the days of the months
around; today (`today`, by default the date of the build), the selected
date, the cursor and a day's own style (`dayStyle`, for events) in the
theme's styles unless given (`style`, `headerStyle`, `weekdayStyle`,
`outsideStyle`, `todayStyle`, `selectedStyle`, `cursorStyle`); English names
unless `monthNames` and `weekdayNames` say otherwise. While it has the focus
the arrows move the cursor a day or a week, Page Up and Page Down a month,
with Shift a year, Home and End to the ends of the month, and Enter and
Space select the cursor's date and call `onSelected` with it; other keys,
Escape too, go up to the nodes above. The arrows, Page Up and Page Down and
Enter are hinted (`←↑↓→ move   pgup pgdn month   enter select` in a
`KeyHintsBar`), none with `keyHints: false`. `canRequestFocus: false` makes
one that only shows a month. A `CalendarController` is what a date picker
drives: the `cursor`, whose month shows (`month`), the `selected` date, the
bounds `firstDate` and `lastDate` that the cursor stays within and that the
days outside of show in `outsideStyle`, and `moveCursor(days:, months:)`;
its dates are days, read whatever their time and zone and given as local
midnights. A repaint boundary: moving the cursor repaints nothing else.

## `RenderCalendar.dateAt`

`RenderCalendar.dateAt(x, y)` gives the date at a cell.

## `Sparkline`

`Sparkline`, `Gauge`, `LineGauge`, `BarChart` and `Chart` paint both colors
of their cells, their style merged over the theme's background and text as a
`Table`'s is, so the colors it leaves unset are the theme's. A `DotCanvas`
paints its blank cells in its `background`, the theme's when it is null, and
a label whose style sets no text color in the theme's text color.

## `Table<T>`

`Table<T>(rows:, columns:, rowKey:, controller:, selection:
TableSelection.row, onActivated:, rowHeight: 1, columnGap: 1, border:
BorderType.none, showHeader: true, sampleRows: 100, focusNode:, autofocus:,
canRequestFocus:, style:, headerStyle:, borderStyle:, selectedStyle:,
cursorStyle:)` shows `rows` in `columns` under a header of their titles that
stays while the rows scroll (sorted by a column, with cells of widgets).

## `Table.source`

`Table.source(source:, columns:, …)` shows the rows of a `TableSource<T>`, a
`ChangeNotifier` that gives `rowCount` and `rowAt(index)` and notifies its
listeners when its rows change, for more rows than a list would hold: the
table reads the rows in view, a sample of the others when it measures its
content columns, and all of them when it sorts, so a million rows scroll as
a hundred do. A `TableColumn<T>(title:, cell:, width: GridTrack.content(),
align:, overflow: TextOverflow.ellipsis, compare:)` shows a `TableCell` of
each row: text in a style (`TableCell(text, style:)`, over the row's), spans
(`.rich`) or a widget (`.widget`); text is one line, placed and cut off as
the column says, a widget as wide as the column and as tall as it likes
within the row, under a `DefaultTextStyle` of the style the row's text cells
take (the row's, the selection's where it is selected, the cursor's), so
that its text shows the row as they do. The columns are `columnGap` cells
apart and sized as a `Grid` sizes its tracks: a fixed one takes its cells; a
content one wants the widest of its title (two cells more for the sort mark
where it sorts) and the text of its cells (a widget cell wants nothing)
within its bounds, a fraction one its `min`; with too few cells the content
columns give up cells down to their `min`, the widest first, with more the
fraction columns share the rest by their fractions within their bounds; what
does not fit is cut off at the right. The text of a content column is
measured once for rows the table was not given before: a list of `rows` or
`columns` not given before or of another length (a new list changes them),
or a `source` that notified or has another count, the rows sorted again
then; of more rows than `sampleRows` and those in view, it measures those in
view then and `sampleRows` rows spread evenly over all of them. The rows are
a `ListView`'s items, `rowHeight` rows tall (null: as tall as their tallest
cell): only those in view and a few past them are built, a row's key
(`rowKey`, by default its index in the rows) keeping its widgets' `State` as
the rows are sorted, and the list scrolls them in hardware, also as the
selection moves past an edge; each row is a repaint boundary, so a row
restyled repaints alone. A drag from the gap after the title of a column
(from the cell after it without a gap) makes the column as wide as the drag
says, and while the table has the focus Shift+Left and Shift+Right make the
column of the cell selected (`TableSelection.cell`), or the one sorted by,
or the first, a cell narrower or wider: a column resized is as wide as it
was made, at least a cell, a content or a fraction column within its bounds.
With a `border`, a line runs down the middle of each gap and under the
header, joined where they cross (ASCII where box drawing is two columns
wide). A click on the title of a column that sorts (`compare`) sorts the
rows by it, keeping the order of rows that compare equal, and again the
other way, the title marked `▴` or `▾`; while the table has the focus, `s`
does that for the column of the cell selected (`TableSelection.cell`) or the
one sorted by (the first that sorts for none), `<` and `>` for the column
that sorts before or after the one sorted by. A
`TableController(selectedKey:, selectedColumn:, sortColumn:, sortAscending:,
columnWidths:)` holds the selection, a row's key, which stays on its row as
the rows are sorted, added and removed, the order (`sortBy`) and the widths
given to the columns resized (`columnWidths`, by column;
`resizeColumn(column, width)`, null giving a column back the width its
`width` makes), and tells its listeners of each change. As `selection` says
(`none`, `row`, `cell`), a click selects a row or a cell and gives the table
the focus; with the focus, Up and Down select the row above and below, Page
Up and Page Down a window's rows away, Home and End the first and the last,
Left and Right the cell before and after, and Enter calls `onActivated` with
the row selected; a key that selects no other row or cell, or resizes no
column, goes on to the nodes above, and the view scrolls the least that
shows the row selected after each and after a sort, and shows it from the
first frame and with a new controller; with `none` the keys scroll the rows.
A key of `rowKey` the controller selects is looked for out from where the
last one was found, a row below and a row above at a time, an index found at
once. The styles merge over the theme's background and text: `style`; the
header's bold, the lines `border`, the row selected `selection`, the cell
selected while the table has the focus `primary` reversed, unless given. It
takes all the room it is given, which must be bounded. Columns written in
its call need its type argument, `Table<File>(rows: files, columns:
[TableColumn(…)])`: Dart infers the arguments of a call that are not
closures apart from one another, with its type argument still unknown, so a
`TableColumn(…)` in a list written in place does not see `rows` — its
closure takes an `Object?`, and without the type argument the table is a
`Table<Object?>`. Columns from elsewhere (a `List<TableColumn<File>>`), or a
type argument on every column of the list, give the table its type as well;
`untyped_table` of [`twk_lints`](../../../twk_lints/README.md) points at a
table whose row type was inferred as `Object?` or `dynamic`.

## `TreeView<T>`

`TreeView<T>(roots:, children:, label:, hasChildren:, nodeKey:, controller:,
onActivated:, showGuides: true, focusNode:, autofocus:, canRequestFocus:,
style:, guideStyle:, selectedStyle:, unfocusedSelectedStyle:)` shows `roots`
and the descendants of the nodes expanded, each node a row below its parent
indented a level more (with lazy children and guides): `▸` before a node
with children, `▾` while it is expanded, and with `showGuides` lines joining
each node to its parent, `├─`, `└─` for the last child, `│` past the
children between (ASCII where box drawing is two columns wide); after them
`label(context, entry)` builds what shows of the node from its `TreeEntry`
(`node`, `key`, `depth`, `hasChildren`, `expanded`, `selected`), a row tall.
`children(node)` gives a list, or a future of one, which shows a spinner row
below the node until it ends, then its list, kept by the node's key until
`TreeController.reload`, or a row with the error it failed with (in the
theme's `error`), forgotten as the node collapses; without `hasChildren`,
`children` is asked for every node shown, so a node with none shows no
expander. The rows are a `ListView`'s items, only those in view and a few
past them built (of a hundred thousand nodes, a window's worth), a node's
key (`nodeKey`, by default the node) keeping its label's `State` as rows
come and go; the nodes shown are walked again as the nodes expanded change,
as a load ends and as the view is built with a new widget. A
`TreeController(selectedKey:, expanded:)` holds the nodes expanded
(`isExpanded`, `expand`, `collapse`, `toggle`, `expandAll`, `collapseAll`)
and the node selected by their keys, kept while the nodes around them
change, and `reload`s children that came in a future. A click selects a node
and gives the view the focus, a click on its expander expands or collapses
it; with the focus, Up and Down select the node above and below, Page Up and
Page Down a window's rows away, Home and End the first and the last, Right
expands the node selected or selects its first child, Left collapses it or
selects its parent, `+` expands it, `-` collapses it, `*` expands it and
every node below it (those whose children come in a future as they come),
and Enter calls `onActivated` with it, or without one expands or collapses
it; a node collapsed while the node selected is below it is selected; a key
that does nothing there goes on to the nodes above, and the view scrolls the
least that shows the node selected, from the first frame on. The styles
merge over the theme's background and text: `style`; the guides `guideStyle`
(the theme's `border`); the row of the node selected, its label's text too,
`selectedStyle` (the theme's `selection`) while the view has the focus and
`unfocusedSelectedStyle` (`selectedStyle`, else the theme's `selectionIdle`)
while it has not. It takes all the room it is given, which must be bounded.

## `TreeTable<T>`

`TreeTable<T>(roots:, children:, columns:, hasChildren:, nodeKey:,
controller:, tableController:, selection: TableSelection.row, onActivated:,
showGuides: true, columnGap: 1, border: BorderType.none, showHeader: true,
sampleRows:, focusNode:, autofocus:, canRequestFocus:, style:, headerStyle:,
borderStyle:, guideStyle:, selectedStyle:, unfocusedSelectedStyle:,
cursorStyle:, pointerShapes: true)` is a tree whose nodes are the rows of a
`Table` (htop's tree, a file manager's sizes and dates, a dependency
browser): the first of its `TableColumn`s shows a `TreeView`'s guides and
expander before the node's text, the others the node's columns, sized,
measured and resized as a `Table`'s, the nodes shown walked as a `TreeView`
walks them and children that come in a future shown as its are. Sorting by a
column orders the children of each node among themselves, every node above
its children, the guides following the order shown. The keys and the mouse
are a `Table`'s and a `TreeView`'s: with `TableSelection.row` Right expands
the node selected or selects its first child shown and Left collapses it or
selects its parent (with `cell` they move the cell), `+`, `-` and `*` expand
and collapse, Enter calls `onActivated`, or without one expands or collapses
the node, and a click on an expander, inside the tree's column alone,
expands or collapses its node as it selects it; with `TableSelection.none`
the keys scroll the rows as a `Table`'s do and neither select, expand,
collapse nor activate a node, a click selects nothing and one on an expander
expands or collapses its node alone. Its `controller`, a `TreeController`,
holds the nodes expanded and the node selected, by key, kept while it is
sorted and while the nodes above it expand and collapse, and its
`tableController` the sort, the widths and the column of the cell selected,
its `selectedKey` following the node selected and the node selected
following it. Only the rows in view are built, so a tree of a hundred
thousand nodes, ten thousand of them shown, builds per key what a `Table` of
those rows does;

## `DirectoryTree`

`DirectoryTree(root:, fileSystem:, controller:, onSelected:, onOpened:,
showHidden: false, gitignore: true, watch: true, showSizes: false, filter:,
icon:, showGuides: false, focusNode:, autofocus:)` is a `TreeView` of the
files under `root` for a side panel: the root expanded, each directory
listed as it is first expanded (a spinner meanwhile), the directories first
in bold with a separator, then the files, each by name in any case; the
hidden entries left out but with `showHidden`, with `gitignore` what the
`.gitignore` files under the root ignore and `.git` too, the files a
`FileFilter` refuses; `showSizes` puts each file's size at the end of its
row (`4.2 KB`), `icon(entry)` what goes before a name, and a directory that
fails to list says why below it in the theme's `muted` (`(permission
denied)`). With `watch`, each directory expanded is listed again a tenth of
a second after its `PickerFileSystem.watch` tells of a change, the selection
and what is expanded kept. Enter and a double click open a file (`onOpened`)
and toggle a directory. A `DirectoryTreeController` reads the path
`selected`, `expand`s and `collapse`s directories, `reveal(path)`s a path,
expanding the way to it and selecting it, and `refresh([directory])` lists
again;

## `Gitignore`

`Gitignore(text)` is the matcher of a `.gitignore`'s patterns (comments,
`!`, `/` at the end or anchoring, `*`, `?`, `[...]`, `**`), its `match(path,
isDirectory:)` what its patterns decide of a path and `ignores` whether it
or a directory above it is ignored; the styles are a `Table`'s, the guides
in `guideStyle` (the theme's `border`), and it takes all the room it is
given, which must be bounded.

## `TaskList`

`TaskList(tasks:, spinner: SpinnerFrames.dots, showElapsed: true, style:)`
shows tasks and how far they have got, a row each (build steps, an
installer's stages, what an agent does): each `TaskItem(label, status:, id:,
elapsed:, children:)` is the mark of its `TaskStatus`, `◦` for `pending`, a
spinner of `spinner`'s frames for `running`, `✓` for `done`, `✗` for
`failed` and `↓` for `skipped`, in the theme's `muted`, `primary`,
`success`, `error` and `muted` (a skipped task's label muted too), then its
label, cut off with `…`, and with `showElapsed` the time it has run on the
app's clock in `muted`: from the frame that showed it running, in whole
seconds while it runs (`12s`), to the tenth of a second once it is done or
failed (`3.4s`), then minutes and seconds (`2m 05s`) and hours and minutes
(`1h 02m`); none for a task pending or skipped, or shown done before it ran;
a task's `elapsed`, the time it has run or ran as the app knows it, is shown
in place of the time the list measures, and the list does not move it on. A
task's `children` are in the rows below it, indented two cells a level. The
list is as tall as its rows and as wide as it may be; each row is a repaint
boundary laid out on its own, so a task that changes, or whose spinner or
time moves on, repaints its row alone, and a row stays with its task (`id`,
by default its label, among its siblings) while tasks come and go around it.
Outside an app the spinner shows its first frame and no time shows. Its rows
are in `style` over the theme's background and text.

## `DescriptionList`

`DescriptionList(items:, separator: ':', gap: 1, termAlign: TextAlign.left,
termWidth:, maxTermFraction: 0.4, stackBelowWidth: 30, termStyle:,
valueStyle:)` shows terms and their values a row each, as `kubectl describe`
or `docker inspect` print them: each `DescriptionItem(term, value,
semanticsValue:)` (a widget; `DescriptionItem.text(term, value, style:)` for
a string) is its term and `separator`, placed as `termAlign` says in a
column as wide as the longest term of its group, or `termWidth`, but where
the group's rows do not all fit so no wider than `maxTermFraction` of the
list (a term cut off with `…`), then its value `gap` columns after it, laid
out in the room to the right edge: a text that does not fit wraps under its
own column and a widget is given that width (a `ProgressBar` fills it).

## `DescriptionItem.group`

`DescriptionItem.group(title)` starts a group, its title bold, a blank row
above it where rows come before. Narrower than `stackBelowWidth` and than
its widest row, each value goes under its term, two columns in. Terms are in
the theme's `muted` and `termStyle`, values in its text, `valueStyle` and
their own; the list paints only its text and values. Below a `SelectionArea`
a row is copied as its term and its value on lines of their own; on plain
output its rows are the lines written; a screen reader reads `term: value`,
the whole term however much of it shows, and a group's title as a heading.

## `Heatmap`

`Heatmap(rows:, columns:, value:, min:, max:, scale: HeatmapScale.shades(),
rowLabels:, columnLabels:, cellWidth: 2, showLegend: false, legendLabels:
('less', 'more'), tooltip:, onSelected:, focusNode:, autofocus: false,
keyHints: true, style:, labelStyle:, cursorStyle:)` shows `rows` × `columns`
cells, each `value(row, column)` on its `scale` from `min` to `max` (by
default the smallest value and the largest), a null or non-finite value
blank: `HeatmapScale.shades(glyphs)` (` ░▒▓█` by default; `.:+#` for a glyph
that does not fit the cell) or `HeatmapScale.colors(gradient, glyph: '■')`,
the glyph in the gradient's color at the value (the shades on a terminal
that shows no RGB colors). A cell is `cellWidth` columns, its glyph over all
but the last, a blank between two; `rowLabels` start the rows, the widest
and a blank before the cells; `columnLabels` go in a row above them, each at
its column and cut off a blank before the next (an empty one is none);
`showLegend` writes `less ░▒▓█ more` below them at the right. With `tooltip`
or `onSelected` it takes the focus: a cell marked in `cursorStyle` (the
theme's `selection`), the top left one at first, the arrows move it and
Enter and Space call `onSelected(row, column)`, other keys going up; a click
marks and selects a cell; the mouse over one shows its `tooltip(row,
column)` in a `Tooltip` under the heatmap at its column (none without an
`Overlay`), and while the focus is in it and the mouse elsewhere, the marked
one's. A screen reader reads it as a table of the values, a row of the
cells' tooltips or values (`no data` for none). Its `RenderHeatmap` is a
repaint boundary: moving the mark repaints nothing else.

## `ActivityHeatmap`

`ActivityHeatmap(counts:, end:, weeks: 26, firstWeekday: DateTime.monday,
tooltip:, scale: ActivityHeatmap.defaultScale, onSelected:, showLegend:
false, legendLabels:, cellWidth: 2, weekdayNames:, monthNames:, focusNode:,
autofocus: false, style:, labelStyle:, cursorStyle:)` is one of counts by
day (`counts`, a `Map<DateTime, num>` read by the year, month and day, those
of the same day added up), a column a week from `firstWeekday` and a row a
weekday, the last column the week of `end` (the day of the build when null),
the oldest at the left: a day without a count at 0, the lowest shade (`·`),
the days after `end` blank and the largest count the last shade; every other
weekday labelled from the first (`Mon`, `Wed`, `Fri`, `Sun`) and a month
over the week that has its first day (`Oct`). Its keys, mouse and tooltips
are a `Heatmap`'s, a day's tooltip by default `3 on 2026-10-21`, and
`onSelected` gets the day chosen, local at midnight
