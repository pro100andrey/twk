# twk reference: tests and demos

[The reference](README.md)


`runApp` runs a tree as an app; the layout tests show one without it, the
way `test/layout/view.dart` does: `RootWidget(child: …).attach(buildOwner)`
mounts it, its render object becomes the `PipelineOwner`'s root, and a
frame runs `buildScope()`, `flushLayout`, `flushPaint` and
`finalizeTree()`. `test/framework/layout_builder_test.dart` runs its
frames that way, `finalizeTree()` after the paint as `AppBinding` runs
it: the elements a `LayoutBuilder` removes are unmounted there, in the
frame that laid it out, and a `GlobalKey` it builds on two widgets at
once fails the assert of that `finalizeTree()`; an item of a `ListView`
with an `itemExtent` that it builds, a relayout boundary, shows a change
in the same frame, which leaves no work for the next.
`test/binding/static_test.dart` runs inline apps on `VtTerminal` and
checks the items of a `Static` in the terminal's scrollback, in order,
each built once and unmounted once written, the frame that writes an
item fitting the region to what it shows, the rows of what left it in
the same build taking the item with the history not scrolled, a region
without a commit keeping its rows, and the items in place full screen.
`test/binding/notify_test.dart` checks `AppBinding.notify`: in the
protocol the terminal shows, inside tmux wrapped for it, each under an
id of its own, and nothing where no notification is known to show or on
a terminal of another kind.
`test/binding/frame_callback_test.dart` checks the frame callbacks on the
tester's clock: each called once, before the frame's build, in the order
scheduled, what it changes built in the same frame, one timer for those
that wait for a time, and none once the app ended; `test/animation/`
moves the clock through tickers, controllers, spinners and bars, and
checks their values and frames, two spinners stepping in the same frames
on one timer, and an app whose controller stopped, or whose spinner was
removed, left with no timer. `test/binding/service_extensions_test.dart`
calls the handlers of the service extensions and checks their JSON, the
ids kept through rebuilds, the outline painted, followed, cut off and
cleared, and the pick of a node; that product mode registers nothing;
and, over a real VM service, that `test/binding/inspected_app.dart` run
with `dart run --enable-vm-service --write-service-info` answers
`ext.twk.tree`, and run with `-Ddart.vm.product=true` lists no extension.
`test/binding/hot_reload_test.dart` checks `reassemble` (every element
built again with its state, the whole screen written again, the debug
panels kept, nothing before the first frame), `ext.twk.log`, and the keys
that post `twk.reload` and `twk.restart`, only while the debug keys are
taken, and say in the log that no tool listens.
`test/exports_test.dart` checks that `lib/twk.dart` exports the library of
every topic and that they load; that `lib/` holds besides it only
`hooks.dart` and `provider.dart`, which export their own declarations,
none of them a name `lib/twk.dart` exports; that it exports every core type a public
signature names, or a constructor of a core class it exports takes, but
the render objects of the widgets, the parent data they put on them, the
core's `TwkApp` and what the frame loop makes for the paint (`Presenter`,
`Surface`, `GlyphTable`); and that the sample app, an app
that imports `package:twk/twk.dart` alone, builds every public widget,
names every declaration of the core that `lib/twk.dart` exports and runs
in a viewport of a terminal in memory with no error or warning in its
log. The sample
app is `test/sample_app.dart` and its parts, `test/sample_app/<topic>.dart`
for each topic: a public widget is built in the part of the topic whose
library declares it, which keeps the state the widget needs, and a widget
the app does not build fails the test naming that part (`Gauge: build it
in test/sample_app/data.dart`). `test/sample_app.dart` keeps what the
topics share, lays their rows out and runs the app; it changes when a
topic is added, with a part, as `exports_test.dart`'s `topics` does.
`test/binding/viewport_test.dart` runs apps in a fixed viewport of the
normal screen over a screen that showed a pattern before, which stays
outside it through the frames and the exit, the cursor put back: the app
laid out at the viewport, the debug console over it, a `Static`'s items
in place, a press in the viewport's cells, the screen-reader mode's lines
in it; and in a pseudo-terminal `test/binding/viewport_app.dart`, whose
terminal `runApp` opens reporting the mouse on the normal screen, in the
text order the probe finds or `bidi` asks for.

