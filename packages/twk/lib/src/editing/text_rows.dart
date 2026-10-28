/// The rows a text area shows its text in: [TextRows], the lines of a
/// [TextBuffer] each broken by word into rows ([LineRows]), worked out for
/// the lines asked for only, as far as asked for, and kept across edits.
library;

import 'dart:collection' show ListBase;
import 'dart:typed_data';

import 'package:meta/meta.dart' show visibleForTesting;
import 'package:twk_core/twk_core.dart'
    show
        BidiClass,
        ClusterScan,
        TextDirection,
        TextMode,
        TextSegmenter,
        bidiClassOf,
        stringWidth;

import 'bidi_row.dart';
import 'caret.dart';
import 'text_buffer.dart';

/// A row of a text: its `line`, and the `row` of the line.
typedef RowOf = ({int line, int row});

/// The lines of a text broken into rows of a width, as [LineRows] breaks
/// a line; each line's rows worked out when asked for. They are kept until
/// the width, the segmenter or the order they are drawn in changes, or a
/// [sweep] finds them not asked for since the last; an edit of the text
/// keeps those of the lines it does not reach, and of the line it is in
/// those before it.
final class TextRows {
  TextBuffer _text = TextBuffer.empty;
  var _width = 1;
  TextSegmenter? _segmenter;
  TextMode? _mode;
  var _ambiguous = 1;
  var _visual = false;
  var _layouts = 0;
  final _scan = ClusterScan();

  // the lines whose rows are kept, in order, and their rows; the index
  // [of] found last
  final _lines = <int>[];
  final _kept = <LineRows>[];
  var _hint = 0;

  /// The text.
  TextBuffer get text => _text;

  /// How many lines' rows are kept.
  int get kept => _kept.length;

  /// How many times the rows were dropped for a width, a segmenter or an
  /// order of their own: while it stays, a row's text is drawn as before.
  int get layouts => _layouts;

  /// Takes [text] in rows of [width] columns (one at least) as [segmenter]
  /// measures it, drawn in visual order when [visual] ([LineRows.visual]).
  void update(
    TextBuffer text,
    int width,
    TextSegmenter segmenter, {
    bool visual = false,
  }) {
    final w = width < 1 ? 1 : width;
    if (w != _width ||
        visual != _visual ||
        !identical(segmenter, _segmenter) ||
        segmenter.mode != _mode ||
        segmenter.ambiguousWidth != _ambiguous) {
      _clear();
      _layouts++;
      _text = text;
      _width = w;
      _visual = visual;
      _segmenter = segmenter;
      _mode = segmenter.mode;
      _ambiguous = segmenter.ambiguousWidth;
      return;
    }
    if (identical(text, _text)) {
      return;
    }
    final old = _text;
    _text = text;
    final change = text.changeSince(old);
    if (change == null) {
      _clear();
      return;
    }
    // the lines from first to last of the old text are those of the new
    // from first to last + shift: those after them move by shift, in
    // place, those between them go
    final (:start, :oldEnd, :newEnd) = change;
    final first = old.lineOf(start);
    final last = old.lineOf(oldEnd);
    final shift = text.lineOf(newEnd) - last;
    final d = newEnd - oldEnd;
    final lines = _lines;
    final kept = _kept;
    var n = 0;
    for (var i = 0; i < lines.length; i++) {
      var l = lines[i];
      final r = kept[i];
      if (l < first) {
        r.rebind(text, r.start);
      } else if (l > last) {
        l += shift;
        r.rebind(text, r.start + d);
      } else if (l == first) {
        final s = r.start;
        r.edit(text, text.lineEnd(l) - s, start - s, oldEnd - s, newEnd - s);
      } else {
        continue;
      }
      lines[n] = l;
      kept[n] = r;
      n++;
    }
    _truncate(n);
  }

  void _clear() => _truncate(0);

  void _truncate(int n) {
    _lines.length = n;
    _kept.length = n;
    _hint = 0;
  }

