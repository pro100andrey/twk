// renderMarkdown: a document as lines of styled spans, which looks as the
// MarkdownView of it does, drawn by the app itself.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show graphemeBoundaries;
import 'package:twk_rich/twk_rich.dart';
import 'package:twk_test/twk_test.dart';

const heading = Color.rgb(1, 0, 0);
const code = Color.rgb(0, 1, 0);
const link = Color.rgb(0, 2, 0);
const codeBlock = Color.rgb(0, 0, 1);
const quote = Color.rgb(0, 0, 2);
const quoteBar = Color.rgb(0, 0, 3);
const marker = Color.rgb(0, 0, 4);
const rule = Color.rgb(0, 0, 5);
const tableHeader = Color.rgb(0, 0, 6);
const tableBorder = Color.rgb(0, 0, 7);

// the code blocks' syntax is that of the theme the views are shown in
final theme = MarkdownTheme(
  heading1: const Style(fg: heading, attrs: Attr.bold),
  heading2: const Style(fg: heading),
  heading3: const Style(fg: heading),
  heading4: const Style(fg: heading),
  heading5: const Style(fg: heading),
  heading6: const Style(fg: heading),
  emphasis: const Style(attrs: Attr.italic),
  strong: const Style(attrs: Attr.bold),
  strikethrough: const Style(attrs: Attr.strike),
  code: const Style(fg: code),
  link: const Style(fg: link, attrs: Attr.underline),
  image: const Style(fg: link),
  codeBlock: const Style(bg: codeBlock),
  quote: const Style(fg: quote),
  quoteBar: const Style(fg: quoteBar),
  marker: const Style(fg: marker),
  rule: const Style(fg: rule),
  tableHeader: const Style(fg: tableHeader, attrs: Attr.bold),
  tableBorder: const Style(fg: tableBorder),
  syntax: SyntaxTheme.from(ThemeData.dark),
);

/// The text of each line.
List<String> texts(String markdown, int width) => [
  for (final line in renderMarkdown(markdown, width, theme))
    line.map((span) => span.text).join(),
];

/// The width of [line] in columns.
int columns(List<Span> line) =>
    line.fold<int>(0, (w, span) => w + stringWidth(span.text));

const document = '''
# A *title* of the document

Some **strong** and ~~struck~~ text with `code`, a [link](https://x.dev) and
a long-winded hyphenated word, enough to wrap at a few widths.

> quoted *text* that wraps as well
>
> - and a list in it

1. first item of a list
   that goes on
2. second
   - nested one
   - nested two

- [x] done
- [ ] not yet

- loose

- items

---

```dart
var a = 1;
	tabbed and a rather long line of code
```

日本語のテキストです、これは長い。English after it.
''';

String text(List<Span> line) => line.map((span) => span.text).join();

