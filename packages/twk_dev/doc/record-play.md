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

`--marker-key=ctrl+]` (any `ctrl+<letter>`, or `[ \\ ] ^ _`; not Ctrl+C, I, J,
M or `[`, which the terminal needs, nor Ctrl+H (Backspace on many terminals),
D (end of input), S and Q (flow control) or Z (suspend); off by default, so no key of the app is
taken) makes that key leave a marker instead of reaching the command: an `m`
event at its time, labelled `marker 1`, `marker 2` and so on, for `twk play`
to go to (`--keys` does not record the key). It is read as the plain byte:
where the app turned the kitty keyboard flags on, the terminal sends the key
as another sequence, which reaches the command. A recording can also have
markers from elsewhere (the VS Code extension's, a hand-edited file); `twk
play` takes any `m` event.

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
Right goes a frame on, Left a frame back, `]` goes to the next marker and `[`
to the one before (each marker is a stop, also several on one step and one at
the start; paused, the screen as at the marker's place among the
events: the frames before it written at once, as Left does; none before the
first or after the last marker stays where it is), Home plays from the start,
`q` quits (exit 0, with what the recording left on turned off as Ctrl+C does). A
frame is what `screenFrames` takes for one: the output up to where no
synchronized update (DEC 2026) is open, written in one piece, so an update is
never shown half; output after the last frame, inside an update never ended,
is a step of its own that counts for no frame. Back is the terminal reset
(RIS) and the frames before written at once. Paused, a status line
(`paused  frame 3/12  1.250 s / 4.000 s  marker 2/5 label`; the marker is the
last at or before the screen shown, `marker 0/5` before the first, and the
part is left out of a recording without markers; a label is cut to 40
characters, its control characters blanked; the whole line is cut to the
terminal's width, wide glyphs counted) shows on the row under the
recording, where the terminal has one (a recording as tall as the terminal
has no room: nothing is drawn); it is not part of what is played, and is
wiped when playing goes on or it stops. It is drawn with `ESC 7` and
`ESC 8`, the terminal's one saved cursor, so a recording that saved its own
cursor before a pause and restores it after finds the status line's. Keys are
read also as application-cursor and kitty-keyboard sequences; the terminal's
answers are not keys; a key release (kitty event type 3) is none, and Ctrl+C
quits wherever it comes, an Escape at the end of a read is dropped, and an
Alt+letter that starts a string (`ESC P`, `ESC ]`) swallows the keys after it
only until the next read, or 500 ms: the trade-off is that a terminal's
answer and Alt+key cannot be told apart by their bytes, so time decides. What
is held (the start of an escape sequence or string) is dropped after 500 ms,
checked at every read and on the player's clock too, and what comes after
is keys; so an answer whose rest arrives later than that (a slow link) has
its tail read as keys (`[`, `]`, Space), and Alt+key followed by another key
within 500 ms is not read as the second key. Played to its last step, the recording stays there
paused (status line shown) while keys are read: Space plays it again from the
start, Left goes back, `q` quits. Where stdin is no terminal there are no
keys, and it exits at the end.

## What a recording keeps of the input, and `--replay`

With `--keys` a recording has an `i` event for each read of the terminal's
input, whatever it holds, which is two kinds of bytes: the keys, mouse
reports, focus changes and pastes of the person, and the answers of the
terminal to the queries the app wrote (mode reports to `CSI ? … $ p`, device
attributes, the cursor position, colours, the terminal's name, the kitty
flags, the size). Nothing in the event tells them apart, and one event can
hold both, so they are told by their shape (`InputSplitter`): an answer is a
sequence a person's keys never make, namely `CSI ? … c`, `CSI > … c`,
`CSI = … c`, `CSI … $ y`, `CSI ? … u`, `CSI ? … R`, `CSI … n`, `CSI … t`, or
a string (OSC, DCS, APC, PM, SOS) up to its terminator; everything else is a
key, `CSI A`, `CSI … ~`, kitty's `CSI … u` (it has no `?`), SS3, focus
(`CSI I`, `CSI O`), the mouse (`CSI < … M`), and a paste with whatever is
inside it. One shape is both: `CSI row ; column R` answers `CSI 6 n` and is
the modified F3 (`CSI 1 ; 2 R`) too; it is an answer once the output has the
query and none has been answered since it, a key otherwise. An Alt+letter
that opens a string (`ESC ]`, `ESC P`) looks like the start of an answer: with
no terminator it is taken for keys at the end. A recording made without
`--keys` has no input to replay, and the resizes (`r`) are not replayed: play
it in a terminal of its size.

```bash
dart run packages/twk_dev/bin/twk.dart record --out=again.cast --keys \
    --replay=s.cast --replay-speed=asap --replay-then=handover -- \
    dart run packages/twk/example/counter.dart
```

`--replay=<file>` types the keys of a recording (the answers left out: this
terminal answers the app's queries itself, as it did) into the command, and
records the session as usual. Once the command has written, the keys are typed
either

- `--replay-speed=<factor>` (1 by default) at their recorded times divided by
  the factor, counted from the command's first output (the recording's times
  already have their pauses cut to the idle limit); or
- `--replay-speed=asap`, each once the command has written nothing for 100 ms
  and, when the recording shows the app wrote after the key before the next,
  has answered the last key (waited for 2 s at most). Without it three keys
  typed in a row reach an app that has not drawn for the first.

Meanwhile this terminal's own keys are dropped, but the terminal's answers
to the command's queries and Ctrl+C. After the last key `--replay-then`
decides: `handover` (the default) gives the terminal to the command, as
`twk record` does (the person goes on from the screen the recording
reached, to look at it or to reproduce the rest), `end` hangs the command up
once it has written nothing for a second and exits 0, a recording of the
replay made for a test. The command's own exit, Ctrl+C or a signal end it as
always. `--replay-speed` and `--replay-then` without `--replay`, a replay
that can't be read or a speed that is no number above 0 (or `asap`) exit with
64.

Without a causal sync with the app (a driver that says when the app has
consumed a key and drawn the frame it makes), "as fast as the app takes them" is
a guess: the quiet of the output and the reaction the recording shows. An
app that is slow to start, writes late after a key, or redraws without one
(a clock) can be typed at too early or late; a recorded time is exact but the
app's pace is not the recording's. A driver would make each key wait for the
frame the previous one produced, rather than for a pause, and would tell the
very start (the app is reading input) from a silence.

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

`twk test-from-cast <file.cast> [--out=<file>] [--no-goldens]` writes that
test: it copies the recording to `test/<name>.cast` (beside the test, which is
`test/<name>_test.dart` unless `--out` names it; a recording already there is
not copied onto itself) and writes the test over `Cast.read` and
`screenFrames`. It checks that the emulator took in all of it
(`frames.last.errors` is empty) and, for each marker of the recording (`m`
events), that the screen shown at its time (the last frame where there are no
markers) is the screen file `test/goldens/<name>/<k>.txt` (`last.txt`), by
`matchesScreenFile`, which takes a `ScreenFrame` of
`screenFrames(screens: {…})`. The generator emulates nothing: the test finds
the frame itself, and the command runs it once with `TWK_UPDATE_GOLDENS=1`
(`dart test` in the project, 90 s at most) so that the emulator that checks
the screens writes them; it says which files. Review them, and commit them
with the test. It ends with 0, 1 for a recording it cannot read, files it
cannot write, a project without a twk_test dev dependency or a run that
fails (the test and the recording are left for you; `--no-goldens` skips the
run), 64 for no recording. The same function, `castTestSource`, is what an
editor's command calls through this one.
