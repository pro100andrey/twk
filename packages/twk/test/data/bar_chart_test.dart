// Bars up and across in eighths, in groups with gaps, their labels and
// their groups', values inside the bar or past its end, labels given up
// where there is no room, braille where eighth blocks are two columns
// wide, and repainting nothing but the chart.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart'
    show Shot, hasBg, hasFg, styleAt, testTwk;

import '../layout/view.dart';
import 'shot.dart';

const red = Color.rgb(255, 0, 0);
const green = Color.rgb(0, 255, 0);
const grey = Color.rgb(1, 2, 3);
const Color none = Color.defaultColor;

/// [chart] shown on [width] × [height] cells.
Shot show(
  RenderBarChart chart,
  int width,
  int height, {
  int ambiguousWidth = 1,
}) {
  final shot = Shot.render(
    chart,
    width,
    height,
    ambiguousWidth: ambiguousWidth,
  );
  expect(shot.vt.errors, isEmpty);
  expect(shot.anyWide, isFalse);
  return shot;
}

/// One group of bars of [values], shown as no text.
List<BarGroup> plain(List<double> values) => [
  BarGroup([for (final v in values) Bar(v, text: '')]),
];

void main() {
  group('up', () {
    test('bars grow in eighths up to the largest value', () {
      final chart = RenderBarChart(
        groups: plain([0, 1, 2, 3, 4, 5, 6, 7, 8]),
        barGap: 0,
      );
      expect(show(chart, 9, 1).rows, [' ▁▂▃▄▅▆▇█']);
    });

    test('values inside the bars that fill their row, over the others', () {
      final shot = show(
        RenderBarChart(
          groups: const [
            BarGroup([
              Bar(1, label: 'a'),
              Bar(2, label: 'b'),
              Bar(4, label: 'c'),
              Bar(8, label: 'd'),
            ]),
          ],
        ),
        7,
        3,
      );
      expect(shot.rows, ['1 2   █', '▂ ▄ 4 8', 'a b c d']);
      const r = Attr.reverse;
      expect(shot.attrs(1), [0, 0, 0, 0, r, 0, r]);
      expect(shot.attrs(0), [0, 0, 0, 0, 0, 0, 0]);
    });

    test('groups apart, their labels under those of the bars', () {
      const groups = [
        BarGroup([
          Bar(4, label: 'a', text: ''),
          Bar(8, label: 'b', text: ''),
        ], label: 'g1'),
        BarGroup([
          Bar(2, label: 'c', text: ''),
          Bar(6, label: 'd', text: ''),
        ], label: 'g2'),
      ];
      RenderBarChart chart() =>
          RenderBarChart(groups: groups, barGap: 0, groupGap: 2);
      expect(show(chart(), 6, 3).rows, ['▄█  ▂▆', 'ab  cd', 'g1  g2']);
      // no room: the groups' labels go first, then the bars'
      expect(show(chart(), 6, 2).rows, ['▄█  ▂▆', 'ab  cd']);
      expect(show(chart(), 6, 1).rows, ['▄█  ▂▆']);
    });

    test('wide bars center their values and labels, cut them off', () {
      final chart = RenderBarChart(
        groups: const [
          BarGroup([
            Bar(8, label: 'abcd'),
            Bar(4, label: 'a'),
          ]),
          BarGroup([Bar(8, text: '1000'), Bar(8)], label: 'group'),
        ],
        barWidth: 3,
      );
      expect(show(chart, 15, 3).rows, [
        '█8█ ▄▄▄███ █8█',
        'abc  a',
        '        group',
      ]);
    });

    test('a bar is as tall as the chart at max, and beyond it', () {
      RenderBarChart chart(double? max) =>
          RenderBarChart(groups: plain([4, 16]), max: max);
      expect(show(chart(8), 3, 1).rows, ['▄ █']);
      expect(show(chart(null), 3, 1).rows, ['▂ █']);
      expect(show(chart(0), 3, 1).rows, ['']);
    });

    test('in braille quarters where eighth blocks are two columns', () {
      final chart = RenderBarChart(groups: plain([0, 1, 2, 3, 4]), barGap: 0);
      expect(show(chart, 5, 1, ambiguousWidth: 2).rows, [' ⣀⣤⣶⣿']);
    });

    test('in their styles', () {
      final shot = show(
        RenderBarChart(
          groups: const [
            BarGroup([
              Bar(8, label: 'a'),
              Bar(
                8,
                label: 'b',
                style: Style(fg: green),
              ),
            ]),
          ],
          style: const Style(bg: grey),
          barStyle: const Style(fg: red),
          valueStyle: const Style(attrs: Attr.bold),
          labelStyle: const Style(fg: green),
        ),
        3,
        3,
      );
      // the text color of a blank is the presenter's to choose
      Iterable<(String, Color, Color)> bars(int y) =>
          shot.colors(y).where((c) => c.$1 != ' ');
      expect(bars(0), [('█', red, grey), ('█', green, grey)]);
      expect(bars(1), [('8', red, grey), ('8', green, grey)]);
      expect(shot.colors(1)[1].$3, grey);
      expect(shot.attrs(1), [
        Attr.bold | Attr.reverse,
        0,
        Attr.bold | Attr.reverse,
      ]);
      expect(shot.colors(2)[0], ('a', green, grey));
    });
  });

  group('across', () {
    RenderBarChart across(
      List<BarGroup> groups, {
      int barWidth = 1,
      int barGap = 1,
      int groupGap = 0,
    }) => RenderBarChart(
      groups: groups,
      direction: Axis.horizontal,
      barWidth: barWidth,
      barGap: barGap,
      groupGap: groupGap,
    );

    test('bars grow in eighths after their labels, values inside', () {
      final chart = across(const [
        BarGroup([
          Bar(4, label: 'a'),
          Bar(8, label: 'bb'),
        ]),
      ]);
      final shot = show(chart, 8, 3);
      expect(shot.rows, ['a  4█▌', '', 'bb 8████']);
      expect(shot.attrs(0)[3], Attr.reverse);
    });

    test('a value past the end of a bar too short for it', () {
      final chart = across(const [
        BarGroup([
          Bar(1, label: 'a'),
          Bar(8, label: 'b'),
        ]),
      ]);
      final shot = show(chart, 8, 3);
      expect(shot.rows, ['a ▊1', '', 'b 8█████']);
      expect(shot.attrs(0)[3], 0);
    });

    test('wide bars, the label and the value on the middle row', () {
      final chart = across(const [
        BarGroup([Bar(8, label: 'a')]),
      ], barWidth: 2);
      expect(show(chart, 5, 2).rows, ['  ███', 'a 8██']);
    });

    test('groups apart, their labels on the row after them', () {
      const groups = [
        BarGroup([Bar(8, text: '')], label: 'g1'),
        BarGroup([Bar(4, text: '')], label: 'g2'),
      ];
      expect(show(across(groups, groupGap: 1), 4, 4).rows, [
        '████',
        'g1',
        '██',
        'g2',
      ]);
      // no gap, no room for them
      expect(show(across(groups), 4, 2).rows, ['████', '██']);
    });

    test('labels given up where they leave no cell for the bars', () {
      final chart = across(const [
        BarGroup([Bar(8, label: 'abc', text: '')]),
      ]);
      expect(show(chart, 3, 1).rows, ['███']);
      expect(show(chart, 5, 1).rows, ['abc █']);
    });

    test('in braille halves where eighth blocks are two columns', () {
      final chart = RenderBarChart(
        groups: plain([1, 4]),
        direction: Axis.horizontal,
        barGap: 0,
      );
      expect(show(chart, 2, 2, ambiguousWidth: 2).rows, ['⡇', '⣿⣿']);
    });
  });

  group('RenderBarChart', () {
    test('repaints when a property changes', () {
      final chart = RenderBarChart(groups: plain([4, 8]));
      final shot = show(chart, 3, 2);
      expect(shot.rows, ['  █', '█ █']);
      chart.groups = plain([8, 4]);
      shot.frame();
      expect(shot.rows, ['█', '█ █']);
      chart.max = 16;
      shot.frame();
      expect(shot.rows, ['', '█ ▄']);
      chart.barGap = 0;
      shot.frame();
      expect(shot.rows, ['', '█▄']);
      chart.barWidth = 2;
      shot.frame();
      expect(shot.rows, ['', '██▄']);
      chart.direction = Axis.horizontal;
      shot.frame();
      expect(shot.rows, ['█▌', '█▌']);
      chart
        ..groups = [
          const BarGroup([Bar(8, text: '')], label: 'g'),
          ...plain([8]),
        ]
        ..barWidth = 1
        ..groupGap = 1;
      shot.frame();
      expect(shot.rows, ['█▌', 'g']);
      chart.style = const Style(bg: grey);
      shot.frame();
      expect(shot.colors(1)[1], (' ', none, grey));
      chart.barStyle = const Style(fg: red);
      shot.frame();
      expect(shot.colors(0)[0].$2, red);
      chart.labelStyle = const Style(fg: green);
      shot.frame();
      expect(shot.colors(1)[0], ('g', green, grey));
      chart
        ..groups = [
          const BarGroup([Bar(8)]),
        ]
        ..valueStyle = const Style(attrs: Attr.bold);
      shot.frame();
      expect(shot.attrs(0)[0], Attr.bold | Attr.reverse);
    });

    test('is as big as the constraints allow', () {
      final chart = RenderBarChart(groups: const [])
        ..layout(const BoxConstraints(0, 5, 2, BoxConstraints.unbounded));
      expect((chart.width, chart.height), (5, 2));
    });
  });

  group('BarChart', () {
    test('new values repaint the chart alone', () {
      final count = PaintCount();
      Widget tree(double value) => Column(
        children: [
          Counted(count),
          Expanded(
            child: BarChart(
              groups: [
                BarGroup([Bar(value, text: ''), const Bar(8, text: '')]),
              ],
            ),
          ),
        ],
      );
      final v = View(3, 2)..pump(tree(4));
      expect(v.rows(), ['', '▄ █']);
      v.pump(tree(2));
      expect(v.rows(), ['', '▂ █']);
      expect(count.paints, 1);
    });

    test('rebuilt, configures the same render object', () {
      final v = View(3, 1)..pump(BarChart(groups: plain([4, 8])));
      final chart = v.top;
      v.pump(BarChart(groups: plain([4, 8]), barGap: 0, max: 16));
      expect(v.top, same(chart));
      expect(v.rows(), ['▂▄']);
      final groups = plain([1]);
      v.pump(
        BarChart(
          groups: groups,
          direction: Axis.horizontal,
          barWidth: 2,
          barGap: 3,
          groupGap: 4,
          style: const Style(bg: grey),
          barStyle: const Style(fg: red),
          valueStyle: const Style(fg: green),
          labelStyle: const Style(attrs: Attr.bold),
        ),
      );
      chart as RenderBarChart;
      expect(chart.groups, same(groups));
      expect(chart.direction, Axis.horizontal);
      expect((chart.barWidth, chart.barGap, chart.groupGap), (2, 3, 4));
      expect(chart.max, isNull);
      expect(chart.style.bg, grey);
      expect(chart.barStyle, const Style(fg: red));
      expect(chart.valueStyle, const Style(fg: green));
      expect(chart.labelStyle, const Style(attrs: Attr.bold));
    });

    testTwk("in the theme's text where its styles set none, over what is "
        'under it', (
      t,
    ) async {
      const theme = ThemeData.light;
      await t.pumpWidget(
        const Theme(
          data: theme,
          child: BarChart(
            groups: [
              BarGroup([
                Bar(2, label: 'a', text: ''),
                Bar(
                  1,
                  label: 'b',
                  text: '',
                  style: Style(fg: red),
                ),
              ]),
            ],
          ),
        ),
        size: (4, 3),
      );
      expect(t.lines, ['█', '█ █', 'a b']);
      final text = theme.text.fg!;
      // over what is under it: nothing painted here, the terminal's own
      const background = Color.defaultColor;
      expect(t, styleAt(0, 1, allOf(hasFg(text), hasBg(background))));
      expect(t, styleAt(2, 1, allOf(hasFg(red), hasBg(background))));
      expect(t, styleAt(0, 2, allOf(hasFg(text), hasBg(background))));
      expect(t, styleAt(3, 0, hasBg(background)));
    });
  });

  group('Bar and BarGroup', () {
    test('bars of equal values are equal and hash the same, those that are '
        'not a number too', () {
      Bar bar(double value) => Bar(value, label: 'a');
      expect(bar(2), bar(2));
      expect(bar(2).hashCode, bar(2).hashCode);
      expect(bar(double.nan), bar(double.nan));
      expect(bar(double.nan).hashCode, bar(double.nan).hashCode);
      expect(bar(2), isNot(bar(3)));
    });

    test('groups of equal bars in other lists are equal, and hash the '
        'same', () {
      BarGroup group(double value) => BarGroup([Bar(value)], label: 'g');
      expect(group(1), group(1));
      expect(group(1).hashCode, group(1).hashCode);
      expect(group(1), isNot(group(2)));
    });
  });

  group('values', () {
    test('whole numbers without decimals, others with at most two, '
        'infinity as a word', () {
      String value(double v) => show(
        RenderBarChart(
          groups: [
            BarGroup([Bar(v)]),
          ],
          direction: Axis.horizontal,
          max: 100,
        ),
        8,
        1,
      ).rows.single.trim();
      expect(value(3), '▎3');
      expect(value(2.5), '▎2.5');
      expect(value(1.257), '▏1.26');
      expect(value(0.001), '0');
      expect(value(-0.001), '0');
      expect(value(double.infinity), 'Infinity');
    });
  });
}
