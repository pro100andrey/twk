# Layout and tests

For those who work on the package. The [README](../README.md) is where to
start with using it.

`bin/twk.dart` only sets the exit code from `runTwk` in `lib/src/cli.dart`,
which builds the subcommands with `package:args`; `lib/src/shell.dart` and
`lib/src/logs.dart` are two commands over twk_core, and `lib/src/run.dart` is
`twk run`, a client of the app's VM service (`package:vm_service`). `twk
inspect` is `lib/src/inspect.dart`, the command and `RunningApps`, the apps
found by the service file; `lib/src/app_client.dart`, `AppClient`, what the
inspector asks an app, and `VmAppClient`, over the VM service; and
`lib/src/inspector_view.dart`, `InspectorView`, the screen, on twk. `twk
create` is `lib/src/create.dart`, over mold's `Unbundler`; its templates are
packages in `templates/`, packed by `tool/pack_templates.dart` into
`lib/src/templates/`, which `templates.dart` names. `twk record` is
`lib/src/record.dart`, over twk_term's `Pty`; `twk play` `lib/src/play.dart`;
both write and read asciicast v2 with `lib/src/cast.dart` (`Cast`,
`CastWriter`, exported by `package:twk_dev/twk_dev.dart`), put the terminal in
raw mode with `lib/src/raw_tty.dart` and turn off what the output left on with
`lib/src/modes.dart`. `twk tape` is `lib/src/tape.dart`, the command,
`TapeRunner` (its pauses those of a `TapeClock`, the real time by default) and
`redraw`, over twk_term's `Pty` and `TerminalEmulator`; its language is
`lib/src/tape/script.dart`, its themes `theme.dart`, the SVG `svg.dart`
(`screenSvg`, `SvgFilm`) and the characters it draws as shapes `glyphs.dart`.
`example/tally.tape` is the walkthrough's app recorded. `example/tally.dart`
is the walkthrough's app.

`test/command_test.dart` runs `dart run twk_dev:twk` the way a developer does,
and `runTwk` in the test's process where a command does not get as far as the
terminal: `--help` must list exactly the eight subcommands, `twk inspect` with
two addresses must exit with 64, with one nothing answers at and without a
terminal with 1, `twk run` without a file must exit with 64 and with a file
that is not there with 1, `twk shell` without a terminal must say so and exit
with 1, `twk record` and `twk play` must exit as above on what they can't do,
`twk record` without a terminal record at 80 by 24, `twk tape` exit as above
on what it can't do (a statement there is not with its line), and an unknown
subcommand must exit with 64. `test/tape_test.dart` parses a tape of every
statement, the errors with their lines, the times and the themes; draws a
known screen as a still SVG, to the byte (runs of a style, a background, box
lines, a wide character, escaping), the theme's colours, a reversed cell, dim
text, blocks and the cursor; plays frames at their times, a row drawn once, a
frame within the gap taking the last one's place and one that shows the same
none; and draws a screen with `redraw` into a second emulator, which must then
show the same cells in the same styles, the cursor and the alternate screen.
`test/tape_run_test.dart` runs tapes in a pseudo-terminal: typed at the typing
speed through `cat`, a Sleep, the time between a Hide and its Show cut and the
screen drawn at the Show, the animation's frames at the recording's times,
these on a clock that moves by the tape's pauses alone, so that the times are
the tape's however loaded the machine; a Wait for the screen and for the
cursor's line, one that times out failing with the screen and writing nothing;
a tape stopped ending at once; the program gone after each; keys encoded as
the program's modes want them; and the walkthrough's app through a tape, its
recording played through twk_test's `screenFrames` to the screen it showed,
its screenshot and animation written. `test/record_test.dart` runs `twk
record` in a pseudo-terminal (twk_term's `Pty`) shown by twk_term's emulator,
which answers the app's queries, the tty's modes read and set through a
descriptor the test holds (`test/terminal.dart`): the walkthrough's app
recorded with `--keys`, counted and resized, must give the header, the keys,
the resize and pauses of 2 s at most, the tty must be raw meanwhile and as
before at the end, and the recording's last frame must be the screen the
terminal showed; without `--keys` no `i` event, the command's exit code the
command's; what a command left on turned off but not recorded; a recording
that can't be written (a FIFO whose reader went away) must end with 1 and the
tty put back, as must SIGTERM with 143; stopped, the tty put back by the test
as a shell does, and continued, it must be raw again. `test/play_test.dart`
plays recordings written by the test so: the `o` events alone, at their times
by `--speed` with the pauses cut; Ctrl+C stopping with 130 and what was left
on turned off; what is typed meanwhile not reaching the shell after it.
`test/cast_test.dart` reads and writes asciicast v2 (the pauses cut, a
character split between two pieces), follows the modes an output leaves on,
and plays recordings through the emulator, a frame each. `test/run_test.dart`
runs `twk run` on an app of a package it makes in a temporary directory, which
draws on a terminal in memory and writes each frame to stdout as base64 for
the test's emulator, its stdin the terminal's input: an edit of `lib/` and of
the app's `main`, one saved by a move, must show with the count kept, Ctrl+G h
must reload a file not watched, a syntax error must open the console with the
compiler's error while the app goes on, Ctrl+G H must start the app again and
the new one be reloaded; the arguments after the file must reach the app, and
a change made while it starts must be reloaded once its binding runs; an app
that does not compile, one a signal ends, and `twk run` stopped by SIGTERM
must end as above. The binding's side (`ext.twk.reassemble`, `ext.twk.log`,
the keys) is tested in twk's `test/binding/hot_reload_test.dart`.
`test/inspect_test.dart` runs `twk run` in a package it makes, on an app that
draws on a terminal in memory whose input is stdin, and finds it as `twk
inspect` does, by the service file: its tree must be read, the node at a cell
selected, a click the app picks (the mouse report written to its stdin) come
as that cell, the node outlined, an id of no node answered with the app's
message, and after Ctrl+G H the restarted app be found again; once `twk run`
has ended, the file must be gone. `test/inspector_view_test.dart` runs the
screen with `testTwk` on canned answers of a fake app: the tree from the app's
widget with the details of its node and the outline, the keys moving both,
`h`, a pick selecting a node below a collapsed one, a pick cancelled or
stopped, an app inline, the render tree with the counterpart selected, a load
again on `r` and on the focus with new nodes expanded, a tree loaded again
until the app has drawn its first frame, an error said, and apps that come and
go. The app's side of the pick is tested in twk's
`test/binding/service_extensions_test.dart`. `test/create_test.dart` and
`test/create_<template>_test.dart`, a file each for the four to run at once,
run `twk create` in the test's process (`runTwk`): each template, written with
`--path-to-twk` at this checkout, must make a package of exactly its files
that `dart pub get --offline`, `dart analyze` (no issues), `dart test` and
`dart format --set-exit-if-changed` pass; by default the `app` template must
be written, the package named after the directory and twk taken by path from
this checkout; a pubspec without a checkout must take the packages from pub at
twk's version, a path YAML would misread quoted; `--dry-run` must name the
files and write none, and with `--force` which it would write over; into a
directory whose parents are not there `--dry-run` must make none of them and
the run must make them; a directory that is not empty must be refused with 1,
saying `--force`, and written into with `--force`, the other files kept and
the one written over named so; `--force` over the package it made must name
each file the same there and write none of them; the pubspec must be rewritten
in mold's plan, one there as the template has it written over and one as `twk
create` writes it the same there; no directory, two, a bad name and an unknown
template must exit with 64, a `--path-to-twk` that is no checkout with 1, and
a file for the directory or on the way to it with 1, with `--force` and
`--dry-run` too, and no word of `--force`. `--list` must name the templates.
`test/templates_test.dart` packs each template in `templates/` as
`tool/pack_templates.dart` does and fails when mold warns of anything or its
packed source is not what that gives, until the script is run again; `twk
create` must offer each, and each must take twk, twk_dev, twk_lints and
twk_test by path and nothing else. `test/example_test.dart` runs the
walkthrough's app with `testTwk`: a line for each name, the keys counting the
line chosen and choosing, `-` stopping at 0, each count in the log, `q`
quitting, and the counts and the line chosen kept by `AppBinding.reassemble`,
which a hot reload calls. `test/logs_test.dart` checks how a record is printed
(padding, colours, the stack), and a line of the log that is one, and runs
`twk logs` against sinks served in the test: waiting for an app, the records
kept and live, the next app after one ended. `test/project_test.dart` checks
the project a directory is in. The shell's ends are tested in twk_core
(`test/terminal/socket_test.dart`); `twk shell` itself in a pseudo-terminal,
from the repository's root:

```bash
python3 tool/pty_run.py --input '6:hello,16:\x03' --out /tmp/shell.bin -- \
    dart run packages/twk_dev/bin/twk.dart shell &
