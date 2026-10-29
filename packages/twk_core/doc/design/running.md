# twk_core design: §4 Running

[The design](README.md)

No runtime dependencies; `dev_dependencies` are `test`, `pro_lints` and, by
path, `packages/twk_test` (the test emulator and the widget tester,
[§2](testing.md)). The commands below run from the repository's root, where
its `tool/` is.

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
  alternate screen. With `--inline` the header, input and status lines are
  the inline region ([§1.12](inline.md)), and every message, from the 30 it
  starts with on, is committed to the terminal's history above it, where the
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
