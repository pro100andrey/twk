# twk_lints

Lints and editor assists for apps built on
[twk](https://pub.dev/packages/twk). They catch the mistakes a terminal app
makes most often, as you type and in `dart analyze`, and they offer quick
fixes for some of them.

## Features

- **Warnings that are on by default:** `set_state_after_dispose` finds a
  `setState` that may run after the widget has gone, such as one that follows
  an `await` with no check of `mounted`. `context_after_await` does the same
  for a `context`. `dispose_controllers` finds a controller or a `FocusNode`
  that the state creates and never disposes.
- **Key names:** `key_names` finds a binding such as `ctrl+i` that a terminal
  without the kitty keyboard protocol sends as `tab`, so that it never fires
  there.
- **Lints you turn on:** a missing key on the stateful widgets of a list, a
  `Table` whose row type is lost, an `InputListener` that `KeyBindings` would
  do better, a wait on the wall clock in a test, and a control a screen reader
  cannot name.
- **Quick fixes:** such as *Add 'if (!mounted) return;'*, where the editor
  shows a warning.
- **Assists at the cursor:** wrap a widget, extract it into a new one, remove
  it, swap it with its parent or child, move it up or down, and convert a
  stateless widget to a stateful one and back.

## Getting started

Needs Dart 3.13.5 or later. Add the package as a dev dependency:

```sh
dart pub add dev:twk_lints
```

and include its recommended set, with every rule on, in the
`analysis_options.yaml` at the root of your package:

```yaml
include: package:twk_lints/recommended.yaml
```

Beside other sets, it is a list:

```yaml
include:
  - package:pro_lints/recommended.yaml
  - package:twk_lints/recommended.yaml
```

`dart analyze` and your editor then report what the rules find. This code:

```dart
Future<void> _load() async {
  final items = await fetch();
  setState(() => _items = items);
}
```

in a `State` of a twk widget gets

```text
warning - lib/a.dart:17:5 - 'setState' may run after 'dispose': it follows an
'await', with no check of 'mounted'. Try 'if (!mounted) return;' before it.
- set_state_after_dispose
```

The first analysis after the change compiles the plugin and takes a while;
an editor's analysis server picks the change up when it restarts.

To silence a rule on one line, write the plugin's name before it:
`// ignore: twk_lints/set_state_after_dispose`.

## Learn more

- [Reference](https://github.com/pro100andrey/twk/blob/main/packages/twk_lints/doc/reference.md):
  every rule, fix and assist in full, and how to turn a rule off.
- [How it works and is tested](https://github.com/pro100andrey/twk/blob/main/packages/twk_lints/doc/internals.md):
  for those who work on the package.
- [What the plugin costs](https://github.com/pro100andrey/twk/blob/main/packages/twk_lints/doc/lints-performance.md):
  time and allocations of each rule.
- [Lint candidates](https://github.com/pro100andrey/twk/blob/main/packages/twk_lints/doc/lint-candidates.md):
  the rules that were considered, built or not, and why.
- [twk](https://pub.dev/packages/twk): the framework the rules are for.

## License

MIT, copyright 2026 Andrii Ivanov: [LICENSE](LICENSE).
