/// A row of text as the editing widgets draw it in visual order
/// (`TextOrder.visual`): [BidiRow], its characters in the order UAX #9
/// shows them, where the caret shows at each offset and where Left and
/// Right move it; [drawBidiRow] draws one.
library;

import 'dart:typed_data';

import 'package:twk_core/twk_core.dart'
    show
        BidiClass,
        BidiText,
        Canvas,
        TextDirection,
        bidiClassOf,
        bidiMirror,
        graphemeBoundaries;

import 'caret.dart';

/// Whether [text] has a character UAX #9 may draw out of logical order: a
/// letter of a right-to-left script, an Arabic number, or a right-to-left
/// embedding, override or isolate. A row without one in a left-to-right
/// paragraph is drawn as stored.
bool mayReorder(String text) {
  for (var i = 0; i < text.length; i++) {
    var cp = text.codeUnitAt(i);
    if (cp < 0x0590) {
      continue;
    }
    if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < text.length) {
      final lo = text.codeUnitAt(i + 1);
      if (lo >= 0xDC00 && lo <= 0xDFFF) {
        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
        i++;
      }
    }
    switch (bidiClassOf(cp)) {
      case BidiClass.r ||
          BidiClass.al ||
          BidiClass.an ||
          BidiClass.rle ||
          BidiClass.rlo ||
          BidiClass.rli:
        return true;
      case _:
    }
  }
  return false;
}

/// A row of text in the order it is drawn from left to right: its
/// characters (grapheme clusters) at the levels UAX #9 resolves for each
/// paragraph of it as one line, the runs at odd levels reversed (rules L1
/// and L2, [BidiText]). Offsets are into the row's text, columns from its
/// left edge.
///
/// The caret at an offset shows at the edge of the character next to it
/// that is the more deeply embedded (at the higher level), the one after
/// it where they are alike: so it stays with the run being typed, at the
/// end of a right-to-left word in a left-to-right line where the next
/// right-to-left letter goes. That places each offset at a cell boundary
/// of its own, so Left and Right ([moveLeft], [moveRight]), a boundary at
/// a time, reach every offset.
final class BidiRow implements RowColumns {
  /// [text] split into clusters at [starts] (then its length), each at the
  /// column of [columns] (then its width), as [measureClusters] measures
  /// it; each paragraph of it runs in [direction], or where that is null
  /// in its own (rules P2 and P3).
  BidiRow(String text, List<int> starts, List<int> columns, {this.direction})
    : _text = text {
    // the characters: the clusters that start a grapheme
    final graphemes = <int>[
      for (final (from, _) in graphemeBoundaries(text)) from,
    ];
    final unitStarts = <int>[];
    final unitColumns = <int>[];
    var g = 0;
    for (var k = 0; k + 1 < starts.length; k++) {
      final s = starts[k];
      while (g < graphemes.length && graphemes[g] < s) {
        g++;
      }
      if (unitStarts.isEmpty || g < graphemes.length && graphemes[g] == s) {
        unitStarts.add(s);
        unitColumns.add(columns[k]);
      }
    }
    final n = unitStarts.length;
    _starts = Int32List(n + 1)..setRange(0, n, unitStarts);
    _starts[n] = text.length;
    final widths = Int32List(n);
    for (var u = 0; u < n; u++) {
      widths[u] =
          (u + 1 < n ? unitColumns[u + 1] : columns.last) - unitColumns[u];
    }
    _bidi = BidiText(text, direction: direction);
    _levels = Uint8List(n);
    _order = Int32List(n);
    var u = 0;
    for (final p in _bidi.paragraphs) {
      if (p.start == p.end) {
        continue;
      }
      final lv = _bidi.lineLevels(p.start, p.end);
      final first = u;
      while (u < n && _starts[u] < p.end) {
        _levels[u] = lv[_starts[u] - p.start];
        u++;
      }
      _reorder(first, u);
    }
    _position = Int32List(n);
    _x = Int32List(n + 1);
    for (var j = 0; j < n; j++) {
      _position[_order[j]] = j;
      _x[j + 1] = _x[j] + widths[_order[j]];
    }
    _boundary = Int32List(n + 1);
    _at = Int32List(n + 1)..fillRange(0, n + 1, -1);
    for (var i = 0; i <= n; i++) {
      final b = n == 0
          ? 0
          : i == 0
          ? _lead(0)
          : i == n
          ? _trail(n - 1)
          : _levels[i - 1] > _levels[i]
          ? _trail(i - 1)
          : _lead(i);
      _boundary[i] = b;
      if (_at[b] < 0) {
        _at[b] = i;
      }
    }
  }

  /// The direction the paragraphs run in; null for each its own.
  final TextDirection? direction;

  final String _text;
  late final BidiText _bidi;

  // where each character starts, then the text's length; its level; the
  // character at each place from the left and the place of each; the
  // column of each place, then the width; the boundary between places each
  // offset shows at, and the offset at each boundary (-1: none)
  late final Int32List _starts;
  late final Uint8List _levels;
  late final Int32List _order;
  late final Int32List _position;
  late final Int32List _x;
  late final Int32List _boundary;
  late final Int32List _at;

