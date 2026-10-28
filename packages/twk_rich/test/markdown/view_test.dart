// The Markdown view: each kind of block and inline in the styles of its
// theme, links as hyperlinks, code highlighted, tables the wheel goes
// through, text selected without the bullets and bars, wide and CJK text
// wrapped, and a document streamed in rebuilding only the blocks not
// settled.
import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show PaintContext, PipelineOwner, Screen, kCont;
import 'package:twk_rich/twk_rich.dart';
import 'package:twk_test/twk_test.dart';

const heading1 = Color.rgb(1, 0, 0);
const heading2 = Color.rgb(2, 0, 0);
const heading3 = Color.rgb(3, 0, 0);
const heading4 = Color.rgb(4, 0, 0);
const heading5 = Color.rgb(5, 0, 0);
const heading6 = Color.rgb(6, 0, 0);
const code = Color.rgb(0, 1, 0);
const link = Color.rgb(0, 2, 0);
const image = Color.rgb(0, 3, 0);
const codeBlock = Color.rgb(0, 0, 1);
const quote = Color.rgb(0, 0, 2);
const quoteBar = Color.rgb(0, 0, 3);
const marker = Color.rgb(0, 0, 4);
const rule = Color.rgb(0, 0, 5);
const tableHeader = Color.rgb(0, 0, 6);
const tableBorder = Color.rgb(0, 0, 7);
const keyword = Color.rgb(9, 9, 9);

const theme = MarkdownTheme(
  heading1: Style(fg: heading1, attrs: Attr.bold),
  heading2: Style(fg: heading2),
  heading3: Style(fg: heading3),
  heading4: Style(fg: heading4),
  heading5: Style(fg: heading5),
  heading6: Style(fg: heading6),
  emphasis: Style(attrs: Attr.italic),
  strong: Style(attrs: Attr.bold),
  strikethrough: Style(attrs: Attr.strike),
  code: Style(fg: code),
  link: Style(fg: link, attrs: Attr.underline),
  image: Style(fg: image),
  codeBlock: Style(bg: codeBlock),
  quote: Style(fg: quote),
  quoteBar: Style(fg: quoteBar),
  marker: Style(fg: marker),
  rule: Style(fg: rule),
  tableHeader: Style(fg: tableHeader, attrs: Attr.bold),
  tableBorder: Style(fg: tableBorder),
);

/// [markdown] in [theme], code in a syntax theme of one keyword color.
Widget view(
  String markdown, {
  TextWrap codeWrap = TextWrap.grapheme,
  MarkdownTheme? withTheme = theme,
}) => SyntaxThemeScope(
  theme: const SyntaxTheme(keyword: Style(fg: keyword)),
  child: MarkdownView(markdown, theme: withTheme, codeWrap: codeWrap),
);

/// The first [count] rows of the screen.
List<String> rows(TwkTester t, int count) => t.lines.take(count).toList();

