// Bars in eighths over one row and several, the window that slides over
// live data, the scale between min and max, braille where eighth blocks
// are two columns wide, and repainting nothing but the sparkline.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart'
    show Shot, hasBg, hasFg, styleAt, testTwk;

import '../layout/view.dart';
import 'shot.dart';

const red = Color.rgb(255, 0, 0);
const grey = Color.rgb(1, 2, 3);

/// [data] on a sparkline of [width] × [height] cells.
Shot spark(
  List<double> data,
  int width, {
  int height = 1,
  double min = 0,
  double? max,
  int ambiguousWidth = 1,
  bool fromRight = true,
}) {
  final shot = Shot.render(
    RenderSparkline(data: data, min: min, max: max, fromRight: fromRight),
    width,
    height,
    ambiguousWidth: ambiguousWidth,
  );
  expect(shot.vt.errors, isEmpty);
  return shot;
}

void main() {
  group('bars', () {
    test('grow in eighths up to the largest value', () {
      expect(spark([0, 1, 2, 3, 4, 5, 6, 7, 8], 9).rows, [' ▁▂▃▄▅▆▇█']);
    });

    test('grow over every row', () {
      expect(spark([0, 4, 8, 12, 16], 5, height: 2).rows, [
        '   ▄█',
        ' ▄███',
      ]);
    });

    test('take the nearest eighth', () {
      // 1/3, 1/2 and 15/16 of a cell
      expect(spark([1, 1.5, 2.8125, 3], 4, max: 3).rows, ['▃▄██']);
      expect(spark([1, 1.5, 2.8, 3], 4, max: 3).rows, ['▃▄▇█']);
    });

    test('are empty at min and full at max, beyond them too', () {
      expect(spark([10, 12, 14, 5, 20], 5, min: 10, max: 14).rows, [
        ' ▄█ █',
      ]);
    });

    test('are empty without a scale or a value', () {
      expect(spark([0, 0, 0], 3).rows, ['']);
      expect(spark([], 3).rows, ['']);
      expect(spark([5, double.nan, 5], 3).rows, ['█ █']);
      expect(spark([1, 2], 2, min: 3).rows, ['']);
    });

    test('are braille in quarters where eighth blocks are two columns', () {
      final shot = spark([0, 1, 2, 3, 4], 5, ambiguousWidth: 2);
      expect(shot.rows, [' ⣀⣤⣶⣿']);
      expect(shot.anyWide, isFalse);
      expect(spark([0, 1, 2, 3, 4], 5).rows, [' ▂▄▆█']);
    });

    test('in the style, over its background on every cell', () {
      final shot = Shot.render(
        RenderSparkline(
          data: const [2, 1],
          style: const Style(fg: red, bg: grey),
        ),
        3,
        1,
      );
      expect(shot.colors(0), [
        (' ', Color.defaultColor, grey),
        ('█', red, grey),
        ('▄', red, grey),
      ]);
    });
  });

  group('the window', () {
    test('shows the last values that fit, oldest to the left', () {
      expect(spark([8, 8, 1, 2, 3, 4], 4, max: 8).rows, ['▁▂▃▄']);
    });

    test('ends at the right edge with fewer values, or with fromRight '
        'false starts at the left one; the same either way once they fill '
        'it', () {
      expect(spark([1, 2], 4, max: 8).rows, ['  ▁▂']);
      expect(spark([1, 2], 4, max: 8, fromRight: false).rows, ['▁▂']);
      expect(spark([8, 8, 1, 2, 3, 4], 4, max: 8, fromRight: false).rows, [
        '▁▂▃▄',
      ]);
    });

    test('slides one column left for each new value', () {
      final data = <double>[1, 2, 3, 4];
      final sparkline = RenderSparkline(data: data, max: 8);
      final shot = Shot.render(sparkline, 3, 1);
      expect(shot.rows, ['▂▃▄']);
      sparkline.data = [...data, 5];
      shot.frame();
      expect(shot.rows, ['▃▄▅']);
      sparkline.data = [...sparkline.data, 8];
      shot.frame();
      expect(shot.rows, ['▄▅█']);
    });

    test('scales to the largest value it shows', () {
      expect(spark([16, 2, 4], 2).rows, ['▄█']);
    });
  });

  group('RenderSparkline', () {
    test('repaints when a property changes', () {
      final sparkline = RenderSparkline(data: const [1, 2], max: 2);
      final shot = Shot.render(sparkline, 2, 1);
      expect(shot.rows, ['▄█']);
      sparkline.max = 4;
      shot.frame();
      expect(shot.rows, ['▂▄']);
      sparkline.min = 1;
      shot.frame();
      expect(shot.rows, [' ▃']);
      sparkline.style = const Style(bg: grey);
      shot.frame();
      expect(shot.colors(0)[0], (' ', Color.defaultColor, grey));
    });

    test('is as wide as it may be and a row tall', () {
      final sparkline = RenderSparkline(data: const [])
        ..layout(const BoxConstraints(0, 5, 0, BoxConstraints.unbounded));
      expect((sparkline.width, sparkline.height), (5, 1));
      sparkline.layout(const BoxConstraints(2, BoxConstraints.unbounded, 0, 3));
      expect((sparkline.width, sparkline.height), (2, 1));
      sparkline.layout(const BoxConstraints(0, 5, 2, 4));
      expect((sparkline.width, sparkline.height), (5, 2));
    });
  });

  group('Sparkline', () {
    test('new data repaints the sparkline alone', () {
      final count = PaintCount();
      final v = View(4, 2)
        ..pump(
          Column(
            children: [
              Counted(count),
              const Sparkline(data: [1, 2, 3, 4]),
            ],
          ),
        );
      expect(v.rows(), ['', '▂▄▆█']);
      expect(count.paints, 1);
      v.pump(
        Column(
          children: [
            Counted(count),
            const Sparkline(data: [2, 3, 4, 8]),
          ],
        ),
      );
      expect(v.rows(), ['', '▂▃▄█']);
      expect(count.paints, 1);
    });

    test('rebuilt, configures the same render object', () {
      final v = View(2, 1)..pump(const Sparkline(data: [1, 2]));
      final sparkline = v.top;
      v.pump(
        const Sparkline(
          data: [1, 2],
          min: 1,
          style: Style(bg: grey),
        ),
      );
      expect(v.top, same(sparkline));
      expect(v.rows(), [' █']);
      v.pump(const Sparkline(data: [1, 2], min: 1, max: 3));
      expect(v.rows(), [' ▄']);
      sparkline as RenderSparkline;
      expect((sparkline.min, sparkline.max), (1, 3));
      expect(sparkline.style.bg, isNot(grey));
    });

    testTwk("in the theme's text where its style sets none, over what is "
        'under it, '
        'a new theme too', (t) async {
      Widget tree(ThemeData theme) => Theme(
        data: theme,
        child: const Row(
          children: [
            Expanded(child: Sparkline(data: [2, 1])),
            Expanded(
              child: Sparkline(
                data: [2, 1],
                style: Style(fg: red),
              ),
            ),
          ],
        ),
      );
      for (final theme in [ThemeData.light, ThemeData.dark]) {
        await t.pumpWidget(tree(theme), size: (6, 1));
        final text = theme.text.fg!;
        // over what is under it: nothing painted here, the terminal's own
        const background = Color.defaultColor;
        expect(t, styleAt(0, 0, hasBg(background)));
        expect(t, styleAt(1, 0, allOf(hasFg(text), hasBg(background))));
        expect(t, styleAt(4, 0, allOf(hasFg(red), hasBg(background))));
      }
    });

    testTwk('in the DefaultTextStyle where its style sets none, over the '
        "theme's", (t) async {
      const theme = ThemeData.light;
      await t.pumpWidget(
        const Theme(
          data: theme,
          child: DefaultTextStyle(
            style: Style(fg: grey, bg: red),
            child: Row(
              children: [
                Expanded(child: Sparkline(data: [2, 1])),
                Expanded(
                  child: Sparkline(
                    data: [2, 1],
                    style: Style(fg: red, bg: grey),
                  ),
                ),
              ],
            ),
          ),
        ),
        size: (6, 1),
      );
      expect(t, styleAt(0, 0, allOf(hasFg(grey), hasBg(red))));
      expect(t, styleAt(2, 0, hasBg(red)));
      expect(t, styleAt(3, 0, allOf(hasFg(red), hasBg(grey))));
    });
  });

  testTwk('in a dialog, a Sparkline and a BarChart over its color, also as '
      'their data change', (t) async {
    const panel = Color.rgb(0x22, 0x25, 0x2c);
    final data = ValueNotifier<List<double>>([1, 2, 3]);
    await t.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 12,
          height: 5,
          child: Box(
            style: const Style(bg: panel),
            child: ValueListenableBuilder<List<double>>(
              valueListenable: data,
              builder: (_, d, _) => Column(
                children: [
                  Sparkline(data: d),
                  SizedBox(
                    height: 4,
                    child: BarChart(
                      groups: [
                        BarGroup([
                          for (final (i, v) in d.indexed)
                            Bar(v, label: '$i', text: ''),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      size: (12, 5),
    );
    for (final step in [
      [1.0, 2.0, 3.0],
      [3.0, 1.0, 2.0],
      [2.0, 3.0, 1.0],
    ]) {
      data.value = step;
      await t.pump();
      for (final (x, y) in [(0, 0), (10, 0), (10, 2), (8, 4)]) {
        expect(t, styleAt(x, y, hasBg(panel)), reason: '$step at $x, $y');
      }
    }
  });
}
