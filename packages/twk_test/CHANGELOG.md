# Changelog

## Unreleased

Breaking:

- `VtTerminal.notify` takes a `DesktopNotification` and returns its id, and
  `VtTerminal.closeNotification` does nothing, as `WindowBackend` now asks.

- `testTwk(trackDisposables:)` is on by default, as Flutter's leak tracker is:
  a test that makes a controller or notifier (a `TextEditingController`,
  `ScrollController`, `FocusNode`, `AnimationController`, any `ValueNotifier`,
  the controllers of twk's widgets) and does not dispose it fails once its app
  is quit and its tear-downs ran, naming it with the stack that made it.
  Dispose it with `addTearDown(x.dispose)`, or pass `trackDisposables: false`
  where an object outlives the test on purpose.
- `testTwk(failOnOverflow:)` is on by default: the test fails when a row,
  column, wrap or grid of its app was overflowed by its children (the warning
  the debug marker of the screen shows), naming each with the widget it is in.
  Pass `failOnOverflow: false` in a test of what an overflow shows; a layout
  that clips on purpose says so with `overflowIntended`.
- `testTwk(failOnPendingTimers:)` is on by default: the test fails when a timer
  of its clock still waits one frame after the app is quit (a `Timer.periodic`
  left running by `dispose`), naming it and where it was started. Pass
  `failOnPendingTimers: false` where the app is meant to leave a timer
  running.
- `FakeClock.stopwatch` is gone: `FakeClock.clock`, a `DrivenClock`, is what an
  app's `clock:` takes. `FakeClock` is that clock plus its zone and its
  microtasks; its other members are as they were. `FakeCliTerminal` keeps
  `fakeClock:`.

Added:

- `TearCheck` (`package:twk_test/vt.dart`): what a terminal without
  synchronized updates (DEC 2026) may show while a frame is drawn. Every
  screen between the frame's steps is held to the screen before it and after
  it: a cell showing content that is in it neither before nor after, and
  that no scroll the app asked for brought there, alone or one after
  another (rows scrolled, a rectangle of them), such as the cells beside a
  rectangle scrolled as whole rows, is reported; a space, what an erase
  leaves, is not. A row shift (ICH, DCH) brings nothing: a glyph it moved
  is to be where the frame leaves it. `Vt.onStep`, `Vt.onScroll` and
  `Vt.onShift` say when the emulator took a step outside a synchronized update, moved
  rows and shifted a row's cells (ICH, DCH).
- `package:twk_test/driver.dart`: `driverTest`, tests of a twk app as a real
  process in a pseudo-terminal on driven time. `d.start(program, size:,
  profile:, env:, driven:, inline:)` returns a `DriverApp`: `press`, `type`,
  `paste`, `resize`, `tap(find...)`, `find`, `findOne`, `rect`, `tree`,
  `waitFor`, `waitForFinder`, `clock`, `screen`. The finders and matchers are
  `testTwk`'s: `find.*` are evaluated by the app (`ext.twk.find`), and
  `containsLine`, `hasTextAt`, `styleAt`, `cursorAt` and `matchesScreen` read
  `app.screen` (a `DriverScreen`) as they read a `TwkTester`. A test ends by
  closing the apps and failing on what the strict `Vt` could not take of their
  output and on the terminal an app that exited did not give back. A failed
  one prints each app's screen, last frames, widget tree and the last log
  records of each app.
- `driverTest(profiles:)` runs a test once per terminal profile
  (`terminalProfiles`: truecolor, 256 colors, 16 colors, no color); the color
  profiles set `NO_COLOR` empty, so a developer's `NO_COLOR=1` does not make
  their apps monochrome locally. The strict `Vt` takes the line feeds of a
  fullscreen app's own output once it left the alternate screen
  (`Vt.lineFeedOnNormalScreen`), and none while it is up.
- `driverTest` writes the trace of each app (the cast with a marker per step,
  and the steps as JSON lines) under `.dart_tool/twk_test/traces/`, names its
  path in the report of a failed test and deletes it for a passing one.
- `disposing(object)`: returns a controller or a node, disposed when the test
  ends, so one made where it is used is not left undisposed:
  `final name = disposing(TextEditingController());`.
- `matchesScreenFile` leaves the screen it did not match beside the file as
  `<file>.actual` (the file as updating would write it), only where a failure
  is reported, and removes it on a match or an update; the VS Code extension
  shows it against the golden and accepts it. Add `*.txt.actual` to a
  project's `.gitignore`.
- `screenFrames(screens:)` keeps, for the frames whose numbers it is given
  (and for no other, so a long recording costs one snapshot a frame checked),
  the screen with its styles and cursor, and `matchesScreenFile` accepts such
  a `ScreenFrame` as it accepts a `TwkTester`: the same file format, update
  and `<file>.actual`. A frame whose screen was not kept fails, saying so.
- `pumpWidget(kittyAnimation:)` gives the app a terminal that plays kitty's
  animations (`TerminalCaps.kittyAnimation`); the emulator keeps an image's
  frames (`Vt.kittyFrames`) and whether its animation plays and how many times
  (`Vt.kittyAnimations`), and fails a frame or a control of an image it lacks,
  a frame number past them, or a state it does not know.

Changed:

- `compiledProgram` lives in twk_driver now and twk_test re-exports it; a
  program that does not compile is a `DriverError` (twk_driver's), not a
  `TestFailure`.
- `find.*` build twk's `ElementFinder` values and evaluate them with its code:
  `Finder` is a final class that wraps one and has `toJson`, which
  `ext.twk.find` takes. `find.byWidgetPredicate`'s `toJson` throws, naming it.
  `Finder` can no longer be extended.
- `element`, `widget`, `state`, `renderObject`, `rect` and `clickOn` on a
  finder that finds more than one widget fail with their number and the first
  five. `clickOn` cuts the cells with twk's `shown`.

Fixed:

- A `testTwk` tear-down that awaits a future of the app's zone completes: the
  microtasks of the zone run on the real event loop once the body is done. A
  stream a callback of the app closed (`input` of a `TerminalSession` closing
  it on `q`), its `close()` awaited again in a tear-down, hung until the
  test's timeout.

## 0.3.0

Breaking:

- A test fails on an error its app logged, unless it takes it with
  `TwkTester.takeErrors()`. Reading `t.logs` takes nothing.

Added:

- `waitFor` and `waitUntil` take `state`: what a failure says of where things
  stood.
- `TwkTester.pumpWidget(remote:)`.
- `FakeCliTerminal.interactive(answers:)`, an entry typed as each question shows,
  and `FakeCliTerminal.onPrompt`.
- `find.textContaining(pattern)`, a `String` or a `RegExp`.

## 0.2.0

- `FakeCliTerminal.openInline` opens the inline terminal again once the
  last one is closed (a session ended by a Ctrl+C, then another), as the
  process's own terminal now does, and throws only while one is open; it
  threw on any second open ("stdin is closed"). `opened` counts each. A
  test that relied on the second open throwing gets a new terminal.

Breaking:

- `describeScreen` prints the screen as plain text unless `styles: true`;
  it marked styles always before. `describeApp` lost its `styles`.
- `containsLine` and `hasTextAt` take `within` as a `Finder` only; a
  rectangle goes in `withinRect`, a `CellRect` (the one `rect` gives and
  `linesIn` takes, now a public typedef). Both together is an
  `ArgumentError`.
- `TwkTester.pointerShape` throws a `StateError` unless
  `pumpWidget(pointerShapes: true)`; it read null there, so an `isNull`
  could pass for the wrong reason.

## 0.1.0

The first release.

- `testTwk` and `TwkTester`: an app on a terminal in memory under a
  `FakeClock`; `pumpWidget`, `pump`, `pumpUntilIdle`; keys, text, the
  mouse, paste, focus and resizes as the bytes a terminal sends; the
  fullscreen and the inline modes and a fixed viewport.
- The screen read back through `Vt`, a strict emulator (kitty graphics,
  sixel and iTerm2 images among what it takes): `lines`, `cell`, and
  matchers such as `containsLine`, `matchesScreen`, `matchesScreenFile`
  (golden files, `TWK_UPDATE_GOLDENS=1`) and `styleAt`.
- Finders (`find.text`, `find.byType`, `find.byKey`, …) and taps on what
  they find (`clickOn`).
- The frames an app wrote (`RecordedFrame`), printed when a test fails
  and written as a trace (`writeTrace`).
- `Shot`: a widget tree or a render object drawn without an app.
- `VtTerminal`, a terminal backend in the inline mode over the emulator.
- `waitFor` and `waitUntil` for what only real time brings;
  `compiledProgram`, `startProcess` and `runProcess` for a program a test
  runs in a process of its own, ended with the test.
