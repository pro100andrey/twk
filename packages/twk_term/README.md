# twk_term — an embedded terminal for twk

A terminal for programs run inside a twk app: what a program writes goes
in as bytes, its screen comes out as cells the core's `Canvas` draws, and
what the terminal sends back to it — answers to its queries, keys, the
mouse, pasted text — goes out as bytes. It takes [twk](../twk/README.md)
and [twk_core](../twk_core/README.md) as path dependencies, and
[twk_test](../twk_test/README.md) for its tests.

Three parts: the emulator (`lib/src/emulator/`), the pseudo-terminal the
program runs in (`lib/src/pty/`, Linux and macOS, through `dart:ffi`
alone), and the `TerminalView` widget that shows a program and gives it
the keys, the mouse, pastes, the focus and its size (`lib/src/view/`).

```dart
import 'package:twk/twk.dart';
import 'package:twk_term/twk_term.dart';

final class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

final class _ShellState extends State<Shell> {
  // started at the view's size, at its first layout
  final _session = TerminalSession.start('bash', const []);

  @override
  void dispose() {
    _session.dispose(); // hangs up: SIGHUP for bash
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TerminalView(
    session: _session,
    autofocus: true,
    ignoredKeys: const ['ctrl+q'], // left to a KeyBindings above
    onTitleChanged: (title) => log('title: $title'),
  );
}
```

`example/split_shells.dart` runs two shells side by side in a
`SplitView`: a click or Alt+1 and Alt+2 focus one, Ctrl+Q quits.

The emulator alone, for a host of its own:

```dart
final pty = Pty.start('bash', ['-l'], width: 80, height: 24);
final term = TerminalEmulator(
  width: 80,
  height: 24,
  onOutput: pty.write, // answers, keys, mouse reports, pasted text
  onEvent: (event) => switch (event) {
    TitleChanged(:final title) => window.title = title,
    // any program in the terminal may send one, over ssh too: ask, or
    // take it only from a program the user trusts
    ClipboardWrite(:final text) when allowClipboard() => clipboard.set(text),
    BellRang() => flash(),
    _ => null,
  },
);
pty.output.listen(term.feed); // what the program writes
term.paint(canvas, x: 0, y: 0); // its screen, in a widget's paint
term.sendKey(const KeyEvent(KeyCode.up)); // in the program's modes
```

## What it emulates

xterm's dialect, permissively: a sequence it doesn't know is ignored
(`strict: true` makes it a `FormatException`, for tests).

- **Screens**: the primary one with a scrollback (`scrollbackLimit` lines,
  1000 by default; lines scrolled off its top, by text or SU, while the top
  margin is its first row) and the alternate one (modes 47, 1047, 1049 with
  the cursor saved and restored), which keeps none.
- **Text**: UTF-8 (a malformed sequence printed as U+FFFD, a character
  split between writes put together), split into cells by the core's
  `TextSegmenter` — code point by code point like wcwidth by default, by
  grapheme clusters with `textMode: TextMode.graphemes` or once the
  program sets DEC mode 2027. Two-column glyphs take a leading and a
  trailing cell; overwriting either half blanks the other. A combining
  mark, a variation selector or the rest of an emoji sequence joins the
  cell left of the cursor, also when it comes in a later write; a VS16
  that makes it two columns wide widens it. Autowrap with a pending wrap
  (DECAWM; a two-column glyph that doesn't fit in the last column wraps
  whole), insert mode (IRM), LNM, REP.
- **Cursor**: CUP, HVP, CUU, CUD, CUF, CUB, CNL, CPL, CHA, HPA, HPR, VPA,
  VPR, IND, RI, NEL, CR, LF, VT, FF, BS, HT, CHT, CBT, HTS, TBC, DECSC,
  DECRC, SCOSC, SCORC, origin mode (DECOM), its visibility (DECTCEM),
  blinking (12) and shape (DECSCUSR).
