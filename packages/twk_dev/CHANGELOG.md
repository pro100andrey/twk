# Changelog

## Unreleased

Fixed:

- `twk record --replay`: a paste that comes in more than one event of a
  recording is typed as it came, each part at its time (it was held back whole
  until its end, and a paste over 4096 bytes lost the protection of its
  content from the answers it holds). One golden, `test/replay_split.golden.json`,
  holds it and the VS Code extension's Type a Recording's Keys to the same
  keys for a recording.
- `twk record --replay`: a recording that ends inside a paste no longer leaves
  the splitter in it for the next `add`.

Changed:

- `twk test-from-cast` emulates nothing: the test it writes holds the frame
  shown at each marker (the last one where there are none) to a screen file,
  `goldens/<name>/<k>.txt` (`last.txt`) beside the test, with
  twk_test's `matchesScreenFile`, and the command runs the test once with
  `TWK_UPDATE_GOLDENS=1` so that the emulator that checks the screens writes
  them, saying which files. It ends with 1, leaving the test and the
  recording, where the project has no twk_test dev dependency or the run
  fails; `--no-goldens` skips the run. A recording with a tab in a checked
  row no longer fails its fresh test (twk_term's emulator and twk_test's
  disagreed on it). `castTestSource` takes `goldens:` and no `note:`.

Added:

- `twk decode <file>...` names what a recording (`.cast`) or the files
  `TWK_TRACE_INPUT` and `TWK_TRACE_OUTPUT` write hold, a row for each text
  run, control character, escape sequence, key, mouse event and terminal
  answer, with its time; `--frames` shows a synchronized update (DEC mode
  2026) as one row, `--only=output|input` and `--grep=<regexp>` choose rows,
  and several files (the two traces of one run) are merged by time. The names
  are those of the VS Code extension's sequence log, both held to one golden,
  `test/decode.golden.json`.
- `twk completion <bash|zsh|fish>` prints the shell's completion script for
  `twk`: subcommands, options (with the `--no-` forms and the allowed
  values), directories for `-C`, and the files of each command (`.cast` for
  `play`, `.tape` for `tape`, `.dart` for `run`). It is written from the
  command's own parsers, with no dependency added.

Fixed:

- `twk doctor` in a pub workspace (or on a package of one) reported `twk`,
  `twk_core`, `twk_dev` and `twk_test` as "not in the lock" and the versions
  as agreeing: a workspace's lock does not list its members. The versions
  now come from the lock, and for what it lacks from
  `.dart_tool/package_config.json` and the package's `pubspec.yaml`, each
  with its source (`locked`, `path`, `workspace`; `sources` in `--json`).
- `twk decode`: every name and byte string it prints is escaped (a title, a
  notification or a C1 character in a recording no longer clears the screen,
  sets a title or writes the clipboard of the terminal it is shown in); all
  rows are shown, not the last 20000; a synchronized update or a string left
  open at the end of the traffic is shown (`not closed`, `output cut short`);
  a stray `?2026l` no longer breaks the frames after it; `CSI 1;5 R` is a
  position answer when the output asked for one, else F3; Alt with Enter, Tab
  or a Ctrl key and with a multi-byte character are named and read whole;
  `ESC [ 1 ESC [ 2 J` is an invalid CSI and then an ED; a text token is
  decoded from its own bytes and a long unterminated string is scanned once.
  The extension's sequence log follows (one golden).
- `twk decode`, input: `ESC` before a mouse report, a focus report, a paste's
  start or an answer is an Escape of its own, not Alt (only a key's sequence
  takes it); a DEL inside a CSI is ignored and shown in the raw. Replay: a
  `CSI ? r;c R` is taken as the answer to a `CSI ? 6 n` the program wrote.
- `twk decode`, input: `CSI ? r;c R` is the answer to `CSI ? 6 n` (named
  DECXCPR) and uses the query up, so a later Ctrl+F3 is not read as a position;
  `ESC` before a sequence is that key with Alt (`ESC ESC [ A` is Alt+Up, `ESC
  ESC` Alt+Escape). Output: a C0 control inside a CSI is shown and the CSI
  goes on (ESC begins a new sequence, CAN and SUB cancel it); the bytes of a
  character cut at the end of a read are shown when an ESC or a control
  character comes next, not dropped.
