// Grids of widgets: the render objects of the children go into the grid in
// order, each in the cells its GridPlacement names or after the one before
// it, and keep their cells whatever is rebuilt below them.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show GridParentData, RenderGrid;

import 'view.dart';

/// The cells on [o]: row, column, row span, column span.
List<int?> cellsOf(RenderObject o) {
  final at = o.parentData as GridParentData;
  return [at.row, at.column, at.rowSpan, at.columnSpan];
}

void main() {
  test('a Grid lays out a form: labels in a column as wide as the widest, '
      'fields in the columns left', () {
    final v = View(14, 3)
      ..pump(
        const Grid(
          columns: [GridTrack.content(), GridTrack.fr(1)],
          columnGap: 1,
          children: [
            Text('Name', align: TextAlign.right),
            Label('Bob'),
            Text('E-mail', align: TextAlign.right),
            Label('bob@example.com'),
          ],
        ),
      );
    expect(v.rows(), ['  Name Bob', 'E-mail bob@exa', '']);
  });

  test('a Grid lays out a dashboard: a header across the columns, panels '
      'sharing the cells left', () {
    final v = View(8, 3)
      ..pump(
        const Grid(
          columns: [GridTrack.fr(1), GridTrack.fr(2)],
          rows: [GridTrack.fixed(1), GridTrack.fr(1)],
          columnGap: 1,
          children: [
            GridPlacement(row: 0, column: 0, columnSpan: 2, child: Fill('=')),
            Fill('a'),
            Fill('b'),
          ],
        ),
      );
    expect(v.rows(), ['========', 'aaa bbbb', 'aaa bbbb']);
  });

  test('a Grid gives its settings to its render object; the same tracks '
      'in other lists ask for nothing', () {
    Widget grid(int width, int gap) => Grid(
      columns: [GridTrack.fixed(width), GridTrack.fixed(width)],
      rows: List.filled(2, const GridTrack.fixed(1)),
      columnGap: gap,
      rowGap: gap,
      children: const [Label('a'), Label('b'), Label('c')],
    );
    final v = View(8, 4)..pump(grid(2, 1));
    final render = v.top as RenderGrid;
    expect(
      [render.columns, render.rows, render.columnGap, render.rowGap],
      [
        [const GridTrack.fixed(2), const GridTrack.fixed(2)],
        [const GridTrack.fixed(1), const GridTrack.fixed(1)],
        1,
        1,
      ],
    );
    expect(v.rows(), ['a  b', '', 'c', '']);
    v.pump(grid(3, 0));
    expect(v.top, same(render));
    expect(v.rows(), ['a  b', 'c', '', '']);
    final state = (v..pump(Toggle(() => grid(3, 0), () => grid(3, 0)))).root;
    toggleIn(state).toggle();
    v.owner.buildScope();
    expect(v.pipeline.hasWork, isFalse);
  });

  test('a GridPlacement puts its cells on its child', () {
    final v = View(3, 3)
      ..pump(
        const Grid(
          columns: [
            GridTrack.fixed(1),
            GridTrack.fixed(1),
            GridTrack.fixed(1),
          ],
          rows: [GridTrack.fixed(1), GridTrack.fixed(1), GridTrack.fixed(1)],
          children: [
            GridPlacement(row: 1, column: 2, child: Label('a')),
            GridPlacement(columnSpan: 2, child: Label('bc')),
            Label('d'),
          ],
        ),
      );
    final [a, bc, d] = childrenOf(v.top);
    expect(cellsOf(a), [1, 2, 1, 1]);
    expect(cellsOf(bc), [null, null, 1, 2]);
    expect(cellsOf(d), [null, null, 1, 1]);
    expect(v.rows(), ['', '  a', 'bcd']);
  });

  test('new cells lay the grid out again; the same ask for nothing', () {
    Widget at(int column, int span) => Grid(
      columns: const [
        GridTrack.fixed(1),
        GridTrack.fixed(1),
        GridTrack.fixed(1),
      ],
      rows: const [GridTrack.fixed(1), GridTrack.fixed(1)],
      children: [
        GridPlacement(
          row: 0,
          column: column,
          columnSpan: span,
          child: const Fill('x'),
        ),
        const Label('y'),
      ],
    );
    final v = View(3, 2)..pump(at(0, 1));
    expect(v.rows(), ['xy', '']);
    v.pump(at(1, 2));
    expect(v.rows(), [' xx', 'y']);
    final state = (v..pump(Toggle(() => at(1, 2), () => at(1, 2)))).root;
    toggleIn(state).toggle();
    v.owner.buildScope();
    expect(v.pipeline.hasWork, isFalse);
  });

  test('a GridPlacement keeps its cells when what is below it is rebuilt '
      'into another render object', () {
    final v = View(4, 1)
      ..pump(
        Grid(
          columns: const [GridTrack.fixed(2), GridTrack.fixed(2)],
          rows: const [GridTrack.fixed(1)],
          children: [
            GridPlacement(
              row: 0,
              column: 1,
              child: Toggle(() => const Label('ab'), () => const Fill('x')),
            ),
          ],
        ),
      );
    expect(v.rows(), ['  ab']);
    toggleIn(v.root).toggle();
    v.frame();
    expect(v.rows(), ['  xx']);
    expect(cellsOf(childrenOf(v.top).single), [0, 1, 1, 1]);
  });

  test('a GridPlacement with a row and no column, or a span of 0, is an '
      'error', () {
    expect(
      () => GridPlacement(row: 0, child: const Label('a')),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => GridPlacement(rowSpan: 0, child: const Label('a')),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => GridPlacement(row: -1, column: 0, child: const Label('a')),
      throwsA(isA<AssertionError>()),
    );
  });

  test('a GridPlacement outside a Grid is an error', () {
    final v = View(10, 1);
    expect(
      () => v.pump(const Row(children: [GridPlacement(child: Label('a'))])),
      throwsA(isA<AssertionError>()),
    );
  });
}