  /// The index of [line] in [_lines]; where it would go, inverted (`~`),
  /// when it is not there.
  int _find(int line) {
    final lines = _lines;
    final n = lines.length;
    // the line asked for last, or the one after it
    final h = _hint;
    if (h < n && lines[h] == line) {
      return h;
    }
    if (h + 1 < n && lines[h + 1] == line) {
      return _hint = h + 1;
    }
    var lo = 0;
    var hi = n;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid] < line) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo < n && lines[lo] == line) {
      return _hint = lo;
    }
    return ~lo;
  }

  /// The rows of [line] of the text [update] took last.
  LineRows of(int line) {
    var i = _find(line);
    if (i < 0) {
      i = ~i;
      final start = _text.lineStart(line);
      _lines.insert(i, line);
      _kept.insert(
        i,
        LineRows(
          _text,
          start,
          _text.lineEnd(line) - start,
          _width,
          _segmenter ?? TextSegmenter(),
          _scan,
          visual: _visual,
        ),
      );
      _hint = i;
    }
    return _kept[i]..asked = true;
  }

  /// Drops the rows of the lines not asked for ([of]) since the last
  /// sweep.
  void sweep() {
    final lines = _lines;
    final kept = _kept;
    var n = 0;
    for (var i = 0; i < kept.length; i++) {
      final r = kept[i];
      if (r.asked) {
        r.asked = false;
        lines[n] = lines[i];
        kept[n] = r;
        n++;
      }
    }
    _truncate(n);
  }

  /// The row [offset] shows on, and the column in it.
  (RowOf, int) place(int offset) {
    final line = _text.lineOf(offset);
    final (row, column) = of(line).place(offset - _text.lineStart(line));
    return ((line: line, row: row), column);
  }

  /// The offset of [at] at [column], as [LineRows.offsetAt] finds it.
  int offsetAt(RowOf at, int column) =>
      _text.lineStart(at.line) + of(at.line).offsetAt(at.row, column);

  /// The row [n] rows below [at] (above it for [n] below 0), as far as
  /// the text goes, and how many rows that is from [at].
  (RowOf, int) move(RowOf at, int n) {
    var line = at.line;
    var row = at.row;
    var moved = 0;
    while (moved < n) {
      if (of(line).hasRow(row + 1)) {
        row++;
      } else if (line + 1 < _text.lineCount) {
        line++;
        row = 0;
      } else {
        break;
      }
      moved++;
    }
    while (moved > n) {
      if (row > 0) {
        row--;
      } else if (line > 0) {
        line--;
        row = of(line).rowCount - 1;
      } else {
        break;
      }
      moved--;
    }
    return ((line: line, row: row), moved);
  }

  /// The last row of the text.
  RowOf get last {
    final line = _text.lineCount - 1;
    return (line: line, row: of(line).rowCount - 1);
  }

  /// How many rows there are from [from] to [to], [to] included; at most
  /// [most], and 0 when [to] is before [from].
  int span(RowOf from, RowOf to, int most) {
    if (to.line < from.line || to.line == from.line && to.row < from.row) {
      return 0;
    }
    var n = 1;
    var line = from.line;
    var row = from.row;
    while (n < most && (line != to.line || row != to.row)) {
      if (of(line).hasRow(row + 1)) {
        row++;
      } else if (line + 1 < _text.lineCount) {
        line++;
        row = 0;
      } else {
        // past the end of the text: as far as asked
        return most;
      }
      n++;
    }
    return n;
  }

  /// How many rows the text has, counted up to [most].
  int count(int most) {
    var n = 0;
    for (var line = 0; line < _text.lineCount && n < most; line++) {
      n += of(line).countUpTo(most - n);
    }
    return n < most ? n : most;
  }
}

/// A line broken into rows of at most [width] columns: by word, after
/// blanks and between two wide characters (CJK), else between characters
/// (grapheme clusters, measured as `Canvas.text` draws them). Blanks at
/// the end of a row hang past its width; the end of the line takes a
/// column, for the caret after it: on a row of its own when the last row
/// is full. Each row is broken from where it starts, the columns of its
/// characters measured when asked for.
///
/// The rows are worked out from the line's start as far as asked for; an
/// edit ([edit]) works out again those from the row before it on, until
/// one starts where one started before.
///
/// In [visual] order a row with right-to-left characters, or any of a
/// line that runs right to left ([isRtl]), is drawn as a [BidiRow] in the
/// line's direction, resolved on its own; one too wide for the width, its
/// blanks hanging past its left edge, starts so that its right edge is
/// the width's.
final class LineRows {
  /// The rows of the line of a text that starts at an offset and is as
  /// long as given, at most [width] columns each, measured with the
  /// segmenter given; drawn in [visual] order or as stored.
  LineRows(
    this._text,
    this._start,
    this._length,
    this.width,
    this._segmenter,
    this._scan, {
    this.visual = false,
  });

  /// The columns of a row.
  final int width;

  /// Whether the rows are drawn in visual order.
  final bool visual;

  // the line's paragraph level by its first strong character (-1: to be
  // found)
  var _level = -1;

  final TextSegmenter _segmenter;
  final ClusterScan _scan;

  // the text and where in it the line starts, and its length
  TextBuffer _text;
  int _start;
  int _length;

