// Datasets plotted against labelled axes: lines and scatters in layers,
// the axes' lines, ticks, labels and titles, labels worked out from the
// bounds or thinned out so that none touch at any width or height, the
// legend where it fits, ASCII where box drawing is two columns wide, what
// is given up where there is no room, and repainting nothing but the
// chart.
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

/// A line across the middle of 0 to 10 on both axes.
const middle = Dataset(data: [(0, 5), (10, 5)], type: GraphType.line);

/// [datasets] on a chart of [width] × [height] cells.
Shot plot(
  int width,
  int height, {
  List<Dataset> datasets = const [middle],
  ChartAxis x = const ChartAxis(bounds: (0, 10), labels: ['0', '5', '10']),
  ChartAxis y = const ChartAxis(bounds: (0, 10), labels: ['0', '10']),
  Marker marker = Marker.braille,
  LegendPosition? legend = LegendPosition.topRight,
  int ambiguousWidth = 1,
}) {
  final shot = Shot.render(
    RenderChart(
      datasets: datasets,
      xAxis: x,
      yAxis: y,
      marker: marker,
      legendPosition: legend,
    ),
    width,
    height,
    ambiguousWidth: ambiguousWidth,
  );
  expect(shot.vt.errors, isEmpty);
  expect(shot.anyWide, isFalse);
  return shot;
}

/// The words of [row], left to right: the labels on a row of them.
List<String> words(String row) =>
    row.trim().isEmpty ? const [] : row.trim().split(RegExp(' +'));

