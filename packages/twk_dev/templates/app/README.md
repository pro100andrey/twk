# app_template

A full-screen app: notes in a list beside the one chosen, the app's name
above them and the keys below (`KeyHintsBar`). Up and Down choose a note,
Enter opens it, where Up and Down scroll and Escape goes back; Tab moves
between the panes, a click focuses one; Ctrl+Q quits.

Made by `twk create --template=app`, on the widgets of twk.

## Run

```bash
dart pub get
dart run --enable-asserts bin/main.dart
```

With hot reload, the files of `lib/` and `bin/main.dart` reloaded as they
change, each `State` kept (Ctrl+G H restarts the app), and asserts on, which
the framework's checks and overflow warnings need (`--no-asserts` runs the
app without them, for measuring):

```bash
dart run twk_dev:twk run bin/main.dart
```

`dart run twk_dev:twk inspect`, in a second terminal in this directory,
shows its widget tree; `TWK_DEBUG=console dart run bin/main.dart` turns on
the debug keys and opens the log, where `print` and `log()` go.

## Test

```bash
dart test
dart analyze
dart format --output=none --set-exit-if-changed .
```

`testTwk` (twk_test) runs the app on a terminal in memory: keys go in as a
terminal sends them, the screen is read back, and timers move only when the
test says, so a test has no sleeps and no flakes.
`driverTest` (`package:twk_test/driver.dart`, tagged `process`) runs the app
as a real process in a pseudo-terminal, as a user's terminal does, and reads
its screen back through an emulator.

## Files

- `bin/main.dart` runs the app.
- `lib/app_template.dart` is the app.
- `test/app_template_test.dart` tests it.
- `test/app_template_driver_test.dart` runs it as a process.
