<!-- Written by tool/skill_references from doc/widgets; do not edit. -->
# Text

Paragraphs and spans of styled text, wrapped, cut off, aligned, and right to left.

[All widgets](../widgets.md)

## Text

A paragraph in one style, its lines broken to fit, cut off and aligned as asked.

API: [`Text`](https://pub.dev/documentation/twk/latest/twk/Text-class.html).

### Code

```dart
final theme = Theme.of(context);
return SizedBox(
  width: 32,
  child: Box(
    border: .all(type: .rounded, style: theme.border),
    child: Text(
      'Terminals draw text in a grid of cells. A paragraph breaks its '
      'lines between words to fit its width; wide characters, 漢字 and '
      '🙂, take two cells each.',
      wrap: .word,
      overflow: .ellipsis,
      textAlign: .left,
    ),
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| wrap | word, grapheme, none | word |
| overflow | clip, ellipsis, ellipsisStart, ellipsisMiddle | ellipsis |
| align | left, center, right, justify | left |
| max lines | all, 3, 1 | all |
| width | 14 cells to 50 cells | 32 |

## Rich text

Spans in styles of their own: attributes, colors and links, 'text'.bold.fg(…) for short.

### Code

```dart
final theme = Theme.of(context);
return Text.rich([
  Span('attributes\n', theme.muted),
  'bold'.bold,
  const Span(' '),
  'dim'.dim,
  const Span(' '),
  'italic'.italic,
  const Span(' '),
  'reverse'.reverse,
  const Span(' '),
  'strike'.strike,
  const Span(' '),
  'overline'.overline,
  const Span('\n\n'),
  Span('underlines\n', theme.muted),
  'underline'.underline,
  const Span(' '),
  'double'.doubleUnderline,
  const Span(' '),
  'curly'.curlyUnderline,
  const Span(' '),
  'dotted'.dottedUnderline,
  const Span(' '),
  'dashed'.dashedUnderline,
  const Span('\n\n'),
  Span('colors\n', theme.muted),
  'red'.fg(.red),
  const Span(' '),
  'color 166'.fg(const .indexed(166)),
  const Span(' '),
  'rgb'.fg(const .rgb(64, 128, 224)),
  const Span(' '),
  ' on navy '.fg(.white).bg(const .indexed(17)),
  const Span(' '),
  const Span(
    'red curly',
    Style(attrs: Attr.curlyUnderline, underlineColor: Color.red),
  ),
  const Span('\n\n'),
  Span('links\n', theme.muted),
  'a link to dart.dev'.link('https://dart.dev').underline,
]);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| row labels | on, off | true |

## DefaultTextStyle

The style of the text below it, which a Text merges its own over.

API: [`DefaultTextStyle`](https://pub.dev/documentation/twk/latest/twk/DefaultTextStyle-class.html).

### Code

```dart
return DefaultTextStyle(
  style: const Style(attrs: Attr.bold),
  child: const Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    children: [
      Text('This text has the default style.'),
      Text('This one merges yellow over it.', style: .new(fg: .yellow)),
    ],
  ),
);
```

### Options

| option | values | starts at |
| --- | --- | --- |
| style | bold, italic, green, on navy | bold |

## Right to left

Hebrew and Arabic among left-to-right text: put in the order it reads where the app reorders it (TextOrder.visual), left as stored where the terminal reorders it itself.

### Code

```dart
import 'package:twk/twk.dart';

// The app puts right-to-left text in the order it
// reads (TextOrder.visual), for a terminal that
// shows each character in the cell it is written to.
// Without bidi, as the terminal is found to need.
Future<void> main() =>
    runApp(const RightToLeft(), bidi: BidiReordering.app);

final class RightToLeft extends StatelessWidget {
  const RightToLeft({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 1,
      children: [
        SizedBox(
          width: 32,
          child: Box(
            border: .all(type: .rounded, style: theme.border),
            padding: const .x(1),
            child: const Text(
              'Hello is שלום in Hebrew,\n'
              'and مرحبا in Arabic.\n'
              'שלום עולם! (hello world)',
              textAlign: .start,
            ),
          ),
        ),
        Text.rich([
          Span('text order: ', theme.muted),
          Span(AppBinding.of(context).textOrder.name),
        ]),
      ],
    );
  }
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| text order | visual, logical | visual |
| align | start, end, left, right | start |

## ANSI

Output with ANSI colour codes, from a program or a log, as styled spans: all at once with parseAnsi, or as it streams in with AnsiStream.

### Code

```dart
// what `dart test` wrote to a terminal, its colours in SGR sequences
const _output =
    '\r\x1B[K00:00 \x1B[32m+0\x1B[0m: loading test/view_test.dart\r\x1B[K00:00 \x1B[32m+3\x1B[0m: test/view_test.dart: lists and their markers\r\x1B[K00:01 \x1B[32m+9\x1B[0m: test/stream_test.dart: a block settled once\r\x1B[K00:01 \x1B[32m+12\x1B[0m \x1B[33m~1\x1B[0m: test/code_test.dart: tabs\r\x1B[K00:02 \x1B[32m+16\x1B[0m \x1B[33m~1\x1B[0m: test/diff_test.dart: a gap row\r\x1B[K00:02 \x1B[32m+16\x1B[0m \x1B[33m~1\x1B[0m \x1B[31m-1\x1B[0m: test/diff_test.dart: a gap row [E]\n'
    '  Expected: \'⋯ 21 unchanged lines\'\n'
    '    Actual: \'⋯ 20 unchanged lines\'\n'
    '     Which: is different.\n'
    '\n'
    '  \x1B[2mtest/diff_test.dart 88:7  main.<fn>\x1B[22m\n'
    '\r\x1B[K00:03 \x1B[32m+21\x1B[0m \x1B[33m~1\x1B[0m \x1B[31m-1\x1B[0m: \x1B[31mSome tests failed.\x1B[0m\n';

final _lines = parseAnsi(_output);

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return SizedBox(
    width: 56,
    child: Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 1,
      children: [
        SizedBox(
          height: 9,
          child: Box(
            border: .all(type: .rounded, style: theme.border),
            titles: [BorderTitle(' dart test ', style: theme.muted)],
            child: Column(
              crossAxisAlignment: .start,
              children: [for (final line in _lines) Text.rich(line, wrap: .none)],
            ),
          ),
        ),
        Text.rich([
          Span('read: ', theme.muted),
          Span('${_output.length} characters at once, ${_lines.length} lines'),
        ]),
      ],
    ),
  );
}
```

### Options

| option | values | starts at |
| --- | --- | --- |
| output | dart test, ls, log | dart test |
| read with | parseAnsi, AnsiStream | parseAnsi |
| piece | 7 chars, 16, 64 | 7 chars |
