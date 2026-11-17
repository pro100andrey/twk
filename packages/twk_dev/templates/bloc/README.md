# bloc_template

A counter with its state in bloc: the count in a box; Up and Down change it,
r resets it, q quits. Made by `twk create --template=bloc`, on the widgets of
twk and [twk_bloc](https://pub.dev/packages/twk_bloc).

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

`testTwk` (twk_test) runs the app on a terminal in memory under a fake
clock: keys go in as a terminal sends them, the screen is read back.

## Files

- `bin/main.dart` runs the app.
- `lib/bloc_template.dart` is the state and the app.
- `test/bloc_template_test.dart` tests it.
