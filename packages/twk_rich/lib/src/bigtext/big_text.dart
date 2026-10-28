/// Text in letters several cells tall: [BigText], [RenderBigText] and the
/// fonts they draw in, [BigFont].
library;

import 'package:twk/twk.dart';

import 'glyphs.dart';

// Examples can assume:
// import 'package:twk/twk.dart';
// late BuildContext context;

/// A font of letters several cells tall: a pixel font drawn with full or
/// half blocks, or letters of box drawing. Where the canvas draws blocks or
/// box drawing two columns wide (they are East Asian ambiguous), a font
/// draws the same shapes in braille or ASCII, as big as before.
///
/// A character the font has no glyph for is drawn as one that stands for
/// it: Cyrillic as the Latin letter it looks like, a letter as the other
/// case of it, an accented letter as the letter without the accent; one
/// without such a stand-in is [MissingGlyph].
final class BigFont {
  /// A pixel font whose glyphs are [rows] pixels tall, drawn [down] pixel
  /// rows to a cell row and [across] cells to a pixel column.
  const BigFont._pixels(
    this.name,
    this._sheets, {
    required int rows,
    required int down,
    required int across,
    required int space,
  }) : height = (rows + down - 1) ~/ down,
       _rows = rows,
       _down = down,
       _across = across,
       _space = space * across;

  /// A box-drawing font whose glyphs are [height] cells tall.
  const BigFont._lines(
    this.name,
    this._sheets, {
    required this.height,
    required this._space,
  }) : _rows = 0,
       _down = 1,
       _across = 1;

  /// Pixels as full blocks two cells wide: a line of text is 8 rows, a
  /// letter 10 columns. Letters, digits, ASCII punctuation and Cyrillic;
  /// see [block] for the glyphs.
  static const large = BigFont._pixels(
    'large',
    fiveByEight,
    rows: 8,
    down: 1,
    across: 2,
    space: 3,
  );

  /// Pixels as half blocks, two to a cell: a line of text is 4 rows, a
  /// letter 5 columns. The glyphs are 5×7 pixels with a row for
  /// descenders: both cases of the Latin and Cyrillic letters (Russian and
  /// Ukrainian), digits, the ASCII punctuation and the degree sign. After
  /// tui-big-text's half-height pixels.
  static const block = BigFont._pixels(
    'block',
    fiveByEight,
    rows: 8,
    down: 2,
    across: 1,
    space: 3,
  );

  /// Light box drawing: a line of text is 3 rows, a letter 3 columns.
  /// Capitals of the Latin and Cyrillic letters, digits and the common
  /// punctuation; lowercase is drawn in capitals.
  static const thin = BigFont._lines(
    'thin',
    thinLines,
    height: 3,
    space: 2,
  );

  /// Pixels of a 3×5 pixel font as half blocks: a line of text is 3 rows,
  /// a letter 3 columns. Capitals of the Latin and Cyrillic letters,
  /// digits and the common punctuation; lowercase is drawn in capitals.
  static const small = BigFont._pixels(
    'small',
    threeByFive,
    rows: 5,
    down: 2,
    across: 1,
    space: 2,
  );

  /// The fonts of blocks, largest first: what [BigText] fits text in
  /// unless told otherwise.
  static const List<BigFont> sizes = [large, block, small];

  /// Every built-in font.
  static const List<BigFont> values = [large, block, thin, small];

  /// The font's name, as in `BigFont.block`.
  final String name;

  /// The rows a line of text takes.
  final int height;

  final List<String> _sheets;

  // pixel rows of a glyph; 0 for box drawing
  final int _rows;

  // pixel rows to a cell row
  final int _down;

  // cells to a pixel column
  final int _across;

  // cells of a space
  final int _space;

  /// Cells between two glyphs: a pixel column.
  int get _gap => _across;

  /// What the font draws two columns wide where ambiguous characters are,
  /// and what it draws in their place.
  Map<int, int> get _narrow => _rows == 0 ? _asciiLines : _brailleBlocks;

