// A screen as a golden file of twk_test holds it (matchesScreenFile: the
// text of each row, a style character a cell, a legend) drawn as an SVG:
// the cells' backgrounds as rectangles, their text in a monospace font,
// and the box-drawing and block characters as shapes, so that lines meet
// and blocks fill their cells whatever font the viewer has.
import 'package:twk_core/twk_core.dart' show ClusterScan, TextSegmenter;

/// The width of a cell in the SVG's units.
const cellWidth = 10;

/// The height of a cell in the SVG's units.
const cellHeight = 20;

/// A cell of a [Shot]: its text (`''` for the right half of a wide glyph)
/// and its style as the file's legend names it (`''` for none).
typedef ShotCell = ({String text, String style});

/// A screen read from a golden file.
final class Shot {
  Shot._(this.width, this.height, this.rows);

  /// The screen [source], a golden file, holds; a [FormatException] where
  /// it holds none.
  factory Shot.parse(String source) {
    final lines = source.split('\n');
    final header = RegExp(r'^screen (\d+)×(\d+), ').firstMatch(lines.first);
    if (header == null) {
      throw FormatException('no "screen <columns>×<rows>"', lines.first);
    }
    final width = int.parse(header[1]!);
    final height = int.parse(header[2]!);
    List<String> layer(int at, String name) {
      if (lines[at] != name) {
        throw FormatException('line ${at + 1} is not "$name"', lines[at]);
      }
      return [
        for (final line in lines.sublist(at + 1, at + 1 + height))
          line.substring(1, line.length - 1),
      ];
    }

    final text = layer(1, 'text');
    final styles = layer(2 + height, 'styles');
    final legend = <String, String>{
      for (final line in lines.skip(3 + 2 * height + 1))
        if (line.length > 2) line[0]: line.substring(2),
    };
    final segmenter = TextSegmenter();
    final scan = ClusterScan();
    final rows = <List<ShotCell>>[];
    for (var y = 0; y < height; y++) {
      final glyphs = <String>[];
      final row = text[y];
      for (var i = 0; i < row.length; i = scan.end) {
        segmenter.scan(row, i, scan);
        final glyph = row.substring(i, scan.end);
        if (scan.width == 0 && glyphs.isNotEmpty) {
          glyphs.last += glyph;
        } else {
          glyphs.add(glyph);
          if (scan.width == 2) {
            glyphs.add('');
          }
        }
      }
      rows.add([
        for (var x = 0; x < width; x++)
          (
            text: x < glyphs.length ? glyphs[x] : ' ',
            style: styles[y][x] == ' ' ? '' : legend[styles[y][x]] ?? '',
          ),
      ]);
    }
    return Shot._(width, height, rows);
  }

  /// The screen's columns.
  final int width;

  /// The screen's rows.
  final int height;

  /// The cells, row by row.
  final List<List<ShotCell>> rows;

  /// The part of the screen [width] columns by [height] rows from column
  /// [x] of row [y].
  Shot crop(int x, int y, int width, int height) => Shot._(width, height, [
    for (final row in rows.sublist(y, y + height)) row.sublist(x, x + width),
  ]);
}

/// The colors a screen's default colors and its 16 named ones are.
final class ShotPalette {
  /// A palette of [foreground] and [background], each `0xRRGGBB`, and the
  /// 16 named colors [ansi] (xterm's by default).
  const ShotPalette({
    required this.foreground,
    required this.background,
    this.ansi = _xterm,
  });

  /// The default text color.
  final int foreground;

  /// The default background.
  final int background;

  /// black, red, … brightWhite, as `0xRRGGBB`.
  final List<int> ansi;
}

const _xterm = [
  0x000000, 0xcd0000, 0x00cd00, 0xcdcd00, 0x0000ee, 0xcd00cd, 0x00cdcd, //
  0xe5e5e5, 0x7f7f7f, 0xff0000, 0x00ff00, 0xffff00, 0x5c5cff, 0xff00ff,
  0x00ffff, 0xffffff,
];

const _names = [
  'black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white', //
  'brightBlack', 'brightRed', 'brightGreen', 'brightYellow', 'brightBlue',
  'brightMagenta', 'brightCyan', 'brightWhite',
];

