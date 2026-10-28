/// Rows of cells (screen and scrollback), the scrollback's ring and the
/// rewrapping of rows for a new width.
library;

import 'dart:typed_data';

import 'package:twk_core/twk_core.dart' show GlyphTable, kBlank, kCont, kWide;

/// One row of the screen or of the scrollback, its cells as a `Surface`
/// keeps them: per column a glyph word (a glyph id with `kWide` on the
/// leading half of a two-column glyph, `kCont` on its trailing half and
/// `kUncertain` where terminals disagree about its width) and a style id.
final class TerminalLine {
  /// A line of [width] blank cells in [style], 0 the default style.
  TerminalLine(int width, [int style = 0])
    : cells = Uint32List(width),
      styles = Uint32List(width) {
    clear(style);
  }

  /// The glyph word of each column.
  Uint32List cells;

  /// The style id of each column.
  Uint32List styles;

  /// The text runs on into the next line: the line was wrapped here, not
  /// ended.
  var wrapped = false;

  /// How many columns the line has.
  int get width => cells.length;

  /// Every cell blank in [style], not wrapped.
  void clear(int style) {
    final n = cells.length;
    if (_blanks.length < n) {
      _blanks = Uint32List(n)..fillRange(0, n, kBlank);
      _zeros = Uint32List(n);
    }
    // block copies: fillRange is a loop of stores
    cells.setRange(0, n, _blanks);
    if (style == 0) {
      styles.setRange(0, n, _zeros);
    } else {
      styles.fillRange(0, n, style);
    }
    wrapped = false;
  }

  static var _blanks = Uint32List(0);
  static var _zeros = Uint32List(0);

  /// Cells [from, to) blank in [style]; a two-column glyph cut by either
  /// end is blanked whole.
  void erase(int from, int to, int style) {
    final w = cells.length;
    var a = from < 0 ? 0 : from;
    var b = to > w ? w : to;
    if (a >= b) {
      return;
    }
    if (a > 0 && (cells[a] & kCont) != 0) {
      a--;
    }
    if (b < w && (cells[b] & kCont) != 0) {
      b++;
    }
    cells.fillRange(a, b, kBlank);
    styles.fillRange(a, b, style);
  }

  /// Blanks whatever two-column glyph column [x] is a half of.
  void breakWide(int x) {
    final c = cells[x];
    if ((c & kCont) != 0) {
      if (x > 0) {
        cells[x - 1] = kBlank;
      }
      cells[x] = kBlank;
    } else if ((c & kWide) != 0) {
      cells[x] = kBlank;
      if (x + 1 < cells.length) {
        cells[x + 1] = kBlank;
      }
    }
  }

  /// Cut or padded with blanks in [style] to [width] columns; a two-column
  /// glyph cut by the new edge is blanked.
  void resize(int width, int style) {
    final old = cells.length;
    if (width == old) {
      return;
    }
    final c = Uint32List(width);
    final s = Uint32List(width);
    final keep = width < old ? width : old;
    c.setRange(0, keep, cells);
    s.setRange(0, keep, styles);
    if (width > old) {
      c.fillRange(old, width, kBlank);
      s.fillRange(old, width, style);
    } else if (width > 0 && (c[width - 1] & kWide) != 0) {
      c[width - 1] = kBlank;
    }
    cells = c;
    styles = s;
  }

  /// Columns up to the last cell that isn't a blank in the default style.
  int get contentWidth {
    var n = cells.length;
    while (n > 0 && cells[n - 1] == kBlank && styles[n - 1] == 0) {
      n--;
    }
    return n;
  }

  /// The line as text, a two-column glyph once, the blanks at its end
  /// left out.
  String text(GlyphTable glyphs) {
    final sb = StringBuffer();
    var n = cells.length;
    while (n > 0 && cells[n - 1] == kBlank) {
      n--;
    }
    for (var x = 0; x < n; x++) {
      final c = cells[x];
      if ((c & kCont) == 0) {
        sb.write(glyphs.stringOf(c));
      }
    }
    return sb.toString();
  }
}

/// The lines scrolled off the top of the primary screen, oldest first, at
/// most [limit] of them.
final class Scrollback {
  /// An empty scrollback of at most [limit] lines; none where it is 0 or
  /// less.
  Scrollback(int limit) : _limit = limit < 0 ? 0 : limit;

  var _ring = <TerminalLine>[];
  var _start = 0;
  int _limit;

