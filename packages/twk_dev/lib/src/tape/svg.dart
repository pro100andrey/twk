/// A terminal's screen as SVG: still ([screenSvg]) or animated, a frame
/// a screen ([SvgFilm]), as svg-term draws them.
library;

import 'package:twk_core/twk_core.dart'
    show Attr, Color, CursorShape, kCont, kWide;
import 'package:twk_term/twk_term.dart' show TerminalEmulator, TerminalMode;

import 'glyphs.dart';
import 'theme.dart';

/// How a screen is drawn: its [theme]'s colours, text of [fontSize]
/// pixels in [fontFamily], [padding] pixels around it (the font size
/// when null).
final class SvgLook {
  /// The look of a screen in [theme], by default [TapeTheme.dark], in
  /// text of 16 pixels.
  const SvgLook({
    this.theme = TapeTheme.dark,
    this.fontSize = 16,
    this.fontFamily = defaultFontFamily,
    this.padding,
  });

  /// The screen's colours.
  final TapeTheme theme;

  /// The text's size, in pixels: a cell's height is 1.2 times it.
  final double fontSize;

  /// The text's font, a CSS `font-family`.
  final String fontFamily;

  /// The space around the screen, in pixels; the font size when null.
  final double? padding;

  /// Monospace fonts of macOS, Windows and Linux, then any.
  static const defaultFontFamily =
      "ui-monospace,'SF Mono',Menlo,Consolas,'DejaVu Sans Mono', "
      "'Liberation Mono',monospace";
}

/// [screen] as it shows now, a still SVG.
String screenSvg(TerminalEmulator screen, SvgLook look) =>
    (SvgFilm(look)..add(Duration.zero, screen)).render(Duration.zero);

/// The screens a terminal showed, at their times, made an animated SVG
/// ([render]): every frame drawn in a strip, side by side, which a CSS
/// animation moves under a window of a screen's size, a step a frame,
/// over and over. A row of cells is drawn once (`<defs>`) and used by
/// each frame that shows it.
///
/// The drawing is in units of a 20-unit font, a cell 12 by 24 of them,
/// scaled to [SvgLook.fontSize]: a run of cells of a style is a `<text>`
/// as long as its cells (`textLength`), a wide character one of its own,
/// a run of cells of a background a `<rect>`; the screen's default
/// colours are the theme's, as are colours 0 to 15 of its palette.
final class SvgFilm {
  /// An empty film drawn in [look].
  SvgFilm(this.look, {this.minGap = Duration.zero});

  /// How each frame is drawn.
  final SvgLook look;

  /// A frame added sooner than this after the last one takes its place,
  /// at its time.
  final Duration minGap;

  final _frames = <_Frame>[];
  // each row once, the frames sharing it
  final _rows = <String, String>{};
  String _share(String row) => _rows.putIfAbsent(row, () => row);
  final _textClasses = <String, int>{};
  final _bgClasses = <int, int>{};
  // by colour and weight: `rgb/weight`
  final _strokeClasses = <String, int>{};

  /// How many frames there are.
  int get length => _frames.length;

  /// [screen] as it shows now is the frame from [at] on; one that shows
  /// what the last one did adds nothing.
  void add(Duration at, TerminalEmulator screen) {
    final frame = _Frame(
      at,
      screen.width,
      screen.height,
      [
        for (var y = 0; y < screen.height; y++) _share(_row(screen, y)),
      ],
      _cursor(screen),
    );
    if (_frames.isEmpty) {
      _frames.add(frame);
      return;
    }
    final last = _frames.last;
    if (frame.same(last)) {
      return;
    }
    if (at - last.at < minGap) {
      _frames.removeLast();
      if (_frames.isEmpty || !frame.same(_frames.last)) {
        _frames.add(frame.from(last.at));
      }
      return;
    }
    _frames.add(frame);
  }

  /// The times of the frames, from the start.
  List<Duration> get times => [for (final f in _frames) f.at];

