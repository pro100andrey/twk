/// The line a terminal is writing: cells of characters and their styles, a
/// cursor, and the spans they make.
library;

import 'dart:typed_data';

import 'package:twk/twk.dart' show Span, Style;
import 'package:twk_core/twk_core.dart' show ClusterScan, TextSegmenter;

/// A cell that holds the second column of the wide character before it.
const _wide = -1;

const _space = 0x20;

/// One line of a terminal's screen as it is written: text goes into cells
/// at the [cursor], over what is there, a wide character into two. The line
/// has no right margin; cells the cursor moved past without writing are
/// blank.
final class LineBuffer {
  /// Per cell: a code point, [_wide], or `-2 - k` for the grapheme cluster
  /// `_clusters[k]`.
  var _chars = Int32List(64);

  /// Per cell: the index of its style in [_styles].
  var _styleIds = Int32List(64);

  var _length = 0;
  final _clusters = <String>[];
  final _styles = <Style>[];
  final _styleIndex = <Style, int>{};
  final _segmenter = TextSegmenter();
  final _scan = ClusterScan();

  /// The column text is written at next.
  var cursor = 0;

  /// Whether no cell is written.
  bool get isEmpty => _length == 0;

  /// Writes [text], which has no controls, at the cursor in [style] and
  /// moves the cursor past it. A character of no width, such as a mark
  /// without the character it combines with, joins the cell before the
  /// cursor, or is dropped where there is none.
  void write(String text, Style style) {
    final id = _idOf(style);
    for (var i = 0; i < text.length; i = _scan.end) {
      _segmenter.scan(text, i, _scan);
      final width = _scan.width;
      if (width == 0) {
        _join(text.substring(i, _scan.end));
        continue;
      }
      final char = _scan.length == 1
          ? _scan.first
          : _cluster(text.substring(i, _scan.end));
      _put(char, width, id);
    }
  }

  /// Moves the cursor to the next multiple of [width].
  void tab(int width) => cursor = (cursor ~/ width + 1) * width;

  /// Moves the cursor a column back, unless it is at the start.
  void back() {
    if (cursor > 0) {
      cursor--;
    }
  }

  /// Erases as EL does: from the cursor to the end ([mode] 0), from the
  /// start to the cursor (1) or the whole line (2). Cells erased before
  /// others that stay are blank.
  void erase(int mode) {
    switch (mode) {
      case 0 when cursor < _length:
        if (_chars[cursor] == _wide) {
          _chars[cursor - 1] = _space;
        }
        _length = cursor;
      case 1 when _length > 0:
        final end = cursor < _length ? cursor : _length - 1;
        final blank = _idOf(const Style());
        for (var k = 0; k <= end; k++) {
          _chars[k] = _space;
          _styleIds[k] = blank;
        }
        if (end + 1 < _length && _chars[end + 1] == _wide) {
          _chars[end + 1] = _space;
        }
      case 2:
        _length = 0;
    }
  }

  /// The cells as spans, each run of cells in one style a span.
  List<Span> spans() {
    final spans = <Span>[];
    final text = StringBuffer();
    var id = -1;
    for (var k = 0; k < _length; k++) {
      final char = _chars[k];
      if (char == _wide) {
        continue;
      }
      if (_styleIds[k] != id) {
        if (text.isNotEmpty) {
          spans.add(Span(text.toString(), _styles[id]));
          text.clear();
        }
        id = _styleIds[k];
      }
      if (char >= 0) {
        text.writeCharCode(char);
      } else {
        text.write(_clusters[-2 - char]);
      }
    }
    if (text.isNotEmpty) {
      spans.add(Span(text.toString(), _styles[id]));
    }
    return List.unmodifiable(spans);
  }

  /// Empties the line and moves the cursor to its start.
  void clear() {
    _length = 0;
    cursor = 0;
    _clusters.clear();
    _styles.clear();
    _styleIndex.clear();
  }

  int _idOf(Style style) => _styleIndex.putIfAbsent(style, () {
    _styles.add(style);
    return _styles.length - 1;
  });

  int _cluster(String cluster) {
    _clusters.add(cluster);
    return -2 - (_clusters.length - 1);
  }

  /// Writes [char] [width] columns wide at the cursor.
  void _put(int char, int width, int id) {
    final end = cursor + width;
    // a wide character written over in part leaves a blank in its other
    // column
    if (cursor < _length && _chars[cursor] == _wide) {
      _chars[cursor - 1] = _space;
    }
    if (end < _length && _chars[end] == _wide) {
      _chars[end] = _space;
    }
    if (end > _length) {
      _grow(end);
      final blank = cursor > _length ? _idOf(const Style()) : 0;
      for (var k = _length; k < cursor; k++) {
        _chars[k] = _space;
        _styleIds[k] = blank;
      }
      _length = end;
    }
    _chars[cursor] = char;
    _styleIds[cursor] = id;
    if (width == 2) {
      _chars[cursor + 1] = _wide;
      _styleIds[cursor + 1] = id;
    }
    cursor = end;
  }

  /// Joins [mark] to the character before the cursor.
  void _join(String mark) {
    var k = cursor - 1;
    if (k >= 0 && k < _length && _chars[k] == _wide) {
      k--;
    }
    if (k < 0 || k >= _length) {
      return;
    }
    final char = _chars[k];
    final base = char >= 0 ? String.fromCharCode(char) : _clusters[-2 - char];
    _chars[k] = _cluster(base + mark);
  }

  void _grow(int length) {
    if (length <= _chars.length) {
      return;
    }
    var capacity = _chars.length * 2;
    while (capacity < length) {
      capacity *= 2;
    }
    _chars = Int32List(capacity)..setRange(0, _length, _chars);
    _styleIds = Int32List(capacity)..setRange(0, _length, _styleIds);
  }
}
