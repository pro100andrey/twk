part of 'terminal_view.dart';

/// How long the view shows the frame before a synchronized update
/// (mode 2026) that is not ended.
const _syncTimeout = Duration(milliseconds: 150);

/// The most moves of rows kept for the next paint; beyond, the rows that
/// changed are painted instead.
const _maxMoves = 8;

/// What a [TerminalView] lays out and paints: the session's screen, or
/// [scrollOffset] lines back in its scrollback, a copy of each row as it
/// was painted kept to paint only the rows that changed since; the rows
/// the program scrolled moved on the surface first.
final class _RenderTerminal extends RenderObject {
  _RenderTerminal(this._session);

  TerminalSession _session;
  TerminalSession get session => _session;
  set session(TerminalSession s) {
    if (identical(s, _session)) {
      return;
    }
    if (owner != null) {
      _session._views.remove(this);
      s._views.add(this);
    }
    _session = s;
    _offset = 0;
    _seenAdded = s.emulator.scrollbackAdded;
    markNeedsLayout();
  }

  var _focused = false;

  // what the program's default colors are painted in
  Color _fg = Color.defaultColor;
  Color _bg = Color.defaultColor;

  /// Paints the program's default text color in [fg] and its background
  /// in [bg] (null as [Color.defaultColor]).
  void setDefaultColors(Color? fg, Color? bg) {
    final f = fg ?? Color.defaultColor;
    final b = bg ?? Color.defaultColor;
    if (f != _fg || b != _bg) {
      _fg = f;
      _bg = b;
      _full = true;
      markNeedsPaint();
    }
  }

  /// Tells [em] the colors the view paints its default ones in, as RGB,
  /// for the program's queries: a palette color as the emulator's palette
  /// has it, the host's default as [styles] knows it (its text color only
  /// where the host told it).
  void _tellDefaults(TerminalEmulator em, StyleTable styles) {
    int? rgb(Color c, int? host) => c.isDefault
        ? host
        : c.isIndexed
        ? em.palette[c.index]
        : c.value & 0xFFFFFF;
    final fg = rgb(_fg, styles.defaultForegroundRgb);
    if (fg != null) {
      em.defaultForeground = fg;
    }
    em.defaultBackground = rgb(_bg, styles.defaultBackgroundRgb)!;
  }

  /// Whether the cursor shows.
  bool get focused => _focused;
  set focused(bool f) {
    if (f != _focused) {
      _focused = f;
      markNeedsPaint();
    }
  }

  // how many lines back in the scrollback the view shows, and the
  // emulator's scrollbackAdded it was last told
  var _offset = 0;
  var _seenAdded = 0;

  /// How many lines back in the scrollback the view shows; 0 the screen.
  int get scrollOffset => _offset;

  // the rows as they were painted, in the emulator's ids; all of them
  // painted again on the next paint
  var _shown = <TerminalLine>[];

  // the sweeps of the emulator's tables when _shown was painted
  var _shownSweeps = 0;
  var _shownGlyphSweeps = 0;
  var _full = true;
  var _reverse = false;

  // moves of rows since the last paint, (top, bottom, n) each, and whether
  // some were left out
  final _moves = <int>[];
  var _movesLost = false;

  // a synchronized update the view waits for the end of, and whether it
  // waited too long
  Timer? _syncTimer;
  var _syncOverdue = false;

  // what painted it last
  PaintContext? _painted;

  // the cursor as the screen was painted last: column, row in the view (-1
  // for none) and shape
  var _paintedCursorX = -1;
  var _paintedCursorY = 0;
  CursorShape _paintedShape = CursorShape.terminalDefault;

  // how many rows the last paint painted
  var _rowsPainted = 0;

  @override
  bool get isRepaintBoundary => true;

  @override
  void attach(PipelineOwner o) {
    super.attach(o);
    _session._views.add(this);
    _seenAdded = _session.emulator.scrollbackAdded;
    _full = true;
  }

  @override
  void detach() {
    _session._views.remove(this);
    _syncTimer?.cancel();
    _syncTimer = null;
    final ctx = _painted;
    if (ctx != null) {
      hideCaret(ctx, this);
    }
    super.detach();
  }

  @override
  void invalidatePaintCache() => _full = true;

  /// Scrolls [lines] further back in the scrollback (towards the screen
  /// for a negative count), as far as it goes; on the alternate screen,
  /// which keeps none, nothing.
  void scrollBack(int lines) {
    final em = _session.emulator;
    final to = em.alternateScreen
        ? 0
        : (_offset + lines).clamp(0, em.scrollbackLength);
    final d = to - _offset;
    if (d == 0) {
      return;
    }
    _offset = to;
    _move(0, height, -d);
    markNeedsPaint();
  }