- `twk completion`: the fish script no longer breaks on sourcing when an
  option's help ends in a backslash or has one before a quote; bash completes
  file names with spaces (or glob characters) as one candidate each; each
  command declares what its arguments and path options are completed with
  (`Completes`), instead of a table kept apart.
- `twk play`: a lone Esc left unanswered for 500 ms is the Esc key, so a `[`
  typed later is the previous marker again.
- `twk test-from-cast`: a marker's label is shown escaped (one line, controls
  as `\u{..}`) in the unchecked-marker comment of the test and on stderr; a
  newline in it no longer writes live code into the test.
- `twk play`: the paused status line is cut to the terminal's width; markers
  are stops one by one (several on one step, and one at the start); the hold
  of the start of a terminal answer is 500 ms (it was 100 ms, which dropped
  the head of a slow answer and read its tail as keys), also checked on the
  clock.
- `twk record --marker-key` refuses ctrl+h, ctrl+d, ctrl+s, ctrl+q and ctrl+z
  (exit 64).
- `twk record --replay`: output logged after a key and before the next is the
  key's reaction by the order of events, also at the same time.
- `twk play`: Alt+P (or Alt+] and the like) no longer swallows `q` and Space
  until Ctrl+C: the start of a terminal answer is held for a limited time only, not
  up to 1024 characters.
- `twk test-from-cast` writes its test in the project's `test/` also when run
  from a subdirectory (it wrote `lib/test/`); a recording already beside the
  test is used where it is, not copied under the sanitised name; a marker
  with no screen at or before it is reported on stderr and in a comment of
  the test instead of being dropped silently.
- `twk record --replay`: a failure while replaying (an odd recording, a write
  error) ends the recording with a message and the terminal put back; a
  cursor-position query cut between two writes of the program is found, and
  one nobody answered no longer makes a later modified F3 an answer.
- `twk play`: an answer of the terminal cut right after its Escape, or over
  three reads, is no longer read as keys (a `q` in it quit); Escape then `q`
  still quits.
- `twk test-from-cast` refuses (exit 1) to overwrite a different recording
  of the same name beside the test; `--force` does.
- The inspector's source locator no longer keeps a failed question as "no
  build" and finds a widget's place when a string with a quote in `${}`
  precedes it.
- `twk play`: Ctrl+C always quits (a lone Escape or an Alt+key that opens a
  string no longer swallows it); a key release is no second press of an arrow
  or Home; played to its end with keys read, it stays paused there (Space
  plays again, Left goes back, `q` quits); the frame count of the status line
  is not recounted at each key.
- `twk run` says `no longer watching` also when a watched directory's stream
  just ends, and a path dependency is watched at its `lib/` always, not at
  its root (`.dart_tool/`, `build/`, `test/` edits no longer reload the app).

Added:

- `twk play`: `]` and `[` go to the next and the previous marker of the
  recording (its `m` events), paused, at the screen as at the marker; the
  paused status line names the last marker reached (`marker 2/5 label`).
  `twk record --marker-key=ctrl+]` leaves a marker (`marker 1`, ...) at that
  key instead of passing it on (off by default); `doc/record-play.md`.
- `doc/run.md`: how to record a `twk run` session, restarts included
  (`twk record -- twk run <file>`), and why `twk run` has no `--record`.
- `twk tape --check`: runs a tape as a test, writing no Output or Screenshot,
  telling each statement on stdout (`<tape>:<line>: ok <statement>`, a last
  line with the count) and failing (exit 1, `FAIL` line, the screen on
  stderr) on the first Wait that times out. `TapeClock.alarm` is the clock
  of a Wait's timeout.
- `twk record --replay=<file>` (with `--replay-speed=<factor>|asap` and
  `--replay-then=handover|end`): types the keys of a recording (`--keys`) into
  the command, at their times or each once the command has settled, then
  hands the terminal over or ends, to reproduce a bug from a session. The
  terminal's answers to queries are told from keys by their shape
  (`doc/record-play.md`) and not typed again.
- `twk test-from-cast <file.cast> [--out=<file>]`: copies the recording next
  to a new test (`test/<name>_test.dart` by default) that plays it through
  twk_test's `screenFrames` and checks a line of the screen at each marker,
  or of the last screen where there are none, and that the emulator took in
  all of it. The generator is `castTestSource`, which the VS Code
  extension's command goes through the CLI to reach.