  /// The SVG: the frames over [duration], the last shown to its end, and
  /// then again from the first; the first frame alone, still, when there
  /// is one or [duration] is not past the first frame.
  String render(Duration duration) {
    if (_frames.isEmpty) {
      throw StateError('a film of no frames');
    }
    final frames = [
      for (final f in _frames)
        if (f.at < duration || identical(f, _frames.first)) f,
    ];
    final animated = frames.length > 1;
    final first = frames.first;
    final (cols, rows) = (first.width, first.height);
    final scale = look.fontSize / _font;
    final pad = (look.padding ?? look.fontSize) / scale;
    final w = cols * _cellWidth;
    final h = rows * _cellHeight;
    final viewW = w + 2 * pad;
    final viewH = h + 2 * pad;
    final theme = look.theme;

    // the rows used, an id each in order
    final ids = <String, String>{};
    for (final f in frames) {
      for (final row in f.rows) {
        if (row.isNotEmpty) {
          ids.putIfAbsent(row, () => _id(ids.length));
        }
      }
    }

    final out = StringBuffer()
      ..write(
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'width="${_n(viewW * scale)}" height="${_n(viewH * scale)}" '
        'viewBox="0 0 ${_n(viewW)} ${_n(viewH)}">',
      )
      ..write('<style>text{white-space:pre}')
      ..write('.c{fill:${_hex(theme.cursor)};fill-opacity:.6}');
    for (final MapEntry(key: css, value: i) in _textClasses.entries) {
      out.write('.t$i{$css}');
    }
    for (final MapEntry(key: rgb, value: i) in _bgClasses.entries) {
      out.write('.b$i{fill:${_hex(rgb)}}');
    }
    if (_strokeClasses.isNotEmpty) {
      out.write('path{fill:none;stroke-linecap:square}');
    }
    for (final MapEntry(:key, value: i) in _strokeClasses.entries) {
      final [rgb, weight] = [for (final n in key.split('/')) int.parse(n)];
      out.write(
        '.s$i{stroke:${_hex(rgb)};stroke-width:${weight == 1 ? 2 : 4}}',
      );
    }
    if (animated) {
      final seconds = duration.inMicroseconds / 1e6;
      out.write(
        '.f{animation:f ${_n(seconds, 3)}s steps(1,end) infinite}\n'
        '@keyframes f{',
      );
      for (final (i, f) in frames.indexed) {
        final percent = f.at.inMicroseconds / duration.inMicroseconds * 100;
        out.write('${_n(percent, 3)}%{transform:translateX(${_n(-i * w)}px)}');
      }
      out.write(
        '100%{transform:translateX(${_n(-(frames.length - 1) * w)}px)}}',
      );
    }
    out
      ..write('</style>')
      ..write(
        '<rect width="${_n(viewW)}" height="${_n(viewH)}" rx="8" '
        'fill="${_hex(theme.background)}"/>',
      )
      ..write(
        '<svg x="${_n(pad)}" y="${_n(pad)}" width="${_n(w)}" '
        'height="${_n(h)}" font-family="${_attr(look.fontFamily)}" '
        'font-size="$_font" fill="${_hex(theme.foreground)}">',
      )
      ..write('<defs>');
    for (final MapEntry(key: row, value: id) in ids.entries) {
      out.write('<g id="$id">$row</g>');
    }
    out.write('</defs>${animated ? '<g class="f">' : ''}');
    for (final (i, f) in frames.indexed) {
      out.write(i == 0 ? '<g>' : '<g transform="translate(${_n(i * w)})">');
      for (final (y, row) in f.rows.indexed) {
        if (row.isNotEmpty) {
          final at = y == 0 ? '' : ' y="${y * _cellHeight}"';
          out.write('<use href="#${ids[row]}"$at/>');
        }
      }
      out.write('${f.cursor}</g>');
    }
    out.write('${animated ? '</g>' : ''}</svg></svg>\n');
    return out.toString();
  }

