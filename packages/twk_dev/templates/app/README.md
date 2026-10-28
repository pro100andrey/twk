# app_template

A full-screen app: notes in a list beside the one chosen, the app's name
above them and the keys below (`KeyHintsBar`). Up and Down choose a note,
Enter opens it, where Up and Down scroll and Escape goes back; Tab moves
between the panes, a click focuses one; Ctrl+Q quits.

Made by `twk create --template=app`, on the widgets of twk.

## Run

```bash
dart pub get
dart run bin/main.dart
```

With hot reload, the files of `lib/` and `bin/main.dart` reloaded as they
change, each `State` kept (Ctrl+G H restarts the app):

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
- `lib/app_template.dart` is the app.
- `test/app_template_test.dart` tests it.
