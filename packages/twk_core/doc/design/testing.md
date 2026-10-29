# twk_core design: §2 Testing

[The design](README.md)

## `test/unicode_test.dart`

Every `GraphemeBreakTest.txt` case + widths.

What it catches: segmentation and widths.

## `test/presenter_fuzz_test.dart`

~64,000 random frames (text, CJK, emoji, ZWJ, fills, clip, translate, blit,
scrolls, resizes) → bytes into an **independent terminal emulator**
(`package:twk_test/vt.dart`: autowrap with pending wrap, BCE, DECSTBM,
DECSLRM, ICH/DCH, REP, wide-glyph breaking) → **the whole screen is
compared**, not just the damage.

What it catches: any missed damage, cursor/SGR/scroll/BCE errors, wraps; 10
configurations, including a terminal without BCE, Konsole's lines, Konsole's
caps on an xterm-like terminal, one without DEC 2026 and hardware scrolling,
one with left/right margins, a legacy wcwidth terminal, and scroll detection
limited or off; a frame with no changes must produce 0 bytes.

## `test/presenter_test.dart`

Presenter edge cases the random frames don't reach.

What it catches: decorated blanks not rewritten when only their colour
changes, a one-column rectangle scrolled with DECSLRM, `invalidate()`
keeping the cursor state, link targets not percent-encoded, underline
colours not in the colon form of SGR 58, fills putting side by side what a
terminal would join, a cursor-only frame hiding the cursor, a blank before
text not taking the text's SGR, a parameter equal to its default written,
reserved cells written, an inline region rewriting more than the row it
gains, or not handing the screen back below itself or erased; committed rows
not above the region or out of order, the region drawn again where it could
move down as it is, rows wider or narrower than the region (or waiting
across a width change) not cut or padded.

## `test/frame_bytes_test.dart`

The bytes of typical updates of a chat screen (100×30 and 200×60, DEC 2026
on and off), each bounded by a fixed count; the emulator checks the screen
after every frame.

What it catches: an encoding technique dropped (ICH/DCH, DECSTBM + SU,
scroll detection, ED 2, EL, REP, SGR reuse, the shortest cursor move,
default parameters left out), named in the failure.

## `test/canvas_reference_test.dart`

The optimised canvas against a naive reference painter built from plain
objects, 600 seeds, both text modes.

What it catches: composition caches, fast paths, wide-glyph rules, clipping,
links.

## `test/canvas_test.dart`

Canvas and surface edge cases.

What it catches: a half-covered wide glyph whose other half isn't damaged,
blits within one surface (overlapping, off the edges), a wide fill cut by
the clip.

## `test/style_test.dart`

Pens, blending and SGR.

What it catches: alpha blended over the wrong background or default colour,
blends not recomputed for new default colours, SGR per colour mode, a pen id
from another table accepted.

## `test/fill_test.dart`, `test/byte_sink_test.dart`

Fills and comparisons of typed arrays against naive loops for every length
and offset; the output buffer.

What it catches: an off-by-one in a block fill or a 64-bit scan; a view not
reused while the length is the same, growth from a small capacity.

## `test/screen_test.dart`, `test/terminal_test.dart`, `test/sequences_test.dart`

`Screen`, the colour mode, notifications and multiplexer from the
environment, dark or light by the background, the OSC strings.

What it catches: a screen resized away and back not rewritten, an empty
screen with a visible cursor, committed rows not written by an inline
screen's next render; `NO_COLOR`, `COLORTERM`, `TERM` and Windows defaults;
a terminal taken for another (by a variable it inherited, inside tmux or
screen); a colour on the wrong side of half white's luma; control characters
escaping the title or a notification, a notification not cut between
graphemes, a tmux or screen wrapping that ends early or a screen piece over
252 bytes; the clipboard inside tmux not sent as it is before its wrapping,
or inside screen not in pieces ended by BEL.

## `test/input_parser_test.dart`

Each kind of input and reply, 300 random splits of the stream + 2000 junk
inputs + 5000 strings of sequence pieces.

What it catches: a sequence decoded otherwise (a colour scheme report other
than `997;1` or `997;2` taken for one), parser robustness.

## `test/input/parser_test.dart`, `test/input/events_test.dart`

F1 to F4 with modifiers in xterm's CSI form, a mouse report's modifiers and
tilted wheel, a paste many times the parser's first buffer; the events as
values.

What it catches: an F-key or a wheel direction taken for another, a modifier
of the mouse lost; a paste cut where its buffer grows; equal events unequal
or hashed apart, a field left out of equality, a key's `ctrl`, `alt` or
`shift` wrong.

## `test/input/kitty_keyboard_test.dart`

