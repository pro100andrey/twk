/// Tables: a [Table] of rows in columns under a header that stays while
/// they scroll, which sorts them by a column, selects a row or a cell and
/// resizes its columns; its [TableColumn]s, the [TableCell]s they show,
/// the [TableSource] of rows read one at a time, and the
/// [TableController] that holds its selection, its order and the widths
/// given to its columns.
library;

import 'dart:collection';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        Attr,
        BorderType,
        BoxConstraints,
        ContainerParentDataMixin,
        ContainerRenderObjectMixin,
        GridTrack,
        GridTrackKind,
        HitTestBehavior,
        KeyEvent,
        KeyKind,
        PaintContext,
        ParentData,
        PipelineOwner,
        RenderList,
        RenderObject,
        RenderObjectWithChildMixin,
        TextAlign,
        TextMode,
        TextOverflow,
        TextSegmenter,
        TextWrap;

import '../binding/terminal_status.dart';
import '../focus/focus.dart';
import '../foundation/change_notifier.dart';
import '../foundation/helpers.dart';
import '../framework/framework.dart';
import '../gestures/mouse.dart';
import '../layout/child_list.dart';
import '../layout/flex.dart';
import '../layout/one_child.dart';
import '../scroll/list_view.dart';
import '../style/style.dart';
import '../text/widgets.dart';
import 'chart_glyphs.dart';

// Examples can assume:
// typedef File = ({String name, int size});
// late List<File> files;
// late List<TableColumn<File>> columns;
// late TableSource<File> listing;
// void open(File file) {}

/// What a cell of a [Table] shows: text in one style ([TableCell.new]),
/// text in spans ([TableCell.rich]), or a widget ([TableCell.widget]).
/// Text is one line, placed and cut off as its column says
/// ([TableColumn.align], [TableColumn.overflow]), in its style over the
/// row's.
@immutable
final class TableCell {
  /// [text] in [style].
  const TableCell(String this.text, {this.style = const Style()})
    : spans = null,
      child = null,
      _wrap = null;

  /// [spans], each in its style.
  const TableCell.rich(List<Span> this.spans)
    : text = null,
      style = const Style(),
      child = null,
      _wrap = null;

  const TableCell._wrapped(List<Span> this.spans, this._wrap)
    : text = null,
      style = const Style(),
      child = null;

  /// [child], laid out as wide as the column and as tall as it likes
  /// within the row's height ([Table.rowHeight]); its text is in the
  /// styles a text cell's is in ([DefaultTextStyle]).
  const TableCell.widget(Widget this.child)
    : text = null,
      spans = null,
      style = const Style(),
      _wrap = null;

  /// The text of a [TableCell.new]; null for the others.
  final String? text;

  /// The spans of a [TableCell.rich]; null for the others.
  final List<Span>? spans;

  /// The style of [text], over the row's.
  final Style style;

  /// The widget of a [TableCell.widget]; null for the others.
  final Widget? child;

  // what the text of a cell of [wrappedTableCell] is drawn in
  final Widget Function(Widget text)? _wrap;
}

/// [spans] as a [TableCell.rich] of them, measured and drawn as it is, the
/// text drawn given to [wrap] for the widget the cell shows, such as one
/// that listens to the mouse over the cell. What a `TreeTable` presses its
/// expanders by; not exported.
TableCell wrappedTableCell(
  List<Span> spans,
  Widget Function(Widget text) wrap,
) => TableCell._wrapped(spans, wrap);

/// A column of a [Table] whose rows are [T]s: its [title], what it shows
/// of a row ([cell]), how wide it is ([width]), where its text sits
/// ([align]) and how text too wide for it is cut off ([overflow]), and how
/// it orders the rows ([compare]).
///
/// A column of sizes, at the right of its cells, that sorts the rows by
/// size:
///
/// ```dart
/// TableColumn<File>(
///   title: 'Size',
///   cell: (file) => TableCell('${file.size}'),
///   align: TextAlign.right,
///   compare: (a, b) => a.size.compareTo(b.size),
/// )
/// ```
@immutable
final class TableColumn<T> {
  /// A column titled [title] that shows [cell] of each row: as wide as
  /// its title and its text want by default ([width]), its text at the
  /// left ([align]) and cut off with `…` ([overflow]); with [compare], one
  /// that sorts the rows.
  const TableColumn({
    required this.title,
    required this.cell,
    this.width = const GridTrack.content(),
    this.align = TextAlign.left,
    this.overflow = TextOverflow.ellipsis,
    this.compare,
  });

  /// The header's text.
  final String title;

  /// What the column shows of a row.
  // called with the table's rows, whose T is the column's own
  // ignore: unsafe_variance
  final TableCell Function(T row) cell;

  /// Fixed ([GridTrack.fixed]), a part of the cells the other columns
  /// leave ([GridTrack.fr]), or as wide as its title and its text want
  /// ([GridTrack.content]); see [Table].
  final GridTrack width;

  /// Where the title and the text of the cells sit in the column.
  final TextAlign align;

  /// How the title and the text of a cell show where they are too wide.
  final TextOverflow overflow;

  /// The order of two rows by this column, for sorting; null for a column
  /// that does not sort.
  // ignore: unsafe_variance
  final Comparator<T>? compare;
}

/// What the keys and the mouse select in a [Table].
enum TableSelection {
  /// Nothing: the keys scroll the rows.
  none,

  /// A row.
  row,

  /// A cell: a row, and a column of it.
  cell,
}

/// The rows of a [Table] read one at a time, for more of them than a list
/// would hold: how many there are ([rowCount]) and the one at an index
/// ([rowAt]). The table reads the rows it shows, a sample of the others
/// when it measures its content columns, and all of them when it sorts
/// them. A source notifies its listeners when its rows change: the table
/// reads them again, measures and sorts them again.
abstract class TableSource<T> extends ChangeNotifier {
  /// How many rows there are.
  int get rowCount;

  /// The row at [index], from 0 to [rowCount] less one.
  T rowAt(int index);
}

/// Where a [Table] is: the row selected, by its key ([selectedKey]), the
/// column of the cell selected ([selectedColumn]), the column the rows are
/// sorted by ([sortColumn], [sortAscending]), and the widths the columns
/// were given ([columnWidths]). It notifies its listeners of each change.
///
/// The selection is a key, not a place: it stays on its row while the rows
/// are sorted, and while rows are added and taken away around it.
///
/// A table that opens sorted by its second column, the largest first, and
/// is sorted by its first from the app:
///
/// ```dart
/// final controller = TableController(sortColumn: 1, sortAscending: false);
/// final table = Table<File>(
///   rows: files,
///   columns: columns,
///   controller: controller,
/// );
/// // ... later:
/// controller.sortBy(0);
/// ```
final class TableController extends ChangeNotifier {
  /// Selects the row whose key is [selectedKey] (none by default) and its
  /// cell in [selectedColumn] (the first by default), sorts the rows by
  /// [sortColumn] (none by default), in the order of its
  /// [TableColumn.compare] unless [sortAscending] is false, and gives the
  /// columns in [columnWidths] those widths. A column below 0 asserts.
  TableController({
    this._selectedKey,
    int selectedColumn = 0,
    int? sortColumn,
    this._sortAscending = true,
    Map<int, int> columnWidths = const {},
  }) : assert(selectedColumn >= 0, 'a column of 0 or more'),
       assert(sortColumn == null || sortColumn >= 0, 'a column of 0 or more'),
       _selectedColumn = selectedColumn,
       _sortColumn = sortColumn,
       _widths = {...columnWidths};

  Object? _selectedKey;

  /// The key of the row selected ([Table.rowKey]); null for none, and a key
  /// no row has selects none.
  Object? get selectedKey => _selectedKey;

  set selectedKey(Object? key) {
    if (key != _selectedKey) {
      _selectedKey = key;
      notifyListeners();
    }
  }

  int _selectedColumn;

