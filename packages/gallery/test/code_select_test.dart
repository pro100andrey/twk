// The Code tab selected with the mouse (doc/design.md, "The mouse"):
// a drag across lines, double and triple clicks, the copy on release (the
// OSC 52 the terminal got) and its toast, y with and without a selection,
// Escape, the wheel during a selection and a drag past the view's edge.
import 'dart:convert';

import 'package:gallery/gallery.dart';
import 'package:gallery/src/shell/code_select.dart';
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// The Text page's Code at 120x36: line 1 on row [top], its first
/// character at column [x0].
const top = 8;
const x0 = 36;

final Color selection = ThemeData.dark.selection.bg!;

Future<void> open(TwkTester t, String route) async {
  await t.pumpWidget(
    galleryApp(route: GalleryRoute.parse(route)),
    size: (120, 36),
  );
  await t.pump();
}

/// The texts the app put on the clipboard (OSC 52), in order.
List<String> clips(TwkTester t) => [
  for (final m in RegExp(
    r'\x1b\]52;c;([A-Za-z0-9+/=]*)',
  ).allMatches(t.written()))
    utf8.decode(base64.decode(m.group(1)!)),
];

/// Presses the left button at [from], drags it through [through] and
/// releases it at the last of those.
Future<void> drag(
  TwkTester t,
  (int, int) from,
  List<(int, int)> through,
) async {
  await t.mouse(MouseKind.down, from.$1, from.$2);
  for (final (x, y) in through) {
    await t.mouse(MouseKind.drag, x, y);
  }
  final (x, y) = through.last;
  await t.mouse(MouseKind.up, x, y);
  await t.pump();
}

/// The columns [from] to [to] of row [y], `x` where the cell has the
/// selection's background and `.` where not.
String marked(TwkTester t, int y, int from, int to) => [
  for (var x = from; x < to; x++)
    if (t.cell(x, y).bg == selection.value) 'x' else '.',
].join();