  // where each row worked out starts in the line, how many there are, and
  // whether the last is the line's
  var _starts = Int32List(4);
  var _known = 1;
  var _complete = false;

  // the characters of the rows measured, by row
  final _cells = <int, _Cells>{};

  /// Whether the rows were asked for since the last [TextRows.sweep].
  var asked = false;

  /// The offset the line starts at in the text.
  int get start => _start;

  /// The line's length.
  int get length => _length;

  /// How many rows the line takes; all of them worked out.
  int get rowCount {
    _workOut(1 << 30);
    return _known;
  }

  /// Whether the line has a row [row].
  bool hasRow(int row) {
    _workOut(row);
    return row < _known;
  }

  /// How many rows the line takes, counted up to [most].
  int countUpTo(int most) {
    _workOut(most - 1);
    return _known < most ? _known : most;
  }

  /// The offset [row] starts at.
  int rowStart(int row) {
    _workOut(row);
    return _starts[row];
  }

  /// The offset [row] ends at: where the next starts, or the line's end.
  int rowEnd(int row) {
    _workOut(row + 1);
    return row + 1 < _known ? _starts[row + 1] : _length;
  }

  /// The part of the line from [from] to [to].
  String text(int from, int to) => _text.substring(_start + from, _start + to);

  /// Whether the line runs right to left: its first strong character
  /// outside isolates does (rules P2 and P3 of UAX #9).
  bool get isRtl {
    if (_level < 0) {
      _level = _firstStrong();
    }
    return _level == 1;
  }

  /// 1 when the first strong character of the line outside isolates is
  /// right to left, else 0; read from the start, a piece at a time.
  int _firstStrong() {
    var depth = 0;
    for (var from = 0; from < _length;) {
      final to = from + 256 < _length ? from + 256 : _length;
      final t = _text.substring(_start + from, _start + to);
      var i = 0;
      for (; i < t.length; i++) {
        var cp = t.codeUnitAt(i);
        if (cp >= 0xD800 && cp <= 0xDBFF) {
          if (i + 1 == t.length) {
            if (to < _length) {
              // read with the piece after
              break;
            }
          } else {
            final lo = t.codeUnitAt(i + 1);
            if (lo >= 0xDC00 && lo <= 0xDFFF) {
              cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
              i++;
            }
          }
        }
        switch (bidiClassOf(cp)) {
          case BidiClass.l when depth == 0:
            return 0;
          case (BidiClass.r || BidiClass.al) when depth == 0:
            return 1;
          case BidiClass.lri || BidiClass.rli || BidiClass.fsi:
            depth++;
          case BidiClass.pdi when depth > 0:
            depth--;
          case _:
        }
      }
      from += i;
    }
    return 0;
  }

  /// [row] as it is drawn in visual order; null for one drawn as stored.
  BidiRow? bidiOf(int row) => _cellsOf(row).bidi;

  /// The column [row] starts at: left of the left edge for one in visual
  /// order too wide for the width.
  int rowX(int row) => _cellsOf(row).x;

  /// The column [offset] is at in its row: that of the character it starts
  /// or is inside.
  int columnOf(int offset) {
    final cells = _cellsOf(_rowOf(offset));
    return cells.columns[cells.indexOf(offset)];
  }

  /// The row [offset] is on and the column in it, where the caret shows:
  /// at the start of the next row for a blank hanging past the width. In
  /// visual order, the column as the row is drawn, within the width.
  (int, int) place(int offset) {
    final r = _rowOf(offset);
    final cells = _cellsOf(r);
    final bidi = cells.bidi;
    if (bidi != null) {
      final o = offset - cells.start;
      final c = cells.x + bidi.columnOf(o);
      if ((c < 0 || c >= width) && o >= cells.blanks && hasRow(r + 1)) {
        final next = _cellsOf(r + 1);
        final n = next.bidi;
        return (r + 1, n == null ? 0 : _inWidth(next.x + n.columnOf(0)));
      }
      return (r, _inWidth(c));
    }
    final c = cells.columns[cells.indexOf(offset)];
    return c >= width && hasRow(r + 1) ? (r + 1, 0) : (r, c);
  }

  int _inWidth(int column) =>
      column < 0 ? 0 : (column >= width ? width - 1 : column);