What kitty's keyboard protocol sends under each of its flags, as
`packages/twk_term`'s emulator writes it.

What it catches: a repeat or a release not the key's `kind`, in `CSI u` and
in the legacy forms (arrows, `~` keys, F1–F4); a key that types text not the
text it types (the associated text, the shifted key) or Shift left among its
modifiers; a shortcut not its unshifted key with its modifiers; text that is
no character taken for one; a modifier key alone made a `KeyEvent`.

## `test/terminal/kitty_keyboard_test.dart`

`TerminalOptions.kittyKeyboardFlags` on a `Terminal` over an in-memory link,
both modes.

What it catches: flags other than those asked for with disambiguation
pushed, pushed off the alternate screen or popped after leaving it, pushed
or popped more than once, not popped by `suspend` or pushed again by
`resume`, missing from what puts the terminal back;
`TerminalInfo.kittyKeyboardFlags` not what was pushed, or not 0 without the
protocol; anything asked or pushed without `kittyKeyboard`.

## `test/join_test.dart`

One test per UAX #29 joining rule between adjacent cells.

What it catches: separately drawn cells are not joined by a
grapheme-clustering terminal.

## `test/render_test.dart`

Retained render objects against the expected screen.

What it catches: rows a partial repaint must not skip (appended lines,
scrolling, pen changes), cells left by a child replaced or removed, a
translucent repaint boundary.

## `test/render/relayout_test.dart`

Layouts counted per object after a layout change.

What it catches: a mark that climbs past a relayout boundary, a boundary not
moved when the constraints or `parentUsesSize` change, cells left behind by
a boundary that shrank, a boundary marked while detached never laid out.

## `test/render/intrinsics_test.dart`

What objects ask for against what they draw, in both text modes and
ambiguous widths.

What it catches: text measured otherwise than the screen draws it, an answer
not cached or not forgotten on a change, a parent that asked not laid out
again when its child changes.

## `test/render/layout_callback_test.dart`

A render object that makes its child in a layout callback for the
constraints it gets, under a parent that asks for its intrinsic sizes or
not.

What it catches: what the callback changes not laid out with the object, or
asking for a layout on the next frame; a relayout boundary the callback
marks below what the object lays out (a padding laid out tight, an item of a
list with an item extent) not laid out and painted in the same frame;
layouts that keep marking each other not stopped after 100 passes, the error
not shown by the one laid out last or reported more than once, or not gone
once they stop; a parent laid out by intrinsic sizes the callback changed,
or a root whose intrinsic sizes it changed, not laid out again on the next
frame, until they hold; a parent that asked for none laid out again.

## `test/render/flex_test.dart`

`RenderFlex` and the child list.

What it catches: children out of order after insert, move and remove; free
cells, gaps and flexible shares not in whole cells or leftovers in the wrong
place; each main and cross alignment, `MainAxisSize`, `FlexFit`; overflow
not cut off or reported more than once; intrinsic sizes; along an unbounded
main axis a child, flexible or not, not as long as it wants, or the flex not
as long as its children whatever its `MainAxisSize`.

## `test/render/viewport_test.dart`

`RenderViewport`; frames through the emulator.

What it catches: the child not laid out as long as it likes along the axis
(a column in it not as tall as its children, flexible ones too), the offset
not kept within the child's extent less the viewport's when set before or
after a layout, `onExtents` not told; a one-row scroll of a view all on the
screen not declared or scrolled in hardware (`DECSTBM + SU/SD`, `DECSLRM`
for a narrower view, rewritten where the terminal has no margins) or
painting more than the exposed rows, a view scrolled back painting anything;
a view cut off by an ancestor, scrolled along a horizontal axis, painted
over by a later child of a stack, or with something inside it marked for
paint or laid out as it scrolls, not painted in full; a repaint boundary
inside it not repainting on its own; the child not hit at the offset, or hit
outside the window; axis, offset and background not described.

## `test/render/list_test.dart`

`RenderList` with a `ListItemManager` of the test's; frames through the
emulator.

What it catches: items built outside the window and the cache rows or not as
wide as the list, or kept once they leave; a height not measured, the others
not taken to be the average, an item extent not kept or measured, heights
not forgotten when the width changes; a move of a window or less not exact
or not laying out the items it passes, a longer one not where the estimate
puts it, 0 or past the end not exactly the start or the end; near an end, a
move of a window stopping short of the end or skipping items; an offset
`onMetrics` sets not taken in the same layout; the item at the top moving as
the items above it are measured, the offset it settled at not told;
`jumpToIndex` and `showIndex`; of an offset set and a move to an item since
the last layout, the later not winning, the offset the list is at too; not
following the end as items are added while it sticks to it, not starting
there, items removed leaving the window empty; unbounded constraints taken;
a one-row scroll of a list all on the screen not shifted and scrolled in
hardware, or painting more than the row exposed and the items laid out again
or moved; a mark inside it other than by its layout not painting all of it,
a repaint boundary inside an item not repainting on its own as it scrolls; a
list cut off by an ancestor scrolled instead of painted; the rows below its
items not filled; an item hit outside the window; items, offset, extent,
cache and sticking not described.

