/// @docImport 'package:twk_core/twk_core.dart';
library;

import '../vt.dart';

/// What a terminal without synchronized updates (DEC 2026) may show while
/// a frame is drawn: the screens between its steps ([Vt.onStep]), each
/// held to the screen before the frame and the one after it.
///
/// [begin] before the frame is fed to the [vt], [end] after it: [end]
/// lists the cells of those screens that are torn, showing content that
/// is there neither before the frame nor after it. A cell is not torn where
/// it shows what it showed before the frame or what it shows after it, a
/// space (what an erase or a scroll leaves before a cell is written: a
/// flicker at most, which no terminal without synchronized updates
/// avoids), or, in what a scroll moved, the content the scrolls so far
/// brought there, or, where the scrolls after it take it into the
/// scrollback ([Vt.history]) or through a scroll into it, what they carry
/// to where the frame leaves it, on its line of the scrollback or the
/// screen after it: the rows an inline region commits pass through the
/// screen so. A shift of a row's cells (ICH,
/// DCH) brings nothing: the presenter shifts a row only to put its glyphs
/// where the frame has them, so one shifted to another cell is torn.
///
/// What a scroll moved is the rectangle of the move the app asked for
/// (`moves` of [begin], as [Surface.pendingScrolls] records them) where
/// the terminal scrolled its rows (DECSTBM and SU/SD), whole or within
/// margins; else what the terminal scrolled (IL, DL, a line feed). So a
/// rectangle scrolled as whole rows (DECSTBM, without margins on its
/// sides) is torn beside the rectangle wherever the rows there differ:
/// those cells move although nothing asked them to.
///
/// Steps inside a synchronized update are not looked at: the terminal
/// shows none of them.
final class TearCheck {
  /// A check of what [vt] shows.
  TearCheck(this.vt);

  /// The emulator the frame is fed to.
  final Vt vt;

  late List<int> _before;
  late List<String> _beforeTexts;
  final _screens = <_Screen>[];
  final _moved = <_Moved>[];
  var _moves = const <int>[];
  var _rowOffset = 0;

  /// Starts watching: the screen now is the one before the frame. [moves]
  /// are the moves the frame asked for, flat (top, bottom, n, x0, x1)
  /// tuples in the rows of the app's surface, which start at row
  /// [rowOffset] of the [vt] (an inline region below what it printed).
  void begin({List<int> moves = const [], int rowOffset = 0}) {
    final (:keys, :texts) = _keys();
    _before = keys;
    _beforeTexts = texts;
    _screens.clear();
    _moved.clear();
    _moves = List.of(moves);
    _rowOffset = rowOffset;
    vt
      ..onStep = _step
      ..onScroll = _scroll
      ..onShift = _shift;
  }

