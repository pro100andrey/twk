# Changelog

## Unreleased

Added:

- `twk doctor` says where DEC 2026 came from: the terminal's answer, or
  what twk knows of it by its name and version where it answers no query
  (`known as konsole 26.8.3`, `yes (known of konsole 26.8.3, which answers
  no query for it)`), or nothing answered. `--json` has `terminal` and
  `synchronizedOutputFrom`.
- `twk doctor` says how desktop notifications are shown and where that came
  from: the keys the terminal answered OSC 99's query with, or its name and
  environment. `--json` has `notifications`, `notificationsFrom` and
  `notificationKeys`; notifications through the desktop's notification
  service on D-Bus are said so.
- `twk mcp`: an MCP server on stdio (JSON-RPC of its own, protocol versions
  2025-06-18, 2025-03-26 and 2024-11-05) that lets a coding agent drive a
  twk app through twk_driver: `start_app`, `screen`, `tree`, `find`, `press`,
  `type`, `tap`, `wait_for`, `elapse`, `hot_reload`, `logs` and `stop_app`.
  The app runs on time the server moves, and stops when the server's input
  ends; each tool answers with the screen after it and a line with the
  frame, the input read and whether the app is quiet, and a failure is a
  result that says why (covered by, never, not within budget, the app
  exited), not a timeout. A `{"node": 42}` finder (the ids `tree` prints) is
  taken alone or inside `first`, `last`, `at` and `descendant`. `logs` reads
  the app's log from the driver session, the last 50 records between two
  calls. The block `twk agents` writes to `AGENTS.md` and the skill say how
  to register it. See `doc/mcp.md`.
- `twk decode <file>...` names what a recording (`.cast`) or the files
  `TWK_TRACE_INPUT` and `TWK_TRACE_OUTPUT` write hold, a row for each text
  run, control character, escape sequence, key, mouse event and terminal
  answer, with its time; `--frames` shows a synchronized update (DEC mode
  2026) as one row, `--only=output|input` and `--grep=<regexp>` choose rows,
  and several files (the two traces of one run) are merged by time. What a
  recording holds is shown escaped, so a title or a C1 character in it does
  not act on the terminal it is shown in. The names are those of the VS Code
  extension's sequence log.
- `twk completion <bash|zsh|fish>` prints the shell's completion script for
  `twk`: subcommands, options (with the `--no-` forms and the allowed
  values), directories for `-C`, and the files of each command (`.cast` for
  `play`, `.tape` for `tape`, `.dart` for `run`).
- `twk doctor [-C <dir>] [--json]`: the terminal as twk probes it (TERM, name
  and version, colours, DEC 2026, kitty keyboard, graphics, links, cell size,
  how long the answers took), the project's twk, twk_core, twk_dev and
  twk_test versions and whether they agree (exit 1 where not), each with its
  source (`locked`, `path`, `workspace`; `sources` in `--json`), also in a pub
  workspace, the Dart SDK, the files of `.dart_tool/twk` and whether they are
  listened at, and the agents' skill when older than this twk_dev. Without a
  terminal only the project part. `--json` for tools.
- `twk record --replay=<file>` (with `--replay-speed=<factor>|asap` and
  `--replay-then=handover|end`): types the keys of a recording (`--keys`) into
  the command, at their times or each once the command has settled, then
  hands the terminal over or ends, to reproduce a bug from a session. The
  terminal's answers to queries are told from keys by their shape
  (`doc/record-play.md`) and not typed again.
- `twk record --marker-key=ctrl+]` leaves a marker (`marker 1`, ...) at that
  key instead of passing it on (off by default); it refuses ctrl+h, ctrl+d,
  ctrl+s, ctrl+q and ctrl+z (exit 64). `doc/record-play.md`.
- `twk play` controls, as the VS Code player's: Space pauses and plays on,
  Right a frame on, Left a frame back, Home from the start, `]` and `[` the
  next and the previous marker of the recording (paused, at the screen as at
  the marker), `q` quits (exit 0), Ctrl+C always. A frame is what twk_test's
  `screenFrames` takes for one, so a synchronized update is written whole;
  paused, a status line (frame n/m, the time, the last marker reached) shows
  under the recording where the terminal has a row for it.