void main() {
  group('inlines and wrapping', () {
    test('a paragraph wraps by words, each inline in its style', () {
      final lines = renderMarkdown(
        'Some **strong** and `code`, a [link](https://x.dev).',
        20,
        theme,
      );
      expect(lines.map(text), ['Some strong and', 'code, a link.']);
      expect(lines[0].map((span) => span.text), ['Some ', 'strong', ' and']);
      expect(lines[0][1].style, const Style(attrs: Attr.bold));
      expect(lines[1][0].style, const Style(fg: code));
      final link = lines[1][lines[1].length - 2];
      expect(link.text, 'link');
      expect(link.style.fg, isNotNull);
      expect(link.style.link, 'https://x.dev');
      expect(lines[1][1].text, ', a ');
    });

    test('a destination off the web is a link in style, not a hyperlink', () {
      final lines = renderMarkdown('[a](notes.md)', 20, theme);
      expect(lines.single.single.style.link, isNull);
      expect(lines.single.single.style.attrs, Attr.underline);
    });

    test('a hard break ends a line, a soft one is a space', () {
      expect(texts('one\ntwo\\\nthree', 20), ['one two', 'three']);
    });

    test('a word longer than the line breaks between graphemes, spaces '
        'at the break hang', () {
      expect(texts('abcdefghij kl', 4), ['abcd', 'efgh', 'ij', 'kl']);
      expect(texts('ab  cd', 3), ['ab', 'cd']);
    });

    test('a line breaks after a hyphen inside a word, not after a dash', () {
      expect(texts('well-known fact', 6), ['well-', 'known', 'fact']);
      expect(texts('a - b - c', 3), ['a -', 'b -', 'c']);
    });

    test('CJK text breaks between characters, not before closing '
        'punctuation; a wide character takes two columns', () {
      expect(texts('日本語のテキスト、です', 8), [
        '日本語の',
        'テキス',
        'ト、です',
      ]);
      expect(texts('日本語', 5), ['日本', '語']);
    });
  });

  group('blocks', () {
    test('headings in their style, a blank line between blocks', () {
      final lines = renderMarkdown('# One *two*\n\ntext\n', 20, theme);
      expect(lines.map(text), ['One two', '', 'text']);
      expect(lines[0][0].style, const Style(fg: heading, attrs: Attr.bold));
      expect(
        lines[0][1].style,
        const Style(fg: heading, attrs: Attr.bold | Attr.italic),
      );
      expect(lines[1], isEmpty);
    });

    test('a block quote has a bar down its side, its blocks in the quote '
        'style, a nested one a bar more', () {
      final lines = renderMarkdown(
        '> quoted *text* that wraps\n>\n> > deep\n',
        14,
        theme,
      );
      expect(lines.map(text), [
        '│ quoted text',
        '│ that wraps',
        '│',
        '│ │ deep',
      ]);
      expect(lines[0][0], const Span('│', Style(fg: quoteBar)));
      expect(lines[0][1], const Span(' '));
      expect(lines[0][2].style, const Style(fg: quote));
      expect(lines[0][3].style, const Style(fg: quote, attrs: Attr.italic));
      expect(lines[3].last.style, const Style(fg: quote));
    });

    test('lists: bullets by depth, numbers aligned at their right, boxes, '
        'blocks wrapped under their own column', () {
      expect(
        texts(
          '- a\n  - b\n    - c\n      - d\n\n'
          '9. nine\n10. ten that is long\n\n'
          '- [x] done\n- [ ] todo\n',
          14,
        ),
        [
          '• a',
          '  ◦ b',
          '    • c',
          '      • d',
          '',
          ' 9. nine',
          '10. ten that',
          '    is long',
          '',
          '[x] done',
          '[ ] todo',
        ],
      );
    });

    test('a loose list has a blank line between its items and their blocks, '
        'a tight one none', () {
      expect(texts('- a\n\n  b\n\n- c\n', 10), ['• a', '', '  b', '', '• c']);
      expect(texts('- a\n- b\n', 10), ['• a', '• b']);
    });

    test('a marker is in the marker style', () {
      final lines = renderMarkdown('- a\n', 10, theme);
      expect(lines.single[0], const Span('•', Style(fg: marker)));
    });

    test('no cell is beyond the width, however narrow: a table of more '
        'columns than fit, quotes, lists and code', () {
      final cols = List.generate(10, (j) => 'c$j');
      final table =
          '| ${cols.join(' | ')} |\n|${'---|' * 10}\n'
          '| ${cols.join(' | ')} |\n';
      final docs = [
        table,
        '> q\n',
        '> > q\n',
        '- a\n- b\n',
        '1. a\n   - b\n',
        '```\nab\n```\n',
        '# head words\n',
      ];
      for (final doc in docs) {
        for (var width = 1; width <= 14; width++) {
          for (final line in renderMarkdown(doc, width, theme)) {
            expect(
              columns(line),
              lessThanOrEqualTo(width),
              reason: '$doc at $width: ${line.map((s) => s.text).join()}',
            );
          }
        }
      }
      expect(texts(table, 12).first, hasLength(lessThanOrEqualTo(12)));
      expect(texts('> q\n', 2), ['│q']);
      expect(texts('> q\n', 1), ['q']);
    });

    test('a thematic break is a line across', () {
      final lines = renderMarkdown('---\n', 7, theme);
      expect(lines.single, [const Span('───────', Style(fg: rule))]);
    });

    test('code: a cell in from either side on the fill of its style, tabs '
        'to 4 columns, long lines broken between graphemes', () {
      final lines = renderMarkdown('```\nab\n\tcd efgh\n```\n', 8, theme);
      expect(lines.map(text), [' ab     ', '     cd ', '  efgh  ']);
      expect(lines.map(columns), [8, 8, 8]);
      expect(lines.first.single.style, const Style(bg: codeBlock));
    });

    test('code is highlighted in the language of its fence, over the fill', () {
      final lines = renderMarkdown('```dart\nvar a = 1;\n```\n', 12, theme);
      expect(lines.map(text), [' var a = 1; ']);
      final syntax = theme.syntax;
      const fill = Style(bg: codeBlock);
      expect(lines.single, [
        const Span(' ', fill),
        Span('var', fill.merge(syntax.keyword)),
        const Span(' a ', fill),
        Span('=', fill.merge(syntax.operator)),
        const Span(' ', fill),
        Span('1', fill.merge(syntax.number)),
        // punctuation has no style of its own: it is the fill's
        const Span('; ', fill),
      ]);
    });

    test('a table: columns as wide as their text, aligned, lines between '
        'them and under the header', () {
      final lines = renderMarkdown(
        '| a | bb |\n|:-:|--:|\n| 1 | 2222 |\n| long | x |\n',
        30,
        theme,
      );
      expect(lines.map(text), [
        ' a   │   bb',
        '─────┼─────',
        ' 1   │ 2222',
        'long │    x',
      ]);
      expect(lines[0][1].style, const Style(fg: tableHeader, attrs: Attr.bold));
      expect(
        lines[0].firstWhere((span) => span.text == '│').style,
        const Style(fg: tableBorder),
      );
      expect(lines[1].single.style, const Style(fg: tableBorder));
    });

    test('a table wider than the width shrinks its widest column and '
        'wraps its cells', () {
      final lines = renderMarkdown(
        '| a | b |\n|---|---|\n| one two | x |\n',
        7,
        theme,
      );
      expect(lines.map(text), [
        'a   │ b',
        '────┼──',
        'one │ x',
        'two │',
      ]);
    });
  });

  group('as a MarkdownView', () {
    for (final width in [8, 13, 24, 40, 80]) {
      testTwk('at $width columns the lines are the rows of the view', (
        t,
      ) async {
        await t.pumpWidget(
          Theme(
            data: ThemeData.dark,
            child: MarkdownView(document, theme: theme),
          ),
          size: (width, 120),
        );
        final lines = texts(document, width);
        final shown = [
          for (final line in lines) line.replaceAll(RegExp(r' +$'), ''),
        ];
        expect(t.lines.take(lines.length).toList(), shown);
        expect(t.lines.skip(lines.length).every((row) => row.isEmpty), isTrue);
      });

      testTwk('at $width columns the cells have the styles of the view', (
        t,
      ) async {
        await t.pumpWidget(
          Theme(
            data: ThemeData.dark,
            child: MarkdownView(document, theme: theme),
          ),
          size: (width, 120),
        );
        final lines = renderMarkdown(document, width, theme);
        for (var y = 0; y < lines.length; y++) {
          var x = 0;
          for (final span in lines[y]) {
            for (final (from, to) in graphemeBoundaries(span.text)) {
              final cluster = span.text.substring(from, to);
              final cell = t.cell(x, y);
              final style = span.style;
              final at = '"$cluster" at $x,$y';
              expect(cell.link, style.link, reason: 'link of $at');
              expect(cell.bg, style.bg?.value ?? 0, reason: 'bg of $at');
              if (cluster != ' ') {
                expect(cell.fg, style.fg?.value ?? 0, reason: 'fg of $at');
                expect(cell.attrs, style.attrs, reason: 'attrs of $at');
              }
              x += stringWidth(cluster);
            }
          }
        }
      });
    }

    test('no line is wider than the width', () {
      for (final width in [8, 9, 20]) {
        for (final line in renderMarkdown(document, width, theme)) {
          expect(columns(line), lessThanOrEqualTo(width), reason: text(line));
        }
      }
    });
  });
}