  /// The offset in [row] at [column] where the caret goes: of the last
  /// character that starts at or before it; on the last row, the line's
  /// end, too.
  int offsetAt(int row, int column) {
    final cells = _cellsOf(row);
    final bidi = cells.bidi;
    if (bidi != null) {
      return cells.start +
          bidi.offsetAt(
            column - cells.x,
            before: hasRow(row + 1) ? rowEnd(row) - cells.start : null,
            leftmost: -cells.x,
          );
    }
    final last = cells.offsets.length - (hasRow(row + 1) ? 2 : 1);
    var best = 0;
    for (var k = 1; k <= last; k++) {
      if (cells.columns[k] > column) {
        break;
      }
      best = k;
    }
    return cells.start + cells.offsets[best];
  }

  /// Takes the line on in [text], where it starts at [start].
  void rebind(TextBuffer text, int start) {
    _text = text;
    _start = start;
  }

  /// Takes the line on in [text], [length] long, after an edit that
  /// replaced the part from [from] to [oldEnd] of it with what ends at
  /// [newEnd] (past its end for an edit that goes on into the lines
  /// after): the rows before the one before the edit's are kept, the
  /// others worked out again. Once a row starts after the edit where one
  /// started before, the rows after it are those before.
  void edit(TextBuffer text, int length, int from, int oldEnd, int newEnd) {
    final old = _starts;
    final oldKnown = _known;
    final oldComplete = _complete;
    final oldLength = _length;
    _text = text;
    _length = length;
    final level = _level;
    _level = -1;
    // the row before the edit's may take more of it, or less
    var r = _lastAtOrBefore(old, oldKnown, from > 0 ? from - 1 : 0);
    if (r > 0) {
      r--;
    }
    // the rows kept, in an array of their own: the old one is read on
    _starts = Int32List(old.length)..setRange(0, r + 1, old);
    _known = r + 1;
    _complete = false;
    _cells.removeWhere((row, _) => row >= r);
    // in visual order, a line that now runs the other way draws its rows
    // the other way
    if (visual && level >= 0 && (isRtl ? 1 : 0) != level) {
      _cells.clear();
    }
    // no row worked out before starts after the edit
    if (oldEnd > oldLength || !oldComplete && old[oldKnown - 1] <= oldEnd) {
      return;
    }
    final d = newEnd - oldEnd;
    for (var i = 0; i < 16 && !_complete; i++) {
      _next();
      final s = _starts[_known - 1];
      if (_complete || s < newEnd) {
        continue;
      }
      final j = _indexIn(old, oldKnown, s - d);
      if (j >= 0) {
        for (var k = j + 1; k < oldKnown; k++) {
          _push(old[k] + d);
        }
        _complete = oldComplete;
        return;
      }
    }
  }

  /// Works the rows out as far as [row], or the line's end.
  void _workOut(int row) {
    while (_known <= row && !_complete) {
      _next();
    }
  }

  /// Works out the row after the last worked out, or that the last is the
  /// line's.
  void _next() {
    final next = _breakAfter(_starts[_known - 1]);
    if (next < 0) {
      _complete = true;
    } else {
      _push(next);
    }
  }

  void _push(int start) {
    if (_known == _starts.length) {
      _starts = Int32List(_known * 2)..setRange(0, _known, _starts);
    }
    _starts[_known++] = start;
  }

  /// The row [offset] is on.
  int _rowOf(int offset) {
    while (!_complete && _starts[_known - 1] <= offset) {
      _next();
    }
    return _lastAtOrBefore(_starts, _known, offset);
  }

