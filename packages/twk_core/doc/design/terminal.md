# twk_core design: §1.7 Terminal and platforms

[The design](README.md)

## Opening a terminal

`Terminal.open()` (throws `TerminalException` when there is no terminal,
no `twk shell` serves one and the output is not taken as plain text, both
below; a stdin that can't enter raw mode, as `/dev/null`, which dart:io
takes for a terminal, counts as none; if anything fails after raw mode
was entered, the console is restored before the error propagates):
1. SIGINT/SIGTERM handlers first, then raw input (`dart:io`); on Linux and
   macOS terminal-generated signals, flow control and CR→NL translation are
   turned off through termios (`dart:ffi` to libc), so Ctrl+C, Ctrl+\ and
   Ctrl+Z arrive as keys instead of killing or stopping the process with the
   terminal in raw mode, and Ctrl+S doesn't freeze the screen; on
   **Windows**, `dart:ffi` to kernel32 without `package:ffi`:
   `ENABLE_VIRTUAL_TERMINAL_PROCESSING` / `DISABLE_NEWLINE_AUTO_RETURN` for
   output, `ENABLE_VIRTUAL_TERMINAL_INPUT` for input (mouse and keys arrive
   as VT sequences), QuickEdit off, UTF-8 code pages, everything restored on
   exit;
2. **capability probe** in one write, answered in one round trip, on the
   alternate screen inside a synchronized update, where a query the terminal
   doesn't know leaves no trace (Terminal.app prints the last byte of a
   DECRQM and the body of kitty's graphics query): DECRQM
   2026/2027/2048/69/2031 and BDSM's `CSI 8 $ p` (below; not inside GNU
   screen, which prints them), OSC 10/11, the 16 palette entries in one OSC
   4 (`TerminalInfo.palette`, those answered), the kitty keyboard query `CSI
   ? u`, a cell's size in pixels (`CSI 16 t`), the secondary device
   attributes (DA2, `CSI > c`, not on the Linux console, which may take it
   for DA1: by them Terminal.app, `1;95;0`, is known over ssh too, where its
   `TERM_PROGRAM` is not passed on, and a terminal started from it that
   keeps that `TERM_PROGRAM` is not taken for it; not through a multiplexer,
   which answers them itself), kitty's graphics query and the terminal's
   name and version (XTVERSION) where the protocol for images is not given
   and no multiplexer answers in the terminal's place ([§1.14](images.md)),
   the width of East Asian Ambiguous characters (U+2500 drawn at the home
   position, then `CSI 6 n`; in the inline mode `CSI 6 n` asks where the
   cursor is instead, on the normal screen before the queries and again
   after them, a terminal with no alternate screen having the cells of its
   line that showed a query erased, [§1.12](inline.md)), and DA1 as the
   "everyone answered" marker, its attribute 4 saying sixel (1 s timeout →
   conservative defaults; answers that come later are dropped, not passed to
   the app as input);
3. resize: in-band (2048) when available, otherwise SIGWINCH; on Windows
   the size is polled every 100 ms (a cheap console call);
4. alternate screen (or the inline mode, [§1.12](inline.md)), mouse (on the
   alternate screen, or with `TerminalOptions.normalScreenMouse` on the
   normal one too, [§1.13](viewport.md)), paste, focus, kitty keyboard (the
   flags asked for pushed, `CSI > flags u`, after the switch to the
   alternate screen and popped, `CSI < u`, before the switch back: each
   screen keeps a stack of its own, [§1.6](input.md)), color scheme reports
   (where mode 2031 is supported); everything is restored on every exit path
   (including SIGTERM).

## Dark or light