void main() {
  testTwk('a drag selects across lines and copies the code alone on '
      'release: no line numbers, its line breaks, no blanks ending a '
      'line', (t) async {
    await open(t, '#/text/text?tab=code&t=2000');
    expect(t.lines[top], contains('1  final theme = Theme.of(context);'));
    // the colours of `Theme` and `of`, highlighted
    final colours = [t.cell(x0 + 14, top).fg, t.cell(x0 + 20, top).fg];
    expect(colours.first, isNot(colours.last));
    // from the blank after `final` to the blank after `width:`
    await drag(t, (x0 + 5, top), [(x0 + 6, top), (x0 + 8, top + 2)]);
    expect(clips(t), [
      ' theme = Theme.of(context);\nreturn SizedBox(\n  width:',
    ]);
    expect(t.lines.join('\n'), contains('Copied 3 lines'));
    expect(marked(t, top, x0, x0 + 34), '.....${'x' * 27}..');
    expect(marked(t, top + 1, x0 - 6, x0 + 18), '......${'x' * 16}..');
    expect(marked(t, top + 2, x0, x0 + 12), '${'x' * 9}...');
    // the highlighting kept under the selection
    expect([t.cell(x0 + 14, top).fg, t.cell(x0 + 20, top).fg], colours);
  });

  testTwk('a drag back, within a line: the characters of both cells; the '
      'toast counts them', (t) async {
    await open(t, '#/text/text?tab=code&t=2000');
    await drag(t, (x0 + 10, top), [(x0 + 6, top)]);
    expect(clips(t), ['theme']);
    expect(t.lines.join('\n'), contains('Copied 5 characters'));
  });

  testTwk('a double click selects the word, a triple click the line; a '
      'drag after them by words and by lines', (t) async {
    await open(t, '#/text/text?tab=code&t=2000');
    await t.click(x0 + 8, top);
    await t.click(x0 + 8, top);
    await t.pump();
    expect(clips(t), ['theme']);
    expect(marked(t, top, x0, x0 + 12), '......xxxxx.');
    await t.click(x0 + 8, top + 1);
    await t.click(x0 + 8, top + 1);
    await t.click(x0 + 8, top + 1);
    await t.pump();
    expect(clips(t).last, 'return SizedBox(');
    // a double click, then its drag goes on by words
    await t.click(x0 + 1, top);
    await t.mouse(MouseKind.down, x0 + 1, top);
    await t.mouse(MouseKind.drag, x0 + 4, top + 1);
    await t.mouse(MouseKind.up, x0 + 4, top + 1);
    await t.pump();
    expect(clips(t).last, 'final theme = Theme.of(context);\nreturn');
    // a triple click, then by lines
    await t.pump(const Duration(milliseconds: 400));
    await t.click(x0 + 1, top + 2);
    await t.click(x0 + 1, top + 2);
    await t.mouse(MouseKind.down, x0 + 1, top + 2);
    await t.mouse(MouseKind.drag, x0 + 1, top + 3);
    await t.mouse(MouseKind.up, x0 + 1, top + 3);
    await t.pump();
    expect(clips(t).last, '  width: 32,\n  child: Box(');
  });

  testTwk('a click clears the selection and copies nothing', (t) async {
    await open(t, '#/text/text?tab=code&t=2000');
    await drag(t, (x0, top), [(x0 + 4, top)]);
    expect(marked(t, top, x0, x0 + 6), 'xxxxx.');
    await t.pump(const Duration(milliseconds: 400));
    await t.click(x0 + 2, top + 1);
    await t.pump();
    expect(marked(t, top, x0, x0 + 6), '......');
    expect(clips(t), ['final']);
  });

  testTwk('y copies the selection with one, the whole code without; Escape '
      'clears it, and then goes back to the list', (t) async {
    await open(t, '#/text/text?tab=code&focus=code&t=2000');
    expect(t.lines.last, isNot(contains('esc clear')));
    await t.press('y');
    await t.pump();
    final whole = clips(t).single;
    expect(whole, startsWith('final theme = Theme.of(context);\nreturn'));
    expect(whole, endsWith('  ),\n);'));
    await drag(t, (x0, top + 1), [(x0 + 5, top + 1)]);
    expect(clips(t).last, 'return');
    expect(t.lines.last, contains('esc clear'));
    await t.press('y');
    await t.pump();
    expect(clips(t), [whole, 'return', 'return']);
    await t.press('escape');
    await t.pump();
    expect(marked(t, top + 1, x0, x0 + 7), '.......');
    expect(t.lines.last, isNot(contains('esc clear')));
    expect(t.lines.last, contains('esc pages'));
    await t.press('y');
    await t.pump();
    expect(clips(t).last, whole);
    await t.press('escape');
    await t.pump();
    expect(t.lines.last, contains('tab into the page'));
  });

  testTwk('the wheel scrolls during a selection, which keeps to its text; a '
      'drag under way goes on to the line under the mouse', (t) async {
    await open(t, '#/data/table?tab=code&t=2000');
    // its about takes two rows
    const top = 9;
    expect(t.lines[top], contains('1  final _controller'));
    final first = t.lines[top];
    await drag(t, (x0, top), [(x0 + 2, top)]);
    final copied = clips(t).single;
    expect(first, contains(copied));
    await t.mouse(MouseKind.wheelDown, x0 + 4, top + 4);
    await t.pump();
    expect(t.lines[top], isNot(first));
    expect(t.lines[top], contains('4  '));
    expect(marked(t, top, x0, x0 + 3), '...');
    await t.mouse(MouseKind.wheelUp, x0 + 4, top + 4);
    await t.pump();
    expect(t.lines[top], first);
    expect(marked(t, top, x0, x0 + 4), 'xxx.');
    // a drag that the wheel scrolls under
    await t.pump(const Duration(milliseconds: 400));
    await t.mouse(MouseKind.down, x0, top);
    await t.mouse(MouseKind.drag, x0 + 1, top + 1);
    await t.mouse(MouseKind.wheelDown, x0 + 1, top + 1);
    await t.mouse(MouseKind.up, x0 + 1, top + 1);
    await t.pump();
    // lines 1 to 5: the row under the mouse shows line 5 now
    expect('\n'.allMatches(clips(t).last).length, 4);
  });

  testTwk('a drag past the bottom of the view scrolls it while it stays '
      'there, and selects on to the line under the mouse', (t) async {
    await open(t, '#/data/table?tab=code&t=2000');
    // its about takes two rows
    const top = 9;
    expect(t.lines[top], contains('1  final _controller'));
    final first = t.lines[top];
    await t.mouse(MouseKind.down, x0, top);
    // the hint bar, two rows past the view's last
    await t.mouse(MouseKind.drag, x0, 35);
    await t.pump(const Duration(milliseconds: 120));
    await t.mouse(MouseKind.up, x0, 35);
    await t.pump();
    expect(t.lines[top], isNot(first));
    final copied = clips(t).single;
    expect(copied, startsWith('final _controller'));
    // the 25 rows of the view, then 3 more each of three steps
    expect('\n'.allMatches(copied).length, greaterThan(25));
    expect(t.lines.join('\n'), contains('Copied '));
    // and past the top, back
    await t.pump(const Duration(milliseconds: 400));
    await t.mouse(MouseKind.down, x0, top + 2);
    await t.mouse(MouseKind.drag, x0, 2);
    await t.pump(const Duration(milliseconds: 500));
    await t.mouse(MouseKind.up, x0, 2);
    await t.pump();
    expect(t.lines[top], first);
    expect(clips(t).last, startsWith('final _controller'));
  });

  testTwk('an option that changes the code clears the selection', (t) async {
    await open(t, '#/text/text?tab=code&focus=o:wrap&t=2000');
    await drag(t, (x0, top), [(x0 + 4, top)]);
    expect(marked(t, top, x0, x0 + 6), 'xxxxx.');
    await t.press('right');
    await t.pump();
    expect(t.lines.join('\n'), contains('wrap: .grapheme,'));
    expect(marked(t, top, x0, x0 + 6), '......');
    await t.press('y');
    await t.pump();
    expect(clips(t).last, startsWith('final theme = Theme.of(context);\n'));
  });

  testTwk('a drag past the right edge of the view scrolls it sideways while '
      'it stays there, and past the left edge back', (t) async {
    await open(t, '#/text/text?tab=code&t=2000');
    // line 7, longer than the view
    const row = top + 6;
    expect(t.lines[row], contains("  'Terminals draw"));
    expect(t.lines[row][x0 - 1], ' ');
    await t.mouse(MouseKind.down, x0 + 6, row);
    // the inspector, right of the view
    await t.mouse(MouseKind.drag, 95, row);
    await t.pump(const Duration(milliseconds: 120));
    await t.mouse(MouseKind.up, 95, row);
    await t.pump();
    expect(t.lines[row][x0 - 1], '‹');
    final copied = clips(t).single;
    expect(copied, startsWith("'Terminals draw text in a grid of cells."));
    // more than the 50 columns the view shows of it
    expect(copied.length, greaterThan(50));
    await t.pump(const Duration(milliseconds: 400));
    await t.mouse(MouseKind.down, x0 + 10, row);
    // the list, left of the view
    await t.mouse(MouseKind.drag, 20, row);
    await t.pump(const Duration(milliseconds: 500));
    await t.mouse(MouseKind.up, 20, row);
    await t.pump();
    expect(t.lines[row][x0 - 1], ' ');
  });

  group('CodeText', () {
    final code = CodeText('ab  cd\n\t中x  \nlast');
    test('a cell: its cluster; left of a line its start, right of it the '
        "next line's; above and below the ends", () {
      expect(code.rangeAt(0, 0), (0, 1));
      expect(code.rangeAt(1, 1), (8, 9));
      expect(code.rangeAt(1, 2), (8, 9));
      expect(code.rangeAt(1, 3), (9, 10));
      expect(code.rangeAt(0, -2), (0, 0));
      expect(code.rangeAt(0, 40), (7, 7));
      expect(code.rangeAt(2, 40), (17, 17));
      expect(code.rangeAt(-1, 3), (0, 0));
      expect(code.rangeAt(5, 3), (17, 17));
    });
    testTwk('by words: the word, or the run of blanks; by lines the line '
        "(twk's SelectionArea over its CodeLines)", (t) async {
      // what is selected, as the lines were painted last
      (int, int)? painted;
      // its lines on rows 2 to 4
      await t.pumpWidget(
        SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              SizedBox(
                width: 20,
                height: 3,
                child: CodeLines(
                  code: code,
                  x0: 0,
                  scroll: () => 0,
                  scrollX: () => 0,
                  scrollBy: (rows) => false,
                  scrollAcross: (columns) => false,
                  onPaint: (p, selected) => painted = selected,
                ),
              ),
            ],
          ),
        ),
        size: (20, 8),
      );

      /// What [clicks] clicks at [line], [column] select.
      Future<(int, int)?> at(int line, int column, int clicks) async {
        await t.pump(const Duration(milliseconds: 400));
        for (var i = 0; i < clicks; i++) {
          await t.click(column, line + 2);
        }
        await t.pump();
        return painted;
      }

      expect(await at(0, 1, 2), (0, 2));
      expect(await at(0, 2, 2), (2, 4));
      expect(await at(1, 5, 3), (7, 12));
      expect(await at(-2, 0, 3), (0, 6));
      expect(await at(5, 0, 3), (13, 17));
    });
    test('copied: the blanks that end a line dropped', () {
      expect(code.copied(3, 17), ' cd\n\t中x\nlast');
      expect(copiedWhat('a\nb'), '2 lines');
      expect(copiedWhat('中x'), '2 characters');
      expect(copiedWhat('x'), '1 character');
    });
  });
}
