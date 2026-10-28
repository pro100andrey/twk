// The links of a Markdown view as the app's own: a click on a link, an
// image or a reference, in a paragraph, a heading or a table, told to
// onLinkTap with its destination and title, the hyperlink still written
// unless hyperlinks is false; and the headings of the view, with their
// slugs, which its controller scrolls to.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_rich/twk_rich.dart';
import 'package:twk_test/twk_test.dart';

// 0 see the docs now
// 2 Title
// 4 logo and ref
// 6 a │ b
// 7 ──┼───
// 8 l │ x
const document =
    'see [the docs](https://x.dev "Docs") now\n'
    '\n'
    '# [Title](https://t.dev)\n'
    '\n'
    '![logo](https://i.dev/logo.png "Logo") and [ref]\n'
    '\n'
    '| a | b |\n'
    '|---|---|\n'
    '| [l](https://l.dev) | x |\n'
    '\n'
    '[ref]: https://r.dev "Ref"\n';

/// A link told to onLinkTap.
typedef Tap = (String destination, String? title);

void main() {
  group('onLinkTap', () {
    testTwk('a click on a link, an image, a reference and a link in a '
        'table tells its destination and title', (t) async {
      final taps = <Tap>[];
      await t.pumpWidget(
        MarkdownView(document, onLinkTap: (d, title) => taps.add((d, title))),
        size: (40, 12),
      );
      await t.click(4, 0);
      await t.click(11, 0);
      expect(taps, [('https://x.dev', 'Docs'), ('https://x.dev', 'Docs')]);
      taps.clear();
      await t.click(3, 0);
      await t.click(12, 0);
      await t.click(2, 1);
      await t.click(6, 4);
      await t.click(30, 4);
      expect(taps, isEmpty, reason: 'beside the links');
      await t.click(2, 2);
      await t.click(3, 4);
      await t.click(9, 4);
      await t.click(0, 8);
      expect(taps, [
        ('https://t.dev', null),
        ('https://i.dev/logo.png', 'Logo'),
        ('https://r.dev', 'Ref'),
        ('https://l.dev', null),
      ]);
      expect(t.cell(4, 0).link, 'https://x.dev', reason: 'still a hyperlink');
      expect(t.cell(0, 8).link, 'https://l.dev');
    });

    testTwk('a press on a link released elsewhere, or with another button, '
        'is no tap', (t) async {
      final taps = <Tap>[];
      await t.pumpWidget(
        MarkdownView(document, onLinkTap: (d, title) => taps.add((d, title))),
        size: (40, 12),
      );
      await t.mouse(MouseKind.down, 4, 0);
      await t.mouse(MouseKind.drag, 6, 0);
      await t.mouse(MouseKind.up, 6, 0);
      await t.click(4, 0, button: 2);
      expect(taps, isEmpty);
    });

    testTwk('the innermost of a link around an image', (t) async {
      final taps = <Tap>[];
      await t.pumpWidget(
        MarkdownView(
          'a [![pic](https://i.dev/p.png) and text](https://l.dev "L")',
          onLinkTap: (d, title) => taps.add((d, title)),
        ),
        size: (40, 3),
      );
      expect(t.lines.first, 'a pic and text');
      await t.click(2, 0);
      await t.click(7, 0);
      expect(taps, [('https://i.dev/p.png', null), ('https://l.dev', 'L')]);
    });

    testTwk('within a SelectionArea, the click is still a tap', (t) async {
      final taps = <Tap>[];
      await t.pumpWidget(
        SelectionArea(
          child: MarkdownView(
            document,
            onLinkTap: (d, title) => taps.add((d, title)),
          ),
        ),
        size: (40, 12),
      );
      await t.click(5, 0);
      expect(taps, [('https://x.dev', 'Docs')]);
    });

    testTwk('hyperlinks: false writes no hyperlink; a click on a link in a '
        'paragraph or a heading is told still', (t) async {
      final taps = <Tap>[];
      await t.pumpWidget(
        MarkdownView(
          document,
          hyperlinks: false,
          onLinkTap: (d, title) => taps.add((d, title)),
        ),
        size: (40, 12),
      );
      expect(t.cell(4, 0).link, isNull);
      expect(t.cell(2, 2).link, isNull);
      expect(t.cell(3, 4).link, isNull);
      expect(t.cell(0, 8).link, isNull);
      await t.click(4, 0);
      await t.click(2, 2);
      await t.click(9, 4);
      await t.click(12, 0);
      expect(taps, [
        ('https://x.dev', 'Docs'),
        ('https://t.dev', null),
        ('https://r.dev', 'Ref'),
      ]);
    });

    testTwk('without onLinkTap, a click is left to the terminal', (t) async {
      await t.pumpWidget(const MarkdownView(document), size: (40, 12));
      await t.click(4, 0);
      expect(t.cell(4, 0).link, 'https://x.dev');
    });

    testTwk('a link streamed in is told, and one kept from before', (t) async {
      final taps = <Tap>[];
      void tap(String d, String? title) => taps.add((d, title));
      var data = 'first [one](https://1.dev)\n\n';
      await t.pumpWidget(MarkdownView(data, onLinkTap: tap), size: (40, 6));
      const more = 'then [two](https://2.dev "Two")';
      data += more;
      await t.pumpWidget(
        MarkdownView(data, appended: more, onLinkTap: tap),
      );
      expect(t.lines.take(3), ['first one', '', 'then two']);
      await t.click(6, 0);
      await t.click(5, 2);
      expect(taps, [('https://1.dev', null), ('https://2.dev', 'Two')]);
    });

    testTwk('MarkdownView.blocks: references resolved by its definitions', (
      t,
    ) async {
      final taps = <Tap>[];
      final stream = MarkdownStream('see [ref]\n\n[ref]: https://r.dev "R"\n');
      await t.pumpWidget(
        MarkdownView.blocks(
          stream.blocks,
          definitions: stream.definitions,
          onLinkTap: (d, title) => taps.add((d, title)),
        ),
        size: (20, 3),
      );
      await t.click(5, 0);
      expect(taps, [('https://r.dev', 'R')]);
    });
  });

  group('headings', () {
    test('markdownHeadings: text, level and a slug as GitHub makes it', () {
      final stream = MarkdownStream(
        '# Getting *started*\n\n'
        'text\n\n'
        "## What's `new`? 1.2!\n\n"
        '> ### Quoted\n\n'
        '- ## In a list\n\n'
        'Setext\n---\n\n'
        '# Getting started\n\n'
        '# Getting started\n\n'
        '## [Linked](https://x.dev) ![pic](p.png)\n\n'
        '## Ünïcode 你好 snake_case\n',
      );
      expect(markdownHeadings(stream.blocks, stream.definitions), const [
        MarkdownHeading('Getting started', 1, 'getting-started'),
        MarkdownHeading("What's new? 1.2!", 2, 'whats-new-12'),
        MarkdownHeading('Quoted', 3, 'quoted'),
        MarkdownHeading('In a list', 2, 'in-a-list'),
        MarkdownHeading('Setext', 2, 'setext'),
        MarkdownHeading('Getting started', 1, 'getting-started-1'),
        MarkdownHeading('Getting started', 1, 'getting-started-2'),
        MarkdownHeading('Linked pic', 2, 'linked-pic'),
        MarkdownHeading('Ünïcode 你好 snake_case', 2, 'ünïcode-你好-snake_case'),
      ]);
    });

    test('a heading is equal by text, level and slug, hashes alike and '
        'shows them', () {
      MarkdownHeading heading(int level) =>
          MarkdownHeading('Install', level, 'install');
      expect(heading(2), heading(2));
      expect(heading(2).hashCode, heading(2).hashCode);
      expect(heading(2), isNot(heading(3)));
      expect(heading(2), isNot(const MarkdownHeading('Install', 2, 'x')));
      expect(heading(2), isNot(const MarkdownHeading('Setup', 2, 'install')));
      expect('${heading(2)}', 'MarkdownHeading(Install, 2, #install)');
    });

    testTwk('the controller has the headings of the view, its listeners '
        'told as they change while the text streams in', (t) async {
      final controller = MarkdownController();
      var told = 0;
      controller.addListener(() => told++);
      expect(controller.headings, isEmpty);
      var data = '# One\n\ntext\n\n';
      await t.pumpWidget(
        MarkdownView(data, controller: controller),
        size: (30, 10),
      );
      await t.pump();
      expect(controller.headings, const [MarkdownHeading('One', 1, 'one')]);
      expect(told, 1);
      const more = 'more text\n\n';
      data += more;
      await t.pumpWidget(
        MarkdownView(data, appended: more, controller: controller),
      );
      await t.pump();
      expect(told, 1, reason: 'the headings as they were');
      const heading = '## Two';
      data += heading;
      await t.pumpWidget(
        MarkdownView(data, appended: heading, controller: controller),
      );
      await t.pump();
      expect(controller.headings, const [
        MarkdownHeading('One', 1, 'one'),
        MarkdownHeading('Two', 2, 'two'),
      ]);
      expect(told, 2);
      await t.pumpWidget(const SizedBox());
      await t.pump();
      expect(controller.headings, isEmpty, reason: 'no view has it');
    });

    testTwk('the controller goes over to a view built in place of its '
        "own: its headings and scrollToHeading are the new one's", (
      t,
    ) async {
      final controller = MarkdownController();
      addTearDown(controller.dispose);
      final data = [
        '# Top',
        for (var i = 0; i < 10; i++) 'paragraph $i',
        '## End',
      ].join('\n\n');
      Widget view(int key) => SingleChildScrollView(
        child: MarkdownView(data, key: ValueKey(key), controller: controller),
      );
      await t.pumpWidget(view(0), size: (20, 6));
      await t.pump();
      expect(controller.headings.map((h) => h.slug), ['top', 'end']);
      await t.pumpWidget(view(1));
      await t.pump();
      expect(controller.headings.map((h) => h.slug), ['top', 'end']);
      expect(controller.scrollToHeading('end'), isTrue);
      await t.pump();
      expect(t.lines.last, 'End');
    });

    testTwk('scrollToHeading scrolls the least that shows the heading', (
      t,
    ) async {
      final controller = MarkdownController();
      final data = [
        '# Top',
        for (var i = 0; i < 10; i++) 'paragraph $i',
        '## Middle',
        for (var i = 10; i < 20; i++) 'paragraph $i',
        '## End',
        'last',
      ].join('\n\n');
      await t.pumpWidget(
        SingleChildScrollView(
          child: MarkdownView(data, controller: controller),
        ),
        size: (20, 6),
      );
      expect(t.lines.first, 'Top');
      expect(controller.scrollToHeading('middle'), isTrue);
      await t.pump();
      expect(t.lines.last, 'Middle');
      expect(controller.scrollToHeading('#end'), isTrue);
      await t.pump();
      expect(t.lines.last, 'End');
      expect(controller.scrollToHeading('top'), isTrue);
      await t.pump();
      expect(t.lines.first, 'Top');
      expect(controller.scrollToHeading('nowhere'), isFalse);
    });

    testTwk('a link to a heading of the document, followed by the app', (
      t,
    ) async {
      final controller = MarkdownController();
      final data = [
        'see [the end](#the-end)',
        for (var i = 0; i < 10; i++) 'paragraph $i',
        '# The end',
      ].join('\n\n');
      await t.pumpWidget(
        SingleChildScrollView(
          child: MarkdownView(
            data,
            controller: controller,
            onLinkTap: (destination, _) =>
                controller.scrollToHeading(destination),
          ),
        ),
        size: (30, 5),
      );
      await t.click(5, 0);
      await t.pump();
      expect(t.lines.last, 'The end');
    });
  });
}