/// A style of the legend resolved against a palette.
final class _Look {
  _Look(String style, ShotPalette palette) {
    int? color(String name) {
      if (name.startsWith('#')) {
        return int.parse(name.substring(1), radix: 16);
      }
      if (RegExp(r'^indexed\((\d+)\)$').firstMatch(name) case final m?) {
        return _indexed(int.parse(m[1]!), palette);
      }
      final named = _names.indexOf(name);
      return named < 0 ? null : palette.ansi[named];
    }

    int? fg;
    int? bg;
    final words = style.split(' ');
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      if (word.isEmpty || word.startsWith('link=')) {
        continue;
      }
      if (word == 'on' && i + 1 < words.length) {
        bg = color(words[++i]);
      } else if (word.startsWith('ul=')) {
        underlineColor = color(word.substring(3));
      } else if (color(word) case final c?) {
        fg = c;
      } else {
        attrs.add(word);
      }
    }
    var f = fg ?? palette.foreground;
    var b = bg ?? palette.background;
    if (attrs.contains('reverse')) {
      (f, b) = (b, f);
    }
    if (attrs.contains('dim')) {
      f = _mix(f, b);
    }
    foreground = f;
    background = b;
  }

  late final int foreground;
  late final int background;
  int? underlineColor;
  final Set<String> attrs = {};

  /// The underline among [attrs], null for none.
  String? get underline =>
      attrs.where((a) => a.toLowerCase().endsWith('underline')).firstOrNull;

  /// What tells two cells' text apart: a run of text is one look.
  String get textKey =>
      '$foreground ${[...attrs.where(_textAttrs.contains)]..sort()}';
}

const _textAttrs = {'bold', 'italic', 'hidden'};

/// The xterm color [index] of the 256.
int _indexed(int index, ShotPalette palette) {
  if (index < 16) {
    return palette.ansi[index];
  }
  if (index >= 232) {
    final v = 8 + 10 * (index - 232);
    return v << 16 | v << 8 | v;
  }
  int level(int n) => n == 0 ? 0 : 55 + 40 * n;
  final i = index - 16;
  return level(i ~/ 36) << 16 | level(i ~/ 6 % 6) << 8 | level(i % 6);
}

/// [a] halfway to [b].
int _mix(int a, int b) {
  int channel(int shift) =>
      ((((a >> shift) & 0xFF) + ((b >> shift) & 0xFF)) ~/ 2) << shift;
  return channel(16) | channel(8) | channel(0);
}

