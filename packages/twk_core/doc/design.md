# twk_core: design, testing, limitations

How the core is built and why, how it is tested, what it does not do,
and how its demo, end to end runs and benchmark are run. The package's
[README](../README.md) is the short version.

## What it is

A terminal UI core with no runtime dependencies (only `dart:*`): a packed
cell buffer, a diff driven by damaged spans, a minimal ANSI stream, its own
Unicode segmentation, an input parser, backends for Linux / macOS / Windows,
and a retained render tree, under the Flutter-like widget layer of
[`packages/twk`](../../twk/doc/reference.md), the rich text of
[`packages/twk_rich`](../../twk_rich/README.md) and the console for
command-line tools of [`packages/twk_cli`](../../twk_cli/README.md).

Key properties:

* a frame with no changes costs **0 bytes**; a retained repaint touches only
  the cells that changed, and the presenter compares only damaged spans;
* cells are typed arrays, styles and glyphs are interned, so the hot path
  allocates next to nothing;
* atomic frames (DEC 2026), hardware scrolling (`DECSTBM + SU/SD`, DECSLRM),
  character insert/delete (ICH/DCH), `REP`, `ECH`/`EL`;
* when a terminal disagrees about a character's width, the error **never
  leaves the cells of that glyph**;
* three screen modes: fullscreen on the alternate screen; **inline**, a
  region of the normal screen under the terminal's history that grows with
  its content and never writes above itself (§1.12); and a **fixed
  viewport**, a rectangle of the screen outside which nothing is written
  (§1.13);
* images in reserved cells, placed with kitty graphics, sixel or iTerm2
  as the terminal shows them (§1.14);
* where the output is no terminal (piped, in CI), **plain text**: no
  escape sequences, the last frame written as lines when the app ends
  (§1.7);
* a `Terminal` over any byte link (`TerminalLink`), and a build for the
  web with dart2wasm, where xterm.js is the terminal (§1.7).

This is `packages/twk_core` of the twk repository: the packages built on
it, and the repository's tools and checks, are in [its
README](../../../README.md). Paths here are this package's (`lib/`, `test/`,
`example/`); `tool/…` is the repository root's `tool/` (`../../tool/`) and
`packages/…` a package of the repository, and the commands of §4 run from
the root.

## 1. Design

```
lib/src/
  unicode/        UAX #29 grapheme segmentation + widths, UAX #9
                  bidirectional text (tables from UCD 18.0)
  style.dart      colors, attributes, pens, style interning, SGR transitions
  surface.dart    cell grid + damage tracking + glyph interning
  canvas.dart     drawing: clip/translate, text, fills, glyph runs,
                  lines merged where they meet, images
  graphics.dart   images: the protocols, an encoded image, its placement
  presenter.dart  diff + minimal ANSI stream; images placed
  fill.dart       block fills and comparisons of typed arrays
  input/          input parser (state machine)
  terminal/       the terminal over a byte link: stdio, a terminal served
                  over a local socket (twk shell), plain output, any link
                  of the caller's; termios (libc) and Windows console
                  (kernel32) through dart:ffi
  platform/       dart:io and dart:ffi behind one conditional import,
                  with stand-ins for the web
  render/         retained render tree (Flutter-like): layout, paint,
                  hit testing, boxes, borders, flex, stacks, grids,
                  wraps, paragraphs, scrolling viewports, lazy lists,
                  effects
  app.dart        frame loop: input → layout/paint → present → write
  headless.dart   in-memory terminal backend, render tree → string
  log.dart        log sink: print, log() and uncaught errors while the UI
                  owns the screen; served on a local socket (twk logs)
```

The libraries of `lib/src` are in layers, each importing only its own and
those below it (`test/layers_test.dart` fails on any other edge): unicode ←
draw (cells, styles, the presenter, input; no `dart:io`) ← platform (the
only one with `dart:io` and `dart:ffi`) ← log ← render | terminal, which
don't import each other, ← app. Two public libraries sit on them:
`package:twk_core/twk_core.dart`, the whole core, and
`package:twk_core/terminal.dart`, the terminal without the render tree and
the app, for a logger, a prompt or a command-line tool that writes lines
and reads keys: `Terminal` and what it is opened with and says it is,
`colorModeFor`, `plainAsked` and `runsInCi`, styles and colours, the
`LineEncoder`, the input parser and its events, widths, the terminal's own
sequences and the log sink. Its names are `twk_core.dart`'s own
declarations, so a program may import both. A program importing it
compiles (`dart compile kernel`, median of seven runs) in 0.40 s to a
9.7 MB kernel, against 0.57 s and 11.2 MB for `twk_core.dart` and 0.26 s
and 8.6 MB for a program importing nothing.

### 1.1 A cell is two 32-bit words

`cells[i] = glyph | flags`, `styles[i] = style id` (two `Uint32List`s).
The glyph id **is the code point** for single-code-point characters (ASCII,
Cyrillic, CJK, box drawing — no tables, no allocation); larger ids are
interned multi-code-point graphemes (emoji ZWJ sequences, flags, combining
marks). All values are < 2²⁹, so they are Smis on every VM configuration.
Comparing a cell is two integer comparisons (the diff compares two cells at
a time through a 64-bit view); fills and scrolls are block copies with
`setRange` (§1.9).

### 1.2 Styles and pens

Applications paint with **pens** (`Pen`): a `null` color inherits from the
cell underneath, alpha < 255 blends over the background (like Flutter text
over a background). Composition results are cached in a hash table over
typed arrays (`(style, pen) → style`); an opaque pen bypasses it entirely.
The SGR sequence of every style and the **shortest transition between two
styles** (an attribute delta that accounts for the shared `22` reset of
bold/dim, or `0;…` when shorter) are computed once and cached. Colors are
downgraded to what the terminal supports (truecolor → 256 → 16; macOS
Terminal.app has no truecolor). The terminal's default background and
text colors come from OSC 11 and OSC 10, so alpha over "default" blends
with the real colors (default-colored text with alpha stays default while
the text color is unknown). Its first 16 palette entries come from OSC 4,
so a blend with a palette color (`Color.blue` and kin: a tint, a gradient
between two of them) goes through the color the terminal shows, not
xterm's (`StyleTable.paletteRgb`, `setPaletteRgb`; an entry the terminal
didn't tell stays xterm's, and SGR still names the index; `rgbOf(color,
text:)` any color as the RGB it shows, the default ones as told or null). When the
terminal reports new ones (after a change of its color scheme, §1.7),
`TwkApp` blends with those and repaints everything.

### 1.3 Damage without help from widgets

Every canvas primitive extends the dirty span of the rows it writes, and the
presenter compares only those spans. The widget layer never has to compute
damage rectangles, so it can't get them wrong (hand-computed damage is a
common source of stale cells). `Surface.scrollRows` moves rows **together
with their damage** and records the move; the presenter replays it in
hardware and compares only the exposed rows.

### 1.4 Presenter (diff → bytes)

* cursor model: picks the shortest of `CUP`, `CHA`, `CUF/CUB`, `CUD/CUU`,
  `CR`; adjacent cells are written without moves; short gaps in the same
  style are rewritten instead of skipped;
* a parameter equal to its default is left out: a count of 1 (`CUU`,
  `CUD`, `CUF`, `CUB`, `ICH`, `DCH`, `IL`, `DL`, `SU`, `SD` as `CSI A` and
  the like), column 1 of `CUP` (`CSI y H`, `CSI H`), and SGR 0 (`CSI m`);