  /// The column of the cell selected, from 0, in a table that selects
  /// cells.
  int get selectedColumn => _selectedColumn;

  set selectedColumn(int column) {
    assert(column >= 0, 'a column of 0 or more');
    if (column != _selectedColumn) {
      _selectedColumn = column;
      notifyListeners();
    }
  }

  int? _sortColumn;
  bool _sortAscending;

  /// The column the rows are sorted by, from 0; null, or a column that
  /// does not sort, for the order of [Table.rows].
  int? get sortColumn => _sortColumn;

  /// Whether the rows are sorted in the order of the column's
  /// [TableColumn.compare], or the other way. Rows that compare equal keep
  /// the order of [Table.rows] either way.
  bool get sortAscending => _sortAscending;

  /// Sorts the rows by [column], [ascending] or not; null for the order of
  /// [Table.rows].
  void sortBy(int? column, {bool ascending = true}) {
    assert(column == null || column >= 0, 'a column of 0 or more');
    if (column != _sortColumn || ascending != _sortAscending) {
      _sortColumn = column;
      _sortAscending = ascending;
      _arranged++;
      notifyListeners();
    }
  }

  final Map<int, int> _widths;

  /// The width given to each column resized ([resizeColumn]), in cells, by
  /// the column, from 0; a column not in it is as wide as its
  /// [TableColumn.width] makes it.
  Map<int, int> get columnWidths => UnmodifiableMapView(_widths);

  /// Makes [column] [width] cells wide, within its bounds (see [Table]), as
  /// a drag of its edge and the keys do; null gives it back the width its
  /// [TableColumn.width] makes.
  void resizeColumn(int column, int? width) {
    assert(column >= 0, 'a column of 0 or more');
    assert(width == null || width >= 0, 'a width of 0 cells or more');
    if (width != _widths[column]) {
      if (width == null) {
        _widths.remove(column);
      } else {
        _widths[column] = width;
      }
      _arranged++;
      notifyListeners();
    }
  }

  // a number for each order and set of widths: another when they change,
  // the selection alone changing the rows it leaves and enters only
  var _arranged = 0;
}

/// A table of [rows] in [columns] under a header of their titles, which
/// stays while the rows scroll.
///
/// The rows are in the order [controller] sorts them in, the one it
/// selects marked. [Table.source] shows the rows of a
/// [TableSource], read one at a time, for more of them than a list would
/// hold: a million rows scroll as a hundred do.
///
/// The rows are a [ListView]'s items: only those in view and a few rows
/// past them are built, each a row of cells, [rowHeight] rows tall (or as
/// tall as its tallest cell, at least a row, when null), scrolled by the
/// wheel and moved by the hardware as the list is, also as the selection
/// moves past an edge: a row restyled repaints alone. A row's key
/// ([rowKey], by default its index in the rows) keeps its widgets'
/// [State] while the rows are sorted, and is what the controller selects;
/// no two rows have the same.
///
/// The columns are [columnGap] cells apart, and sized as a grid sizes
/// them: a fixed column takes its cells; a content column wants the
/// widest of its title (with two cells for the sort mark when it sorts)
/// and the text of its cells (a widget cell wants nothing) within its
/// bounds, a fraction column its minimum. When the cells are too few for
/// that, the content columns give up cells down to their minimum, the
/// widest first; when they are more, the fraction columns share the cells
/// left by their fractions within their bounds. What does not fit is cut
/// off at the right. Text too wide for its column is cut off as the
/// column says ([TableColumn.overflow]). The text of the cells of a
/// content column is measured once for rows the table was not given
/// before: a list of [rows] or [columns] it was not given before, or of
/// another length (so give it a new list to change them), or a [source]
/// that notified or has another count; the rows are sorted again then.
/// Of more rows than [sampleRows] and those in view, it measures the rows
/// in view then and [sampleRows] rows spread evenly over all of them.
///
/// A drag from the gap after the title of a column (from the cell after
/// it without a gap) makes the column as wide as the drag says, the
/// pointer [PointerShape.ewResize] over that gap with [pointerShapes]
/// where the terminal shows the pointer's shape (and then reports all
/// motion of the mouse over the header); while the
/// table has the focus, Shift+Left and Shift+Right make the column of the
/// cell selected (with [TableSelection.cell]), or that sorted by, or the
/// first, a cell narrower or wider. A column resized is as wide as it was
/// made ([TableController.columnWidths]): at least a cell, and a content
/// or a fraction column within its bounds.
///
/// With [border], a line runs down the middle of each gap and under the
/// header, joined where they cross; [BorderType.ascii] where the terminal
/// draws box drawing two columns wide.
///
/// A click on the title of a column that sorts ([TableColumn.compare])
/// sorts the rows by it, again the other way, the header marking it `▴`
/// or `▾`. While the table has the focus, `s` does that for the column of
/// the cell selected (with [TableSelection.cell]) or that sorted by (the
/// first that sorts for none), and `<` and `>` sort by the column before
/// or after the one sorted by. Sorting reads every row.
///
/// As [selection] says, a click selects a row or a cell, and gives the
/// table the focus; while it has the focus, Up and Down select the row
/// above and below, Page Up and Page Down a window's rows away, Home and
/// End the first and the last, Left and Right the cell before and after
/// in the row; Enter calls [onActivated] with the row selected. A key that
/// selects no other row or cell, or resizes no column, at an end or a
/// bound, goes on to the nodes above. The view scrolls the least that
/// shows the row selected, after each of them and after the rows are
/// sorted, and shows it from the first frame and with a new [controller].
/// With [TableSelection.none] the keys scroll the rows instead.
/// A key of [rowKey] the controller selects is looked for out from where
/// the last one was found, a row below and a row above at a time; an
/// index is found at once.
///
/// The styles, each merged over those before it: [style] for every cell,
/// over the theme's background and text; [headerStyle] for the header,
/// [borderStyle] for the lines; for a row, the cell's own
/// ([TableCell.style]), for the row selected [selectedStyle] while the
/// table has the focus and [unfocusedSelectedStyle] while it has not, and,
/// while it has the focus, [cursorStyle] for the cell selected, a widget
/// cell's text included ([DefaultTextStyle]). One left null is the
/// theme's: bold text, [ThemeData.border], [ThemeData.selection],
/// [ThemeData.selectionIdle] (or [selectedStyle] where that is given) and
/// [ThemeData.primary] reversed.
///
/// It takes all the room it is given, which must be bounded.
///
/// Columns written in place in the call need the table's type argument,
/// `Table<File>(…)`: without it, Dart infers the row type of the columns'
/// closures apart from `rows`, and the table is a `Table<Object?>`.
///
/// Files by name and size, sorted by a click on a title, Enter opening the
/// one selected:
///
/// ```dart
/// Table<File>(
///   rows: files,
///   rowKey: (file) => file.name,
///   columns: [
///     TableColumn(title: 'Name', cell: (file) => TableCell(file.name)),
///     TableColumn(
///       title: 'Size',
///       cell: (file) => TableCell('${file.size}'),
///       align: TextAlign.right,
///       compare: (a, b) => a.size.compareTo(b.size),
///     ),
///   ],
///   onActivated: open,
/// )
/// ```
///
/// See also:
///
///  * `TreeTable`, a tree whose nodes are the rows of a table.
///  * [ListView], what the rows are the items of.
final class Table<T> extends StatefulWidget {
  /// A table of [rows], a list it is given whole. A [rowHeight] below 1, a
  /// [columnGap] or [sampleRows] below 0, and a [border] with no
  /// [columnGap] for it assert.
  const Table({
    required List<T> this.rows,
    required this.columns,
    super.key,
    this.rowKey,
    this.controller,
    this.selection = TableSelection.row,
    this.onActivated,
    this.rowHeight = 1,
    this.columnGap = 1,
    this.border = BorderType.none,
    this.showHeader = true,
    this.sampleRows = defaultSampleRows,
    this.focusNode,
    this.autofocus = false,
    this.canRequestFocus,
    this.style,
    this.headerStyle,
    this.borderStyle,
    this.selectedStyle,
    this.unfocusedSelectedStyle,
    this.cursorStyle,
    this.pointerShapes = true,
  }) : source = null,
       assert(rowHeight == null || rowHeight > 0, 'rows a row tall or more'),
       assert(columnGap >= 0, 'a gap of 0 cells or more'),
       assert(
         border == BorderType.none || columnGap > 0,
         'a gap for the lines between the columns',
       ),
       assert(sampleRows >= 0, 'a sample of 0 rows or more');