The demos, from this directory: `dart run example/counter.dart` (a
counter in a rounded box: Up counts, q quits), `dart run
example/static_screen.dart` (a header, two boxes of wrapped text side by
side and a footer; q quits) and `dart run example/interactive.dart` (a
chat: its messages in a `ListView.builder` with `stickToBottom` in a
`Scrollbar`, which follows those the others write every two seconds
while it shows the end; the people beside it in a `SelectionList`, where
Enter mentions a name; a `TextField` below, whose Enter sends and takes
the list to the end with `ListController.ensureIndexVisible`. Tab and
Shift+Tab move the focus from pane to pane and a click gives it to the
pane clicked, a `Listener` around each calling `FocusNode.requestFocus`;
the keys scroll the list that has the focus, the wheel the one under the
mouse, and the scrollbar's thumb drags. F1 shows the keys in place of
the panes, where no `Listener` is mounted, so the terminal reports no
mouse and its own selection works; Ctrl+C quits. Inline, where the mouse
is the terminal's, the chat is in a `SizedBox` 16 rows tall: a list asks
for no rows), each on the alternate screen, or with `--inline` below the
shell's history. Full screen: `dart run example/dashboard.dart`, an operations
dashboard that a timer moves on each second: a header with a `Badge`,
tiles of figures with a `Sparkline` each, a `Chart` of the latency, the
services, an `ActivityHeatmap` of the deploys and a `LogView` that
follows, panels in a `Grid` whose rounded borders merge (a track a cell wide before,
between and after those of the panels, each panel's `Box` spanning the
edge tracks around it with `Border(merge: true)`), the key hints over
the bottom border in a `Stack`, in `Theme.adaptive`'s dark or light
theme as the terminal's background is, switched as the terminal reports
another color scheme. The dashboard turns the debug keys on
(`AppBinding.debug.keys`): Ctrl+G shows them over the bottom row until
the next key, then `o` shows the frame overlay, `r` the repaint rainbow,
`c` the log console. Its heatmap has the focus: the arrows move the
cursor, and Enter shows what was deployed that day in a toast and logs
it, in the log panel and to the console; Tab takes the focus to the log;
q quits. `dart run example/settings.dart`: a `MenuBar` over a `TabBar`
and its tabs of switches, checkboxes and radio buttons, all `FormField`s
of one `Form`, and a `StatusBar` under them. F10, a click or Alt and a
letter opens a menu, a right click on the settings or Shift+F10 a
`ContextMenu`; Tab moves from the tabs to the settings, Left and Right
on the tabs switch them; Space, Enter or a click flips a switch or a box,
the arrows choose a radio button. Ctrl+S saves the form, File ▸ Revert
puts back what was saved. Clearing the cache asks in a dialog first;
confirmed, a `Spinner` turns in the status bar while it is cleared, then
a toast says it is done, and so does a desktop notification
(`AppBinding.notify`) where the terminal shows them. Ctrl+Q quits. `dart
run example/monitor.dart`: a process monitor after btop, the CPU and the
memory as `LineGauge`s under `Sparkline`s of the minutes before, and the
processes in a `Table.source` sorted by the CPU they use. A click on a
title sorts by its column, again the other way, `s` does that for the
column sorted by, `<` and `>` sort by the column before or after it; the
arrows, Page Up, Page Down, Home and End select a process. `t` swaps in
a `TreeView` of the processes under their parents, and back, the
process selected carried across and its ancestors expanded; Left and
Right collapse and expand, `*` expands all below; q quits. It reads
`/proc` once a second on Linux, in an isolate, and makes processes up
elsewhere and with `--synthetic`; at 100 × 30 it writes a frame a
second, about 1.4 KB a second on a real system. `dart run example/files.dart
[directory]`: a file manager after Midnight Commander, the directories
in a `TreeView` beside the entries of one in a `Table` (`../`,
directories first, then by name, size or time), in a `SplitView` with
shared edges under a `MenuBar` and over a `StatusBar` and a
`KeyHintsBar`, a `CommandPalette` on Ctrl+P. F5 copies and F6 moves the
files marked with Space, or the row, into the other pane's directory
after a `Form` dialog that takes the target, then in a dialog with a
`ProgressBar` while a `Ticker` copies 4 MiB a frame (Escape stops it,
the file half copied deleted); a file dragged onto a directory, `../` or
the other pane asks whether to copy or move it. F2 renames and F7 makes
a directory in forms, F9 pushes a settings `PageRoute` that Ctrl+S saves
and Escape leaves; Enter opens a directory, Backspace goes up, Ctrl+R
reads the directories again, Ctrl+Q quits. It copies the bytes, not
permissions or times.

