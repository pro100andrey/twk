// The status bar: its sections at the edges and in the middle, the
// middle one moved, cut and gone as the row narrows, then the left one
// cut, then the right one; a section cut showing its first row; sections
// left out; its style; no bound.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// [text] on one row, cut off with "…".
Text cut(String text) =>
    Text(text, wrap: TextWrap.none, overflow: TextOverflow.ellipsis);

/// A mode on the left, errors in the middle and the place on the right.
StatusBar bar({Style? style}) => StatusBar(
  left: cut('NORMAL'),
  center: cut('3 errors'),
  right: cut('Ln 1, Col 1'),
  style: style,
);

void main() {
  testTwk('the sections at the edges and in the middle of the row; as the '
      'row narrows, the middle one moves between the others, is cut, and '
      'goes, then the left one is cut, then the right one', (t) async {
    final rows = <String>[];
    for (final width in [40, 30, 24, 20, 19, 15, 8]) {
      await t.pumpWidget(bar(), size: (width, 1));
      rows.add(t.lines[0]);
    }
    expect(rows, [
      'NORMAL          3 errors     Ln 1, Col 1',
      'NORMAL    3 errors Ln 1, Col 1',
      'NORMAL 3 er… Ln 1, Col 1',
      'NORMAL … Ln 1, Col 1',
      'NORMAL  Ln 1, Col 1',
      'NO… Ln 1, Col 1',
      'Ln 1, C…',
    ]);
  });

  testTwk('a section cut shows its first row: a Text that wraps the first '
      'of its lines at that width, one on one line with an ellipsis its '
      'line ending with "…"', (t) async {
    final rows = <String>[];
    for (final width in [15, 8]) {
      await t.pumpWidget(
        Column(
          children: [
            const StatusBar(left: Text('NORMAL'), right: Text('Ln 1, Col 1')),
            bar(),
          ],
        ),
        size: (width, 2),
      );
      rows.addAll(t.lines);
    }
    expect(rows, [
      'NOR Ln 1, Col 1',
      'NO… Ln 1, Col 1',
      '   Ln 1,',
      'Ln 1, C…',
    ]);
  });

  testTwk('a section left out leaves its room to the others', (t) async {
    await t.pumpWidget(
      Column(
        children: [
          StatusBar(right: cut('right')),
          StatusBar(center: cut('center')),
          StatusBar(left: cut('left'), center: cut('a long middle')),
          StatusBar(center: cut('middle'), right: cut('end'), gap: 3),
        ],
      ),
      size: (20, 4),
    );
    expect(
      t,
      matchesScreen('''
               right
       center
left a long middle
       middle    end'''),
    );
  });

  testTwk("the row is filled with its style over the theme's surface and "
      'text, which the sections take', (t) async {
    await t.pumpWidget(
      Theme(
        data: ThemeData.dark,
        child: bar(style: const Style(attrs: Attr.reverse)),
      ),
      size: (40, 1),
    );
    for (final x in [0, 10, 39]) {
      expect(
        t,
        styleAt(
          x,
          0,
          allOf(
            hasAttr(Attr.reverse),
            hasBg(const Color.rgb(0x22, 0x25, 0x2c)),
            hasFg(const Color.rgb(0xe6, 0xe8, 0xeb)),
          ),
        ),
      );
    }
  });

  testTwk('with no bound on its width, it is as wide as its sections and '
      'the gaps between them', (t) async {
    await t.pumpWidget(
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [bar(), const Text('|')]),
      ),
      size: (40, 1),
    );
    expect(t.lines[0], 'NORMAL 3 errors Ln 1, Col 1|');
    await t.pumpWidget(
      Row(
        children: [
          IntrinsicWidth(child: bar()),
          const Text('|'),
        ],
      ),
    );
    expect(t.lines[0], 'NORMAL 3 errors Ln 1, Col 1|');
  });
}
