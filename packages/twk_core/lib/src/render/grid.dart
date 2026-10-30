part of 'render.dart';

// ------------------------------------------------------------------ grid --

/// How a [GridTrack] is sized.
enum GridTrackKind {
  /// A fixed number of cells.
  fixed,

  /// A part of the cells the other tracks leave, by its fraction.
  fraction,

  /// As long as the children in it ask for.
  content,
}

/// The length of a column or a row of a [RenderGrid], in whole cells:
/// fixed, a fraction of the cells the other tracks leave (CSS `fr`), or as
/// long as the children in it ask for (CSS `auto`). A fraction or a
/// content track is at least [min] and at most [max] cells long.
final class GridTrack {
  /// Exactly [cells] long.
  const GridTrack.fixed(int cells)
    : assert(cells >= 0, 'a track of 0 cells or more'),
      kind = GridTrackKind.fixed,
      fraction = 0,
      min = cells,
      max = cells;

  /// [fraction] parts of the cells the other tracks leave, against the
  /// parts of the other fraction tracks.
  const GridTrack.fr(
    this.fraction, {
    this.min = 0,
    this.max = BoxConstraints.unbounded,
  }) : assert(fraction > 0, 'a fraction above 0'),
       assert(0 <= min && min <= max, 'bounds of 0 cells or more, in order'),
       kind = GridTrackKind.fraction;

  /// As long as the children in it want to be (their max intrinsic sizes)
  /// while there are cells for that, down to as long as they need to be
  /// (their min intrinsic sizes).
  const GridTrack.content({this.min = 0, this.max = BoxConstraints.unbounded})
    : assert(0 <= min && min <= max, 'bounds of 0 cells or more, in order'),
      kind = GridTrackKind.content,
      fraction = 0;

  /// How the track is sized: fixed, a fraction or by its content.
  final GridTrackKind kind;

  /// The parts of a fraction track; 0 for the others.
  final int fraction;

  /// The fewest cells the track takes; a fixed track's length.
  final int min;

  /// The most cells the track takes; a fixed track's length.
  final int max;

  @override
  bool operator ==(Object other) =>
      other is GridTrack &&
      other.kind == kind &&
      other.fraction == fraction &&
      other.min == min &&
      other.max == max;
  @override
  int get hashCode => Object.hash(kind, fraction, min, max);

  /// `5` for five fixed cells, `2fr` or `content`, with the bounds after
  /// it where they are not the defaults (`1fr(4..∞)`, `content(2..10)`).
  @override
  String toString() => switch (kind) {
    GridTrackKind.fixed => '$min',
    GridTrackKind.fraction => '${fraction}fr${_bounds()}',
    GridTrackKind.content => 'content${_bounds()}',
  };

  String _bounds() => min == 0 && max >= BoxConstraints.unbounded
      ? ''
      : '(${_range(min, max)})';
}

/// What a [RenderGrid] keeps on a child: its offset, its siblings, and the
/// cells it takes: [rowSpan] rows from [row] and [columnSpan] columns from
/// [column], counted from 0 at the top left. A child with neither a row
/// nor a column goes after the child before it ([RenderGrid]).
final class GridParentData extends ParentData with ContainerParentDataMixin {
  /// The data of a child not laid out yet: after the child before it.
  GridParentData();

  /// The child's first row; null with [column] to place the child after
  /// the one before it.
  int? row;

  /// The child's first column; null with [row] to place the child after
  /// the one before it.
  int? column;

  /// The rows the child takes, 1 or more.
  var rowSpan = 1;

  /// The columns the child takes, 1 or more.
  var columnSpan = 1;

  // the first row and column the child takes, as the grid placed it
  var _row = 0;
  var _column = 0;

  /// The row and the column that are set, and spans other than 1.
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add('row', row, defaultValue: null)
      ..add('column', column, defaultValue: null)
      ..add('rowSpan', rowSpan, defaultValue: 1)
      ..add('columnSpan', columnSpan, defaultValue: 1);
  }
}

