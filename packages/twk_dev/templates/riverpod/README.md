# riverpod_template

A counter with its state in riverpod: the count in a box; Up and Down change it,
r resets it, q quits. Made by `twk create --template=riverpod`, on the widgets of
twk and [twk_riverpod](https://pub.dev/packages/twk_riverpod).

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

## Files

- `bin/main.dart` runs the app.
- `lib/riverpod_template.dart` is the state and the app.
- `test/riverpod_template_test.dart` tests it.