* a visible cursor is hidden while a frame draws and shown again at its
  end; a frame that only moves it leaves it shown (it jumps once, so
  hiding it would prevent no flicker); on the whole screen a hidden one
  is put at `cursorX`, `cursorY` too, where the frame left it elsewhere,
  not where it wrote last: a terminal that marks the cursor's row
  (iTerm2's cursor guide) or follows it (macOS zoom) keeps still, and an
  idle frame still writes nothing (an inline region and a fixed viewport
  leave it as they need it);
* SGR only on a style change; blanks compare by how they look (background,
  attributes visible on a space and the colour of lines drawn on it), so a
  space inside text doesn't toggle SGR; a blank that needs an SGR change
  anyway takes the style of the text written right after it when a blank
  looks the same in both, so that text needs no SGR of its own;
* long blank runs use `ECH`/`EL` (BCE-aware: without BCE, erasing is used
  only for the default background);
* hardware scrolling with `DECSTBM + SU/SD` for recorded moves, declared
  scrolls (`scrollRegion`) and auto-detected ones (row hashes; a hash
  collision costs bytes, never correctness, because the diff runs against
  the shifted model). Recorded moves are replayed in order, each checked
  against the state the previous ones left. **SGR is reset before SU**
  (otherwise the exposed rows would be filled with a stray background);
* frames are wrapped in `DEC 2026`; autowrap is off (`DECAWM`), so no width
  error can wrap text into the next row or scroll the screen; a change
  within one row (≤ 64 bytes) is not wrapped — it can't tear, and the
  wrapper would cost 16 bytes;
* a full frame (the first one, after a resize or `invalidate()`) with
  `DEC 2026`: the most common blank style is painted with one `ED 2`
  (BCE), then only the other cells are written — no flash, because the
  frame is atomic;
* `REP` (`CSI n b`) for runs of one character (box lines `────`) — only for
  single code points and only on terminals known to support it (kitty,
  foot, alacritty, Ghostty, WezTerm, Windows Terminal, xterm, VTE ≥ 0.62);
* scroll detection first checks cheaply whether at least 3 rows changed
  (otherwise a scroll can't pay off and no hashes are computed); the diff
  reuses the result of that check, and the row hashes of the screen are
  cached between frames (tests verify the cache against a recomputation
  with `assert`);
* a frame with no changes is **0 bytes**.

### 1.5 Unicode and uncertain widths

Almost every "ghost character" in a TUI comes from the application and the
terminal **disagreeing about a character's width**, which no diff can fix.
Therefore:

* segmentation is an own implementation of UAX #29 (Unicode 18.0,
  including GB9c for Indic scripts) and **passes every official
  `GraphemeBreakTest.txt` case**; the tables are generated by
  `tool/gen_unicode.dart` from the UCD;
* two modes: `graphemes` (cluster = cell; Ghostty, WezTerm, kitty, Windows
  Terminal, mode 2027) and `legacy` (wcwidth: xterm, VTE, Konsole,
  Alacritty, Terminal.app, conhost); the mode is chosen from the terminal's
  answer (DECRQM 2027) and the environment; the ambiguous width (1, or 2
  in some CJK setups) is measured by the probe (§1.7);
* glyphs whose width terminals disagree on (emoji, VS16, ZWJ, flags,
  clusters of several wide code points) are flagged `kUncertain`. After
  such a glyph the cursor column is treated as unknown (the next cell is
  positioned explicitly); a wide one is preceded by `ECH 2` (covers a narrow
  rendering) and followed by a rewrite of the cells it could overflow into
  when rendered wider (up to the sum of its code points' widths). Result
  (tested against an emulated terminal that disagrees): **a width error
  never leaves the glyph's own cells and leaves no debris**.

Edge cases this covers:

* a lone surrogate in a Dart (UTF-16) string is treated as a control: it
  never joins a following Extend and is never drawn;
* a cluster without a base (e.g. a virama whose consonant was deleted)
  would be joined by a terminal to the cell on its *left*: in grapheme mode
  such leading marks are not drawn (in legacy mode a width-1 spacing mark is
  an ordinary cell);
* two cells drawn separately can be joined by a grapheme-clustering
  terminal when the first ends with a virama, an emoji ZWJ, a Prepend, a
  Hangul L jamo, or is a lone regional indicator: such a cell is flagged and
  the next one is written after explicit positioning (`test/join_test.dart`
  has one test per UAX #29 rule).

Bidirectional text is an own implementation of UAX #9 (revision 52,
Unicode 18.0: rules P1 to L2, and L4's mirroring): `BidiText(text,
direction:)` splits the text into paragraphs (`paragraphs`,
`paragraphAt`, each a `BidiParagraph` with its `level` and `direction`,
by its first strong character unless `direction` is given) and resolves
a level for each UTF-16 unit (`levels`; `isLeftToRight` where nothing is
right-to-left, with no work done); for a line, `lineLevels(start, end)`,
`visualRuns(start, end)`, the `BidiRun`s in the order they are drawn,
and `visual(start, end)`, the line as drawn, right-to-left runs reversed
by grapheme and their characters mirrored (`bidiMirror`). The tables
(Bidi_Class, Bidi_Mirroring_Glyph, Bidi_Paired_Bracket, `bidiClassOf`)
are `lib/src/unicode/bidi_data.g.dart`, written by `tool/gen_unicode.dart`
from the UCD. It passes every case of the official `BidiTest.txt` and
`BidiCharacterTest.txt`, which `test/unicode/bidi_test.dart` downloads
from unicode.org into `.dart_tool/ucd/<version>/` on its first run (7.6
and 6.6 MB; offline without them, those two tests are skipped). Lines of
a `RenderParagraph` are drawn in that order where the owner says so
(§1.8).

### 1.6 Input

A real state machine: a sequence may be split at any byte and several may
arrive in one read. With the kitty keyboard protocol (detected by the probe)
the Escape key arrives as `CSI 27 u`, so a sequence split across reads —
common over slow ssh — is never mistaken for Escape; without it a lone ESC
counts as Escape after 30 ms, while a sequence whose parameters already
arrived gets 500 ms, so a slow link can't turn its tail into typed text. An
ESC inside an unterminated OSC/DCS string aborts it, as in a terminal's own
parser, so a truncated reply can't swallow the input that follows. The ESC
timeout never cuts a bracketed paste: it ends with its end marker, or, when
no input arrives for 2 s (`pasteTimeout`), the marker is taken as lost and
the paste is delivered, so later keys aren't pasted text forever. Modified
keys, F1–F12, the kitty keyboard protocol (`CSI u`, press/repeat/release),
SGR mouse (including the wheel with modifiers), bracketed paste, focus,
query replies (DECRPM, DA1, OSC 10/11, CPR), in-band resize (mode 2048),
color scheme reports (mode 2031: `ColorSchemeReport`, `CSI ? 997 ; 1 n`
dark, `; 2 n` light).
Backspace and Ctrl+Backspace follow the tty's erase character (DEL, or ^H on
some setups). Text is grouped by grapheme. A key arrives as a `KeyEvent`
whose `code` is a `KeyCode`: `KeyCode.char` for
text, the grapheme in `char`, or the key it is — `enter`, `up`, `f5` —
with its `modifiers` and `kind`. `Key` is left to the widgets' keys.

`TerminalOptions.kittyKeyboardFlags` asks for more of the kitty keyboard
protocol: a sum of `KittyKeyboardFlags` bits, its progressive
enhancements. Disambiguation (1) is always among them, and by default it
is the only one, so keys come as presses only.
`TerminalInfo.kittyKeyboardFlags` tells what was pushed (0 without the
protocol). The others:

* `eventTypes` (2): keys come repeated and released too, as the key's
  `kind` (`CSI 97 ; 1:3 u`, `CSI 1 ; 1:3 A`: `:2` a repeat, `:3` a
  release). A key that types text repeats as its text again. Enter, Tab
  and Backspace are released unreported unless `allKeysAsEscapes`.
* `alternateKeys` (4): a key comes with the key Shift makes of it. The
  base layout key it also carries is not decoded.
* `allKeysAsEscapes` (8): every key comes as a sequence, modifier keys
  alone too (no `KeyEvent` for those).
* `associatedText` (16): with `allKeysAsEscapes`, a key comes with the
  text it types.

Under any of them a key that types text (no modifier but Shift) is still
the text it types, with no modifiers, as without the flags. That text is
the associated text where the key carries it, else, with Shift, the
shifted key of `alternateKeys`; where neither tells it, the key is its
unshifted key with Shift. A shortcut (Ctrl, Alt, Super) is its unshifted
key, its modifiers kept. With `eventTypes`,
what acts on keys must act on presses and repeats and leave releases
alone, or a field types each letter twice. `twk`'s widgets do: a
`TextField` types, deletes, moves and submits on no release, and
`KeyCombo.accepts`, `Shortcuts` and the binding's Tab and Ctrl+C take
none.

### 1.7 Terminal and platforms

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
2. **capability probe** in one batch: DECRQM 2026/2027/2048/69/2031 and
   BDSM's `CSI 8 $ p` (below), OSC 10/11, the 16 palette entries in one
   OSC 4 (`TerminalInfo.palette`, those answered), the kitty keyboard query
   `CSI ? u`, a cell's size in pixels (`CSI 16 t`), kitty's graphics
   query and the terminal's name and version (XTVERSION) where the
   protocol for images is not given and no multiplexer answers in the
   terminal's place (§1.14), the width of East Asian Ambiguous characters
   (U+2500 drawn on the alternate screen inside a synchronized update,
   then `CSI 6 n`; in the inline mode `CSI 6 n` asks where the cursor is
   instead, §1.12), and DA1 as the "everyone answered" marker, its
   attribute 4 saying sixel (1 s timeout → conservative defaults;
   answers that come later are dropped, not passed to the app as input);
3. resize: in-band (2048) when available, otherwise SIGWINCH; on Windows
   the size is polled every 100 ms (a cheap console call);
4. alternate screen (or the inline mode, §1.12), mouse (on the alternate
   screen, or with `TerminalOptions.normalScreenMouse` on the normal one
   too, §1.13), paste, focus, kitty keyboard (the flags asked for pushed,
   `CSI > flags u`, after the switch to the alternate screen and popped,
   `CSI < u`, before the switch back: each screen keeps a stack of its
   own, §1.6), color scheme reports (where mode 2031 is supported);
   everything is restored on every exit path (including SIGTERM).

Dark or light: `TerminalInfo.brightness` is light where the luma (Rec.
601) of the background OSC 11 gave is at least half that of white, dark
below, and null without an answer (`Brightness.ofRgb`). Where the
terminal has mode 2031 (`TerminalInfo.colorSchemeReports`) it reports
each change of its color scheme as a `ColorSchemeReport`, after which
`Terminal` asks again for the default colors and palette entries the
probe got: their `ColorReport`s (OSC 4's with its `index`) follow the
report.

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

Right-to-left text: `TerminalInfo.bidi` (a `BidiReordering`) says who
puts it in the order it reads, and `TwkApp` draws text in the order that
needs (`PipelineOwner.textOrder`, §1.8). The app, in visual order: where
the terminal honours BDSM, answering `CSI 8 $ p` with 1 or 2 (VTE and
GNOME Terminal, WezTerm, iTerm2 3.7.5+, mintty), which is put in its
explicit mode (`CSI 8 l`) while it is open and back in its own when it is
closed or handed to another program; where it does no bidi (xterm,
kitty, foot, Alacritty, Ghostty, Contour, Windows Terminal, the Linux
console) or is not known; inside tmux and GNU screen, which pass BDSM on
to no terminal; and on a `HeadlessTerminal`, whose `bidi` is the app's
unless it is given another. The terminal, in logical order, as stored:
where it reorders rows itself with no way to stop it, an answer of 3 or
by its name (XTVERSION, `KONSOLE_VERSION`, `MLTERM`, `TERM_PROGRAM`,
`TERM`) Konsole, mlterm, Terminal.app and PuTTY; and on plain output,
whose reader orders each line. `TerminalOptions(bidi:)` chooses instead,
the terminal put in the mode the choice needs, as `runApp(bidi:)` of
`packages/twk` does.

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

Frame loop (`TwkApp`): frames on demand (idle means 0 CPU and 0 bytes), an
FPS cap, and **backpressure** — the next frame doesn't start until the
previous one reached the OS (frames don't pile up on a slow ssh link).
`run(root, onEvent, beforeLayout:, beforePresent:, afterPresent:)`:
`beforeLayout` runs at the start of every frame, in the app's zone,
before the tree is laid out (in the inline mode before the region is
sized to the root), so what it changes in the tree (a widget tree's
build) is laid out and painted by that frame. `beforePresent` runs once
the frame is laid out and painted, just before the screen is written:
what it sets of the presenter goes with that frame (a widget tree puts
the hidden cursor on the focus there). `afterPresent` runs at the end of every frame, in the app's
zone, once the frame's bytes are handed to the terminal (also when it has
none) and before they are flushed: the bytes don't wait on it, nor it on
a slow link, and no input is handled between the paint and it (a widget
tree unmounts there what the frame removed); what it changes in the tree
is laid out and painted by the next frame. Input waits for the first
frame: an event that arrives before it is handled once `beforeLayout` has
run. A resize, and a default color or palette entry the terminal reports
(`ColorReport`) other than the one known, repaint everything; `onEvent` gets them too. An
error in an event handler, in `beforeLayout` or `afterPresent`, in
layout/paint (a commit's too) or while the inline region or a commit is
sized (where the `owner` has no `onError`, §1.8, §1.12), while writing,
or in anything those callbacks scheduled ends `run()` with that error
after the terminal was restored. `suspend(run)` hands the terminal to
another program for as long as `run` takes (`Process.start(…, mode:
ProcessStartMode.inheritStdio)` for an editor or a shell) and returns
what it returns: frames wait, the inline region stays on the screen with
the cursor below it, and taken back the screen is repainted in full, the
inline region from a fresh start below whatever the other program
printed. `suspendToShell()` is that around `Terminal.stopForShell()`, for
Ctrl+Z (POSIX only). On a backend that isn't a `SuspendableBackend` only
the frames wait.
Frames are spaced by `TwkApp.clock` (`clock:`), a `Stopwatch` on which
the gap of `maxFps` passes: by default a started one, in a test one its
fake clock moves.
`TwkApp.stats` (`FrameStats`) holds the time and bytes of recent frames
(`medianMicros`, the median of the last 128) and, of the last one, the
time of each stage, which add up to its `lastMicros`:
`lastBuildMicros` (what runs before layout, a widget tree's build),
`lastLayoutMicros` (with the sizing of the inline region),
`lastPaintMicros` (with the inline mode's commits) and
`lastPresentMicros` (the bytes encoded); and `lastRepaints`, the repaint
boundaries, the root among them, it repainted because they were marked
for paint (`PipelineOwner.dirtyBoundaries`, read before the paint), on
their own or inside one marked around them.

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
bytes of all in a row, `truncated` for a file whose writer never closed
it: the records before the cut are kept). `tool/replay.dart --trace`
replays an output trace frame by frame (see §2); `Trace.feed(input,
waiting:, timeOut:)` feeds an input trace read by read to a
`HeadlessTerminal` (`term.input`, `term.inputTimeout`,
`term.timeOutInput`), resolving a lone ESC or a pending sequence where the
pause before the next read was long enough for a `Terminal`'s timer to
have done so, so a test sees the events the app saw.

`TWK_DEBUG`, a comma-separated list, turns on debugging of `TwkApp`:
`frames`, `timeline` and `logs` (each also a constructor argument,
`framesInRow`, `timeline` and `serveLogs`), `rainbow` and `relayout`;
the widget layer's binding reads `overlay`, `console` and `keys` too
([`packages/twk`](../../twk/doc/reference.md)). It is read from `TwkApp(environment:)`,
and where that is not given from the process's environment, in which
the terminal's settings take the place of the process's values
(`TerminalInfo.settings`): `TWK_DEBUG` and `TWK_SCREEN_READER` (the
widget layer's screen-reader mode) as the environment of the terminal's
link sets them, set empty too, on a terminal of the process's
(`Terminal.open`, its own or the `twk shell`'s it found, and
`Terminal.connect`), so that the terminal an app is on (an editor's
`twk shell`, part of the VS Code extension) switches them for any app;
none over `Terminal.overLink`, whose far end (an SSH client, a browser)
is not to turn the app's debug aids on. The rest, `TWK_LOG` and the
editor's command among them, are the process's alone. An environment
given is the whole of it: a test passes `const {}`, and so does
twk_ssh's server. `logs` serves the app's log
for `twk logs` while it runs (above); `rainbow` and `relayout` turn the
debug paints of `TwkApp.owner` on from the start (§1.8); `frames`
writes each frame in full below the last one instead of in place, for
reading in a log: a line `--- frame 3 (412
bytes) ---` naming it and the bytes it took in place, then its rows as
text without styles, each ending in CR LF, in the inline mode after the rows committed with it. The frame
is still diffed by the presenter, whose bytes are dropped: only frames
that changed something are written. On the alternate screen the frames
scroll by and go with it; in the inline mode they stay in the scrollback;
`TWK_TRACE_OUTPUT` or `pty_run.py --out` keeps them either way, as text
between a few escape sequences. `timeline` puts each frame on
dart:developer's `Timeline` (DevTools' Performance tab) as a slice
`Frame` holding `Build` (`beforeLayout`), `Layout`, `Paint`, `Commit`
(inline commits), `Present` and `Finalize` (`afterPresent`). Off, a
frame makes no `Timeline` call at all: the VM records its Dart stream by
default (in an AOT build too), so each slice would cost some 150 ns
whether anyone looks or not, and there is no public way to ask whether
anyone does.

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
sequence or with the kitty protocol, the paste timeout).
`renderToString(root, width, height, styles: …)` lays a render tree out at
that size, paints it once and returns its rows as text (without the blanks
that end them, a wide glyph once), or with `ansi: true` the presenter's
bytes for that frame; the tree's pen ids are those of `styles`, where
its `Pen` values are looked up.

### 1.8 Flutter-like layer

`render/render.dart` is a retained render tree, one library in part
files by topic beside it (`object.dart`, the render object and what it
is made of; `pipeline.dart`, the `PipelineOwner`; `boxes.dart`,
`decoration.dart`, `flex.dart`, `stack.dart`, `grid.dart`, `wrap.dart`,
`text.dart`, `log.dart`, `viewport.dart`, `list.dart`, `effect.dart`,
`error_box.dart`, `debug_paint.dart`), so that its private names reach
across them. The
widget layer of
[`packages/twk`](../../twk/doc/reference.md) sits on it as Flutter's does:
elements create these objects and set their properties, and widgets know
nothing about diffs, bytes or terminals.

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
* the order of the text: the owner's `textOrder` (`TextOrder.logical`
  until set; setting it lays the tree out and paints it again), which
  `TwkApp` sets as the terminal needs (`TerminalInfo.bidi`, §1.7). In
  `logical` order a line is drawn as stored, every paragraph left to
  right, for a terminal that reorders right-to-left text itself. In
  `visual` order, for one that doesn't, each line, broken as stored, is
  drawn as UAX #9 orders it (§1.5): its right-to-left runs reversed by
  grapheme, the clusters a legacy-mode grapheme is drawn in kept in
  order, single-code-point glyphs at an odd level mirrored (`(` drawn as
  `)`), an ellipsis at the lower level beside it, a right-to-left line
  justified from the right. Text without right-to-left characters pays a
  scan per change in visual order and nothing in logical order;
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

An object may change what is below it while it is laid out (the widget
layer's `LayoutBuilder` builds its child there, for its constraints):
`invokeLayoutCallback(callback)`, called in its `performLayout` before it
lays its children out, runs a callback that may adopt, replace and drop
children of the object and of those below it. The marks that makes stop
at the object, or at the relayout boundaries below it (the items of a
`RenderList` with an `itemExtent`, the list itself), which `flushLayout`
lays out after it in the same flush: what changed is laid out before
anything is painted, leaving no layout for the next frame. When an intrinsic size the object
answered before comes out different afterwards, its parent may have laid
it out by the old answer: the parent is laid out again on the next frame,
or the object itself when it is the root (an inline region is sized by
the root's max intrinsic height, §1.12). A parent that asked for no
intrinsic size is not.

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

Debug paints, flags of a `PipelineOwner` (an app's `TwkApp.owner`), off
by default (on from the start where `TWK_DEBUG` names `rainbow` or
`relayout`, §1.7), when they cost a frame nothing measurable: with
`debugRepaintRainbow` each repaint of a repaint boundary, or of the
root on its own, blends the next of 12 hues over the background of the
cells it covered (its bounds, cut where its ancestors cut it), keeping
their glyphs, text colours and attributes, so an area that changes
colour repainted and one that keeps it did not. With `debugRelayoutHighlight` each repaint outlines the
objects in it laid out since the last one: the backgrounds of the cells
along their edges, in one tint per frame that lays anything out, the
next of a cycle; an outline stays until its cells repaint. Turning
either on or off repaints everything; while one is on, a boundary
repaints all of its cells (a `RenderLog` doesn't scroll in hardware),
so frames cost many more bytes. In 16 colours a tint may round away.

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
region and committing throw (§1.12).
`RenderErrorBox` is that block on its own: a message broken between
words, as wide as its longest line and as tall as its lines, within its
constraints.

### 1.9 Fills: `setRange` instead of `fillRange`

`fillRange` on Dart typed lists is an element-by-element loop, while
`setRange` within one list is a `memmove`. `lib/src/fill.dart` fills 16
elements and doubles the block with `setRange`. Whole rows are filled as one
block (not row by row), and runs of equal styles are found by scanning
64-bit words.

### 1.10 Text fast paths

* a run of printable ASCII is written in one tight loop (style from a
  micro-cache, damage once per run); the last character of the run goes to
  the full segmenter when a combining mark follows it;
* a single BMP character (box drawing, Cyrillic, CJK) skips the UAX #29
  machine when its own rules say it can't join a neighbour: `GCB=Other` and
  the next code point is not Extend/ZWJ/SpacingMark (in legacy mode: the
  next one is not zero-width); the canvas reference test runs in both
  modes and compares against the full segmenter.

### 1.11 Techniques for components

What text fields, lists, panels and chat views need:

| technique | what it does | how it is tested |
|---|---|---|
| **ICH / DCH** (insert/delete characters, VT102) | typing or deleting in the middle of a line shifts the tail on the terminal with one command; the presenter detects the shift itself and compares its cost with a rewrite | typing in the middle of a 160-column line costs 5 bytes instead of 132; the emulator models ICH/DCH strictly (splitting a wide glyph is an error); Konsole's lines are as long as what was written on them: its ICH inserts blanks in the default background, not the current one, and its DCH appends its blanks, in the current colours, at the line's length — mid-row on a short line — so there (`TerminalCaps.konsoleLines`, from XTVERSION or `KONSOLE_VERSION`, never inside a multiplexer) the presenter shifts a row only with the default SGR, which comes out right on a terminal wrongly taken for Konsole too, as the emulator's Konsole line model (`Vt(konsoleLines: true)`) and an xterm-like one check |
| **several scroll blocks per frame** | auto-detection finds up to 4 disjoint blocks moved by different amounts (two panes stacked vertically) | fuzz frames with ≥ 2 hardware scrolls |
| **rectangle scrolling** (`Surface.scrollRect`) | a list or log narrower than the screen (side panel, bordered box) moves without a repaint; in hardware with DECSLRM margins on terminals with DECLRMM (DECRQM `?69`); elsewhere, and in the inline mode, as whole rows (`DECSTBM`) where that is estimated to write fewer bytes than the cells inside would, the cells beside the rectangle that the shift left different written again (`PresentStats.widenedScrollOps`; never over an image or a wide glyph the rectangle's edge cuts, nor in a fixed viewport that does not span the screen's rows), otherwise by a plain diff; the surface marks only the rows the move brought in, and the damage inside moves with the cells | a dedicated fuzz configuration, and every configuration without margins widens scrolls; wide glyphs on the edges are broken up front |
| **cursor shape** (DECSCUSR) | `Presenter.cursorShape` — a bar in a text field; the user's cursor is restored on exit | cursor position, visibility and shape are checked after every fuzz frame |
| **hyperlinks** (OSC 8) | `Pen(link: 'https://…')`; the link is part of the interned style, but its terminal state is tracked separately (SGR 0 doesn't close it); erased cells lose their link, so erase is used only for styles without one | the emulator stores the link per cell; compared in the fuzz and canvas reference tests |
| **clipboard** (OSC 52) and **title** | `Terminal.copyToClipboard`, `Terminal.setTitle` (a `WindowBackend`'s, see below; the user's title is pushed and restored); the raw strings are `clipboardSequence`, `titleSequence`. The clipboard is wrapped for tmux or screen (`TerminalInfo.multiplexer`, `clipboardSequence(text, multiplexer:)`), as notifications are (below), and inside tmux also sent as it is, first: tmux takes that one itself with `set-clipboard on` (keeping a paste buffer too) and drops it by default, while the wrapped one needs `allow-passthrough on`; a tmux inside another hands the outer one plain OSC 52 | `test/sequences_test.dart` (control characters can't escape the title; the clipboard's bytes per multiplexer), `test/terminal/notify_test.dart` (`Terminal.copyToClipboard` in a pseudo-terminal inside tmux, inside screen and outside both) |
| **desktop notifications** (OSC 9, 777, 99) | `Terminal.notify(title, body)` (a `WindowBackend`'s), for "the long job finished": the sequence the terminal is known to show (`TerminalInfo.notifications`, see below), wrapped for tmux or screen (`TerminalInfo.multiplexer`), nothing elsewhere; control characters removed, the title cut to 256 bytes and the body to 1024 between graphemes; the raw strings are `notifySequence` and `passthroughSequence` | `test/sequences_test.dart` (the bytes per protocol and multiplexer, control characters, the cut), `test/terminal_test.dart` (the terminal from the environment), `test/terminal/notify_test.dart` (`Terminal.notify` in a pseudo-terminal) |

Desktop notifications go to a terminal the environment names: its own
`TERM`, then `TERM_PROGRAM`, then the variables terminals set for their
programs, which programs inside tmux or screen inherit. Inside tmux the
sequence goes in `DCS tmux; … ST` (every ESC doubled), which tmux passes
on with `allow-passthrough on` (tmux 3.3+); inside GNU screen in `DCS …
ST` pieces of at most 252 bytes, the OSCs ended by BEL.

| terminal | known by | sent |
|---|---|---|
| kitty | `TERM=xterm-kitty`, `KITTY_WINDOW_ID` | OSC 99: the title, then the body under the same id (`pid.n`, so another notification doesn't replace it); a body with line breaks keeps them, in base64 (`e=1`) |
| iTerm2 | `TERM_PROGRAM=iTerm.app`, `ITERM_SESSION_ID`, `LC_TERMINAL=iTerm2` (passed on by ssh) | OSC 9: `title: body` |
| WezTerm | `TERM_PROGRAM=WezTerm`, `WEZTERM_PANE` | OSC 777 `notify;title;body` |
| Ghostty | `TERM=xterm-ghostty`, `TERM_PROGRAM=ghostty`, `GHOSTTY_RESOURCES_DIR` | OSC 777 (its OSC 9 reads a body like `4;…` as a ConEmu command) |
| foot | `TERM=foot…` | OSC 777 |
| Konsole 22.12+ | `KONSOLE_VERSION` | OSC 777 |
| Windows Terminal | `WT_SESSION` (passed on to WSL) | OSC 777, shown from 1.26, ignored before |
| urxvt | `TERM=rxvt-unicode…` | OSC 777, shown by a `notify` perl extension where one is installed |
| VTE 0.52+ (GNOME Terminal, Tilix, Ptyxis) | `VTE_VERSION` | OSC 777, shown where the distribution patched VTE for it (Fedora); upstream VTE ignores it |
| Alacritty, xterm, Terminal.app, any other `TERM_PROGRAM`, `TERM=dumb` | | nothing |

In OSC 777 a `;` would end its field (title or body), so it is sent as
`,`; a body without a title is sent as the title. OSC 9 and OSC 777 get
line breaks as spaces.

What a terminal can do beyond drawing and input is an interface of its
own beside `TerminalBackend`, which `Terminal` and `HeadlessTerminal`
implement, and the app asks the backend it runs on for each one:

| interface | what it does | on a backend without it |
|---|---|---|
| `SuspendableBackend` | `suspend()`, `resume()`: hands the terminal to another program and takes it back (`TwkApp.suspend`) | only the frames wait |
| `MouseTrackingBackend` | `mouseTracking`: switches the mouse reports to what the app listens to | the reports stay as the terminal opened with them |
| `TerminalStateBackend` | `setTerminalState`, `restoreTerminalState`: the pointer's shape and the progress in the tab, put back on every way out | neither is shown |
| `WindowBackend` | `setTitle`, `notify`: the window's title (twk's `WindowTitle`) and desktop notifications (`AppBinding.notify`) | neither is sent |

A backend that wraps a terminal (to add to its input, as the gallery's
`Typing` does, or to record what is written) implements and passes on
each of these it wants to keep: one that implements only
`TerminalBackend` loses them all, and nothing says so.

### 1.12 Inline mode

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
* what the root's max intrinsic height throws while the region is sized,
  and what a commit's sizing, layout or paint throws, ends `run()` unless
  the `owner` has `onError` (§1.8). Then the region's error is reported
  there as the root's, in `RenderPhase.layout`, once while it is the
  same: the region keeps its height (1 row on the first frame, within its
  limits) and a `shrinkRegion()` waits for a frame that sizes it. A
  commit's is reported once as the commit's, in the phase it threw in
  (sizing as `RenderPhase.layout`), and a `RenderErrorBox` with the
  message, at the terminal's width and as tall as the message there,
  goes to the history in its place. The region and later commits go on;
* when `run()` ends it stays on the screen with the cursor at the start of
  the line below it, or with `clearInlineOnExit` it is erased and the
  cursor is back on its first row;
* the mouse stays the terminal's (`TerminalOptions.mouse` and a switch
  of `mouseTracking` are ignored on the normal screen unless
  `normalScreenMouse` is set, which a fixed viewport, §1.13, wants): its
  wheel scrolls the scrollback and its selection works, and mouse
  reports would give screen rows, which the region doesn't know.

The rest — damage, the diff, SGR, ICH/DCH, REP, DEC 2026 — works as in
the fullscreen mode, in the same presenter (`Presenter.inline`).

### 1.13 Fixed viewport

`TwkApp(terminal, viewport: Viewport.fixed(left, top, width, height))`
lays the tree out at that rectangle and draws it there, on whichever
screen the terminal is on (the normal one with
`TerminalOptions(alternateScreen: false)`): an app beside a shell's output, a status panel in a
corner. Nothing outside the rectangle is written, in the same presenter
(`Presenter(viewport:)`, `Screen(viewport:)`):

* cells are addressed with the offset (`CUP`, `CHA`; `CR` only where the
  viewport starts at the first column); no `ED 2`; `EL`, `ICH` and `DCH`
  only where the viewport ends at the screen's right edge, `ECH`
  elsewhere;
* a scroll stays inside: `DECSTBM` with `SU`/`SD` only where the viewport
  is as wide as the screen, `DECSLRM` margins at its columns where the
  terminal has them, else the rows are written again;
* a glyph terminals may draw wider (`kUncertain`) that could reach past
  its right edge is drawn as blanks;
* each frame turns autowrap off while it draws and on again at its end;
  the first frame saves the cursor (`DECSC`), and each frame that leaves
  it hidden puts it back (`DECRC`), as handing the terminal back
  (`leave`, at the end of `run()` and on `suspend`) does, so the cursor
  of the shell around it stays where it was;
* a resize cuts the rectangle to the screen (down to nothing) and gives
  the part cut off back as the screen grows; the viewport is painted
  again in full on every resize;
* mouse events come in its coordinates, those outside it dropped; drags
  and the release of a button pressed inside it come at the nearest cell
  inside. On the normal screen a `Terminal` reports the mouse only with
  `TerminalOptions(normalScreenMouse: true)` (`HeadlessTerminal` too);
* `commit` throws: the viewport has no history above it; and
  `clearInlineOnExit` is the inline mode's.

On plain output (§1.7) the viewport is laid out at its own size, neither
cut nor placed, and its last frame written as lines like any other.

### 1.14 Images

`Canvas.image(x, y, cols, rows, image)` reserves a rectangle of cells
(`kSkip`, which the diff never writes, erases or compares) and records
an `ImagePlacement` of a `TerminalImage(protocol, data, pixelWidth:,
pixelHeight:)` on the surface (`Surface.images`); the presenter writes it
in the protocol it was encoded for (`GraphicsProtocol.kitty`, `sixel`,
`iterm2`, or `none`), the terminal's (`TerminalCaps.graphics`). `data`
is the encoded image (`package:twk_rich/image.dart` makes it): a PNG file for
kitty, sent in base64 chunks of 4096 bytes; an image file for iTerm2;
for sixel the bytes between `ESC P` and `ESC \`, raster attributes
included, no taller than the cells. The image is drawn over blanks in
the cells' styles, so a background is filled first; the same
`TerminalImage` object across frames is the same image (a new object is
sent again), and a cell's size in pixels is `TerminalCaps.cellPixelWidth`
and `cellPixelHeight` (0 where the terminal told none).

* kitty: an image is sent once by id (`a=T`; again after a full frame,
  whose `ED 2` deletes it) and placed by a placement id, placed again
  after any scroll, `IL`/`DL` or commit that moves its cells, so it is
  where its cells are whether or not the terminal moved it; cut off by a
  clip, it shows the part left (its pixel size must cover its cells);
  drawn over, its placement is deleted, and an image no placement shows
  is freed. Handing the terminal back (exit, suspend) frees every image;
* sixel and iTerm2: their pixels belong to the cells, so no hardware
  scroll passes over them (recorded, declared and detected scrolls
  rewrite those rows instead) and they are sent again where they went;
  written between `DECSC` and `DECRC`, sixel with DEC mode 8452 and
  iTerm2 with `doNotMoveCursor=1`, so the cursor model holds; cut off by
  a clip, they are not shown (the cells stay blank); drawn over, they
  are dropped, their pixels left in the cells still reserved until they
  are painted again;
* a frame that writes images is a synchronized update; a frame without
  images does no work for them (`PresentStats.images` counts those a
  frame sent or placed again).

The protocol: `TerminalOptions.graphics`, else `TWK_GRAPHICS`
(`kitty`, `sixel`, `iterm2`, `none`), else what the probe finds (§1.7):
kitty's where it answers kitty's graphics query, iTerm2's where its name
(XTVERSION) or its environment says iTerm2 or WezTerm, sixel where DA1
lists it. Inside tmux, which answers the queries itself, sixel is tmux's
own (3.4), and kitty's or iTerm2's go to the terminal outside through
its passthrough (`allow-passthrough on`) where the environment names one
that has it; inside GNU screen, none.

## 2. Testing

| test | what it catches |
|---|---|
| `test/unicode_test.dart` — every `GraphemeBreakTest.txt` case + widths | segmentation and widths |
| `test/presenter_fuzz_test.dart` — ~64,000 random frames (text, CJK, emoji, ZWJ, fills, clip, translate, blit, scrolls, resizes) → bytes into an **independent terminal emulator** (`package:twk_test/vt.dart`: autowrap with pending wrap, BCE, DECSTBM, DECSLRM, ICH/DCH, REP, wide-glyph breaking) → **the whole screen is compared**, not just the damage | any missed damage, cursor/SGR/scroll/BCE errors, wraps; 10 configurations, including a terminal without BCE, Konsole's lines, Konsole's caps on an xterm-like terminal, one without DEC 2026 and hardware scrolling, one with left/right margins, a legacy wcwidth terminal, and scroll detection limited or off; a frame with no changes must produce 0 bytes |
| `test/presenter_test.dart` — presenter edge cases the random frames don't reach | decorated blanks not rewritten when only their colour changes, a one-column rectangle scrolled with DECSLRM, `invalidate()` keeping the cursor state, link targets not percent-encoded, underline colours not in the colon form of SGR 58, fills putting side by side what a terminal would join, a cursor-only frame hiding the cursor, a blank before text not taking the text's SGR, a parameter equal to its default written, reserved cells written, an inline region rewriting more than the row it gains, or not handing the screen back below itself or erased; committed rows not above the region or out of order, the region drawn again where it could move down as it is, rows wider or narrower than the region (or waiting across a width change) not cut or padded |
| `test/frame_bytes_test.dart` — the bytes of typical updates of a chat screen (100×30 and 200×60, DEC 2026 on and off), each bounded by a fixed count; the emulator checks the screen after every frame | an encoding technique dropped (ICH/DCH, DECSTBM + SU, scroll detection, ED 2, EL, REP, SGR reuse, the shortest cursor move, default parameters left out), named in the failure |
| `test/canvas_reference_test.dart` — the optimised canvas against a naive reference painter built from plain objects, 600 seeds, both text modes | composition caches, fast paths, wide-glyph rules, clipping, links |
| `test/canvas_test.dart` — canvas and surface edge cases | a half-covered wide glyph whose other half isn't damaged, blits within one surface (overlapping, off the edges), a wide fill cut by the clip |
| `test/style_test.dart` — pens, blending and SGR | alpha blended over the wrong background or default colour, blends not recomputed for new default colours, SGR per colour mode, a pen id from another table accepted |
| `test/fill_test.dart`, `test/byte_sink_test.dart` — fills and comparisons of typed arrays against naive loops for every length and offset; the output buffer | an off-by-one in a block fill or a 64-bit scan; a view not reused while the length is the same, growth from a small capacity |
| `test/screen_test.dart`, `test/terminal_test.dart`, `test/sequences_test.dart` — `Screen`, the colour mode, notifications and multiplexer from the environment, dark or light by the background, the OSC strings | a screen resized away and back not rewritten, an empty screen with a visible cursor, committed rows not written by an inline screen's next render; `NO_COLOR`, `COLORTERM`, `TERM` and Windows defaults; a terminal taken for another (by a variable it inherited, inside tmux or screen); a colour on the wrong side of half white's luma; control characters escaping the title or a notification, a notification not cut between graphemes, a tmux or screen wrapping that ends early or a screen piece over 252 bytes; the clipboard inside tmux not sent as it is before its wrapping, or inside screen not in pieces ended by BEL |
| `test/input_parser_test.dart` — each kind of input and reply, 300 random splits of the stream + 2000 junk inputs + 5000 strings of sequence pieces | a sequence decoded otherwise (a colour scheme report other than `997;1` or `997;2` taken for one), parser robustness |
| `test/input/parser_test.dart`, `test/input/events_test.dart` — F1 to F4 with modifiers in xterm's CSI form, a mouse report's modifiers and tilted wheel, a paste many times the parser's first buffer; the events as values | an F-key or a wheel direction taken for another, a modifier of the mouse lost; a paste cut where its buffer grows; equal events unequal or hashed apart, a field left out of equality, a key's `ctrl`, `alt` or `shift` wrong |
| `test/input/kitty_keyboard_test.dart` — what kitty's keyboard protocol sends under each of its flags, as `packages/twk_term`'s emulator writes it | a repeat or a release not the key's `kind`, in `CSI u` and in the legacy forms (arrows, `~` keys, F1–F4); a key that types text not the text it types (the associated text, the shifted key) or Shift left among its modifiers; a shortcut not its unshifted key with its modifiers; text that is no character taken for one; a modifier key alone made a `KeyEvent` |
| `test/terminal/kitty_keyboard_test.dart` — `TerminalOptions.kittyKeyboardFlags` on a `Terminal` over an in-memory link, both modes | flags other than those asked for with disambiguation pushed, pushed off the alternate screen or popped after leaving it, pushed or popped more than once, not popped by `suspend` or pushed again by `resume`, missing from what puts the terminal back; `TerminalInfo.kittyKeyboardFlags` not what was pushed, or not 0 without the protocol; anything asked or pushed without `kittyKeyboard` |
| `test/join_test.dart` — one test per UAX #29 joining rule between adjacent cells | separately drawn cells are not joined by a grapheme-clustering terminal |
| `test/render_test.dart` — retained render objects against the expected screen | rows a partial repaint must not skip (appended lines, scrolling, pen changes), cells left by a child replaced or removed, a translucent repaint boundary |
| `test/render/relayout_test.dart` — layouts counted per object after a layout change | a mark that climbs past a relayout boundary, a boundary not moved when the constraints or `parentUsesSize` change, cells left behind by a boundary that shrank, a boundary marked while detached never laid out |
| `test/render/intrinsics_test.dart` — what objects ask for against what they draw, in both text modes and ambiguous widths | text measured otherwise than the screen draws it, an answer not cached or not forgotten on a change, a parent that asked not laid out again when its child changes |
| `test/render/layout_callback_test.dart` — a render object that makes its child in a layout callback for the constraints it gets, under a parent that asks for its intrinsic sizes or not | what the callback changes not laid out with the object, or asking for a layout on the next frame; a relayout boundary the callback marks below what the object lays out (a padding laid out tight, an item of a list with an item extent) not laid out and painted in the same frame; layouts that keep marking each other not stopped after 100 passes, the error not shown by the one laid out last or reported more than once, or not gone once they stop; a parent laid out by intrinsic sizes the callback changed, or a root whose intrinsic sizes it changed, not laid out again on the next frame, until they hold; a parent that asked for none laid out again |
| `test/render/flex_test.dart` — `RenderFlex` and the child list | children out of order after insert, move and remove; free cells, gaps and flexible shares not in whole cells or leftovers in the wrong place; each main and cross alignment, `MainAxisSize`, `FlexFit`; overflow not cut off or reported more than once; intrinsic sizes; along an unbounded main axis a child, flexible or not, not as long as it wants, or the flex not as long as its children whatever its `MainAxisSize` |
| `test/render/viewport_test.dart` — `RenderViewport`; frames through the emulator | the child not laid out as long as it likes along the axis (a column in it not as tall as its children, flexible ones too), the offset not kept within the child's extent less the viewport's when set before or after a layout, `onExtents` not told; a one-row scroll of a view all on the screen not declared or scrolled in hardware (`DECSTBM + SU/SD`, `DECSLRM` for a narrower view, rewritten where the terminal has no margins) or painting more than the exposed rows, a view scrolled back painting anything; a view cut off by an ancestor, scrolled along a horizontal axis, painted over by a later child of a stack, or with something inside it marked for paint or laid out as it scrolls, not painted in full; a repaint boundary inside it not repainting on its own; the child not hit at the offset, or hit outside the window; axis, offset and background not described |
| `test/render/list_test.dart` — `RenderList` with a `ListItemManager` of the test's; frames through the emulator | items built outside the window and the cache rows or not as wide as the list, or kept once they leave; a height not measured, the others not taken to be the average, an item extent not kept or measured, heights not forgotten when the width changes; a move of a window or less not exact or not laying out the items it passes, a longer one not where the estimate puts it, 0 or past the end not exactly the start or the end; near an end, a move of a window stopping short of the end or skipping items; an offset `onMetrics` sets not taken in the same layout; the item at the top moving as the items above it are measured, the offset it settled at not told; `jumpToIndex` and `showIndex`; of an offset set and a move to an item since the last layout, the later not winning, the offset the list is at too; not following the end as items are added while it sticks to it, not starting there, items removed leaving the window empty; unbounded constraints taken; a one-row scroll of a list all on the screen not shifted and scrolled in hardware, or painting more than the row exposed and the items laid out again or moved; a mark inside it other than by its layout not painting all of it, a repaint boundary inside an item not repainting on its own as it scrolls; a list cut off by an ancestor scrolled instead of painted; the rows below its items not filled; an item hit outside the window; items, offset, extent, cache and sticking not described |
| `test/render/boxes_test.dart` — `EdgeInsets`, `RenderPadding`, `Alignment`, `RenderPositionedBox`, `RenderConstrainedBox`, `RenderFractionallySizedBox`, `RenderIntrinsicWidth`, `RenderIntrinsicHeight` | layouts, the odd cell in the middle, a child sticking out not cut off, a box with factors taken for a relayout boundary, intrinsic sizes, a new constraints object for a child laid out again within the same ones; a child not given exactly its fraction, or a fraction not rounded to the nearest cell, a half up (0.29 of 100 cells floored to 28), a factor applied along an unbounded axis; a size to content not rounded up to its step, a tight extent not kept as it is, a row whose children stretch not as tall as its tallest child |
| `test/render/borders_test.dart` — `BorderType`, `RenderDecoratedBox` and `RenderDivider`; every frame also through the emulator | a missing piece of a type; a type on any of the 16 sets of sides, ASCII not drawn where box drawing is two columns wide (both text modes), side and corner pens, `none` not showing its background; titles out of place, of order or of room, not cut off with an ellipsis (a two-column one too) or splitting a wide glyph, no row for titles without a border; insets, `inner`, sizes and intrinsic sizes; new pens laying it out, new sides, padding or titles not, titles not measured again for another owner or shaped again for another screen; a divider off the middle or longer than allowed along an unbounded axis, a new direction not reaching its parent |
| `test/render/border_merge_test.dart` — `Canvas.mergeRun`, and `RenderDecoratedBox` and `RenderDivider` with `merge`, over each other in a `RenderStack` | a piece of a type not joined with every other piece of it, or with the half lines of single and heavy lines; an arm's weight not kept where Unicode has the mix, or a piece not in the new weight where it hasn't; a round corner not kept where nothing is added to it, dashed lines not merged as solid ones, ASCII merged with box drawing, text in a cell not kept with its style or a wide glyph not kept whole, a glyph drawn that is no piece of line not drawn as `run` draws it; a trimmed end reaching past the line it lands on, `under` not painted first, clipping and wide glyphs otherwise than `run`; merged boxes side by side, one above another, four around a point or nested not joining their lines (every type), unmerged ones not covering them, a side without a neighbour not ending in a joint, ASCII not merged where box drawing is two columns wide, mixed types not mixing where Unicode can, the titles of the edges they cross or share not kept; a merged box over nothing looking otherwise than unmerged (every type, the 16 sets of sides, small sizes, one pen and a pen per side that sets every color), the background not under the merged lines or not filling the rest; dividers across and down a box or crossing each other not joining (every type, mixed types), or over nothing drawn otherwise than unmerged; `merge` laying out instead of repainting, or not described |
| `test/render/stack_test.dart` — `RenderStack`; frames with repaint boundaries also through the emulator | children placed by the alignment with each `StackFit`, the stack's size with and without them, each way a child is pinned (both edges, its size, no edge, up to the far edge, a negative edge cut off), paint order, intrinsic sizes; a boundary repainted on its own covering the children over it (boundaries or not, in nested stacks, in a stack its parent cuts off), children painted again that don't overlap it, a log moving the panel over it along as it scrolls, a log over a repainted boundary losing lines |
| `test/render/grid_test.dart` — `GridTrack` and `RenderGrid`; every frame also through the emulator | a track of a kind not sized as it says or outside its bounds, cells left over not going to the first tracks, gaps; a spanning child not growing the content tracks it spans by even parts, growing them across a fraction track, or sized before those that span fewer; rows asked for heights at other widths than their columns'; the length along an unbounded axis, intrinsic sizes; a child without a row and a column not placed after the one before or not wrapped, taken cells skipped; a boundary repainted on its own covering the children after it; overflow not cut off or reported more than once; new tracks or gaps not laid out again, equal ones laid out; tracks, lengths, overflow or a child's cells not described; a child with a row and no column not showing the error |
| `test/render/wrap_test.dart` — `RenderWrap` on a screen | children of mixed widths not wrapping at each of several widths, gaps between the children or the runs, a vertical wrap not filling columns, runs made along an unbounded main axis, a child not let take the whole main axis; the size not that of the longest run and the runs, or of the constraints where they ask for more; a `WrapAlignment` not sharing the free cells of a run, or across the runs, in whole cells, a `WrapCrossAlignment` not placing a child in its run; runs that don't fit not cut off, reported more than once or not described; intrinsic sizes along and across the main axis, of a vertical wrap too; a child's new size or a new setting not laying the wrap out again; a child of a later run not hit at its cell |
| `test/render/paragraph_test.dart` — `RenderParagraph` in Latin, Cyrillic, CJK, kana, emoji, ZWJ sequences, flags and combining marks; every frame also through the emulator, in both text modes and ambiguous widths | each wrap mode, each ellipsis, `maxLines`, alignment and justification, intrinsic sizes, a grapheme split, a change laid out when it needs only a repaint or not laid out when it does, clusters not split again for another owner's segmenter, pens not looked up again in another style table |
| `test/render/paragraph_text_range_test.dart` — `RenderParagraph.textRangeAt` | the cluster at a cell not given by its offsets into the spans joined (either cell of a wide one, a cluster of several code points), left of a row's text (aligned or not) not its start, right of it not the next row's start after the spaces it hangs and its line break, what takes no cell (the CR of CR LF) not going with the cluster after it, a justified row's gap not the space before it, an ellipsis not standing for the clusters it replaces (each line's own, cut off at its start), rows cut off, above the first row and below the last, the ranges of a new text; the offsets of the clusters found by a layout before they are asked for, or found again for a layout at another width (counted) |
| `test/render/diagnostics_test.dart` — `DiagnosticsNode` as text and JSON, the `describe…` functions, `describe()` of each kind of render object | guides, the size column or the legend out of place (wide glyphs counting two columns), a run folded below `fold`, a text not quoted, escaped or cut off, a pen, constraints, insets or an alignment written otherwise; a property missing or shown at its default, a boundary, needs layout or needs paint not flagged, a flex's overflow not reported; a frame describing anything |
| `test/render/error_test.dart` — render objects whose layout or paint throws, in a tree that fills the screen | the message not shown in white on red where the object is, as big as it is within the constraints, or cut off at its bounds; an error reported more than once, or not again once fixed and broken again; what a throwing paint left on the canvas moving the rest; a repaint boundary inside painting over the error; without `onError`, an error not thrown once the flush ended (or at once outside one) or the others not shown; an object showing an error not described so |
| `test/render/hit_test_test.dart` — `hitTest` and `HitTestResult` over nested, clipped and overlapping objects, and over every cell of a 200×60 tree | objects not found from the deepest to the root, or the cell not in each one's coordinates; what sticks out of its parent or any ancestor hit; the children of a stack or a grid not tested from the one on top (after a move too), a flex's gaps not leaving the cell to what is under it; opaque not hiding what it covers, translucent not letting it be hit, deferToChild hit without a child, an object showing an error not hit whole; the core's objects not opaque where they paint, a box not hit around its child, a decorated box without a background hit where it draws nothing; a result not emptied, not growing for a deeper path, or growing while reused |
| `test/render/debug_paint_test.dart` — the repaint rainbow and the relayout highlight of a `PipelineOwner` | a boundary tinted that didn't repaint, or not tinted anew on each repaint; a tint not blended over the background or changing a cell's glyph, colours or attributes; a tint beyond where the boundary's ancestors let it paint; the rows of a log tinted twice (scrolled, or painted by its parent); a flag reaching another owner's tree; turning a flag on or off not repainting everything; an outline around more or fewer objects than those laid out, one frame's outlines in more than one tint, the next not in the next, half of a wide glyph on an edge left out, objects laid out before the highlight was turned on outlined |
| `test/outbox_test.dart` — bytes on their way to stdout, against a sink that rejects writes during a flush like dart:io | writes during a pending flush wait in order, one flush at a time, frames are copied into one reused buffer (the caller's buffer is free at once), a failed flush |
| `test/terminal/suspend_test.dart` — `TwkApp.suspend` on `HeadlessTerminal` (on `VtTerminal` for a backend that can't be handed over), the screen in the emulator (the inline one below guarded history) | frames written while handed over, the backend not handed over before `run` or taken back after it, the screen not repainted in full afterwards (what another program drew left on it), what `run` throws not reaching the caller, a second `suspend` while handed over not refused, the inline region not parked below itself, or started again over what the other program printed instead of below it (on the cursor's line, or the next), quit while handed over taking the terminal back, a backend that can't be handed over drawing meanwhile |
| `test/terminal/notify_test.dart` — `Terminal.notify` and `Terminal.copyToClipboard` in a pseudo-terminal (`tool/pty_run.py`) in the environment of kitty inside tmux, of foot, of a terminal without notifications, and for the clipboard inside tmux, inside GNU screen and outside both | the protocol or the multiplexer not taken from the environment by the probe, bytes written where nothing is known to show them; the clipboard not wrapped for tmux or screen, or wrapped outside them |
| `test/terminal/color_scheme_test.dart` — `test/terminal/color_scheme_app.dart` in a pseudo-terminal (`test/terminal/color_scheme_pty.py`) that answers the probe as a dark terminal with mode 2031 and then reports a switch to light | the mode not asked for by the probe, not turned on while the app runs (or more than once) or not off at the end, the brightness not taken from the background, the report not decoded, the default colors not asked for again after it |
| `test/terminal/socket_test.dart` — `Terminal.connect` against a shell's end spoken by hand, `TerminalShell` serving a terminal in memory to `TwkApp` on `Terminal.connect` or to the wire spoken by hand, the address files; `Terminal.open` in a process without a terminal (`test/terminal/socket_app.dart`) | the hello without the token, output before raw mode, a size or environment not the shell's, frames, input or resizes not passed on, a flush completing before the shell wrote the bytes, the restore bytes not told (the title's pop, empty once restored or while suspended), mouse reports switched not written or not undone by the restore, the shell going away not ending `run()`; the console not raw while an app has it or not cooked after, input passed on while no app has it in raw mode, the restore bytes not written for an app that went away or part of a frame cut short written, a newer app not taking over, a wrong token or protocol not refused, `stop` leaving the address file or the socket; an address file not read back, the project not found by its pubspec, a socket path too long not moved to a temporary directory, another server's address file removed; `Terminal.open` not finding the project's shell |
| `test/terminal/socket_wire_test.dart` — the wire where it breaks: frames split across reads or too long, a shell that sends nonsense, doesn't answer or isn't there, an app that sends no hello, an unknown frame or one too long; `Terminal.open` failing at a shell (`test/terminal/socket_app.dart` with a trace it can't write); the addresses | a frame bigger than the reader's buffer garbled; a frame too long taken in; connecting not failing, or hanging, against a shell that is gone, silent or broken; a flush left waiting when the shell goes away or the link closes; a link whose input nobody listened to never closing (`Terminal.open` then ending the process without its error); an app with a broken hello or frame not cut off, or the terminal not put back for it; `stop` not idempotent; a project without a pubspec, a socket left behind not replaced; addresses unequal or printed with their token |
| `test/terminal/mouse_tracking_test.dart` — `mouseTrackingSequence` and `HeadlessTerminal.mouseTracking` | a switch that doesn't turn the old mode off before the new one on, SGR coordinates not on with the first reports and off with the last; a `HeadlessTerminal` starting with reports, a switch not written to its frames, or written in the inline mode or once closed |
| `test/app_test.dart` — the frame loop against `HeadlessTerminal` | layout measuring text otherwise than the screen draws it, requests coalesce into one frame, `beforeLayout` not at the start of each frame (in the inline mode before the region is sized), its changes not laid out by that frame or asking for another, `afterPresent` not at the end of each frame, after its bytes are written and before they are flushed (also in a frame with no bytes), or its changes not painted by the next frame, input handled before the first frame, the fps cap, frames spaced by the wall clock instead of the clock given, a repaint asked for during a held flush, errors in paint/handlers/timers ending `run()` after the restore, quit, resize; a reported default color not blended with or one already known repainting; frames in a row not in full, not below each other, the presenter's bytes written too, the name not cut to the width, committed rows after their frame, the inline region left at the end; the stages of the last frame not adding up to it or holding another stage's work, the repaint boundaries it repainted not counted |
| `test/terminal/trace_test.dart` — `TraceWriter` and `Trace`; an input trace fed to `HeadlessTerminal`; `test/terminal/trace_app.dart` in a pseudo-terminal with both traces on | the header or a record laid out otherwise, a write on the caller's path, records lost or out of order while a write is on its way, a caller's buffer not copied, a cut-off file not read up to the cut, a broken one read; a lone ESC fed back as Alt with the next key, a split sequence cut; the probe or any write missing from the output trace (it must equal the capture byte for byte), its replay not reaching the capture's screen, `--frame` and `--step` off by one; reads missing from the input trace, which must decode to the keys typed |
| `test/terminal/timeline_test.dart` — `test/terminal/timeline_app.dart` run with the VM's Dart timeline stream recorded to a file | a phase missing from a frame's slices or out of order (`Build`, `Layout`, `Paint`, `Present` and `Finalize` inside `Frame`), a slice left open; slices on the timeline while `TWK_DEBUG` doesn't name it |
| `test/headless/` — `HeadlessTerminal` and `renderToString`; an inline app on it, its frames fed into the emulator below guarded history | input split anywhere decoded by the parser, the pause each kind of pending input waits and what timing it out gives, resizes, frames kept as written, input not dropped while handed over, a line break missing or extra when taken back (inline, the cursor off the start of a line), close; a notification not in the protocol given, not wrapped for the multiplexer or not under an id of its own, or written for none or once closed; text rows with wide and combining glyphs, the ANSI frame shown with its styles by the emulator, a tree painted before painted in full; an inline region writing to the history, not starting on the next line after text, not growing, shrinking or repainting on a resize, or writing other bytes than on `VtTerminal` |
| `test/presenter_fuzz_test.dart`, inline group — ~17,500 random frames in a region of a normal screen (`package:twk_test/vt.dart` with a scrollback) below printed history; the region grows, shrinks, and the terminal is resized keeping what it shows (rows cut or padded, the screen scrolling its top into the scrollback or taking lines back from it); rows are committed to the history (more than the screen holds, with the screen height known or not); 4 configurations | a write to the history (the emulator guards it, committed lines too), any absolute row (`CUP`, `DECSTBM`, `ED 2`), the region not found again after a resize, rows below the region left non-blank, committed rows not as they were drawn (styles, wide glyphs, links) or out of order, plus every check of the fullscreen fuzz |
| `test/inline/` — `TwkApp` in the inline mode against `VtTerminal` (`package:twk_test/vt_terminal.dart`: frames into the emulator with a scrollback, below guarded history) | the region starting below the history (on the next line after text), growing with its content and pushing the history into the scrollback, its row limit, shrinking only when asked, the region kept or erased on exit with the cursor below it or where it began, resizes; commits not above the region, not wrapped at the width or losing styles and wide glyphs, a burst of 10,000 committed lines holding input up or written out of order, a commit before `run` or one waiting at quit lost; an error while sizing the region not reported to `onError` as the root's or reported more than once, the region not keeping its height (1 row at first, within the terminal) or dropping a shrink asked for; a commit that throws not reported as the commit's in its phase, not replaced by an error block at the width, or stopping the region and later commits; either without `onError` not ending `run()` |
| `test/log/` — the log sink, and an app with a stand-in stderr; `TWK_LOG` in a process of its own; the sink served on a socket to a client spoken by hand | `print` in handlers and timers recorded instead of printed, `log()` levels, uncaught errors recorded, the ring dropping the oldest, listeners, warnings and errors on stderr after the restore in order, a log file that can't be written; in the process: stdout stays empty and the file gets every record; the sink served on a socket: a record not surviving JSON, the records kept not sent first or those that come not after them, records sent once the sink stopped serving, the project's address file not naming the socket meanwhile, a client without the token served, a newer app's address file removed; an app in a process of its own (`test/log/served_app.dart`): its log not served while it runs with `TWK_DEBUG=logs` or still served after it ends, served without it, a log that can't be served not a warning on stderr or ending the app |
| `test/unicode/bidi_test.dart` — the bidi properties, `BidiText`, and every case of `BidiTest.txt` and `BidiCharacterTest.txt` | a level or an order otherwise than UAX #9 resolves it (more than 700,000 class sequences in each paragraph direction, 91,707 strings) |
| `test/render/bidi_paragraph_test.dart` — `RenderParagraph` in logical and visual order, Hebrew and Arabic with Latin and digits, through the emulator | right-to-left text reordered in logical order, or not in visual order; brackets not mirrored, `start` and `end` not by the paragraph's direction, an ellipsis or justification on the wrong side, `textRangeAt` not the cluster drawn; a new order not laying the tree out again; work done for text with no right-to-left character |
| `test/render/effect_test.dart` — `RenderEffect` through the emulator | a frame of the effect painting the child or what is under it, a mark in the child not putting back what was under it, a repaint boundary inside not shown through the effect, what the parent or a boundary under it paints anew not shown, two-column glyphs split |
| `test/graphics/` — `Canvas.image` in each protocol through the emulator, which records placements; the probe; a fuzz of frames with images in both modes; an app in a pseudo-terminal per protocol (`TWK_GRAPHICS`) | an image not sent once, not placed again after a scroll, or not deleted and freed when drawn over or on leaving the screen; a hardware scroll over sixel or iTerm2 pixels; the cursor moved by an image; a kitty chunk over 4096 bytes; an unsynchronized frame with images; a protocol not found from the answers or the environment; a frame without images writing other bytes |
| `test/viewport/` — the presenter in a viewport over a patterned screen (a fuzz of 5 placements), and `TwkApp` on `HeadlessTerminal` with one | a cell outside the viewport written, during frames, resizes or after the end; the cursor not put back, autowrap not on again; `EL`, `ICH`, `DCH`, `ED 2` or `DECSTBM` where they reach past it; a rectangle not cut to the screen or not given back; mouse events not relative to it, outside it not dropped, a held button's release lost; the mouse on the normal screen without `normalScreenMouse`; on plain output, the frame placed |
| `test/terminal/plain_test.dart` — the choice of plain output, a plain `Terminal` and an app on it, the demo with its stdout piped | an escape sequence written to a pipe or in CI; the last frame not written as text when the app ends, or inline commits not as they come; `TWK_PLAIN`, `CI` and the rest not read as they should |
| `test/terminal/link_test.dart` — `Terminal.overLink` over a link in memory, and in a process of its own | the probe not answered, keys or resizes lost, modes not put back at close; bytes other than `Terminal.open` writes over the same link; a signal of the process taken as a key or a trace written over a link; `suspend` not refused; state kept or a timer started on plain output |
| `test/terminal/terminal_input_test.dart` — `Terminal.overLink` on what the probe's answers turn on, input that takes a while, keys typed during the probe, a link failing during it, `notify` | in-band resize or grapheme clusters not turned on and off, a resize report not the size; the ambiguous width or the inline cursor column misread; keys typed during the probe lost or out of order; opening not failing, or the link not put back and closed, when its input fails; a lone ESC waiting as long as a sequence that started, or a started one cut; a paste whose end got lost never ending; a notification not numbered for the process, or written where none shows or once closed |
| `test/platform/` — the platform layer on the VM (`io.dart`) and its web stand-ins (`web.dart`), loaded on the VM; the own terminal link and termios on a stdin that is no terminal; a log server's client that sends no line | the process's id, platform or environment not dart:io's; an own terminal without both stdin and stdout one; plain stdio not sized by `COLUMNS` and `LINES`; a trace file not emptied or a header failure swallowed; raw mode not refused without a terminal; a stand-in that reads, watches or serves something; a client without a token kept |
| `test/terminal/sequences_test.dart` — the pointer shape and the progress; GNU screen's pieces of a sequence passed on | the sequences, a shape or a progress written where the environment names no terminal known to show it, or where a version may read OSC 9 as a notification; a character split between pieces or its UTF-8 bytes miscounted |
| `test/web/core_app.dart`, run by the root's `test/tool/web_check_test.dart` — `tool/web_check.dart`'s core case: an app on `HeadlessTerminal` and over a link of its own, built with dart2wasm and run in node | a library of the core reachable on the web importing dart:io or dart:ffi, or failing when run (skipped without node 22) |
| `packages/twk/test/` — the widget layer, by topic | see [its README](../../twk/doc/reference.md) |
| `packages/twk_rich/test/` — rich text, by topic, and images (`test/image/`) | see [its README](../../twk_rich/README.md) |
| `packages/twk_test/test/` — the tester, its fake clock, its keys, matchers and finders, the frames it records, the emulator's passthrough strings | see [its README](../../twk_test/README.md) |
| `packages/twk_dev/test/` — the `twk` command | see [its README](../../twk_dev/README.md) |
| `packages/twk_cli/test/` — the console: its modes, messages, widgets shown, prompts and progress in each mode, the traceback and `inspect`, its fake terminal | see [its README](../../twk_cli/README.md) |
| `packages/twk_riverpod/test/`, `twk_bloc/test/`, `twk_lints/test/`, `twk_term/test/`, `twk_web/test/`, `gallery/test/` | see each package's README |

The tests share `test/support/harness.dart`, which wires the core to the
emulator and makes random scenes. The emulator is
`package:twk_test/vt.dart`, and `VtTerminal`
(`package:twk_test/vt_terminal.dart`) an inline `TerminalBackend` that
feeds it: the core, `packages/twk` and `packages/twk_rich` take
[`packages/twk_test`](../../twk_test/README.md) as a dev dependency by
path, and those of their tests that check what reaches a terminal feed
it to that emulator. The widget layer's tests also run apps with its
tester, `testTwk` (`package:twk_test/twk_test.dart`): `runApp`'s binding
on a `HeadlessTerminal` under a fake clock, input as the bytes a
terminal sends, the screen read back through the emulator.

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

`dart analyze` (rules: `pro_lints/recommended`, strict casts, inference
and raw types) must report no issues, `dart test` must pass and `dart
format` must change nothing, here as in every package of the repository:
the checks are the repository's (`xtask.yaml` at the root, run by
`dart run tool/xtask.dart handover`; [its README](../../../README.md) and
`CONTRIBUTING.md` say what they are). `dart run tool/web_check.dart` (§1.7)
builds the core, packages/twk and packages/twk_web for the web and runs
them.

## 3. Limitations

* **Not run on Windows** — the kernel32 code follows the documentation and
  is only checked by the analyzer. It needs a run on Windows Terminal and
  conhost. Ctrl+Break can't be watched from Dart (only CTRL_C_EVENT and
  the console closing are), so it ends the process without restoring the
  console. Older conhost builds read non-ASCII input as NUL bytes under the
  UTF-8 input code page that is set; reading through `ReadConsoleW` would
  need a Windows input backend of its own.
* **Not run on macOS** (the POSIX path is the same as on Linux except the
  `struct termios` layout used to turn ISIG off; Terminal.app → 256 colors
  is detected from `TERM_PROGRAM`).
* Raw mode beyond what `dart:io` does (ISIG, IXON, ICRNL off) needs the
  `struct termios` layout, known here for Linux and macOS only; elsewhere
  Ctrl+C arrives as a signal and is turned into a key, Ctrl+\ / Ctrl+Z act
  on the process and Ctrl+S may freeze output.
* `Terminal` can be opened on the process's terminal once per process:
  `close()` cancels the stdin subscription, which closes stdin. To hand
  the terminal to another program and come back there is
  `suspend`/`resume` (§1.7), which keep it paused. Over a socket
  (`Terminal.connect`) it can be opened as often as wanted.
* `twk shell` and the sockets (§1.7): not run on Windows or macOS. On
  Windows the socket is TCP on the loopback interface, which any local
  user can reach (the token in the project's address file guards it).
  Ctrl+C reaches the shell only while no app has the terminal; to stop
  it meanwhile, stop the app. `TwkApp.suspend` on a served terminal
  gives the shell's console back, but the other program runs in the
  app's own stdio; `suspendToShell` stops the app with no shell to
  continue it.
* `twk run` (hot reload, [`packages/twk_dev`](../../twk_dev/README.md)):
  not run on Windows or macOS. On Windows, which has no SIGTERM, a
  restart (Ctrl+G H) kills the app without the terminal put back. A
  reload leaves what `main` built and code that ran already as they
  were: that takes a restart.
* Handing the terminal over: on a terminal that answers no queries, input
  the other program read can leave the app waiting for the next key once
  it takes the terminal back (dart:io's blocking read, §1.7). Ctrl+\
  while the other program has the terminal ends the app (SIGQUIT can't be
  watched from Dart); the terminal is in cooked mode by then. Not run on
  Windows, where `suspendToShell` throws (no job control). On macOS
  dart:io takes a read that gets less input than it noted for the end of
  stdin, which input the other program read could cause (not run there).
* The widget layer, [`packages/twk`](../../twk/doc/reference.md), covers part
  of what an app needs: `runApp` (full screen, inline or in a fixed
  viewport), the framework (widgets, elements, state, keys, inherited
  widgets, parent data, notifications, building in the layout),
  listenables, futures and streams and the builders over them, animations
  (tickers, controllers, tweens and curves), spinners and progress bars,
  style values and themes, text, the layout widgets over the core's boxes,
  borders, flexes, stacks, grids and wraps, a dot canvas, charts,
  heatmaps, a calendar, tables of a million rows, tree views, a file tree,
  task lists and lists of many tasks with their rate and time left,
  description lists, output written to the terminal's history, desktop
  notifications, the focus tree, key bindings and key sequences, the mouse
  by hit test and gestures, text selection with the mouse, drag and drop,
  an overlay with dialogs, toasts, tooltips, popovers, a menu bar, context
  menus and a command palette, a navigator of routes that slide in,
  breadcrumbs, pagination, a stepper of steps that validate, sections that
  fold, scrolling a child, lazy lists and scrollbars, split panes, a
  one-line text field and a multi-line text area with undo and
  suggestions, buttons, segmented buttons, checkboxes, switches, radio
  groups, selection lists, selects and confirmations, sliders, number
  inputs and date pickers, forms of fields that validate, tabs, a key
  hints bar, a status bar, status messages, callouts, badges and links,
  dumps of the element and render trees, a log console, a frame overlay,
  and service extensions for tools over the VM service, hot reload (`twk
  run`) and an inspector (`twk inspect`) among them; also floating windows
  and docked panels, named slots that plugins fill, implicit animations
  and transitions, skeletons that shimmer while content loads, effects
  over a subtree, drop shadows and gradients, semantics and a
  screen-reader mode, a file picker, and the pointer's shape and the
  program's progress in the terminal's tab.
  [`packages/twk_rich`](../../twk_rich/README.md) parses Markdown and
  shows it, also as it streams in, inline a block at a time into the
  terminal's history, reads program output with ANSI sequences into styled
  spans or strips them, highlights source code (Dart, JSON, YAML, Bash,
  JavaScript, TypeScript, Python, Rust, Go and diffs), shows diffs unified
  or side by side with line numbers, draws big text and QR codes, and
  shows JSON and Dart values as a tree that folds.
  [`packages/twk_cli`](../../twk_cli/README.md) is the console of a
  command-line tool that is no app: where somebody answers at a terminal,
  its prompts, progress and widgets are live in one inline app, the output
  committed above them; elsewhere they are lines.
* Desktop notifications are told apart by the environment only: a
  terminal started from another may inherit its variables (a
  `TERM_PROGRAM` of its own guards against that), and tmux keeps the
  variables of the terminal it was started in, not of the one attached
  now. Inside tmux they need `allow-passthrough on`; a multiplexer inside
  another gets them wrapped once, which the outer one drops.
* Rectangle scrolling is done in hardware only where the terminal answers
  DECRQM `?69` (DECLRMM); otherwise it is a plain diff. Joining of adjacent
  cells by a grapheme-clustering terminal is broken by explicit
  positioning; a terminal that joins across a repositioned cursor can't be
  protected against (the behaviour is unspecified).
* Images (§1.14): inside tmux, kitty's and iTerm2's go through its
  passthrough, which takes `allow-passthrough on`; tmux drops a sequence
  over 1 MB (an iTerm2 image is one) and puts an image where it left the
  outer terminal's cursor, which can be off in a split pane (kitty's
  Unicode placeholders would place it right; they are not used). GNU
  screen passes none on. Where terminals move sixel and iTerm2 pixels
  within scroll margins is not known, so no hardware scroll passes over
  them. Still images only. `Canvas.reserve` hands cells to anything else
  drawn outside the cell model the same way: the presenter never writes,
  erases or compares them.
* Bidirectional text is ordered by who the terminal is taken to leave
  it to (§1.7), told by its answer or its name: a terminal misjudged
  (Konsole with its bidi rendering turned off, one of another name that
  reorders) shows right-to-left text reversed unless
  `TerminalOptions.bidi` says otherwise, and an outer terminal that
  reorders, inside tmux, which drops BDSM, reorders what the app ordered
  already. Where the terminal reorders text itself it does so a whole row
  at a time, which can mix up text in columns side by side. In visual
  order `RenderText`, and what a widget draws with `Canvas.text` itself,
  stay as stored; Arabic is not shaped (no presentation forms), which a
  terminal that leaves the reordering to the app needs; kitty, unless its
  `force_ltr` is on, reverses the letters of right-to-left words it is
  given in visual order.
* The web build (§1.7) is dart2wasm's only, and runs where WasmGC is
  (Chrome and Edge 137, Firefox 134, Safari 26.2 and later). It has no
  file system, environment or signals: `Terminal.overLink` is its
  terminal, and a `LogSink` writing a file or serving a socket throws
  `UnsupportedError`.
* Plain output (§1.7) reads input only where stdin is a terminal: an app
  that a key ends, run with no terminal at all (CI), runs until it ends
  itself or a signal ends it.
* An uncertain glyph's width error is contained, but the glyph itself may
  render clipped on a disagreeing terminal — a property of the terminal.
* Inline mode: a terminal that reflows the region's own rows on a resize (a
  narrower window wrapping them) may leave pieces of the old region above
  the repainted one; the history isn't written, but those pieces stay.
  SIGTERM restores the terminal without leaving the region: the cursor
  stays where the last frame put it. The ambiguous width is not measured
  (that would draw on the normal screen) and is taken as 1. Committed
  text is wrapped by the app into lines of their own, so a terminal that
  reflows its history on a resize doesn't join them again; the rows of a
  commit still being written when the width changes are cut or padded.

## 4. Running

No runtime dependencies; `dev_dependencies` are `test`, `pro_lints` and,
by path, `packages/twk_test` (the test emulator and the widget tester,
§2). The commands below run from the repository's root, where its
`tool/` is.

```bash
dart pub get                                               # the whole pub workspace
(cd packages/twk_core && dart test)                        # the core's tests
dart run packages/twk_core/example/chat_demo.dart          # live demo (q / Esc to quit)
dart run packages/twk_core/example/chat_demo.dart --inline # the same in the inline mode
dart run packages/gallery/bin/gallery.dart                 # the widget gallery (Ctrl+C to quit)
dart run tool/gen_unicode.dart --refresh                   # regenerate the Unicode tables

# end to end: the demo in a pseudo-terminal, then its output in the emulator
python3 tool/pty_run.py --out /tmp/demo.bin -- \
    dart run packages/twk_core/example/chat_demo.dart --seconds=3
dart run tool/replay.dart --fullscreen /tmp/demo.bin 100 30

# the same for the inline mode: the committed lines in order in the
# scrollback, the region below them, the cursor below it
python3 tool/pty_run.py --out /tmp/inline.bin -- \
    dart run packages/twk_core/example/chat_demo.dart --inline --seconds=3
dart run tool/replay.dart --inline /tmp/inline.bin 100 30

# the demo's Ctrl+E through an "editor" that prompts, reads a line and
# appends it to the file (for the inline mode, add --inline to the demo and
# replay with --inline); pty_run.py prints the demo's stderr, where the log
# says `editor exited with 0`, then `sent: hi from the editor`
python3 tool/pty_run.py --suspended 'editing> ' \
    --input '0.5:hi,0.8:\x05,@0.3:from the editor\r,@1:\r,@1.3:q' \
    --out /tmp/edit.bin -- dart run packages/twk_core/example/chat_demo.dart \
    '--editor=printf "editing> "; read x; echo "$x" >>'
dart run tool/replay.dart --fullscreen /tmp/edit.bin 100 30

# an app in the inline mode below lines printed before it (with no input:
# it would come before the app reads it, and the terminal would echo it)
python3 tool/pty_run.py --input none --out /tmp/inline.bin -- sh -c \
    'printf "history 1\nhistory 2\n"; exec dart run packages/twk_core/test/inline/inline_demo.dart --seconds=3'
dart run tool/replay.dart --inline /tmp/inline.bin 100 30

# handing the terminal to `sh -c '… read x …'` and taking it back (add
# --inline to the app for the inline mode; see tool/pty_run.py --help for
# Ctrl+Z and the shell)
python3 tool/pty_run.py --suspended 'suspended> ' \
    --input '1:s,@0.2:hello\r,@1.5:q' --out /tmp/suspend.bin -- \
    dart run packages/twk_core/test/terminal/suspend_app.dart
dart run tool/replay.dart --fullscreen /tmp/suspend.bin 100 30

# twk shell in a pseudo-terminal: the demo started without a terminal draws
# there and gets what is typed; Ctrl+C stops the shell once the demo ended
python3 tool/pty_run.py --input '6:hello,16:\x03' --out /tmp/shell.bin -- \
    dart run packages/twk_dev/bin/twk.dart shell &
sleep 4; dart packages/twk_core/example/chat_demo.dart --seconds=3 </dev/null; wait

# a terminal that switches to a light color scheme after a second
python3 tool/pty_run.py --input none --scheme 1:light --out /tmp/scheme.bin -- \
    dart run packages/twk/test/binding/color_scheme_app.dart --seconds=2
dart run tool/replay.dart --fullscreen /tmp/scheme.bin 100 30

# the demo's reads and writes traced, its writes replayed frame by frame
TWK_TRACE_INPUT=/tmp/in.trace TWK_TRACE_OUTPUT=/tmp/out.trace \
    python3 tool/pty_run.py --out /tmp/demo.bin -- \
    dart run packages/twk_core/example/chat_demo.dart --seconds=3
dart run tool/replay.dart --fullscreen --trace /tmp/out.trace     # final screen
dart run tool/replay.dart --fullscreen --trace --frame=5 /tmp/out.trace
dart run tool/replay.dart --fullscreen --trace --step /tmp/out.trace | less

# each frame below the last, as text (TWK_DEBUG=timeline: DevTools slices)
TWK_DEBUG=frames dart run packages/twk_core/example/chat_demo.dart --seconds=3

# the demo's log, served while it runs, tailed in another terminal
TWK_DEBUG=logs dart run packages/twk_core/example/chat_demo.dart
dart run packages/twk_dev/bin/twk.dart logs        # in another terminal

# twk run in a pseudo-terminal: packages/twk's counter hot reloaded; Up
# counts, Ctrl+G H restarts it, q quits (an edit of
# packages/twk/example/counter.dart meanwhile shows with the count kept)
python3 tool/pty_run.py --input '2:\x1b[A,4:\x07H,9:q' --out /tmp/run.bin -- \
    dart run packages/twk_dev/bin/twk.dart run packages/twk/example/counter.dart
dart run tool/replay.dart --fullscreen /tmp/run.bin 100 30

# a running app's widget tree in a second terminal: twk inspect connects to
# the app twk run runs from the same directory (packages/twk_dev's README)
dart run packages/twk_dev/bin/twk.dart run packages/twk/example/counter.dart
dart run packages/twk_dev/bin/twk.dart inspect     # in another terminal

# the demo with its stdout piped: no escape sequences, its last frame as
# text when it ends (TWK_PLAIN=1 asks for that on a terminal too)
dart run packages/twk_core/example/chat_demo.dart --seconds=2 | cat

# an app in a fixed viewport, a box of 36 x 7 cells from column 10 of
# row 3 of the normal screen, the rest of the screen left as it was
python3 tool/pty_run.py --input none --out /tmp/fixed.bin -- \
    dart run packages/twk_core/test/viewport/fixed_demo.dart --seconds=3
dart run tool/replay.dart /tmp/fixed.bin 100 30

# the checks of a handover: analyze, test and format here and in every
# package, the demo end to end; the web builds run in node
dart run tool/xtask.dart handover
dart run tool/web_check.dart

# frame benchmark, AOT: the working tree against a commit, run alternately
# (pinned to one core whose SMT sibling is idle)
taskset -c 23 dart run tool/bench.dart --baseline=HEAD
# the same under the machine's bench lock, its report judged (xtask.yaml)
dart run tool/xtask.dart bench
```

`example/chat_demo.dart` is an agent-chat screen on the render tree
(`TwkApp`): a header with a spinner, the messages, the input line and a
status line with the cost of the last frame, a message coming in every
350 ms.

* Fullscreen (the default), the messages are a `RenderLog` filling the
  alternate screen. With `--inline` the header, input and status lines
  are the inline region (§1.12), and every message, from the 30 it starts
  with on, is committed to the terminal's history above it, where the
  terminal scrolls and selects it; when the demo ends the region stays on
  the screen.
* Keys: typing and Enter send a message; Ctrl+E edits the input in an
  editor; Ctrl+Y copies the input (OSC 52); q with nothing typed, Esc or
  Ctrl+C quit, as does `--seconds=N`; fullscreen, Up/Down/PgUp/PgDn and
  the mouse wheel scroll the messages (inline, the terminal scrolls its
  history).
* Ctrl+E writes the input to a file and hands the terminal to the editor
  on it (`TwkApp.suspend`); taken back, the lines left in the file are
  the input, joined by blanks. The editor is `--editor=…`, else
  `$EDITOR`, else `vi` (`notepad` on Windows), run as git runs it: by
  `sh -c '<editor> "$1"'` (through `cmd` on Windows), so a shell fragment
  that ends where the file goes is an editor too, as in the end to end
  check. An editor that exits with another status than 0 leaves the input
  as it was.
* `print` in the demo's handlers goes to the app's log (`TwkApp.logs`,
  with `TWK_LOG=path` also to that file as it comes): the messages sent
  and an editor's exit with 0. Once the terminal is restored the demo writes
  those records to stderr, after the warnings `run()` reports itself (an
  editor that failed, logged with `log(…, level: LogLevel.warning)`), and
  then its frame stats.

`tool/bench.dart` times twelve scenarios at 200×60: seven updates of an
agent-chat screen (nothing changed, the spinner, mid-line typing, a log
line, repainting every object, a full frame, one change in a tree with no
inner repaint boundary), three of a word-wrapped paragraph of Latin,
Cyrillic, CJK and emoji text that fills most of the screen (`wrap`: a word
typed into it and every line wrapped again; `ellipsis`: the same cut off
at two thirds of the rows with "…"; `pens`: a sentence highlighted, new
pens and no layout), one of a list of 100,000 items of 1 to 3 rows
built as they come into view (`list-scroll`: a row scrolled), and
decoding 2000 input events. `--only=NAME,…` picks
scenarios by the names the report gives them. Each is first run for 64
frames into the test emulator and is not timed unless the screen matches
what was painted; bytes per frame come from that run and are exact. The
report gives the median time per frame of each build, the ratio, the bytes
per frame of both, the load average and how busy the pinned core's sibling
was. `--baseline` builds the scenarios against the core of 743dca4 or a
later commit only: an older one has no `RenderParagraph` that takes
`(String, Pen)` spans. A scenario that needs a core class the baseline
lacks (`list-scroll`, `RenderList`) is left out of its build and
reported without a before.

## 5. License

MIT, copyright 2026 Andrii Ivanov: [LICENSE](../LICENSE). The third-party
material bundled here keeps its own licence, listed in [NOTICE](../NOTICE):
the Unicode data the segmentation, width and bidi tables come from
(`lib/src/unicode/tables.g.dart` and `lib/src/unicode/bidi_data.g.dart`,
which `tool/gen_unicode.dart` writes with the licence in their headers,
and `test/data/GraphemeBreakTest.txt`), under the Unicode License v3. The
repository's [NOTICE](../../../NOTICE) lists it with that of the other
packages.
