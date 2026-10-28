// Runs of widgets: a Wrap flows its children onto the next run where they
// would not fit, the render objects of the children in order, its settings
// on its render object.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show RenderWrap;

import 'view.dart';

/// Tags of mixed widths, a wide one among them.
const tags = [Text('alpha'), Text('β'), Text('日本語'), Text('ok')];

/// The rows [v] shows, a wide character once.
List<String> shown(View v) => [
  for (final row in v.rows()) row.replaceAll('\x00', ''),
];

void main() {
  // the runs of the tags at each width, gap 1
  const runs = <int, List<String>>{
    17: ['alpha β 日本語 ok'],
    14: ['alpha β 日本語', 'ok'],
    12: ['alpha β', '日本語 ok'],
    8: ['alpha β', '日本語', 'ok'],
    6: ['alpha', 'β', '日本語', 'ok'],
  };
  for (final MapEntry(key: width, value: want) in runs.entries) {
    test('a Wrap of tags of mixed widths wraps at $width columns', () {
      final v = View(width, 4)..pump(const Wrap(gap: 1, children: tags));
      expect(shown(v), [...want, for (var i = want.length; i < 4; i++) '']);
    });
  }

  test('a Wrap is as long as its longest run: a Column centers it, and '
      'the alignment places the runs in it', () {
    final v = View(10, 3)
      ..pump(
        const Column(
          children: [
            Wrap(
              alignment: WrapAlignment.end,
              gap: 1,
              children: [Text('abc'), Text('de'), Text('fghi')],
            ),
          ],
        ),
      );
    expect(v.rows(), ['  abc de', '    fghi', '']);
  });

  test('a Wrap gives its settings to its render object, and a new widget '
      'changes them on the same one', () {
    final v = View(6, 4)
      ..pump(
        const Wrap(
          direction: Axis.vertical,
          alignment: WrapAlignment.end,
          runAlignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.end,
          gap: 1,
          runGap: 2,
          children: [Label('ab'), Label('c'), Label('d')],
        ),
      );
    final wrap = v.top as RenderWrap;
    expect(
      [
        wrap.direction,
        wrap.alignment,
        wrap.runAlignment,
        wrap.crossAxisAlignment,
        wrap.gap,
        wrap.runGap,
      ],
      [
        Axis.vertical,
        WrapAlignment.end,
        WrapAlignment.center,
        WrapCrossAlignment.end,
        1,
        2,
      ],
    );
    // ab and c in a run, d in the next
    expect(v.rows(), ['', 'ab', '', ' c  d']);
    v.pump(const Wrap(children: [Label('ab'), Label('c'), Label('d')]));
    expect(v.top, same(wrap));
    expect(
      [
        wrap.direction,
        wrap.alignment,
        wrap.runAlignment,
        wrap.crossAxisAlignment,
        wrap.gap,
        wrap.runGap,
      ],
      [
        Axis.horizontal,
        WrapAlignment.start,
        WrapAlignment.start,
        WrapCrossAlignment.start,
        0,
        0,
      ],
    );
    expect(v.rows(), ['abcd', '', '', '']);
  });

  test('the render objects of children inserted, moved and removed keep '
      'their order', () {
    Widget wrap(List<String> keys) => Wrap(
      gap: 1,
      children: [for (final k in keys) Label(k, key: ValueKey(k))],
    );
    final v = View(5, 3)..pump(wrap(['a', 'c']));
    final [a, c] = childrenOf(v.top);
    v.pump(wrap(['c', 'b', 'a']));
    final [c2, b, a2] = childrenOf(v.top);
    expect([c2, a2], [same(c), same(a)]);
    expect(v.rows(), ['c b a', '', '']);
    v.pump(wrap(['b', 'c']));
    expect(childrenOf(v.top), [same(b), same(c)]);
    expect(v.rows(), ['b c', '', '']);
  });
}