void main() {
  group('inlines', () {
    testTwk('emphasis, strong, struck text and code in their styles', (
      t,
    ) async {
      await t.pumpWidget(
        view('Some *em*, **strong**, ~~gone~~ and `code`.'),
        size: (40, 3),
      );
      expect(rows(t, 1), ['Some em, strong, gone and code.']);
      expect(t, styleAt(0, 0, isNot(hasAttr(Attr.italic))));
      expect(t, styleAt(5, 0, hasAttr(Attr.italic)));
      expect(t, styleAt(9, 0, hasAttr(Attr.bold)));
      expect(t, styleAt(17, 0, hasAttr(Attr.strike)));
      expect(t, styleAt(26, 0, hasFg(code)));
    });

    testTwk('styles nest: strong text in emphasis is both', (t) async {
      await t.pumpWidget(view('*a **b** c*'), size: (20, 2));
      expect(rows(t, 1), ['a b c']);
      expect(t, styleAt(2, 0, hasAttr(Attr.italic | Attr.bold)));
      expect(t, styleAt(4, 0, isNot(hasAttr(Attr.bold))));
    });

    testTwk('a line ending is a space, a hard break ends the line', (
      t,
    ) async {
      await t.pumpWidget(view('one\ntwo\\\nthree'), size: (20, 3));
      expect(rows(t, 2), ['one two', 'three']);
    });

    testTwk('links are hyperlinks (OSC 8) in the link style: inline, '
        'autolinks and URLs and addresses in the text', (t) async {
      await t.pumpWidget(
        view('A [link](https://x.dev) and www.y.dev and <me@z.dev>.'),
        size: (40, 2),
      );
      expect(rows(t, 1), ['A link and www.y.dev and me@z.dev.']);
      expect(t.cell(0, 0).link, isNull);
      expect(t.cell(2, 0).link, 'https://x.dev');
      expect(t.cell(5, 0).link, 'https://x.dev');
      expect(t.cell(6, 0).link, isNull);
      expect(t, styleAt(2, 0, allOf(hasFg(link), hasAttr(Attr.underline))));
      expect(t.cell(11, 0).link, 'http://www.y.dev');
      expect(t.cell(25, 0).link, 'mailto:me@z.dev');
    });

    testTwk('a reference is a link where a definition, before it or after, '
        'names its label, and its text where none does', (t) async {
      await t.pumpWidget(
        view('See [docs] and [nope].\n\n[docs]: https://d.dev\n'),
        size: (30, 3),
      );
      expect(rows(t, 2), ['See docs and [nope].', '']);
      expect(t.cell(4, 0).link, 'https://d.dev');
      expect(t.cell(13, 0).link, isNull);
    });

    testTwk('an image shows its description, linked to its source', (
      t,
    ) async {
      await t.pumpWidget(
        view('![a cat](cat.png) and ![](dog.png)'),
        size: (30, 2),
      );
      expect(rows(t, 1), ['a cat and dog.png']);
      expect(t, styleAt(0, 0, hasFg(image)));
      expect(t.cell(0, 0).link, 'cat.png');
      expect(t.cell(10, 0).link, 'dog.png');
    });
  });

  group('blocks', () {
    testTwk('headings of each level in their styles, a blank row between '
        'blocks', (t) async {
      await t.pumpWidget(
        view(
          '# One\n## Two\n### Three\n#### Four\n##### Five\n###### Six\n\n'
          'Setext\n------\n',
        ),
        size: (20, 14),
      );
      expect(rows(t, 13), [
        'One',
        '',
        'Two',
        '',
        'Three',
        '',
        'Four',
        '',
        'Five',
        '',
        'Six',
        '',
        'Setext',
      ]);
      expect(t, styleAt(0, 0, allOf(hasFg(heading1), hasAttr(Attr.bold))));
      expect(t, styleAt(0, 2, hasFg(heading2)));
      expect(t, styleAt(0, 4, hasFg(heading3)));
      expect(t, styleAt(0, 6, hasFg(heading4)));
      expect(t, styleAt(0, 8, hasFg(heading5)));
      expect(t, styleAt(0, 10, hasFg(heading6)));
      expect(t, styleAt(0, 12, hasFg(heading2)));
    });

    testTwk('a paragraph wraps by words', (t) async {
      await t.pumpWidget(view('one two three four five'), size: (10, 4));
      expect(rows(t, 3), ['one two', 'three four', 'five']);
    });

    testTwk('a thematic break is a line across', (t) async {
      await t.pumpWidget(view('a\n\n---\n\nb'), size: (12, 6));
      expect(rows(t, 5), ['a', '', '─' * 12, '', 'b']);
      expect(t, styleAt(5, 2, hasFg(rule)));
    });

    testTwk('a block quote has a bar down every row of it, its blocks in '
        'the quote style', (t) async {
      await t.pumpWidget(
        view('> quoted *text*\n> more\n>\n> - item\n\nafter'),
        size: (20, 6),
      );
      expect(rows(t, 5), [
        '│ quoted text more',
        '│',
        '│ • item',
        '',
        'after',
      ]);
      expect(t, styleAt(0, 0, hasFg(quoteBar)));
      expect(t, styleAt(0, 1, hasFg(quoteBar)));
      expect(t, styleAt(2, 0, hasFg(quote)));
      expect(t, styleAt(0, 4, isNot(hasFg(quote))));
    });

    testTwk('a quote within a quote, wrapped', (t) async {
      await t.pumpWidget(view('> a\n>\n> > bbb ccc ddd'), size: (11, 5));
      expect(rows(t, 4), ['│ a', '│', '│ │ bbb ccc', '│ │ ddd']);
    });
  });

  group('lists', () {
    testTwk('bullets by depth, the items of a list under one another', (
      t,
    ) async {
      await t.pumpWidget(
        view('- one\n- two\n  - nested\n    - deeper\n      - again\n- three'),
        size: (20, 7),
      );
      expect(rows(t, 6), [
        '• one',
        '• two',
        '  ◦ nested',
        '    ▪ deeper',
        '      • again',
        '• three',
      ]);
      expect(t, styleAt(0, 0, hasFg(marker)));
    });

    testTwk('ordered from its start, numbers aligned at their right', (
      t,
    ) async {
      await t.pumpWidget(view('9. nine\n10. ten\n\n3) three'), size: (20, 5));
      expect(rows(t, 4), [' 9. nine', '10. ten', '', '3) three']);
      expect(t, styleAt(1, 0, hasFg(marker)));
    });

    testTwk('task items have a box, checked or not', (t) async {
      await t.pumpWidget(
        view('- [ ] todo\n- [x] done\n\n1. [x] first'),
        size: (20, 5),
      );
      expect(rows(t, 4), ['☐ todo', '☑ done', '', '1. ☑ first']);
    });

    testTwk('a loose list has a blank row between its items and blocks', (
      t,
    ) async {
      await t.pumpWidget(view('- a\n\n  more\n- b'), size: (20, 6));
      expect(rows(t, 5), ['• a', '', '  more', '', '• b']);
    });

    testTwk('an item wraps under its own text, not its marker', (t) async {
      await t.pumpWidget(view('- one two three four'), size: (12, 3));
      expect(rows(t, 2), ['• one two', '  three four']);
    });

    testTwk('an item that starts with code or is empty', (t) async {
      await t.pumpWidget(
        view('- ```\n  x\n  ```\n-\n- c'),
        size: (20, 4),
      );
      expect(rows(t, 3), ['•  x', '•', '• c']);
    });
  });

  group('code', () {
    testTwk('a fenced block in the language of its info string, on the '
        'code block fill across', (t) async {
      await t.pumpWidget(
        view('```dart\nfinal x = 1;\n```\n\n    plain\n\n```nope\nfinal\n```'),
        size: (20, 6),
      );
      expect(rows(t, 5), [' final x = 1;', '', ' plain', '', ' final']);
      expect(t, styleAt(1, 0, hasFg(keyword)));
      expect(t, styleAt(0, 0, hasBg(codeBlock)));
      expect(t, styleAt(19, 0, hasBg(codeBlock)));
      expect(t, styleAt(1, 2, isNot(hasFg(keyword))));
      expect(t, styleAt(1, 4, isNot(hasFg(keyword))));
    });

    testTwk('long lines wrap, or are cut off with TextWrap.none', (t) async {
      const markdown = '```\nabcdefghijklmnop\n```\n\nafter';
      await t.pumpWidget(view(markdown), size: (12, 5));
      expect(rows(t, 4), [' abcdefghij', ' klmnop', '', 'after']);
      await t.pumpWidget(view(markdown, codeWrap: TextWrap.none));
      expect(rows(t, 3), [' abcdefghij', '', 'after']);
    });
  });

  group('tables', () {
    testTwk('a table: the header, the rows in their alignment, lines '
        'between the columns', (t) async {
      await t.pumpWidget(
        view(
          '| Name | Qty |\n|:-----|----:|\n| *ab* | 1 |\n| c | 100 |\n\n'
          'after',
        ),
        size: (20, 7),
      );
      final lines = rows(t, 6);
      expect(lines[0], 'Name │ Qty');
      expect(lines[1], startsWith('─────┼────'));
      expect(lines.sublist(2), ['ab   │   1', 'c    │ 100', '', 'after']);
      expect(t, styleAt(0, 0, allOf(hasFg(tableHeader), hasAttr(Attr.bold))));
      expect(t, styleAt(5, 0, hasFg(tableBorder)));
      expect(t, styleAt(0, 2, hasAttr(Attr.italic)));
    });

    testTwk('the wheel over a table scrolls the document around it', (
      t,
    ) async {
      final markdown = [
        '| a | b |\n|---|---|\n| 1 | 2 |\n',
        for (var i = 0; i < 20; i++) 'paragraph $i\n',
      ].join('\n');
      await t.pumpWidget(
        SingleChildScrollView(child: view(markdown)),
        size: (20, 6),
      );
      expect(rows(t, 1), ['a │ b']);
      await t.mouse(MouseKind.wheelDown, 0, 2);
      await t.pump();
      expect(rows(t, 2), ['', 'paragraph 0']);
    });

    testTwk('the text of the cells is selected and copied', (t) async {
      final copies = <String>[];
      await t.pumpWidget(
        SelectionArea(
          onCopy: copies.add,
          child: view('| a | b |\n|---|---|\n| one | two |'),
        ),
        size: (20, 4),
      );
      expect(rows(t, 3), ['a   │ b', startsWith('────┼'), 'one │ two']);
      await t.mouse(MouseKind.down, 1, 2);
      await t.mouse(MouseKind.drag, 7, 2);
      await t.mouse(MouseKind.up, 7, 2);
      expect(copies, ['ne\ntw']);
    });

    testTwk('links and code in cells', (t) async {
      await t.pumpWidget(
        view('| a |\n|---|\n| [x](https://x.dev) `y` |'),
        size: (20, 3),
      );
      expect(rows(t, 3), ['a', startsWith('─'), 'x y']);
      expect(t.cell(0, 2).link, 'https://x.dev');
      expect(t, styleAt(2, 2, hasFg(code)));
    });
  });

  group('theme', () {
    testTwk('without a theme, the styles of the Theme above', (t) async {
      await t.pumpWidget(
        Theme(
          data: ThemeData.light,
          child: view('# Title\n\n[x](https://x.dev)', withTheme: null),
        ),
        size: (20, 4),
      );
      expect(t, styleAt(0, 0, hasFg(ThemeData.light.primary.fg!)));
      expect(t, styleAt(0, 0, hasAttr(Attr.bold | Attr.underline)));
      expect(t, styleAt(0, 2, hasFg(ThemeData.light.primary.fg!)));
    });

    testTwk('without a theme, another Theme above restyles it', (t) async {
      Widget under(ThemeData data) => Theme(
        data: data,
        child: view('# Title', withTheme: null),
      );
      await t.pumpWidget(under(ThemeData.light), size: (20, 2));
      expect(t, styleAt(0, 0, hasFg(ThemeData.light.primary.fg!)));
      await t.pumpWidget(under(ThemeData.dark));
      expect(t, styleAt(0, 0, hasFg(ThemeData.dark.primary.fg!)));
      await t.pumpWidget(under(ThemeData.light));
      expect(t, styleAt(0, 0, hasFg(ThemeData.light.primary.fg!)));
    });

    testTwk('a new theme shows every block in it', (t) async {
      await t.pumpWidget(view('# Title\n\n- item'), size: (20, 4));
      expect(t, styleAt(0, 0, hasFg(heading1)));
      const other = Color.rgb(7, 7, 7);
      await t.pumpWidget(
        view(
          '# Title\n\n- item',
          withTheme: theme.copyWith(
            heading1: const Style(fg: other),
            marker: const Style(fg: other),
          ),
        ),
      );
      expect(t, styleAt(0, 0, hasFg(other)));
      expect(t, styleAt(0, 2, hasFg(other)));
    });

    test('MarkdownTheme.from takes the colors of a ThemeData', () {
      const data = ThemeData.dark;
      final from = MarkdownTheme.from(data);
      expect(from.heading1.fg, data.primary.fg);
      expect(from.heading(3).fg, data.accent.fg);
      expect(from.link, data.primary.merge(const Style(attrs: Attr.underline)));
      expect(from.codeBlock, data.surface);
      expect(from.quoteBar, data.border);
      expect(from, MarkdownTheme.from(data));
      expect(from, isNot(MarkdownTheme.from(ThemeData.light)));
    });
  });

  testTwk('the text of the blocks is selected and copied without bullets, '
      'numbers or bars', (t) async {
    final copies = <String>[];
    await t.pumpWidget(
      SelectionArea(
        onCopy: copies.add,
        child: view('# Title\n\n- one\n- two\n\n> quote\n\n1. first'),
      ),
      size: (20, 9),
    );
    expect(rows(t, 8), [
      'Title',
      '',
      '• one',
      '• two',
      '',
      '│ quote',
      '',
      '1. first',
    ]);
    await t.mouse(MouseKind.down, 0, 0);
    await t.mouse(MouseKind.drag, 7, 7);
    await t.mouse(MouseKind.up, 7, 7);
    expect(copies, ['Title\none\ntwo\nquote\nfirst']);
  });

  group('wide and CJK text', () {
    testTwk('a paragraph of CJK breaks between characters, none cut in two', (
      t,
    ) async {
      await t.pumpWidget(view('日本語のテキストを折り返す'), size: (11, 4));
      expect(rows(t, 3), ['日本語のテ', 'キストを折', 'り返す']);
    });

    testTwk('CJK and Latin words wrap together', (t) async {
      await t.pumpWidget(view('abc 漢字かな交じり def'), size: (8, 4));
      expect(rows(t, 3), ['abc 漢字', 'かな交じ', 'り def']);
    });

    testTwk('a list item of CJK wraps under its text', (t) async {
      await t.pumpWidget(view('- 漢字漢字漢字漢字漢字'), size: (12, 3));
      expect(rows(t, 2), ['• 漢字漢字漢', '  字漢字漢字']);
    });

    testTwk('a quote of wide text keeps its bar on every row', (t) async {
      await t.pumpWidget(view('> 👍👍👍👍👍'), size: (8, 3));
      expect(rows(t, 2), ['│ 👍👍👍', '│ 👍👍']);
    });

    testTwk('a table measures its columns in columns of the screen', (
      t,
    ) async {
      await t.pumpWidget(
        view('| 名前 | x |\n|---|---|\n| 東京 | 1 |\n| a | 2 |'),
        size: (20, 4),
      );
      final lines = rows(t, 4);
      expect(lines[0], '名前 │ x');
      expect(lines.sublist(2), ['東京 │ 1', 'a    │ 2']);
    });

    test('a bullet the terminal draws two columns wide takes two', () {
      final shot = Shot(
        view('- one two three\n- b'),
        10,
        3,
        ambiguousWidth: 2,
      );
      expect(shot.at(0, 0), '•');
      expect(shot.at(3, 0), 'o');
      expect(shot.at(3, 1), 't');
      expect(shot.at(3, 2), 'b');
    });
  });

  group('streaming', () {
    testTwk('text added shows; text replaced shows anew', (t) async {
      await t.pumpWidget(view('# Tit'), size: (20, 4));
      expect(rows(t, 1), ['Tit']);
      await t.pumpWidget(view('# Title\n\nbody'));
      expect(rows(t, 3), ['Title', '', 'body']);
      await t.pumpWidget(view('other'));
      expect(rows(t, 3), ['other', '', '']);
    });

    testTwk('a definition that arrives later makes a reference shown '
        'before a link', (t) async {
      await t.pumpWidget(view('See [docs].\n\nmore\n\n'), size: (20, 4));
      expect(rows(t, 1), ['See [docs].']);
      await t.pumpWidget(
        view('See [docs].\n\nmore\n\n[docs]: https://d.dev\n'),
      );
      expect(rows(t, 3), ['See docs.', '', 'more']);
      expect(t.cell(4, 0).link, 'https://d.dev');
    });

    testTwk('a definition that arrives later reaches a reference in an item '
        'kept while its list grew', (t) async {
      await t.pumpWidget(view('- see [docs]\n'), size: (20, 6));
      await t.pumpWidget(view('- see [docs]\n- two\n'));
      await t.pumpWidget(view('- see [docs]\n- two\n\nmore\n\n'));
      expect(rows(t, 4), ['• see [docs]', '• two', '', 'more']);
      await t.pumpWidget(
        view('- see [docs]\n- two\n\nmore\n\n[docs]: https://d.dev\n'),
      );
      expect(rows(t, 1), ['• see docs']);
      expect(t.cell(6, 0).link, 'https://d.dev');
    });

    testTwk('a list that grows to wider numbers aligns them all again', (
      t,
    ) async {
      await t.pumpWidget(view('9. nine\n'), size: (20, 3));
      expect(rows(t, 1), ['9. nine']);
      await t.pumpWidget(view('9. nine\n10. ten\n'));
      expect(rows(t, 2), [' 9. nine', '10. ten']);
    });

    testTwk('a code block that grows is highlighted as it does', (t) async {
      await t.pumpWidget(view('```dart\nfin'), size: (20, 3));
      expect(rows(t, 1), [' fin']);
      expect(t, styleAt(1, 0, isNot(hasFg(keyword))));
      await t.pumpWidget(view('```dart\nfinal x'));
      expect(rows(t, 1), [' final x']);
      expect(t, styleAt(1, 0, hasFg(keyword)));
    });

    testTwk('a long document streamed in pieces rebuilds only the blocks '
        'not settled', (t) async {
      final document = [for (var i = 0; i < 12; i++) section(i)].join();
      final stream = MarkdownStream();
      final shown = StringBuffer();
      var before = <Map<Element, Widget>>[];
      var pieces = 0;
      var updatedMost = 0;
      var updatedAll = 0;
      var elementsAll = 0;
      for (var at = 0; at < document.length; at += 17) {
        final piece = document.substring(
          at,
          math.min(at + 17, document.length),
        );
        final settled = stream.settled;
        stream.add(piece);
        shown.write(piece);
        await t.pumpWidget(
          SingleChildScrollView(child: view('$shown')),
          size: (40, 10),
        );
        final after = blockElements();
        expect(after.length, stream.blocks.length);
        for (var k = 0; k < settled; k++) {
          expect(
            same(after[k], before[k]),
            isTrue,
            reason: 'block $k of ${after.length}, settled before piece $pieces',
          );
        }
        final was = {for (final block in before) ...block};
        var updated = 0;
        for (final block in after) {
          for (final MapEntry(key: element, value: widget) in block.entries) {
            if (!identical(was[element], widget)) {
              updated++;
            }
          }
        }
        updatedMost = math.max(updatedMost, updated);
        updatedAll += updated;
        elementsAll += after.fold(0, (n, block) => n + block.length);
        before = after;
        pieces++;
      }
      final elements = before.fold(0, (n, block) => n + block.length);
      printOnFailure(
        '$pieces pieces, ${before.length} blocks of $elements elements: '
        '$updatedAll elements updated, at most $updatedMost a piece, of '
        '$elementsAll a rebuild of every block would update',
      );
      // a piece updates the elements of a block or two at the end
      expect(updatedAll, lessThan(elementsAll ~/ 10));
    });

    testTwk('a list that grows keeps the elements of its items', (t) async {
      final items = [for (var i = 0; i < 30; i++) '- item $i\n'];
      await t.pumpWidget(
        SingleChildScrollView(child: view(items.join())),
        size: (20, 5),
      );
      final before = blockElements().single;
      await t.pumpWidget(
        SingleChildScrollView(child: view('${items.join()}- item 30\n')),
      );
      final after = blockElements().single;
      final updated = [
        for (final MapEntry(key: element, value: widget) in after.entries)
          if (!identical(before[element], widget)) widget.runtimeType,
      ];
      // the list, its column and the items 29 and 30 (the last but one
      // ends at the new one)
      expect(updated.length, lessThan(20));
    });
  });

  group('blocks given', () {
    testTwk('show as the view of their document shows them', (t) async {
      final document = section(1);
      await t.pumpWidget(view(document), size: (40, 30));
      final whole = t.lines;
      final styles = cells(t);
      final stream = MarkdownStream(document);
      await t.pumpWidget(
        blocksView(stream.blocks, definitions: stream.definitions),
      );
      expect(t.lines, whole);
      expect(whole.where((line) => line.isNotEmpty), hasLength(greaterThan(9)));
      expect(cells(t), styles);
    });

    testTwk('their references resolve by the definitions given; one given '
        'later makes a link of the block kept', (t) async {
      final blocks = parseMarkdown('See [docs].\n\nnext');
      await t.pumpWidget(blocksView(blocks), size: (20, 4));
      expect(rows(t, 3), ['See [docs].', '', 'next']);
      final next = blockElements()[1];
      await t.pumpWidget(
        blocksView(
          blocks,
          definitions: const {'DOCS': MdDefinition('docs', 'https://d.dev')},
        ),
      );
      expect(rows(t, 3), ['See docs.', '', 'next']);
      expect(t.cell(4, 0).link, 'https://d.dev');
      expect(same(blockElements()[1], next), isTrue);
    });

    testTwk('a block kept from the blocks given before keeps its widgets', (
      t,
    ) async {
      final stream = MarkdownStream('# Title\n\n- one\n- tw');
      await t.pumpWidget(blocksView(stream.blocks), size: (20, 5));
      final before = blockElements();
      stream.add('o\n- three');
      await t.pumpWidget(blocksView(stream.blocks));
      expect(rows(t, 5), ['Title', '', '• one', '• two', '• three']);
      final after = blockElements();
      expect(same(after[0], before[0]), isTrue);
      expect(same(after[1], before[1]), isFalse);
    });
  });
}

