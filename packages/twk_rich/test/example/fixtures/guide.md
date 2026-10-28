# Greet

A tool that greets people by name, in **English**, *Ukrainian* or
Japanese (こんにちは). See [the Dart site](https://dart.dev) for the SDK.

## Usage

Run it with the names to greet:

```bash
dart run lib/greet.dart Ada Linus
```

Each name is greeted on a line of its own:

1. the names are read from the arguments;
2. each is greeted in `language`, English by default;
   - `uk` greets in Ukrainian,
   - `ja` in Japanese.

## Code

```dart
String greet(String name, {String language = 'en'}) {
  final hello = switch (language) {
    'uk' => 'Привіт',
    'ja' => 'こんにちは',
    _ => 'Hello',
  };
  return '$hello, $name!';
}
```

> A greeting is one line: a name longer than the terminal is cut off by
> the terminal, not by the tool.

## Languages

| code | language  | greeting  |
|------|-----------|----------:|
| en   | English   | Hello     |
| uk   | Ukrainian | Привіт    |
| ja   | Japanese  | こんにちは |

## Plans

- [x] greet in three languages
- [ ] read the names from a file
- [ ] ~~greet in Latin~~

---

Written for the viewer of `twk_rich`.
