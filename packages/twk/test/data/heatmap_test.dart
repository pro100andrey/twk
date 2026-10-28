// Heatmaps: values on the shades between min and max, null cells blank,
// cells of a width, glyphs two columns wide, row and column labels, the
// legend; colors on an RGB terminal and shades elsewhere; the keys, the
// mouse and the tooltips; read as a table. ActivityHeatmap: weeks as
// columns up to the end, months over their first week, every other
// weekday labelled, the days after the end blank, its tooltips and the
// day selected.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ms = Duration(milliseconds: 1);
const black = Color.rgb(0, 0, 0);
const green = Color.rgb(0, 200, 0);

/// [values], a list a row, on a heatmap of [width] × [height] cells.
Shot heat(
  List<List<double?>> values,
  int width,
  int height, {
  double? min,
  double? max,
  HeatmapScale scale = const HeatmapScale.shades(),
  int cellWidth = 1,
  List<String>? rowLabels,
  List<String>? columnLabels,
  bool showLegend = false,
  int ambiguousWidth = 1,
  (int, int)? cursor,
}) {
  final shot = Shot.render(
    RenderHeatmap(
      rows: values.length,
      columns: values.isEmpty ? 0 : values[0].length,
      value: (row, column) => values[row][column],
      min: min,
      max: max,
      scale: scale,
      cellWidth: cellWidth,
      rowLabels: rowLabels,
      columnLabels: columnLabels,
      showLegend: showLegend,
      cursor: cursor,
    ),
    width,
    height,
    ambiguousWidth: ambiguousWidth,
  );
  expect(shot.vt.errors, isEmpty);
  return shot;
}

/// Moves the clock on past a tooltip's fade, then by a frame.
Future<void> settle(TwkTester t) async {
  await t.pump(ms * 200);
  await t.pump();
}

