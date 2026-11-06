<!-- Written by tool/skill_references from doc/widgets; do not edit. -->
# Rich

Markdown, code, diffs, JSON, big text, QR codes and program output with its colors.

[All widgets](../widgets.md)

## MarkdownView

A Markdown document as widgets, a blank row between the blocks; its links the app's with onLinkTap, a MarkdownController scrolling to a heading.

Package: `twk_rich`.

### Code

```dart
const _notes =
    '# Release notes\n'
    '\n'
    '**twk_rich** puts *rich text* in the terminal: Markdown, code and diffs, '
    'each a widget.\n'
    '\n'
    'Jump to [what is new](#what-is-new) or [still to come](#still-to-come).\n'
    '\n'
    '## What is new\n'
    '\n'
    '- `MarkdownView` streams an answer in\n'
    '- `CodeView` highlights ten languages\n'
    '  - Dart, Rust, Go and Python\n'
    '  - JSON, YAML and Bash\n'
    '- `DiffView` marks the words that changed\n'
    '\n'
    '1. Add the package:\n'
    '2. Import `package:twk_rich/twk_rich.dart`\n'
    '3. Show a document\n'
    '\n'
    '```bash\n'
    'dart pub add twk_rich\n'
    '```\n'
    '\n'
    '```dart\n'
    "final notes = await File('NOTES.md').readAsString();\n"
    'runApp(SingleChildScrollView(\n'
    '  child: MarkdownView(notes),\n'
    '));\n'
    '```\n'
    '\n'
    '> Every block is a widget: this quote, the lists above and the table '
    'below.\n'
    '\n'
    '| widget       | shows       | scrolls |\n'
    '|:-------------|:------------|:-------:|\n'
    '| MarkdownView | documents   |   no    |\n'
    '| CodeView     | source code |   no    |\n'
    '| DiffView     | changes     |   yes   |\n'
    '\n'
    '### Still to come\n'
    '\n'
    '- [x] tables and task lists\n'
    '- [ ] ~~images~~ pictures in cells\n'
    '\n'
    'Read the [guide](https://dart.dev/tools) for more.\n'
    '\n'
    '---';

