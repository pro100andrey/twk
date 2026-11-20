# Changelog

## Unreleased

Added:

- The package: a twk app run as a process in a pseudo-terminal and driven
  from outside. `Session` presses keys (`press`, `pressKey` for an event as
  it is, such as Shift with a space), types, pastes, resizes, taps a widget
  and finds widgets (`tap`, `find`), and reads the screen (`waitForScreen`,
  `waitFor`); each action returns at the frame that took the input in.
  `type('')` and `paste('')` send nothing and return the current step at
  once. `Session.close` twice returns the first call's report.
- Ports: a session is made of `TerminalPort`, `ScreenPort`, `AppServicePort`
  and `ProcessPort`, with their adapters. `Session.start` is the twk app's
  convenience over `Session.compose` and `Session.attach`, which take the
  ports a caller gives (process, screen, clock, an optional app service).
  Without an app service, waits are on the screen the output leaves, input
  returns when written, and `find`, `tap` and `clock` fail with "not a twk
  app (no app service)". `PtyCommandPort` starts any command in a pty;
  `ScreenView.updating` says a synchronized update is in progress. The ports
  follow the platform, macOS included, unless told.
- Driven time (`Session.start(driven: true)`, the default): the app is
  started with `TWK_DRIVEN=<driver pid>`, its clock stands until the driver
  moves it, `press` moves it to the frame the input asked for and no
  further, `Session.clock` (`ClockControl`: `status`, `advance`,
  `advanceTo`, `next`) moves it by hand, and `waitFor(test, budget, io)`
  moves it from timer to timer until the screen is what it waits for: "not
  within" the budget of app time with the timers that wait, or "never" at
  once for a quiet app, `io` giving real time for what comes in from
  outside. The start fails at once where the app did not take the time
  (`driven: false` runs it on real time). A wait on a quiet app, which
  waits for the app's `twk.scheduled` event, fails with `QuietApp`, whose
  `messageUsing(option)` names the wait's `io` argument as a front end calls
  it. Every wait ends at its own deadline, also when several are open at
  once, and fails after the session's `timeout` naming what did not happen,
  with the screen; a `waitFor` predicate that throws fails that wait with its
  error.
- The app's log reaches the driver: a step of the trace has the records the
  app logged during it, `ExitResult.log` and `AppEnded.log` the last ones,
  `Session.log` the tail (50 lines) and `Session.logCount` how many records
  the app has posted.
- The trace: `Session.start(trace: TraceOptions(path))` (also `compose` and
  `attach`) writes `<path>.cast`, the app's output as asciicast with a marker
  for each step and an event boundary at each frame, and
  `<path>.trace.jsonl`, a line for each step (action, finder, target, the
  tap's hit test, frames, times, result, tree, log) and each frame
  (`Session.trace`, `Trace.delete`). `Cast`, `CastEvent`, `CastHeader` and
  `CastWriter` come from twk_dev, which re-exports them; `ByteLog` counts
  what the app wrote against what the terminal gave.
- `treeText`: the `ext.twk.tree` answer as indented text, as `twk mcp`'s
  `tree` tool writes it, for the front ends that show a tree.
- `VmAppClient` and `AppClient`, moved from twk_dev, and `compiledProgram`,
  moved from twk_test.
- The program a session starts takes no `NO_COLOR` and `FORCE_COLOR` from the
  developer's shell (twk_core turns colors off for any non-empty
  `NO_COLOR`): `PtyProcessPort` and `PtyCommandPort` give both empty, over
  what the spec's `environment` sets, so the same app runs the same on every
  machine.
