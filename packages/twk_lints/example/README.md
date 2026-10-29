# Using twk_lints

An app built on twk takes the plugin as a dev dependency:

```yaml
# pubspec.yaml
dev_dependencies:
  twk_lints: ^0.1.0
```

and includes its recommended set, every rule on:

```yaml
# analysis_options.yaml
include: package:twk_lints/recommended.yaml
```

`dart analyze` and the editor then report what the rules find, such as a
`setState` that may run after the state was disposed:

```dart
Future<void> _load() async {
  final items = await fetch();
  setState(() => _items = items); // set_state_after_dispose
}
```

and the editor offers the plugin's fixes (`Add 'if (!mounted) return;'`)
and assists (wrap a widget, extract one, convert a stateless widget to a
stateful one) at the cursor.
