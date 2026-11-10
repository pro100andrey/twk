# Changelog

## Unreleased

Fixed:

- `twk play`: Ctrl+C always quits (a lone Escape or an Alt+key that opens a
  string no longer swallows it); a key release is no second press of an arrow
  or Home; played to its end with keys read, it stays paused there (Space
  plays again, Left goes back, `q` quits); the frame count of the status line
  is not recounted at each key.
- `twk run` says `no longer watching` also when a watched directory's stream
  just ends, and a path dependency is watched at its `lib/` always, not at
  its root (`.dart_tool/`, `build/`, `test/` edits no longer reload the app).

Added:

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
