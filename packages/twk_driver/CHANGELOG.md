# Changelog

## Unreleased

Fixed:

- A wait on an app that never reads its input, or is not quiet yet has no
  timer, failed never (`waitFor` looped for ever on the driver's clock);
  it fails after the session's timeout, naming what did not happen, with the
  screen.
- A `waitFor` predicate that throws fails that wait with its error (it
  escaped as an uncaught error and the wait ran to its budget); a trace that
  cannot be opened ends the app that was launched; `ByteLog.slice` is
  logarithmic to its start, not linear.

Added:

- `QuietApp`, the `DriverError` of a wait on a quiet app, with
  `messageUsing(option)` naming the wait's `io` argument as a front end
  calls it.

Added:

- The trace: `Session.start(trace: TraceOptions(path))` (also `compose`
  and `attach`) writes `<path>.cast`, the app's output as asciicast with a
  marker for each step and an event boundary at each frame, and
  `<path>.trace.jsonl`, a line for each step (action, finder, target, the
  tap's hit test, frames, times, result, tree, log) and each frame
  (`Session.trace`, `Trace.delete`). `Cast`, `CastEvent`, `CastHeader` and
  `CastWriter` (from twk_dev, which re-exports them).
- `treeText`: the `ext.twk.tree` answer as indented text, as `twk mcp`'s
  `tree` tool writes it, for the front ends that show a tree.
- A quiet app waited on with `io` waits for the app's `twk.scheduled` event
  (up to the io time on the driver's clock) instead of asking its
  `ext.twk.clock` status every 50 ms.
- `Session.compose` and `Session.attach`: a session from the ports a
  caller gives (process, screen, clock, an optional app service);
  `Session.start` is the twk app's convenience over `compose`. Without an
  app service: waits on the screen the output leaves, input returns when
  written, `find`/`tap`/`clock` fail with "not a twk app (no app
  service)". `PtyCommandPort` starts any command in a pty;
  `ScreenView.updating` (a synchronized update in progress).
- The package: `Session`, a twk app run as a process in a pseudo-terminal
  and driven from outside (`press`, `type`, `paste`, `resize`, `tap`,
  `find`, `waitForScreen`), each action returning at the frame that took the
  input in; the ports `TerminalPort`, `ScreenPort`, `AppServicePort` and
  `ProcessPort` with their adapters; `ByteLog`, the app's count of what it
  wrote against what the terminal gave.
- Driven time (`Session.start(driven: true)`, the default): the app is
  started with `TWK_DRIVEN=<driver pid>`, its clock stands until the driver
  moves it, `press` moves it to the frame the input asked for and no
  further, `Session.clock` (`ClockControl`: `status`, `advance`,
  `advanceTo`, `next`) moves it by hand, and `waitFor(test, budget, io)`
  moves it from timer to timer until the screen is what it waits for:
  "not within" the budget of app time with the timers that wait, or "never"
  at once for a quiet app, `io` giving real time for what comes in from
  outside. The start fails at once where the app did not take the time
  (`driven: false` runs it on real time).
- `VmAppClient` and `AppClient`, moved from twk_dev, and `compiledProgram`,
  moved from twk_test.
