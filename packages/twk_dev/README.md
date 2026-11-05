# twk_dev

The `twk` command: the developer tools for apps built with
[twk](https://pub.dev/packages/twk). Start an app from a template, change its
code while it runs, look inside it, read its log and record a session.

## Features

- **Create:** `twk create` writes a new app from a template (`app`, `inline`,
  `form` or `dashboard`). It runs, analyzes and passes its tests as it is.
- **Hot reload:** `twk run` runs your app and reloads the code you save. The
  state of every widget is kept.
- **Inspect:** `twk inspect` shows a running app's widget tree or render
  tree, with the properties and layout of the node you select. Click in the
  app to pick a node.
- **Logs:** `twk logs` tails the log of a running app, with levels and
  colours, while the app owns the screen.
- **Debugger:** `twk shell` lends its terminal to an app started from the
  IDE, where the app has no terminal of its own.
- **Record:** `twk record` and `twk play` record a session of an app as
  asciicast v2 and play it back. A recording can be a test.
- **Tapes:** `twk tape` runs a script of keys to type and screens to wait
  for, and writes the session as an animated SVG, to show an app in a README.

## Getting started

```sh
dart pub global activate twk_dev
twk create my_app
cd my_app
dart pub get
dart run twk_dev:twk run bin/main.dart
```

`twk create` makes `my_app` with a notes app in it: a list beside the note
chosen, full screen. `twk run` runs it in your terminal. Edit a file in
`my_app/lib/` and save: the app shows the change, and keeps its state.
Ctrl+G H starts it again, Ctrl+Q quits.

The app takes `twk_dev` as a dev dependency, so `dart run twk_dev:twk` runs
the version its lock file names. In a second terminal in the same directory,
`dart run twk_dev:twk inspect` shows the widgets of the running app.

`twk run` has been run on Linux. It has not been run on Windows or macOS.

## Learn more

- [The commands](https://github.com/pro100andrey/twk/blob/main/packages/twk_dev/doc/commands.md):
  all of them in a table, and how they find the project.
- [A walkthrough](https://github.com/pro100andrey/twk/blob/main/packages/twk_dev/doc/walkthrough.md):
  the tools, one after the other, on a small app.
- [twk create](https://github.com/pro100andrey/twk/blob/main/packages/twk_dev/doc/create.md):
  the templates and the options.
- [twk run](https://github.com/pro100andrey/twk/blob/main/packages/twk_dev/doc/run.md):
  hot reload and restart.
- [twk inspect](https://github.com/pro100andrey/twk/blob/main/packages/twk_dev/doc/inspect.md):
  the inspector's screen and keys.
- [twk logs](https://github.com/pro100andrey/twk/blob/main/packages/twk_dev/doc/logs.md)
  and [twk shell](https://github.com/pro100andrey/twk/blob/main/packages/twk_dev/doc/shell.md):
  the log, and the terminal for an app under a debugger.
- [twk record and twk play](https://github.com/pro100andrey/twk/blob/main/packages/twk_dev/doc/record-play.md):
  recordings, and a recording as a test.
- [twk tape](https://github.com/pro100andrey/twk/blob/main/packages/twk_dev/doc/tape.md):
  the tape language, in full.
- [How it is laid out and tested](https://github.com/pro100andrey/twk/blob/main/packages/twk_dev/doc/internals.md):
  for those who work on the package.

## License

MIT, copyright 2026 Andrii Ivanov: [LICENSE](LICENSE).
