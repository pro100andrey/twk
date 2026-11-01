// A theme's Glyphs.shades of one entry, or none (the const constructor
// cannot check a list's length): a Heatmap and an ActivityHeatmap draw with
// it, through rampOf, rather than throw.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  const one = Glyphs(shades: ['#'], partialBlocks: false);
  const none = Glyphs(shades: [], partialBlocks: false);

  for (final (name, glyphs) in [('one shade', one), ('no shade', none)]) {
    testTwk('a Heatmap and an ActivityHeatmap with $name', (t) async {
      await t.pumpWidget(
        Theme(
          data: ThemeData.dark.copyWith(glyphs: glyphs),
          child: Column(
            children: [
              Heatmap(
                rows: 2,
                columns: 2,
                value: (r, c) => (r * 2 + c).toDouble(),
                showLegend: true,
              ),
              ActivityHeatmap(
                counts: {DateTime(2026, 10, 21): 3},
                end: DateTime(2026, 10, 25),
                weeks: 3,
                showLegend: true,
              ),
            ],
          ),
        ),
        size: (40, 14),
      );
      // no error box, no error in the log
      expect(
        t.binding.twkApp.logs.records.where((r) => r.error != null),
        isEmpty,
      );
      expect(
        t.lines.where((l) => l.trim().isNotEmpty),
        hasLength(greaterThan(5)),
      );
    });
  }
}
