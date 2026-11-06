// A LineGauge's own marks (type null: the theme's gaugeFilled, gaugeHalf and
// gaugeEmpty) keep the Glyphs width rule: a mark not one cell wide is the
// ASCII mark of the same meaning, with one warning; an empty one is no
// warning.
import 'package:test/test.dart';
import 'package:twk/log.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

Widget gauge(Glyphs glyphs, {double ratio = 0.45}) => Theme(
  data: ThemeData.dark.copyWith(glyphs: glyphs),
  child: SizedBox(
    width: 10,
    height: 1,
    child: LineGauge(ratio: ratio),
  ),
);

String tooWide(String field, String glyph, String instead) =>
    "Glyphs.$field '$glyph' is 2 cells wide, not 1; $instead is drawn in its "
    'place.';

List<String> warnings(TwkTester t) => [
  for (final r in t.logs.records)
    if (r.level == LogLevel.warning && r.message.startsWith('Glyphs.'))
      r.message,
];

void main() {
  testTwk('the default marks draw as they did, with no warning', (t) async {
    await t.pumpWidget(gauge(Glyphs.unicode), size: (10, 1));
    expect(t.lines, ['────╴─────']);
    expect(warnings(t), isEmpty);
  });

  testTwk('a wide filled mark is the ASCII one, the empty mark kept', (
    t,
  ) async {
    await t.pumpWidget(
      gauge(Glyphs.unicode.copyWith(gaugeFilled: '🙂', gaugeHalf: '')),
      size: (10, 1),
    );
    expect(t.lines, ['=====─────']);
    expect(warnings(t), [tooWide('gaugeFilled', '🙂', "Glyphs.ascii's '='")]);
  });

  testTwk('a wide empty mark is the ASCII one, the filled mark kept', (
    t,
  ) async {
    await t.pumpWidget(
      gauge(Glyphs.unicode.copyWith(gaugeEmpty: '🙂', gaugeHalf: '')),
      size: (10, 1),
    );
    expect(t.lines, ['─────-----']);
    expect(warnings(t), [tooWide('gaugeEmpty', '🙂', "Glyphs.ascii's '-'")]);
  });

  testTwk('a wide half mark is no half cell, warned of once', (t) async {
    await t.pumpWidget(
      gauge(Glyphs.unicode.copyWith(gaugeHalf: '🙂')),
      size: (10, 1),
    );
    expect(t.lines, ['──────────']);
    await t.pumpWidget(
      gauge(Glyphs.unicode.copyWith(gaugeHalf: '🙂'), ratio: 0.5),
      size: (10, 1),
    );
    expect(warnings(t), [tooWide('gaugeHalf', '🙂', 'no mark')]);
  });

  testTwk('an empty filled or empty mark is the ASCII one, no warning', (
    t,
  ) async {
    await t.pumpWidget(
      gauge(
        Glyphs.unicode.copyWith(gaugeFilled: '', gaugeEmpty: '', gaugeHalf: ''),
      ),
      size: (10, 1),
    );
    expect(t.lines, ['=====-----']);
    expect(warnings(t), isEmpty);
  });
}
