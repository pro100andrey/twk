part of 'tree.dart';

// Examples can assume:
// abstract class Proc {
//   String get name;
//   int get pid;
//   double get cpu;
//   List<Proc> get children;
// }
// late List<Proc> procs;

/// [roots] and their descendants as the rows of a [Table] in [columns]: a
/// tree whose nodes show their columns, as a process viewer, a file
/// manager with sizes and dates, or a browser of JSON or of dependencies
/// shows them.
///
/// The rows are those a [TreeView] of [roots], [children], [hasChildren]
/// and [nodeKey] shows, and the first of [columns] is its tree: before its
/// text each row shows the guides that join its node to its parent (with
/// [showGuides]: `├─`, `└─` for the last child, `│` down past the children
/// between them, [BorderType.ascii] where the terminal draws box drawing
/// two columns wide) and its expander, `▸` or `▾`, indented two cells a
/// level, always on the left of the column, whose [TableColumn.align] is
/// its title's alone. A node's children come as a [TreeView]'s do, those
/// in a future with a spinner row below the node until it ends, then
/// kept by key until [TreeController.reload], or a row with the error it
/// failed with; such a row has nothing in the other columns, and is not
/// selected: the keys go past it, and a click on it selects its node.
///
/// The columns are a [Table]'s, sized, measured (the first with its guides
/// and its expander), resized and drawn as there, and sorted as there
/// with one difference: the rows are sorted within their parents, each
/// node's children among themselves by the column's [TableColumn.compare]
/// and every node above its children, in either direction; equal children
/// keep the order [children] gives them. The rows are a [Table]'s too:
/// only those in view and a few rows past them are built, so a tree of a
/// hundred thousand nodes, ten thousand of them shown, scrolls as a table
/// of ten thousand rows does, and the selection moved builds again the row
/// it left and the row it entered alone. Each change of the nodes
/// expanded, each load that ends and each new widget whose nodes shown
/// are not those of the last walks the nodes shown again, and measures
/// and sorts them again as a [Table] does its rows.
///
/// [controller] holds the nodes expanded and the node selected, by key, as
/// for a [TreeView]: a node stays selected while it is sorted, and while
/// the nodes above it expand and collapse. [tableController] holds the
/// column the rows are sorted by, the widths the columns were given and
/// the column of the cell selected; its [TableController.selectedKey]
/// follows the node selected, and the node selected follows it.
///
/// The keys and the mouse are a [Table]'s, [selection] a row or a cell,
/// and a [TreeView]'s besides: while it has the focus, Right expands the
/// node selected, or selects its first child shown when it is expanded,
/// and Left collapses it, or selects its parent when it is collapsed
/// (with [TableSelection.row]: with [TableSelection.cell] they move the
/// cell), `+` expands it, `-` collapses it and `*` expands it and every
/// node below it; Enter calls [onActivated] with the node selected, or
/// without one expands or collapses it. A click on a node's expander, in
/// the tree's column, expands or collapses it, as it selects it. A node
/// collapsed by a key or a click is selected when the node selected was
/// below it. With [TableSelection.none] the keys scroll the rows, as a
/// [Table]'s do, and neither select, expand, collapse nor activate a node;
/// a click selects nothing, and on an expander expands or collapses its
/// node alone.
///
/// The styles are a [Table]'s: [style], [headerStyle], [borderStyle],
/// [selectedStyle], [unfocusedSelectedStyle] and [cursorStyle], and
/// [guideStyle] for the guides ([ThemeData.border] when null), under the
/// row's; a failed load's error is in [ThemeData.error].
///
/// It takes all the room it is given, which must be bounded.
///
/// Processes under their parents, by name and by how much of the CPU they
/// take, which a click on its title sorts by:
///
/// ```dart
/// TreeTable<Proc>(
///   roots: procs,
///   children: (p) => p.children,
///   hasChildren: (p) => p.children.isNotEmpty,
///   nodeKey: (p) => p.pid,
///   columns: [
///     TableColumn(title: 'Name', cell: (p) => TableCell(p.name)),
///     TableColumn(
///       title: 'CPU %',
///       align: TextAlign.right,
///       cell: (p) => TableCell(p.cpu.toStringAsFixed(1)),
///       compare: (a, b) => a.cpu.compareTo(b.cpu),
///     ),
///   ],
/// )
/// ```
///
/// See also:
///
///  * [TreeView], the same nodes without columns.
///  * [Table], rows that are not a tree.
final class TreeTable<T> extends StatefulWidget {
  /// Shows [roots] and the children of those [controller] expands as the
  /// rows of a table in [columns]; asserts what [Table.new] does of
  /// [columnGap], [border] and [sampleRows].
  const TreeTable({
    required this.roots,
    required this.children,
    required this.columns,
    super.key,
    this.hasChildren,
    this.nodeKey,
    this.controller,
    this.tableController,
    this.selection = TableSelection.row,
    this.onActivated,
    this.showGuides = true,
    this.columnGap = 1,
    this.border = BorderType.none,
    this.showHeader = true,
    this.sampleRows = Table.defaultSampleRows,
    this.focusNode,
    this.autofocus = false,
    this.canRequestFocus,
    this.style,
    this.headerStyle,
    this.borderStyle,
    this.guideStyle,
    this.selectedStyle,
    this.unfocusedSelectedStyle,
    this.cursorStyle,
    this.pointerShapes = true,
  }) : assert(columnGap >= 0, 'a gap of 0 cells or more'),
       assert(
         border == BorderType.none || columnGap > 0,
         'a gap for the lines between the columns',
       ),
       assert(sampleRows >= 0, 'a sample of 0 rows or more');

