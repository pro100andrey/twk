// Under Glyphs.ascii (no partial blocks) the charts draw ASCII only: bars
// in the ramp of Glyphs.shades, a gauge and a progress bar full of its last
// shade, the dots of a canvas as the shade as dense as their number.
// Glyphs.unicode draws as it always did.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

Widget themed(Glyphs glyphs, Widget child) => Theme(
  data: ThemeData.dark.copyWith(glyphs: glyphs),
  child: child,
);

bool isAscii(List<String> lines) =>
    lines.every((l) => l.runes.every((r) => r < 0x80));

void main() {
  const data = <double>[0, 1, 2, 3, 4, 5, 6, 7, 8];

  group('Sparkline', () {
    Widget spark(Glyphs g) =>
        themed(g, const SizedBox(width: 9, child: Sparkline(data: data)));

    testTwk('Glyphs.unicode: eighths', (t) async {
      await t.pumpWidget(spark(Glyphs.unicode), size: (9, 1));
      expect(t.lines, [' ▁▂▃▄▅▆▇█']);
    });

    testTwk('Glyphs.ascii: the ramp, a step a shade', (t) async {
      await t.pumpWidget(spark(Glyphs.ascii), size: (9, 1));
      expect(t.lines, [' ..::++##']);
    });

    testTwk('a ramp of the theme\'s own', (t) async {
      await t.pumpWidget(
        spark(Glyphs.ascii.copyWith(shades: [' ', '-', '=', '#'])),
        size: (9, 1),
      );
      expect(t.lines, ['  --===##']);
    });
  });

  group('BarChart', () {
    Widget bars(Glyphs g, Axis direction) => themed(
      g,
      SizedBox(
        width: 9,
        height: 2,
        child: BarChart(
          direction: direction,
          barGap: 0,
          groups: const [
            BarGroup([Bar(2), Bar(4), Bar(8)]),
          ],
        ),
      ),
    );

    testTwk('up, Glyphs.ascii: the ramp', (t) async {
      await t.pumpWidget(bars(Glyphs.ascii, Axis.vertical), size: (9, 2));
      expect(isAscii(t.lines), isTrue, reason: '${t.lines}');
      expect(t.lines, ['2 #', ':48']);
    });

    testTwk('across, Glyphs.ascii: the ramp', (t) async {
      await t.pumpWidget(bars(Glyphs.ascii, Axis.horizontal), size: (9, 2));
      expect(t.lines, ['2#.', '4###:']);
      expect(isAscii(t.lines), isTrue, reason: '${t.lines}');
    });

    testTwk('Glyphs.unicode keeps the blocks', (t) async {
      await t.pumpWidget(bars(Glyphs.unicode, Axis.vertical), size: (9, 2));
      expect(isAscii(t.lines), isFalse);
    });
  });

  group('Gauge and ProgressBar', () {
    testTwk('Gauge: filled cells are the last shade', (t) async {
      for (final (g, filled) in [(Glyphs.unicode, '█'), (Glyphs.ascii, '#')]) {
        await t.pumpWidget(
          themed(g, const SizedBox(width: 10, child: Gauge(ratio: 0.5))),
          size: (10, 1),
        );
        expect(t.lines, [filled * 5]);
      }
    });

    testTwk('ProgressBar: filled cells are the last shade', (t) async {
      for (final (g, filled) in [(Glyphs.unicode, '█'), (Glyphs.ascii, '#')]) {
        await t.pumpWidget(
          themed(g, const SizedBox(width: 10, child: ProgressBar(value: 0.5))),
          size: (10, 1),
        );
        expect(t.lines[0].startsWith(filled * 5), isTrue, reason: '${t.lines}');
      }
    });

    testTwk('a part of a cell is a shade between', (t) async {
      await t.pumpWidget(
        themed(
          Glyphs.ascii,
          const SizedBox(width: 10, child: Gauge(ratio: 0.55)),
        ),
        size: (10, 1),
      );
      expect(isAscii(t.lines), isTrue);
      expect(t.lines, ['#####:']);
    });
  });

  group('DotCanvas', () {
    void line(DotContext c) => c.draw(const .line(0, 0, 15, 7));

    Widget canvas(Glyphs g, [Marker marker = Marker.braille]) => themed(
      g,
      SizedBox(
        width: 8,
        height: 2,
        child: DotCanvas(
          draw: line,
          xBounds: const (0, 15),
          yBounds: const (0, 7),
          marker: marker,
        ),
      ),
    );

    testTwk('Glyphs.ascii: shades, none outside ASCII', (t) async {
      await t.pumpWidget(canvas(Glyphs.ascii), size: (8, 2));
      expect(isAscii(t.lines), isTrue, reason: '${t.lines}');
      expect(t.lines, ['    ....', '....']);
    });

    testTwk('every marker but a custom one', (t) async {
      for (final m in [
        Marker.braille,
        Marker.dot,
        Marker.block,
        Marker.bar,
        Marker.halfBlock,
        Marker.quadrant,
      ]) {
        await t.pumpWidget(canvas(Glyphs.ascii, m), size: (8, 2));
        expect(isAscii(t.lines), isTrue, reason: '$m: ${t.lines}');
        expect(t.lines.join().trim(), isNotEmpty, reason: '$m');
      }
      await t.pumpWidget(
        canvas(Glyphs.ascii, Marker.custom('*')),
        size: (8, 2),
      );
      expect(t.lines.join().contains('*'), isTrue);
    });

    testTwk('Glyphs.unicode draws braille', (t) async {
      await t.pumpWidget(canvas(Glyphs.unicode), size: (8, 2));
      expect(isAscii(t.lines), isFalse);
    });
  });

  group('Chart', () {
    testTwk('Glyphs.ascii draws no braille', (t) async {
      await t.pumpWidget(
        themed(
          Glyphs.ascii,
          SizedBox(
            width: 30,
            height: 8,
            child: Chart(
              datasets: [
                Dataset(
                  name: 'y',
                  data: [for (var i = 0; i < 10; i++) (i.toDouble(), i * 2.0)],
                ),
              ],
              xAxis: const ChartAxis(bounds: (0, 9)),
              yAxis: const ChartAxis(bounds: (0, 18)),
            ),
          ),
        ),
        size: (30, 8),
      );
      expect(isAscii(t.lines), isTrue, reason: '${t.lines}');
    });
  });
}