- **Editing**: ED (3 clears the scrollback), EL, ECH, ICH, DCH, IL, DL,
  SU, SD, DECSTBM, DECALN; erased and scrolled-in cells take the current
  background (BCE). DECSED and DECSEL as ED and EL.
- **Attributes**: SGR bold, dim, italic, underline in its styles (`4:0`
  to `4:5`, 21 double), blink, reverse, hidden, strike, overline; the 16
  colors and their bright forms, 256 and 24-bit ones with `;` and `:`
  (`38;5;n`, `38;2;r;g;b`, `38:2::r:g:b`, `38:2:r:g:b`), and underline
  colors (58, 59). Reverse video of the whole screen (DECSCNM) is applied
  when it is painted.
- **Character sets**: G0 to G3 designated as ASCII, DEC special graphics
  or UK, SO, SI, SS2, SS3, LS2, LS3.
- **Modes the host acts on** (see below): DECCKM, DECKPAM/DECNKM, the mouse
  (X10 9, 1000, 1002, 1003; UTF-8 1005, SGR 1006, urxvt 1015), focus
  (1004), alternate scroll (1007), bracketed paste (2004), synchronized
  output (2026). XTSAVE and XTRESTORE, DECSTR, RIS.
- **Keys**: xterm's (`keySequence`), or the kitty keyboard protocol's once
  the program set its flags (`kittyKeySequence`): `CSI > flags u`
  pushes them, `CSI < n u` pops, `CSI = flags ; mode u` sets, ors or
  and-nots them, `CSI ? u` asks (`CSI ? flags u`); a stack of 16 for each
  screen, which RIS empties. Disambiguated keys, event types (repeats and
  releases), alternate keys (the capital of a letter typed with Shift),
  all keys as escape codes and their text, as kitty sends them.