  @override
  String toString() => 'BigFont.$name';
}

/// How [BigText] draws a character its font has no glyph for, nor one that
/// stands for it.
enum MissingGlyph {
  /// As the font's box, as big as a letter.
  box,

  /// As it is, on the middle row of the line, as wide as the canvas draws
  /// it.
  plain,
}

/// [text] in big letters: each line of it set in [font], or in the first
/// of [fonts] it fits in, the last one when it fits in none; lines are a
/// blank row apart, each placed as [align] says. A character the font has
/// no glyph for is drawn as [missing] says. In [style] merged onto that of
/// the [DefaultTextStyle] above: the letters in its [Style.fg], over its
/// [Style.bg] when it sets one.
///
/// It is as wide as its widest line and as tall as its lines, within its
/// constraints; a font is fitted to the room they give, so in a narrow
/// terminal the same text comes out smaller. A line wider than the room
/// is cut off at the right, as are the rows below it.
///
/// A clock in the largest font that fits, centered, in the theme's
/// primary color:
///
/// ```dart
/// BigText(
///   '12:30',
///   align: TextAlign.center,
///   style: Theme.of(context).primary,
/// )
/// ```
///
/// See also:
///
///  * [RenderBigText], which lays it out and paints it.
///  * [BigFont.values], the fonts to draw in.
final class BigText extends LeafRenderObjectWidget {
  /// Draws [text] in big letters, fitting it to the fonts of
  /// [BigFont.sizes], left-aligned, a missing glyph a box.
  const BigText(
    this.text, {
    super.key,
    this.font,
    this.fonts = BigFont.sizes,
    this.align = TextAlign.left,
    this.style = const Style(),
    this.missing = MissingGlyph.box,
  });

  /// The text to draw, its lines apart at each line break.
  final String text;

  /// The font to draw in whatever room there is; null to fit [fonts].
  final BigFont? font;

  /// The fonts to fit the text in, tried in order; not empty.
  final List<BigFont> fonts;

  /// Where each line sits across the width: [TextAlign.left] by default,
  /// [TextAlign.start] taken as left, [TextAlign.end] as right and
  /// [TextAlign.justify] as left.
  final TextAlign align;

  /// Merged onto the style of the [DefaultTextStyle] above.
  final Style style;

  /// How a character neither the font nor a stand-in has a glyph for is
  /// drawn: [MissingGlyph.box] by default.
  final MissingGlyph missing;

  @override
  RenderBigText createRenderObject(BuildContext context) => RenderBigText(
    text,
    fonts: _fonts,
    align: align,
    style: DefaultTextStyle.of(context).merge(style),
    missing: missing,
  );

  @override
  void updateRenderObject(BuildContext context, RenderBigText renderObject) {
    renderObject
      ..text = text
      ..fonts = _fonts
      ..align = align
      ..style = DefaultTextStyle.of(context).merge(style)
      ..missing = missing;
  }

  List<BigFont> get _fonts => font == null ? fonts : [font!];
}

/// What a [BigText] lays out and paints: the text set in the first of
/// [fonts] it fits in at the largest size its constraints allow, the last
/// when it fits in none ([font]). It is as wide as its widest line and as
/// tall as its lines, within its constraints; a line wider than it starts
/// at its left edge and is cut off, as are the rows below it.
final class RenderBigText extends RenderObject {
  /// Sets [text] in the first of [fonts] it fits in, [fonts] not empty,
  /// drawn with [align], [style] and [missing] as [BigText] has them.
  RenderBigText(
    this._text, {
    List<BigFont> fonts = BigFont.sizes,
    this._align = TextAlign.left,
    this._style = const Style(),
    this._missing = MissingGlyph.box,
  }) : assert(fonts.isNotEmpty, 'no font to draw in'),
       _fonts = fonts,
       _font = fonts.first;

  String _text;

