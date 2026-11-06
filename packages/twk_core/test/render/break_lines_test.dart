// breakLines: the lines a paragraph of a wrap breaks a text into, as ranges
// of the text, so that a caller with styled text of its own breaks it alike.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// The text of each line [text] breaks into at [width].
List<String> lines(String text, int width, {TextWrap wrap = TextWrap.word}) => [
  for (final (from, to) in breakLines(TextSegmenter(), text, width, wrap: wrap))
    text.substring(from, to),
];

void main() {
  test('by word: spaces hang, a hyphen inside a word breaks', () {
    expect(lines('well-known words here', 8), [
      'well-',
      'known',
      'words',
      'here',
    ]);
    expect(lines('ab cd  ef', 5), ['ab cd', 'ef']);
  });

  test('a word longer than the line breaks between graphemes', () {
    expect(lines('abcdefgh', 3), ['abc', 'def', 'gh']);
  });

  test('a newline ends a line; an empty text has one empty line', () {
    expect(lines('a\n\nb', 5), ['a', '', 'b']);
    expect(breakLines(TextSegmenter(), '', 5), [(0, 0)]);
  });

  test('CJK breaks between its characters, not before closing punctuation', () {
    expect(lines('日本語、テキスト', 6), ['日本', '語、テ', 'キスト']);
  });

  test('by grapheme: any two, spaces counting', () {
    expect(lines('ab cd ef', 4, wrap: TextWrap.grapheme), ['ab c', 'd ef']);
  });

  test('every line is what a paragraph of the text lays out', () {
    const text = 'the quick brown fox jumps over the lazy dog, well-known';
    for (var width = 1; width < 30; width++) {
      final p = RenderParagraph([(text, const Pen())]);
      final rows = <String>[];
      final tester = breakLines(TextSegmenter(), text, width);
      p.layout(
        BoxConstraints(minWidth: width, maxWidth: width, maxHeight: 100),
      );
      for (var y = 0; y < p.height; y++) {
        final (from, _) = p.textRangeAt(0, y);
        final (_, to) = p.textRangeAt(width - 1, y);
        rows.add(text.substring(from, to).trimRight());
      }
      expect([for (final (a, b) in tester) text.substring(a, b)], rows);
    }
  });

  test('by the segmenter given: ambiguous-wide letters take two columns', () {
    // Greek letters are ambiguous in width; 4 of them are 8 columns wide
    const text = 'αβγδ εζηθ';
    String join(TextSegmenter s, int width) => [
      for (final (a, b) in breakLines(s, text, width)) text.substring(a, b),
    ].join('|');
    expect(join(TextSegmenter(), 5), 'αβγδ|εζηθ');
    expect(join(TextSegmenter(ambiguousWidth: 2), 5), 'αβ|γδ|εζ|ηθ');
    expect(join(TextSegmenter(ambiguousWidth: 2), 8), 'αβγδ|εζηθ');
  });
}