- `twk test-from-cast <file.cast> [--out=<file>]`: copies the recording next
  to a new test (`test/<name>_test.dart` by default, in the project's
  `test/` also from a subdirectory) that plays it through twk_test's
  `screenFrames` and holds the frame shown at each marker (the last one where
  there are none) to a screen file, `goldens/<name>/<k>.txt` (`last.txt`)
  beside the test, with twk_test's `matchesScreenFile`. The command runs the
  test once with `TWK_UPDATE_GOLDENS=1` to write them, saying which files;
  it ends with 1, leaving the test and the recording, where the project has
  no twk_test dev dependency or the run fails, and `--no-goldens` skips the
  run. It refuses (exit 1) to overwrite a different recording of the same
  name beside the test; `--force` does. A marker with no screen at or before
  it is reported on stderr and in a comment of the test. The generator is
  `castTestSource` (`goldens:`), which the VS Code extension's command goes
  through the CLI to reach.
- `twk tape --check`: runs a tape as a test, writing no Output or Screenshot,
  telling each statement on stdout (`<tape>:<line>: ok <statement>`, a last
  line with the count) and failing (exit 1, `FAIL` line, the screen on
  stderr) on the first Wait that times out.
- `twk tape`: `Wait Widget <Type>`, `Wait Text "<text>"` and `Click "<text>"`
  for a twk app (`Run dart <file>`): the tape waits for what the app's widget
  tree has, after each frame the app draws, and clicks a widget, after the
  tap check of twk_driver (a click on what is covered, hidden or takes no
  click fails the tape, saying why). On a program that is no twk app they
  fail with "not a twk app". `Click Key "<id>"` clicks the widget with that
  `ValueKey` (a bare whole number is an int key).
- `twk inspect`: `g` opens where the selected widget was made in the editor
  (`TWK_EDITOR`, `VISUAL`, `EDITOR`; a terminal editor runs in the
  inspector's terminal while it waits). The place is found in the app's code
  through its VM service, as the VS Code extension finds it.
- `twk run` reloads on a change in the `lib/` of the path dependencies and
  workspace members of the app's package too, found from
  `package_config.json` (a package without a `packageUri` is watched from its
  root; hosted and git packages are not watched, and without a pub cache
  known only packages under a `.pub-cache` are taken for hosted ones); the
  app log names them. `--no-watch-deps` turns it off.
- `twk run --debug=<aids>`, `--screen-reader` and `--plain` set `TWK_DEBUG`
  (added to the app's own and to `keys`), `TWK_SCREEN_READER=1` and
  `TWK_PLAIN=1` for the app, before the file; an unknown aid is refused
  with 64. `doc/run.md` says how to record a `twk run` session, restarts
  included (`twk record -- twk run <file>`).
- `twk create`: templates `ssh` (`twk_ssh`), `web` (`twk_web`), `riverpod`
  (`twk_riverpod`) and `bloc` (`twk_bloc`), each printing its own run
  commands. Their package is taken at its own version from pub, or by path in
  a checkout of the twk repository; outside one, the four are refused, saying
  why. `--template=app` has a `driverTest` beside the `testTwk` ones: it
  starts the app, presses a key, reads the screen and quits with Ctrl+Q.

Changed:

- `twk run` runs the app with asserts on (`--enable-asserts`), so the
  framework's checks and overflow warnings are heard in a terminal run;
  `--no-asserts` runs it as it ships, for measuring. The templates'
  READMEs say so.
- `twk tape` runs on twk_driver's `Session`: its typing, keys and Waits go
  through the session. `TapeClock` is a twk_core `Clock` (`timer`, `periodic`,
  `elapsed`, `pause`), and a program is ended through its terminal at the end.

Fixed:

- `twk tape` takes no `NO_COLOR` and `FORCE_COLOR` from the shell, so a tape
  draws the same on every machine; a tape's own `env` still sets them.
- `twk logs` and `twk create` take a pseudo-terminal of no size for a
  terminal: colours in the log, questions asked; `/dev/null` is none.
- `twk run` goes on when a watched `lib/` is deleted or moved (a branch
  switch): it stops watching that directory and says so in the app's log.
- `twk agents`: a link at the manifest's path (`.twk-agents.json`) is the
  project's, as a pack file's is, and what it points at is not written; a file
  where a directory of the skill belongs, or a directory at the manifest's
  path, is refused up front instead of failing partway through, leaving a
  part of the skill written.

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