  /// Row [y] of [screen]: its backgrounds and its text, as SVG.
  String _row(TerminalEmulator screen, int y) {
    final width = screen.width;
    final fg = List<int>.filled(width, 0);
    final bg = List<int>.filled(width, 0);
    final css = List<String>.filled(width, '');
    final text = List<String>.filled(width, ' ');
    final wide = List<bool>.filled(width, false);
    // the cells drawn as shapes, by their characters' code points
    final shape = List<int>.filled(width, 0);
    final theme = look.theme;
    final reversed = screen.mode(TerminalMode.reverseVideo);
    final defaultFg = screen.foregroundColor == screen.defaultForeground
        ? theme.foreground
        : screen.foregroundColor;
    final defaultBg = screen.backgroundColor == screen.defaultBackground
        ? theme.background
        : screen.backgroundColor;
    int rgb(Color c, int otherwise) => c.isDefault
        ? otherwise
        : c.isRgb
        ? (c.r << 16) | (c.g << 8) | c.b
        : c.index < 16
        ? theme.ansi[c.index]
        : screen.palette[c.index];
    final styles = screen.styles;
    for (var x = 0; x < width; x++) {
      final word = screen.cellAt(x, y);
      final id = screen.styleAt(x, y);
      final attrs = styles.attrsOf(id);
      var f = rgb(styles.fgOf(id), defaultFg);
      var b = rgb(styles.bgOf(id), defaultBg);
      if ((attrs & Attr.reverse != 0) != reversed) {
        (f, b) = (b, f);
      }
      if (attrs & Attr.dim != 0) {
        f = _mix(f, b);
      }
      fg[x] = f;
      bg[x] = b;
      wide[x] = word & kWide != 0;
      text[x] = word & kCont != 0
          ? ''
          : attrs & Attr.hidden != 0
          ? ' '
          : screen.cellText(x, y);
      css[x] = _css(f, attrs);
      final runes = text[x].runes;
      if (runes.length == 1 &&
          (boxArms(runes.first) != null || block(runes.first) != null)) {
        shape[x] = runes.first;
      }
    }
    final out = StringBuffer();
    // the backgrounds, a run of cells of one a rect
    for (var x = 0; x < width;) {
      final b = bg[x];
      var end = x + 1;
      while (end < width && bg[end] == b) {
        end++;
      }
      if (b != theme.background) {
        final k = _bgClasses.putIfAbsent(b, () => _bgClasses.length);
        out.write(
          '<rect${_x(x)} width="${(end - x) * _cellWidth}" '
          'height="$_cellHeight" class="b$k"/>',
        );
      }
      x = end;
    }
    _blocks(out, shape, fg);
    _lines(out, shape, fg);
    // the text, a run of cells of one style a text, a wide character one
    // of its own; blanks at the ends of a run left out unless decorated
    bool blank(int x) => text[x] == ' ' && !css[x].contains('decoration');
    for (var x = 0; x < width;) {
      if (text[x].isEmpty || blank(x) || shape[x] != 0) {
        x++;
        continue;
      }
      var end = x + 1;
      if (!wide[x]) {
        while (end < width &&
            !wide[end] &&
            text[end].isNotEmpty &&
            shape[end] == 0 &&
            css[end] == css[x]) {
          end++;
        }
        while (blank(end - 1)) {
          end--;
        }
      }
      final cells = wide[x] ? 2 : end - x;
      final k = css[x].isEmpty
          ? null
          : _textClasses.putIfAbsent(css[x], () => _textClasses.length);
      final style = k == null ? '' : ' class="t$k"';
      final length = cells > 1 && !wide[x]
          ? ' textLength="${cells * _cellWidth}"'
          : '';
      out.write(
        '<text${_x(x)} y="$_baseline"$style$length>'
        '${_escape(text.sublist(x, end).join())}</text>',
      );
      x = end;
    }
    return out.toString();
  }