  /// The session fed the emulator.
  void _fed() {
    final em = _session.emulator;
    final added = em.scrollbackAdded - _seenAdded;
    _seenAdded = em.scrollbackAdded;
    // what is shown stays where it is
    final to = _offset > 0 ? _offset + added : 0;
    _offset = to > em.scrollbackLength ? em.scrollbackLength : to;
    if (em.mode(TerminalMode.synchronizedOutput)) {
      if (_syncTimer == null && !_syncOverdue) {
        _syncTimer = Timer(_syncTimeout, () {
          _syncTimer = null;
          _syncOverdue = true;
          markNeedsPaint();
        });
      }
    } else {
      _syncTimer?.cancel();
      _syncTimer = null;
      _syncOverdue = false;
    }
    markNeedsPaint();
  }

  void _event(TerminalEvent event) {
    if (event case ModeChanged(mode: TerminalMode.alternateScreen)) {
      _offset = 0;
      _movesLost = true;
    }
  }

  /// Rows [top, bottom) of the screen moved up by [n].
  void _scrolled(int top, int bottom, int n) {
    if (_offset != 0) {
      _movesLost = true;
      return;
    }
    _move(top, bottom, n);
  }

  /// Rows [top, bottom) of the view are to move up by [n] (down when
  /// negative) on the next paint.
  void _move(int top, int bottom, int n) {
    if (_movesLost) {
      return;
    }
    final m = _moves;
    final k = m.length;
    if (k >= 3 &&
        m[k - 3] == top &&
        m[k - 2] == bottom &&
        (m[k - 1] > 0) == (n > 0)) {
      m[k - 1] += n;
    } else if (k >= 3 * _maxMoves) {
      _movesLost = true;
      m.clear();
    } else {
      m
        ..add(top)
        ..add(bottom)
        ..add(n);
    }
  }

  @override
  int computeMaxIntrinsicWidth(int height) => _session.emulator.width;

  @override
  int computeMaxIntrinsicHeight(int width) => _session.emulator.height;

  @override
  void performLayout(BoxConstraints c) {
    final em = _session.emulator;
    width = c.maxW >= BoxConstraints.unbounded
        ? c.constrainW(em.width)
        : c.maxW;
    height = c.maxH >= BoxConstraints.unbounded
        ? c.constrainH(em.height)
        : c.maxH;
    if (width > 0 && height > 0) {
      _session.resize(width, height);
    }
    if (_offset > em.scrollbackLength) {
      _offset = em.scrollbackLength;
    }
    _full = true;
  }

  @override
  void paint(PaintContext ctx) {
    final em = _session.emulator;
    final canvas = ctx.canvas;
    final w = width;
    final h = height;
    _painted = ctx;
    _tellDefaults(em, canvas.styles);
    if (w <= 0 || h <= 0) {
      hideCaret(ctx, this);
      return;
    }
    final sized = _shown.length == h && (h == 0 || _shown[0].width == w);
    // a frame the program is drawing: the rows as they were painted
    final held =
        sized && em.mode(TerminalMode.synchronizedOutput) && !_syncOverdue;
    if (!sized) {
      _shown = [for (var y = 0; y < h; y++) TerminalLine(w)];
      _full = true;
    }
    if (!held) {
      final reverse = em.mode(TerminalMode.reverseVideo);
      if (reverse != _reverse) {
        _reverse = reverse;
        _full = true;
      }
      // swept (StyleTable.sweep, GlyphTable.sweep): the ids kept are of
      // the tables as they were
      if (em.styles.sweeps != _shownSweeps ||
          em.glyphs.sweeps != _shownGlyphSweeps) {
        _shownSweeps = em.styles.sweeps;
        _shownGlyphSweeps = em.glyphs.sweeps;
        _full = true;
      }
      _moveRows(ctx, w, h);
    }
    final full = _full;
    _full = false;
    final back = em.alternateScreen
        ? 0
        : (_offset < em.scrollbackLength ? _offset : em.scrollbackLength);
    final sb = em.scrollbackLength;
    Pen? blank;
    _rowsPainted = 0;
    for (var y = 0; y < h; y++) {
      final shown = _shown[y];
      var changed = full;
      if (!held) {
        final line = y < back
            ? em.scrollbackLine(sb - back + y)
            : (y - back < em.height ? em.line(y - back) : null);
        changed = _copy(line, shown) || changed;
      }
      if (!changed) {
        continue;
      }
      if (em.width < w) {
        blank ??= Pen(
          fg: _fg,
          bg: _bg,
          attrs: _reverse ? Attr.reverse : 0,
        );
        canvas.fill(em.width, y, w - em.width, 1, canvas.styles.pen(blank));
      }
      em.paintLine(canvas, shown, y: y, fg: _fg, bg: _bg);
      _rowsPainted++;
    }
    if (!held) {
      final cy = em.cursorY + back;
      final shows = em.cursorVisible && cy < h && em.cursorX < w;
      _paintedCursorX = shows ? em.cursorX : -1;
      _paintedCursorY = cy;
      _paintedShape = em.cursorShape;
    }
    if (_focused && _paintedCursorX >= 0) {
      showCaret(
        ctx,
        this,
        _paintedCursorX,
        _paintedCursorY,
        shape: _paintedShape,
      );
    } else {
      hideCaret(ctx, this);
    }
  }