  /// The nodes at the top, in order.
  final List<T> roots;

  /// The children of a node, in order: a list, or a future of one.
  // called with the nodes, whose T is the table's own
  // ignore: unsafe_variance
  final FutureOr<List<T>> Function(T node) children;

  /// The columns, the first the tree's.
  final List<TableColumn<T>> columns;

  /// Whether a node has children, without asking for them; null asks
  /// [children].
  // ignore: unsafe_variance
  final bool Function(T node)? hasChildren;

  /// The key of a node, which the controllers expand and select and its
  /// row keeps its [State] by; null for the node itself.
  // ignore: unsafe_variance
  final Object Function(T node)? nodeKey;

  /// What is expanded and selected; null for one of its own.
  final TreeController? controller;

  /// The order, the widths of the columns and the column of the cell
  /// selected; null for one of its own.
  final TableController? tableController;

  /// What the keys and the mouse select: a row, a cell, or nothing, the
  /// keys scrolling the rows.
  final TableSelection selection;

  /// Called with the node selected when Enter is pressed.
  // ignore: unsafe_variance
  final void Function(T node)? onActivated;

  /// Whether lines join the nodes to their parents.
  final bool showGuides;

  /// See [Table.columnGap].
  final int columnGap;

  /// See [Table.border].
  final BorderType border;

  /// See [Table.showHeader].
  final bool showHeader;

  /// See [Table.sampleRows].
  final int sampleRows;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// See [FocusNode.canRequestFocus].
  final bool? canRequestFocus;

  /// See [Table.style].
  final Style? style;

  /// See [Table.headerStyle].
  final Style? headerStyle;

  /// See [Table.borderStyle].
  final Style? borderStyle;

  /// The guides; [ThemeData.border] when null.
  final Style? guideStyle;

  /// See [Table.selectedStyle].
  final Style? selectedStyle;

  /// See [Table.unfocusedSelectedStyle].
  final Style? unfocusedSelectedStyle;

  /// See [Table.cursorStyle].
  final Style? cursorStyle;

  /// See [Table.pointerShapes].
  final bool pointerShapes;

  @override
  State<TreeTable<T>> createState() => _TreeTableState<T>();
}

/// The rows of a [TreeTable] for its [Table]: each the index of a row of
/// the nodes shown, which its state works out.
final class _TreeSource<T> extends TableSource<int> {
  _TreeSource(this._state);

  final _TreeTableState<T> _state;

  @override
  int get rowCount => _state._shown.length;

  @override
  int rowAt(int index) => index;

  /// The nodes shown changed.
  void changed() => notifyListeners();
}