  /// The text drawn; a new one is set again and laid out again.
  String get text => _text;
  set text(String t) {
    if (t != _text) {
      _text = t;
      _sets.clear();
      markNeedsLayout();
    }
  }

  List<BigFont> _fonts;

  /// The fonts the text is fitted to, in order; not empty. A list with
  /// other fonts, or the same in another order, lays it out again.
  List<BigFont> get fonts => _fonts;
  set fonts(List<BigFont> f) {
    assert(f.isNotEmpty, 'no font to draw in');
    if (!_same(f, _fonts)) {
      _fonts = f;
      markNeedsLayout();
    }
  }

  TextAlign _align;

  /// Where each line sits across the width, as [BigText.align] says.
  TextAlign get align => _align;
  set align(TextAlign a) {
    if (a != _align) {
      _align = a;
      markNeedsPaint();
    }
  }

  Style _style;

  /// The style of the letters, merged already onto the text style above:
  /// its [Style.fg] for the letters, its [Style.bg], when it sets one,
  /// filling the whole box.
  Style get style => _style;
  set style(Style s) {
    if (s != _style) {
      _style = s;
      markNeedsPaint();
    }
  }

  MissingGlyph _missing;

  /// How a character no glyph stands for is drawn, as [BigText.missing]
  /// says.
  MissingGlyph get missing => _missing;
  set missing(MissingGlyph m) {
    if (m != _missing) {
      _missing = m;
      _sets.clear();
      markNeedsLayout();
    }
  }

  /// The font of [fonts] the text was set in at the last layout.
  BigFont get font => _font;
  BigFont _font;

  // the text set in each font tried, by the segmenter it was measured with
  final _sets = <BigFont, _Set>{};
  TextSegmenter? _measuredWith;

  /// [text] set in [font], as the owner's segmenter measures it.
  _Set _setIn(BigFont font) {
    final seg = owner?.segmenter ?? _detached;
    if (!identical(seg, _measuredWith)) {
      _sets.clear();
      _measuredWith = seg;
    }
    return _sets[font] ??= _Set(font, _text, seg, _missing);
  }

  /// The first of [fonts] whose lines fit in [maxW] × [maxH] cells; the
  /// last when none does.
  BigFont _fit(int maxW, int maxH) {
    for (final f in _fonts) {
      final set = _setIn(f);
      if (set.width <= maxW && set.height <= maxH) {
        return f;
      }
    }
    return _fonts.last;
  }

  @override
  void performLayout(BoxConstraints c) {
    _font = _fit(c.maxW, c.maxH);
    final set = _setIn(_font);
    width = c.constrainW(set.width);
    height = c.constrainH(set.height);
  }

  // the narrowest it can be is in the last font, whatever the height
  @override
  int computeMinIntrinsicWidth(int height) => _setIn(_fonts.last).width;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      _setIn(_fit(BoxConstraints.unbounded, height)).width;

  @override
  int computeMinIntrinsicHeight(int width) =>
      _setIn(_fit(width, BoxConstraints.unbounded)).height;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      _setIn(_fit(width, BoxConstraints.unbounded)).height;

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final pen = _style.penIn(canvas.styles);
    if (_style.bg != null) {
      canvas.fill(0, 0, width, height, pen);
    }
    final set = _setIn(_font);
    for (var i = 0; i < set.lines.length; i++) {
      final y = i * (_font.height + 1);
      final room = width - set.widths[i];
      final x = room <= 0
          ? 0
          : switch (_align) {
              TextAlign.center => room ~/ 2,
              TextAlign.right || TextAlign.end => room,
              TextAlign.left || TextAlign.justify || TextAlign.start => 0,
            };
      final rows = set.lines[i];
      for (var r = 0; r < rows.length && y + r < height; r++) {
        canvas.text(x, y + r, rows[r], pen);
      }
    }
  }
}

