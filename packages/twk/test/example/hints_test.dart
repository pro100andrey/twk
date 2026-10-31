// The layout guide's second app (doc/guides/layout.md): `s` and its hint
// exist side by side only; Align on a bounded axis fills it, with a
// heightFactor it does not.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../../example/guides/hints.dart' show Hints;

void main() {
  testTwk('wide: the swap key is hinted and swaps the panes', (t) async {
    await t.pumpWidget(const Hints(), size: (50, 5));
    expect(t, containsLine(contains('s swap')));
    expect(t.rect(find.text('one')).x, lessThan(t.rect(find.text('two')).x));
    await t.press('s');
    await t.pump();
    expect(t.rect(find.text('two')).x, lessThan(t.rect(find.text('one')).x));
  });

  testTwk('narrow: no hint, and the key does nothing', (t) async {
    await t.pumpWidget(const Hints(), size: (30, 5));
    expect(t, containsLine(contains('q quit')));
    expect(t, isNot(containsLine(contains('swap'))));
    expect(find.text('two'), findsNothing);
    await t.press('s');
    await t.pump();
    expect(find.text('one'), findsOneWidget);
  });

  testTwk('the hint follows the width when the terminal is resized', (t) async {
    await t.pumpWidget(const Hints(), size: (30, 5));
    expect(t, isNot(containsLine(contains('swap'))));
    await t.resize(50, 5);
    // the bar follows the keys one frame after the layout changes them
    await t.pumpUntilIdle();
    expect(t, containsLine(contains('s swap')));
  });

  testTwk('Column: max takes the room, also in a Column; min does not', (
    t,
  ) async {
    Widget header(MainAxisSize size) => Column(
      children: [
        Column(mainAxisSize: size, children: const [Text('a'), Text('b')]),
        const Expanded(child: Text('list')),
      ],
    );
    await t.pumpWidget(header(.max), size: (20, 10));
    expect(t.rect(find.byType(Column).at(1)).height, 10);
    expect(t.rect(find.text('list')).height, 0);
    await t.pumpWidget(header(.min), size: (20, 10));
    expect(t.rect(find.byType(Column).at(1)).height, 2);
    expect(t.rect(find.text('list')).height, 8);
  });

  testTwk('Align: fills a bounded height, heightFactor: 1 does not', (t) async {
    await t.pumpWidget(
      const Column(
        children: [
          SizedBox(
            height: 6,
            child: Row(
              children: [
                Expanded(
                  child: Align(alignment: .centerLeft, child: Text('full')),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 6,
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: .centerLeft,
                    heightFactor: 1,
                    child: Text('one'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      size: (20, 14),
    );
    final aligns = find.byType(Align);
    expect(t.rect(aligns.at(0)).height, 6);
    expect(t.rect(aligns.at(1)).height, 1);
  });
}
