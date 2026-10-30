// Markdown added in pieces: it parses as it would whole, and the blocks
// complete before a piece arrives are the same objects after it.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:twk_rich/src/markdown/inlines.dart' show parsedUnits;
import 'package:twk_rich/twk_rich.dart';

/// A document with every kind of block, nested, as an agent may write one.
const document = r'''
# Streaming

Some *emphasis*, **strong**, ~~struck~~ and `code`, a [link](https://x.dev "t")
and www.example.com, ![an image](i.png), a [reference][ref] defined below.

Setext heading
--------------

- one
- two
  - nested
  - [x] done

  more of two
- three

1. first
2) second

> quoted *text*
continued lazily
>
> - a list in a quote
>   ```
>   code in a list in a quote
>   ```

```dart
void main() {}

```

    indented code

[Ref]: https://r.dev
  "r"

| a | b:|
|:--|--:|
| 1 | 2 |
| 3 \| x |

* * *

- [ ] last
''';

/// [text] added to a stream in two pieces split at [at]; checks that the
/// blocks settled after the first piece are the same objects after the
/// second, and that the whole parses as it would in one piece, link
/// reference definitions too.
void split(String text, int at) {
  final stream = MarkdownStream(text.substring(0, at));
  final before = stream.blocks;
  final settled = stream.settled;
  stream.add(text.substring(at));
  final reason = 'split at $at of ${jsonEncode(text)}';
  expect(stream.blocks, parseMarkdown(text), reason: reason);
  expect(stream.definitions, MarkdownStream(text).definitions, reason: reason);
  expect(stream.settled, greaterThanOrEqualTo(settled), reason: reason);
  for (var k = 0; k < settled; k++) {
    expect(identical(stream.blocks[k], before[k]), isTrue, reason: reason);
  }
}