  /// The block elements of a row, by [shape], in their colours [fg]: a
  /// rect a part, those of cells alike side by side one.
  void _blocks(StringBuffer out, List<int> shape, List<int> fg) {
    final width = shape.length;
    for (var x = 0; x < width;) {
      final b = shape[x] == 0 ? null : block(shape[x]);
      if (b == null) {
        x++;
        continue;
      }
      var end = x + 1;
      // a part as wide as the cell joins those of the cells after it
      final (l, _, r, _) = b.rects.first;
      if (b.rects.length == 1 && l == 0 && r == 8) {
        while (end < width && shape[end] == shape[x] && fg[end] == fg[x]) {
          end++;
        }
      }
      final k = _bgClasses.putIfAbsent(fg[x], () => _bgClasses.length);
      final opacity = b.opacity == 1 ? '' : ' fill-opacity="${b.opacity}"';
      for (final (l, t, r, bottom) in b.rects) {
        final left = x * _cellWidth + l * _cellWidth / 8;
        final right = (end - 1) * _cellWidth + r * _cellWidth / 8;
        out.write(
          '<rect x="${_n(left)}" y="${_n(t * _cellHeight / 8)}" '
          'width="${_n(right - left)}" '
          'height="${_n((bottom - t) * _cellHeight / 8)}" '
          'class="b$k"$opacity/>',
        );
      }
      x = end;
    }
  }

  /// The box-drawing lines of a row, by [shape], in their colours [fg]: a
  /// path a colour and weight, a line through cells side by side one.
  void _lines(StringBuffer out, List<int> shape, List<int> fg) {
    final width = shape.length;
    final paths = <String, StringBuffer>{};
    StringBuffer path(int rgb, int weight) =>
        paths.putIfAbsent('$rgb/$weight', StringBuffer.new);
    const middle = _cellHeight ~/ 2;
    const half = _cellWidth ~/ 2;
    // the arms across, a weight each half cell, and their colours
    final across = List<int>.filled(2 * width, 0);
    for (var x = 0; x < width; x++) {
      final arms = shape[x] == 0 ? null : boxArms(shape[x]);
      if (arms == null) {
        continue;
      }
      final centre = x * _cellWidth + half;
      if (arms.round) {
        final left = x * _cellWidth;
        final right = left + _cellWidth;
        path(fg[x], 1).write(switch ((arms.up, arms.right)) {
          (0, 1) =>
            'M$right ${middle}A$half $half 0 0 0 $centre '
                '${middle + half}V$_cellHeight',
          (0, _) =>
            'M$left ${middle}A$half $half 0 0 1 $centre '
                '${middle + half}V$_cellHeight',
          (_, 1) =>
            'M$centre 0V${middle - half}A$half $half 0 0 0 $right '
                '$middle',
          _ => 'M$centre 0V${middle - half}A$half $half 0 0 1 $left $middle',
        });
        continue;
      }
      across[2 * x] = arms.left;
      across[2 * x + 1] = arms.right;
      if (arms.up == arms.down) {
        path(fg[x], arms.up).write('M$centre 0V$_cellHeight');
      } else {
        if (arms.up > 0) {
          path(fg[x], arms.up).write('M$centre 0V$middle');
        }
        if (arms.down > 0) {
          path(fg[x], arms.down).write('M$centre ${middle}V$_cellHeight');
        }
      }
    }
    for (var i = 0; i < across.length;) {
      final weight = across[i];
      var end = i + 1;
      while (end < across.length &&
          across[end] == weight &&
          fg[end ~/ 2] == fg[i ~/ 2]) {
        end++;
      }
      if (weight > 0) {
        path(fg[i ~/ 2], weight).write('M${i * half} ${middle}H${end * half}');
      }
      i = end;
    }
    for (final MapEntry(:key, value: d) in paths.entries) {
      if (d.isEmpty || key.endsWith('/0')) {
        continue;
      }
      final k = _strokeClasses.putIfAbsent(key, () => _strokeClasses.length);
      out.write('<path d="$d" class="s$k"/>');
    }
  }