/// Text set in a font: the rows of each of its lines, a string per row,
/// and the cells each line takes.
final class _Set {
  _Set(BigFont font, String text, TextSegmenter seg, MissingGlyph missing)
    : _height = font.height {
    final glyphs = _glyphsOf(font, seg);
    final box = _lookup(glyphs, 0xFFFD)!;
    final gap = ' ' * font._gap;
    final middle = (font.height - 1) ~/ 2;
    final scan = ClusterScan();
    for (final line in text.split('\n')) {
      final rows = [for (var r = 0; r < font.height; r++) StringBuffer()];
      var w = 0;
      for (var i = 0; i < line.length;) {
        final start = i;
        seg.scan(line, i, scan);
        i = scan.end;
        if (scan.width == 0) {
          continue;
        }
        if (w > 0) {
          for (final row in rows) {
            row.write(gap);
          }
          w += gap.length;
        }
        final glyph =
            (scan.length == 1 ? _lookup(glyphs, scan.first) : null) ??
            (missing == MissingGlyph.box ? box : null);
        if (glyph != null) {
          for (var r = 0; r < rows.length; r++) {
            rows[r].write(glyph[r]);
          }
          w += glyph[0].length;
        } else {
          final cluster = line.substring(start, i);
          for (var r = 0; r < rows.length; r++) {
            rows[r].write(r == middle ? cluster : ' ' * scan.width);
          }
          w += scan.width;
        }
      }
      lines.add([for (final row in rows) '$row']);
      widths.add(w);
    }
    for (final w in widths) {
      width = w > width ? w : width;
    }
  }

  final int _height;

  /// The rows of each line.
  final lines = <List<String>>[];

  /// The cells each line takes.
  final widths = <int>[];

  /// The cells the widest line takes.
  var width = 0;

  /// The rows the lines take, a blank row between two.
  int get height => lines.length * (_height + 1) - 1;
}

/// The glyphs of a font: the rows of its cells, a string per row, by the
/// character they draw; as the font draws them ([wide]) and with what it
/// draws two columns wide replaced ([narrow]).
final class _Glyphs {
  _Glyphs(this.wide, this.narrow);

  final Map<int, List<String>> wide;
  final Map<int, List<String>> narrow;
}

final _glyphs = Expando<_Glyphs>();

/// The glyphs of [font] as a canvas whose text [seg] measures draws them
/// one column wide.
Map<int, List<String>> _glyphsOf(BigFont font, TextSegmenter seg) {
  final glyphs = _glyphs[font] ??= _parse(font);
  return _oneColumn(font._narrow.keys, seg) ? glyphs.wide : glyphs.narrow;
}

_Glyphs _parse(BigFont font) {
  final wide = <int, List<String>>{
    0x20: List.filled(font.height, ' ' * font._space),
  };
  for (final sheet in font._sheets) {
    final lines = sheet.split('\n');
    final chars = lines.first.runes.toList();
    final parts = [
      for (var l = 1; l < lines.length; l++)
        if (lines[l].isNotEmpty) lines[l].split('|'),
    ];
    assert(
      parts.length == (font._rows == 0 ? font.height : font._rows) &&
          parts.every((row) => row.length == chars.length + 1),
      'a sheet of $font out of shape: ${lines.first}',
    );
    for (var k = 0; k < chars.length; k++) {
      wide[chars[k]] = font._rows == 0
          ? [for (final row in parts) row[k]]
          : _cells([for (final row in parts) row[k]], font);
    }
  }
  final narrow = font._narrow;
  return _Glyphs(wide, {
    for (final MapEntry(:key, :value) in wide.entries)
      key: [
        for (final row in value)
          String.fromCharCodes(row.runes.map((cp) => narrow[cp] ?? cp)),
      ],
  });
}