Dark or light: `TerminalInfo.brightness` is light where the luma (Rec.
601) of the background OSC 11 gave is at least half that of white, dark
below, and null without an answer (`Brightness.ofRgb`). Where the
terminal has mode 2031 (`TerminalInfo.colorSchemeReports`) it reports
each change of its color scheme as a `ColorSchemeReport`, after which
`Terminal` asks again for the default colors and palette entries the
probe got: their `ColorReport`s (OSC 4's with its `index`) follow the
report.

## Mouse reports

Mouse reports: `MouseTracking` is how much of the mouse the terminal
reports, each value what the one before reports and more, with SGR
coordinates (mode 1006): `off`, the mouse the terminal's own (its
selection, its wheel); `buttons`, presses, releases and the wheel (mode
1000); `drags`, motion while a button is held too (1002); `motion`, all
motion (1003). `TerminalOptions.mouse` starts a `Terminal` at `drags`,
with `mouseMotion` at `motion`. A `MouseTrackingBackend` (`Terminal`,
`HeadlessTerminal`) switches the reports while it is open
(`mouseTracking`), so an app has on only what it uses: the mode of the
old reports off, then that of the new on, as terminals keep one of them
on at a time and some turn any of them off with the reset of another
(`mouseTrackingSequence(from, to)`); what puts the terminal back,
`suspend()` and `resume()` follow the reports switched to, and a switch
while suspended is written on `resume()`. A switch is ignored on the
normal screen unless `normalScreenMouse` is set, on plain output and
once closed. `HeadlessTerminal` starts with no reports
whatever its options say, and writes each switch to its `frames`.

## Handing the terminal over

