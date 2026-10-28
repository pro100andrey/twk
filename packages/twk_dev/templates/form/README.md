# form_template

A full-screen sign-up form (`Form`, `TextFormField`, `FormField`): a name,
an email, an age and the newsletter, what is wrong said under each field.
Enter goes to the next field and from the last submits, as Ctrl+S and the
button do; once every field is right, who signed up shows under the form.
Ctrl+Q quits.

Made by `twk create --template=form`, on the widgets of twk.

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
- `lib/form_template.dart` is the app.
- `test/form_template_test.dart` tests it.
