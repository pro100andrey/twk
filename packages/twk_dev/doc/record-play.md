# `twk record` and `twk play`

```bash
dart run packages/twk_dev/bin/twk.dart record --keys --out=s.cast -- \
    dart run packages/twk/example/counter.dart     # from the repository's root
dart run packages/twk_dev/bin/twk.dart play --speed=2 s.cast
```

`twk record` runs `<command>` in a pseudo-terminal (twk_term's `Pty`) of this
terminal's size, with this terminal's `TERM` and `CI=false` (a twk app in CI
writes plain text, which a terminal is not), and passes this terminal through
to it until the command ends: raw mode (`cfmakeraw`, through `dart:ffi`), so
every byte typed reaches the command as it is, Ctrl+C and Ctrl+Z included, and
what the command writes comes out unchanged; a change of this terminal's size
resizes the command's. Options go before `<command>`; what follows it is the
command's, `--` or not. The recording, `--out` (`session.cast` by default), is
written as the session goes, so one cut short is read up to there:

```text
{"version":2,"width":100,"height":30,"timestamp":1792427943,"idle_time_limit":2.0,"command":"dart run example/tally.dart","title":"dart run example/tally.dart","env":{"TERM":"xterm-256color","SHELL":"/usr/bin/zsh"}}
[2.000000, "o", "\u001b[?2026$p…"]
[2.009538, "i", "\u001b[?2026;2$y…"]
[3.512113, "r", "120x40"]
```

an `o` event for each piece the command wrote, an `i` event for each piece
typed with `--keys` (the terminal's answers to the app's queries among them),
an `r` event for each change of size, at its time since the start: a pause
longer than `--idle-limit` seconds (2; 0 keeps each) is cut to it, and the
header says so (`idle_time_limit`). UTF-8 is decoded a stream each, a
character split between two pieces put together. The header has the size, the
time, `TERM` and `SHELL`, the command line and `--title` (the command line by
default).

It ends with the command's exit code, once the command has ended and its
terminal hung up (what it left running is hung up 2 s after it ended); with
128 and the signal's number on SIGINT, SIGTERM or SIGHUP, which hang the
command's terminal up (SIGKILL after 2 s more). Then the terminal is put back:
what the command left turned on — the alternate screen, mouse or paste
reports, a hidden cursor, autowrap off, kitty keyboard flags, a cursor shape —
is turned off (written to the terminal, not to the recording), and the modes
raw mode changed are restored, also when the recording failed (a write to the
file did: the command is hung up, exit 1). Stopped (SIGSTOP, SIGTSTP from
elsewhere: Ctrl+Z goes to the command) it can't put the terminal back, which
the shell does as it takes it; continued, SIGCONT can't be watched from Dart,
so the terminal's modes are checked every 200 ms and raw mode is entered again
once they changed. No command, or an `--idle-limit` that is no number, exits
with 64; a recording that can't be written with 1, a command that can't be
started with 127, neither leaving a file. Without a terminal it records at 80
by 24 and passes stdin on.

`twk play` writes what the program wrote (the `o` events) at its times divided
by `--speed`, a pause longer than the idle limit (the header's, or
`--idle-limit`; 0 plays each) cut to it; the terminal is not resized, so a
recording plays in a terminal of its size. Raw mode meanwhile, so what is
typed is not echoed, but dropped, as are the terminal's answers to the queries
the recording has; Ctrl+C stops (exit 130; 128 and the number on SIGINT,
SIGTERM, SIGHUP), turning off what the recording left on. At the end it waits
100 ms for answers still on their way and drops what was not read
(`TCSAFLUSH`), so none reaches the shell. A recording it can't read, or that
is not asciicast v2, exits with 1; no file, or a `--speed` not above 0, with
64.

While it plays: Space pauses and plays on (from the start once it ended),
Right goes a frame on, Left a frame back, Home plays from the start, `q`
quits (exit 0, with what the recording left on turned off as Ctrl+C does). A
frame is what `screenFrames` takes for one: the output up to where no
synchronized update (DEC 2026) is open, written in one piece, so an update is
never shown half; output after the last frame, inside an update never ended,
is a step of its own that counts for no frame. Back is the terminal reset
(RIS) and the frames before written at once. Paused, a status line
(`paused  frame 3/12  1.250 s / 4.000 s`) shows on the row under the
recording, where the terminal has one (a recording as tall as the terminal
has no room: nothing is drawn); it is not part of what is played, and is
wiped when playing goes on or it stops. It is drawn with `ESC 7` and
`ESC 8`, the terminal's one saved cursor, so a recording that saved its own
cursor before a pause and restores it after finds the status line's. Keys are
read also as application-cursor and kitty-keyboard sequences; the terminal's
answers are not keys. Where stdin is no terminal there are no keys.

A recording is a regression test of the app: its `Cast.writes`, the output
events and each resize, are what twk_test's `screenFrames` plays through its
emulator (`Vt`) of the recording's size, a resize keeping what the screen
shows, as xterm does. It gives a `ScreenFrame` after each output that leaves
no synchronized update (DEC 2026) open: its time, size, rows, the cursor, and
what the emulator could not take up to it. twk_dev and twk_test import nothing
of each other; an app's tests take both, as `twk create` writes them.

```dart
final cast = Cast.read('test/tally.cast');
final frames = screenFrames(
  cast.header.width,
  cast.header.height,
  cast.writes,
);
expect(frames.last.lines[1], startsWith('│ › coffee     1 ■'));
expect(frames.last.errors, isEmpty);
```