void main() {
  test('the document has a block of every kind and a reference', () {
    expect(MarkdownStream(document).definitions, const {
      'REF': MdDefinition('Ref', 'https://r.dev', title: 'r'),
    });
    final kinds = parseMarkdown(document).map((b) => b.runtimeType).toSet();
    expect(kinds, {
      MdHeading,
      MdParagraph,
      MdList,
      MdBlockQuote,
      MdCodeBlock,
      MdTable,
      MdThematicBreak,
    });
  });

  test('split anywhere, the document parses as it does whole', () {
    for (var at = 0; at <= document.length; at++) {
      split(document, at);
    }
  });

  test('a fenced block streamed a character at a time, its code joined as '
      'it grows, is at each one what its text so far parses to', () {
    const text =
        '```dart\nfinal a = 1;\n\nfinal b = 2;\n```\n'
        '- item\n\n  ```\n  in a list\n  two\n  ```\n'
        '> ~~~\n> in a quote\n> two\n> ~~~\n';
    final stream = MarkdownStream();
    for (var k = 0; k < text.length; k++) {
      stream.add(text[k]);
      expect(
        stream.blocks,
        parseMarkdown(text.substring(0, k + 1)),
        reason: jsonEncode(text.substring(0, k + 1)),
      );
    }
  });

  test('added a character at a time, settled blocks never change', () {
    final stream = MarkdownStream();
    final seen = <MdBlock>[];
    for (var k = 0; k < document.length; k++) {
      stream.add(document[k]);
      for (var b = 0; b < seen.length; b++) {
        expect(identical(stream.blocks[b], seen[b]), isTrue, reason: '$k');
      }
      seen.addAll(stream.blocks.sublist(seen.length, stream.settled));
    }
    expect(stream.blocks, parseMarkdown(document));
    expect(seen, hasLength(stream.blocks.length - 1));
  });

  test('added a character at a time, a block equal to what it was is the '
      'same object', () {
    final stream = MarkdownStream();
    var before = stream.blocks;
    var kept = 0;
    for (var k = 0; k < document.length; k++) {
      stream.add(document[k]);
      final after = stream.blocks;
      for (var b = 0; b < before.length && b < after.length; b++) {
        if (after[b] == before[b]) {
          expect(identical(after[b], before[b]), isTrue, reason: '$k');
          kept++;
        }
      }
      before = after;
    }
    expect(kept, greaterThan(document.length));
  });

  test('every CommonMark example parses the same split anywhere', () {
    final examples = jsonDecode(
      File('test/markdown/spec.json').readAsStringSync(),
    ) as List<Object?>;
    for (final example in examples) {
      if (example case {'markdown': final String markdown}) {
        for (var at = 0; at <= markdown.length; at++) {
          split(markdown, at);
        }
        final stream = MarkdownStream();
        for (var k = 0; k < markdown.length; k++) {
          stream.add(markdown[k]);
        }
        expect(stream.blocks, parseMarkdown(markdown), reason: markdown);
      }
    }
  });

  group('read after each character, what the text so far parses to', () {
    /// [text] streamed a character at a time, its blocks read after each
    /// and held to what the text so far parses to whole.
    void streamed(String text) {
      final stream = MarkdownStream();
      for (var k = 0; k < text.length; k++) {
        stream.add(text[k]);
        final so = text.substring(0, k + 1);
        expect(stream.blocks, parseMarkdown(so), reason: jsonEncode(so));
      }
    }

    for (final file in ['spec.json', 'gfm.json']) {
      test('every example of $file', () {
        final examples = jsonDecode(
          File('test/markdown/$file').readAsStringSync(),
        ) as List<Object?>;
        for (final example in examples) {
          if (example case {'markdown': final String markdown}) {
            streamed(markdown);
          }
        }
      });
    }

    // what inline parsing decides by: emphasis, brackets, code spans,
    // autolinks, entities, escapes and breaks, among plain words
    const pieces = [
      'word ',
      'a',
      'b ',
      ' ',
      '  ',
      '\n',
      '*',
      '**',
      '_',
      '__',
      '~',
      '~~',
      '`',
      '``',
      '[',
      ']',
      '](',
      '(',
      ')',
      '![',
      '<',
      '>',
      'http://x.dev',
      'www.y.org',
      'a@b.cd',
      '&amp;',
      '&am',
      r'\',
      '!',
      '"',
      "'",
      ':',
      '[ref]',
      '[ref]: /u\n',
      'é',
      '🙂',
      '.',
      ',',
      'foo_bar',
      ' * ',
      '日本語',
      '。',
      'тест',
      '\u00a0',
    ];
    for (var seed = 0; seed < 40; seed++) {
      test('random inline text (seed $seed)', () {
        final random = Random(seed);
        final text = StringBuffer();
        while (text.length < 300) {
          text.write(pieces[random.nextInt(pieces.length)]);
        }
        streamed('$text');
      });
    }
  });

  group('settled', () {
    test('a block settles once the next one starts', () {
      final stream = MarkdownStream('# Title\n\nFirst');
      expect(stream.settled, 1);
      stream.add(' paragraph.\n');
      expect(stream.settled, 1);
      stream.add('\nSecond');
      expect(stream.settled, 2);
      expect(stream.blocks, hasLength(3));
    });

    test('a paragraph does not settle on a partial line that may continue '
        'it', () {
      final stream = MarkdownStream('Text\n#');
      expect(stream.blocks, [
        const MdParagraph([MdText('Text')]),
        const MdHeading(1, []),
      ]);
      expect(stream.settled, 0);
      stream.add('2 is not a heading');
      expect(stream.blocks, [
        const MdParagraph([
          MdText('Text'),
          MdSoftBreak(),
          MdText('#2 is not a heading'),
        ]),
      ]);
    });

    test('a paragraph does not settle before a line that may underline '
        'it', () {
      final stream = MarkdownStream('Title\n');
      expect(stream.settled, 0);
      stream.add('===\n');
      expect(stream.blocks, [
        const MdHeading(1, [MdText('Title')]),
      ]);
    });

    test('the lines of settled blocks are not parsed again', () {
      final stream = MarkdownStream('```\nunclosed\n```\n\nnext');
      expect(stream.settled, 1);
      stream.add('\n\n```\nfence\n');
      expect(
        stream.blocks.first,
        const MdCodeBlock('unclosed\n', fenced: true),
      );
      expect(stream.blocks.last, const MdCodeBlock('fence\n', fenced: true));
    });
  });

  group('link reference definitions', () {
    test('one after its reference changes the definitions, not the settled '
        'block', () {
      final stream = MarkdownStream('[a]\n\nnext\n');
      final block = stream.blocks.first;
      expect(stream.settled, 1);
      expect(stream.definitions, isEmpty);
      stream.add('\n[a]: /x\n');
      expect(identical(stream.blocks.first, block), isTrue);
      expect(stream.definitions, const {'A': MdDefinition('a', '/x')});
      expect(
        resolveInlines((block as MdParagraph).children, stream.definitions),
        const [
          MdLink('/x', [MdText('a')]),
        ],
      );
    });

    test('one may change until its paragraph settles', () {
      final stream = MarkdownStream('[a]: /x');
      expect(stream.blocks, isEmpty);
      expect(stream.definitions, const {'A': MdDefinition('a', '/x')});
      stream.add('y\n"t"\n');
      expect(stream.definitions, const {
        'A': MdDefinition('a', '/xy', title: 't'),
      });
      stream.add('more\n\n[a]: /z\n');
      expect(stream.blocks, const [
        MdParagraph([MdText('more')]),
      ]);
      expect(stream.settled, 1);
      expect(stream.definitions, const {
        'A': MdDefinition('a', '/xy', title: 't'),
      });
    });
  });

  group('taken for the history', () {
    test('each settled block is taken once, in order; the rest is live', () {
      final stream = MarkdownStream('# Title\n\nFirst');
      expect(stream.takeSettled(), const [
        MdHeading(1, [MdText('Title')]),
      ]);
      expect(stream.live, const [
        MdParagraph([MdText('First')]),
      ]);
      expect(stream.takeSettled(), isEmpty);
      stream.add(' one.\n\n- item');
      final first = stream.blocks[1];
      final taken = stream.takeSettled();
      expect(taken, const [
        MdParagraph([MdText('First one.')]),
      ]);
      expect(identical(taken.single, first), isTrue);
      expect(stream.live, [stream.blocks.last]);
      expect(stream.blocks, hasLength(3));
    });

    test('taken in any pieces, the blocks are those of the document, '
        'their references resolved', () {
      // the definition before the references that use it
      const text = '[ref]: https://first.dev\n\n$document';
      final whole = MarkdownStream(text);
      final resolved = resolveReferences(whole.blocks, whole.definitions);
      final stream = MarkdownStream();
      final taken = <MdBlock>[];
      for (var k = 0; k < text.length; k++) {
        stream.add(text[k]);
        taken.addAll(stream.takeSettled());
        expect(taken.length + stream.live.length, stream.blocks.length);
        expect(stream.live, stream.blocks.sublist(taken.length));
      }
      stream.close();
      taken.addAll(stream.takeSettled());
      expect(stream.live, isEmpty);
      expect(taken, resolved);
    });

    test('a reference taken is a link where its definition settled before, '
        'its text where none has', () {
      final stream = MarkdownStream('[a]: /x\n\nSee [a] and [b].\n\n');
      expect(stream.takeSettled(), const [
        MdParagraph([
          MdText('See '),
          MdLink('/x', [MdText('a')]),
          MdText(' and [b].'),
        ]),
      ]);
      stream.add('[b]: /y\n\nend\n');
      expect(stream.definitions['B'], const MdDefinition('b', '/y'));
      expect(stream.takeSettled(), isEmpty);
    });

    test('a definition not settled is not used: it may still change', () {
      final stream = MarkdownStream('[a]\n\n[a]: /x');
      expect(stream.definitions['A'], const MdDefinition('a', '/x'));
      expect(stream.takeSettled(), const [
        MdParagraph([MdText('[a]')]),
      ]);
      stream.add('y\n');
      expect(stream.definitions['A'], const MdDefinition('a', '/xy'));
    });

    test('a definition settled by the same piece is used', () {
      final stream = MarkdownStream('[a]\n\n[a]: /x\n\nnext');
      expect(stream.takeSettled(), const [
        MdParagraph([
          MdLink('/x', [MdText('a')]),
        ]),
      ]);
    });
  });

  group('closed', () {
    test('every block settles, and the definitions of the last', () {
      final stream = MarkdownStream('text\n\n- one\n- two')..close();
      expect(stream.settled, 2);
      expect(stream.blocks, parseMarkdown('text\n\n- one\n- two'));
      expect(stream.takeSettled(), stream.blocks);
      final definitions = MarkdownStream('[a]\n\n[a]: /x')..close();
      expect(definitions.takeSettled(), const [
        MdParagraph([
          MdLink('/x', [MdText('a')]),
        ]),
      ]);
      expect(definitions.live, isEmpty);
    });

    test('the last line, ended by a carriage return or not at all, is '
        'complete', () {
      final stream = MarkdownStream('Title\r')..close();
      expect(stream.blocks, parseMarkdown('Title'));
      expect(stream.settled, 1);
    });

    test('adding text is an error', () {
      final stream = MarkdownStream('text')..close();
      expect(() => stream.add('more'), throwsStateError);
      expect(stream.close, returnsNormally);
    });
  });

  group('open blocks keep the parts that did not change', () {
    test('the finished items of a growing list', () {
      final stream = MarkdownStream('- one\n- two\n- thr');
      final list = stream.blocks.single as MdList;
      stream.add('ee\n- four');
      final grown = stream.blocks.single as MdList;
      expect(grown.items, hasLength(4));
      expect(identical(grown.items[0], list.items[0]), isTrue);
      expect(identical(grown.items[1], list.items[1]), isTrue);
      expect(identical(grown.items[2], list.items[2]), isFalse);
    });

    test('the items of a list that turns loose', () {
      final stream = MarkdownStream('- one\n- two\n');
      final list = stream.blocks.single as MdList;
      stream.add('\n- three');
      final loose = stream.blocks.single as MdList;
      expect(loose.tight, isFalse);
      expect(identical(loose.items[0], list.items[0]), isTrue);
      expect(identical(loose.items[1], list.items[1]), isTrue);
    });

    test('the blocks of a growing quote', () {
      final stream = MarkdownStream('> # Quote\n> \n> text');
      final quote = stream.blocks.single as MdBlockQuote;
      stream.add(' goes on');
      final grown = stream.blocks.single as MdBlockQuote;
      expect(identical(grown.children[0], quote.children[0]), isTrue);
      expect(identical(grown.children[1], quote.children[1]), isFalse);
    });

    test('a block more text left as it was', () {
      final stream = MarkdownStream('Hello');
      final paragraph = stream.blocks.single;
      stream.add(' ');
      expect(identical(stream.blocks.single, paragraph), isTrue);
      stream.add('there');
      expect(identical(stream.blocks.single, paragraph), isFalse);
    });
  });

  group('line endings', () {
    test('a carriage return and line feed split between pieces end one '
        'line', () {
      final stream = MarkdownStream('a\r')..add('\nb');
      expect(stream.blocks, parseMarkdown('a\nb'));
    });

    test('a carriage return alone ends a line', () {
      expect(parseMarkdown('# a\rb'), parseMarkdown('# a\nb'));
      expect(MarkdownStream('# a\r').blocks, parseMarkdown('# a'));
    });

    test('a NUL is U+FFFD', () {
      expect(parseMarkdown('a\u0000b'), [
        const MdParagraph([MdText('a�b')]),
      ]);
    });
  });

  group('what a piece costs', () {
    test('a table streamed a character at a time is at each one what its '
        'text so far parses to', () {
      const text =
          '| a | b |\n|---|:-:|\n| *1* | 2 |\n| 3 | `4` |\n\n'
          '> | q |\n> |---|\n> | r |\n';
      final stream = MarkdownStream();
      for (var k = 0; k < text.length; k++) {
        stream.add(text[k]);
        expect(
          stream.blocks,
          parseMarkdown(text.substring(0, k + 1)),
          reason: jsonEncode(text.substring(0, k + 1)),
        );
      }
    });

    test('pieces added between two reads are parsed once', () {
      final words = [for (var k = 0; k < 4000; k++) 'word$k '];
      final stream = MarkdownStream();
      final before = parsedUnits;
      words.forEach(stream.add);
      final paragraph = stream.blocks.single as MdParagraph;
      final text = (paragraph.children.single as MdText).text;
      expect(text, words.join().trimRight());
      expect(parsedUnits - before, text.length);
    });

    test('an open paragraph read after every piece parses about what each '
        'piece adds, emphasis and all', () {
      final stream = MarkdownStream();
      final before = parsedUnits;
      final text = StringBuffer();
      for (var k = 0; k < 2000; k++) {
        final piece = k % 7 == 3 ? '*em* [a](b) `c` ' : 'word ';
        text.write(piece);
        stream
          ..add(piece)
          ..blocks;
      }
      final parsed = parsedUnits - before;
      printOnFailure('$parsed code units parsed for ${text.length}');
      // the piece since the last cut is parsed again at each read
      expect(parsed, lessThan(text.length * 3));
      expect(stream.blocks, parseMarkdown('$text'));
    });

    for (final (name, unit) in [
      ('runs that can neither open nor close', 'a foo_bar 2 * 3 snake_case '),
      ('no spaces', '日本語のテキストです。'),
    ]) {
      test('an open paragraph of $name read after every piece parses about '
          'what each piece adds', () {
        final stream = MarkdownStream();
        final before = parsedUnits;
        final text = StringBuffer();
        while (text.length < 8000) {
          text.write(unit);
          stream
            ..add(unit)
            ..blocks;
        }
        final parsed = parsedUnits - before;
        printOnFailure('$parsed code units parsed for ${text.length}');
        expect(parsed, lessThan(text.length * 3));
        expect(stream.blocks, parseMarkdown('$text'));
      });
    }

    test('a table read after every piece parses each row about once', () {
      final rows = [for (var k = 0; k < 400; k++) '| cell $k | *b$k* |\n'];
      final text = '| a | b |\n|---|---|\n${rows.join()}';
      final stream = MarkdownStream();
      final before = parsedUnits;
      for (var at = 0; at < text.length; at += 5) {
        stream
          ..add(text.substring(at, (at + 5).clamp(0, text.length)))
          ..blocks;
      }
      final parsed = parsedUnits - before;
      printOnFailure('$parsed code units parsed for ${text.length}');
      // the row not ended yet is parsed again at each read, a piece of 5
      // code units at a time: some 4 times for a row of 20
      expect(parsed, lessThan(text.length * 3));
      expect((stream.blocks.single as MdTable).rows, hasLength(400));
    });
  });
}
