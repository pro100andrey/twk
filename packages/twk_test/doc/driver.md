# Driving the real app

`testTwk` runs an app in the test's own process, on a fake clock. `driverTest`
(`package:twk_test/driver.dart`, a library of its own, so that `testTwk`
users do not load the driver) runs the program as a user's terminal does: a
real process in a pseudo-terminal, its keys real bytes, its screen read
through an emulator, its widget tree asked of it through its VM service. What
it shows that `testTwk` cannot: the process, the terminal modes `runApp` sets
and gives back, the bytes the app writes.

The test starts the app, drives it, and reads the screen with the matchers
and the widgets with the finders of `testTwk`:

```dart
driverTest('saving shows it', (d) async {
  final app = await d.start('bin/main.dart', size: (60, 12));
  await app.press('ctrl+n');
  await app.tap(find.text('Save'));
  expect(app.screen, containsLine('Saved'));
  final step = await app.press('q');
  expect(step.exit!.code, 0);
}, tags: 'process');
```

A test that starts a process is tagged `process` (`@Tags(['process'])` on the
library), and runs on Linux and macOS.

## Starting

`d.start(program)` takes a Dart file (compiled to a kernel once, in
`.dart_tool/twk_test/programs`, and again when its sources change) or a
kernel. `arguments`, `env`, `workingDirectory` and `size` (columns, rows) are
the process's. It returns once the app has drawn its first frame.

- `profile` is a name of `terminalProfiles`: `'truecolor'`, `'256 colors'`,
  `'16 colors'`, `'no color'`, each the environment (`TERM`, `COLORTERM`,
  `NO_COLOR`) the app reads its colors from. `driverTest(profiles: [...])`
  runs the test once for each, `description [16 colors]`, and `d.profile` says
  which.
- `driven` (on by default): the app's time is the test's. Its timers fire
  when the test moves its clock, never by themselves; `press` moves it to the
  frame the key asked for and no further, `waitFor` moves it on until the
  screen is what it waits for. With `driven: false` the app runs on real time,
  and only the waits that take `io` are of use.
- `inline`: the app draws in the normal screen (`ScreenMode.inline`).

## Acting

Each action returns a `Step` (the frame, the screen as text, and `exit` when
the app ended) once the app has drawn the frame that took the input in: no
sleep, no poll.

- `press('ctrl+s')`, `press('g g')`, `type('text')`, `paste('text')`,
  `resize(width, height)`.
- `tap(find.text('Save'))` clicks the middle of the one widget the finder
  finds, after checking that a click there reaches it. The failure says why
  it does not: not shown, covered by another widget (and which), nothing there
  takes a click, an `AbsorbPointer` in the way.
- `press('q')` of an app that quits returns the exit: `step.exit!.code`.

## Reading

- `app.screen` is a `DriverScreen`: `containsLine`, `hasTextAt`, `styleAt`,
  `cursorAt` and `matchesScreen` take it as they take a `TwkTester`
  (`app.screen.lines`, `app.text`). A finder cannot say where a widget of
  another process is drawn, so the matchers' `within:` fails saying so; ask
  the app: `withinRect: await app.rect(find.byType(ListView))`.
- `await app.find(finder)` is the list of nodes the finder matches in the
  app's tree, `findOne` the one (strict: none or several is a failure
  that says which). The finders are the `find.*` of `testTwk`, the same code,
  evaluated in the app (`ext.twk.find`); `find.byWidgetPredicate` stays in the
  test's process and cannot be asked.
- `await app.tree(depth: 3)` is the widget tree as text.

## Waiting

`waitFor((screen) => screen.contains('Done'))` looks at the screen of each
frame, the one shown first, and, on a driven app, moves the app's time from
timer to timer until it has moved `budget` (10 s by default). It fails with
the screen and the timers that wait, or, when the app is quiet (no timer, no
frame asked for) and nothing will change the screen, at once with `never`.
`near: 'text'` adds the closest line of the screen to the failure. Real I/O in
flight (a socket, a child process) is invisible to the app's clock: give `io:`,
how long to wait for it in real time.

`await app.waitForFinder(find.text('Done'))` waits for a condition on the
tree: the count the finder finds (`findsOneWidget` by default, `findsNothing`,
`findsWidgets`, `findsNWidgets(n)`), looked at after each frame. It returns the
nodes found. `app.clock` moves the time by hand (`advance`).

## What ends a test

When the body returns, every app it started is ended (one still running is
killed), and the test fails for what the app did wrong:

- what the strict `Vt` emulator, fed the same bytes as the screen, could not
  take: an unknown sequence, a print that wraps or scrolls, a synchronized
  update (DEC 2026) left open;
- for an app that exited by itself, the terminal it did not give back: the
  tty not in cooked mode, the alternate screen not left, the cursor hidden.

A test that fails prints, for each app, its screen, the last frames that
changed it (`framesOnFailure`, 3), its widget tree and what the strict
emulator could not take. The log of the app and the recorded trace of the
session are not in the report yet.