## `test/render/boxes_test.dart`

`EdgeInsets`, `RenderPadding`, `Alignment`, `RenderPositionedBox`,
`RenderConstrainedBox`, `RenderFractionallySizedBox`,
`RenderIntrinsicWidth`, `RenderIntrinsicHeight`.

What it catches: layouts, the odd cell in the middle, a child sticking out
not cut off, a box with factors taken for a relayout boundary, intrinsic
sizes, a new constraints object for a child laid out again within the same
ones; a child not given exactly its fraction, or a fraction not rounded to
the nearest cell, a half up (0.29 of 100 cells floored to 28), a factor
applied along an unbounded axis; a size to content not rounded up to its
step, a tight extent not kept as it is, a row whose children stretch not as
tall as its tallest child.

## `test/render/borders_test.dart`

`BorderType`, `RenderDecoratedBox` and `RenderDivider`; every frame also
through the emulator.

What it catches: a missing piece of a type; a type on any of the 16 sets of
sides, ASCII not drawn where box drawing is two columns wide (both text
modes), side and corner pens, `none` not showing its background; titles out
of place, of order or of room, not cut off with an ellipsis (a two-column
one too) or splitting a wide glyph, no row for titles without a border;
insets, `inner`, sizes and intrinsic sizes; new pens laying it out, new
sides, padding or titles not, titles not measured again for another owner or
shaped again for another screen; a divider off the middle or longer than
allowed along an unbounded axis, a new direction not reaching its parent.

## `test/render/border_merge_test.dart`

`Canvas.mergeRun`, and `RenderDecoratedBox` and `RenderDivider` with
`merge`, over each other in a `RenderStack`.

What it catches: a piece of a type not joined with every other piece of it,
or with the half lines of single and heavy lines; an arm's weight not kept
where Unicode has the mix, or a piece not in the new weight where it hasn't;
a round corner not kept where nothing is added to it, dashed lines not
merged as solid ones, ASCII merged with box drawing, text in a cell not kept
with its style or a wide glyph not kept whole, a glyph drawn that is no
piece of line not drawn as `run` draws it; a trimmed end reaching past the
line it lands on, `under` not painted first, clipping and wide glyphs
otherwise than `run`; merged boxes side by side, one above another, four
around a point or nested not joining their lines (every type), unmerged ones
not covering them, a side without a neighbour not ending in a joint, ASCII
not merged where box drawing is two columns wide, mixed types not mixing
where Unicode can, the titles of the edges they cross or share not kept; a
merged box over nothing looking otherwise than unmerged (every type, the 16
sets of sides, small sizes, one pen and a pen per side that sets every
color), the background not under the merged lines or not filling the rest;
dividers across and down a box or crossing each other not joining (every
type, mixed types), or over nothing drawn otherwise than unmerged; `merge`
laying out instead of repainting, or not described.

## `test/render/stack_test.dart`

`RenderStack`; frames with repaint boundaries also through the emulator.

What it catches: children placed by the alignment with each `StackFit`, the
stack's size with and without them, each way a child is pinned (both edges,
its size, no edge, up to the far edge, a negative edge cut off), paint
order, intrinsic sizes; a boundary repainted on its own covering the
children over it (boundaries or not, in nested stacks, in a stack its parent
cuts off), children painted again that don't overlap it, a log moving the
panel over it along as it scrolls, a log over a repainted boundary losing
lines.

## `test/render/grid_test.dart`

`GridTrack` and `RenderGrid`; every frame also through the emulator.

What it catches: a track of a kind not sized as it says or outside its
bounds, cells left over not going to the first tracks, gaps; a spanning
child not growing the content tracks it spans by even parts, growing them
across a fraction track, or sized before those that span fewer; rows asked
for heights at other widths than their columns'; the length along an
unbounded axis, intrinsic sizes; a child without a row and a column not
placed after the one before or not wrapped, taken cells skipped; a boundary
repainted on its own covering the children after it; overflow not cut off or
reported more than once; new tracks or gaps not laid out again, equal ones
laid out; tracks, lengths, overflow or a child's cells not described; a
child with a row and no column not showing the error.

## `test/render/wrap_test.dart`

`RenderWrap` on a screen.

