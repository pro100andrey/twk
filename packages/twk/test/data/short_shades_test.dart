// A theme's Glyphs.shades of one entry, or none, built straight from the
// constructor (which cannot check a list's length): the charts and a
// Skeleton draw with it rather than throw — one shade is full or nothing,
// none is Glyphs.ascii's ramp.
import 'dart:collection';

import 'package:test/test.dart';
import 'package:twk/src/data/chart_glyphs.dart' show ChartGlyphs;
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

Widget themed(Glyphs glyphs, Widget child) => Theme(
  data: ThemeData.dark.copyWith(glyphs: glyphs),
  child: child,
);

void main() {
  const one = Glyphs(shades: ['#'], partialBlocks: false);
  const none = Glyphs(shades: [], partialBlocks: false);

  test('ChartGlyphs.use does not rebuild its ramp for the same list', () {
    // rampOf of a one-entry list is a new list each time, so the cache is
    // kept by the theme's list: it is not read again while that is the same
    final list = _Counting(['#']);
    final glyphs = Glyphs(shades: list, partialBlocks: false);
    final chart = ChartGlyphs();
    final segmenter = TextSegmenter();
    chart.use(segmenter, glyphs);
    expect(chart.upSteps, 1);
    final reads = list.reads;
    expect(reads, greaterThan(0));
    chart
      ..use(segmenter, glyphs)
      ..use(segmenter, glyphs.copyWith(swatch: 'x'));
    expect(list.reads, reads);
  });

  testTwk('a Sparkline: one shade is full or blank', (t) async {
    await t.pumpWidget(
      themed(
        one,
        const SizedBox(width: 3, child: Sparkline(data: [0, 4, 8])),
      ),
      size: (3, 1),
    );
    expect(t.lines, [' ##']);
  });

  testTwk("a Sparkline: no shade draws Glyphs.ascii's ramp", (t) async {
    await t.pumpWidget(
      themed(
        none,
        const SizedBox(width: 3, child: Sparkline(data: [0, 4, 8])),
      ),
      size: (3, 1),
    );
    expect(t.lines, [' :#']);
  });

  testTwk('a BarChart and a Skeleton with one shade or none', (t) async {
    for (final glyphs in [one, none]) {
      await t.pumpWidget(
        themed(
          glyphs,
          const Column(
            children: [
              SizedBox(
                height: 2,
                width: 6,
                child: BarChart(
                  groups: [
                    BarGroup([Bar(2), Bar(8)]),
                  ],
                ),
              ),
              Skeleton(width: 4),
            ],
          ),
        ),
        size: (6, 3),
      );
      // no error box, no error in the log
      expect(
        t.binding.twkApp.logs.records.where((r) => r.error != null),
        isEmpty,
      );
      expect(t.lines.last.trim(), isNotEmpty);
    }
  });
}

class _Counting extends ListBase<String> {
  _Counting(this._items);
  final List<String> _items;
  var reads = 0;

  @override
  int get length => _items.length;

  @override
  set length(int value) => _items.length = value;

  @override
  String operator [](int index) {
    reads++;
    return _items[index];
  }

  @override
  void operator []=(int index, String value) => _items[index] = value;
}
