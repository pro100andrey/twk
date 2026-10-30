# Examples

`tally.dart` is an app to try the `twk` command on: Up and Down choose a
line, `+` and `-` count it, `q` quits; each count goes to the app's log.
`tally.tape` records a session of it. From the package's directory:

```bash
dart run twk_dev:twk run example/tally.dart     # hot reloaded
dart run twk_dev:twk logs                       # its log, in another terminal
dart run twk_dev:twk inspect                    # its widgets, in another terminal
dart run twk_dev:twk tape example/tally.tape    # build/tally.cast and .svg
```

An app of your own starts from a template:

```bash
dart pub global activate twk_dev
twk create my_app
cd my_app && dart run twk_dev:twk run bin/main.dart
```

The package's
[README](https://github.com/pro100andrey/twk/tree/main/packages/twk_dev#a-walkthrough)
walks through the tools with the tally.
