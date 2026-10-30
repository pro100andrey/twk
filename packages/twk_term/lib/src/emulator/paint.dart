part of 'emulator.dart';

/// Draws an emulator's rows with a canvas: the cells' styles made in the
/// canvas's style table, drawn as they are ([Canvas.runStyled]) and not
/// with a pen each, which the table would keep for good, and the glyph
/// ids in its glyph table; both kept between frames, the styles until
/// either table is swept ([StyleTable.sweeps]).
final class _Painter {
  StyleTable? _styles;
  // the sweeps of the canvas's table and of the emulator's when _ids
  // were made
  var _sweeps = -1;
  var _ownSweeps = -1;
  GlyphTable? _glyphs;
  var _reverse = false;
  // what the default colors are painted in
  Color _fg = Color.defaultColor;
  Color _bg = Color.defaultColor;
  // the canvas's style of each of the emulator's, -1 for none made yet
  var _ids = Int32List(0);
  final _glyphMap = <int, int>{};
  var _buf = Uint32List(256);

  void paint(
    TerminalEmulator t,
    Canvas canvas,
    int x,
    int y,
    int scrollOffset,
    Color fg,
    Color bg,
  ) {
    _prepare(t, canvas, fg, bg);
    final back = t.alternateScreen
        ? 0
        : scrollOffset.clamp(0, t._scrollback.length);
    final sb = t._scrollback;
    for (var row = 0; row < t._height; row++) {
      final line = row < back
          ? sb[sb.length - back + row]
          : t._screen.lines[row - back];
      _line(t, canvas, line, x, y + row);
    }
  }

  void paintLine(
    TerminalEmulator t,
    Canvas canvas,
    TerminalLine line,
    int x,
    int y,
    Color fg,
    Color bg,
  ) {
    _prepare(t, canvas, fg, bg);
    _line(t, canvas, line, x, y);
  }

  /// The pens and glyph ids kept are for [canvas]'s tables, the screen's
  /// reverse video and the default colors in [fg] and [bg].
  void _prepare(TerminalEmulator t, Canvas canvas, Color fg, Color bg) {
    final reverse = t.mode(TerminalMode.reverseVideo);
    if (!identical(canvas.styles, _styles) ||
        canvas.styles.sweeps != _sweeps ||
        t.styles.sweeps != _ownSweeps ||
        reverse != _reverse ||
        fg != _fg ||
        bg != _bg) {
      _styles = canvas.styles;
      _sweeps = canvas.styles.sweeps;
      _ownSweeps = t.styles.sweeps;
      _reverse = reverse;
      _fg = fg;
      _bg = bg;
      _ids = Int32List(0);
    }
    if (!identical(canvas.glyphs, _glyphs)) {
      _glyphs = canvas.glyphs;
      _glyphMap.clear();
    }
  }

  void _line(
    TerminalEmulator t,
    Canvas canvas,
    TerminalLine line,
    int x,
    int y,
  ) {
    final cells = line.cells;
    final styles = line.styles;
    final n = line.width < t._width ? line.width : t._width;
    if (_buf.length < n) {
      _buf = Uint32List(n);
    }
    final buf = _buf;
    final same = identical(_glyphs, t.glyphs);
    var col = 0;
    while (col < n) {
      final s = styles[col];
      var end = col;
      var k = 0;
      while (end < n && styles[end] == s) {
        final c = cells[end++];
        if ((c & kCont) != 0) {
          continue;
        }
        buf[k++] = same || (c & kGlyphMask) < 0x110000 ? c : _glyph(t, c);
      }
      canvas.runStyled(
        x + col,
        y,
        GlyphRun(Uint32List.sublistView(buf, 0, k), end - col),
        _style(t, s),
      );
      col = end;
    }
  }

  /// [word] with its interned glyph id in the canvas's table.
  int _glyph(TerminalEmulator t, int word) {
    final g = word & kGlyphMask;
    final mapped = _glyphMap[g] ??= () {
      final s = t.glyphs.stringOf(g);
      return _glyphs!.intern(s, 0, s.length);
    }();
    return (word & ~kGlyphMask) | mapped;
  }

  /// The canvas's style of style [id] of the emulator's table.
  int _style(TerminalEmulator t, int id) {
    if (id >= _ids.length) {
      var size = _ids.isEmpty ? 64 : _ids.length * 2;
      while (size <= id) {
        size *= 2;
      }
      _ids = Int32List(size)
        ..fillRange(0, size, -1)
        ..setRange(0, _ids.length, _ids);
    }
    final cached = _ids[id];
    if (cached >= 0) {
      return cached;
    }
    final st = t.styles;
    final fg = st.fgOf(id);
    final bg = st.bgOf(id);
    return _ids[id] = _styles!.style(
      fg: fg.isDefault ? _fg : fg,
      bg: bg.isDefault ? _bg : bg,
      attrs: st.attrsOf(id) ^ (_reverse ? Attr.reverse : 0),
      underlineColor: st.underlineColorOf(id),
      link: st.linkOf(id),
    );
  }
}