String _hex(int rgb) => '#${rgb.toRadixString(16).padLeft(6, '0')}';

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// [shot] as an SVG, its default colors and named ones [palette]'s.
String svgOf(Shot shot, ShotPalette palette) {
  final looks = <String, _Look>{};
  _Look look(ShotCell cell) =>
      looks.putIfAbsent(cell.style, () => _Look(cell.style, palette));
  final width = shot.width * cellWidth;
  final height = shot.height * cellHeight;
  final backgrounds = StringBuffer();
  final shapes = <int, StringBuffer>{};
  final texts = StringBuffer();
  final lines = StringBuffer();
  for (final (y, row) in shot.rows.indexed) {
    final top = y * cellHeight;
    // the backgrounds, a rectangle a run of one color
    for (var x = 0; x < row.length;) {
      final bg = look(row[x]).background;
      var end = x + 1;
      while (end < row.length && look(row[end]).background == bg) {
        end++;
      }
      if (bg != palette.background) {
        backgrounds.write(
          '<rect x="${x * cellWidth}" y="$top" '
          'width="${(end - x) * cellWidth}" height="$cellHeight" '
          'fill="${_hex(bg)}"/>',
        );
      }
      x = end;
    }
    // the text, a <text> a run of one look; shapes and blanks end a run
    for (var x = 0; x < row.length;) {
      final cell = row[x];
      final l = look(cell);
      if (_rules[cell.text] case final thickness?) {
        // a horizontal line, one rectangle however long
        var end = x + 1;
        while (end < row.length &&
            row[end].text == cell.text &&
            look(row[end]).foreground == l.foreground) {
          end++;
        }
        shapes
            .putIfAbsent(l.foreground, StringBuffer.new)
            .write(
              '<rect x="${x * cellWidth}" '
              'y="${_n(top + cellHeight / 2 - thickness / 2)}" '
              'width="${(end - x) * cellWidth}" height="${_n(thickness)}"/>',
            );
        x = end;
        continue;
      }
      if (_isShape(cell.text)) {
        _shape(
          cell.text,
          x * cellWidth,
          top,
          l.foreground,
          shapes.putIfAbsent(l.foreground, StringBuffer.new),
        );
      }
      if (cell.text.trim().isEmpty ||
          _isShape(cell.text) ||
          l.attrs.contains('hidden')) {
        x++;
        continue;
      }
      var end = x + 1;
      var last = x + 1;
      while (end < row.length) {
        final next = row[end];
        if (_isShape(next.text) || look(next).textKey != l.textKey) {
          break;
        }
        end++;
        if (next.text.trim().isNotEmpty || next.text.isEmpty) {
          last = end;
        }
      }
      // a <text> a character, each at its cell's column: a renderer that
      // takes one x a text (flutter_svg) puts each in its cell whatever the
      // font's advance
      final fill = l.foreground == palette.foreground
          ? ''
          : ' fill="${_hex(l.foreground)}"';
      final weight = l.attrs.contains('bold') ? ' font-weight="bold"' : '';
      final style = l.attrs.contains('italic') ? ' font-style="italic"' : '';
      texts.write('<g$fill$weight$style>');
      for (var i = x; i < last; i++) {
        final glyph = row[i].text;
        if (glyph.trim().isNotEmpty) {
          texts.write(
            '<text x="${i * cellWidth}" y="${top + 15}">'
            '${_escape(glyph)}</text>',
          );
        }
      }
      texts.write('</g>');
      x = last;
    }
    // the lines over and under the text
    for (final (x, cell) in row.indexed) {
      final l = look(cell);
      final left = x * cellWidth;
      final color = _hex(l.underlineColor ?? l.foreground);
      void line(double at, {String dash = ''}) => lines.write(
        '<line x1="$left" x2="${left + cellWidth}" y1="$at" y2="$at" '
        'stroke="$color"$dash/>',
      );
      switch (l.underline) {
        case 'underline':
          line(top + 18.5);
        case 'doubleUnderline':
          line(top + 17.5);
          line(top + 19.5);
        case 'dottedUnderline':
          line(top + 18.5, dash: ' stroke-dasharray="1 2"');
        case 'dashedUnderline':
          line(top + 18.5, dash: ' stroke-dasharray="3 2"');
        case 'curlyUnderline':
          lines.write(
            '<path d="M$left ${top + 18.5}q2.5 -2 5 0t5 0" fill="none" '
            'stroke="$color"/>',
          );
      }
      final textColor = _hex(l.foreground);
      if (l.attrs.contains('strike')) {
        lines.write(
          '<line x1="$left" x2="${left + cellWidth}" y1="${top + 10.5}" '
          'y2="${top + 10.5}" stroke="$textColor"/>',
        );
      }
      if (l.attrs.contains('overline')) {
        lines.write(
          '<line x1="$left" x2="${left + cellWidth}" y1="${top + 0.5}" '
          'y2="${top + 0.5}" stroke="$textColor"/>',
        );
      }
    }
  }
  // one family, not a list: flutter_svg takes the attribute as one name,
  // which an app can give a font of its own; a browser takes it as its
  // monospace font
  const font = 'monospace';
  const svg = 'xmlns="http://www.w3.org/2000/svg"';
  final textGroup =
      '<g font-family="$font" font-size="16.67" '
      'fill="${_hex(palette.foreground)}">$texts</g>';
  return [
    '<svg $svg width="$width" height="$height" viewBox="0 0 $width $height">',
    '<rect width="$width" height="$height" fill="${_hex(palette.background)}"/>',
    '<g shape-rendering="crispEdges">$backgrounds</g>',
    for (final MapEntry(key: color, value: shape) in shapes.entries)
      '<g fill="${_hex(color)}">$shape</g>',
    textGroup,
    '<g stroke-width="1">$lines</g>',
    '</svg>',
    '',
  ].join('\n');
}

/// Whether [text] is drawn as a shape rather than a glyph of the font.
bool _isShape(String text) =>
    text.length == 1 &&
    (_blocks.containsKey(text) ||
        _arms.containsKey(text) ||
        _rounded.containsKey(text) ||
        _doubles.containsKey(text) ||
        _shades.containsKey(text));

/// The block elements as the rectangle of the cell each fills, in eighths:
/// left, top, right, bottom.
const _blocks = <String, (int, int, int, int)>{
  '█': (0, 0, 8, 8),
  '▀': (0, 0, 8, 4),
  '▔': (0, 0, 8, 1),
  '▁': (0, 7, 8, 8),
  '▂': (0, 6, 8, 8),
  '▃': (0, 5, 8, 8),
  '▄': (0, 4, 8, 8),
  '▅': (0, 3, 8, 8),
  '▆': (0, 2, 8, 8),
  '▇': (0, 1, 8, 8),
  '▉': (0, 0, 7, 8),
  '▊': (0, 0, 6, 8),
  '▋': (0, 0, 5, 8),
  '▌': (0, 0, 4, 8),
  '▍': (0, 0, 3, 8),
  '▎': (0, 0, 2, 8),
  '▏': (0, 0, 1, 8),
  '▐': (4, 0, 8, 8),
  '▕': (7, 0, 8, 8),
};

/// The horizontal lines a run of is drawn as one, by their thickness.
const _rules = {'─': 1.5, '━': 3.0};

/// The shades as the opacity of their color over the cell.
const _shades = {'░': 0.25, '▒': 0.5, '▓': 0.75};

