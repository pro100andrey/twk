// One switch for an ASCII app: the markdown, the diff and the JSON view
// draw their marks from the theme's Glyphs, ASCII only under Glyphs.ascii.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_rich/twk_rich.dart';
import 'package:twk_test/twk_test.dart';

const document = '''
# Title

- one
  - two
    - three
- [x] done
- [ ] todo

> quoted

| a | b |
|---|---|
| 1 | 2 |

---
''';

String joined(List<Span> line) => line.map((s) => s.text).join();

bool isAscii(Iterable<String> lines) =>
    lines.every((l) => l.runes.every((r) => r < 0x80));

void main() {
  final theme = MarkdownTheme.from(ThemeData.dark);

  test('renderMarkdown with Glyphs.ascii draws ASCII only', () {
    final lines = [
      for (final l in markdownLines(
        TextSegmenter(),
        document,
        20,
        theme: theme,
        glyphs: Glyphs.ascii,
      ))
        joined(l),
    ];
    expect(isAscii(lines), isTrue, reason: '$lines');
    expect(lines, containsAll(['*   one', '    . two', '      * three']));
    expect(lines, contains('[x] done'));
    expect(lines, contains('| quoted'));
    expect(lines, contains('--------------------'));
  });

  test('renderMarkdown draws Glyphs.unicode as it did, the third bullet '
      'a bullet and the task box the checkbox marks', () {
    final lines = [
      for (final l in markdownLines(
        TextSegmenter(),
        document,
        20,
        theme: theme,
      ))
        joined(l),
    ];
    expect(lines, containsAll(['•   one', '    ◦ two', '      • three']));
    expect(lines, containsAll(['[x] done', '[ ] todo']));
    expect(lines, contains('─' * 20));
    expect(lines, contains('│ quoted'));
  });

  testTwk('a MarkdownView and a JsonView under Glyphs.ascii', (t) async {
    await t.pumpWidget(
      Theme(
        data: ThemeData.dark.copyWith(glyphs: Glyphs.ascii),
        child: Column(
          children: [
            Expanded(child: MarkdownView(document, theme: theme)),
            const Expanded(
              child: JsonView(
                value: {'long': 'abcdefghij'},
                maxStringLength: 4,
              ),
            ),
          ],
        ),
      ),
      size: (30, 30),
    );
    expect(isAscii(t.lines), isTrue, reason: '${t.lines}');
    expect(t.lines.any((l) => l.contains('"abcd...')), isTrue);
  });

  group('the lines a DiffView leaves out', () {
    final before = [for (var i = 1; i <= 30; i++) 'line $i\n'].join();
    final after = before.replaceFirst('line 15\n', 'line fifteen\n');
    final diff = Diff.between(before, after, context: 1);

    Future<List<String>> gap(TwkTester t, Glyphs glyphs) async {
      await t.pumpWidget(
        Theme(
          data: ThemeData.dark.copyWith(glyphs: glyphs),
          child: DiffView(diff),
        ),
        size: (40, 12),
      );
      return t.lines;
    }

    testTwk('are marked by Glyphs.omitted: ⋯ in unicode, ... in ASCII', (
      t,
    ) async {
      expect(
        (await gap(t, Glyphs.unicode)).first,
        contains('⋯ 13 unchanged lines'),
      );
      final ascii = await gap(t, Glyphs.ascii);
      expect(ascii.first, contains('... 13 unchanged lines'));
      expect(isAscii(ascii), isTrue, reason: '$ascii');
    });

    testTwk('do not take the text ellipsis of a theme that copies unicode', (
      t,
    ) async {
      final lines = await gap(t, Glyphs.unicode.copyWith(ellipsis: '~'));
      expect(lines.first, contains('⋯ 13 unchanged lines'));
      final own = await gap(t, Glyphs.unicode.copyWith(omitted: '[..]'));
      expect(own.first, contains('[..] 13 unchanged lines'));
    });
  });
}