/// The cells of a glyph of [font] whose pixel rows are [pixels].
List<String> _cells(List<String> pixels, BigFont font) {
  final across = font._across;
  final w = pixels.first.length;
  return [
    for (var y = 0; y < font._rows; y += font._down)
      String.fromCharCodes([
        for (var x = 0; x < w; x++)
          for (var a = 0; a < across; a++)
            _block(
              pixels[y].codeUnitAt(x) == _pixel,
              font._down == 2 &&
                  y + 1 < font._rows &&
                  pixels[y + 1].codeUnitAt(x) == _pixel,
              font._down,
            ),
      ]),
  ];
}

const _pixel = 0x23; // #

/// The block of a cell whose upper pixel is [top] and lower [bottom]; a
/// full block or none for a cell of one pixel.
int _block(bool top, bool bottom, int down) => down == 1
    ? (top ? 0x2588 : 0x20)
    : top
    ? (bottom ? 0x2588 : 0x2580)
    : (bottom ? 0x2584 : 0x20);

/// The glyph [glyphs] draw [cp] with: its own, else that of the character
/// that stands for it.
List<String>? _lookup(Map<int, List<String>> glyphs, int cp) {
  final other = _otherCase(cp);
  final glyph =
      glyphs[cp] ??
      glyphs[_alike[cp]] ??
      glyphs[other] ??
      glyphs[_alike[other]];
  if (glyph != null) {
    return glyph;
  }
  final base = _base[cp];
  return base == null ? null : _lookup(glyphs, base);
}

/// [cp] in the other case, when that is one code point; -1 otherwise.
int _otherCase(int cp) {
  final s = String.fromCharCode(cp);
  final upper = s.toUpperCase();
  final other = upper != s ? upper : s.toLowerCase();
  return other != s && other.runes.length == 1 ? other.runes.first : -1;
}

/// Each character of [from] to the one at its place in [to].
Map<int, int> _pairs(String from, String to) => {
  for (var i = 0; i < from.length; i++) from.codeUnitAt(i): to.codeUnitAt(i),
};

// Cyrillic letters drawn as the Latin ones they look like
final Map<int, int> _alike = _pairs(
  'АВЕКМНОРСТХІЈЅаеорсухіјѕ',
  'ABEKMHOPCTXIJSaeopcyxijs',
);

// letters drawn as the letter without the accent
final Map<int, int> _base = _pairs(
  'ÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖØÙÚÛÜÝ'
      'àáâãäåçèéêëìíîïñòóôõöøùúûüýÿ'
      'ЁЙЇҐЎёйїґў',
  'AAAAAACEEEEIIIINOOOOOOUUUUY'
      'aaaaaaceeeeiiiinoooooouuuuyy'
      'ЕИІГУеиігу',
);

// half and full blocks, and braille of the same pixels: the upper half
// as the upper two rows of dots, the lower as the lower two
const _brailleBlocks = {0x2588: 0x28FF, 0x2580: 0x281B, 0x2584: 0x28E4};

// box drawing, and the ASCII drawn in its place
final Map<int, int> _asciiLines = {
  ..._pairs('─╴╶═', '---='),
  ..._pairs('│╵╷║', '||||'),
  ..._pairs('┌┐└┘├┤┬┴┼╔╗╚╝', '+++++++++++++'),
  ..._pairs('╭╮╰╯╱╲', r"..''/\"),
};

final _scan = ClusterScan();

/// Whether each of [codePoints] takes one column of a canvas whose text
/// [seg] measures, whatever its neighbours, on every terminal.
bool _oneColumn(Iterable<int> codePoints, TextSegmenter seg) {
  for (final cp in codePoints) {
    // the glyph twice: two clusters of a column each
    final two = String.fromCharCodes([cp, cp]);
    seg.scan(two, 0, _scan);
    if (_scan.end * 2 != two.length ||
        _scan.width != 1 ||
        _scan.joinsNext ||
        _scan.uncertain) {
      return false;
    }
  }
  return true;
}

final _detached = TextSegmenter();

/// Whether [a] and [b] hold the same fonts in the same order.
bool _same(List<BigFont> a, List<BigFont> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i])) {
      return false;
    }
  }
  return true;
}