void main() {
  group('the scale', () {
    test('a value takes the shade of its share of the way from min to max, '
        'the blank at min alone', () {
      expect(
        heat(
          [
            [0, 1, 2, 3, 4],
          ],
          5,
          1,
        ).rows,
        [' ░▒▓█'],
      );
      // above min, the second shade at least; a share rounded up
      expect(
        heat(
          [
            [0, 0.1, 1.1, 2.5, 3.9, 4],
          ],
          6,
          1,
        ).rows,
        [' ░▒▓██'],
      );
    });

    test('min and max default to the smallest and the largest value; '
        'those beyond them as they are', () {
      expect(
        heat(
          [
            [10, 15, 20],
          ],
          3,
          1,
        ).rows,
        [' ▒█'],
      );
      expect(
        heat(
          [
            [0, 5, 10, 15, 20],
          ],
          5,
          1,
          min: 5,
          max: 15,
        ).rows,
        ['  ▒██'],
      );
      // all alike: all at min
      expect(
        heat(
          [
            [3, 3],
          ],
          2,
          1,
          max: 3,
        ).rows,
        [''],
      );
    });

    test('glyphs of its own', () {
      expect(
        heat(
          [
            [0, 1, 2],
          ],
          3,
          1,
          scale: const HeatmapScale.shades(['.', 'o', 'O']),
        ).rows,
        ['.oO'],
      );
    });
  });

  group('cells', () {
    test('null and not finite are blank: no data', () {
      expect(
        heat(
          [
            [4, null, 4, double.nan, 4],
          ],
          5,
          1,
          min: 0,
          scale: const HeatmapScale.shades(['.', '#']),
        ).rows,
        ['# # #'],
      );
    });

    test('are their glyph over all their columns but the last', () {
      expect(
        heat(
          [
            [1, 2, 4],
          ],
          6,
          1,
          min: 0,
          cellWidth: 2,
        ).rows,
        ['░ ▒ █'],
      );
      expect(
        heat(
          [
            [1, 4],
          ],
          6,
          1,
          min: 0,
          cellWidth: 3,
        ).rows,
        ['░░ ██'],
      );
    });

    test('a glyph two columns wide takes a whole cell, and in a cell of a '
        'column is in :+#', () {
      final wide = heat(
        [
          [2, 3, 4],
        ],
        6,
        1,
        min: 0,
        cellWidth: 2,
        ambiguousWidth: 2,
      );
      expect(wide.rows, ['▒▓█']);
      expect(wide.anyWide, isTrue);
      final narrow = heat(
        [
          [0, 1, 2, 3, 4],
        ],
        5,
        1,
        ambiguousWidth: 2,
      );
      // ░ is one column wherever
      expect(narrow.rows, [' ░:+#']);
      expect(narrow.anyWide, isFalse);
    });

    test('rows of cells, and the marked one in the cursor style', () {
      final shot = heat(
        [
          [0, 4],
          [4, 0],
        ],
        3,
        2,
        cellWidth: 2,
        cursor: (1, 0),
      );
      expect(shot.rows, ['  █', '█']);
      expect(shot.attrs(1).take(2), [Attr.reverse, Attr.reverse]);
      expect(shot.attrs(0).take(2), [0, 0]);
    });
  });

  group('labels', () {
    test('rows start with theirs, the widest and a blank before the '
        'cells', () {
      expect(
        heat(
          [
            [4],
            [0],
            [4],
          ],
          11,
          3,
          rowLabels: const ['Mon', '', 'Wednesday'],
        ).rows,
        ['Mon       █', '', 'Wednesday █'],
      );
    });

    test('a column label runs on to a blank before the next one', () {
      expect(
        heat(
          [
            [1, 1, 1, 1, 1, 1],
          ],
          11,
          2,
          min: 0,
          cellWidth: 2,
          columnLabels: const ['October', '', '', 'Nov', '', ''],
        ).rows,
        ['Octob Nov', '█ █ █ █ █ █'],
      );
    });

    test('the legend: the scale between less and more, at the right of '
        'the cells', () {
      expect(
        heat(
          [
            [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13],
          ],
          15,
          2,
          showLegend: true,
        ).rows,
        [' ░░░▒▒▒▓▓▓████', 'less  ░▒▓█ more'],
      );
    });
  });

  group('colors', () {
    const scale = HeatmapScale.colors(Gradient([black, green]));

    test('on an RGB terminal, ■ in the color of the gradient at the '
        'value', () {
      final shot = heat(
        [
          [0, 1, null, 2],
        ],
        4,
        1,
        scale: scale,
      );
      expect(shot.rows, ['■■ ■']);
      final cells = shot.colors(0);
      expect(
        [cells[0].$2, cells[1].$2, cells[3].$2],
        [
          black,
          const Color.rgb(0, 100, 0),
          green,
        ],
      );
    });

    test('between the stops of the gradient', () {
      const stops = HeatmapScale.colors(
        Gradient([black, green, Color.rgb(200, 200, 200)], stops: [0, 0.5, 1]),
      );
      final shot = heat(
        [
          [0, 1, 2, 3, 4],
        ],
        5,
        1,
        scale: stops,
      );
      expect(
        [for (final (_, fg, _) in shot.colors(0)) fg],
        [
          black,
          const Color.rgb(0, 100, 0),
          green,
          const Color.rgb(100, 200, 100),
          const Color.rgb(200, 200, 200),
        ],
      );
    });

    test('where ■ is two columns, a blank on the color in a cell of '
        'one', () {
      final shot = heat(
        [
          [0, 2],
        ],
        2,
        1,
        scale: scale,
        ambiguousWidth: 2,
      );
      expect(shot.colors(0), [
        (' ', Color.defaultColor, black),
        (' ', Color.defaultColor, green),
      ]);
    });

    test('on a terminal of 256 colors or fewer, the shades', () {
      final grid = RenderHeatmap(
        rows: 1,
        columns: 3,
        value: (row, column) => column.toDouble(),
        scale: scale,
        cellWidth: 1,
      );
      final shot = Shot.render(grid, 3, 1);
      expect(shot.rows, ['■■■']);
      shot.screen.styles.colorMode = ColorMode.ansi256;
      grid.markNeedsPaint();
      shot.frame();
      expect(shot.rows, [' ▒█']);
      shot.screen.styles.colorMode = ColorMode.none;
      grid.markNeedsPaint();
      shot.frame();
      expect(shot.rows, [' ▒█']);
    });

    test('scales are equal by their glyphs or their gradient', () {
      expect(
        const HeatmapScale.shades(['a', 'b']),
        HeatmapScale.shades(['a', 'b'].toList()),
      );
      expect(
        HeatmapScale.colors(Gradient([black, green].toList())),
        scale,
      );
      expect(scale, isNot(const HeatmapScale.colors(Gradient([green]))));
      expect(scale, isNot(const HeatmapScale.shades()));
    });
  });

  group('Heatmap', () {
    Widget map({
      void Function((int, int))? onSelected,
      bool tooltips = true,
    }) => Overlay(
      child: Align(
        alignment: Alignment.topLeft,
        child: Heatmap(
          rows: 3,
          columns: 4,
          value: (row, column) => (row * 4 + column).toDouble(),
          rowLabels: const ['a', 'b', 'c'],
          tooltip: tooltips ? (row, column) => 'r$row c$column' : null,
          onSelected: onSelected,
          autofocus: true,
        ),
      ),
    );

    testTwk('is as big as its cells and labels', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Heatmap(
                rows: 2,
                columns: 3,
                value: (row, column) => 1,
                min: 0,
                rowLabels: const ['ab', 'c'],
                columnLabels: const ['x', '', ''],
                showLegend: true,
              ),
              const Text('|'),
            ],
          ),
        ),
        size: (30, 6),
      );
      // the legend is wider than the cells
      expect(t.lines.take(4), [
        '   x           |',
        'ab █ █ █',
        'c  █ █ █',
        'less  ░▒▓█ more',
      ]);
    });

    testTwk('the arrows move the marked cell while it has the focus, its '
        'tooltip under it; Enter and Space select it', (t) async {
      final selected = <(int, int)>[];
      await t.pumpWidget(
        Theme.terminal(child: map(onSelected: selected.add)),
        size: (30, 8),
      );
      await settle(t);
      expect(t, styleAt(2, 0, hasBg(const Color.indexed(237))));
      expect(t.lines[3], contains('r0 c0'));
      await t.press('right down');
      await settle(t);
      expect(t, styleAt(2, 0, isNot(hasBg(const Color.indexed(237)))));
      expect(t, styleAt(4, 1, hasBg(const Color.indexed(237))));
      expect(t.lines[3], contains('r1 c1'));
      // at the edges it stays
      await t.press('up up up left left left');
      await settle(t);
      expect(t, styleAt(2, 0, hasBg(const Color.indexed(237))));
      await t.press('enter');
      await t.press('right space');
      expect(selected, [(0, 0), (0, 1)]);
    });

    testTwk('the mouse on a cell shows its tooltip, at once; a click '
        'selects it', (t) async {
      final selected = <(int, int)>[];
      await t.pumpWidget(
        Theme.terminal(child: map(onSelected: selected.add)),
        size: (30, 8),
      );
      await t.mouse(MouseKind.move, 7, 2);
      await settle(t);
      expect(t.lines[3], contains('r2 c2'));
      // the blank after a cell is the cell's
      await t.mouse(MouseKind.move, 5, 1);
      await settle(t);
      expect(t.lines[3], contains('r1 c1'));
      await t.click(4, 2);
      await settle(t);
      expect(selected, [(2, 1)]);
      expect(t, styleAt(4, 2, hasBg(const Color.indexed(237))));
    });

    testTwk('a tooltip that says something after a rebuild shows, and '
        'one that says nothing goes', (t) async {
      // as big as the screen: the tooltip under its cells all the same
      Widget saying(String message) => Overlay(
        child: Heatmap(
          rows: 1,
          columns: 2,
          value: (row, column) => 1,
          tooltip: (row, column) => message,
          autofocus: true,
        ),
      );
      await t.pumpWidget(Theme.terminal(child: saying('')), size: (30, 4));
      await settle(t);
      expect(t.lines.join(), isNot(contains('now')));
      await t.pumpWidget(Theme.terminal(child: saying('now')));
      await settle(t);
      expect(t.lines[1], contains('now'));
      await t.pumpWidget(Theme.terminal(child: saying('')));
      await settle(t);
      expect(t.lines.join(), isNot(contains('now')));
    });

    testTwk('without the focus or the mouse, no tooltip', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: Overlay(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Button('x', onPressed: () {}, autofocus: true),
                Heatmap(
                  rows: 1,
                  columns: 2,
                  value: (row, column) => 1,
                  tooltip: (row, column) => 'tip',
                ),
              ],
            ),
          ),
        ),
        size: (30, 8),
      );
      await settle(t);
      expect(t.lines.join(), isNot(contains('tip')));
      await t.mouse(MouseKind.move, 0, 1);
      await settle(t);
      expect(t.lines.join(), contains('tip'));
      await t.mouse(MouseKind.move, 20, 6);
      await settle(t);
      expect(t.lines.join(), isNot(contains('tip')));
    });

    testTwk('without a tooltip or onSelected it takes no keys', (t) async {
      final log = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: KeyBindings(
            {'right': () => log.add('right')},
            child: Heatmap(
              rows: 1,
              columns: 2,
              value: (row, column) => 1,
            ),
          ),
        ),
        size: (10, 2),
      );
      await t.press('tab right');
      expect(log, ['right']);
    });

    testTwk('a screen reader reads a table of the values', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: Heatmap(
            rows: 2,
            columns: 2,
            value: (row, column) => row == 1 && column == 1 ? null : 1.5,
            rowLabels: const ['cpu', 'io'],
            columnLabels: const ['9h', '10h'],
          ),
        ),
        size: (10, 4),
      );
      expect(t.binding.semantics.lines, [
        'cpu',
        '9h: 1.5',
        '10h: 1.5',
        'io',
        '9h: 1.5',
        '10h: no data',
      ]);
      await t.pumpWidget(Theme.terminal(child: map()), size: (30, 8));
      await t.pump();
      expect(t.binding.semantics.lines.take(3), ['a', 'r0 c0', 'r0 c1']);
      expect(t.binding.semantics.focusedLine, 1);
    });
  });

  group('ActivityHeatmap', () {
    testTwk('weeks as columns up to the end, months over their first week, '
        'every other weekday labelled, the days after the end blank', (
      t,
    ) async {
      await t.pumpWidget(
        Theme.terminal(
          child: ActivityHeatmap(
            counts: {
              DateTime(2026, 9, 28): 4,
              DateTime(2026, 10, 7, 13): 2,
              DateTime(2026, 10, 7, 18): 2,
              DateTime(2026, 11, 4): 1,
            },
            end: DateTime(2026, 11, 4),
            weeks: 6,
          ),
        ),
        size: (20, 9),
      );
      expect(t.lines.take(8), [
        '    Oct     Nov',
        'Mon █ · · · · ·',
        '    · · · · · ·',
        'Wed · █ · · · ░',
        '    · · · · ·',
        'Fri · · · · ·',
        '    · · · · ·',
        'Sun · · · · ·',
      ]);
    });

    testTwk('the first week takes its month where it fits before the '
        'next', (t) async {
      Future<String> months(DateTime end, int weeks) async {
        await t.pumpWidget(
          Theme.terminal(
            child: ActivityHeatmap(counts: const {}, end: end, weeks: weeks),
          ),
          size: (40, 9),
        );
        return t.lines[0];
      }

      // from Monday 14 September, October from the third week
      expect(await months(DateTime(2026, 10, 28), 7), '    Sep Oct     Nov');
      // from Monday 21 September, October from the second: no room
      expect(await months(DateTime(2026, 10, 28), 6), '      Oct     Nov');
    });

    testTwk('from the first weekday given', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: ActivityHeatmap(
            counts: {DateTime(2026, 10, 18): 1},
            end: DateTime(2026, 10, 21),
            weeks: 2,
            firstWeekday: DateTime.sunday,
          ),
        ),
        size: (20, 9),
      );
      // from Sunday 11 October: the 18th the first of the second week
      expect(t.lines.take(8), [
        '    Oct',
        'Sun · █',
        '    · ·',
        'Tue · ·',
        '    · ·',
        'Thu ·',
        '    ·',
        'Sat ·',
      ]);
    });

    testTwk("the marked day's tooltip says its count; Enter and a click "
        'select the day, not one after the end', (t) async {
      final selected = <DateTime>[];
      await t.pumpWidget(
        Theme.terminal(
          child: Overlay(
            child: Align(
              alignment: Alignment.topLeft,
              child: ActivityHeatmap(
                counts: {DateTime(2026, 10, 12): 3},
                end: DateTime(2026, 10, 21),
                weeks: 2,
                autofocus: true,
                onSelected: selected.add,
              ),
            ),
          ),
        ),
        size: (30, 10),
      );
      await settle(t);
      expect(t.lines[8], contains('3 on 2026-10-12'));
      await t.press('right down down');
      await settle(t);
      expect(t.lines[8], contains('0 on 2026-10-21'));
      await t.press('enter down');
      await settle(t);
      // Thursday is after the end: nothing to say, nothing to select
      expect(t.lines[8], isNot(contains(' on ')));
      await t.press('enter');
      await t.click(4, 2);
      expect(selected, [DateTime(2026, 10, 21), DateTime(2026, 10, 13)]);
    });

    testTwk('a tooltip of its own', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: Overlay(
            child: Align(
              alignment: Alignment.topLeft,
              child: ActivityHeatmap(
                counts: {DateTime(2026, 10, 12): 2},
                end: DateTime(2026, 10, 21),
                weeks: 2,
                autofocus: true,
                tooltip: (day, count) => '$count commits, ${day.day}th',
              ),
            ),
          ),
        ),
        size: (30, 10),
      );
      await settle(t);
      expect(t.lines[8], contains('2 commits, 12th'));
    });

    test('the default tooltip', () {
      expect(
        ActivityHeatmap.defaultTooltip(DateTime(2026, 10, 21), 3),
        '3 on 2026-10-21',
      );
      expect(
        ActivityHeatmap.defaultTooltip(DateTime(2026, 1, 2), 2.5),
        '2.5 on 2026-01-02',
      );
    });
  });
}