  /// A table of the rows of [source], read one at a time, for more of
  /// them than a list would hold; it asserts as [Table.new] does.
  ///
  /// ```dart
  /// Table<File>.source(source: listing, columns: columns)
  /// ```
  const Table.source({
    required TableSource<T> this.source,
    required this.columns,
    super.key,
    this.rowKey,
    this.controller,
    this.selection = TableSelection.row,
    this.onActivated,
    this.rowHeight = 1,
    this.columnGap = 1,
    this.border = BorderType.none,
    this.showHeader = true,
    this.sampleRows = defaultSampleRows,
    this.focusNode,
    this.autofocus = false,
    this.canRequestFocus,
    this.style,
    this.headerStyle,
    this.borderStyle,
    this.selectedStyle,
    this.unfocusedSelectedStyle,
    this.cursorStyle,
    this.pointerShapes = true,
  }) : rows = null,
       assert(rowHeight == null || rowHeight > 0, 'rows a row tall or more'),
       assert(columnGap >= 0, 'a gap of 0 cells or more'),
       assert(
         border == BorderType.none || columnGap > 0,
         'a gap for the lines between the columns',
       ),
       assert(sampleRows >= 0, 'a sample of 0 rows or more');

  /// The rows besides those in view whose text a content column is
  /// measured by, by default.
  static const defaultSampleRows = 100;

  /// The rows, in the order the table shows them unsorted; null for those
  /// of [source].
  final List<T>? rows;

  /// Where the rows are read from; null for [rows].
  final TableSource<T>? source;

  /// The columns, left to right: what each shows of a row, how wide it is
  /// and how it sorts.
  final List<TableColumn<T>> columns;

  /// The key of a row, which its widgets keep their [State] by and the
  /// controller selects; null for its index in the rows.
  // called with the rows, whose T is the table's own
  // ignore: unsafe_variance
  final Object Function(T row)? rowKey;

  /// Its selection, its order and the widths of its columns; null for one
  /// of its own.
  final TableController? controller;

  /// What the keys and the mouse select: a row by default.
  final TableSelection selection;

  /// Called with the row selected when Enter is pressed.
  // ignore: unsafe_variance
  final void Function(T row)? onActivated;

  /// The rows a row takes, 1 by default; null for as many as its tallest
  /// cell.
  final int? rowHeight;

  /// Cells between one column and the next, 1 by default.
  final int columnGap;

  /// The lines between the columns and under the header; none by default.
  final BorderType border;

  /// Whether the titles show above the rows, true by default.
  final bool showHeader;

  /// The rows besides those in view whose text a content column is
  /// measured by, spread evenly over them; all of them in a table of no
  /// more rows than these and those in view.
  final int sampleRows;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// See [FocusNode.canRequestFocus].
  final bool? canRequestFocus;

  /// Every cell, over the theme's background and text.
  final Style? style;

  /// The header; bold when null.
  final Style? headerStyle;

  /// The lines; [ThemeData.border] when null.
  final Style? borderStyle;

  /// The row selected while the table has the focus;
  /// [ThemeData.selection] when null.
  final Style? selectedStyle;

  /// The row selected while the table has not the focus; when null,
  /// [selectedStyle] where that is given, else [ThemeData.selectionIdle].
  /// [ThemeData.selection] keeps the row as it is with the focus.
  final Style? unfocusedSelectedStyle;

  /// The cell selected while the table has the focus;
  /// [ThemeData.primary] reversed when null.
  final Style? cursorStyle;

  /// Whether the pointer over the edge of a column is
  /// [PointerShape.ewResize], where the terminal shows the pointer's shape.
  final bool pointerShapes;

  @override
  State<Table<T>> createState() => _TableState<T>();
}

/// The styles of a [Table], the theme's where it has none.
final class _Styles {
  const _Styles({
    required this.base,
    required this.header,
    required this.border,
    required this.selected,
    required this.cursor,
  });

  final Style base;
  final Style header;
  final Style border;
  final Style selected;
  final Style cursor;
}

final class _TableState<T> extends State<Table<T>> {
  TableController? _own;
  FocusNode? _ownNode;
  final _list = ListController();

  TableController get _controller =>
      widget.controller ?? (_own ??= TableController());

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  // the notifications of the source so far
  var _changes = 0;

  // the selection and the order the view followed last
  Object? _followed;

  // the rows in the order shown, indices into the rows (null for theirs),
  // where each row is shown (made when asked for), and what they were
  // worked out for; a number for each order worked out
  Int32List? _order;
  Int32List? _places;
  Object? _orderData;
  List<TableColumn<T>>? _orderColumns;
  int? _orderColumn;
  var _orderAscending = true;
  var _orderVersion = 0;

  // where the selected key was found in the order of that number: -1 for
  // nowhere; where a key was found last
  Object? _foundKey;
  var _foundIn = -1;
  var _found = -1;
  var _near = 0;

  // the rows built and kept, by where they are shown; the styles they
  // were built in, where the row selected and the cell of the cursor were
  // shown last; the controller and its arrangement they were built for
  final _rows = <int, _RowSlotState<T>>{};
  late _Styles _styles;
  var _shownSelected = -1;
  var _shownCursor = -1;
  TableController? _builtFor;
  var _builtArranged = 0;

  // what each content column wants, and what it was measured for
  var _wants = const <int>[];
  Object? _wantsData;
  List<TableColumn<T>>? _wantsColumns;
  TextMode? _wantsMode;
  var _wantsAmbiguous = 0;

  // the column whose edge the mouse drags, its width and the mouse's
  // column at the press
  int? _resizing;
  var _resizedFrom = 0;
  var _pressedAt = 0;

  // the column whose edge the mouse is over in the header, while the
  // pointer's shape shows it
  int? _edgeHovered;

  // the columns as laid out last, which the rows lay their cells out by
  final _columns = _Columns();

  @override
  void initState() {
    super.initState();
    _node.addListener(_focusChanged);
    _controller.addListener(_changed);
    widget.source?.addListener(_sourceChanged);
    _follow();
  }