/// The text, colors, attributes and link of each cell of the screen.
List<Object> cells(TwkTester t) => [
  for (var y = 0; y < t.terminal.height; y++)
    for (var x = 0; x < t.terminal.width; x++) cellOf(t.cell(x, y)),
];

/// The text, colors, attributes and link of [cell].
Object cellOf(VtCell cell) =>
    (cell.text, cell.fg, cell.bg, cell.ul, cell.attrs, cell.link);

/// [blocks] in [theme], their references resolved by [definitions].
Widget blocksView(
  List<MdBlock> blocks, {
  Map<String, MdDefinition> definitions = const {},
}) => SyntaxThemeScope(
  theme: const SyntaxTheme(keyword: Style(fg: keyword)),
  child: MarkdownView.blocks(blocks, definitions: definitions, theme: theme),
);

/// Section [i] of a long document: a block of every kind.
String section(int i) =>
    '''
## Section $i

A paragraph with *emphasis* and a [link](https://x.dev/$i), long enough
to wrap at the width of the screen.

- item one
- item two
  - nested

```dart
final x = $i;
```

> a quote

| a | b |
|---|---|
| $i | ${i * 2} |

''';

/// The elements of each block the [MarkdownView] shows, the widget of each.
List<Map<Element, Widget>> blockElements() {
  final column = find
      .descendant(of: find.byType(MarkdownView), matching: find.byType(Column))
      .first
      .evaluate()
      .single;
  final blocks = <Map<Element, Widget>>[];
  column.visitChildren((child) {
    final elements = <Element, Widget>{};
    void visit(Element element) {
      elements[element] = element.widget;
      element.visitChildren(visit);
    }

    visit(child);
    blocks.add(elements);
  });
  return blocks;
}

/// Whether [a] and [b] hold the same elements with the very same widgets.
bool same(Map<Element, Widget> a, Map<Element, Widget> b) =>
    a.length == b.length &&
    a.entries.every((e) => identical(b[e.key], e.value));

/// A widget tree on a screen whose canvas takes ambiguous characters as
/// `ambiguousWidth` columns.
final class Shot {
  Shot(Widget widget, int width, int height, {required int ambiguousWidth})
    : screen = Screen(width, height, ambiguousWidth: ambiguousWidth) {
    final owner = BuildOwner();
    final pipeline = PipelineOwner(() {}, segmenter: screen.canvas.segmenter);
    final root = RootWidget(child: widget).attach(owner);
    owner.buildScope();
    final top = root.renderObject!;
    pipeline
      ..root = top
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    owner.finalizeTree();
  }

  final Screen screen;

  /// The text of the cell at [x], [y]; empty for the second column of a
  /// wide character.
  String at(int x, int y) {
    final cell = screen.surface.cells[y * screen.surface.width + x];
    return cell & kCont != 0 ? '' : screen.glyphs.stringOf(cell);
  }
}