  /// Moves the rows of the surface and of [_shown] as the moves since the
  /// last paint did, where the view is wholly visible and the moves are
  /// known; else the rows that changed are painted alone.
  void _moveRows(PaintContext ctx, int w, int h) {
    final moves = _moves;
    if (!_full && !_movesLost && moves.isNotEmpty) {
      var gx = 0;
      var gy = 0;
      for (RenderObject? o = this; o != null; o = o.parent) {
        gx += o.parentData.dx;
        gy += o.parentData.dy;
      }
      if (ctx.canvas.clipContains(gx, gy, gx + w, gy + h)) {
        for (var i = 0; i < moves.length; i += 3) {
          final top = moves[i] < h ? moves[i] : h;
          final bottom = moves[i + 1] < h ? moves[i + 1] : h;
          final n = moves[i + 2];
          if (top < bottom && n != 0) {
            ctx.surface.scrollRect(gx, gx + w, gy + top, gy + bottom, n);
            _moveShown(top, bottom, n);
          }
        }
      }
    }
    moves.clear();
    _movesLost = false;
  }

  /// Moves rows [top, bottom) of [_shown] up by [n] (down when negative);
  /// those that come in are unknown, to be painted.
  void _moveShown(int top, int bottom, int n) {
    final rows = _shown;
    final k = n.abs();
    if (k >= bottom - top) {
      for (var y = top; y < bottom; y++) {
        _forget(rows[y]);
      }
      return;
    }
    final moved = rows.sublist(top, bottom);
    for (var i = 0; i < moved.length; i++) {
      final from = i + n;
      rows[top + i] =
          moved[(from % moved.length + moved.length) % moved.length];
    }
    final (a, b) = n > 0 ? (bottom - k, bottom) : (top, top + k);
    for (var y = a; y < b; y++) {
      _forget(rows[y]);
    }
  }

  /// Makes [row] unlike any row of the emulator, so it is painted.
  static void _forget(TerminalLine row) =>
      row.cells.fillRange(0, row.width, 0xFFFFFFFF);

  /// Copies [line] (null for a blank row) into [shown], cut or padded to
  /// its width; returns whether it changed it.
  static bool _copy(TerminalLine? line, TerminalLine shown) {
    final w = shown.width;
    final cells = shown.cells;
    final styles = shown.styles;
    final n = line == null ? 0 : (line.width < w ? line.width : w);
    var changed = false;
    if (line != null) {
      final from = line.cells;
      final fromStyles = line.styles;
      for (var x = 0; x < n; x++) {
        if (cells[x] != from[x] || styles[x] != fromStyles[x]) {
          changed = true;
          cells.setRange(x, n, from, x);
          styles.setRange(x, n, fromStyles, x);
          break;
        }
      }
      // a two-column glyph cut by the edge
      if (n == w && n < line.width && (cells[n - 1] & kWide) != 0) {
        cells[n - 1] = kBlank;
      }
    }
    for (var x = n; x < w; x++) {
      if (cells[x] != kBlank || styles[x] != 0) {
        changed = true;
        cells.fillRange(x, w, kBlank);
        styles.fillRange(x, w, 0);
        break;
      }
    }
    return changed;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    final em = _session.emulator;
    properties
      ..add('terminal', '${em.width}x${em.height}')
      ..add('scrollOffset', _offset, defaultValue: 0)
      ..add('rows painted', _rowsPainted);
    if (em.alternateScreen) {
      properties.addTag('alternate screen');
    }
    if (_focused) {
      properties.addTag('focused');
    }
  }
}
