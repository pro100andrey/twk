// A Text cuts with the theme's Glyphs.ellipsis: `…` in Glyphs.unicode, `...`
// (three columns, taken from the room) in Glyphs.ascii; so does a Box title.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

Widget themed(Glyphs glyphs, Widget child) => Theme(
  data: ThemeData.dark.copyWith(glyphs: glyphs),
  child: child,
);

void main() {
  const long = Text(
    'The quick brown fox',
    wrap: TextWrap.none,
    overflow: TextOverflow.ellipsis,
    maxLines: 1,
  );

  testTwk('Glyphs.unicode cuts with a single "…"', (t) async {
    await t.pumpWidget(
      themed(Glyphs.unicode, const SizedBox(width: 10, child: long)),
      size: (10, 1),
    );
    expect(t.lines, ['The quick…']);
  });

  testTwk('Glyphs.ascii cuts with "...", its columns from the room', (
    t,
  ) async {
    await t.pumpWidget(
      themed(Glyphs.ascii, const SizedBox(width: 10, child: long)),
      size: (10, 1),
    );
    expect(t.lines, ['The qui...']);
  });

  testTwk('a new theme changes the mark of a Text already shown', (t) async {
    Widget app(Glyphs glyphs) =>
        themed(glyphs, const SizedBox(width: 10, child: long));
    await t.pumpWidget(app(Glyphs.unicode), size: (10, 1));
    expect(t.lines, ['The quick…']);
    await t.pumpWidget(app(Glyphs.ascii), size: (10, 1));
    expect(t.lines, ['The qui...']);
  });

  testTwk('a mark of the theme of any length is the cut', (t) async {
    await t.pumpWidget(
      themed(
        Glyphs.unicode.copyWith(ellipsis: ' [more]'),
        const SizedBox(width: 12, child: long),
      ),
      size: (12, 1),
    );
    expect(t.lines, ['The q [more]']);
  });

  testTwk('the three cells of "..." take no tap, what is shown does', (
    t,
  ) async {
    final log = <String>[];
    await t.pumpWidget(
      themed(
        Glyphs.ascii,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 8,
            child: Text.richLine([
              const Span('abcd'),
              'efghij'.tap(() => log.add('efghij')),
            ]),
          ),
        ),
      ),
      size: (20, 1),
    );
    expect(t.lines.first, 'abcde...');
    await t.click(4, 0);
    await t.click(5, 0);
    await t.click(6, 0);
    await t.click(7, 0);
    expect(log, ['efghij']);
  });

  testTwk('a Box title is cut with the theme mark', (t) async {
    Widget box(Glyphs glyphs) => themed(
      glyphs,
      const SizedBox(
        width: 12,
        height: 3,
        child: Box(
          border: Border.all(type: BorderType.ascii),
          titles: [BorderTitle('a long box title')],
        ),
      ),
    );
    await t.pumpWidget(box(Glyphs.unicode), size: (12, 3));
    expect(t.lines.first, '+a long bo…+');
    await t.pumpWidget(box(Glyphs.ascii), size: (12, 3));
    expect(t.lines.first, '+a long...-+');
  });
}