void main() {
  group('axes', () {
    test('labels at the cells of their values, a tick beside each', () {
      expect(plot(12, 6).rows, [
        '10┤',
        '  │',
        '  │⠉⠉⠉⠉⠉⠉⠉⠉⠉',
        ' 0┤',
        '  └┬───┬───┬',
        '   0   5  10',
      ]);
    });

    test('labels worked out from the bounds, a blank between', () {
      const auto = ChartAxis(bounds: (0, 10));
      expect(plot(20, 6, x: auto, y: auto).rows, [
        '10┤',
        '  │',
        '  │⠉⠉⠉⠉⠉⠉⠉⠉⠉⠉⠉⠉⠉⠉⠉⠉⠉',
        ' 0┤',
        '  └┬──┬──┬───┬──┬──┬',
        '   0  2  4   6  8 10',
      ]);
      expect(
        plot(
          30,
          8,
          datasets: const [],
          x: const ChartAxis(bounds: (-0.5, 0.5)),
          y: const ChartAxis(bounds: (-1, 1)),
        ).rows,
        [
          ' 1┤',
          '  │',
          '  │',
          ' 0┤',
          '  │',
          '-1┤',
          '  └──┬─────┬────┬────┬─────┬──',
          '    -0.4  -0.2 0.0  0.2   0.4',
        ],
      );
    });

    test('x labels worked out never touch, at any width', () {
      for (final bounds in const [(0.0, 1000.0), (-0.5, 0.5), (3.0, 17.0)]) {
        for (var width = 3; width <= 60; width++) {
          final shot = plot(
            width,
            3,
            datasets: const [],
            x: ChartAxis(bounds: bounds),
            y: const ChartAxis(bounds: (0, 1), labels: []),
          );
          final labels = words(shot.rows[2]);
          final values = labels.map(double.parse).toList();
          for (var i = 1; i < values.length; i++) {
            expect(values[i], greaterThan(values[i - 1]));
          }
          expect('┬'.allMatches(shot.rows[1]).length, labels.length);
          expect(labels, isNotEmpty, reason: '$bounds at $width');
          for (final v in values) {
            expect(v, inInclusiveRange(bounds.$1, bounds.$2));
          }
        }
      }
    });

    test('y labels worked out never touch, at any height', () {
      for (final bounds in const [(0.0, 1000.0), (-1.0, 1.0)]) {
        for (var height = 3; height <= 40; height++) {
          final shot = plot(
            8,
            height,
            datasets: const [],
            x: const ChartAxis(bounds: (0, 1), labels: []),
            y: ChartAxis(bounds: bounds),
          );
          final rows = <int>[];
          final values = <double>[];
          for (var y = 0; y < height - 1; y++) {
            final row = shot.rows[y];
            final axis = row.indexOf(RegExp('[┤│]'));
            final label = row.substring(0, axis).trim();
            expect(row[axis] == '┤', label.isNotEmpty);
            if (label.isNotEmpty) {
              rows.add(y);
              values.add(double.parse(label));
            }
          }
          expect(values, isNotEmpty);
          for (var i = 1; i < values.length; i++) {
            expect(values[i], lessThan(values[i - 1]));
            // a blank row between
            expect(rows[i] - rows[i - 1], greaterThan(1));
          }
        }
      }
    });

    test('its own labels thinned out where they would touch', () {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      Shot chart(int width) => plot(
        width,
        3,
        datasets: const [],
        x: const ChartAxis(bounds: (0, 11), labels: months),
        y: const ChartAxis(bounds: (0, 1), labels: []),
      );
      expect(chart(30).rows, [
        '│',
        '└┬────┬────┬────┬────┬─────┬──',
        'Jan  Mar  May  Jul  Sep   Nov',
      ]);
      for (var width = 4; width <= 60; width++) {
        final labels = words(chart(width).rows[2]);
        expect(labels, isNotEmpty);
        // every one, every second, third...
        final every = labels.length > 1
            ? months.indexOf(labels[1])
            : months.length;
        expect(labels, [
          for (var i = 0; i < months.length; i += every) months[i],
        ], reason: 'at $width');
      }
      // a row each
      final shot = plot(
        4,
        4,
        datasets: const [],
        x: const ChartAxis(bounds: (0, 1), labels: []),
        y: const ChartAxis(bounds: (0, 4), labels: ['0', '1', '2', '3', '4']),
      );
      expect(shot.rows, ['4┤', '2┤', '0┤', ' └──']);
    });

    test('titles at the top left and under the x labels at the right', () {
      expect(
        plot(
          12,
          8,
          x: const ChartAxis(
            bounds: (0, 10),
            labels: ['0', '5', '10'],
            title: 'x',
          ),
          y: const ChartAxis(bounds: (0, 10), labels: ['0', '10'], title: 'y'),
        ).rows,
        [
          'y',
          '10┤',
          '  │',
          '  │⠉⠉⠉⠉⠉⠉⠉⠉⠉',
          ' 0┤',
          '  └┬───┬───┬',
          '   0   5  10',
          '           x',
        ],
      );
    });

    test('given up where there is no room, the plot keeping a cell', () {
      const x = ChartAxis(bounds: (0, 10), labels: ['0', '10'], title: 'x');
      const y = ChartAxis(bounds: (0, 10), labels: ['0'], title: 'y');
      List<String> rows(int width, int height) =>
          plot(width, height, datasets: const [], x: x, y: y).rows;
      expect(rows(6, 5), ['y', '0┤', ' └┬──┬', '  0 10', '     x']);
      expect(rows(6, 4), ['0┤', ' └┬──┬', '  0 10', '     x']);
      expect(rows(6, 3), ['0┤', ' └┬──┬', '  0 10']);
      expect(rows(6, 2), ['0┤', ' └────']);
      expect(rows(6, 1), ['0┤']);
      expect(rows(3, 1), ['0┤']);
      // the y labels, then its line
      expect(rows(2, 1), ['│']);
      expect(rows(1, 1), ['']);
      expect(rows(0, 0), <String>[]);
    });

    test('labels and plot left out where the bounds enclose nothing', () {
      const empty = ChartAxis(bounds: (5, 5));
      // the line across the middle
      expect(plot(4, 3, x: empty, y: empty).rows, ['│', '└───', '']);
    });

    test('ASCII where box drawing is two columns wide', () {
      final shot = plot(
        12,
        8,
        datasets: const [
          Dataset(data: [(0, 5), (10, 5)], name: 'a'),
        ],
        ambiguousWidth: 2,
      );
      expect(shot.rows, [
        '10+      +-+',
        '  |      |a|',
        '  |      +-+',
        '  |⠁       ⠈',
        '  |',
        ' 0+',
        '  ++---+---+',
        '   0   5  10',
      ]);
    });

    test('in their styles, over the chart style', () {
      final shot = Shot.render(
        RenderChart(
          datasets: const [],
          xAxis: const ChartAxis(
            bounds: (0, 1),
            labels: ['a'],
            style: Style(fg: red),
          ),
          yAxis: const ChartAxis(
            bounds: (0, 1),
            labels: ['b'],
            style: Style(fg: green),
          ),
          style: const Style(bg: grey),
        ),
        3,
        3,
      );
      expect(shot.colors(0), [
        ('b', green, grey),
        ('┤', green, grey),
        (' ', none, grey),
      ]);
      expect(shot.colors(1).skip(1), [('└', red, grey), ('┬', red, grey)]);
      expect(shot.colors(2)[2], ('a', red, grey));
    });
  });

  group('datasets', () {
    test('each covers those before it cell by cell, in its color', () {
      final shot = plot(
        12,
        6,
        datasets: const [
          Dataset(data: [(0, 0), (10, 0)], type: GraphType.line, color: red),
          Dataset(data: [(0, 0), (10, 10)], color: green),
        ],
      );
      expect(shot.rows, [
        '10┤        ⠈',
        '  │',
        '  │',
        ' 0┤⡀⣀⣀⣀⣀⣀⣀⣀⣀',
        '  └┬───┬───┬',
        '   0   5  10',
      ]);
      expect(
        [for (final c in shot.colors(3).skip(3)) c.$2],
        [
          green,
          for (var i = 0; i < 8; i++) red,
        ],
      );
      expect(shot.colors(0)[11].$2, green);
    });

    test('with the marker', () {
      expect(plot(12, 6, marker: Marker.halfBlock).rows[2], '  │▀▀▀▀▀▀▀▀▀');
      expect(plot(12, 6, marker: Marker.dot).rows[2], '  │•••••••••');
    });
  });

  group('the legend', () {
    const named = [
      Dataset(data: [], name: 'ab', color: red),
      Dataset(data: [], name: 'c', color: green),
      Dataset(data: []),
    ];
    const bare = ChartAxis(bounds: (0, 10), labels: []);

    /// The legend of [named] at [position] in a plot of [size] × [size].
    List<String> at(LegendPosition position, [int size = 8]) => plot(
      size + 1,
      size + 1,
      datasets: named,
      x: bare,
      y: bare,
      legend: position,
    ).rows;

    test('lists the datasets with a name in a box, in their colors', () {
      final shot = plot(9, 9, datasets: named, x: bare, y: bare);
      expect(shot.rows.take(4), [
        '│    ┌──┐',
        '│    │ab│',
        '│    │c │',
        '│    └──┘',
      ]);
      expect(shot.colors(1)[6], ('a', red, none));
      expect(shot.colors(2)[6], ('c', green, none));
    });

    test('at its position in the plot', () {
      expect(at(LegendPosition.topLeft).take(2), ['│┌──┐', '││ab│']);
      expect(at(LegendPosition.top).take(2), ['│  ┌──┐', '│  │ab│']);
      expect(at(LegendPosition.left).skip(2).take(2), ['│┌──┐', '││ab│']);
      expect(at(LegendPosition.right).skip(2).take(2), [
        '│    ┌──┐',
        '│    │ab│',
      ]);
      expect(at(LegendPosition.bottomLeft).skip(4).take(4), [
        '│┌──┐',
        '││ab│',
        '││c │',
        '│└──┘',
      ]);
      expect(at(LegendPosition.bottom).skip(7).take(2), [
        '│  └──┘',
        '└────────',
      ]);
      expect(at(LegendPosition.bottomRight).skip(7).first, '│    └──┘');
    });

    test('left out where it takes more than half the plot', () {
      expect(at(LegendPosition.topLeft, 7).first, '│');
      expect(
        plot(9, 9, datasets: named, x: bare, y: bare, legend: null).rows.first,
        '│',
      );
      expect(plot(9, 9, datasets: const [], x: bare, y: bare).rows.first, '│');
    });
  });

  group('RenderChart', () {
    test('repaints when a property changes', () {
      final chart = RenderChart(
        datasets: const [],
        xAxis: const ChartAxis(bounds: (0, 1), labels: []),
        yAxis: const ChartAxis(bounds: (0, 1), labels: []),
      );
      final shot = Shot.render(chart, 4, 3);
      expect(shot.rows, ['│', '│', '└───']);
      chart.datasets = const [
        Dataset(data: [(0, 1), (1, 1)], type: GraphType.line, name: 'a'),
      ];
      shot.frame();
      expect(shot.rows, ['│⠉⠉⠉', '│', '└───']);
      chart.marker = Marker.halfBlock;
      shot.frame();
      expect(shot.rows, ['│▀▀▀', '│', '└───']);
      chart.yAxis = const ChartAxis(bounds: (0, 2), labels: []);
      shot.frame();
      expect(shot.rows, ['│', '│▀▀▀', '└───']);
      chart.yAxis = const ChartAxis(bounds: (0, 1.5), labels: []);
      shot.frame();
      expect(shot.rows, ['│▄▄▄', '│', '└───']);
      chart.xAxis = const ChartAxis(bounds: (0, 2), labels: [], title: 'x');
      shot.frame();
      expect(shot.rows, ['│▀▀', '└───', '   x']);
      chart.style = const Style(bg: grey);
      shot.frame();
      expect(shot.colors(0)[3], (' ', none, grey));
    });

    test('repaints when the legend moves', () {
      const axis = ChartAxis(bounds: (0, 1), labels: []);
      final chart = RenderChart(
        datasets: const [Dataset(data: [], name: 'a')],
        xAxis: axis,
        yAxis: axis,
        legendPosition: null,
      );
      final shot = Shot.render(chart, 7, 7);
      expect(shot.rows.first, '│');
      chart.legendPosition = LegendPosition.topLeft;
      shot.frame();
      expect(shot.rows.first, '│┌─┐');
    });

    test('is as big as the constraints allow', () {
      final chart = RenderChart(
        datasets: const [],
        xAxis: const ChartAxis(bounds: (0, 1)),
        yAxis: const ChartAxis(bounds: (0, 1)),
      )..layout(const BoxConstraints(0, 5, 2, BoxConstraints.unbounded));
      expect((chart.width, chart.height), (5, 2));
    });
  });

  group('Chart', () {
    test('new data repaints the chart alone', () {
      final count = PaintCount();
      Widget tree(double y) => Column(
        children: [
          Counted(count),
          Expanded(
            child: Chart(
              datasets: [
                Dataset(data: [(0, y), (1, y)], type: GraphType.line),
              ],
              xAxis: const ChartAxis(bounds: (0, 1), labels: []),
              yAxis: const ChartAxis(bounds: (0, 1), labels: []),
            ),
          ),
        ],
      );
      final v = View(4, 3)..pump(tree(0));
      expect(v.rows(), ['', '│⣀⣀⣀', '└───']);
      v.pump(tree(1));
      expect(v.rows(), ['', '│⠉⠉⠉', '└───']);
      expect(count.paints, 1);
    });

    test('rebuilt, configures the same render object', () {
      const axis = ChartAxis(bounds: (0, 1), labels: []);
      final v = View(4, 2)
        ..pump(const Chart(datasets: [], xAxis: axis, yAxis: axis));
      final chart = v.top;
      v.pump(
        const Chart(
          datasets: [middle],
          xAxis: ChartAxis(bounds: (0, 10), labels: []),
          yAxis: ChartAxis(bounds: (0, 10), labels: []),
          marker: Marker.halfBlock,
          legendPosition: null,
          style: Style(bg: grey),
        ),
      );
      expect(v.top, same(chart));
      expect(v.rows(), ['│▄▄▄', '└───']);
      chart as RenderChart;
      expect(chart.datasets, [middle]);
      expect(chart.xAxis, const ChartAxis(bounds: (0, 10), labels: []));
      expect(chart.yAxis.bounds, (0, 10));
      expect(chart.marker, Marker.halfBlock);
      expect(chart.legendPosition, isNull);
      expect(chart.style.bg, grey);
    });

    testTwk("in the theme's background and text where its style sets none", (
      t,
    ) async {
      const theme = ThemeData.light;
      await t.pumpWidget(
        const Theme(
          data: theme,
          child: Chart(
            datasets: [
              Dataset(
                data: [(0, 5), (10, 5)],
                type: GraphType.line,
                color: red,
              ),
            ],
            xAxis: ChartAxis(bounds: (0, 10), labels: []),
            yAxis: ChartAxis(bounds: (0, 10), labels: []),
            marker: Marker.halfBlock,
          ),
        ),
        size: (4, 3),
      );
      expect(t.lines, ['│', '│▀▀▀', '└───']);
      final text = theme.text.fg!;
      final background = theme.background.bg!;
      expect(t, styleAt(0, 0, allOf(hasFg(text), hasBg(background))));
      expect(t, styleAt(1, 2, allOf(hasFg(text), hasBg(background))));
      expect(t, styleAt(1, 1, allOf(hasFg(red), hasBg(background))));
      expect(t, styleAt(3, 0, hasBg(background)));
    });
  });

  group('ChartAxis', () {
    test('axes with equal labels in other lists are equal, and hash the '
        'same', () {
      ChartAxis axis(List<String>? labels) =>
          ChartAxis(bounds: (0, 1), title: 't', labels: labels);
      expect(axis(['0', '1']), axis(['0', '1']));
      expect(axis(['0', '1']).hashCode, axis(['0', '1']).hashCode);
      expect(axis(null), axis(null));
      expect(axis(null).hashCode, axis(null).hashCode);
      expect(axis(['0', '1']), isNot(axis(['0', '2'])));
      expect(axis([]), isNot(axis(null)));
      expect(axis(null), isNot(axis([])));
    });
  });

  group('Dataset', () {
    test('datasets of equal points in other lists are equal, and hash the '
        'same', () {
      Dataset of(List<(double, double)> data) =>
          Dataset(data: data, name: 'a', type: GraphType.line);
      expect(of([(0, 1), (2, 3)]), of([(0, 1), (2, 3)]));
      expect(of([(0, 1)]).hashCode, of([(0, 1)]).hashCode);
      expect(of([(0, 1)]), isNot(of([(0, 2)])));
    });
  });
}