  /// Stops watching, the frame fed: the cells of the screens between its
  /// steps that are torn, as `step n: (x,y) "text"` lines, [limit] at
  /// most; none where every step showed only what [TearCheck] allows.
  List<String> end({int limit = 5}) {
    vt
      ..onStep = null
      ..onScroll = null
      ..onShift = null;
    final (keys: after, :texts) = _keys();
    String row(List<String> t, int y) =>
        t.sublist(y * vt.width, (y + 1) * vt.width).join();
    final w = vt.width;
    final h = vt.height;
    final out = <String>[];
    for (var n = 0; n < _screens.length; n++) {
      final s = _screens[n];
      if (s.keys.length != w * h) {
        continue; // resized in the frame: a full repaint follows
      }
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = y * w + x;
          final k = s.keys[i];
          if (k == _before[i] || k == after[i]) {
            continue;
          }
          if (s.texts[i] == ' ') {
            continue; // erased or exposed, not yet written
          }
          if (_brought(s, x, y, k) || _carried(s, x, y, k, after)) {
            continue;
          }
          out.add(
            'step ${n + 1} of ${_screens.length}: ($x,$y) "${s.texts[i]}" '
            'in row "${row(s.texts, y)}", before "${row(_beforeTexts, y)}", '
            'after "${row(texts, y)}"',
          );
          if (out.length >= limit) {
            return out..add(_scrolls());
          }
        }
      }
    }
    return out.isEmpty ? out : (out..add(_scrolls()));
  }

  static String _report(_Moved m) => m.dx != 0
      ? 'row ${m.top} from column ${m.left} by ${m.dx} columns'
      : 'rows ${m.top}-${m.bottom - 1} by ${m.by} (columns '
            '${m.termLeft}-${m.termRight - 1}, asked '
            '${m.left}-${m.right - 1})';

  /// The scrolls the terminal made and the moves asked for, for a report.
  String _scrolls() {
    final scrolls = [
      for (final m in _moved) _report(m),
    ];
    return 'the terminal moved ${scrolls.join('; ')}; '
        'moves asked (top, bottom, n, x0, x1): $_moves';
  }

  /// Whether cell ([x], [y]) shows what the scrolls and shifts covering
  /// it before [s] brought there, as [k]: each alone, all of them in turn,
  /// and along the path back through each that covers where it came from.
  /// A row shift (ICH, DCH) brings nothing: what it moved is to be where
  /// the frame leaves it.
  bool _brought(_Screen s, int x, int y, int k) {
    final w = vt.width;
    final h = vt.height;
    var dy = 0;
    var dx = 0;
    bool was(int fx, int fy) =>
        fx >= 0 && fx < w && fy >= 0 && fy < h && _before[fy * w + fx] == k;
    for (var m = 0; m < s.moved; m++) {
      final r = _moved[m];
      if (r.dx != 0) {
        continue; // a shift: below
      }
      if (y < r.top || y >= r.bottom || x < r.left || x >= r.right) {
        continue;
      }
      dy += r.by;
      dx += r.dx;
      if (was(x - dx, y + dy) || was(x - r.dx, y + r.by)) {
        return true;
      }
    }
    // the path back through every move, the last first: content a move
    // brought to where a later one took it from (rows scrolled down, a
    // rectangle in them scrolled again)
    var px = x;
    var py = y;
    for (var m = s.moved - 1; m >= 0; m--) {
      final r = _moved[m];
      if (py < r.top || py >= r.bottom || px < r.left || px >= r.right) {
        continue;
      }
      if (r.dx != 0) {
        // what a row shift (ICH, DCH) moved is to be where the frame has
        // it: a glyph it takes elsewhere shows there until written over
        return false;
      }
      px -= r.dx;
      py += r.by;
      if (was(px, py)) {
        return true;
      }
    }
    return false;
  }

  /// Whether cell ([x], [y]) of [s] shows, as [k], what the scrolls after
  /// [s], one of them into the scrollback at least, carry to where the
  /// frame leaves it: the screen [after] it, or the line of the scrollback
  /// such a scroll took it to. Through a row shift nothing is carried (see
  /// [_brought]).
  bool _carried(_Screen s, int x, int y, int k, List<int> after) {
    final w = vt.width;
    var py = y;
    var scrolledBack = false;
    for (var m = s.moved; m < _moved.length; m++) {
      final r = _moved[m];
      if (py < r.top || py >= r.bottom || x < r.left || x >= r.right) {
        continue;
      }
      if (r.dx != 0) {
        return false;
      }
      scrolledBack = scrolledBack || r.history != null;
      final from = py;
      py -= r.by;
      if (py >= r.top && py < r.bottom) {
        continue;
      }
      // out of what moved: into the scrollback, the top rows of a scroll
      // of the whole screen, else gone
      final line = r.history;
      if (line == null || py >= r.top) {
        return false;
      }
      // row `from` of the screen, its top row 0, went to line `line + from`
      final at = line + from;
      return at < vt.history.length && _historyKey(at, x) == k;
    }
    return scrolledBack && py >= 0 && py < vt.height && after[py * w + x] == k;
  }

  /// The key of cell [x] of line [line] of the scrollback, as [_keys]
  /// makes a screen's.
  int _historyKey(int line, int x) {
    final row = vt.history[line];
    if (x >= row.length) {
      return 0;
    }
    final c = row[x];
    return _key(c, c.role == -1 && x > 0 ? row[x - 1].text : c.text);
  }

  static int _key(VtCell c, String text) =>
      Object.hash(text, c.fg, c.bg, c.ul, c.attrs, c.role, c.link);

  void _step() {
    final (:keys, :texts) = _keys();
    _screens.add(_Screen(keys, texts, _moved.length));
  }

  void _scroll(
    int top,
    int bottom,
    int left,
    int right,
    int by, {
    required bool scrollback,
    required bool lines,
  }) {
    // its top rows into the scrollback, from its line now on
    final history = scrollback ? vt.history.length : null;
    // the move asked for whose rows the terminal scrolled (DECSTBM and
    // SU/SD, exactly those rows by as many): its rectangle is what moves.
    // Not a scroll into the scrollback, which no move asks for (an inline
    // region commits rows so), nor IL or DL, which move the rows down to
    // the bottom margin, whichever the app meant (an inline region scrolls
    // with a DL and an IL)
    for (var i = 0; !scrollback && !lines && i + 4 < _moves.length; i += 5) {
      if (_moves[i] + _rowOffset == top &&
          _moves[i + 1] + _rowOffset == bottom &&
          _moves[i + 2] == by) {
        _moved.add(
          _Moved(
            top,
            bottom,
            _moves[i + 3],
            _moves[i + 4],
            by,
            left,
            right,
            history: history,
          ),
        );
        return;
      }
    }
    _moved.add(
      _Moved(top, bottom, left, right, by, left, right, history: history),
    );
  }

  void _shift(int row, int from, int by) => _moved.add(
    _Moved(row, row + 1, from, vt.width, 0, from, vt.width, dx: by),
  );

  ({List<int> keys, List<String> texts}) _keys() {
    final w = vt.width;
    final h = vt.height;
    final keys = List<int>.filled(w * h, 0);
    final texts = List<String>.filled(w * h, '');
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final c = vt.cell(x, y);
        final i = y * w + x;
        // the trailing half of a wide glyph is the glyph's: its lead's text
        keys[i] = _key(
          c,
          c.role == -1 && x > 0 ? vt.cell(x - 1, y).text : c.text,
        );
        texts[i] = c.text;
      }
    }
    return (keys: keys, texts: texts);
  }
}

/// A screen between two steps, and how many scrolls came before it.
final class _Screen {
  _Screen(this.keys, this.texts, this.moved);

  final List<int> keys;
  final List<String> texts;
  final int moved;
}

/// What a scroll moved: rows [top, bottom) by [left, right) by [by] rows
/// up, the terminal having moved columns [termLeft, termRight) of them,
/// its top rows into the scrollback from its line [history] on where it
/// scrolled the whole screen up; or a shift: one row's cells from [left] by
/// [dx] columns right.
final class _Moved {
  _Moved(
    this.top,
    this.bottom,
    this.left,
    this.right,
    this.by,
    this.termLeft,
    this.termRight, {
    this.dx = 0,
    this.history,
  });

  final int top;
  final int bottom;
  final int left;
  final int right;
  final int by;
  final int termLeft;
  final int termRight;
  final int dx;
  final int? history;
}