final class _TreeTableState<T> extends State<TreeTable<T>>
    with _TreeModel<T, TreeTable<T>> {
  TreeController? _own;
  TableController? _ownTable;

  @override
  TreeController get _controller =>
      widget.controller ?? (_own ??= TreeController());

  TableController get _table =>
      widget.tableController ?? (_ownTable ??= TableController());

  @override
  List<T> get _roots => widget.roots;

  @override
  // called with the nodes, whose T is the state's own
  // ignore: unsafe_variance
  FutureOr<List<T>> Function(T node) get _childrenOf => widget.children;

  @override
  // as is this
  // ignore: unsafe_variance
  bool Function(T node)? get _hasChildren => widget.hasChildren;

  @override
  // as is this
  // ignore: unsafe_variance
  Object Function(T node)? get _nodeKey => widget.nodeKey;

  // the rows the table shows, the state's own; another source for nodes
  // shown that are not those of the last widget
  late var _source = _TreeSource<T>(this);

  // the nodes shown before a new widget, until it is built
  _Rows<T>? _before;

  // the version of the controller the source last told of
  var _told = -1;

  // the columns of the table, and those they were made of
  var _inner = const <TableColumn<int>>[];
  List<TableColumn<T>>? _innerOf;

  // what the tree's column draws with, as worked out at the last build:
  // the guides' style and pieces, the error's style
  var _guideStyle = const Style();
  var _errorStyle = const Style();
  var _down = '│ ';
  var _tee = '├─';
  var _corner = '└─';
  var _across = '─';

  // a selection of the row of a load moved to a node's in this turn of
  // the event loop, as a key or a press on it made it; the key of the
  // load's node
  var _moved = false;
  Object? _leftLoadOf;

  // the row whose expander a press is on, in the rows it was built in, for
  // the press's handler after the table's
  _Rows<T>? _expanderOf;
  var _expanderAt = -1;

  @override
  void initState() {
    super.initState();
    _told = _controller._version;
    _controller.addListener(_treeChanged);
    _table
      ..addListener(_tableChanged)
      ..selectedKey = _controller.selectedKey;
  }

  @override
  void didUpdateWidget(TreeTable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      (oldWidget.controller ?? _own)?.removeListener(_treeChanged);
      _controller.addListener(_treeChanged);
      _told = _controller._version;
    }
    if (!identical(widget.tableController, oldWidget.tableController)) {
      (oldWidget.tableController ?? _ownTable)?.removeListener(_tableChanged);
      _table.addListener(_tableChanged);
    }
    if (!identical(widget.controller, oldWidget.controller) ||
        !identical(widget.tableController, oldWidget.tableController)) {
      _table.selectedKey = _controller.selectedKey;
    }
    _before ??= _rows;
  }

  @override
  void dispose() {
    _controller.removeListener(_treeChanged);
    _table.removeListener(_tableChanged);
    _own?.dispose();
    _ownTable?.dispose();
    _source.dispose();
    super.dispose();
  }

  @override
  void _loadEnded() => _source.changed();

  /// The tree controller changed: the table selects its node, and the rows
  /// are told of when it expanded or collapsed one.
  void _treeChanged() {
    final c = _controller;
    _table.selectedKey = c.selectedKey;
    if (c._version != _told) {
      _told = c._version;
      _source.changed();
    }
  }

  /// The table controller changed: the node it selects is selected, a node
  /// for the row of a load.
  void _tableChanged() {
    final key = _table.selectedKey;
    if (key is _LoadKey) {
      _leaveLoad(key);
    } else {
      _controller.selectedKey = key;
    }
  }

  /// The table selected the row of the load of [key]'s children: the
  /// selection goes on past it, coming from above, else to the node.
  void _leaveLoad(_LoadKey key) {
    final rows = _shown;
    final load = rows.keys.indexOf(key);
    if (load < 0) {
      _table.selectedKey = _controller.selectedKey;
      return;
    }
    final node = rows.parent(load);
    final from = _selectedRow(rows);
    var to = from >= 0 && _shownBefore(rows, from, load)
        ? _nextAfter(rows, node)
        : -1;
    if (to < 0) {
      to = node;
    }
    _leftLoadOf = key.key;
    if (!_moved) {
      _moved = true;
      scheduleMicrotask(() => _moved = false);
    }
    _select(rows, to);
  }

  @override
  bool _select(_Rows<T> rows, int i) {
    final key = rows.keys[i];
    final moved = key != _controller.selectedKey;
    _foundKey = key;
    _foundIn = rows;
    _found = i;
    _controller.selectedKey = key;
    // the same key again: the table may have selected a load's row
    _table.selectedKey = key;
    return moved;
  }

  /// What the rows are sorted by within their parents; null for the order
  /// [TreeTable.children] gives.
  // called with the nodes, whose T is the state's own
  // ignore: unsafe_variance
  Comparator<T>? get _sortCompare {
    final column = _table.sortColumn;
    final columns = widget.columns;
    return column != null && column < columns.length
        ? columns[column].compare
        : null;
  }

  /// Whether row [a] of [rows] shows before row [b].
  bool _shownBefore(_Rows<T> rows, int a, int b) {
    final compare = _sortCompare;
    if (compare == null) {
      return a < b;
    }
    final ascending = _table.sortAscending;
    final d = _treeOrder(rows, compare, a, b, ascending: ascending);
    return d != 0 ? (ascending ? d < 0 : d > 0) : a < b;
  }

  // which rows show last of their parent's, sorted; the rows, the compare
  // and the order it was worked out for
  var _lasts = const <bool>[];
  _Rows<T>? _lastsOf;
  Object? _lastsBy;
  var _lastsAscending = true;

  /// Whether row [i] of [rows] shows last of its parent's.
  bool _lastShown(_Rows<T> rows, int i) {
    final compare = _sortCompare;
    if (compare == null) {
      return rows.last(i);
    }
    final ascending = _table.sortAscending;
    if (!identical(rows, _lastsOf) ||
        !identical(compare, _lastsBy) ||
        ascending != _lastsAscending) {
      _lastsOf = rows;
      _lastsBy = compare;
      _lastsAscending = ascending;
      // the row shown last of each parent's, by the parent's row, from -1
      final last = List<int>.filled(rows.length + 1, -1);
      for (var j = 0; j < rows.length; j++) {
        final p = rows.parent(j) + 1;
        if (last[p] < 0 || _shownBefore(rows, last[p], j)) {
          last[p] = j;
        }
      }
      final lasts = _lasts = List<bool>.filled(rows.length, false);
      for (final j in last) {
        if (j >= 0) {
          lasts[j] = true;
        }
      }
    }
    return _lasts[i];
  }

  /// The row shown first after those below row [i] of [rows]; -1 for none.
  int _nextAfter(_Rows<T> rows, int i) {
    for (var r = i; r >= 0; r = rows.parent(r)) {
      final p = rows.parent(r);
      var next = -1;
      for (
        var j = p + 1, end = p < 0 ? rows.length : rows.end(p);
        j < end;
        j = rows.end(j)
      ) {
        if (j != r &&
            _shownBefore(rows, r, j) &&
            (next < 0 || _shownBefore(rows, j, next))) {
          next = j;
        }
      }
      if (next >= 0) {
        return next;
      }
    }
    return -1;
  }

  /// The first of the children of row [at] as they show, sorted.
  @override
  int _firstChild(_Rows<T> rows, int at) {
    if (_sortCompare == null) {
      return super._firstChild(rows, at);
    }
    var first = -1;
    for (var j = at + 1, end = rows.end(at); j < end; j = rows.end(j)) {
      if (first < 0 || _shownBefore(rows, j, first)) {
        first = j;
      }
    }
    return first >= 0 && rows.isNode(first) ? first : -1;
  }

  /// The order of rows [a] and [b] of [rows] by [compare] within their
  /// parents, as a [Table] sorting [ascending] or not takes it (it turns
  /// the order the other way when not, and keeps that of the rows for
  /// equal ones): the order of the nodes above them that are siblings,
  /// and of one above the other, the one above first either way.
  static int _treeOrder<T>(
    _Rows<T> rows,
    Comparator<T> compare,
    int a,
    int b, {
    required bool ascending,
  }) {
    if (a == b) {
      return 0;
    }
    var x = a;
    var y = b;
    var dx = rows.depth(x);
    var dy = rows.depth(y);
    for (; dx > dy; dx--) {
      x = rows.parent(x);
    }
    for (; dy > dx; dy--) {
      y = rows.parent(y);
    }
    if (x == y) {
      final above = rows.depth(a) < rows.depth(b);
      return above == ascending ? -1 : 1;
    }
    while (rows.parent(x) != rows.parent(y)) {
      x = rows.parent(x);
      y = rows.parent(y);
    }
    return compare(rows.nodes[x], rows.nodes[y]);
  }

  /// The columns of the table: the first the tree's, each sorting the
  /// rows within their parents.
  List<TableColumn<int>> _columns() {
    final columns = widget.columns;
    if (identical(columns, _innerOf)) {
      return _inner;
    }
    _innerOf = columns;
    return _inner = [
      for (var j = 0; j < columns.length; j++)
        _column(columns[j], tree: j == 0),
    ];
  }

  TableColumn<int> _column(TableColumn<T> column, {required bool tree}) {
    final compare = column.compare;
    return TableColumn<int>(
      title: column.title,
      width: column.width,
      align: tree ? TextAlign.left : column.align,
      overflow: column.overflow,
      compare: compare == null
          ? null
          : (a, b) => _treeOrder(
              _shown,
              compare,
              a,
              b,
              ascending: _table.sortAscending,
            ),
      cell: tree
          ? (i) => _treeCell(column, i)
          : (i) {
              final rows = _shown;
              return rows.isNode(i) ? column.cell(rows.nodes[i]) : _blank;
            },
    );
  }

  static const _blank = TableCell('');

  /// The cell of [column], the tree's, of row [i]: its guides and expander,
  /// then what the column shows of the node; the spinner of a load, or its
  /// error.
  TableCell _treeCell(TableColumn<T> column, int i) {
    final rows = _shown;
    final mark = rows.mark(i);
    final level = rows.depth(i);
    final guides = StringBuffer();
    var expander = '';
    if (widget.showGuides && level > 0) {
      // for each depth from 1 below the row's, whether the guide of its
      // ancestor there goes on down past it: it does not show last
      final lines = List<bool>.filled(level - 1, false);
      for (
        var p = rows.parent(i);
        p >= 0 && rows.depth(p) >= 1;
        p = rows.parent(p)
      ) {
        lines[rows.depth(p) - 1] = !_lastShown(rows, p);
      }
      for (final down in lines) {
        guides.write(down ? _down : '  ');
      }
      guides.write(_lastShown(rows, i) ? _corner : _tee);
      if (mark == _Mark.leaf || mark == _Mark.failed) {
        guides.write(_across);
        expander = ' ';
      }
    } else {
      guides.write('  ' * level);
      if (mark == _Mark.leaf || mark == _Mark.failed) {
        expander = '  ';
      }
    }
    if (mark == _Mark.collapsed || mark == _Mark.expanded) {
      expander = mark == _Mark.expanded ? '▾ ' : '▸ ';
    }
    final before = [
      Span(guides.toString(), _guideStyle),
      if (expander.isNotEmpty) Span(expander),
    ];
    switch (mark) {
      case _Mark.loading:
        return TableCell.widget(
          Row(
            children: [
              Text.rich(before, wrap: TextWrap.none),
              const Spinner(),
            ],
          ),
        );
      case _Mark.failed:
        return TableCell.rich([
          ...before,
          Span('${rows.errors[i]}', _errorStyle),
        ]);
      case _Mark.leaf || _Mark.collapsed || _Mark.expanded:
        final cell = column.cell(rows.nodes[i]);
        final expands = mark != _Mark.leaf;
        if (cell.child case final child?) {
          final text = Text.rich(before, wrap: TextWrap.none);
          return TableCell.widget(
            Row(
              children: [
                if (expands) _expander(rows, i, text) else text,
                Expanded(child: child),
              ],
            ),
          );
        }
        final spans = [
          ...before,
          ...?cell.spans,
          if (cell.text case final text?) Span(text, cell.style),
        ];
        return expands
            ? wrappedTableCell(spans, (text) => _expander(rows, i, text))
            : TableCell.rich(spans);
    }
  }

  /// [text], which starts row [i] of [rows] in the tree's column, the
  /// row's expander two cells of it from its level's indent: a press there
  /// is the expander's, which [_pressed] takes after the table's. Inside
  /// the column only, however narrow it is.
  Widget _expander(_Rows<T> rows, int i, Widget text) => Listener(
    onDown: (event) {
      final x = rows.depth(i) * 2;
      if (event.button == 0 && event.x >= x && event.x < x + 2) {
        _expanderOf = rows;
        _expanderAt = i;
      }
    },
    child: text,
  );

  /// The guides drawn as [segmenter] draws them: box drawing, or ASCII
  /// where that is two columns wide.
  void _useGuides(TextSegmenter segmenter) {
    _glyphs.use(segmenter);
    final type = _glyphs.lines(BorderType.single);
    final across = String.fromCharCode(type.glyph(left: true, right: true));
    _down = '${String.fromCharCode(type.glyph(up: true, down: true))} ';
    _tee =
        String.fromCharCode(type.glyph(up: true, down: true, right: true)) +
        across;
    _corner = String.fromCharCode(type.glyph(up: true, right: true)) + across;
    _across = across;
  }

  /// A key the table left: Left and Right (selecting rows), `+`, `-`, `*`
  /// and Enter.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // only while the table has the focus, whichever keys reach its node
    if (event.kind == KeyKind.release || !node.hasFocus) {
      return KeyEventResult.ignored;
    }
    final selection = widget.selection;
    if (selection == TableSelection.none) {
      return KeyEventResult.ignored;
    }
    final rows = selection == TableSelection.row;
    for (final (key, combo) in _combos) {
      if (combo.accepts(event)) {
        final did = switch (key) {
          'left' => rows && _left(),
          'right' => rows && _right(),
          '+' => _expandSelected(expand: true),
          '-' => _expandSelected(expand: false),
          '*' => _expandAllSelected(),
          _ => _toggleSelected(),
        };
        return did ? KeyEventResult.handled : KeyEventResult.ignored;
      }
    }
    return KeyEventResult.ignored;
  }

  static final List<(String, KeyCombo)> _combos = [
    for (final key in ['left', 'right', '+', '-', '*', 'enter'])
      (key, KeyCombo.parse(key)),
  ];

  /// Enter without [TreeTable.onActivated]: expands or collapses the node
  /// selected.
  bool _toggleSelected() {
    final rows = _shown;
    final at = _selectedRow(rows);
    return at >= 0 && _toggle(rows, at);
  }

  /// Calls [TreeTable.onActivated] with the node of row [i].
  void _activated(int i) {
    final rows = _shown;
    if (rows.isNode(i)) {
      widget.onActivated?.call(rows.nodes[i]);
    }
  }

  /// The key of row [i].
  Object _keyAt(int i) => _shown.keys[i];

  /// A press, after the table's: one on the expander of a node expands
  /// or collapses it; one on the row of a load, which the table selected,
  /// selects its node.
  void _pressed(PointerEvent event) {
    final rows = _shown;
    final at = identical(_expanderOf, rows) ? _expanderAt : -1;
    _expanderOf = null;
    if (event.button != 0) {
      return;
    }
    if (_moved) {
      // the row of a load: its node
      final node = _leftLoadOf == null ? -1 : rows.keys.indexOf(_leftLoadOf!);
      if (node >= 0) {
        _select(rows, node);
      }
      return;
    }
    if (at >= 0) {
      _toggle(rows, at);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final theme = Theme.of(context);
    _guideStyle = w.guideStyle ?? theme.border;
    _errorStyle = theme.error;
    _useGuides(
      AppBinding.maybeOf(context)?.twkApp.owner.segmenter ?? _segmenter,
    );
    final rows = _shown;
    if (_before case final before?) {
      _before = null;
      if (!identical(rows, before) && !rows.same(before)) {
        // the table lets go of the old one as it is given the new
        _source.dispose();
        _source = _TreeSource<T>(this);
      }
    }
    return Listener(
      onDown: _pressed,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: Table<int>.source(
          source: _source,
          columns: _columns(),
          rowKey: _keyAt,
          controller: _table,
          selection: w.selection,
          onActivated: w.onActivated == null ? null : _activated,
          columnGap: w.columnGap,
          border: w.border,
          showHeader: w.showHeader,
          sampleRows: w.sampleRows,
          focusNode: w.focusNode,
          autofocus: w.autofocus,
          canRequestFocus: w.canRequestFocus,
          style: w.style,
          headerStyle: w.headerStyle,
          borderStyle: w.borderStyle,
          selectedStyle: w.selectedStyle,
          unfocusedSelectedStyle: w.unfocusedSelectedStyle,
          cursorStyle: w.cursorStyle,
          pointerShapes: w.pointerShapes,
        ),
      ),
    );
  }
}

// what measures text outside an app
final _segmenter = TextSegmenter();