/// The box-drawing lines of single strokes: the weight of each arm from
/// the cell's middle, up, right, down and left, 1 light and 2 heavy.
const _arms = <String, (int, int, int, int)>{
  '─': (0, 1, 0, 1),
  '━': (0, 2, 0, 2),
  '│': (1, 0, 1, 0),
  '┃': (2, 0, 2, 0),
  '┌': (0, 1, 1, 0),
  '┐': (0, 0, 1, 1),
  '└': (1, 1, 0, 0),
  '┘': (1, 0, 0, 1),
  '├': (1, 1, 1, 0),
  '┤': (1, 0, 1, 1),
  '┬': (0, 1, 1, 1),
  '┴': (1, 1, 0, 1),
  '┼': (1, 1, 1, 1),
  '╴': (0, 0, 0, 1),
  '╵': (1, 0, 0, 0),
  '╶': (0, 1, 0, 0),
  '╷': (0, 0, 1, 0),
  '╸': (0, 0, 0, 2),
  '╹': (2, 0, 0, 0),
  '╺': (0, 2, 0, 0),
  '╻': (0, 0, 2, 0),
};

/// The rounded corners: the way their arms go, across and down.
const _rounded = <String, (int, int)>{
  '╭': (1, 1),
  '╮': (-1, 1),
  '╰': (1, -1),
  '╯': (-1, -1),
};

/// The double lines: the way their arms go, across and down, 0 for a
/// straight line through the cell.
const _doubles = <String, (int, int)>{
  '═': (2, 0),
  '║': (0, 2),
  '╔': (1, 1),
  '╗': (-1, 1),
  '╚': (1, -1),
  '╝': (-1, -1),
};

/// Writes [text], a shape (_isShape), drawn in the cell at [left], [top]
/// to [out], filled by the group it is written into, which is in [color]:
/// a line stroked says that color itself.
void _shape(String text, int left, int top, int color, StringBuffer out) {
  const w = cellWidth;
  const h = cellHeight;
  final cx = left + w / 2;
  final cy = top + h / 2;
  void rect(num x, num y, num width, num height, [String extra = '']) =>
      out.write(
        '<rect x="${_n(x)}" y="${_n(y)}" width="${_n(width)}" '
        'height="${_n(height)}"$extra/>',
      );
  if (_blocks[text] case (final l, final t, final r, final b)?) {
    rect(left + l * w / 8, top + t * h / 8, (r - l) * w / 8, (b - t) * h / 8);
  } else if (_shades[text] case final opacity?) {
    rect(left, top, w, h, ' opacity="$opacity"');
  } else if (_arms[text] case (final up, final right, final down, final l)?) {
    double t(int weight) => weight == 2 ? 3 : 1.5;
    // each arm from the middle out, from half its thickness before it so
    // that the arms of a corner meet
    if (up > 0) {
      rect(cx - t(up) / 2, top, t(up), h / 2 + t(up) / 2);
    }
    if (down > 0) {
      rect(cx - t(down) / 2, cy - t(down) / 2, t(down), h / 2 + t(down) / 2);
    }
    if (l > 0) {
      rect(left, cy - t(l) / 2, w / 2 + t(l) / 2, t(l));
    }
    if (right > 0) {
      rect(
        cx - t(right) / 2,
        cy - t(right) / 2,
        w / 2 + t(right) / 2,
        t(right),
      );
    }
  } else if (_rounded[text] case (final across, final down)?) {
    const r = w / 2;
    final ex = across > 0 ? left + w : left;
    final ey = down > 0 ? top + h : top;
    out.write(
      '<path d="M${_n(ex)} ${_n(cy)}H${_n(cx + across * r)}'
      'Q${_n(cx)} ${_n(cy)} ${_n(cx)} ${_n(cy + down * r)}V${_n(ey)}" '
      'fill="none" stroke="${_hex(color)}" stroke-width="1.5"/>',
    );
  } else if (_doubles[text] case (final across, final down)?) {
    const d = 2.0;
    const t = 1.0;
    if (down == 0) {
      rect(left, cy - d - t / 2, w, t);
      rect(left, cy + d - t / 2, w, t);
    } else if (across == 0) {
      rect(cx - d - t / 2, top, t, h);
      rect(cx + d - t / 2, top, t, h);
    } else {
      // the line outside the corner, then the one inside it
      for (final side in const [-1, 1]) {
        final x = cx + side * across * d;
        final y = cy + side * down * d;
        final xEnd = across > 0 ? left + w : left;
        final yEnd = down > 0 ? top + h : top;
        final x0 = x < xEnd ? x - t / 2 : xEnd;
        rect(x0, y - t / 2, (xEnd - x).abs() + t / 2, t);
        final y0 = y < yEnd ? y - t / 2 : yEnd;
        rect(x - t / 2, y0, t, (yEnd - y).abs() + t / 2);
      }
    }
  }
}

/// [n] as the SVG writes it: an integer without its fraction.
String _n(num n) => n == n.roundToDouble()
    ? '${n.round()}'
    : n.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