- **Answers**: DA1 (`CSI ? 62 ; 22 ; 52 c`), DA2, DA3, XTVERSION
  (`twk_term 0.1.0`), DSR 5 and 6, DECXCPR, DSR 15, 25, 26 and 996 (the
  color scheme, from the background), DECRQM for every mode it knows (0
  for those it doesn't, 4 for 132 columns, smooth scrolling, reverse
  wraparound and xterm's meta and keypad variants), DECRQSS for SGR,
  DECSTBM, DECSCUSR, DECSCL and DECSCA, XTGETTCAP (no capability is
  told), XTWINOPS 14, 16 (once the host has set `cellPixelWidth` and
  `cellPixelHeight`), 18 and 19, OSC 4, 10, 11 and 12 queries, ended as
  the query was (BEL or ST); of OSC 4, the first 256 queries of a
  sequence, so that its replies are not many times its length.
- **OSC**: titles and icon names (0, 1, 2, with the title stack of
  XTWINOPS 22 and 23), the palette (4, 104), the default colors (10, 11,
  12 and their resets), the working directory (7, a `file:` URI only),
  hyperlinks (8, kept in the cells' styles, a URI of at most 2083
  characters, VTE's limit; an erase takes them), notifications (9, 777) and
  progress (9;4), shell prompts (133), the pointer shape (22), the
  clipboard (52) — handed to the host as events, none executed.

Not spoken: left and right margins (DECLRMM, reported unknown, so
programs don't use them), double-width and double-height lines (drawn single), 132 columns, sixel and other images
(their strings skipped), rectangle operations (DECFRA, DECERA, …), C1
controls as single bytes (in UTF-8 they are parts of characters; as
characters they print nothing).

### Resizing

`resize` rewraps the primary screen and its scrollback: lines the
program's text wrapped are joined and split again at the new width (a
two-column glyph never cut), the cursor staying on the character it was
on, a wrap pending where it ends up past the last column. The screen then
shows the last lines with the cursor's among them: the blank rows below
the cursor go first, then lines go to the scrollback when it gets shorter,
and come back from it when it gets taller. The alternate screen, which
its program redraws on SIGWINCH, is cut or padded, keeping the cursor's
row. The margins are reset, the tab stops extended.

## The host interface

What the pseudo-terminal and the view need, and nothing they don't:

- **In**: `feed(bytes)` with each read from the program; a sequence or a
  character may be split anywhere between reads.
- **Out**: `onOutput(Uint8List)` with every byte for the program, written
  to it in order: answers come during `feed`, input when the host calls
  `sendKey` (as `KeyEvent`s of the core, in the program's kitty flags,
  `keyboardFlags`, or else its DECCKM and LNM),
  `sendText`, `sendPaste` (bracketed in mode 2004, line breaks as CR, an
  end marker inside taken out), `sendFocus` (false when mode 1004 is off),
  `sendMouse` (cell coordinates; false when the program doesn't track the
  mouse — the host's for selection and the scrollback then — except the
  wheel going as arrow keys on the alternate screen in mode 1007) and
  `answerClipboard` after a `ClipboardRead`.
- **Events**: `onEvent(TerminalEvent)`, during `feed`, in the order asked:
  `TitleChanged`, `IconNameChanged`, `BellRang`, `ClipboardWrite`,
  `ClipboardRead`, `ModeChanged` (every mode that changes, the ones that
  change what the host sends or shows among them), `CursorShapeChanged`,
  `WorkingDirectoryChanged`, `NotificationRequested`, `ProgressChanged`,
  `PromptMarked`, `ColorsChanged`, `ResizeRequested`,
  `PointerShapeChanged`.
- **The screen as cells**: `line(y)` (`TerminalLine`: per column a glyph
  word — a `GlyphTable` id with `kWide`, `kCont` and `kUncertain` as a
  `Surface` keeps them — and a `StyleTable` style id; `wrapped` where the
  text runs on), `scrollbackLine(i)`, `cellAt`, `cellText`, `styleAt`,
  `lineText`, `text`; `styles` and `glyphs`, the tables the ids are in
  (a host can pass its canvas's own, so the cells copy as they are).
  `paint(canvas, x:, y:, scrollOffset:)` draws the screen with a
  `Canvas` — its translation and clip apply, pens and glyph ids are
  carried over to the canvas's tables once each, `scrollOffset` lines
  back in the scrollback, the program's default text color and
  background in `fg:` and `bg:` (the host terminal's own by default; the
  emulator's state untouched); `paintLine(canvas, line, x:, y:, fg:,
  bg:)` one row, or a copy of one. The cursor is left to the view: `cursorX`, `cursorY`,
  `wrapPending`, `cursorVisible`, `cursorShape`, `cursorColor`.
- **What moved**: `onScrolled(top, bottom, n)` as rows of the screen shown
  move (a line feed at the bottom margin, IND, RI, SU, SD, IL, DL), so a
  view moves what it painted of them instead of painting them again;
  `scrollbackAdded`, the lines that have gone into the scrollback, by
  which a view scrolled back keeps its lines in place.
- **State**: `mode(TerminalMode)`, `mouseProtocol`, `mouseEncoding`,
  `alternateScreen`, `margins`, `title`, `iconName`, `workingDirectory`,
  `palette`, `foregroundColor` and `backgroundColor` (the program's, or
  the host's `defaultForeground` and `defaultBackground`, which OSC 10
  and 11 report and CSI ? 996 n's dark or light is of: `TerminalView`
  keeps them at the colors it paints the defaults in).
- **Size**: `resize(width, height)`; `Pty.resize` tells the program
  (TIOCSWINSZ, SIGWINCH).

While `TerminalMode.synchronizedOutput` is set the program is drawing a
frame: a view shows the screen as it was until the mode is reset (or a
timeout passes).

## The pseudo-terminal

`Pty.start(executable, arguments, width:, height:, workingDirectory:,
environment:, includeParentEnvironment:)` runs a program in a new
pseudo-terminal; a `ProcessException` when it can't (no such program, no
such directory), an `UnsupportedError` off Linux and macOS. On the web the
`Pty` is a stand-in whose `start` throws, so that an app with a
`TerminalSession` over a link of its own (a scripted shell, a remote one)
compiles for the browser too (`tool/web_check.dart`'s gallery case).

- **The program's terminal**: the program leads a session of its own with
  the pseudo-terminal as its controlling terminal and its process group in
  the foreground, so `tty` names `ttyName` and `/dev/tty` opens, Ctrl+C,
  Ctrl+Z and Ctrl+\ written to it are signals to that group, and a shell
  runs jobs. Its descriptors 0, 1 and 2 are the terminal, nothing else is
  inherited; every signal is at its default (the VM's ignored SIGPIPE
  isn't passed on) and none is blocked. IUTF8 is set, so the line
  discipline erases a UTF-8 character whole.
- **Its environment**: this process's (unless `includeParentEnvironment`
  is false) with `TERM=xterm-256color`, the dialect the emulator speaks,
  and `environment` over both; an executable without a slash is looked for
  in that PATH.
- **Out**: `output`, a single-subscription stream of what the program
  writes, in pieces of up to 64 KiB. While it isn't listened to or is
  paused, the terminal is read no further and the program blocks in its
  writes, as with a terminal that scrolls no more. It ends when the
  terminal hangs up: the program and whatever it left running closed it,
  or `close` was called.
- **In**: `write(bytes)`; what the terminal doesn't take now (the program
  isn't reading) waits, in order.
- **Size**: `resize(width, height)` sets what the program reads with
  TIOCGWINSZ; its foreground group gets SIGWINCH.
- **The end**: `exitCode`, the program's exit code or the signal that
  killed it negated, as `dart:io`'s `Process.exitCode`; it can come
  before `output` ends, while something the program left running still
  writes. `kill(signal)` signals the program, `close()` hangs the terminal
  up as closing its window does (SIGHUP for the program and its
  foreground job). A signal goes through the pidfd made with the program
  where there is one (`pidfd_send_signal`, glibc 2.36), which reaches
  that process and no other, else to its `pid` only while that is
  positive: `pid` is -1 for a program that ended before its id was read
  (the VM may reap it first), and kill(2) with -1 would signal every
  process of the user. Nothing waits on a `pid` that is not positive.

`twk record` of [twk_dev](../twk_dev/README.md) runs the command it
records in a `Pty`.

The child is made with `posix_spawn` (`pidfd_spawn` where glibc has it,
2.39), never by forking the VM, whose other threads would leave a forked
copy only async-signal-safe calls — and the VM runs Dart code between any
two FFI calls. The spawn attributes start a new session
(`POSIX_SPAWN_SETSID`: glibc 2.26; macOS has it too) and reset the signals;
the file actions open the slave as descriptor 0 — the session's leader
opening a terminal without `O_NOCTTY` makes it its controlling one, with
its process group in the foreground, so no `TIOCSCTTY` (which would need
code in the child) is needed — duplicate it to 1 and 2, change the
directory and close the rest (`addclosefrom_np`, glibc 2.34;
`POSIX_SPAWN_CLOEXEC_DEFAULT` on macOS). macOS performs the file actions
before it makes the new session, so its slave becomes no controlling
terminal there (Ctrl+C would signal nothing, a shell run no jobs, the
hang-up send no SIGHUP): the program is spawned through `/bin/sh`, the
session's leader by then, which opens the slave again, making it the
controlling terminal, and execs the program through `env -i`, in the
environment given and with its name as `argv[0]`, the pid the program's
along the way. An isolate of its own polls the
master (non-blocking) and a pipe the main isolate tells it through (output
taken, a write waiting, closed), and waits for the program's end.

The VM waits for *any* child (`waitpid(-1)`) while a `dart:io` `Process`
it started runs — the test runner's compiler does throughout — and may so
take the program's end first. Linux 6.15 and later still tell it through
the pidfd made with the program (`PIDFD_INFO_EXIT`); elsewhere `exitCode`
is null then. macOS revokes a session's controlling terminal once its
leader ends: a descriptor of the slave reads nothing more, and what the
program left running writes to it no more; `modesAtEnd` keeps the
terminal's attributes as the program left them, read through the master.
Tested on Linux (x86-64, glibc 2.44, Linux 7.2) and macOS (arm64, macOS
26.6); macOS's exit codes taken by the VM would need kqueue's
`NOTE_EXITSTATUS`.

## The view

`TerminalSession` is a program and the emulator of its terminal: what the
program writes is fed to `emulator`, what the emulator sends goes to the
program, its listeners are told after each piece of output and when the
output `ended`. `TerminalSession.start(executable, arguments, width:,
height:, workingDirectory:, environment:, includeParentEnvironment:,
scrollbackLimit:, textMode:)` runs it in a `Pty`, at once at the size
given or, without one, at the first `resize` — which the first layout of
a view showing it calls, so the program never sees another size (a
shell that started at 80 columns and was resized at once may print its
first prompt for 80); what that start throws is `error`, logged, and the
session has ended. `TerminalSession(output:, input:, onResize:)` is a
program over any other byte link. `events` is a broadcast stream of its
`TerminalEvent`s, `exitCode` its exit code, `title` its title;
`dispose` hangs a pty up (SIGHUP) — a program that ignores it is the
app's to `pty.kill`.

`TerminalView(session:, focusNode:, autofocus:, ignoredKeys:, wheelLines:,
defaultStyle:, onTitleChanged:, onBell:, onClipboardWrite:, onClipboardRead:, onEvent:)`
shows the session's screen and is its terminal:

- **Size**: it takes all the room it gets (along an axis without a bound,
  the terminal's size) and resizes the session to it at each layout:
  SIGWINCH for the program.
- **Keys**: while it has the focus every key goes to the program
  (`sendKey`), Tab, Escape and Ctrl+C among them, except `ignoredKeys`
  (named as `KeyBindings` names them, `'ctrl+q'`), which go up to the
  nodes above, as do releases the program doesn't hear of. So Tab does
  not move the focus out of it: a click elsewhere, or a binding of an
  ignored key, does. A key brings a view scrolled back to the screen.
- **Pastes** go as typed, bracketed in mode 2004.
- **Focus**: the program is told (mode 1004) when the view gains or loses
  the focus, and when the app's terminal does.
- **Mouse**: a press focuses the view. While the program tracks the mouse
  it gets presses, releases, the wheel and, as its mode asks, motion, in
  the view's cells — the app's terminal reports motion only while a
  program wants it. Otherwise the wheel scrolls the scrollback
  `wheelLines` lines (3), or on the alternate screen sends as many Up or
  Down keys. Output while scrolled back leaves the lines shown in place.
- **Default colors**: the program's default text color and background
  are painted in `defaultStyle`'s `fg` and `bg` — by default the
  `Theme`'s text on its background, so the terminal is of a piece with a
  themed app (`Color.defaultColor` for the app's terminal's own). They
  are what the program is told when it asks (OSC 10, 11, and CSI ? 996 n
  for dark or light): a program choosing its colors by the background
  (vim's `background`, a `light` or `dark` theme) chooses them for the
  one it is shown on. A palette color is told as the emulator's
  `palette` has it, the app's terminal's default as the app learnt it
  (its text color only where it told it).
- **Cursor**: the terminal's cursor shows the program's, in its shape
  (DECSCUSR; its default, 0, is the app's terminal's own, whatever its
  user set — a block in the gallery design, which stands in for it), while the view has the focus, the program shows it and it
  is in view. The view places it with twk's `showCaret` and `hideCaret`,
  as a `TextField` does its caret, so a focus moving between fields and
  views within a frame leaves it at the one with the focus.
- **Synchronized output**: while the program draws a frame in mode 2026,
  the view shows the frame before, until the mode is reset or 150 ms
  passed.
- **The program asks** for a title, the bell, the clipboard: the callbacks
  are told (`onEvent` every event first); `onClipboardRead` answers with
  what it returns or completes with. Nothing is done without them.
- **Painting**: a repaint boundary that keeps a copy of each row as it
  painted it and paints only the rows that changed; rows the program
  scrolled (and those the wheel scrolled) move on the surface first
  (`Surface.scrollRect`), which the presenter replays as a hardware
  scroll (DECSTBM and SU or SD; with DECSLRM for a view narrower than the
  screen where the terminal has it), and the rows the move exposed are
  painted. Colors the program set with OSC 4, 10 and 11 are reported back
  but not applied: cells keep palette indices, drawn in the app's
  terminal's palette, and the defaults in the view's. No
  selection with the mouse yet.

## Tests

Sequence by sequence, vttest's screens (cursor movements with a border of
`*`s and `+`s around a frame of `E`s, autowrap mixed with controls), and
the output of real programs captured in an 80x24 pseudo-terminal with
`tool/pty_run.py` and checked as screens: a bash session, nano editing a
file (vim isn't installed where they were captured), less paging and
searching, a few htop frames, `git log --graph --color` and the core's
chat demo; each fed in pieces of every size gives the screen fed whole.

The pseudo-terminal runs real programs (`sh -c`, `cat`, `bash -i`,
`stty`, `tput`, `head`, `od`, `env`, `ls`): their output with the CR the
terminal adds, their exit codes and signals (also those the VM waited for
first), the controlling terminal, Ctrl+C, Ctrl+Z and `fg`, SIGWINCH and
the new size, the signals at their defaults, the environment, TERM and the
directory, IUTF8, input larger than the terminal takes, output held back
while paused, the hang-up, what a background job writes after the
program's end, the inherited descriptors, and the emulator fed by a
program it answers. `test/pty/signal_test.dart` checks, with stand-ins
for the system, that a signal goes through the pidfd where there is one
and never to a pid that is not positive.

The view (`test/view/`) over a link of the test's own: the screen in its
styles, its size told to the program, the rows painted (only those that
changed), the hardware scroll of the rows a program scrolls (with a
status line below its margins too), synchronized output and its timeout,
the scrollback under the wheel and kept in place by output, the wheel on
the alternate screen, keys in the program's modes (DECCKM, kitty), the
ignored keys, pastes, the mouse while tracked (motion only when asked),
the focus of two views and of the app's terminal, the cursor and its
default shape, the default colors (the theme's, `defaultStyle`'s, and
what OSC 10, 11 and CSI ? 996 n answer), the callbacks, the end of the output and a program that could not start. And
real programs through `testTwk`, in pseudo-terminals: `sh` (a command,
`stty size` before and after a resize, Ctrl+C, a bracketed paste, `exit
3`), `less` (pages, DECCKM's Down, the wheel as Down keys, a search, q),
`nano` (typing, Ctrl+O and Ctrl+X, the file written), `htop` (its
meters, the mouse it takes, q), and scripts reading raw what the keys and
the mouse send (DECCKM, the kitty protocol, SGR reports of a press, a
drag and a release). vim is not installed where they run. Each program
is killed and waited for in its tear-down, and at the end `ps` shows none
of them left.

```bash
dart pub get
dart test
```

## Speed

`tool/feed_bench.dart` feeds a capture (or 10 MiB of its own) in pieces of
64 KiB, as reads from a pseudo-terminal come:

```bash
python3 ../../tool/pty_run.py --input none --size 120x40 \
    --out /tmp/cat.bin -- cat big.txt
taskset -c 21 dart run tool/feed_bench.dart /tmp/cat.bin
```

`cat` of 10 MiB of this repository's sources and READMEs (200 000 lines,
10.2 MiB with the CR the tty adds) takes about 70 ms on one core, some
140 MiB/s, at 120x40 with 10 000 lines of scrollback.

## License

MIT, copyright 2026 Andrii Ivanov: [LICENSE](LICENSE).