`test/example/` runs each through `testTwk`: the first three full screen
and inline, the dashboard on a dark and on a light terminal, through a
color scheme report and with each debug key, the settings on a terminal
that shows notifications (`pumpWidget(notifications:)`), and the monitor
on its made-up processes under the fake clock, its reader of `/proc` on a
directory laid out as one, and the file manager over a temporary
directory.

The gallery of every widget is a package of its own, `packages/gallery`
(`dart run packages/gallery/bin/gallery.dart` from the repository's
root): a page for each widget of twk, `twk_rich` (its
`package:twk_rich/image.dart` too) and `twk_term`, in a list by group on the left, the one chosen live on the
stage with its options beside it and the Dart that builds it in its Code
tab (its design: `packages/gallery/doc/design.md`). Its
`test/widgets_test.dart` fails for a widget `lib/twk.dart` exports that no page builds: a widget added
gets a `GalleryPage` in `packages/gallery/lib/src/pages/<group>.dart`
(its README, "Adding a page"). End to end, from the repository's root:

```bash
python3 tool/pty_run.py --size 60x12 --input '1:\x1b[A,1.3:\x1b[A,1.6:\x1b[A,2.5:q' \
    --out /tmp/counter.bin -- dart run packages/twk/example/counter.dart
dart run tool/replay.dart --fullscreen /tmp/counter.bin 60 12        # Count: 3

# the chat: a message sent, the wheel, Tab, a click on the field, another
# message, the keys page shown and left, Ctrl+C; then inline below lines
# printed before it
python3 tool/pty_run.py --size 80x24 \
    --input '1.5:hello,1.8:\r,2.2:\x1b[<64;20;5M,2.6:\t,3:\x1b[<0;20;22M,3.05:\x1b[<0;20;22m,3.4:hi,3.6:\r,4:\x1bOP,5:\x1bOP,6:\x03' \
    --out /tmp/interactive.bin -- dart run packages/twk/example/interactive.dart
dart run tool/replay.dart --fullscreen /tmp/interactive.bin 80 24
python3 tool/pty_run.py --size 80x24 --input '6:hi all,6.3:\r,6.6:\t,6.9:\x1b[A,7.3:\x1bOP,8.3:\x1bOP,9:\x03' \
    --out /tmp/inline.bin -- sh -c \
    'printf "history 1\nhistory 2\n"; exec dart run packages/twk/example/interactive.dart --inline'
dart run tool/replay.dart --inline /tmp/inline.bin 80 24

# the dashboard: the overlay, the cursor moved and Enter logged, the
# rainbow and the console, each turned off again; the terminal switches
# to a light color scheme at 4.5 s
python3 tool/pty_run.py --size 80x24 --scheme 4.5:light \
    --input '1:\x07o,2:\x1b[D,2.2:\x1b[D,2.4:\r,2.8:\x07r,3.2:\x1b[A,3.6:\x07c,4.2:\x07c,4.8:\x07r,5.2:\x07o,6:q' \
    --out /tmp/dashboard.bin -- dart run packages/twk/example/dashboard.dart
dart run tool/replay.dart --fullscreen /tmp/dashboard.bin 80 24

# the settings in Konsole's environment, which shows notifications: the
# next tab, a switch flipped, Ctrl+S, the cache cleared from the Tools
# menu, the context menu at the mouse and closed, Ctrl+Q; the output holds
# one OSC 777 notification
KONSOLE_VERSION=260802 python3 tool/pty_run.py --size 100x30 \
    --input '1.5:\x1b[C,1.8:\t,2.1: ,2.4:\x13,2.8:\x1bt,3.1:\r,3.4:\x1b[Z,3.7:\r,6.0:\x1b[<2;31;9M,6.1:\x1b[<2;31;9m,6.5:\x1b[27u,7.0:\x11' \
    --out /tmp/settings.bin -- dart run packages/twk/example/settings.dart
dart run tool/replay.dart --fullscreen /tmp/settings.bin 100 30

# the monitor on this machine's /proc: rows selected, sorted by a click
# and by keys, the tree shown, folded and unfolded, the table again, q
python3 tool/pty_run.py --size 100x30 \
    --input '2:\x1b[B,2.2:\x1b[B,2.4:\x1b[B,3:\x1b[<0;8;8M,3.05:\x1b[<0;8;8m,3.5:>,4:s,4.5:t,5:\x1b[B,5.2:\x1b[D,5.6:\x1b[C,6:*,6.5:t,7:\x1b[A,8:q' \
    --out /tmp/monitor.bin -- dart run packages/twk/example/monitor.dart
dart run tool/replay.dart --fullscreen /tmp/monitor.bin 100 30

# the gallery: two pages down, Ctrl+P to the Calendar, Tab into it, Right
# and Enter, Ctrl+C
python3 tool/pty_run.py --size 100x30 \
    --input '2:\x1b[B,2.3:\x1b[B,2.6:\x10,3:Calendar,3.5:\r,4:\t,4.3:\x1b[C,4.6:\r,5.5:\x03' \
    --out /tmp/gallery.bin -- dart run packages/gallery/bin/gallery.dart
dart run tool/replay.dart --fullscreen /tmp/gallery.bin 100 30

# the file manager over a directory of one's own (/tmp/files): keys
# through both panes, Space twice, F5 confirmed, F9's settings changed
# and saved, the palette's refresh, F7 makes a directory `out`, Ctrl+Q
python3 tool/pty_run.py \
    --input '1.0:\t,1.2:\x1b[B,1.4:\t,1.5:\t,1.7:\x1b[B,1.8:\x1b[B,1.9: ,2.0: ,2.2:\x1b[15~,2.6:\r,3.6:\x1b[20~,4.0: ,4.3:\x13,4.8:\x10,5.0:refr,5.4:\r,5.8:\x1b[18~,6.0:out,6.3:\r,7.0:\x11' \
    --out /tmp/files.bin -- dart run packages/twk/example/files.dart /tmp/files
dart run tool/replay.dart --fullscreen /tmp/files.bin 100 30

# runApp in a fixed viewport of the normal screen, a box of 30 x 5 cells
# from column 10 of row 3: once it is drawn, keys typed and a press in it
# (at 2, 1 of its cells), q once the box shows the press; the rest of the
# screen left as it was (replayed without --inline, which takes the
# viewport's absolute rows for errors)
python3 tool/pty_run.py --when 'pressed nothing' --when 'at 2, 1' \
    --input '#1:ab\x1b[<0;13;5M\x1b[<0;13;5m,#2:q' \
    --out /tmp/viewport.bin -- dart run packages/twk/test/binding/viewport_app.dart
dart run tool/replay.dart /tmp/viewport.bin 100 30
```