// a track past the end of a grid's list
const _implicitTrack = GridTrack.content();

/// Track [i] of [tracks]: past the end of the list, a content track.
GridTrack _track(List<GridTrack> tracks, int i) =>
    i < tracks.length ? tracks[i] : _implicitTrack;

/// Whether [a] and [b] hold the same tracks.
bool _sameTracks(List<GridTrack> a, List<GridTrack> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// [v] within [lo]..[hi].
int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// Lays its children out in the cells of its [columns] and [rows], tracks
/// [columnGap] columns and [rowGap] rows apart (CSS grid, simplified). A
/// child takes the cells its [GridParentData] names and is laid out
/// exactly as big as they are with the gaps between them. A child with
/// neither a row nor a column goes in the cells after the child before
/// it, or from the first column on the next row when they would reach
/// past the last of [columns]; the first child at the top left. Cells
/// another child takes are not skipped. Tracks past the end of a list, up
/// to the last a child takes, are content tracks.
///
/// The columns are sized first, then the rows at the widths of the
/// columns each child spans, each axis the same way. A fixed track takes
/// its cells, a content track what the children in it alone need (their
/// min intrinsic sizes) and a fraction track its [GridTrack.min]; a child
/// that spans tracks and needs more than they take grows the content
/// tracks it spans, unless it spans a fraction track, by even parts of
/// what it lacks. Then the content tracks grow by even parts of the cells
/// left towards what their children want (their max intrinsic sizes), a
/// spanning child's want grown into them the same way, and the fraction
/// tracks share the cells left after that by their fractions. Cells are
/// shared in whole cells, those left over going to the first tracks; a
/// track stays within its bounds and leaves the rest to the others. Along
/// an unbounded axis the grid is as long as its children want, as its max
/// intrinsic size says, its fraction tracks stretched to the least the
/// constraints allow if that is longer.
///
/// The grid is as big as its tracks and gaps, within its constraints; what
/// doesn't fit is cut off at its bounds and, in debug, reported once as a
/// warning in the [log]. Children that overlap are painted in order: a
/// later child covers an earlier one, and a repaint boundary in a child
/// that repaints on its own has the children after it that reach its
/// cells painted again over it ([paintOver]).
///
/// It asks for its gaps and its tracks at what their children ask for: a
/// content track at what its children need or want, the fraction tracks
/// at the fewest cells per part that give each fraction track, and each
/// child spanning one, what it asks for.
///
/// A sidebar 20 columns wide beside a main pane that takes the rest, a
/// column apart; the children go in the cells in order:
///
/// ```dart
/// final grid = RenderGrid(
///   columns: const [GridTrack.fixed(20), GridTrack.fr(1)],
///   columnGap: 1,
///   children: [
///     RenderParagraph([('Files', const Pen())]),
///     RenderParagraph([('main.dart', const Pen())]),
///   ],
/// );
/// ```
///
/// See also:
///
///  * [RenderFlex], children along one axis.
///  * [GridParentData], where a child is put in cells of its own.
final class RenderGrid extends RenderObject
    with ContainerRenderObjectMixin<GridParentData> {
  /// A grid of [children] in [columns] and [rows], none unless given (a
  /// track per child, as long as it asks for), [columnGap] and [rowGap]
  /// cells apart, each 0 or more.
  RenderGrid({
    List<RenderObject>? children,
    this._columns = const [],
    this._rows = const [],
    this._columnGap = 0,
    this._rowGap = 0,
  }) : assert(_columnGap >= 0 && _rowGap >= 0, 'gaps of 0 cells or more') {
    addAll(children);
  }

  List<GridTrack> _columns;

  /// The columns from the left; those past the end of the list are
  /// content tracks.
  List<GridTrack> get columns => _columns;
  set columns(List<GridTrack> t) {
    if (!_sameTracks(t, _columns)) {
      _columns = t;
      markNeedsLayout();
    }
  }

  List<GridTrack> _rows;

  /// The rows from the top; those past the end of the list are content
  /// tracks.
  List<GridTrack> get rows => _rows;
  set rows(List<GridTrack> t) {
    if (!_sameTracks(t, _rows)) {
      _rows = t;
      markNeedsLayout();
    }
  }

  int _columnGap;

  /// Columns between one column and the next.
  int get columnGap => _columnGap;
  set columnGap(int g) {
    assert(g >= 0, 'a gap of 0 cells or more');
    if (g != _columnGap) {
      _columnGap = g;
      markNeedsLayout();
    }
  }

  int _rowGap;

  /// Rows between one row and the next.
  int get rowGap => _rowGap;
  set rowGap(int g) {
    assert(g >= 0, 'a gap of 0 cells or more');
    if (g != _rowGap) {
      _rowGap = g;
      markNeedsLayout();
    }
  }

  // the tracks the children reach, those of the lists or more: as last
  // placed, and as last laid out
  var _placedColumns = 0;
  var _placedRows = 0;
  var _columnCount = 0;
  var _rowCount = 0;

  // as last laid out, where each column and each row starts and, after
  // the last, where one more would
  var _columnAt = Int64List(1);
  var _rowAt = Int64List(1);

  // the same while intrinsic sizes are worked out
  var _columnsAsked = Int64List(1);
  var _rowsAsked = Int64List(1);

  // what the sizing along an axis works with: the fewest cells each track
  // takes, and the most it grows to
  var _base = Int64List(0);
  var _limit = Int64List(0);

  // the overflow was reported (debug)
  var _overflowReported = false;

  /// The tracks and the gaps that are set; once laid out, the length of
  /// each track and the cells the tracks and gaps need beyond the grid, if
  /// any, with the [DiagnosticsFlag.overflow] flag.
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    if (_columns.isNotEmpty) {
      properties.addMessage('columns', _columns.join(' '));
    }
    if (_rows.isNotEmpty) {
      properties.addMessage('rows', _rows.join(' '));
    }
    properties
      ..add('columnGap', _columnGap, defaultValue: 0)
      ..add('rowGap', _rowGap, defaultValue: 0);
    if (_constraints == null) {
      return;
    }
    if (_columnCount > 0) {
      properties.addMessage(
        'widths',
        _lengths(_columnAt, _columnCount, _columnGap),
      );
    }
    if (_rowCount > 0) {
      properties.addMessage('heights', _lengths(_rowAt, _rowCount, _rowGap));
    }
    final overW = _length(_columnAt, _columnCount, _columnGap) - width;
    final overH = _length(_rowAt, _rowCount, _rowGap) - height;
    if (overW > 0 || overH > 0) {
      properties
        ..addMessage(
          'overflow',
          [
            if (overW > 0) _cells(overW, 'column'),
            if (overH > 0) _cells(overH, 'row'),
          ].join(', '),
        )
        ..flag(DiagnosticsFlag.overflow);
    }
  }

  /// The length of each of [count] tracks that start where [at] says,
  /// [gap] cells apart: `3 1 10`.
  static String _lengths(Int64List at, int count, int gap) => [
    for (var i = 0; i < count; i++) at[i + 1] - at[i] - gap,
  ].join(' ');

  /// `1 column`, `3 rows`.
  static String _cells(int n, String unit) => '$n $unit${n == 1 ? '' : 's'}';

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! GridParentData) {
      child.parentData = GridParentData();
    }
  }

  /// Puts each child in its cells, as its [GridParentData] says or after
  /// the child before it, and counts the tracks the children reach.
  void _place() {
    final last = _columns.isEmpty ? 1 : _columns.length;
    var columns = _columns.length;
    var rows = _rows.length;
    var row = 0;
    var column = 0;
    for (var child = _firstChild; child != null;) {
      final at = child.parentData as GridParentData;
      final r = at.row;
      final c = at.column;
      assert(
        at.rowSpan > 0 && at.columnSpan > 0,
        'a child spans 1 track or more',
      );
      assert(
        (r == null) == (c == null),
        'a child has a row and a column, or neither',
      );
      if (r != null && c != null) {
        assert(r >= 0 && c >= 0, 'a row and a column of 0 or more');
        row = r;
        column = c;
      } else if (column > 0 && column + at.columnSpan > last) {
        row++;
        column = 0;
      }
      at
        .._row = row
        .._column = column;
      column += at.columnSpan;
      columns = column > columns ? column : columns;
      final end = row + at.rowSpan;
      rows = end > rows ? end : rows;
      child = at.nextSibling;
    }
    _placedColumns = columns;
    _placedRows = rows;
  }

  /// The cells of [span] tracks from [from], which start where [at] says,
  /// [gap] cells apart, with the gaps between them.
  static int _span(Int64List at, int from, int span, int gap) =>
      at[from + span] - at[from] - gap;

  /// The cells of [count] tracks that start where [at] says, [gap] cells
  /// apart, with the gaps between them.
  static int _length(Int64List at, int count, int gap) =>
      count == 0 ? 0 : at[count] - gap;

  @override
  void performLayout(BoxConstraints c) {
    _place();
    final columns = _columnAt = _fit(true, _columnAt, c.minW, c.maxW, null);
    _columnCount = _placedColumns;
    final rows = _rowAt = _fit(false, _rowAt, c.minH, c.maxH, columns);
    _rowCount = _placedRows;
    final w = _length(columns, _columnCount, _columnGap);
    final h = _length(rows, _rowCount, _rowGap);
    width = c.constrainW(w);
    height = c.constrainH(h);
    assert(_debugReportOverflow(w - width, h - height), 'reports overflow');
    for (var child = _firstChild; child != null;) {
      final at = child.parentData as GridParentData;
      final cw = _span(columns, at._column, at.columnSpan, _columnGap);
      final ch = _span(rows, at._row, at.rowSpan, _rowGap);
      _layoutChild(child, cw, cw, ch, ch);
      at
        ..dx = columns[at._column]
        ..dy = rows[at._row];
      child = at.nextSibling;
    }
  }

  /// The tracks along one axis sized within [min]..[max] cells, in [out]
  /// or a longer list in its place: along an unbounded axis as long as
  /// the children want, the fraction tracks stretched to [min] if that is
  /// longer.
  Int64List _fit(
    bool columns,
    Int64List out,
    int min,
    int max,
    Int64List? across,
  ) {
    final at = _size(columns, out, max, across: across);
    if (max < BoxConstraints.unbounded) {
      return at;
    }
    final count = columns ? _placedColumns : _placedRows;
    final gap = columns ? _columnGap : _rowGap;
    return _length(at, count, gap) < min
        ? _size(columns, at, min, across: across)
        : at;
  }

  /// Logs a warning the first time the tracks and gaps overflow the grid,
  /// [overW] columns and [overH] rows beyond it.
  bool _debugReportOverflow(int overW, int overH) {
    if ((overW > 0 || overH > 0) && !_overflowReported) {
      _overflowReported = true;
      final sides = [
        if (overW > 0) '${_cells(overW, 'column')} on the right',
        if (overH > 0) '${_cells(overH, 'row')} on the bottom',
      ].join(' and ');
      _warn('A RenderGrid overflowed by $sides.');
    }
    return true;
  }

  /// Sizes the columns, or the rows when not [columns], and returns where
  /// each starts and, after the last, where one more would, in [out] or a
  /// longer list in its place. Within [available] cells, or along an
  /// unbounded axis as long as the children need with [least], or want.
  /// The rows ask their children for heights at the widths of the columns
  /// they span, which start where [across] says.
  Int64List _size(
    bool columns,
    Int64List out,
    int available, {
    bool least = false,
    Int64List? across,
  }) {
    final tracks = columns ? _columns : _rows;
    final count = columns ? _placedColumns : _placedRows;
    final gap = columns ? _columnGap : _rowGap;
    final measure = available >= BoxConstraints.unbounded;
    final sizes = out.length > count ? out : Int64List(count + 1);
    if (_base.length < count) {
      _base = Int64List(count);
      _limit = Int64List(count);
    }
    final base = _base;
    final limit = _limit;
    var fractions = false;
    for (var i = 0; i < count; i++) {
      final t = _track(tracks, i);
      base[i] = t.min;
      limit[i] = t.min;
      fractions |= t.kind == GridTrackKind.fraction;
    }
    // what the children in one track ask for: in a content track, and in
    // a fraction track along an unbounded axis
    var spans = 1;
    for (var child = _firstChild; child != null;) {
      final at = child.parentData as GridParentData;
      final span = columns ? at.columnSpan : at.rowSpan;
      if (span > 1) {
        spans = span > spans ? span : spans;
      } else {
        final i = columns ? at._column : at._row;
        final kind = _track(tracks, i).kind;
        if (kind == GridTrackKind.content ||
            (measure && kind == GridTrackKind.fraction)) {
          final extent = _across(columns, at, across);
          final need = child._intrinsic(
            columns ? _minWidth : _minHeight,
            extent,
          );
          base[i] = need > base[i] ? need : base[i];
          if (!least) {
            final want = child._intrinsic(
              columns ? _maxWidth : _maxHeight,
              extent,
            );
            limit[i] = want > limit[i] ? want : limit[i];
          }
        }
      }
      child = at.nextSibling;
    }
    for (var i = 0; i < count; i++) {
      final max = _track(tracks, i).max;
      base[i] = base[i] > max ? max : base[i];
      limit[i] = _clamp(limit[i], base[i], max);
    }
    // then what the children that span tracks ask for beyond them, those
    // that span fewer first
    for (var span = 2; span <= spans; span++) {
      for (var child = _firstChild; child != null;) {
        final at = child.parentData as GridParentData;
        if ((columns ? at.columnSpan : at.rowSpan) == span) {
          _grow(columns, child, at, tracks, gap, least, across);
        }
        child = at.nextSibling;
      }
    }
    if (measure) {
      _measure(columns, sizes, tracks, count, gap, spans, least, across);
    } else {
      var free = available - (count > 1 ? gap * (count - 1) : 0);
      for (var i = 0; i < count; i++) {
        sizes[i] = base[i];
        free -= base[i];
      }
      if (free > 0) {
        free -= _spread(tracks, sizes, limit, 0, count, free);
      }
      if (free > 0 && fractions) {
        _share(tracks, count, sizes, free);
      }
    }
    var x = 0;
    for (var i = 0; i < count; i++) {
      final s = sizes[i];
      sizes[i] = x;
      x += s + gap;
    }
    sizes[count] = x;
    return sizes;
  }

  /// The extent across the axis being sized at which [at]'s child is asked
  /// for its intrinsic sizes: for a row, the width of the columns it
  /// spans, which start where [across] says; for a column, any height.
  int _across(bool columns, GridParentData at, Int64List? across) =>
      columns || across == null
      ? BoxConstraints.unbounded
      : _span(across, at._column, at.columnSpan, _columnGap);

  /// Grows the content tracks among [tracks] that [child], placed by [at],
  /// spans by even parts of what it needs beyond them, gaps included, and
  /// unless [least] of what it wants; nothing when it spans a fraction
  /// track or no content track.
  void _grow(
    bool columns,
    RenderObject child,
    GridParentData at,
    List<GridTrack> tracks,
    int gap,
    bool least,
    Int64List? across,
  ) {
    final from = columns ? at._column : at._row;
    final span = columns ? at.columnSpan : at.rowSpan;
    final to = from + span;
    var content = false;
    for (var i = from; i < to; i++) {
      final kind = _track(tracks, i).kind;
      if (kind == GridTrackKind.fraction) {
        return;
      }
      content |= kind == GridTrackKind.content;
    }
    if (!content) {
      return;
    }
    final base = _base;
    final limit = _limit;
    final extent = _across(columns, at, across);
    var need =
        child._intrinsic(columns ? _minWidth : _minHeight, extent) -
        gap * (span - 1);
    for (var i = from; i < to; i++) {
      need -= base[i];
    }
    if (need > 0) {
      _spread(tracks, base, null, from, to, need);
      for (var i = from; i < to; i++) {
        limit[i] = limit[i] < base[i] ? base[i] : limit[i];
      }
    }
    if (!least) {
      var want =
          child._intrinsic(columns ? _maxWidth : _maxHeight, extent) -
          gap * (span - 1);
      for (var i = from; i < to; i++) {
        want -= limit[i];
      }
      if (want > 0) {
        _spread(tracks, limit, null, from, to, want);
      }
    }
  }

  /// Adds up to [cells] cells to the content tracks among [tracks] from
  /// [from] to [to] in [sizes], by even parts, those left over going to
  /// the first: each up to its cap in [caps], or without them up to its
  /// [GridTrack.max]; a track at its cap leaves the rest to the others.
  /// Returns the cells added.
  static int _spread(
    List<GridTrack> tracks,
    Int64List sizes,
    Int64List? caps,
    int from,
    int to,
    int cells,
  ) {
    var left = cells;
    while (left > 0) {
      // the tracks that can grow, and the least room any of them has
      var n = 0;
      var room = 0;
      for (var i = from; i < to; i++) {
        final t = _track(tracks, i);
        if (t.kind == GridTrackKind.content) {
          final r = (caps == null ? t.max : caps[i]) - sizes[i];
          if (r > 0) {
            room = n == 0 || r < room ? r : room;
            n++;
          }
        }
      }
      if (n == 0) {
        break;
      }
      // all of their least room, or an even part of what is left
      final all = room * n <= left;
      final part = all ? room : left ~/ n;
      var extra = all ? 0 : left - part * n;
      for (var i = from; i < to; i++) {
        final t = _track(tracks, i);
        if (t.kind == GridTrackKind.content &&
            (caps == null ? t.max : caps[i]) > sizes[i]) {
          var add = part;
          if (extra > 0) {
            add++;
            extra--;
          }
          sizes[i] += add;
          left -= add;
        }
      }
    }
    return cells - left;
  }

  /// Shares [free] cells and those the fraction tracks among [tracks]
  /// take in [sizes] by their fractions, in whole cells, those left over
  /// going to the first. A share beyond a track's bounds holds it at the
  /// bound and the others share the rest: those below their minimum when
  /// the bounds add more to the shares than they take, those above their
  /// maximum when less, all of them when they even out (as CSS resolves
  /// flexible lengths).
  void _share(List<GridTrack> tracks, int count, Int64List sizes, int free) {
    // a track not held yet is -1 in sizes, its share in shares: the scratch
    // of the limits, which _size reads no more once it shares
    final shares = _limit;
    var left = free;
    for (var i = 0; i < count; i++) {
      if (_track(tracks, i).kind == GridTrackKind.fraction) {
        left += sizes[i];
        sizes[i] = -1;
      }
    }
    for (;;) {
      var parts = 0;
      for (var i = 0; i < count; i++) {
        if (sizes[i] < 0) {
          parts += _track(tracks, i).fraction;
        }
      }
      if (parts == 0) {
        return;
      }
      var extra = left;
      for (var i = 0; i < count; i++) {
        if (sizes[i] < 0) {
          extra -= left * _track(tracks, i).fraction ~/ parts;
        }
      }
      // the cells the bounds add to the shares, less those they take
      var off = 0;
      for (var i = 0; i < count; i++) {
        if (sizes[i] < 0) {
          final t = _track(tracks, i);
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
          final t = _track(tracks, i);
          final share = shares[i];
          if (off == 0 || (off > 0 ? share < t.min : share > t.max)) {
            sizes[i] = _clamp(share, t.min, t.max);
            left -= sizes[i];
          }
        }
      }
    }
  }

  /// Sizes the [count] tracks among [tracks] into [sizes] as their
  /// children ask for them along an unbounded axis: a content track takes
  /// what they need with [least], or want; the fraction tracks the fewest
  /// cells per part that give each of them, and each child that spans one,
  /// what it asks for beyond the other tracks it spans, within its bounds.
  void _measure(
    bool columns,
    Int64List sizes,
    List<GridTrack> tracks,
    int count,
    int gap,
    int spans,
    bool least,
    Int64List? across,
  ) {
    final asked = least ? _base : _limit;
    var unit = 0;
    var fractions = false;
    for (var i = 0; i < count; i++) {
      final t = _track(tracks, i);
      if (t.kind == GridTrackKind.fraction) {
        fractions = true;
        sizes[i] = 0;
        unit = _perPart(unit, asked[i], t.fraction);
      } else {
        sizes[i] = asked[i];
      }
    }
    if (!fractions) {
      return;
    }
    for (var child = _firstChild; spans > 1 && child != null;) {
      final at = child.parentData as GridParentData;
      final from = columns ? at._column : at._row;
      final span = columns ? at.columnSpan : at.rowSpan;
      if (span > 1) {
        // the parts it spans, and what the other tracks give it
        var parts = 0;
        var given = gap * (span - 1);
        for (var i = from; i < from + span; i++) {
          final t = _track(tracks, i);
          if (t.kind == GridTrackKind.fraction) {
            parts += t.fraction;
          } else {
            given += sizes[i];
          }
        }
        if (parts > 0) {
          final ask = child._intrinsic(
            least
                ? (columns ? _minWidth : _minHeight)
                : (columns ? _maxWidth : _maxHeight),
            _across(columns, at, across),
          );
          unit = _perPart(unit, ask - given, parts);
        }
      }
      child = at.nextSibling;
    }
    for (var i = 0; i < count; i++) {
      final t = _track(tracks, i);
      if (t.kind == GridTrackKind.fraction) {
        sizes[i] = _clamp(t.fraction * unit, t.min, t.max);
      }
    }
  }

  /// [unit], or the fewest cells per part that give [parts] parts [cells]
  /// cells if that is more.
  static int _perPart(int unit, int cells, int parts) {
    final per = cells <= 0 ? 0 : (cells + parts - 1) ~/ parts;
    return per > unit ? per : unit;
  }

  @override
  int computeMinIntrinsicWidth(int height) => _askedWidth(least: true);

  @override
  int computeMaxIntrinsicWidth(int height) => _askedWidth();

  @override
  int computeMinIntrinsicHeight(int width) => _askedHeight(width, least: true);

  @override
  int computeMaxIntrinsicHeight(int width) => _askedHeight(width);

  /// The width the columns and their gaps ask for at any height: what the
  /// children need with [least], or want.
  int _askedWidth({bool least = false}) {
    _place();
    final at = _columnsAsked = _size(
      true,
      _columnsAsked,
      BoxConstraints.unbounded,
      least: least,
    );
    return _length(at, _placedColumns, _columnGap);
  }

  /// The height the rows and their gaps ask for at the widths of the
  /// columns sized in [width]: what the children need with [least], or
  /// want.
  int _askedHeight(int width, {bool least = false}) {
    _place();
    final columns = _columnsAsked = _size(true, _columnsAsked, width);
    final at = _rowsAsked = _size(
      false,
      _rowsAsked,
      BoxConstraints.unbounded,
      least: least,
      across: columns,
    );
    return _length(at, _placedRows, _rowGap);
  }

  @override
  void paint(PaintContext ctx) {
    for (var child = _firstChild; child != null;) {
      paintChild(ctx, child);
      child = (child.parentData as GridParentData).nextSibling;
    }
  }

  /// Whether a child after [child] reaches the cells.
  @override
  bool paintsOver(RenderObject child, int x, int y, int w, int h) =>
      _laterReaches(child, x, y, w, h);

  /// Paints the children after [child] that reach the cells, in order.
  /// They paint only those cells: whatever they keep of what they painted
  /// is forgotten.
  @override
  void paintOver(
    PaintContext ctx,
    RenderObject child,
    int x,
    int y,
    int w,
    int h,
  ) => _paintLater(this, ctx, child, x, y, w, h);
}
