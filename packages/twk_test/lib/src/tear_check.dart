/// @docImport 'package:twk_core/twk_core.dart';
library;

import 'dart:typed_data';

import '../vt.dart';

/// What a terminal without synchronized updates (DEC 2026) may show while
/// a frame is drawn: the screens between its steps ([Vt.onStep]), each
/// held to the screen before the frame and the one after it.
///
/// [begin] before the frame is fed to the [vt], [end] after it: [end]
/// lists the cells of those screens that are torn. A cell is not torn
/// where it shows what it showed before the frame or what it shows after
/// it; where the frame changes it, a space, or what its row showed
/// elsewhere (a row shifted by ICH or DCH); in what a scroll moved, the
/// content the scrolls so far brought there or a blank one exposed. A cell
/// the frame leaves as it is shows nothing else: that is the tear.
///
/// What a scroll moved is the rectangle of the move the app asked for
/// (`moves` of [begin], as [Surface.pendingScrolls] records them) where
/// the terminal scrolled its rows, whole or within margins; else what the
/// terminal scrolled. So a rectangle scrolled as whole rows (DECSTBM,
/// without margins on its sides) is torn beside the rectangle wherever the
/// rows there differ: those cells move although nothing asked them to.
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
    final (:keys, blank: _, :texts) = _keys();
    _before = keys;
    _beforeTexts = texts;
    _screens.clear();
    _moved.clear();
    _moves = List.of(moves);
    _rowOffset = rowOffset;
    vt
      ..onStep = _step
      ..onScroll = _scroll;
  }

  /// Stops watching, the frame fed: the cells of the screens between its
  /// steps that are torn, as `step n: (x,y) "text"` lines, [limit] at
  /// most; none where every step showed only what [TearCheck] allows.
  List<String> end({int limit = 5}) {
    vt
      ..onStep = null
      ..onScroll = null;
    final (keys: after, blank: _, :texts) = _keys();
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
          if (_before[i] != after[i] && (s.texts[i] == ' ' || _fromRow(y, k))) {
            // a cell the frame changes, erased or its row shifted (ICH,
            // DCH) before it is drawn
            continue;
          }
          if (_brought(s, x, y, k)) {
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

  static String _report(_Moved m) =>
      'rows ${m.top}-${m.bottom - 1} by ${m.by} (columns '
      '${m.termLeft}-${m.termRight - 1}, asked ${m.left}-${m.right - 1})';

  /// The scrolls the terminal made and the moves asked for, for a report.
  String _scrolls() {
    final scrolls = [
      for (final m in _moved) _report(m),
    ];
    return 'the terminal scrolled ${scrolls.join('; ')}; '
        'moves asked (top, bottom, n, x0, x1): $_moves';
  }

  /// Whether row [y] showed [k] somewhere before the frame.
  bool _fromRow(int y, int k) {
    final w = vt.width;
    for (var i = y * w; i < (y + 1) * w; i++) {
      if (_before[i] == k) {
        return true;
      }
    }
    return false;
  }

  /// Whether cell ([x], [y]) of [s] is a blank a scroll exposed, or what
  /// the scrolls covering it before [s] brought there, as [k].
  bool _brought(_Screen s, int x, int y, int k) {
    final w = vt.width;
    final h = vt.height;
    var covered = false;
    var sum = 0;
    for (var m = 0; m < s.moved; m++) {
      final r = _moved[m];
      if (y < r.top || y >= r.bottom || x < r.left || x >= r.right) {
        continue;
      }
      covered = true;
      sum += r.by;
      for (final off in [sum, r.by]) {
        final from = y + off;
        if (from >= 0 && from < h && _before[from * w + x] == k) {
          return true;
        }
      }
    }
    return covered && s.blank[y * w + x] == 1;
  }

  void _step() {
    final (:keys, :blank, :texts) = _keys();
    _screens.add(_Screen(keys, blank, texts, _moved.length));
  }

  void _scroll(int top, int bottom, int left, int right, int by) {
    // the move asked for whose rows the terminal scrolled: its rectangle
    // is what moves
    for (var i = 0; i + 4 < _moves.length; i += 5) {
      if (_moves[i] + _rowOffset == top &&
          _moves[i + 1] + _rowOffset == bottom &&
          _moves[i + 2].abs() == by.abs()) {
        _moved.add(
          _Moved(top, bottom, _moves[i + 3], _moves[i + 4], by, left, right),
        );
        return;
      }
    }
    _moved.add(_Moved(top, bottom, left, right, by, left, right));
  }

  ({List<int> keys, Uint8List blank, List<String> texts}) _keys() {
    final w = vt.width;
    final h = vt.height;
    final keys = List<int>.filled(w * h, 0);
    final blank = Uint8List(w * h);
    final texts = List<String>.filled(w * h, '');
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final c = vt.cell(x, y);
        final i = y * w + x;
        keys[i] = Object.hash(
          c.text,
          c.fg,
          c.bg,
          c.ul,
          c.attrs,
          c.role,
          c.link,
        );
        texts[i] = c.text;
        if (c.text == ' ' && c.attrs == 0 && c.role == 0 && c.link == null) {
          blank[i] = 1;
        }
      }
    }
    return (keys: keys, blank: blank, texts: texts);
  }
}

/// A screen between two steps, and how many scrolls came before it.
final class _Screen {
  _Screen(this.keys, this.blank, this.texts, this.moved);

  final List<int> keys;
  final Uint8List blank;
  final List<String> texts;
  final int moved;
}

/// What a scroll moved: rows [top, bottom) by [left, right) by [by] rows;
/// the terminal moved columns [termLeft, termRight) of those rows.
final class _Moved {
  _Moved(
    this.top,
    this.bottom,
    this.left,
    this.right,
    this.by,
    this.termLeft,
    this.termRight,
  );

  final int top;
  final int bottom;
  final int left;
  final int right;
  final int by;
  final int termLeft;
  final int termRight;
}