- `twk inspect`: `g` opens where the selected widget was made in the editor
  (`TWK_EDITOR`, `VISUAL`, `EDITOR`; a terminal editor runs in the
  inspector's terminal while it waits). The place is found in the app's code
  through its VM service: the `build` methods above the element, the calls
  of the widget's constructor in them, the one at the element's place among
  them (the same finding as the VS Code extension's).
- `twk play` controls, as the VS Code player's: Space pauses and plays on,
  Right a frame on, Left a frame back (the terminal reset and the frames
  before written at once), Home from the start, `q` quits (exit 0). A frame
  is what twk_test's `screenFrames` takes for one, so a synchronized update
  is written whole; paused, a status line (frame n/m, the time) shows under
  the recording where the terminal has a row for it, never written into what
  is played.
- `twk doctor [-C <dir>] [--json]`: the terminal as twk probes it (TERM, name
  and version, colours, DEC 2026, kitty keyboard, graphics, links, cell size,
  how long the answers took), the project's twk, twk_core, twk_dev and
  twk_test versions from the lock and whether they agree (exit 1 where not),
  the Dart SDK, the files of `.dart_tool/twk` and whether they are listened
  at, and the agents' skill when older than this twk_dev. Without a terminal
  only the project part. `--json` for tools.
- `twk run` reloads on a change in the `lib/` of the path dependencies and
  workspace members of the app's package too, found from
  `package_config.json` (hosted and git packages are not watched); the app
  log names them. `--no-watch-deps` turns it off.
- `twk run --debug=<aids>`, `--screen-reader` and `--plain` set `TWK_DEBUG`
  (added to the app's own and to `keys`), `TWK_SCREEN_READER=1` and
  `TWK_PLAIN=1` for the app, before the file; an unknown aid is refused
  with 64.

Changed:

- `twk run` runs the app with asserts on (`--enable-asserts`), so the
  framework's checks and overflow warnings are heard in a terminal run;
  `--no-asserts` runs it as it ships, for measuring. The templates'
  READMEs say so.

Fixed:

- `twk logs` and `twk create` take a pseudo-terminal of no size for a
  terminal: colours in the log, questions asked; `/dev/null` is none.
- `twk run` goes on when a watched `lib/` is deleted or moved (a branch
  switch): it stops watching that directory and says so in the app's log.
  A package without a `packageUri` in the package configuration is watched
  from its root, as the configuration says; without a pub cache known, only
  packages under a `.pub-cache` are taken for hosted ones.
- `twk doctor` closes a socket that connects after its one-second wait.

## 0.3.0

Added:

- `twk create` asks, in a terminal, for what its flags did not say: the template
  and the files for coding agents. `--agents=agents-md,skill` says them,
  `--agents=none` says none. Without a terminal it asks nothing and takes the
  defaults. `createApp`, `askCreate` and `canAsk` are the steps apart.
- `twk agents` writes the twk skill into a project's `.agents/skills/twk` and
  `.claude/skills/twk`, and a block between two markers into its `AGENTS.md`. Run
  again, it updates what a newer twk_dev changed. A manifest, `.twk-agents.json`,
  lists what it wrote: files not as it wrote them, and links, stay and are named.
  `--directory` names the project, `--dry-run` writes nothing. `agentsPlan` is the
  same as a function.

Changed:

- `twk create` makes a project take twk, twk_dev, twk_lints and twk_test at
  `^0.3.0`.

## 0.2.0

- Takes twk, twk_core and twk_term at 0.2.0, which have breaking
  changes, and `twk create` makes a project take twk, twk_dev, twk_lints
  and twk_test from pub at `^0.2.0`.

## 0.1.0

The first release.

- `twk create`: an app from a template (`app`, `dashboard`, `form`,
  `inline`), depending on twk, with twk_test and twk_lints.
- `twk run`: the app hot reloaded on save, its terminal kept.
- `twk inspect` and `twk logs`: the widget tree of a running app, and its
  log, over the VM service.
- `twk shell`: the terminal a twk app's editor extension talks to.
- `twk record`, `twk play` and `twk tape`: a session recorded as an
  asciicast, played back, or scripted and drawn as SVG; and
  `Cast.writes`, what a recording did to its terminal, which twk_test's
  `screenFrames` plays into the screens it showed, for a test.