sleep 4; dart packages/twk_core/example/chat_demo.dart --seconds=3 </dev/null; wait
```

and `twk run` too, with the counter: Up counts, Ctrl+G H restarts it, q quits;
an edit of `packages/twk/example/counter.dart` meanwhile shows with the count
kept:

```bash
python3 tool/pty_run.py --input '2:\x1b[A,4:\x07H,9:q' --out /tmp/run.bin -- \
    dart run packages/twk_dev/bin/twk.dart run packages/twk/example/counter.dart
dart run tool/replay.dart --fullscreen /tmp/run.bin 100 30
```

and `twk inspect` beside it, in a pseudo-terminal of its own: the counter
counts to 2; the inspector selects two nodes down, has the app pick one (`s`),
which the click written to the counter's terminal does, shows the render tree
and the widget tree again (`t`, `t`) and quits:

```bash
python3 tool/pty_run.py --timeout 60 --size 40x8 \
    --input '2:\x1b[A,3:\x1b[A,18:\x1b[<0;4;3M,18.1:\x1b[<0;4;3m,30:q' \
    --out /tmp/app.bin -- \
    dart run packages/twk_dev/bin/twk.dart run packages/twk/example/counter.dart &
sleep 1; python3 tool/pty_run.py --timeout 60 --size 100x24 \
    --input '9:\x1b[B,10:\x1b[B,12:s,20:t,24:t,26:q' --out /tmp/inspect.bin -- \
    dart run packages/twk_dev/bin/twk.dart inspect; wait
dart run tool/replay.dart --fullscreen /tmp/app.bin 40 8           # Count: 2
dart run tool/replay.dart --fullscreen /tmp/inspect.bin 100 24     # picked Text at 3, 2
```

and `twk record` and `twk play` with the walkthrough's app, the recording
played through the test emulator by `replay.dart` as the terminal got it, and
back:

```bash
python3 tool/pty_run.py --input '3:+,3.5:\x1b[B,4:+,5:q' --out /tmp/rec.bin -- \
    dart run packages/twk_dev/bin/twk.dart record --keys --out=/tmp/s.cast -- \
    dart run packages/twk_dev/example/tally.dart
dart run tool/replay.dart --fullscreen /tmp/rec.bin 100 30         # coffee 1, tea 1
python3 tool/pty_run.py --input none --out /tmp/play.bin -- \
    dart run packages/twk_dev/bin/twk.dart play --speed=2 /tmp/s.cast
dart run tool/replay.dart --fullscreen /tmp/play.bin 100 30        # the same
```

The checks, from this directory:

```bash
dart pub get
dart analyze
dart test
dart format --output=none --set-exit-if-changed lib test bin example
```
