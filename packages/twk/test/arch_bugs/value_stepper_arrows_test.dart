// A ValueStepper leaves room for its arrows as the theme's glyphs are
// wide, not as `‹` and `›` are: with two-column marks in a narrow room
// the right arrow stays on screen and a click on it steps. Review finding 5
// of the architecture review; the cases that fail wait for arch-cell-text.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const List<Choice<String>> _values = [
  Choice('dark', 'dark'),
  Choice('auto', 'auto-switching'),
];

Widget stepper(Glyphs glyphs, int width, List<String> changes) => Theme(
  data: ThemeData.dark.copyWith(glyphs: glyphs),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: width,
        child: ValueStepper<String>(
          values: _values,
          value: 'dark',
          onChanged: changes.add,
        ),
      ),
    ],
  ),
);

final Glyphs wideArrows = Glyphs.unicode.copyWith(previous: '<<', next: '>>');

void main() {
  testTwk('guard: with one-column arrows the row is as wide as the room and '
      'ends in the right arrow', (t) async {
    final changes = <String>[];
    await t.pumpWidget(stepper(Glyphs.unicode, 10, changes), size: (30, 2));
    expect(t.lines.first.length, lessThanOrEqualTo(10));
    expect(t.lines.first, endsWith('›'));
    await t.click(t.lines.first.length - 1, 0);
    await t.pump();
    expect(changes, ['auto']);
  });

  testTwk('with two-column arrows, a value cut to fit still shows the right '
      'arrow inside the room', (t) async {
    await t.pumpWidget(stepper(wideArrows, 14, []), size: (30, 2));
    // << + blank + 8 columns of label + blank + >> is the 14 columns
    expect(t.lines.first.length, lessThanOrEqualTo(14));
    expect(t.lines.first, endsWith('>>'), reason: 'the row: ${t.lines.first}');
  }, skip: 'probable bug confirmed: arch-cell-text');

  testTwk('with two-column arrows, a click on the right arrow steps to the '
      'next value', (t) async {
    final changes = <String>[];
    await t.pumpWidget(stepper(wideArrows, 14, changes), size: (30, 2));
    await t.click(13, 0);
    await t.pump();
    expect(changes, ['auto'], reason: 'the row: ${t.lines.first}');
  }, skip: 'probable bug confirmed: arch-cell-text');
}