  /// The CSS of text in [rgb] with [attrs], empty for the default's.
  String _css(int rgb, int attrs) {
    final decorations = [
      if (attrs & Attr.underlineMask != 0) 'underline',
      if (attrs & Attr.strike != 0) 'line-through',
      if (attrs & Attr.overline != 0) 'overline',
    ];
    return [
      if (rgb != look.theme.foreground) 'fill:${_hex(rgb)}',
      if (attrs & Attr.bold != 0) 'font-weight:bold',
      if (attrs & Attr.italic != 0) 'font-style:italic',
      if (decorations.isNotEmpty) 'text-decoration:${decorations.join(' ')}',
    ].join(';');
  }

  /// The cursor of [screen] where it shows, as SVG; empty when hidden.
  static String _cursor(TerminalEmulator screen) {
    if (!screen.cursorVisible) {
      return '';
    }
    final x = screen.cursorX * _cellWidth;
    final y = screen.cursorY * _cellHeight;
    return switch (screen.cursorShape) {
      CursorShape.underline || CursorShape.blinkingUnderline =>
        '<rect x="$x" y="${y + _cellHeight - 2}" width="$_cellWidth" '
            'height="2" class="c"/>',
      CursorShape.bar || CursorShape.blinkingBar =>
        '<rect x="$x" y="$y" width="2" height="$_cellHeight" class="c"/>',
      _ =>
        '<rect x="$x" y="$y" width="$_cellWidth" height="$_cellHeight" '
            'class="c"/>',
    };
  }

  /// The font's size, a cell's and where in its cell text stands, in
  /// the drawing's units.
  static const _font = 20;
  static const _cellWidth = 12;
  static const _cellHeight = 24;
  static const _baseline = 18;

  static String _x(int x) => x == 0 ? '' : ' x="${x * _cellWidth}"';

  /// Halfway between [a] and [b], each 0xRRGGBB.
  static int _mix(int a, int b) {
    var c = 0;
    for (final shift in [16, 8, 0]) {
      c |= ((((a >> shift) & 0xff) + ((b >> shift) & 0xff)) ~/ 2) << shift;
    }
    return c;
  }

  /// A short id for the [n]th row: a, b, ..., z, ba, ...
  static String _id(int n) {
    var s = '';
    var k = n;
    do {
      s = String.fromCharCode(0x61 + k % 26) + s;
      k ~/= 26;
    } while (k > 0);
    return s;
  }
}

/// A screen from [at] on: its size, its [rows] and its [cursor] as SVG.
final class _Frame {
  _Frame(this.at, this.width, this.height, this.rows, this.cursor);

  final Duration at;
  final int width;
  final int height;
  final List<String> rows;
  final String cursor;

  /// This screen from [time] on.
  _Frame from(Duration time) => _Frame(time, width, height, rows, cursor);

  /// [other] shows what this does.
  bool same(_Frame other) {
    if (width != other.width ||
        cursor != other.cursor ||
        rows.length != other.rows.length) {
      return false;
    }
    for (var i = 0; i < rows.length; i++) {
      if (rows[i] != other.rows[i]) {
        return false;
      }
    }
    return true;
  }
}

String _hex(int rgb) => '#${rgb.toRadixString(16).padLeft(6, '0')}';

/// [v] with at most [digits] decimals, no zeros at their end.
String _n(num v, [int digits = 2]) {
  if (v == v.roundToDouble()) {
    return v.round().toString();
  }
  var s = v.toStringAsFixed(digits);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
}

/// [text] for XML: `&`, `<` and `>` escaped, a control character U+FFFD.
String _escape(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    out.write(switch (rune) {
      0x26 => '&amp;',
      0x3c => '&lt;',
      0x3e => '&gt;',
      < 0x20 || 0x7f => '�',
      _ => String.fromCharCode(rune),
    });
  }
  return out.toString();
}

/// [text] for an attribute in double quotes.
String _attr(String text) => _escape(text).replaceAll('"', '&quot;');