  @override
  void didUpdateWidget(Table<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.focusNode, oldWidget.focusNode)) {
      // the Focus below lets an own node go after this build: it is
      // disposed with this state
      (oldWidget.focusNode ?? _ownNode)?.removeListener(_focusChanged);
      _node.addListener(_focusChanged);
    }
    if (!identical(widget.controller, oldWidget.controller)) {
      (oldWidget.controller ?? _own)?.removeListener(_changed);
      _controller.addListener(_changed);
      _follow();
    }
    if (!identical(widget.source, oldWidget.source)) {
      oldWidget.source?.removeListener(_sourceChanged);
      widget.source?.addListener(_sourceChanged);
    }
  }

  @override
  void dispose() {
    widget.source?.removeListener(_sourceChanged);
    _controller.removeListener(_changed);
    _node.removeListener(_focusChanged);
    _own?.dispose();
    _ownNode?.dispose();
    _list.dispose();
    super.dispose();
  }

  void _focusChanged() => setState(() {});

  void _sourceChanged() => setState(() => _changes++);

  /// The selection and the order: another value when either changes.
  Object get _following {
    final c = _controller;
    return (c.selectedKey, c.selectedColumn, c.sortColumn, c.sortAscending);
  }

  // a new selection or order: the selected row is scrolled into view; new
  // widths alone move nothing. A new selection alone builds the row it
  // left and the row it entered again, not the table
  void _changed() {
    final c = _controller;
    if (identical(c, _builtFor) && c._arranged == _builtArranged) {
      _reselect();
    } else {
      setState(() {});
    }
    _follow();
  }

  /// The cell of the cursor: -1 for none, unless the table selects cells
  /// and has the focus.
  int get _cursor => _node.hasFocus && widget.selection == TableSelection.cell
      ? _controller.selectedColumn
      : -1;

  /// Builds again the row the selection left and the row it entered, or
  /// the row selected when the cursor moved in it.
  void _reselect() {
    final was = _shownSelected;
    final selected = _selectedIndex();
    final cursor = _cursor;
    if (selected == was && cursor == _shownCursor) {
      return;
    }
    _shownSelected = selected;
    _shownCursor = cursor;
    _rows[was]?._rebuild();
    if (selected != was) {
      _rows[selected]?._rebuild();
    }
  }

  /// Scrolls the selected row into view when the selection or the order
  /// is not the one the view followed last: as the controller changes
  /// them, with a new controller, and as the table is mounted, the list
  /// of rows mounted later taking the move from its [ListController].
  void _follow() {
    final following = _following;
    if (following == _followed) {
      return;
    }
    _followed = following;
    final at = _selectedIndex();
    if (at >= 0) {
      _list.ensureIndexVisible(at);
    }
  }

  /// How many rows there are.
  int get _count => widget.source?.rowCount ?? widget.rows!.length;

  /// The row at [index] of the rows.
  T _rowAt(int index) {
    final source = widget.source;
    return source != null ? source.rowAt(index) : widget.rows![index];
  }

  /// What the rows are: another value when they change.
  Object get _data {
    final source = widget.source;
    if (source != null) {
      return (source, _changes, source.rowCount);
    }
    final rows = widget.rows!;
    return (rows, rows.length);
  }

  /// Sorts the rows in their own order, or by the column the controller
  /// names, unless they are sorted so.
  void _sort() {
    final w = widget;
    final c = _controller;
    final data = _data;
    final column = c.sortColumn;
    if (data == _orderData &&
        identical(w.columns, _orderColumns) &&
        column == _orderColumn &&
        c.sortAscending == _orderAscending) {
      return;
    }
    _orderData = data;
    _orderColumns = w.columns;
    _orderColumn = column;
    _orderAscending = c.sortAscending;
    _orderVersion++;
    _places = null;
    final compare = column != null && column < w.columns.length
        ? w.columns[column].compare
        : null;
    if (compare == null) {
      _order = null;
      return;
    }
    final ascending = c.sortAscending;
    final count = _count;
    final source = w.source;
    // each row read once
    final rows = source == null
        ? w.rows!
        : List<T>.generate(count, source.rowAt, growable: false);
    final order = Int32List(count);
    for (var i = 0; i < order.length; i++) {
      order[i] = i;
    }
    // equal rows keep their order either way
    order.sort((a, b) {
      final d = compare(rows[a], rows[b]);
      return d != 0 ? (ascending ? d : -d) : a - b;
    });
    _order = order;
  }

  /// Where the row at [index] of the rows is shown.
  int _placeOf(int index) {
    final order = _order;
    if (order == null) {
      return index;
    }
    var places = _places;
    if (places == null) {
      places = _places = Int32List(order.length);
      for (var i = 0; i < order.length; i++) {
        places[order[i]] = i;
      }
    }
    return places[index];
  }

  /// The key of the row shown at [index].
  Object _keyAt(int index) {
    final i = _order?[index] ?? index;
    final key = widget.rowKey;
    return key == null ? i : key(_rowAt(i));
  }

  /// Where the row selected is shown; -1 for none. An index is found at
  /// once, a key of [Table.rowKey] out from where a key was found last.
  int _selectedIndex() {
    final key = _controller.selectedKey;
    if (key == null) {
      return -1;
    }
    _sort();
    if (key == _foundKey && _foundIn == _orderVersion) {
      return _found;
    }
    final count = _count;
    var found = -1;
    if (widget.rowKey == null) {
      if (key is int && key >= 0 && key < count) {
        found = _placeOf(key);
      }
    } else if (count > 0) {
      // a row below and a row above at a time
      final from = _near < count ? _near : count - 1;
      for (var d = 0; from + d < count || from - d > 0; d++) {
        final below = from + d;
        if (below < count && _keyAt(below) == key) {
          found = below;
          break;
        }
        final above = from - d - 1;
        if (above >= 0 && _keyAt(above) == key) {
          found = above;
          break;
        }
      }
    }
    _foundKey = key;
    _foundIn = _orderVersion;
    if (found >= 0) {
      _near = found;
    }
    return _found = found;
  }

  /// Selects the row shown at [index], within the rows, and scrolls it
  /// into view; whether that is another row.
  bool _select(int index) {
    final count = _count;
    if (count == 0) {
      return false;
    }
    final at = index < 0 ? 0 : (index >= count ? count - 1 : index);
    final key = _keyAt(at);
    final moved = key != _controller.selectedKey;
    _foundKey = key;
    _foundIn = _orderVersion;
    _found = at;
    _near = at;
    _controller.selectedKey = key;
    _list.ensureIndexVisible(at);
    return moved;
  }

  /// Selects the row [by] rows from the one selected, from none the first;
  /// whether that is another row.
  bool _move(int by) {
    final at = _selectedIndex();
    return _select(at < 0 ? 0 : at + by);
  }

  /// The rows of a window.
  int get _page {
    final rows = _list.hasClients ? _list.position.viewportExtent : 1;
    final per = widget.rowHeight ?? 1;
    return rows ~/ per > 1 ? rows ~/ per : 1;
  }

  /// Selects the cell [by] columns from the one selected; whether there is
  /// one there.
  bool _moveColumn(int by) {
    final c = _controller;
    final to = c.selectedColumn + by;
    if (to < 0 || to >= widget.columns.length) {
      return false;
    }
    c.selectedColumn = to;
    return true;
  }

  /// Scrolls the rows [by] rows, [Table.rowHeight] tall; whether they
  /// moved.
  bool _scroll(int by) =>
      _list.hasClients &&
      _scrollTo(_list.offset + by * (widget.rowHeight ?? 1));

  /// Scrolls the rows to [offset]; whether they moved.
  bool _scrollTo(int offset) {
    if (!_list.hasClients) {
      return false;
    }
    final from = _list.offset;
    _list.jumpTo(offset);
    return _list.offset != from;
  }

  /// Calls [Table.onActivated] with the row selected; whether there is
  /// one.
  bool _activate() {
    final at = _selectedIndex();
    final activated = widget.onActivated;
    if (at < 0 || activated == null) {
      return false;
    }
    activated(_rowAt(_order?[at] ?? at));
    return true;
  }

  /// Sorts by [column], the other way when the rows are sorted by it;
  /// whether the column sorts.
  bool _sortOn(int column) {
    if (column >= widget.columns.length ||
        widget.columns[column].compare == null) {
      return false;
    }
    final c = _controller;
    c.sortBy(column, ascending: c.sortColumn != column || !c.sortAscending);
    return true;
  }

  /// `s`: by the column of the cell selected, or the one sorted by, or the
  /// first that sorts.
  bool _sortHere() {
    if (widget.selection == TableSelection.cell) {
      return _sortOn(_controller.selectedColumn);
    }
    if (_sorted case final column?) {
      return _sortOn(column);
    }
    return _sortNext(1);
  }

  /// `<` and `>`: by the column that sorts before or after the one sorted
  /// by; whether there is one.
  bool _sortNext(int step) {
    final columns = widget.columns;
    var i = _sorted ?? (step > 0 ? -1 : columns.length);
    for (i += step; i >= 0 && i < columns.length; i += step) {
      if (columns[i].compare != null) {
        _controller.sortBy(i);
        return true;
      }
    }
    return false;
  }

  /// Shift+Left and Shift+Right: makes the column of the cell selected,
  /// or the one sorted by, or the first, [by] cells wider; whether that is
  /// another width.
  bool _resizeBy(int by) {
    final column = widget.selection == TableSelection.cell
        ? _controller.selectedColumn
        : (_sorted ?? 0);
    final width = _widthOf(column);
    return width != null && _resize(column, width + by);
  }

  /// The width of [column]: as it was made, or else as laid out last;
  /// null for none.
  int? _widthOf(int column) {
    if (column >= widget.columns.length) {
      return null;
    }
    if (_controller._widths[column] case final width?) {
      return _within(widget.columns[column].width, width);
    }
    final widths = _columns.widths;
    return column < widths.length ? widths[column] : null;
  }

  /// Makes [column] [width] cells wide, within its bounds; whether that is
  /// another width.
  bool _resize(int column, int width) {
    final from = _widthOf(column);
    if (from == null) {
      return false;
    }
    final to = _within(widget.columns[column].width, width);
    if (to == from) {
      return false;
    }
    _controller.resizeColumn(column, to);
    return true;
  }

  /// The column the rows are sorted by; null for none.
  int? get _sorted {
    final column = _controller.sortColumn;
    return column != null &&
            column < widget.columns.length &&
            widget.columns[column].compare != null
        ? column
        : null;
  }

  static final List<(String, KeyCombo)> _combos = [
    for (final key in [
      'up',
      'down',
      'pageup',
      'pagedown',
      'home',
      'end',
      'left',
      'right',
      'enter',
      's',
      '<',
      '>',
      'shift+left',
      'shift+right',
    ])
      (key, KeyCombo.parse(key)),
  ];

  /// What [key] does as [Table.selection] says: whether it did anything;
  /// null for a key that does nothing in it.
  bool? _do(String key) {
    final selection = widget.selection;
    final none = selection == TableSelection.none;
    final cells = selection == TableSelection.cell;
    return switch (key) {
      'up' => none ? _scroll(-1) : _move(-1),
      'down' => none ? _scroll(1) : _move(1),
      'pageup' => none ? _scroll(-_page) : _move(-_page),
      'pagedown' => none ? _scroll(_page) : _move(_page),
      'home' => none ? _scrollTo(0) : _select(0),
      'end' => none ? _scrollTo(_list.position.maxOffset) : _select(_count - 1),
      'left' when cells => _moveColumn(-1),
      'right' when cells => _moveColumn(1),
      'enter' when !none => _activate(),
      's' => _sortHere(),
      '<' => _sortNext(-1),
      '>' => _sortNext(1),
      'shift+left' => _resizeBy(-1),
      'shift+right' => _resizeBy(1),
      _ => null,
    };
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // only while it has the focus, whichever keys reach its node
    if (event.kind == KeyKind.release || !node.hasFocus) {
      return KeyEventResult.ignored;
    }
    for (final (key, combo) in _combos) {
      if (combo.accepts(event)) {
        if (_do(key) case final did?) {
          return did ? KeyEventResult.handled : KeyEventResult.ignored;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  // a press on the edge of a column resizes it, on a title sorts by it
  void _headerDown(PointerEvent event) {
    if (event.button != 0) {
      return;
    }
    if (_columns.edgeAt(event.x) case final column?) {
      _resizing = column;
      _resizedFrom = _widthOf(column) ?? 0;
      _pressedAt = event.x;
    } else if (_columns.at(event.x) case final column?) {
      _sortOn(column);
    }
  }

  void _headerDrag(PointerEvent event) {
    if (_resizing case final column?) {
      _resize(column, _resizedFrom + event.x - _pressedAt);
    }
  }

  void _headerUp(PointerEvent event) => _resizing = null;

  // the mouse over the header, or out of it (null): over an edge or not
  void _headerHover(PointerEvent? event) {
    final edge = event == null ? null : _columns.edgeAt(event.x);
    if (edge != _edgeHovered) {
      setState(() => _edgeHovered = edge);
    }
  }

  void _rowDown(int index, PointerEvent event) {
    if (event.button != 0) {
      return;
    }
    if (_node.canRequestFocus) {
      _node.requestFocus();
    }
    if (widget.selection == TableSelection.cell) {
      if (_columns.at(event.x) case final column?) {
        _controller.selectedColumn = column;
      }
    }
    _select(index);
  }

  /// The cells each content column wants, as [segmenter] measures them,
  /// in a table [height] rows tall.
  List<int> _measure(TextSegmenter? segmenter, int height) {
    final columns = widget.columns;
    final data = _data;
    final mode = segmenter?.mode ?? TextMode.graphemes;
    final ambiguous = segmenter?.ambiguousWidth ?? 1;
    if (data == _wantsData &&
        identical(columns, _wantsColumns) &&
        mode == _wantsMode &&
        ambiguous == _wantsAmbiguous) {
      return _wants;
    }
    _wantsData = data;
    _wantsColumns = columns;
    _wantsMode = mode;
    _wantsAmbiguous = ambiguous;
    final width = (segmenter ?? TextSegmenter()).width;
    final measures = columns.any(
      (c) => c.width.kind == GridTrackKind.content,
    );
    final rows = measures ? _measured(height) : <T>[];
    return _wants = [
      for (final column in columns)
        if (column.width.kind != GridTrackKind.content)
          0
        else
          _want(column, rows, width),
    ];
  }

  /// The rows a content column is measured by in a table [height] rows
  /// tall: all of them, or of more than [Table.sampleRows] and those in
  /// view, those in view and the sample spread evenly over all of them.
  List<T> _measured(int height) {
    final count = _count;
    final per = widget.rowHeight ?? 1;
    final shown = height ~/ per + 1;
    final sample = widget.sampleRows;
    final source = widget.source;
    if (count <= shown + sample) {
      return source == null
          ? widget.rows!
          : List<T>.generate(count, source.rowAt, growable: false);
    }
    // the row at the top of the list, rows of no height taken a row tall
    final first = _list.hasClients ? _list.offset ~/ per : 0;
    final order = _order;
    final indices = <int>{
      for (var i = first; i < first + shown && i < count; i++) order?[i] ?? i,
      for (var k = 0; k < sample; k++) k * count ~/ sample,
    };
    return [for (final i in indices) _rowAt(i)];
  }

  /// The widest of [column]'s title, with its sort mark, and the text of
  /// its cells, as [width] measures text.
  static int _want<T>(
    TableColumn<T> column,
    List<T> rows,
    int Function(String text) width,
  ) {
    var want = width(column.title) + (column.compare == null ? 0 : 2);
    for (final row in rows) {
      final cell = column.cell(row);
      var w = 0;
      if (cell.text case final text?) {
        w = width(text);
      } else if (cell.spans case final spans?) {
        for (final span in spans) {
          w += width(span.text);
        }
      }
      want = w > want ? w : want;
    }
    return want;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final theme = Theme.of(context);
    final focused = _node.hasFocus;
    final base = opaque(
      theme.background.merge(theme.text).merge(w.style ?? const Style()),
    );
    final styles = _Styles(
      base: base,
      header: base.merge(w.headerStyle ?? const Style(attrs: Attr.bold)),
      border: w.borderStyle ?? theme.border,
      selected: focused
          ? w.selectedStyle ?? theme.selection
          : w.unfocusedSelectedStyle ?? w.selectedStyle ?? theme.selectionIdle,
      cursor: w.cursorStyle ?? theme.fill(theme.primary.fg),
    );
    final columns = w.columns;
    _sort();
    _styles = styles;
    _shownSelected = _selectedIndex();
    _shownCursor = _cursor;
    _builtFor = _controller;
    _builtArranged = _controller._arranged;
    return Focus(
      focusNode: _node,
      autofocus: w.autofocus,
      canRequestFocus: w.canRequestFocus,
      onKeyEvent: _onKey,
      child: _Layout(
        columns: _columns,
        tracks: [
          for (var j = 0; j < columns.length; j++)
            switch (_controller._widths[j]) {
              final width? => GridTrack.fixed(_within(columns[j].width, width)),
              null => columns[j].width,
            },
        ],
        gap: w.columnGap,
        measured: (_data, columns),
        measure: _measure,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (w.showHeader)
              _shaped(
                Listener(
                  onDown: _headerDown,
                  onDrag: _headerDrag,
                  onUp: _headerUp,
                  child: _Row(
                    columns: _columns,
                    lines: w.border,
                    rule: w.border != BorderType.none,
                    background: styles.base,
                    style: styles.header,
                    lineStyle: styles.border,
                    children: [
                      for (var j = 0; j < columns.length; j++)
                        _title(columns[j], j, styles.header),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: _count,
                itemExtent: w.rowHeight,
                controller: _list,
                canRequestFocus: false,
                style: w.style,
                itemBuilder: (context, i) => _slot(i),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// [header] in a region whose pointer is [PointerShape.ewResize] over
  /// the edge of a column, with [Table.pointerShapes] where the terminal
  /// shows the pointer's shape; [header] alone otherwise, so that the
  /// mouse's motion is not reported for nothing.
  Widget _shaped(Widget header) {
    final shows =
        widget.pointerShapes &&
        (TerminalStatus.of(context)?.showsPointerShape ?? false);
    if (!shows) {
      _edgeHovered = null;
      return header;
    }
    return MouseRegion(
      onEnter: _headerHover,
      onHover: _headerHover,
      onExit: (_) => _headerHover(null),
      cursor: _edgeHovered == null ? null : PointerShape.ewResize,
      child: header,
    );
  }

  /// The title of [column], the [index]th, marked when the rows are
  /// sorted by it.
  Widget _title(TableColumn<T> column, int index, Style style) {
    final title = Text(
      column.title,
      style: style,
      wrap: TextWrap.none,
      overflow: column.overflow,
      maxLines: 1,
      align: column.align,
    );
    if (index != _sorted) {
      return title;
    }
    return Row(
      mainAxisAlignment: switch (column.align) {
        TextAlign.center => MainAxisAlignment.center,
        TextAlign.right || TextAlign.end => MainAxisAlignment.end,
        _ => MainAxisAlignment.start,
      },
      children: [
        Flexible(child: title),
        Text(_controller.sortAscending ? ' ▴' : ' ▾', style: style),
      ],
    );
  }

  /// The row shown at [index], keyed by its key, which builds itself
  /// again when the selection enters or leaves it.
  Widget _slot(int index) {
    final at = _order?[index] ?? index;
    final row = _rowAt(at);
    return _RowSlot<T>(
      key: ValueKey<Object>(widget.rowKey?.call(row) ?? at),
      table: this,
      index: index,
      row: row,
    );
  }

  /// [row], shown at [index]: in the selected style when it is the row
  /// selected, the cell of the cursor in the cursor's; [onDown] a press on
  /// it.
  Widget _row(int index, T row, void Function(PointerEvent event) onDown) {
    final w = widget;
    final styles = _styles;
    final selected = index == _shownSelected;
    final cursor = _shownCursor;
    final columns = w.columns;
    final style = selected ? styles.base.merge(styles.selected) : styles.base;
    return Listener(
      onDown: w.selection == TableSelection.none ? null : onDown,
      // the hidden cursor on the selected row, on its cursor's cell
      child: ActiveItem(
        active: selected,
        child: _Row(
          columns: _columns,
          lines: w.border,
          background: styles.base,
          style: style,
          lineStyle: styles.border,
          highlight: selected ? cursor : -1,
          highlightStyle: styles.cursor,
          children: [
            for (var j = 0; j < columns.length; j++)
              ActiveItem(
                active: selected && j == cursor,
                child: _cell(
                  columns[j],
                  columns[j].cell(row),
                  selected,
                  selected && j == cursor,
                  styles,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// [cell] of [column] in its style over the row's: in the selected
  /// style when [selected], and the cursor's when [cursor]; a widget's
  /// text in it too.
  static Widget _cell<T>(
    TableColumn<T> column,
    TableCell cell,
    bool selected,
    bool cursor,
    _Styles styles,
  ) {
    final style = _over(
      styles.base.merge(cell.style),
      styles,
      selected: selected,
      cursor: cursor,
    );
    if (cell.child case final child?) {
      return DefaultTextStyle(style: style, child: child);
    }
    final spans = cell.spans;
    final text = spans == null
        ? Text(
            cell.text!,
            style: style,
            wrap: TextWrap.none,
            overflow: column.overflow,
            maxLines: 1,
            align: column.align,
          )
        : Text.rich(
            [
              for (final s in spans)
                Span(
                  s.text,
                  _over(s.style, styles, selected: selected, cursor: cursor),
                ),
            ],
            style: style,
            wrap: TextWrap.none,
            overflow: column.overflow,
            maxLines: 1,
            align: column.align,
          );
    return cell._wrap?.call(text) ?? text;
  }

  /// The row's [styles] over a cell's [own]: the selected style when
  /// [selected], and the cursor's when [cursor].
  static Style _over(
    Style own,
    _Styles styles, {
    required bool selected,
    required bool cursor,
  }) {
    var s = own;
    if (selected) {
      s = s.merge(styles.selected);
    }
    return cursor ? s.merge(styles.cursor) : s;
  }
}

/// The row of a [Table] shown at [index]: what the table builds for it,
/// built again by itself when the selection enters or leaves it.
final class _RowSlot<T> extends StatefulWidget {
  const _RowSlot({
    required super.key,
    required this.table,
    required this.index,
    required this.row,
  });

  final _TableState<T> table;
  final int index;
  final T row;

  @override
  State<_RowSlot<T>> createState() => _RowSlotState<T>();
}

final class _RowSlotState<T> extends State<_RowSlot<T>> {
  @override
  void initState() {
    super.initState();
    widget.table._rows[widget.index] = this;
  }

  @override
  void didUpdateWidget(_RowSlot<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index ||
        !identical(oldWidget.table, widget.table)) {
      _forget(oldWidget);
      widget.table._rows[widget.index] = this;
    }
  }

  @override
  void dispose() {
    _forget(widget);
    super.dispose();
  }

  // another row's slot may have taken the place since
  void _forget(_RowSlot<T> slot) {
    final rows = slot.table._rows;
    if (identical(rows[slot.index], this)) {
      rows.remove(slot.index);
    }
  }

  /// Builds the row again, unless it is out of view, kept by the list: it
  /// is built as it comes back.
  void _rebuild() {
    if ((context as Element).slot != null) {
      setState(() {});
    }
  }

  // made once, not at each build
  late final void Function(PointerEvent event) _down = _onDown;

  void _onDown(PointerEvent event) =>
      widget.table._rowDown(widget.index, event);

  @override
  Widget build(BuildContext context) =>
      widget.table._row(widget.index, widget.row, _down);
}

/// The widths of columns [tracks], [gap] cells apart, in [available]
/// cells, the content columns wanting [wants] (see [Table]); along an
/// unbounded axis, the content columns at what they want and the fraction
/// columns at their minimum.
List<int> _columnWidths(
  List<GridTrack> tracks,
  List<int> wants,
  int available,
  int gap,
) {
  final count = tracks.length;
  final sizes = List<int>.filled(count, 0);
  final limits = List<int>.filled(count, 0);
  var free = available - (count > 1 ? gap * (count - 1) : 0);
  for (var i = 0; i < count; i++) {
    final t = tracks[i];
    sizes[i] = t.min;
    limits[i] = t.kind == GridTrackKind.content
        ? _clamp(wants[i], t.min, t.max)
        : t.min;
    free -= t.min;
  }
  if (available >= BoxConstraints.unbounded) {
    return limits;
  }
  // the content columns grow by even parts towards what they want
  while (free > 0) {
    var n = 0;
    var room = 0;
    for (var i = 0; i < count; i++) {
      final r = limits[i] - sizes[i];
      if (r > 0) {
        room = n == 0 || r < room ? r : room;
        n++;
      }
    }
    if (n == 0) {
      break;
    }
    final all = room * n <= free;
    final part = all ? room : free ~/ n;
    var extra = all ? 0 : free - part * n;
    for (var i = 0; i < count; i++) {
      if (limits[i] > sizes[i]) {
        var add = part;
        if (extra > 0) {
          add++;
          extra--;
        }
        sizes[i] += add;
        free -= add;
      }
    }
  }
  if (free > 0) {
    _share(tracks, sizes, free);
  }
  return sizes;
}

/// Shares [free] cells and those the fraction columns among [tracks] take
/// in [sizes] by their fractions, in whole cells, those left over going to
/// the first. A share beyond a column's bounds holds it at the bound and
/// the others share the rest: those below their minimum when the bounds
/// add more to the shares than they take, those above their maximum when
/// less, all of them when they even out (as CSS resolves flexible
/// lengths, and a grid its fraction tracks).
void _share(List<GridTrack> tracks, List<int> sizes, int free) {
  final count = tracks.length;
  // a column not held yet is -1 in sizes, its share in shares
  final shares = List<int>.filled(count, 0);
  var left = free;
  for (var i = 0; i < count; i++) {
    if (tracks[i].kind == GridTrackKind.fraction) {
      left += sizes[i];
      sizes[i] = -1;
    }
  }
  for (;;) {
    var parts = 0;
    for (var i = 0; i < count; i++) {
      if (sizes[i] < 0) {
        parts += tracks[i].fraction;
      }
    }
    if (parts == 0) {
      return;
    }
    var extra = left;
    for (var i = 0; i < count; i++) {
      if (sizes[i] < 0) {
        extra -= left * tracks[i].fraction ~/ parts;
      }
    }
    // the cells the bounds add to the shares, less those they take
    var off = 0;
    for (var i = 0; i < count; i++) {
      if (sizes[i] < 0) {
        final t = tracks[i];
        var share = left * t.fraction ~/ parts;
        if (extra > 0) {
          share++;
          extra--;
        }
        shares[i] = share;
        off += _clamp(share, t.min, t.max) - share;
      }
    }
    for (var i = 0; i < count; i++) {
      if (sizes[i] < 0) {
        final t = tracks[i];
        final share = shares[i];
        if (off == 0 || (off > 0 ? share < t.min : share > t.max)) {
          sizes[i] = _clamp(share, t.min, t.max);
          left -= sizes[i];
        }
      }
    }
  }
}

/// [v] within [lo]..[hi].
int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// [width] within the bounds of a column of [track] resized: at least a
/// cell, and a content or a fraction column's within its own.
int _within(GridTrack track, int width) {
  final fixed = track.kind == GridTrackKind.fixed;
  final lo = fixed || track.min < 1 ? 1 : track.min;
  final hi = fixed
      ? BoxConstraints.unbounded
      : (track.max < lo ? lo : track.max);
  return _clamp(width, lo, hi);
}

/// The columns of a [Table] as its [_RenderTable] laid them out last:
/// how wide each is ([widths]), where each starts ([starts]) and the
/// cells between two ([gap]); and the rows attached, which lay their
/// cells out by them and are laid out again when they change.
final class _Columns {
  var widths = const <int>[];

  /// Where each column starts, and after the last, where one more would.
  var starts = const <int>[0];

  var gap = 0;

  /// One more for each change.
  var version = 0;

  final rows = <_RenderTableRow>{};

  /// The cells of the columns and the gaps between them.
  int get total => widths.isEmpty ? 0 : starts[widths.length] - gap;

  /// Takes [w] and [g]; whether either is new.
  bool take(List<int> w, int g) {
    if (g == gap && sameList(w, widths)) {
      return false;
    }
    widths = w;
    gap = g;
    final s = List<int>.filled(w.length + 1, 0);
    for (var i = 0; i < w.length; i++) {
      s[i + 1] = s[i] + w[i] + g;
    }
    starts = s;
    version++;
    return true;
  }

  /// The column at [x] of a row; null for a gap or past the last.
  int? at(int x) {
    for (var i = 0; i < widths.length; i++) {
      if (x >= starts[i] && x < starts[i] + widths[i]) {
        return i;
      }
    }
    return null;
  }

  /// The column whose edge is at [x] of a row: the gap after it, or the
  /// cell after it without a gap; null for none.
  int? edgeAt(int x) {
    final edge = gap > 0 ? gap : 1;
    for (var i = 0; i < widths.length; i++) {
      final end = starts[i] + widths[i];
      if (x >= end && x < end + edge) {
        return i;
      }
    }
    return null;
  }
}

/// Lays [child], the header and the rows of a [Table], out with the
/// widths of the columns [tracks] it works out for its constraints into
/// [columns], [measure] giving what the content columns want.
final class _Layout extends SingleChildRenderObjectWidget {
  const _Layout({
    required this.columns,
    required this.tracks,
    required this.gap,
    required this.measured,
    required this.measure,
    super.child,
  });

  final _Columns columns;
  final List<GridTrack> tracks;
  final int gap;

  /// What [measure] measures: when it is new, it measures again.
  final Object measured;

  final List<int> Function(TextSegmenter? segmenter, int height) measure;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  _RenderTable createRenderObject(BuildContext context) => _RenderTable(
    columns: columns,
    tracks: tracks,
    gap: gap,
    measured: measured,
    measure: measure,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderTable renderObject) {
    renderObject
      ..tracks = tracks
      ..gap = gap
      ..measured = measured
      ..measure = measure;
  }
}

/// What lays a [Table] out: the widths of its columns, worked out for its
/// constraints into [columns] (see [Table]); then its child within the
/// same constraints, as big as it is. The rows attached are laid out
/// again in the same pass when the widths change, and those attached
/// later when they are next laid out.
final class _RenderTable extends RenderObject with RenderObjectWithChildMixin {
  _RenderTable({
    required this.columns,
    required this._tracks,
    required this._gap,
    required this._measured,
    required this.measure,
  });

  final _Columns columns;

  List<int> Function(TextSegmenter? segmenter, int height) measure;

  List<GridTrack> _tracks;
  List<GridTrack> get tracks => _tracks;
  set tracks(List<GridTrack> t) {
    if (!sameList(t, _tracks)) {
      _tracks = t;
      markNeedsLayout();
    }
  }

  int _gap;
  int get gap => _gap;
  set gap(int g) {
    if (g != _gap) {
      _gap = g;
      markNeedsLayout();
    }
  }

  Object _measured;
  Object get measured => _measured;
  set measured(Object m) {
    if (m != _measured) {
      _measured = m;
      markNeedsLayout();
    }
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMinIntrinsicHeight(int width) =>
      child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void performLayout(BoxConstraints c) {
    final widths = _columnWidths(
      _tracks,
      measure(owner?.segmenter, c.maxH),
      c.maxW,
      _gap,
    );
    if (columns.take(widths, _gap)) {
      // a row is a relayout boundary, which its own mark would leave to
      // the next frame: marked up to here, it is laid out below
      invokeLayoutCallback(() {
        for (final row in columns.rows) {
          for (RenderObject? o = row; o != null && !identical(o, this);) {
            o.markNeedsLayout();
            o = o.parent;
          }
        }
      });
    }
    final child = this.child;
    if (child == null) {
      width = c.minW;
      height = c.minH;
      return;
    }
    child.layout(c, parentUsesSize: true);
    width = c.constrainW(child.width);
    height = c.constrainH(child.height);
  }

  @override
  void paint(PaintContext ctx) {
    if (child case final child?) {
      paintChild(ctx, child);
    }
  }
}

/// A row of a [Table]: its cells, a child each, laid out by a
/// [_RenderTableRow] in [columns].
final class _Row extends MultiChildRenderObjectWidget {
  const _Row({
    required this.columns,
    required this.lines,
    required this.background,
    required this.style,
    required this.lineStyle,
    this.rule = false,
    this.highlight = -1,
    this.highlightStyle = const Style(),
    super.children,
  });

  final _Columns columns;
  final BorderType lines;
  final bool rule;
  final Style background;
  final Style style;
  final Style lineStyle;
  final int highlight;
  final Style highlightStyle;

  @override
  MultiChildRenderObjectElement createElement() => ChildListElement(this);

  @override
  _RenderTableRow createRenderObject(BuildContext context) =>
      _RenderTableRow(columns)
        ..lines = lines
        ..rule = rule
        ..background = background
        ..style = style
        ..lineStyle = lineStyle
        ..highlight = highlight
        ..highlightStyle = highlightStyle;

  @override
  void updateRenderObject(BuildContext context, _RenderTableRow renderObject) {
    renderObject
      ..lines = lines
      ..rule = rule
      ..background = background
      ..style = style
      ..lineStyle = lineStyle
      ..highlight = highlight
      ..highlightStyle = highlightStyle;
  }
}

final class _CellData extends ParentData with ContainerParentDataMixin {}

// the glyphs of the lines, as the canvas draws them
final _glyphs = ChartGlyphs();

/// What a row of a [Table] lays out and paints: its children, a cell
/// each, side by side in [columns], each laid out as wide as its column
/// and as tall as it likes within the row; the row as tall as its tallest
/// cell, at least a row, and with [rule] a row more under them. It fills
/// its cells with [style], over [background] where it lets that through,
/// the cell of the column [highlight] with [highlightStyle] over it, and
/// draws [lines] in [lineStyle] over [style] down the middle of each gap
/// and, with [rule], under the cells, joined where they cross:
/// [BorderType.ascii] where the canvas draws box drawing two columns wide.
/// What does not fit is cut off at its right.
final class _RenderTableRow extends RenderObject
    with ContainerRenderObjectMixin<_CellData> {
  _RenderTableRow(this.columns);

  final _Columns columns;

  // the version of the columns it was laid out by
  var _laidOutBy = -1;

  BorderType _lines = BorderType.none;
  BorderType get lines => _lines;
  set lines(BorderType l) {
    if (l != _lines) {
      _lines = l;
      markNeedsPaint();
    }
  }

  var _rule = false;
  bool get rule => _rule;
  set rule(bool r) {
    if (r != _rule) {
      _rule = r;
      markNeedsLayout();
    }
  }

  Style _background = opaque(const Style());

  /// What shows where [style] lets the background through: opaque, since
  /// the row paints over its own cells.
  Style get background => _background;
  set background(Style s) {
    if (s != _background) {
      _background = s;
      markNeedsPaint();
    }
  }

  var _style = const Style();
  Style get style => _style;
  set style(Style s) {
    if (s != _style) {
      _style = s;
      markNeedsPaint();
    }
  }

  var _lineStyle = const Style();
  Style get lineStyle => _lineStyle;
  set lineStyle(Style s) {
    if (s != _lineStyle) {
      _lineStyle = s;
      markNeedsPaint();
    }
  }

  var _highlight = -1;

  /// The column whose cell is in [highlightStyle]; -1 for none.
  int get highlight => _highlight;
  set highlight(int h) {
    if (h != _highlight) {
      _highlight = h;
      markNeedsPaint();
    }
  }

  var _highlightStyle = const Style();
  Style get highlightStyle => _highlightStyle;
  set highlightStyle(Style s) {
    if (s != _highlightStyle) {
      _highlightStyle = s;
      markNeedsPaint();
    }
  }

  @override
  void attach(PipelineOwner o) {
    super.attach(o);
    columns.rows.add(this);
    // the columns changed while it was out of the tree: a relayout
    // boundary, it is marked up to the list that lays it out
    if (_laidOutBy >= 0 && _laidOutBy != columns.version) {
      for (
        RenderObject? r = this;
        r != null && r is! RenderList && r is! _RenderTable;
        r = r.parent
      ) {
        r.markNeedsLayout();
      }
    }
  }

  @override
  void detach() {
    columns.rows.remove(this);
    super.detach();
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _CellData) {
      child.parentData = _CellData();
    }
  }

  /// Hit wherever it is: it paints all of its cells.
  @override
  HitTestBehavior get hitTestBehavior => HitTestBehavior.opaque;

  /// Its own: a row restyled, as the selection moves, repaints alone, and
  /// the list moves the others in hardware as it scrolls.
  @override
  bool get isRepaintBoundary => true;

  @override
  int computeMinIntrinsicWidth(int height) => columns.total;

  @override
  int computeMaxIntrinsicWidth(int height) => columns.total;

  @override
  int computeMinIntrinsicHeight(int width) => _height(min: true);

  @override
  int computeMaxIntrinsicHeight(int width) => _height(min: false);

  int _height({required bool min}) {
    final widths = columns.widths;
    var h = 1;
    var i = 0;
    for (var c = firstChild; c != null; c = childAfter(c), i++) {
      final w = i < widths.length ? widths[i] : 0;
      final ch = min ? c.getMinIntrinsicHeight(w) : c.getMaxIntrinsicHeight(w);
      h = ch > h ? ch : h;
    }
    return h + (_rule ? 1 : 0);
  }

  @override
  void performLayout(BoxConstraints c) {
    _laidOutBy = columns.version;
    final widths = columns.widths;
    final starts = columns.starts;
    final rule = _rule ? 1 : 0;
    final maxH = c.maxH >= BoxConstraints.unbounded
        ? c.maxH
        : (c.maxH - rule > 0 ? c.maxH - rule : 0);
    var h = 1;
    var i = 0;
    for (var child = firstChild; child != null; i++) {
      final w = i < widths.length ? widths[i] : 0;
      child.layout(BoxConstraints(w, w, 0, maxH), parentUsesSize: true);
      final at = child.parentData as _CellData
        ..dx = i < widths.length ? starts[i] : columns.total
        ..dy = 0;
      h = child.height > h ? child.height : h;
      child = at.nextSibling;
    }
    width = c.constrainW(columns.total);
    height = c.constrainH(h + rule);
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final styles = canvas.styles;
    final widths = columns.widths;
    final starts = columns.starts;
    final gap = columns.gap;
    final cells = _rule ? height - 1 : height;
    final fill = _style.penIn(styles);
    final through = styles.penOf(fill);
    if (through.bg == null || through.bgAlpha != 255) {
      canvas.fill(0, 0, width, height, _background.penIn(styles));
    }
    canvas.fill(0, 0, width, height, fill);
    if (_highlight >= 0 && _highlight < widths.length) {
      canvas.fill(
        starts[_highlight],
        0,
        widths[_highlight],
        cells,
        _style.merge(_highlightStyle).penIn(styles),
      );
    }
    for (var child = firstChild; child != null; child = childAfter(child)) {
      paintChild(ctx, child);
    }
    if (_lines == BorderType.none || gap == 0) {
      return;
    }
    _glyphs.use(canvas.segmenter);
    final type = _glyphs.lines(_lines);
    final pen = _style.merge(_lineStyle).penIn(styles);
    if (_rule) {
      canvas.fill(0, cells, width, 1, pen, type.glyph(left: true, right: true));
    }
    final down = type.glyph(up: true, down: true);
    final cross = type.glyph(up: true, down: true, left: true, right: true);
    for (var i = 0; i + 1 < widths.length; i++) {
      final x = starts[i + 1] - gap + (gap - 1) ~/ 2;
      canvas.fill(x, 0, 1, cells, pen, down);
      if (_rule) {
        canvas.fill(x, cells, 1, 1, pen, cross);
      }
    }
  }
}