  /// The index of the last of the first [n] of [starts] at or before
  /// [offset]; 0 before the first.
  static int _lastAtOrBefore(Int32List starts, int n, int offset) {
    var lo = 0;
    var hi = n - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (starts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// The index of [offset] in the first [n] of [starts]; -1 when it is
  /// not one of them.
  static int _indexIn(Int32List starts, int n, int offset) {
    final k = _lastAtOrBefore(starts, n, offset);
    return starts[k] == offset ? k : -1;
  }

  /// Where the row after the one that starts at [start] starts; -1 when
  /// the line's end is in this row.
  int _breakAfter(int start) {
    for (var span = 4 * width + 64; ; span *= 4) {
      final end = start + span < _length ? start + span : _length;
      final found = _breakIn(
        _text.substring(_start + start, _start + end),
        end == _length,
      );
      if (found != null) {
        return found < 0 ? found : start + found;
      }
    }
  }

  /// Where in [t], the line from a row's start on, the next row starts; -1
  /// when the line ends in the row, null when [t] ends before the row does
  /// and [lineEnd] does not say it is the line's end.
  int? _breakIn(String t, bool lineEnd) {
    final graphemes = _segmenter.mode == TextMode.graphemes;
    var column = 0;
    // where the row may break: after a blank, between wide characters
    var brk = -1;
    var prevBlank = false;
    var prevWidth = 0;
    // a mark at the start or after a control has no base
    var baseless = true;
    for (var k = 0; ;) {
      if (k == t.length) {
        if (!lineEnd) {
          return null;
        }
        // the end takes a column
        if (k > 0 && prevBlank) {
          brk = k;
        }
        if (k > 0 && column + 1 > width) {
          return brk > 0 ? brk : k;
        }
        return -1;
      }
      // a character cut off at the end of t is not taken: the row ends
      // before it, or t is read again longer
      _segmenter.scan(t, k, _scan);
      final end = _scan.end;
      var w = _scan.width;
      final control = w == 0;
      if (control) {
        w = _scan.first == 0x09 ? 1 : 0;
      } else if (graphemes && (baseless || _scan.length > 1)) {
        w = stringWidth(
          t.substring(k, end),
          ambiguousWidth: _segmenter.ambiguousWidth,
        );
      }
      baseless = control;
      final blank = _isBlank(t.codeUnitAt(k));
      if (k > 0 && !blank && (prevBlank || w == 2 && prevWidth == 2)) {
        brk = k;
      }
      if (!blank && column + w > width && k > 0) {
        return brk > 0 ? brk : k;
      }
      column += w;
      prevBlank = blank;
      prevWidth = w;
      k = end;
    }
  }

  static bool _isBlank(int c) => c == 0x20 || c == 0x09;

  // what a row is measured in ([_measure]), then copied out of
  static final _offsets = GrowingInts();
  static final _columns = GrowingInts();

  /// The characters of [row] and their columns; in visual order, as they
  /// are drawn.
  _Cells _cellsOf(int row) => _cells[row] ?? (_cells[row] = _measure(row));

  /// Measures the characters of [row] ([_cellsOf]).
  _Cells _measure(int row) {
    final from = rowStart(row);
    final t = text(from, rowEnd(row));
    final offsets = _offsets..length = 0;
    final columns = _columns..length = 0;
    measureClusters(t, _segmenter, offsets, columns, _scan);
    final cells = _Cells(from, offsets.copy(), columns.copy());
    if (visual && (isRtl || mayReorder(t))) {
      final bidi = BidiRow(
        t,
        cells.offsets,
        cells.columns,
        direction: isRtl ? TextDirection.rtl : TextDirection.ltr,
      );
      var blanks = t.length;
      while (blanks > 0 && _isBlank(t.codeUnitAt(blanks - 1))) {
        blanks--;
      }
      cells
        ..bidi = bidi
        ..blanks = blanks
        ..x = isRtl && bidi.width > width ? width - bidi.width : 0;
    }
    return cells;
  }
}

/// Ints added to an array that grows and is kept when the list is emptied
/// (a growable list gives its up). Read and written within its [length]
/// only, which the asserts check: past it the array holds what an earlier
/// use left there, and a list grown by [length] reads 0 there.
@visibleForTesting
final class GrowingInts extends ListBase<int> {
  var _array = Int32List(64);
  var _length = 0;

  @override
  int get length => _length;

  @override
  set length(int n) {
    if (n > _array.length) {
      _array = Int32List(n * 2)..setRange(0, _length, _array);
    } else if (n > _length) {
      _array.fillRange(_length, n, 0);
    }
    _length = n;
  }

  @override
  int operator [](int i) {
    assert(i >= 0 && i < _length, 'index $i outside 0..${_length - 1}');
    return _array[i];
  }

  @override
  void operator []=(int i, int value) {
    assert(i >= 0 && i < _length, 'index $i outside 0..${_length - 1}');
    _array[i] = value;
  }

  @override
  void add(int element) {
    if (_length == _array.length) {
      length = _length + 1;
      _array[_length - 1] = element;
    } else {
      _array[_length++] = element;
    }
  }

  /// The ints, in an array of their own.
  Int32List copy() => _array.sublist(0, _length);
}

/// The characters of a row: the offset each starts at in the row, then
/// the row's end, and the column of each and of the end.
final class _Cells {
  _Cells(this.start, this.offsets, this.columns);

  /// Where the row starts in its line.
  final int start;

  final Int32List offsets;
  final Int32List columns;

  /// In visual order, the row as it is drawn, else null; where the blanks
  /// at its end start; the column it starts at.
  BidiRow? bidi;
  var blanks = 0;
  var x = 0;

  /// The index of the character [offset] of the line starts or is inside;
  /// the end's past the last.
  int indexOf(int offset) {
    final o = offset - start;
    final s = offsets;
    var lo = 0;
    var hi = s.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (s[mid] <= o) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}
