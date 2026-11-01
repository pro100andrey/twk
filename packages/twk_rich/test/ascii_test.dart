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
      for (final l in renderMarkdown(document, 20, theme, glyphs: Glyphs.ascii))
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
      for (final l in renderMarkdown(document, 20, theme)) joined(l),
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
}
