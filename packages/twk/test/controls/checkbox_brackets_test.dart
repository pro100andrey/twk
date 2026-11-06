// A checkbox's brackets are a field of the glyph set, as a radio button's
// are: the marks between them are not cut out of a longer string by guess.
import 'package:test/test.dart';
import 'package:twk/log.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

Widget themed(Glyphs glyphs, bool value) => Theme(
  data: ThemeData.dark.copyWith(glyphs: glyphs),
  child: Checkbox(value: value, onChanged: (_) {}, label: 'a'),
);

List<String> warnings(TwkTester t) => [
  for (final r in t.logs.records)
    if (r.level == LogLevel.warning) r.message,
];

void main() {
  testTwk('the default look is [x] and [ ]', (t) async {
    await t.pumpWidget(themed(Glyphs.unicode, true), size: (8, 1));
    expect(t.lines.single, '[x] a');
    await t.pumpWidget(themed(Glyphs.ascii, false), size: (8, 1));
    expect(t.lines.single, '[ ] a');
  });

  testTwk('a mark of three characters is not split into brackets and a mark, '
      'it is the ASCII mark, warned of, in the brackets of the set', (t) async {
    await t.pumpWidget(
      themed(Glyphs.unicode.copyWith(checkboxOn: 'yes'), true),
      size: (8, 1),
    );
    expect(t.lines.single, '[x] a');
    expect(warnings(t), hasLength(1));
    expect(warnings(t).single, startsWith("Glyphs.checkboxOn 'yes'"));
  });

  testTwk('the brackets are drawn in the bracket style and the mark in the '
      'mark style', (t) async {
    await t.pumpWidget(
      Theme(
        data: ThemeData.dark.copyWith(
          glyphs: Glyphs.unicode.copyWith(checkboxBrackets: ('<', '>')),
        ),
        child: Checkbox(
          value: true,
          onChanged: (_) {},
          bracketStyle: const Style(fg: Color.red),
        ),
      ),
      size: (8, 1),
    );
    expect(t.lines.single.trimRight(), '<x>');
    expect(t, styleAt(0, 0, hasFg(Color.red)));
    expect(t, styleAt(2, 0, hasFg(Color.red)));
    expect(t, styleAt(1, 0, isNot(hasFg(Color.red))));
  });

  testTwk('empty brackets draw no cell and no span', (t) async {
    await t.pumpWidget(
      themed(
        Glyphs.unicode.copyWith(
          checkboxOn: '✓',
          checkboxOff: '·',
          checkboxBrackets: ('', ''),
        ),
        true,
      ),
      size: (8, 1),
    );
    expect(t.lines.single, '✓ a');
    expect(warnings(t), isEmpty);
  });

  testTwk('a bracket of two columns is the ASCII one, warned of', (t) async {
    await t.pumpWidget(
      themed(Glyphs.unicode.copyWith(checkboxBrackets: ('【', '】')), true),
      size: (8, 1),
    );
    expect(t.lines.single, '[x] a');
    expect(warnings(t), hasLength(2));
  });
}
