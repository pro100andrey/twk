# twk reference: `binding`

[The reference](README.md) · `lib/src/binding/`, `test/binding/`

`runApp`, which runs a tree as an app until it quits, full screen or inline
(`ScreenMode`), on the process's terminal (opened with the mouse off) or a
given one, or with `viewport: Viewport.fixed(left, top, width, height)` in
that rectangle of the screen alone, as the core's `TwkApp(viewport:)`
([§1.13](../../../twk_core/doc/design/viewport.md)), on the normal
screen with `mode: ScreenMode.inline` (beside a shell's output, a status
panel in a corner): the app laid out at its size as full screen, the debug
panels over it, a `Static`'s items in place, the mouse events relative to
it, which the process's terminal then reports on the normal screen too
(`normalScreenMouse`); the `AppBinding` between the tree and the core's
`TwkApp` (`AppBinding.of(context)`), which builds the tree at the start of
each frame (after the frame callbacks due, `scheduleFrameCallback`), in the
app's zone (any number of `setState` calls between two frames make one
build, at most `maxFps` a second, spaced by its `clock`, the `Stopwatch` it
gives `TwkApp`, which a test's fake clock moves), tells the focus nodes
whose focus changed first and settles the focus again after the build when
that moved it (an autofocus, a focused node removed), in the same frame,
unmounts what the frame's builds removed, a `LayoutBuilder`'s in the layout
too, once the frame is written (`TwkApp.run`'s `afterPresent`), in that
frame and asking for no other, their states disposed, mounts the app in the
first frame (input waits for it), puts it under a `TerminalBrightness` (that
of the terminal's background, dark when not known, then that of each
`ColorSchemeReport`, so `Theme.adaptive` switches live) and under the
`rootScope` of its `focusManager` (`focus`), and unmounts it when the app
ends. `notify(title, body)` shows a desktop notification ("the long job
finished") where the terminal is known to show one, as the core's
`Terminal.notify` does
([§1.7](../../../twk_core/doc/design/terminal.md): OSC 99,
777 or 9 as the terminal the environment names takes them, wrapped for tmux
and GNU screen), on a `HeadlessTerminal` writing it to its frames in the
protocol it was given (`pumpWidget(notifications:)` of twk_test), and does
nothing elsewhere. `scheduleFrameCallback(callback, at:)` calls `callback`
once, at the start of the next frame, or with `at` of the first frame at or
after that time on the app's clock, before the frame's build, with the
frame's time (`frameTime`, the clock's as the frame started), the callbacks
due in the order they were scheduled: what they change is built in that
frame, and one scheduled while they are called waits for the next;
`cancelFrameCallback(id)` drops one. One timer waits for the earliest `at`;
while no callback waits and nothing changes, the binding asks for no frame
and starts no timer, and a callback scheduled once the app ended is never
called (the animations' ticks, `animation`). `reassemble()`, what a hot
reload calls (`twk run` of `packages/twk_dev`), has the next frame rebuild
every element, its state kept, lay out and paint every render object again
and write the whole screen again. It gives a key to the debug aids first
(below), then to the focus tree's `keyPath` (`focus`) and a mouse event to
the `Listener`s and `MouseRegion`s a hit test of the last frame finds
(`gestures`), and has the terminal report the mouse only while those mounted
need it, whatever the terminal was opened with (all of it while a tool picks
a node, below);

## `InputListener`

`InputListener` gets what they leave: the keys no focus node handled, the
mouse events no `Listener` took (which a terminal sends only while it
reports the mouse), pastes, focus and resizes, the one mounted last first,
until one takes an event. Tab and Shift+Tab that none takes move the focus,
and Ctrl+C that none takes quits, unless `exitOnCtrlC` is false, and Ctrl+Z
that none takes stops the app for the shell on the process's own terminal
until `fg` (`TwkApp.suspendToShell`), unless `stopOnCtrlZ` is false; on the
whole screen the hidden cursor rests on what has the focus (`restCursor`,
true by default, a move of the cursor a frame that writes: false leaves it
where a frame wrote last);

## `ErrorWidget`

`ErrorWidget`, the white-on-red message (the core's `RenderErrorBox`) shown
in place of what a widget builds when its build threw or a widget below
threw as it was created or updated, the error logged with the widget's path,
once while its builds go on throwing an error of the same type and text; a
render object whose layout or paint throws shows the message in its place,
logged with the path of its widget once while it throws the same one;

## `WidgetError`

`WidgetError`, which an error in an `InputListener`, in a focus node's
`onKeyEvent` or in a callback of a `Listener`, a `MouseRegion` or a
`GestureDetector` (from a timer too) ends the app with: the error and the
path, `Column → InputListener`, then its `source`, which the VM prints above
the stack once the terminal is restored: the lines of the app's own code
around the one the error was thrown at, two on each side, that line marked
with `>` under its file and line, from the first frame of the stack in
neither the SDK, nor twk, nor the pub cache; null where that file cannot be
read (a `package:` URI the program does not resolve, as an AOT build
resolves none; the web; a missing file);

## `Static<T>`

`Static<T>(items:, builder:)`, output that is finished once shown: each item
is built once, when the list first has it, and items are told apart by their
index, so a changed item or a shorter list shows nothing. In the inline mode
an item is built below the `Static`, under the inherited widgets above it,
laid out at the terminal's width as tall as its max intrinsic height there,
written to the terminal's history above the region (`TwkApp.commit`) by the
frame that built it (the next ones after a burst of over 256 rows), in the
order of the items, and then unmounted, its states disposed; the `Static`
takes no room in the region, so `Column(children: [Static(items: messages,
builder: (_, m) => Text(m)), prompt])` keeps only the prompt there. A build
that commits an item also has the region fit what the app shows, even when
that is less than it has (`TwkApp.shrinkRegion`; without a commit it only
grows): what the same build took out of the region, such as the finished
part of an answer that streams in, gives back its rows, which the frame that
writes the item erases in the same update of the screen, the item's rows
taking their place instead of the history scrolling up. In the fullscreen
mode, and outside `runApp`, the items are shown in place, one below another
as in a `Column` whose children stretch to its width, their widgets kept
mounted and not rebuilt when the `Static` is.

## `AppBinding.debug`

`AppBinding.debug`, the app's `DebugAids`, all off by default: the frame
overlay (`overlay`), the log console (`console`, a `ConsoleController` over
the app's log that opens on an error, made when first asked for), the core's
repaint rainbow (`rainbow`) and relayout highlight (`relayout`), each on
from the start when `TWK_DEBUG`, a comma-separated list, names it (a name
neither these nor the core's `frames`, `timeline` and `logs` is turns
nothing on and is said in the log as a warning), and the outline over a
render object (`highlight`): the backgrounds of the cells of it the screen
shows, those an ancestor cuts off left out, blended with blue, its edges'
more, their glyphs and text kept, painted over the app and under the panels
from the next frame on wherever the object is, and null again while it is
out of the tree; and the pick of a node on the screen for a tool (`select`,
full screen only): while it is on, the terminal reports all of the mouse,
none of which the app gets, and the node under the mouse is outlined in
place of `highlight`; a press of the left button picks its cell and ends it,
posting `twk.select` with `x` and `y` on the VM service's `Extension`
stream, the app getting neither that press nor what the mouse does until it
is released, and Escape ends it, posting `x` and `y` null. The app turns
them on and off, or a tool by the service extensions (below), or the debug
keys (`keys`), taken from the start when `TWK_DEBUG` names `keys` or any of
the first four: Ctrl+G, then `o` shows or hides the overlay, `c` opens or
closes the console, `r` turns the rainbow on or off, `l` the relayout
highlight, `f` lists the console's next level and above, `y` copies its
selected record, `s` saves the records it lists to a file in the system's
temporary directory and logs where, `x` clears it (what was logged so far
listed no more, the log keeping it), `h` asks the tool that runs the app
(`twk run`) for a hot reload and `H` (kitty's Shift+h too) for a hot
restart, an event `twk.reload` or `twk.restart` on the VM service's
`Extension` stream, or, while no client listens to it, a warning in the log;
Ctrl+G gives the app a Ctrl+G, and any other key after it is dropped. While
Ctrl+G waits for its key, a line over the bottom row of the screen, or of
the inline region, names it in reverse video and lists these keys and what
each does, as many as fit, in the colors of `ThemeData.terminal`; the next
key takes it away. Drawn as the panels below are, it lays nothing of the app
out again and grows no region; full screen, once it goes only the smallest
repaint boundary under it repaints, none when it went before a frame showed
it. Turned on or off, the rainbow repaints all of the app once, so that it
shows at once on an app that repaints nothing. While the console is open, Up
and Down select the record before or after, Page Up and Page Down scroll a
page, End goes back to the newest, Enter shows the selected record whole
(below), and Escape deselects the record, or closes the console with none
selected; while a record shows whole, Up, Down, Page Up, Page Down, Home and
End move through its lines, Enter on a frame of its stack opens the frame's
file at its line in an editor, and Escape goes back to the list. The editor
is the one `editorCommand(environment, file, line, column)` makes:
`TWK_EDITOR`, a command whose `{file}`, `{line}` and `{column}` are put in
(`code -g {file}:{line}:{column}`, `idea --line {line} {file}`, `nvim
+{line} {file}`), else `VISUAL`, else `EDITOR`, given the file and line as
that editor takes them (`+line file` for vi, Vim, Neovim, nano, Emacs,
micro, Kakoune; `file:line:column` for Helix, Zed, Sublime Text; `-g
file:line:column` for VS Code; `--line line file` for the JetBrains IDEs); a
terminal editor runs in the app's terminal, the app suspended until it ends,
another apart. A frame of no file (the SDK's, a package the program does not
resolve), none of the three set, or an editor that fails or ends badly is
said in the log. These keys go to the aids before the focus nodes and the
`InputListener`s; with `keys` off, none is taken. Ctrl+G is the prefix
because every terminal sends it, one byte without the kitty keyboard
protocol, neither the tty nor the terminal takes it, and few apps bind it
(Emacs' cancel, nano's help); F12 is the terminal's own in some (Guake,
Yakuake, Tilda). The overlay and the console are panels over the app in the
colors of `ThemeData.terminal`: the overlay, 31 × 12, at the top right, the
console, 10 rows, over the bottom of the screen, or in the inline mode below
the app, the region growing by it. Full screen, a panel shown is painted on
its own and one hidden repaints only the smallest repaint boundary of the
app that holds its cells; in the inline mode either lays the region out
again, which shrinks once a panel goes. The overlay takes no mouse events;
the console takes those over it, which the app below gets none of: the wheel
scrolls it (or a record shown whole), a press selects the row's record or
line. The overlay shows each of these numbers of the last frame and their
median over the last 128: the time of its build, layout, paint and present
(the core's `FrameStats`), the bytes written, the cells written and
compared, the rows scrolled, the repaint boundaries marked for paint and the
elements built (`BuildOwner.rebuilds`), and the frames written in the last
second; it shows new numbers at most four times a second and once more a
second after the last frame written, counts each frame the app did anything
in, those it shows them in too, less its own layout, paint, mark and the
bytes and cells of its own presented alone, and turned on before the first
frame shows after it. Off, the aids add nothing to a frame's work. The first
app run in a program not compiled in product mode (none under `dart compile
exe`) registers the VM service extensions `AppBinding.serviceExtensions`,
each answering about the app started last of those running, as
`callServiceExtension(method, parameters)` answers: a JSON object whose
`version` is `serviceExtensionsVersion` (1), or an error whose details are a
JSON object with a `message`, invalid params for a parameter missing or
malformed, an extension error for an id that names no node or while no app
runs. A node of the element or the render tree is named by an id, a positive
int given it the first time an answer names it and kept while it is in the
tree, an element's through its rebuilds: one sequence for both kinds, never
given twice in a run. `ext.twk.tree` gives the element tree (the render tree
with `tree=render`) from its `root`, null before the first frame, and in the
element tree `app`, the element of the app's widget below the binding's own;
each node its `id`, `name` (the type of its widget or render object), `key`,
`properties`, `size` once laid out, `flags` (by `DiagnosticsFlag` name), an
element's `render`, the id of its render object or the nearest below, a
render object's `element`, and `children`. `ext.twk.properties` (`id`) gives
a node without its children; `ext.twk.layout` (`id`) its render object's
`constraints` (null for no limit) and `size` once laid out, its `offset` in
its parent and `global` on the screen (of the inline region);
`ext.twk.select` (`x`, `y`) the deepest element whose render object a hit
test of the last frame finds at a cell, the `path` of ids from the root to
it and the render objects hit (`render`), the deepest first;
`ext.twk.highlight` (`id`, none to clear it) outlines a node's render object
(`highlight`); `ext.twk.flags` gives `overlay`, `console` (open), `rainbow`,
`relayout`, `keys`, `select` and `framesInRow`, and sets those of the first
six passed `true` or `false`, none when a value is wrong (`framesInRow`
cannot be set); `ext.twk.reassemble` reassembles the app; `ext.twk.log`
(`message`, `level`: `debug`, `info` by default, `warning` or `error`;
`error`) adds a record to the app's log, an error opening the console.

## `TerminalProgress`

`TerminalProgress(state: ProgressState.normal, value:, child:)` shows the
program's progress in the terminal's tab or taskbar (the core's OSC 9;4,
[§1.7](../../../twk_core/doc/design/terminal.md)) while it
is in the tree, where the terminal is known to show one: as far as `value`,
from 0 to 1, says, as `state` says (`ProgressState.none`, `normal`, `error`,
`indeterminate`, `paused`; a null value in the normal state shows as
indeterminate). Of several, the one mounted last is shown; once none is, the
progress is taken away, as it is when the app ends or hands the terminal to
another program. It is written when what it shows changes (a state, a value
of another whole percent) and again every `TerminalStatus.progressRefresh`
(10 s), as Ghostty drops a progress it was not told of for 15 s; the child
is laid out as without it.

## `WindowTitle`

`WindowTitle(title:, child:)` sets the title of the terminal's window or tab
while it is in the tree, and again when `title` changes, its control
characters left out: through the core's `Terminal.setTitle`, which gives the
user's title back when the app ends, and on a `HeadlessTerminal` as the
sequence written to its frames. Of several, the one mounted last sets it, so
of nested ones the innermost; once that one goes, the one mounted before it
sets its own again, and once none is, the title stays as it was set until
the app ends. The child is laid out as without it.

## `TerminalStatus.of`

`TerminalStatus.of(context)` is what shows the pointer's shape, the progress
and the title on the app's terminal: `showsPointerShape` says whether a
`MouseRegion`'s `cursor` is shown there, and `title` is the title the app
set, null before a `WindowTitle` was mounted. With `runApp(screenReader:
true)`, by default where `TWK_SCREEN_READER` is `1`, the app is read out as
lines of text (`semantics`). Where the output is no terminal (piped, in CI),
`runApp` runs the app on the core's plain output: no escape sequences, the
last frame written as text when the app ends, an inline app's `Static` items
as they are written