  /// Rule L2 for characters [from, to), a paragraph of them.
  void _reorder(int from, int to) {
    var highest = 0;
    var lowestOdd = 0xFF;
    for (var u = from; u < to; u++) {
      _order[u] = u;
      final l = _levels[u];
      highest = l > highest ? l : highest;
      if (l.isOdd && l < lowestOdd) {
        lowestOdd = l;
      }
    }
    for (var level = highest; level >= lowestOdd; level--) {
      for (var i = from; i < to; i++) {
        if (_levels[_order[i]] < level) {
          continue;
        }
        var j = i + 1;
        while (j < to && _levels[_order[j]] >= level) {
          j++;
        }
        for (var a = i, b = j - 1; a < b; a++, b--) {
          final t = _order[a];
          _order[a] = _order[b];
          _order[b] = t;
        }
        i = j;
      }
    }
  }

  /// The boundary at the edge of character [u] that its text starts from:
  /// its left one, its right one when it runs right to left.
  int _lead(int u) => _position[u] + (_levels[u] & 1);

  /// The boundary at the other edge.
  int _trail(int u) => _position[u] + 1 - (_levels[u] & 1);

  /// How many characters there are.
  int get length => _starts.length - 1;

  /// The columns the row takes.
  @override
  int get width => _x[length];

  /// The offset the character drawn [j]th from the left starts at.
  int start(int j) => _starts[_order[j]];

  /// The offset it ends at.
  int end(int j) => _starts[_order[j] + 1];

  /// The column it is drawn at.
  int x(int j) => _x[j];

  /// Whether it runs right to left.
  bool isRtl(int j) => _levels[_order[j]].isOdd;

  /// What is drawn for it: its text, mirrored when it runs right to left
  /// and is a character with a mirror image (rule L4).
  String shown(int j) {
    final s = start(j);
    final e = end(j);
    if (isRtl(j)) {
      final cp = _text.codeUnitAt(s);
      if (e == s + 1 && bidiMirror(cp) != cp) {
        return String.fromCharCode(bidiMirror(cp));
      }
    }
    return _text.substring(s, e);
  }

  /// The direction of the paragraph [offset] is in.
  TextDirection directionAt(int offset) => _bidi.paragraphAt(offset).direction;

  /// The index of the character [offset] starts or is inside; the length
  /// past the last.
  int _indexOf(int offset) {
    var lo = 0;
    var hi = length;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_starts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// The column the caret shows at for [offset]: the boundary it shows at,
  /// that of the character it is inside for one inside a character.
  @override
  int columnOf(int offset) => _x[_boundary[_indexOf(offset)]];

  /// The offset the caret at [offset] moves to by a cell boundary to the
  /// left; null at the left edge.
  int? moveLeft(int offset) {
    for (var b = _boundary[_indexOf(offset)] - 1; b >= 0; b--) {
      if (_at[b] >= 0) {
        return _starts[_at[b]];
      }
    }
    return null;
  }

  /// The offset it moves to by one to the right; null at the right edge.
  int? moveRight(int offset) {
    for (var b = _boundary[_indexOf(offset)] + 1; b <= length; b++) {
      if (_at[b] >= 0) {
        return _starts[_at[b]];
      }
    }
    return null;
  }

  /// The offset whose caret shows at [column], or at the last boundary
  /// before it; of those before [before] whose boundary is at [leftmost] or
  /// right of it, the leftmost of them for a column left of all.
  int offsetAt(int column, {int? before, int leftmost = -1 << 30}) {
    final limit = before ?? _text.length + 1;
    var best = -1;
    var first = -1;
    for (var b = 0; b <= length; b++) {
      final i = _at[b];
      if (i < 0 || _starts[i] >= limit || _x[b] < leftmost) {
        continue;
      }
      if (first < 0) {
        first = i;
      }
      if (_x[b] > column) {
        break;
      }
      best = i;
    }
    final i = best >= 0 ? best : first;
    return i < 0 ? 0 : _starts[i];
  }

  @override
  int startAtOrAfter(int column) {
    var lo = 0;
    var hi = length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_x[mid] < column) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return _x[lo] < column ? column : _x[lo];
  }

  @override
  int startAtOrBefore(int column) {
    var lo = 0;
    var hi = length;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_x[mid] <= column) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return _x[lo];
  }
}

/// Draws [row], of [text], from column [x] of row [y] of [canvas] in the
/// order it is drawn, each character in the pen [penAt] gives for the
/// offset it starts at: the left-to-right ones one after the other in a
/// pen together, the right-to-left ones each on its own, mirrored.
void drawBidiRow(
  Canvas canvas,
  int x,
  int y,
  String text,
  BidiRow row,
  int Function(int offset) penAt,
) {
  final n = row.length;
  for (var j = 0; j < n;) {
    final s = row.start(j);
    final pen = penAt(s);
    if (row.isRtl(j)) {
      canvas.text(x + row.x(j), y, row.shown(j), pen);
      j++;
      continue;
    }
    var e = row.end(j);
    var k = j + 1;
    while (k < n && !row.isRtl(k) && row.start(k) == e && penAt(e) == pen) {
      e = row.end(k);
      k++;
    }
    canvas.text(x + row.x(j), y, text.substring(s, e), pen);
    j = k;
  }
}
