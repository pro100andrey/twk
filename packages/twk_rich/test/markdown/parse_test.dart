// The tree a document parses into: the values a view of it reads, beyond
// what the HTML of the spec examples shows.
import 'package:test/test.dart';
import 'package:twk_rich/twk_rich.dart';

MdBlock single(String text) => parseMarkdown(text).single;

List<MdInline> inlines(String text) =>
    (parseMarkdown(text).single as MdParagraph).children;

/// How deep [top] nests, through quotes and lists of one item, and the
/// block at the bottom.
(int, MdBlock) bottom(MdBlock top) {
  var block = top;
  var depth = 0;
  while (true) {
    final children = switch (block) {
      MdBlockQuote(:final children) => children,
      MdList(:final items) => items.single.children,
      _ => null,
    };
    if (children == null) {
      return (depth, block);
    }
    depth++;
    block = children.single;
  }
}

void main() {
  group('blocks', () {
    test('headings, ATX and setext', () {
      expect(parseMarkdown('### Three ###\n\nOne\n===\nTwo\n---'), [
        const MdHeading(3, [MdText('Three')]),
        const MdHeading(1, [MdText('One')]),
        const MdHeading(2, [MdText('Two')]),
      ]);
    });

    test('fenced code keeps its info string; its language is the first '
        'word', () {
      final code =
          single('~~~ dart title="a b"\nmain() {}\n~~~') as MdCodeBlock;
      expect(
        code,
        const MdCodeBlock(
          'main() {}\n',
          info: 'dart title="a b"',
          fenced: true,
        ),
      );
      expect(code.language, 'dart');
    });

    test('indented code has no info string', () {
      final code = single('    a\n\n    b\n') as MdCodeBlock;
      expect(code, const MdCodeBlock('a\n\nb\n'));
      expect(code.language, '');
    });

    test('a thematic break and a block quote', () {
      expect(parseMarkdown('***\n> > deep'), [
        const MdThematicBreak(),
        const MdBlockQuote([
          MdBlockQuote([
            MdParagraph([MdText('deep')]),
          ]),
        ]),
      ]);
    });

    test('a bullet list keeps its bullet', () {
      expect(
        single('* a\n* b'),
        const MdList([
          MdListItem([
            MdParagraph([MdText('a')]),
          ]),
          MdListItem([
            MdParagraph([MdText('b')]),
          ]),
        ], marker: '*'),
      );
    });

    test('an ordered list keeps its start and delimiter', () {
      final list = single('7) a\n8) b') as MdList;
      expect(list.ordered, isTrue);
      expect(list.start, 7);
      expect(list.marker, ')');
    });

    test('a list is loose when a blank line separates items or blocks in '
        'one', () {
      expect((single('- a\n- b') as MdList).tight, isTrue);
      expect((single('- a\n\n- b') as MdList).tight, isFalse);
      expect((single('- a\n\n  b') as MdList).tight, isFalse);
      expect((single('- a\n  - b\n\n  c') as MdList).tight, isFalse);
      expect((single('- a\n  - b\n\n    c\n- d') as MdList).tight, isTrue);
      expect((single('- ```\n  a\n\n  ```\n- b') as MdList).tight, isTrue);
      expect((single('- ```\n  a\n\n- b') as MdList).tight, isTrue);
    });

    test('task list items', () {
      expect(
        single('- [ ] to do\n- [x] done\n- [X] done too\n- plain'),
        const MdList([
          MdListItem([
            MdParagraph([MdText('to do')]),
          ], checked: false),
          MdListItem([
            MdParagraph([MdText('done')]),
          ], checked: true),
          MdListItem([
            MdParagraph([MdText('done too')]),
          ], checked: true),
          MdListItem([
            MdParagraph([MdText('plain')]),
          ]),
        ]),
      );
    });

    test('a task list item may be empty so far', () {
      expect(single('- [ ]'), const MdList([MdListItem([], checked: false)]));
    });

    test('brackets not followed by a space do not make a task', () {
      expect(
        single('- [x]y'),
        const MdList([
          MdListItem([
            MdParagraph([
              MdReference('x', [MdText('x')], kind: MdReferenceKind.shortcut),
              MdText('y'),
            ]),
          ]),
        ]),
      );
    });

    test('a table: alignment, header, rows of as many cells', () {
      expect(
        single('| a | b | c | d |\n|---|:--|:-:|--:|\n| 1 \\| 2 |\n'),
        const MdTable(
          [MdAlign.none, MdAlign.left, MdAlign.center, MdAlign.right],
          [
            [MdText('a')],
            [MdText('b')],
            [MdText('c')],
            [MdText('d')],
          ],
          [
            [
              [MdText('1 | 2')],
              [],
              [],
              [],
            ],
          ],
        ),
      );
    });

    test('a table starts at the last line of a paragraph', () {
      expect(parseMarkdown('text\n| a |\n| - |\n| b |'), [
        const MdParagraph([MdText('text')]),
        const MdTable(
          [MdAlign.none],
          [
            [MdText('a')],
          ],
          [
            [
              [MdText('b')],
            ],
          ],
        ),
      ]);
    });

    test('a delimiter row without a pipe is not one', () {
      expect(
        single('a\n:-:'),
        const MdParagraph([
          MdText('a'),
          MdSoftBreak(),
          MdText(':-:'),
        ]),
      );
    });

    test('quotes and items nest 32 deep, a marker deeper being text', () {
      expect(bottom(single('${'>' * 33} x')), (
        32,
        const MdParagraph([MdText('> x')]),
      ));
      final (depth, paragraph) = bottom(single('${'- ' * 34}x'));
      expect(depth, 32);
      expect(paragraph, const MdParagraph([MdText('- - x')]));
    });

    test('a document of nothing but markers parses', () {
      expect(bottom(single('${'>' * 100000} x')).$1, 32);
      expect(bottom(single('${'- ' * 100000}x')).$1, 32);
      expect(bottom(single('${'> - ' * 50000}x')).$1, 32);
    });
  });

  group('inlines', () {
    test('emphasis, strong, strikethrough and code', () {
      expect(inlines('*a* **b** ~~c~~ ~d~ `e`'), const [
        MdEmphasis([MdText('a')]),
        MdText(' '),
        MdStrong([MdText('b')]),
        MdText(' '),
        MdStrikethrough([MdText('c')]),
        MdText(' '),
        MdStrikethrough([MdText('d')]),
        MdText(' '),
        MdCode('e'),
      ]);
    });

    test('tildes of different runs or three do not strike through', () {
      expect(inlines('~~a~ ~~~b~~~'), const [MdText('~~a~ ~~~b~~~')]);
    });

    test('soft and hard line breaks', () {
      expect(inlines('a\nb  \nc\\\nd'), const [
        MdText('a'),
        MdSoftBreak(),
        MdText('b'),
        MdHardBreak(),
        MdText('c'),
        MdHardBreak(),
        MdText('d'),
      ]);
    });

    test('a link with a title, one without, an autolink', () {
      expect(inlines('[a](/x "t") [b](</y z>) <http://h.i>'), const [
        MdLink('/x', [MdText('a')], title: 't'),
        MdText(' '),
        MdLink('/y z', [MdText('b')]),
        MdText(' '),
        MdLink('http://h.i', [MdText('http://h.i')]),
      ]);
    });

    test('URLs, www addresses and email addresses in the text', () {
      expect(inlines('see https://a.dev/x_y_, www.b.org. or c@d.io!'), const [
        MdText('see '),
        MdLink('https://a.dev/x_y', [MdText('https://a.dev/x_y')]),
        MdText('_, '),
        MdLink('http://www.b.org', [MdText('www.b.org')]),
        MdText('. or '),
        MdLink('mailto:c@d.io', [MdText('c@d.io')]),
        MdText('!'),
      ]);
    });

    test('no extended autolink inside a word or a link', () {
      expect(inlines('xwww.a.b [www.c.d](/e)'), const [
        MdText('xwww.a.b '),
        MdLink('/e', [MdText('www.c.d')]),
      ]);
    });

    test('an image shows its description as plain text', () {
      final image = inlines('![a *b* `c`\nd](i.png "t")').single as MdImage;
      expect(image.source, 'i.png');
      expect(image.title, 't');
      expect(image.alt, 'a b c\nd');
    });

    test('an image within the description of one shows its own', () {
      final image = inlines('![a ![b *c*](x.png) [d](/e)](i.png)').single;
      expect((image as MdImage).alt, 'a b c d');
    });

    test('escapes and character references are resolved', () {
      expect(inlines(r'\*a\* &amp; &#x41; &hellip; &nope;'), const [
        MdText('*a* & A … &nope;'),
      ]);
    });
  });

  group('link reference definitions', () {
    test('are left out of the blocks, where a paragraph starts with them, '
        'and collected by their label', () {
      final stream = MarkdownStream(
        '[a]: /x\n\n> [b]: /y\n\ntext\n[c]: /z\n\n- [d]: /w\n  item',
      );
      expect(stream.blocks, const [
        MdBlockQuote([]),
        MdParagraph([
          MdText('text'),
          MdSoftBreak(),
          MdReference('c', [MdText('c')], kind: MdReferenceKind.shortcut),
          MdText(': /z'),
        ]),
        MdList([
          MdListItem([
            MdParagraph([MdText('item')]),
          ]),
        ]),
      ]);
      expect(stream.definitions, const {
        'A': MdDefinition('a', '/x'),
        'B': MdDefinition('b', '/y'),
        'D': MdDefinition('d', '/w'),
      });
    });

    test('a destination and title are unescaped and may be on lines of '
        'their own', () {
      expect(
        MarkdownStream('[a]:\n  <my url>\n  "&amp; \\"b\\"\nc"').definitions,
        const {'A': MdDefinition('a', 'my url', title: '& "b"\nc')},
      );
    });

    test('a definition followed by more than a title on its line is '
        'text', () {
      final stream = MarkdownStream('[a]: /x "t" no');
      expect(stream.definitions, isEmpty);
      expect(stream.blocks.single, isA<MdParagraph>());
    });

    test('the first definition of a label wins; labels match case-folded, '
        'whitespace collapsed', () {
      expect(
        MarkdownStream('[ẞ  x]: /1\n[ss X]: /2\n[ SS\tX ]: /3').definitions,
        const {'SS X': MdDefinition('ẞ  x', '/1')},
      );
      expect(normalizeLabel(' Foo \n\t bar '), 'FOO BAR');
      expect(normalizeLabel('ΑΓΩ'), normalizeLabel('αγω'));
    });

    test('before a setext underline: what follows them is the heading, or '
        'with nothing following the underline is text', () {
      expect(parseMarkdown('[a]: /x\nTitle\n===\n'), const [
        MdHeading(1, [MdText('Title')]),
      ]);
      expect(MarkdownStream('[a]: /x\nTitle\n===\n').definitions, hasLength(1));
      expect(parseMarkdown('[a]: /x\n===\n'), const [
        MdParagraph([MdText('===')]),
      ]);
    });
  });

  group('reference links', () {
    test('of each kind hold their label and parsed text', () {
      expect(inlines('[a *b*][Ref] [c][] [d] ![e][f]'), const [
        MdReference('Ref', [
          MdText('a '),
          MdEmphasis([MdText('b')]),
        ]),
        MdText(' '),
        MdReference('c', [MdText('c')], kind: MdReferenceKind.collapsed),
        MdText(' '),
        MdReference('d', [MdText('d')], kind: MdReferenceKind.shortcut),
        MdText(' '),
        MdReference('f', [MdText('e')], image: true),
      ]);
    });

    test('brackets around no label that may be defined are text', () {
      expect(inlines('[ ] [] [a][ ] [b [c]]'), const [
        MdText('[ ] [] [a][ ] [b '),
        MdReference('c', [MdText('c')], kind: MdReferenceKind.shortcut),
        MdText(']'),
      ]);
    });

    test('brackets that leave emphasis in them unmatched are a reference '
        'only with a label after them', () {
      expect(inlines('*a [b* c] [*d*] [e*][f]*'), const [
        MdEmphasis([MdText('a [b')]),
        MdText(' c] '),
        MdReference('*d*', [
          MdEmphasis([MdText('d')]),
        ], kind: MdReferenceKind.shortcut),
        MdText(' '),
        MdReference('f', [MdText('e*')]),
        MdText('*'),
      ]);
      expect(inlines('[a *b] c*'), const [
        MdText('[a '),
        MdEmphasis([MdText('b] c')]),
      ]);
    });

    test('a label has at most 999 characters', () {
      final label = 'a' * 999;
      expect(inlines('[$label]'), [
        MdReference(label, [MdText(label)], kind: MdReferenceKind.shortcut),
      ]);
      expect(inlines('[${label}a]'), [MdText('[${label}a]')]);
    });

    test('an inline link takes precedence', () {
      expect(inlines('[a](/x)[b]'), const [
        MdLink('/x', [MdText('a')]),
        MdReference('b', [MdText('b')], kind: MdReferenceKind.shortcut),
      ]);
    });
  });

  group('resolving references', () {
    test('a reference whose label is defined is a link or image', () {
      final stream = MarkdownStream(
        '# [Text][A b] ![alt][]\n\n[a  B]: /x "t"\n[ALT]: i.png',
      );
      expect(resolveReferences(stream.blocks, stream.definitions), const [
        MdHeading(1, [
          MdLink('/x', [MdText('Text')], title: 't'),
          MdText(' '),
          MdImage('i.png', [MdText('alt')]),
        ]),
      ]);
    });

    test('one whose label is not defined is its literal text', () {
      expect(resolveInlines(inlines(r'[a *b*][c\*] [d][] ![e]'), const {}), [
        const MdText('[a '),
        const MdEmphasis([MdText('b')]),
        const MdText('][c*] [d][] ![e]'),
      ]);
    });

    test('a link one within a link is its literal text, as links do not '
        'nest; an image one is an image', () {
      expect(
        resolveInlines(inlines('[a [b] ![b]](/x)'), const {
          'B': MdDefinition('b', '/y'),
        }),
        const [
          MdLink('/x', [
            MdText('a [b] '),
            MdImage('/y', [MdText('b')]),
          ]),
        ],
      );
    });

    test('the literal text of one links its email addresses, as other text '
        'does', () {
      expect(resolveInlines(inlines('[mail a@b.io]'), const {}), const [
        MdText('[mail '),
        MdLink('mailto:a@b.io', [MdText('a@b.io')]),
        MdText(']'),
      ]);
    });

    test('in quotes, lists and tables; a block without one is itself', () {
      final blocks = parseMarkdown(
        '# a\n\n> [b]\n\n- [b]\n\n| [b] |\n|-|\n| c |',
      );
      final resolved = resolveReferences(blocks, const {
        'B': MdDefinition('b', '/y'),
      });
      const link = MdLink('/y', [MdText('b')]);
      expect(identical(resolved.first, blocks.first), isTrue);
      expect(resolved.skip(1), const [
        MdBlockQuote([
          MdParagraph([link]),
        ]),
        MdList([
          MdListItem([
            MdParagraph([link]),
          ]),
        ]),
        MdTable(
          [MdAlign.none],
          [
            [link],
          ],
          [
            [
              [MdText('c')],
            ],
          ],
        ),
      ]);
    });
  });

  group('values', () {
    test('equal content makes equal nodes with equal hash codes', () {
      final a = parseMarkdown('# a *b*\n\n- [x] c\n\n| d |\n|-|\n| e |');
      final b = parseMarkdown('# a *b*\n\n- [x] c\n\n| d |\n|-|\n| e |');
      expect(identical(a.first, b.first), isFalse);
      expect(a, b);
      expect(a.map((x) => x.hashCode), b.map((x) => x.hashCode));
      expect(
        a,
        isNot(parseMarkdown('# a *b*\n\n- [ ] c\n\n| d |\n|-|\n| e |')),
      );
    });

    test('nodes of every kind equal by content hash alike', () {
      final a = everyKind('a');
      final again = everyKind('a');
      final b = everyKind('b');
      for (var k = 0; k < a.length; k++) {
        expect(identical(a[k], again[k]), isFalse);
        expect(a[k], again[k]);
        expect(a[k].hashCode, again[k].hashCode, reason: '${a[k]}');
        if (a[k] is! MdThematicBreak &&
            a[k] is! MdSoftBreak &&
            a[k] is! MdHardBreak) {
          expect(a[k], isNot(b[k]));
        }
      }
    });

    test('a node of every kind shows as the code that makes it', () {
      const list =
          "MdList([MdListItem([MdParagraph([MdText('a')])])], start: 3, "
          'marker: ), tight: false)';
      expect(everyKind('a').map((x) => '$x'), [
        "MdParagraph([MdText('a')])",
        "MdHeading(2, [MdText('a')])",
        "MdCodeBlock('a', info: 'a', fenced: true)",
        'MdThematicBreak()',
        "MdBlockQuote([MdParagraph([MdText('a')])])",
        list,
        "MdTable([MdAlign.center], [[MdText('a')]], [[[MdText('a')]]])",
        "MdCode('a')",
        "MdEmphasis([MdText('a')])",
        "MdStrong([MdText('a')])",
        "MdStrikethrough([MdText('a')])",
        "MdLink('a', [MdText('a')], title: 'a')",
        "MdImage('a', [MdText('a')], title: 'a')",
        "MdReference('a', [MdText('a')], kind: collapsed, image: true)",
        "MdDefinition('a', 'a', title: 'a')",
        'MdSoftBreak()',
        'MdHardBreak()',
      ]);
      expect('${const MdText("it's\n\\")}', r"MdText('it\'s\n\\')");
    });

    test('a node shows as the code that makes it', () {
      expect(
        single('- [x] *a*\n').toString(),
        "MdList([MdListItem([MdParagraph([MdEmphasis([MdText('a')])])], "
        'checked: true)], start: null, marker: -, tight: true)',
      );
    });
  });
}

/// A node of every kind, blocks then inlines then a definition, each
/// holding [text] wherever it holds text: made anew on each call, so that
/// two calls give equal nodes that are not the same objects.
List<Object> everyKind(String text) {
  List<MdInline> inlines() => [MdText(text)];
  return [
    MdParagraph(inlines()),
    MdHeading(2, inlines()),
    MdCodeBlock(text, info: text, fenced: true),
    // ignore: prefer_const_constructors, a new object, not the constant
    MdThematicBreak(),
    MdBlockQuote([MdParagraph(inlines())]),
    MdList(
      [
        MdListItem([MdParagraph(inlines())]),
      ],
      start: 3,
      marker: ')',
      tight: false,
    ),
    MdTable(
      [MdAlign.center],
      [inlines()],
      [
        [inlines()],
      ],
    ),
    MdCode(text),
    MdEmphasis(inlines()),
    MdStrong(inlines()),
    MdStrikethrough(inlines()),
    MdLink(text, inlines(), title: text),
    MdImage(text, inlines(), title: text),
    MdReference(text, inlines(), kind: MdReferenceKind.collapsed, image: true),
    MdDefinition(text, text, title: text),
    // ignore: prefer_const_constructors, a new object, not the constant
    MdSoftBreak(),
    // ignore: prefer_const_constructors, a new object, not the constant
    MdHardBreak(),
  ];
}