Handing the terminal to another program (`$EDITOR`, a pager, a shell) and
taking it back: `Terminal.suspend()` turns every mode off as `close()`
does (the alternate screen left, mouse, paste and focus reports off, the
kitty keyboard flags popped, the cursor shown in the user's shape) and
puts the console back in cooked mode, but only pauses the stdin
subscription: cancelling it would close stdin. Ctrl+C meanwhile is the
other program's (the SIGINT is not turned into a key). `resume()` enters
raw mode and the modes again, resumes input, reports a size changed
meanwhile and, on a terminal that answers queries, asks where the cursor
is (`CSI 6 n`): the inline region starts again on that line when the
cursor is at its start, on the next one otherwise or without an answer.
The answer is also what ends a wait of dart:io, which notes how much
input is waiting while input is paused and, once resumed, reads that
much in a blocking read, even when the other program has read it.
`suspend()` and `resume()` are those of `SuspendableBackend`, which
`TwkApp` drives and `HeadlessTerminal` implements too.
`Terminal.stopForShell()` stops the process the way Ctrl+Z does with
terminal-generated signals on (SIGTSTP to its process group), so the
shell it was started from has the terminal until `fg`; Ctrl+Z itself
arrives as a key.

## Over a local socket: `twk shell`

Over a local socket (`twk shell`): a `Terminal` reads and writes the
process's own stdin and stdout, or the terminal a `twk shell` in another
terminal serves over a local socket (`TerminalShell`), so that an app
started from an IDE under the debugger draws there and a breakpoint
stops the app, not the screen. `Terminal.open()` connects to the shell
of the project the current directory is in (the nearest directory up
holding a `pubspec.yaml`) when stdin or stdout isn't a terminal and the
project's address file `.dart_tool/twk/shell` names a shell that
listens; `Terminal.connect(address)` connects to a given one. The
environment variable `TWK_SHELL` names the shell instead of the address
file, for an app started by a shell of its own (an editor's terminal per
run or debug session): `unix:<path>#<token>` or
`tcp:<host>:<port>#<token>`, the token after the last `#`
(`LocalAddress.toVariable`, `fromVariable`). Set, it is the only shell
looked for: one where nobody listens, or a value of no such form, is a
`TerminalException` (plain output where stdout is no terminal, as with
no shell), the address file not read; empty is unset. Over the
socket the app does what it does on its own terminal — the probe (with
the shell's size, environment and erase character, so colours,
notifications and the multiplexer are those of the shell's terminal),
the modes, the frames, the restore — and `flush()` completes once the
shell has written the bytes. The shell keeps what the app's process
can't: raw mode while an app has the terminal (its input passed on byte
for byte), each change of size (SIGWINCH, polled on Windows; the
terminal's in-band reports pass as input), and the bytes that put the
terminal back, which the app tells it as it sets its modes and title and
empties once it restored the terminal itself: an app that goes away
without that — killed, restarted by the debugger — leaves them to the
shell, which writes them and turns the console back to cooked mode.
Output reaches the terminal a whole frame at a time, so a killed app
leaves no sequence cut short. One app at a time: a newer one takes the
terminal over and the older one is disconnected; an app whose shell
goes away gets a `TerminalException` on `events`, which ends `run()`.
Addresses (`LocalAddress`): a Unix domain socket beside the address file
(in a new temporary directory when that path is longer than 103 bytes),
TCP on 127.0.0.1 on Windows, which has no Unix domain sockets; an
address file holds the address and a token, which a client sends first.
The wire (`lib/src/terminal/socket.dart`): frames of a type byte, a
4-byte big-endian length and the payload.

## Over a link of one's own

Over a link of one's own: a `Terminal` reads and writes a
`TerminalLink` (`lib/src/terminal/link.dart`, which needs no dart:io):
the environment that names the terminal (`TERM`, `COLORTERM`,
`TERM_PROGRAM`), its size and erase character, raw mode entered and put
back (nothing to do where the far end sets its own modes), the input as
a stream that ends with a `TerminalException` when the far end goes
away, `add` and `flush`, the resizes, `restoreWith` (what puts the
terminal back should the process go away without doing so; `twk shell`
writes it) and `close`. The process's stdio and `twk shell`'s socket are
links of the core's; `Terminal.overLink(link, [options])` does over any
other (xterm.js in a web page, `packages/twk_web`) what `Terminal.open()`
does over stdio, the probe, the modes, the input and the restore, except
that it watches none of the process's signals, writes no `TWK_TRACE_*`
traces, and its `suspend()` throws `UnsupportedError`.

## Plain output

Plain output: where the output is no terminal, a `Terminal` writes plain
text (`TerminalInfo.plain`). `TerminalOptions.plain` asks for it (true),
never (false, and `Terminal.open()` throws where it finds no terminal) or
leaves it to the environment (null, the default): plain where it says CI
(`CI`, `CONTINUOUS_INTEGRATION`, `BUILD_NUMBER` or `RUN_ID` set to
anything but empty, `0` or `false`, unless `CI` is `0` or `false`), and
where `Terminal.open()` finds no terminal of its own and no `twk shell`
and stdout is none (a pipe, a file). `TWK_PLAIN` (`1` or `true`, `0` or
`false`) overrides the option. Over a link or a shell's socket only
`plain: true` makes it plain. A plain terminal asks nothing, enters no
raw mode and no modes, and writes nothing of its own (title, clipboard,
notifications, mouse modes, pointer shape, progress); its size is
`COLUMNS` × `LINES`, else 80 × 24, and it reads stdin, in cooked mode,
only where stdin is a terminal. `TwkApp` lays out and paints each frame
but writes none as it comes: when `run()` ends it writes the last frame
as lines of text ended by LF, without styles, a wide glyph once, the
blanks that end each line and the blank rows that end the frame left
out (nothing for an inline app with `clearInlineOnExit`); an inline
app's commits are written as lines of text as they are committed.
`framesInRow` is off there.

## Pointer shape and progress

Pointer shape and progress: `pointerShapeSequence(shape)` (OSC 22, a
`PointerShape` by its CSS name, `arrow` being CSS's `default`; null, the
terminal's own) sets the mouse pointer's shape, and
`progressSequence(state, percent:)` (OSC 9;4, a `ProgressState`: `none`,
`normal`, `error`, `indeterminate`, `paused`; the percent cut to 0–100)
the program's progress in the terminal's tab or taskbar.
`TerminalInfo.pointerShapes` and `progressReports` say where the
environment names a terminal known to show them (kitty, foot, Ghostty,
Konsole 26.04+ and Rio for the pointer; Windows Terminal, ConEmu,
Ghostty, kitty 0.38+, iTerm2 3.6.6+, VTE 0.80+, Konsole 26.04+, mintty,
Rio, Contour and tmux 3.7+ for the progress), never where a version that
reads OSC 9 as a notification may be, and no pointer shape inside tmux
or GNU screen. A `TerminalStateBackend` (`Terminal`, `HeadlessTerminal`)
keeps such state: `setTerminalState(key, sequence, restore, refresh:)`
writes the sequence and keeps what puts it back, written when the
terminal is closed (whatever closes it, SIGTERM and a crash included) or
handed to another program, the sequence again when it is taken back, and
with `refresh` again each time that long passed (Ghostty drops a
progress 15 s after it was last told); `restoreTerminalState(key)` puts
one back. Nothing on plain output.

## Right-to-left text

Right-to-left text: `TerminalInfo.bidi` (a `BidiReordering`) says who puts
it in the order it reads, and `TwkApp` draws text in the order that needs
(`PipelineOwner.textOrder`, [§1.8](render.md)). The app, in visual order:
where the terminal honours BDSM, answering `CSI 8 $ p` with 1 or 2 (VTE and
GNOME Terminal, WezTerm, iTerm2 3.7.5+, mintty), which is put in its
explicit mode (`CSI 8 l`) while it is open and back in its own when it is
closed or handed to another program; where it does no bidi (xterm, kitty,
foot, Alacritty, Ghostty, Contour, Windows Terminal, the Linux console) or
is not known; inside tmux and GNU screen, which pass BDSM on to no terminal;
and on a `HeadlessTerminal`, whose `bidi` is the app's unless it is given
another. The terminal, in logical order, as stored: where it reorders rows
itself with no way to stop it, an answer of 3 or by its name (XTVERSION,
`KONSOLE_VERSION`, `MLTERM`, `TERM_PROGRAM`, `TERM`) Konsole, mlterm,
Terminal.app and PuTTY; and on plain output, whose reader orders each line.
`TerminalOptions(bidi:)` chooses instead, the terminal put in the mode the
choice needs, as `runApp(bidi:)` of `packages/twk` does.

## The web

The web: every use of dart:io and dart:ffi in the core goes through
`lib/src/platform/platform.dart`, which exports `io.dart`, or
`web.dart` where `dart.library.js_interop` is, so the VM, AOT and the
analyzer see the API as it is and a web build gets stand-ins: an empty
environment, no terminal of its own and no signals; `Terminal.open()`,
`Terminal.connect()`, `TerminalShell.start`, `LogSink.serve`, a
`LogSink` writing a file, `Trace.read` and `TraceWriter.open` throw
`UnsupportedError`. `Terminal.overLink` is the terminal there. The build
is dart2wasm's: dart2js compiles the core, but the 64-bit views its
cells are compared through (`Uint64List`, `Int64List`) throw once run.
`dart run tool/web_check.dart`, or with the cases to run (`core`, `twk`,
`twk_web`), builds an app of each with `dart compile wasm`, fails where
a library of the build imports
dart:io, dart:ffi, dart:isolate or dart:mirrors, and runs it in node 22
or later (exit 2, a skip, without one); the root's
`test/tool/web_check_test.dart` runs the core's case, `test/web/core_app.dart`,
in `dart test`.

## Frame loop

Frame loop (`TwkApp`): frames on demand (idle means 0 CPU and 0 bytes), an
FPS cap, and **backpressure** — the next frame doesn't start until the
previous one reached the OS (frames don't pile up on a slow ssh link).
`run(root, onEvent, beforeLayout:, beforePresent:, afterPresent:)`:
`beforeLayout` runs at the start of every frame, in the app's zone, before
the tree is laid out (in the inline mode before the region is sized to the
root), so what it changes in the tree (a widget tree's build) is laid out
and painted by that frame. `beforePresent` runs once the frame is laid out
and painted, just before the screen is written: what it sets of the
presenter goes with that frame (a widget tree puts the hidden cursor on the
focus there). `afterPresent` runs at the end of every frame, in the app's
zone, once the frame's bytes are handed to the terminal (also when it has
none) and before they are flushed: the bytes don't wait on it, nor it on a
slow link, and no input is handled between the paint and it (a widget tree
unmounts there what the frame removed); what it changes in the tree is laid
out and painted by the next frame. Input waits for the first frame: an event
that arrives before it is handled once `beforeLayout` has run. A resize, and
a default color or palette entry the terminal reports (`ColorReport`) other
than the one known, repaint everything; `onEvent` gets them too. An error in
an event handler, in `beforeLayout` or `afterPresent`, in layout/paint (a
commit's too) or while the inline region or a commit is sized (where the
`owner` has no `onError`, [§1.8](render.md), [§1.12](inline.md)), while
writing, or in anything those callbacks scheduled ends `run()` with that
error after the terminal was restored. `suspend(run)` hands the terminal to
another program for as long as `run` takes (`Process.start(…, mode:
ProcessStartMode.inheritStdio)` for an editor or a shell) and returns what
it returns: frames wait, the inline region stays on the screen with the
cursor below it, and taken back the screen is repainted in full, the inline
region from a fresh start below whatever the other program printed.
`suspendToShell()` is that around `Terminal.stopForShell()`, for Ctrl+Z
(POSIX only). On a backend that isn't a `SuspendableBackend` only the frames
wait. Frames are spaced by `TwkApp.clock` (`clock:`), a `Stopwatch` on which
the gap of `maxFps` passes: by default a started one, in a test one its fake
clock moves. `TwkApp.stats` (`FrameStats`) holds the time and bytes of
recent frames (`medianMicros`, the median of the last 128) and, of the last
one, the time of each stage, which add up to its `lastMicros`:
`lastBuildMicros` (what runs before layout, a widget tree's build),
`lastLayoutMicros` (with the sizing of the inline region), `lastPaintMicros`
(with the inline mode's commits) and `lastPresentMicros` (the bytes
encoded); and `lastRepaints`, the repaint boundaries, the root among them,
it repainted because they were marked for paint
(`PipelineOwner.dirtyBoundaries`, read before the paint), on their own or
inside one marked around them.

## Log sink

Log sink: while the app owns the screen, anything written to stdout or
stderr would land in the middle of a frame. So `print` in event handlers,
frames and anything they schedule goes to the app's `LogSink`
(`TwkApp.logs`) through the zone they run in, as do
`log(message, level:, error:, stack:)` and the errors nothing catches
there; nothing global is patched, so `print` elsewhere (in `main` between
awaits) still writes to stdout, and `log()` outside an app prints its
record. The sink keeps the last 1000 records (time, level, text, error,
stack) in a ring that drops the oldest, passes each record to its
listeners as it comes (`addListener`: the widget layer's log console), and
with `TWK_LOG=path` appends each to that file as it comes. Once the
terminal is restored, the warnings and errors in the ring are written to
stderr, oldest first, except the error `run()` ends with, which its caller
gets. A log file that can't be written ends the app like any other error.
SIGTERM restores the terminal and exits without that report (`TWK_LOG`
keeps the records). `serve()` serves the records on a local socket until
`close()`, for `twk logs` (`packages/twk_dev`): a client that sends the
token gets the records kept, then each one as it comes, as lines of JSON
(`LogRecord.toJson`, `fromJson`). The address goes to the project's
address file `.dart_tool/twk/logs`, in place of another app's; the
socket keeps the process alive until `close()`. A `TwkApp` serves its
log so while `run()` runs when `TWK_DEBUG` names `logs` (`serveLogs`),
in the project the current directory is in, and stops when `run()`
ends, so `twk logs` needs no code in the app; a log that can't be
served is a warning in it, and the app runs on. Unasked, an app opens
no socket and writes no address file.

## Byte traces

Byte traces: with `TWK_TRACE_INPUT=path` a `Terminal` records every read
of stdin in that file, with `TWK_TRACE_OUTPUT=path` every write to stdout,
from the capability probe on, each with when it happened (one clock for
both, so answers line up with the queries they answer). A record is
copied into a buffer as it comes, and the buffer goes to the file on a
later turn of the event loop, one write at a time, records piling up
meanwhile: a frame never waits for the file. The traces are complete once
the terminal is closed (on SIGTERM too); a path that can't be written
fails `Terminal.open()` before raw mode. The format
(`lib/src/terminal/trace.dart`): a header line, then one record per read
or write, the length in bytes after the time in µs since the trace began:

```text
twk-trace 1 output 100x30          magic, version, input|output, size at start
1532 412                           µs, bytes
<412 bytes>
```

followed by a line feed that only keeps the next record's line apart when
the file is read as text. `Trace.read(path)` reads one back (`records`, the
bytes of all in a row, `truncated` for a file whose writer never closed it:
the records before the cut are kept). `tool/replay.dart --trace` replays an
output trace frame by frame (see [§2](testing.md)); `Trace.feed(input,
waiting:, timeOut:)` feeds an input trace read by read to a
`HeadlessTerminal` (`term.input`, `term.inputTimeout`, `term.timeOutInput`),
resolving a lone ESC or a pending sequence where the pause before the next
read was long enough for a `Terminal`'s timer to have done so, so a test
sees the events the app saw.

## `TWK_DEBUG`

`TWK_DEBUG`, a comma-separated list, turns on debugging of `TwkApp`:
`frames`, `timeline` and `logs` (each also a constructor argument,
`framesInRow`, `timeline` and `serveLogs`), `rainbow` and `relayout`; the
widget layer's binding reads `overlay`, `console` and `keys` too
([`packages/twk`](../../../twk/doc/reference/README.md)). It is read from
`TwkApp(environment:)`, and where that is not given from the process's
environment, in which the terminal's settings take the place of the
process's values (`TerminalInfo.settings`): `TWK_DEBUG` and
`TWK_SCREEN_READER` (the widget layer's screen-reader mode) as the
environment of the terminal's link sets them, set empty too, on a terminal
of the process's (`Terminal.open`, its own or the `twk shell`'s it found,
and `Terminal.connect`), so that the terminal an app is on (an editor's `twk
shell`, part of the VS Code extension) switches them for any app; none over
`Terminal.overLink`, whose far end (an SSH client, a browser) is not to turn
the app's debug aids on. The rest, `TWK_LOG` and the editor's command among
them, are the process's alone. An environment given is the whole of it: a
test passes `const {}`, and so does twk_ssh's server. `logs` serves the
app's log for `twk logs` while it runs (above); `rainbow` and `relayout`
turn the debug paints of `TwkApp.owner` on from the start
([§1.8](render.md)); `frames` writes each frame in full below the last one
instead of in place, for reading in a log: a line `--- frame 3 (412 bytes)
---` naming it and the bytes it took in place, then its rows as text without
styles, each ending in CR LF, in the inline mode after the rows committed
with it. The frame is still diffed by the presenter, whose bytes are
dropped: only frames that changed something are written. On the alternate
screen the frames scroll by and go with it; in the inline mode they stay in
the scrollback; `TWK_TRACE_OUTPUT` or `pty_run.py --out` keeps them either
way, as text between a few escape sequences. `timeline` puts each frame on
dart:developer's `Timeline` (DevTools' Performance tab) as a slice `Frame`
holding `Build` (`beforeLayout`), `Layout`, `Paint`, `Commit` (inline
commits), `Present` and `Finalize` (`afterPresent`). Off, a frame makes no
`Timeline` call at all: the VM records its Dart stream by default (in an AOT
build too), so each slice would cost some 150 ns whether anyone looks or
not, and there is no public way to ask whether anyone does.

## Headless

Headless, for tests, snapshots and one-off output: `HeadlessTerminal` is a
`TerminalBackend` in memory whose size, capabilities, text mode, ambiguous
width, default colors and kitty keyboard protocol are the caller's; with
`TerminalOptions(alternateScreen: false)` an app runs on it in the inline
mode, the cursor starting in the column `cursorColumn` gives (by default
0, the start of a line). Input goes in as bytes (`input(bytes)`,
`type(text)`) and is decoded by the same `InputParser` as stdin;
`resize(w, h)` reports a new size; every frame written is kept (`frames`),
and `holdFlush` stands for a slow connection. Its
`TerminalInfo.multiplexer` is the `multiplexer` it is given, so what an
app sends through tmux or screen (the clipboard, notifications) comes
wrapped for it, and its `TerminalInfo.notifications` the `notifications`
it is given (by default `none`): `notify(title, body)` writes a desktop
notification to `frames` in that protocol as `Terminal.notify` does, each
under an id of its own from 1, and nothing for `none` or once closed.
With `pointerShapes` and `progressReports` its `TerminalInfo` says the
terminal shows a pointer shape and a progress, and as a
`TerminalStateBackend` it writes what is set and put back to `frames` as
a `Terminal` writes them, with no timer for a refresh. Its
`TerminalCaps` are the `caps` it is given, the protocol for images
(`graphics`) and a cell's size in pixels among them. It
is a
`SuspendableBackend`: from `suspend()` to `resume()` it is `suspended`
and drops input (resizes still arrive), `suspends` counts the handovers,
and nothing is written but, in the inline mode, the line break `resume()`
writes unless `resumeColumn` (where the other program left the cursor)
is 0. It starts no timers: a lone
ESC, or a paste whose end marker was lost, waits for `timeOutInput()`,
which a caller keeping a clock calls once `inputTimeout` has passed — the
pause a `Terminal` would wait (the escape timeout, 500 ms for a started
sequence, the paste timeout).
`renderToString(root, width, height, styles: …)` lays a render tree out at
that size, paints it once and returns its rows as text (without the blanks
that end them, a wide glyph once), or with `ansi: true` the presenter's
bytes for that frame; the tree's pen ids are those of `styles`, where
its `Pen` values are looked up.
