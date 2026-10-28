# dashboard_template

A full-screen dashboard of readings taken every second: the CPU in a line
chart of the last minute (`Chart`), the memory in a gauge (`LineGauge`) and
the requests to each service in bars (`BarChart`). The readings are made up
in `lib/`, where the real ones are to be read. `p` pauses and resumes, `q`
and Ctrl+Q quit.

Made by `twk create --template=dashboard`, on the widgets of twk.

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
- `lib/dashboard_template.dart` is the app.
- `test/dashboard_template_test.dart` tests it.