@override
Widget build(BuildContext context) => SizedBox(
  width: 50,
  height: 24,
  child: Scrollbar(
    style: Theme.of(context).border,
    child: SingleChildScrollView(
      child: MarkdownView(_notes),
    ),
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| content | document, chat answer | document |
| code wrap | grapheme, word, none | grapheme |
| width | 30 cells to 72 cells | 50 |
| links go to | the terminal, the app, the app only | the terminal |

## CodeView

Source code highlighted for its language, with line numbers, its long lines wrapped or cut off at the width; a CodeViewController scrolls it to a line, highlights lines and finds text.

Package: `twk_rich`.

### Code

```dart
const _source = r'''
import 'package:twk/twk.dart';

/// Counts the presses of the space bar.
final class Counter extends StatefulWidget {
  const Counter({super.key, this.start = 0});

  final int start;

  @override
  State<Counter> createState() => _CounterState();
}

final class _CounterState extends State<Counter> {
  late var _count = widget.start;

  @override
  Widget build(BuildContext context) => KeyBindings(
    {'space': () => setState(() => _count++)},
    child: Text('Pressed $_count times, ${_count.isEven ? 'even' : 'odd'}'),
  );
}
''';

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return SizedBox(
    width: 56,
    height: 22,
    child: Scrollbar(
      style: theme.border,
      child: SingleChildScrollView(
        child: CodeView(
          _source,
          language: dartLanguage,
          lineNumbers: true,
          wrap: .word,
        ),
      ),
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| language | Dart, Python, Rust, Go, JavaScript, TypeScript, JSON, YAML, Bash, diff, plain | Dart |
| line numbers | on, off | true |
| changes | on, off | false |
| wrap | none, word, grapheme | word |
| width | 24 cells to 80 cells | 56 |
| rows | all, 10 | all |
| first line | 1, 120 | 1 |
| to line 18 | none, least, ½ | none |
| highlight | none, 14, 13–16 | none |
| find | on, off | false |

## SyntaxThemeScope

The styles of the code below it, a style for each kind of token, in place of those derived from the theme: a SyntaxTheme of its own, or the derived one with a few changed.

Package: `twk_rich`.

### Code

```dart
const _source = r'''
/// Says hello to the user, twice.
@override
Widget build(BuildContext context) {
  final name = 'user', times = 2;
  return Text('Hello, $name! ' * times);
}
''';

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return SyntaxThemeScope(
    // the theme derived from the Theme, three kinds
    // of token changed
    theme: SyntaxTheme.from(theme).copyWith(
      keyword: theme.error.merge(const .new(attrs: Attr.bold)),
      string: theme.warning,
      comment: theme.muted,
    ),
    child: const CodeView(_source, language: dartLanguage),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| syntax theme | copyWith, own, none | copyWith |

## DiffView

The changes between two texts, unified or side by side, the words that changed marked and both sides highlighted.

Package: `twk_rich`.

### Code

```dart
const _before = r'''
import 'dart:io';

/// Greets [name] on the terminal.
String greet(String name) {
  return 'Hello, ' + name + '!';
}

/// The names to greet, one a line.
List<String> readNames(String path) {
  final file = File(path);
  final lines = file.readAsLinesSync();
  return lines.where((l) => l.isNotEmpty).toList();
}

void main(List<String> args) {
  final names = readNames(args.first);
  for (final name in names) {
    print(greet(name));
  }
  print('Greeted ${names.length} names.');
}
''';

const _after = r'''
import 'dart:io';

/// Greets [name] on the terminal, in [language].
String greet(String name, {String language = 'en'}) {
  return '${hello[language]}, $name!';
}

const hello = {'en': 'Hello', 'uk': 'Привіт'};

/// The names to greet, one a line.
List<String> readNames(String path) {
  final file = File(path);
  final lines = file.readAsLinesSync();
  return lines.where((l) => l.isNotEmpty).toList();
}

void main(List<String> args) {
  final names = readNames(args.first);
  final language = args.length > 1 ? args[1] : 'en';
  for (final name in names) {
    print(greet(name, language: language));
  }
}
''';

final _diff = Diff.between(_before, _after, path: 'bin/greet.dart');

@override
Widget build(BuildContext context) {
  return SizedBox(
    width: 56,
    height: 22,
    child: Scrollbar(
      style: Theme.of(context).border,
      child: DiffView(_diff),
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| layout | unified, sideBySide | unified |
| context | 3 lines, 1, 0 | 3 lines |
| edit live | on, off | false |
| language | the path's, plain | the path's |

## JsonView

JSON or a Dart value as a tree that folds, each kind of value in its color: c copies the path of the value selected, y the value, / filters the keys.

Package: `twk_rich`.

### Code

```dart
static const _package = {
  'name': 'twk',
  'version': '0.1.0',
  'description': 'Widgets for terminal apps, laid out as Flutter lays them',
  'private': true,
  'score': 0.97,
  'homepage': null,
  'environment': {'sdk': '^3.13.5'},
  'dependencies': {'args': '^2.7.0', 'meta': '^1.16.0', 'path': '^1.9.1'},
  'scripts': ['quick', 'handover', 'bench'],
};

final _view = JsonViewController();
var _copied = '';

@override
void dispose() {
  _view.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    spacing: 1,
    children: [
      SizedBox(
        width: 50,
        height: 14,
        child: JsonView(
          value: _package,
          controller: _view,
          onPathCopied: (path) => setState(() => _copied = path),
        ),
      ),
      Text.rich([
        Span('copied: ', theme.muted),
        if (_copied.isEmpty)
          Span('nothing', theme.muted)
        else
          Span(_copied),
      ]),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| expanded depth | 1, 2, 0 | 1 |
| sort keys | on, off | false |
| strings cut at | 200, 24 | 200 |

## BigText

Text in letters several cells tall, drawn with full or half blocks or with box drawing, in a font of its own.

Package: `twk_rich`.

### Code

```dart
final _controller = TextEditingController(text: 'Hello');
final _focus = FocusNode(debugLabel: 'text');

@override
void initState() {
  super.initState();
  _focus.addListener(() => setState(() {}));
}

@override
void dispose() {
  _controller.dispose();
  _focus.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Column(
    mainAxisSize: .min,
    spacing: 1,
    children: [
      // what the field and the gap leave: the font that fits in it
      Flexible(child: BigText(_controller.text, style: theme.primary)),
      SizedBox(
        width: 30,
        child: Box(
          border: .all(
            type: .rounded,
            style: _focus.hasFocus ? theme.primary : theme.border,
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            placeholder: 'type here',
            maxLength: 24,
            onChanged: (_) => setState(() {}),
          ),
        ),
      ),
    ],
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| font | fit, large, block, thin, small | fit |
| text | typed, clock, two lines | typed |
| align | left, center, right | left |
| style | primary, accent, success, warning, info | primary |

## QrCode

Text as a QR code a phone's camera reads: in half blocks, two modules to a cell, black on white whatever the theme, with as much of the quiet zone around it as the rows allow.

Package: `twk_rich`.

### Code

```dart
@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  // the mode of fewest bits, the smallest version, the
  // mask the penalty rules score lowest
  final symbol = QrSymbol.encode('20261019', level: .medium);
  return LayoutBuilder(
    builder: (context, constraints) => Row(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 2,
      children: [
        // in half blocks, black on white; in fewer rows than it
        // asks for, a narrower quiet zone, the whole symbol shown
        QrCode.symbol(
          symbol,
          quietZone: ((2 * constraints.maxHeight - symbol.size) ~/ 2).clamp(0, 4),
        ),
        Text.rich([
          Span('version ', theme.muted),
          Span('${symbol.version}\n'),
          Span('mask ', theme.muted),
          Span('${symbol.mask}\n'),
          Span('mode ', theme.muted),
          Span(symbol.mode.name),
          // taller than the rows there are even without a quiet
          // zone: cut off at its bottom, which a camera can't read
          if ((symbol.size + 1) ~/ 2 > constraints.maxHeight) ...[
            Span('\n\nneeds ', theme.warning),
            Span('${(symbol.size + 1) ~/ 2} rows'),
          ],
        ]),
      ],
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| text | link, wifi, digits | digits |
| level | low, medium, quartile, high | medium |
| quiet zone | 0 modules to 4 modules | 4 |
| inverted | on, off | false |
