# twk reference: `debug`

[The reference](README.md) · `lib/src/debug/`, `test/debug/`

`debugDumpTree(context)` and `debugDumpRenderTree(context)`, which print the
element tree or the render tree `context` is in, from its root, as
`DiagnosticsNode.toStringDeep` renders it (guides, sizes, flags and their
legend, long runs of siblings folded); `print` in an app goes to its log.

## `Console`

`Console(controller:, child:, rows:)`, the log console: a
`ConsoleController` over an app's `LogSink`
(`AppBinding.of(context).twkApp.logs`) keeps the records the sink keeps and
takes each as it is logged, until `dispose`; it opens and closes (`open`,
`close`, `toggle`, `isOpen`), lists the records at its `level` and above,
shows a window onto them that follows the newest record until scrolled back
(`scrollBy`, `scrollToEnd`, `below`), selects a record (`selectPrevious`,
`selectNext`, `deselect`), puts the selected one on the clipboard over OSC
52 as the log writes it, wrapped for tmux or GNU screen where the terminal
runs in one (`copy(terminal)`), writes the records listed to a file as
`TWK_LOG` keeps them (`save(path)`), lists none of the records taken so far
but those taken after (`clear()`, `cleared` counting those it kept), and
with `openOnError` opens on an error, following the newest record.

## `Console`

`Console` shows its child and, while the controller is open, the console
`rows` rows tall: full screen over the bottom of the child (all of it when
the child is shorter), inline below it, the region growing by it; opening
and closing rebuild nothing. The console is a header (the level, how many
records are listed of those kept since a clear, how many it cleared, how
many are below the window), then a row per record in the window: its time,
its level and the first line of its message and error, in the theme's
colors, the selected one in `selection`, and at its end, muted, what it
leaves out (`+2` lines, `stack`). `showSelected()` shows the selected record
whole in place of the list, in twice the rows (`hideRecord()` the list
again): a header of its time, its level and the line selected, then
`recordLines(record, width)`: its message and error line by line, a line too
long broken at the width, and its stack a frame a line (`location  member`,
a `RecordFrame` with its URI, file, line and column), parsed by
package:stack_trace, the frames of an asynchronous stack in a row; where
some frames are the app's own code, each run of the others (the SDK's,
twk's, a package's in the pub cache) folds into a line saying how many and
whose (`… 70 frames of twk, dart:async`), and where none is, every frame
shows. A frame's place is a link (OSC 8) to its file where the program can
say which, cut from the left when it is too long for the row; `moveLine(by)`
moves the selected line (`selectedLine`, `lineIndex`, `firstLine`), the
window following it; a repaint boundary that paints only the rows it shows,
so a burst of records costs a frame no more than one does. An app builds a
`Console` and calls its controller itself (from an `InputListener`, say), or
turns on the binding's (`AppBinding.debug`, `binding`), which shows the
console and the frame overlay over any app