What it catches: children of mixed widths not wrapping at each of several
widths, gaps between the children or the runs, a vertical wrap not filling
columns, runs made along an unbounded main axis, a child not let take the
whole main axis; the size not that of the longest run and the runs, or of
the constraints where they ask for more; a `WrapAlignment` not sharing the
free cells of a run, or across the runs, in whole cells, a
`WrapCrossAlignment` not placing a child in its run; runs that don't fit not
cut off, reported more than once or not described; intrinsic sizes along and
across the main axis, of a vertical wrap too; a child's new size or a new
setting not laying the wrap out again; a child of a later run not hit at its
cell.

## `test/render/paragraph_test.dart`

`RenderParagraph` in Latin, Cyrillic, CJK, kana, emoji, ZWJ sequences, flags
and combining marks; every frame also through the emulator, in both text
modes and ambiguous widths.

What it catches: each wrap mode, each ellipsis, `maxLines`, alignment and
justification, intrinsic sizes, a grapheme split, a change laid out when it
needs only a repaint or not laid out when it does, clusters not split again
for another owner's segmenter, pens not looked up again in another style
table.

## `test/render/paragraph_text_range_test.dart`

`RenderParagraph.textRangeAt`.

What it catches: the cluster at a cell not given by its offsets into the
spans joined (either cell of a wide one, a cluster of several code points),
left of a row's text (aligned or not) not its start, right of it not the
next row's start after the spaces it hangs and its line break, what takes no
cell (the CR of CR LF) not going with the cluster after it, a justified
row's gap not the space before it, an ellipsis not standing for the clusters
it replaces (each line's own, cut off at its start), rows cut off, above the
first row and below the last, the ranges of a new text; the offsets of the
clusters found by a layout before they are asked for, or found again for a
layout at another width (counted).

## `test/render/diagnostics_test.dart`

`DiagnosticsNode` as text and JSON, the `describe…` functions, `describe()`
of each kind of render object.

What it catches: guides, the size column or the legend out of place (wide
glyphs counting two columns), a run folded below `fold`, a text not quoted,
escaped or cut off, a pen, constraints, insets or an alignment written
otherwise; a property missing or shown at its default, a boundary, needs
layout or needs paint not flagged, a flex's overflow not reported; a frame
describing anything.

## `test/render/error_test.dart`

Render objects whose layout or paint throws, in a tree that fills the
screen.

What it catches: the message not shown in white on red where the object is,
as big as it is within the constraints, or cut off at its bounds; an error
reported more than once, or not again once fixed and broken again; what a
throwing paint left on the canvas moving the rest; a repaint boundary inside
painting over the error; without `onError`, an error not thrown once the
flush ended (or at once outside one) or the others not shown; an object
showing an error not described so.

## `test/render/hit_test_test.dart`

`hitTest` and `HitTestResult` over nested, clipped and overlapping objects,
and over every cell of a 200×60 tree.

What it catches: objects not found from the deepest to the root, or the cell
not in each one's coordinates; what sticks out of its parent or any ancestor
hit; the children of a stack or a grid not tested from the one on top (after
a move too), a flex's gaps not leaving the cell to what is under it; opaque
not hiding what it covers, translucent not letting it be hit, deferToChild
hit without a child, an object showing an error not hit whole; the core's
objects not opaque where they paint, a box not hit around its child, a
decorated box without a background hit where it draws nothing; a result not
emptied, not growing for a deeper path, or growing while reused.

## `test/render/debug_paint_test.dart`

The repaint rainbow and the relayout highlight of a `PipelineOwner`.

What it catches: a boundary tinted that didn't repaint, or not tinted anew
on each repaint; a tint not blended over the background or changing a cell's
glyph, colours or attributes; a tint beyond where the boundary's ancestors
let it paint; the rows of a log tinted twice (scrolled, or painted by its
parent); a flag reaching another owner's tree; turning a flag on or off not
repainting everything; an outline around more or fewer objects than those
laid out, one frame's outlines in more than one tint, the next not in the
next, half of a wide glyph on an edge left out, objects laid out before the
highlight was turned on outlined.

## `test/outbox_test.dart`

Bytes on their way to stdout, against a sink that rejects writes during a
flush like dart:io.

What it catches: writes during a pending flush wait in order, one flush at a
time, frames are copied into one reused buffer (the caller's buffer is free
at once), a failed flush.

## `test/terminal/suspend_test.dart`

`TwkApp.suspend` on `HeadlessTerminal` (on `VtTerminal` for a backend that
can't be handed over), the screen in the emulator (the inline one below
guarded history).

What it catches: frames written while handed over, the backend not handed
over before `run` or taken back after it, the screen not repainted in full
afterwards (what another program drew left on it), what `run` throws not
reaching the caller, a second `suspend` while handed over not refused, the
inline region not parked below itself, or started again over what the other
program printed instead of below it (on the cursor's line, or the next),
quit while handed over taking the terminal back, a backend that can't be
handed over drawing meanwhile.

## `test/terminal/notify_test.dart`

`Terminal.notify` and `Terminal.copyToClipboard` in a pseudo-terminal
(`tool/pty_run.py`) in the environment of kitty inside tmux, of foot, of a
terminal without notifications, and for the clipboard inside tmux, inside
GNU screen and outside both.

What it catches: the protocol or the multiplexer not taken from the
environment by the probe, bytes written where nothing is known to show them;
the clipboard not wrapped for tmux or screen, or wrapped outside them.

## `test/terminal/color_scheme_test.dart`

`test/terminal/color_scheme_app.dart` in a pseudo-terminal
(`test/terminal/color_scheme_pty.py`) that answers the probe as a dark
terminal with mode 2031 and then reports a switch to light.

What it catches: the mode not asked for by the probe, not turned on while
the app runs (or more than once) or not off at the end, the brightness not
taken from the background, the report not decoded, the default colors not
asked for again after it.

## `test/terminal/socket_test.dart`

`Terminal.connect` against a shell's end spoken by hand, `TerminalShell`
serving a terminal in memory to `TwkApp` on `Terminal.connect` or to the
wire spoken by hand, the address files; `Terminal.open` in a process without
a terminal (`test/terminal/socket_app.dart`).

What it catches: the hello without the token, output before raw mode, a size
or environment not the shell's, frames, input or resizes not passed on, a
flush completing before the shell wrote the bytes, the restore bytes not
told (the title's pop, empty once restored or while suspended), mouse
reports switched not written or not undone by the restore, the shell going
away not ending `run()`; the console not raw while an app has it or not
cooked after, input passed on while no app has it in raw mode, the restore
bytes not written for an app that went away or part of a frame cut short
written, a newer app not taking over, a wrong token or protocol not refused,
`stop` leaving the address file or the socket; an address file not read
back, the project not found by its pubspec, a socket path too long not moved
to a temporary directory, another server's address file removed;
`Terminal.open` not finding the project's shell.

## `test/terminal/socket_wire_test.dart`

The wire where it breaks: frames split across reads or too long, a shell
that sends nonsense, doesn't answer or isn't there, an app that sends no
hello, an unknown frame or one too long; `Terminal.open` failing at a shell
(`test/terminal/socket_app.dart` with a trace it can't write); the
addresses.

What it catches: a frame bigger than the reader's buffer garbled; a frame
too long taken in; connecting not failing, or hanging, against a shell that
is gone, silent or broken; a flush left waiting when the shell goes away or
the link closes; a link whose input nobody listened to never closing
(`Terminal.open` then ending the process without its error); an app with a
broken hello or frame not cut off, or the terminal not put back for it;
`stop` not idempotent; a project without a pubspec, a socket left behind not
replaced; addresses unequal or printed with their token.

## `test/terminal/mouse_tracking_test.dart`

`mouseTrackingSequence` and `HeadlessTerminal.mouseTracking`.

What it catches: a switch that doesn't turn the old mode off before the new
one on, SGR coordinates not on with the first reports and off with the last;
a `HeadlessTerminal` starting with reports, a switch not written to its
frames, or written in the inline mode or once closed.

## `test/app_test.dart`

The frame loop against `HeadlessTerminal`.

What it catches: layout measuring text otherwise than the screen draws it,
requests coalesce into one frame, `beforeLayout` not at the start of each
frame (in the inline mode before the region is sized), its changes not laid
out by that frame or asking for another, `afterPresent` not at the end of
each frame, after its bytes are written and before they are flushed (also in
a frame with no bytes), or its changes not painted by the next frame, input
handled before the first frame, the fps cap, frames spaced by the wall clock
instead of the clock given, a repaint asked for during a held flush, errors
in paint/handlers/timers ending `run()` after the restore, quit, resize; a
reported default color not blended with or one already known repainting;
frames in a row not in full, not below each other, the presenter's bytes
written too, the name not cut to the width, committed rows after their
frame, the inline region left at the end; the stages of the last frame not
adding up to it or holding another stage's work, the repaint boundaries it
repainted not counted.

## `test/terminal/trace_test.dart`

`TraceWriter` and `Trace`; an input trace fed to `HeadlessTerminal`;
`test/terminal/trace_app.dart` in a pseudo-terminal with both traces on.

What it catches: the header or a record laid out otherwise, a write on the
caller's path, records lost or out of order while a write is on its way, a
caller's buffer not copied, a cut-off file not read up to the cut, a broken
one read; a lone ESC fed back as Alt with the next key, a split sequence
cut; the probe or any write missing from the output trace (it must equal the
capture byte for byte), its replay not reaching the capture's screen,
`--frame` and `--step` off by one; reads missing from the input trace, which
must decode to the keys typed.

## `test/terminal/timeline_test.dart`

`test/terminal/timeline_app.dart` run with the VM's Dart timeline stream
recorded to a file.

What it catches: a phase missing from a frame's slices or out of order
(`Build`, `Layout`, `Paint`, `Present` and `Finalize` inside `Frame`), a
slice left open; slices on the timeline while `TWK_DEBUG` doesn't name it.

## `test/headless/`

`HeadlessTerminal` and `renderToString`; an inline app on it, its frames fed
into the emulator below guarded history.

What it catches: input split anywhere decoded by the parser, the pause each
kind of pending input waits and what timing it out gives, resizes, frames
kept as written, input not dropped while handed over, a line break missing
or extra when taken back (inline, the cursor off the start of a line),
close; a notification not in the protocol given, not wrapped for the
multiplexer or not under an id of its own, or written for none or once
closed; text rows with wide and combining glyphs, the ANSI frame shown with
its styles by the emulator, a tree painted before painted in full; an inline
region writing to the history, not starting on the next line after text, not
growing, shrinking or repainting on a resize, or writing other bytes than on
`VtTerminal`.

## `test/presenter_fuzz_test.dart`, inline group

~17,500 random frames in a region of a normal screen
(`package:twk_test/vt.dart` with a scrollback) below printed history; the
region grows, shrinks, and the terminal is resized keeping what it shows
(rows cut or padded, the screen scrolling its top into the scrollback or
taking lines back from it); rows are committed to the history (more than the
screen holds, with the screen height known or not); 4 configurations.

What it catches: a write to the history (the emulator guards it, committed
lines too), any absolute row (`CUP`, `DECSTBM`, `ED 2`), the region not
found again after a resize, rows below the region left non-blank, committed
rows not as they were drawn (styles, wide glyphs, links) or out of order,
plus every check of the fullscreen fuzz.

## `test/inline/`

`TwkApp` in the inline mode against `VtTerminal`
(`package:twk_test/vt_terminal.dart`: frames into the emulator with a
scrollback, below guarded history).

What it catches: the region starting below the history (on the next line
after text), growing with its content and pushing the history into the
scrollback, its row limit, shrinking only when asked, the region kept or
erased on exit with the cursor below it or where it began, resizes; commits
not above the region, not wrapped at the width or losing styles and wide
glyphs, a burst of 10,000 committed lines holding input up or written out of
order, a commit before `run` or one waiting at quit lost; an error while
sizing the region not reported to `onError` as the root's or reported more
than once, the region not keeping its height (1 row at first, within the
terminal) or dropping a shrink asked for; a commit that throws not reported
as the commit's in its phase, not replaced by an error block at the width,
or stopping the region and later commits; either without `onError` not
ending `run()`.

## `test/log/`

The log sink, and an app with a stand-in stderr; `TWK_LOG` in a process of
its own; the sink served on a socket to a client spoken by hand.

What it catches: `print` in handlers and timers recorded instead of printed,
`log()` levels, uncaught errors recorded, the ring dropping the oldest,
listeners, warnings and errors on stderr after the restore in order, a log
file that can't be written; in the process: stdout stays empty and the file
gets every record; the sink served on a socket: a record not surviving JSON,
the records kept not sent first or those that come not after them, records
sent once the sink stopped serving, the project's address file not naming
the socket meanwhile, a client without the token served, a newer app's
address file removed; an app in a process of its own
(`test/log/served_app.dart`): its log not served while it runs with
`TWK_DEBUG=logs` or still served after it ends, served without it, a log
that can't be served not a warning on stderr or ending the app.

## `test/unicode/bidi_test.dart`

The bidi properties, `BidiText`, and every case of `BidiTest.txt` and
`BidiCharacterTest.txt`.

What it catches: a level or an order otherwise than UAX #9 resolves it (more
than 700,000 class sequences in each paragraph direction, 91,707 strings).

## `test/render/bidi_paragraph_test.dart`

`RenderParagraph` in logical and visual order, Hebrew and Arabic with Latin
and digits, through the emulator.

What it catches: right-to-left text reordered in logical order, or not in
visual order; brackets not mirrored, `start` and `end` not by the
paragraph's direction, an ellipsis or justification on the wrong side,
`textRangeAt` not the cluster drawn; a new order not laying the tree out
again; work done for text with no right-to-left character.

## `test/render/effect_test.dart`

`RenderEffect` through the emulator.

What it catches: a frame of the effect painting the child or what is under
it, a mark in the child not putting back what was under it, a repaint
boundary inside not shown through the effect, what the parent or a boundary
under it paints anew not shown, two-column glyphs split.

## `test/graphics/`

`Canvas.image` in each protocol through the emulator, which records
placements; the probe; a fuzz of frames with images in both modes; an app in
a pseudo-terminal per protocol (`TWK_GRAPHICS`).

What it catches: an image not sent once, not placed again after a scroll, or
not deleted and freed when drawn over or on leaving the screen; a hardware
scroll over sixel or iTerm2 pixels; the cursor moved by an image; a kitty
chunk over 4096 bytes; an unsynchronized frame with images; a protocol not
found from the answers or the environment; a frame without images writing
other bytes.

## `test/viewport/`

The presenter in a viewport over a patterned screen (a fuzz of 5
placements), and `TwkApp` on `HeadlessTerminal` with one.

What it catches: a cell outside the viewport written, during frames, resizes
or after the end; the cursor not put back, autowrap not on again; `EL`,
`ICH`, `DCH`, `ED 2` or `DECSTBM` where they reach past it; a rectangle not
cut to the screen or not given back; mouse events not relative to it,
outside it not dropped, a held button's release lost; the mouse on the
normal screen without `normalScreenMouse`; on plain output, the frame
placed.

## `test/terminal/plain_test.dart`

The choice of plain output, a plain `Terminal` and an app on it, the demo
with its stdout piped.

What it catches: an escape sequence written to a pipe or in CI; the last
frame not written as text when the app ends, or inline commits not as they
come; `TWK_PLAIN`, `CI` and the rest not read as they should.

## `test/terminal/link_test.dart`

`Terminal.overLink` over a link in memory, and in a process of its own.

What it catches: the probe not answered, keys or resizes lost, modes not put
back at close; bytes other than `Terminal.open` writes over the same link; a
signal of the process taken as a key or a trace written over a link;
`suspend` not refused; state kept or a timer started on plain output.

## `test/terminal/terminal_input_test.dart`

`Terminal.overLink` on what the probe's answers turn on, input that takes a
while, keys typed during the probe, a link failing during it, `notify`.

What it catches: in-band resize or grapheme clusters not turned on and off,
a resize report not the size; the ambiguous width or the inline cursor
column misread; keys typed during the probe lost or out of order; opening
not failing, or the link not put back and closed, when its input fails; a
lone ESC waiting as long as a sequence that started, or a started one cut; a
paste whose end got lost never ending; a notification not numbered for the
process, or written where none shows or once closed.

## `test/platform/`

The platform layer on the VM (`io.dart`) and its web stand-ins (`web.dart`),
loaded on the VM; the own terminal link and termios on a stdin that is no
terminal; a log server's client that sends no line.

What it catches: the process's id, platform or environment not dart:io's; an
own terminal without both stdin and stdout one; plain stdio not sized by
`COLUMNS` and `LINES`; a trace file not emptied or a header failure
swallowed; raw mode not refused without a terminal; a stand-in that reads,
watches or serves something; a client without a token kept.

## `test/terminal/sequences_test.dart`

The pointer shape and the progress; GNU screen's pieces of a sequence passed
on.

What it catches: the sequences, a shape or a progress written where the
environment names no terminal known to show it, or where a version may read
OSC 9 as a notification; a character split between pieces or its UTF-8 bytes
miscounted.

## `test/web/core_app.dart`, run by the root's `test/tool/web_check_test.dart`

`tool/web_check.dart`'s core case: an app on `HeadlessTerminal` and over a
link of its own, built with dart2wasm and run in node.

What it catches: a library of the core reachable on the web importing
dart:io or dart:ffi, or failing when run (skipped without node 22).

## `packages/twk/test/`

The widget layer, by topic.

What it catches: see [how the package is
tested](../../../twk/doc/reference/testing.md).

## `packages/twk_rich/test/`

Rich text, by topic, and images (`test/image/`).

What it catches: see [its README](../../../twk_rich/README.md).

## `packages/twk_test/test/`

The tester, its fake clock, its keys, matchers and finders, the frames it
records, the emulator's passthrough strings.

What it catches: see [its README](../../../twk_test/README.md).

## `packages/twk_dev/test/`

The `twk` command.

What it catches: see [its README](../../../twk_dev/README.md).

## `packages/twk_cli/test/`

The console: its modes, messages, widgets shown, prompts and progress in
each mode, the traceback and `inspect`, its fake terminal.

What it catches: see [its README](../../../twk_cli/README.md).

## `packages/twk_riverpod/test/`, `twk_bloc/test/`, `twk_lints/test/`, `twk_term/test/`, `twk_web/test/`, `gallery/test/`

What it catches: see each package's README.

## The harness

The tests share `test/support/harness.dart`, which wires the core to the
emulator and makes random scenes. The emulator is
`package:twk_test/vt.dart`, and `VtTerminal`
(`package:twk_test/vt_terminal.dart`) an inline `TerminalBackend` that
feeds it: the core, `packages/twk` and `packages/twk_rich` take
[`packages/twk_test`](../../../twk_test/README.md) as a dev dependency by
path, and those of their tests that check what reaches a terminal feed
it to that emulator. The widget layer's tests also run apps with its
tester, `testTwk` (`package:twk_test/twk_test.dart`): `runApp`'s binding
on a `HeadlessTerminal` under a fake clock, input as the bytes a
terminal sends, the screen read back through the emulator.

## End to end

End to end in a real pseudo-terminal: `tool/pty_run.py` runs a program in a
pty (answering the capability probe like a modern terminal, or staying
silent like an old one), types a scripted input (text, Enter, mouse wheel,
arrows, bracketed paste; timed from the program's first output, so a slow
start can't make the tty echo it) and after exit checks the exit status
(`--expect-status`), that the tty is back in cooked mode and every mode
the program turned on is off again: the alternate screen left, the cursor
visible, mouse, paste and focus reports off, the kitty keyboard flags
popped (`--no-kitty` and `--silent`
emulate terminals without the kitty keyboard protocol or without any
answers). `tool/replay.dart --fullscreen` then feeds the captured output into the
same emulator and reports unsupported sequences, wraps and unbalanced DEC
2026. This also covers failures: an exception in paint, in an event handler
or in a timer they started ends the app with that error, but only after the
terminal was restored. pty_run answers every probe in the order of the
output, and a `CSI 6 n` with where the cursor is, which it follows
through the output (text by its width, line breaks, cursor moves,
margins, insertions and deletions, saves and restores, the alternate
screen), so a second app in the same terminal is answered as the first
was. For the inline mode `tool/replay.dart --inline` replays the capture
on a normal screen with a scrollback: it guards what was printed before
the app's probe, rejects absolute rows and checks that the cursor ends
visible on a line below the region (`test/inline/inline_demo.dart` is a
small inline app for it). An app in a fixed viewport is replayed with
`--inline --viewport=LEFT,TOP,WIDTH,HEIGHT` as well: it checks that no
cell outside the rectangle changed and that the cursor was put back where
it was (`test/viewport/fixed_demo.dart`, 10,3,36,7).
`pty_run.py --suspended MARKER` checks an app that hands the terminal
over (`test/terminal/suspend_app.dart` runs `sh -c '… read x …'`): when
the other program prints the marker the tty must be in cooked mode and
every mode off, after it raw again with every mode back on; input timed
`@t` is typed that long after the marker and `--resize` resizes the
terminal; `tool/replay.dart --fullscreen` leaves out what the other program
printed meanwhile. The app itself fails when it drew
nothing after taking the terminal back (dart:io's blocking read) or
missed a resize.
Input can wait for what the program writes instead of for a time guessed
to be long enough: each `pty_run.py --when TEXT` (Python escapes, as
often as wanted, in order) is the first time TEXT appears in the output
after the `--when` before it appeared, and an input, a resize or a scheme
switch timed `#N` is due once the Nth one appeared (`#N+t`: t seconds
after it), however long the program takes; a text that never appears
fails the run (`--when 'typed:' --when hi --input '#1:hi,#2:q'`). A
resize due with input is done first.
`pty_run.py --scheme T:light` (or `dark`, as often as wanted) is a
terminal with mode 2031: at time T, once the app turned the mode on, it
switches its color scheme (dark at first) to that one, reports it
(`CSI ? 997 ; 1|2 n`) and answers the default colors asked for after it
(OSC 10/11) with the new scheme's; a switch that never happened fails
the run
(`packages/twk/test/binding/color_scheme_app.dart` is an app for it).
`tool/replay.dart --trace` takes an output trace (`TWK_TRACE_OUTPUT`)
instead of a capture, its size from the trace unless given, each write a
frame: `--step` prints the screen after each under `=== frame N/TOTAL at
T µs, B bytes ===`, `--frame=N` the screen after frame N (from 1) and the
problems found up to it. A trace replays to the screen the capture of the
same run does.

## Analysis

`dart analyze` (rules: `pro_lints/recommended`, strict casts, inference and
raw types) must report no issues, `dart test` must pass and `dart format`
must change nothing, here as in every package of the repository: the checks
are the repository's (`xtask.yaml` at the root, run by `dart run
tool/xtask.dart handover`; [its README](../../../../README.md) and
`CONTRIBUTING.md` say what they are). `dart run tool/web_check.dart`
([§1.7](terminal.md)) builds the core, packages/twk and packages/twk_web for
the web and runs them.
