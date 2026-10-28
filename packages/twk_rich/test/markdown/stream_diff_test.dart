// A stream against a parser that is given the whole text at once: at every
// point a document may be split, what the stream holds is what one
// BlockParser makes of the same text, blocks and definitions, with no stream
// in between (parseMarkdown is a stream itself); and the lines a parser's
// blocks start on.
import 'package:test/test.dart';
import 'package:twk_rich/src/markdown/blocks.dart';
import 'package:twk_rich/twk_rich.dart';

/// Documents whose later lines change how earlier ones parse, or that a
/// stream keeps state across: fences, lists, tables, nested quotes, line
/// endings, definitions.
const corpus = <String, String>{
  'fences': '''
```dart
void main() {
  print(1);
}
```

~~~~
not ``` closed by backticks
~~~
still code
~~~~~

```
unclosed to the end
''',
  'fence in a list': '''
- item
  ```
  code in an item

  still code
  ```
- next

1. one
   ~~~
   ten
''',
  'lists': '''
- a
- b
  - nested
    - deeper
  - [x] done
  - [ ] todo

  more of b
- c

1. first
2. second
3) another list

* loose

* items
+ new list
10. ten
- after
lazy continuation
''',
  'tables': r'''
| a | b:| c |
|:--|--:|:-:|
| 1 | 2 | 3 |
| x \| y | | |
no pipes, still a row

text before
| h |
| - |
| r |

| not | a table |
| -- |
''',
  'nested quotes': '''
> outer
> > inner
> > lazy
continues inner
>
> back in outer
> > - a list
> > - in a quote
> >   > deeper still
> >   lazy

> # heading in a quote
> ```
> code in a quote
> ```
''',
  'setext and breaks': '''
Title
=====

paragraph
---

- item
---
* * *
Para
  ===
''',
  'definitions': '''
[a]: https://a.dev
[b]: https://b.dev
  "title"
[a]: https://shadowed.dev

A [a] and [b][] and [c].

[c]: <https://c.dev> 'c'
Heading
-------

[d]:
https://d.dev
''',
  'indented code': '''
    code
      more

    after a blank
para
    not code
''',
  'crlf': '# h\r\n\r\n- a\r\n- b\r\n\r\n```\r\ncode\r\n```\r\n> q\r\nlazy\r\n',
  'lone cr': '# h\r\rpara\rmore\r\r| a |\r| - |\r| 1 |\r- x\r  - y\r',
  'mixed endings': 'a\r\nb\rc\n\r\n```\r\n\rx\n```\r',
  'tabs and nul': '-\tone\n\t-\ttwo\n\n>\tquote\n\n\tcode\u0000\n',
};

/// What one parser makes of [text] whole: its lines, the last one too
/// whether it ends or not, as [MarkdownStream] splits them.
({List<MdBlock> blocks, Map<String, MdDefinition> definitions}) whole(
  String text,
) {
  final parts = text.replaceAll('\u0000', '�').split(RegExp('\r\n|\r|\n'));
  final parser = BlockParser();
  for (var k = 0; k < parts.length - 1; k++) {
    parser.add(parts[k]);
  }
  if (parts.last.isNotEmpty) {
    parser.add(parts.last);
  }
  final blocks = <MdBlock>[];
  final definitions = <String, MdDefinition>{};
  for (final top in parser.finish()) {
    if (top.block case final block?) {
      blocks.add(block);
    }
    for (final definition in top.definitions) {
      definitions.putIfAbsent(
        normalizeLabel(definition.label),
        () => definition,
      );
    }
  }
  return (blocks: blocks, definitions: definitions);
}

void expectWhole(MarkdownStream stream, String text, String reason) {
  final expected = whole(text);
  expect(stream.blocks, expected.blocks, reason: reason);
  expect(stream.definitions, expected.definitions, reason: reason);
  expect(stream.live, expected.blocks, reason: reason);
}

void main() {
  for (final MapEntry(key: name, value: text) in corpus.entries) {
    group(name, () {
      test('a character at a time, every prefix is what a parser makes of '
          'it whole', () {
        final stream = MarkdownStream();
        for (var k = 0; k < text.length; k++) {
          stream.add(text[k]);
          expectWhole(stream, text.substring(0, k + 1), 'after ${k + 1}');
        }
      });

      test('in two pieces split anywhere, each is what a parser makes of '
          'the text so far', () {
        for (var at = 0; at <= text.length; at++) {
          final stream = MarkdownStream(text.substring(0, at));
          expectWhole(stream, text.substring(0, at), 'first $at');
          stream.add(text.substring(at));
          expectWhole(stream, text, 'split at $at');
        }
      });

      test('in pieces of every size, closed, every block is settled and '
          'what a parser makes of it whole', () {
        for (var size = 1; size <= 12; size++) {
          final stream = MarkdownStream();
          final history = <MdBlock>[];
          for (var at = 0; at < text.length; at += size) {
            final end = at + size < text.length ? at + size : text.length;
            stream.add(text.substring(at, end));
            history.addAll(stream.takeSettled());
            expect(
              stream.live,
              stream.blocks.sublist(history.length),
              reason: 'size $size at $end',
            );
          }
          stream.close();
          history.addAll(stream.takeSettled());
          final expected = whole(text);
          expect(stream.settled, expected.blocks.length, reason: '$size');
          expect(stream.blocks, expected.blocks, reason: '$size');
          expect(history, hasLength(expected.blocks.length), reason: '$size');
        }
      });
    });
  }

  test('a parser tells the line each top-level block starts on, those it '
      'forgot left out', () {
    final parser = BlockParser();
    for (final line in ['# a', '', 'b', 'c', '', '- d', '  e']) {
      parser.add(line);
    }
    expect(parser.starts, [0, 2, 5]);
    expect(parser.closed, 2);
    parser.forget(1);
    expect(parser.starts, [2, 5]);
  });
}
