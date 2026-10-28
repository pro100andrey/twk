# inline_template

An inline app, in rows below the shell's prompt: each line sent goes to the
terminal's scrollback (`Static`) with the app's answer under it, a spinner
turning while the app thinks; the field and the keys alone stay in the app's
rows, left on the screen when it ends. Enter sends, Ctrl+Q quits.

Made by `twk create --template=inline`, on the widgets of twk.

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
- `lib/inline_template.dart` is the app.
- `test/inline_template_test.dart` tests it.
