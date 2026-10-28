/// Children in the cells of columns and rows: [Grid] lays them out,
/// [GridPlacement] puts one in its cells.
///
/// @docImport '../data/table.dart';
/// @docImport 'flex.dart';
library;

import 'package:twk_core/twk_core.dart'
    show GridParentData, GridTrack, RenderGrid, RenderObject;

import '../framework/framework.dart';
import 'child_list.dart';

export 'package:twk_core/twk_core.dart' show GridTrack, GridTrackKind;

/// Lays its children out in the cells of its [columns] and [rows], tracks
/// [columnGap] columns and [rowGap] rows apart (CSS grid, simplified). A
/// track is fixed ([GridTrack.fixed]), a fraction of the cells the others
/// leave ([GridTrack.fr]) or as long as the children in it ask for
/// ([GridTrack.content]); tracks past the end of a list are content
/// tracks. A [GridPlacement] puts a child in its cells; a child without a
/// row and a column goes in the cells after the child before it, from the
/// first column on the next row when they would reach past the last of
/// [columns]. Each child is exactly as big as its cells; children that
/// overlap are painted in order. See [RenderGrid].
///
/// A form: labels as wide as the longest, fields in the rest, and a note
/// across both columns at the bottom:
///
/// ```dart
/// const Grid(
///   columns: [GridTrack.content(), GridTrack.fr(1)],
///   columnGap: 1,
///   children: [
///     Text('Name'),
///     TextField(),
///     Text('E-mail'),
///     TextField(),
///     GridPlacement(row: 2, column: 0, columnSpan: 2, child: Text('*')),
///   ],
/// )
/// ```
///
/// See also:
///
///  * [Row] and [Column], for one track.
///  * [Table], for rows of data.
final class Grid extends MultiChildRenderObjectWidget {
  /// Lays [children] out in [columns] and [rows], [columnGap] and
  /// [rowGap] cells apart (0 or more); with no tracks given, every track
  /// is a content track.
  const Grid({
    super.key,
    this.columns = const [],
    this.rows = const [],
    this.columnGap = 0,
    this.rowGap = 0,
    super.children,
  }) : assert(columnGap >= 0 && rowGap >= 0, 'gaps of 0 cells or more');

  /// The columns from the left.
  final List<GridTrack> columns;

  /// The rows from the top.
  final List<GridTrack> rows;

  /// Columns between one column and the next.
  final int columnGap;

  /// Rows between one row and the next.
  final int rowGap;

  @override
  MultiChildRenderObjectElement createElement() => ChildListElement(this);

  @override
  RenderGrid createRenderObject(BuildContext context) => RenderGrid(
    columns: columns,
    rows: rows,
    columnGap: columnGap,
    rowGap: rowGap,
  );

  @override
  void updateRenderObject(BuildContext context, RenderGrid renderObject) {
    renderObject
      ..columns = columns
      ..rows = rows
      ..columnGap = columnGap
      ..rowGap = rowGap;
  }
}

/// Puts [child] in the cells of the [Grid] it is in: [rowSpan] rows from
/// [row] and [columnSpan] columns from [column], counted from 0 at the top
/// left. Without a row and a column the child goes after the one before
/// it, as the grid places a child without a [GridPlacement]. It goes
/// inside a [Grid] with no render object widget in between.
///
/// A header across the three columns of a grid's first row:
///
/// ```dart
/// const GridPlacement(row: 0, column: 0, columnSpan: 3, child: Text('Q3'))
/// ```
final class GridPlacement extends ParentDataWidget<GridParentData> {
  /// Puts [child] at [row] and [column], both or neither given, each 0 or
  /// more, over [rowSpan] rows and [columnSpan] columns, each 1 or more.
  const GridPlacement({
    required super.child,
    super.key,
    this.row,
    this.column,
    this.rowSpan = 1,
    this.columnSpan = 1,
  }) : assert(
         (row == null) == (column == null),
         'a row and a column, or neither',
       ),
       assert(
         (row ?? 0) >= 0 && (column ?? 0) >= 0,
         'a row and a column of 0 or more',
       ),
       assert(rowSpan > 0 && columnSpan > 0, 'spans of 1 track or more');

  /// The first row the child is in, from 0; null to follow the child
  /// before it.
  final int? row;

  /// The first column the child is in, from 0; null to follow the child
  /// before it.
  final int? column;

  /// How many rows the child takes: 1 by default.
  final int rowSpan;

  /// How many columns the child takes: 1 by default.
  final int columnSpan;

  @override
  void applyParentData(RenderObject renderObject) {
    final at = renderObject.parentData as GridParentData;
    if (at.row != row ||
        at.column != column ||
        at.rowSpan != rowSpan ||
        at.columnSpan != columnSpan) {
      at
        ..row = row
        ..column = column
        ..rowSpan = rowSpan
        ..columnSpan = columnSpan;
      renderObject.parent?.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => Grid;
}