  /// How many lines it keeps at most, 0 for none: set lower, the oldest
  /// go.
  int get limit => _limit;
  set limit(int value) {
    final v = value < 0 ? 0 : value;
    if (v == _limit) {
      return;
    }
    final all = toList();
    _limit = v;
    replace(all);
  }

  /// How many lines it holds.
  int get length => _ring.length;

  /// Line [i], 0 the oldest.
  TerminalLine operator [](int i) => _ring[(_start + i) % _ring.length];

  /// Keeps [line]; returns the line that had to go to stay within [limit]
  /// (to be reused), [line] itself when nothing is kept, or null.
  TerminalLine? push(TerminalLine line) {
    if (_limit == 0) {
      return line;
    }
    if (_ring.length < _limit) {
      _ring.add(line);
      return null;
    }
    final gone = _ring[_start];
    _ring[_start] = line;
    _start = _start + 1 == _ring.length ? 0 : _start + 1;
    return gone;
  }

  /// Drops every line.
  void clear() {
    _ring = <TerminalLine>[];
    _start = 0;
  }

  /// The lines, oldest first.
  List<TerminalLine> toList() => [
    for (var i = 0; i < _ring.length; i++) this[i],
  ];

  /// The lines become [lines], the newest kept where they are more than
  /// [limit].
  void replace(List<TerminalLine> lines) {
    final skip = lines.length > _limit ? lines.length - _limit : 0;
    _ring = lines.sublist(skip);
    _start = 0;
  }
}

/// [lines] rewrapped to [width] columns: each run of lines that ended
/// wrapped is joined with the line after it and split again where [width]
/// ends it, a two-column glyph that would be cut going to the next line
/// whole. The blanks a wrapped line ends with before a two-column glyph
/// (it didn't fit) are dropped, and so are those in the default style at
/// the end of each run. The position ([cursorLine], [cursorCol]) is
/// followed: it comes back with the new lines, its column [width] when it
/// is past the last column of a full line (a wrap pending there).
(List<TerminalLine>, int, int) reflow(
  List<TerminalLine> lines,
  int width,
  int cursorLine,
  int cursorCol,
) {
  final out = <TerminalLine>[];
  var newLine = 0;
  var newCol = 0;
  var cells = Uint32List(256);
  var styles = Uint32List(256);
  for (var i = 0; i < lines.length;) {
    var j = i;
    while (j < lines.length - 1 && lines[j].wrapped) {
      j++;
    }
    // the run's cells, joined
    var n = 0;
    var cursorAt = -1;
    for (var k = i; k <= j; k++) {
      final line = lines[k];
      var len = k < j ? line.width : line.contentWidth;
      if (k < j &&
          len > 0 &&
          line.cells[len - 1] == kBlank &&
          (lines[k + 1].cells.isNotEmpty &&
              (lines[k + 1].cells[0] & kWide) != 0)) {
        len--; // the blank a glyph too wide for the end left
      }
      if (k == cursorLine) {
        cursorAt = n + cursorCol;
      }
      if (n + len > cells.length) {
        final size = (n + len) * 2;
        cells = Uint32List(size)..setRange(0, n, cells);
        styles = Uint32List(size)..setRange(0, n, styles);
      }
      cells.setRange(n, n + len, line.cells);
      styles.setRange(n, n + len, line.styles);
      n += len;
    }
    // split again
    var line = TerminalLine(width);
    var col = 0;
    var found = cursorAt < 0;
    for (var s = 0; s < n; s++) {
      final c = cells[s];
      if ((c & kCont) != 0) {
        continue;
      }
      final w = (c & kWide) != 0 && width > 1 ? 2 : 1;
      if (col + w > width) {
        line.wrapped = true;
        out.add(line);
        line = TerminalLine(width);
        col = 0;
      }
      if (!found && s >= cursorAt) {
        found = true;
        newLine = out.length;
        newCol = col;
      }
      if (w == 2) {
        line.cells[col] = c;
        line.cells[col + 1] = kCont;
        line.styles[col] = styles[s];
        line.styles[col + 1] = styles[s];
      } else {
        line.cells[col] = (c & kWide) != 0 ? kBlank : c;
        line.styles[col] = styles[s];
      }
      col += w;
    }
    if (!found) {
      // past the text: as far past the end of its last line
      newLine = out.length;
      newCol = col + cursorAt - n;
      if (newCol > width) {
        newCol = width;
      }
    }
    out.add(line);
    i = j + 1;
  }
  return (out, newLine, newCol);
}
