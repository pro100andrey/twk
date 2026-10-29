/// Colors ([Color]), text attributes ([Attr]), paint styles ([Pen]) and
/// [StyleTable], the interned cell styles with their SGR sequences and the
/// shortest SGR transitions between them, in a [ColorMode].
///
/// @docImport 'screen.dart';
library;

import 'dart:typed_data';

/// A terminal color: the terminal's default, an entry of its palette, or
/// 24-bit RGB, packed into a small int (always a Smi):
///
///  * `0`: the terminal's default ([defaultColor]);
///  * `0x1000000 | 0xRRGGBB`: 24-bit color (`Color.rgb`);
///  * `0x2000000 | index`: palette entry 0 to 255 (`Color.indexed`).
///
/// A color the terminal can't show is brought down to the nearest it can
/// when it is written ([StyleTable.colorMode]).
///
/// A color is an [Object], so it fills a type parameter bound by one, as
/// that of `TweenAnimationBuilder<Color>` in package:twk is; `Color.lerp`
/// gives the colors between two.
///
/// ```dart
/// const pen = Pen(fg: Color.rgb(255, 128, 0), bg: Color.blue);
/// ```
extension type const Color._(
  /// The color packed in an int: 0 for the default, a palette entry or a
  /// 24-bit color tagged in the bits above 24 ([isIndexed], [isRgb]).
  int value,
) implements Object {
  /// The 24-bit color of red [r], green [g] and blue [b], each 0 to 255.
  const Color.rgb(int r, int g, int b)
    : value = 0x1000000 | (r << 16) | (g << 8) | b;

  /// Entry [index] (0 to 255) of the terminal's palette: 0 to 15 the ANSI
  /// colors, as the terminal's theme shows them, 16 to 231 a 6 x 6 x 6
  /// color cube, 232 to 255 grays.
  const Color.indexed(int index) : value = 0x2000000 | index;

  /// Makes the color [t] of the way from [a], at 0, to [b], at 1.
  ///
  /// Between two RGB colors each channel is as far from [a]'s to [b]'s as
  /// [t] says, rounded, and kept from 0 to 255 where [t] is past the ends
  /// (a curve that overshoots). A palette entry or the default is what
  /// the terminal's theme makes it, which is not known here, so between
  /// colors of which either is not RGB it is [a] until halfway ([t] under
  /// 0.5) and [b] from there.
  ///
  /// ```dart
  /// // Color.rgb(128, 64, 0)
  /// final mid = Color.lerp(
  ///   const Color.rgb(255, 128, 0),
  ///   const Color.rgb(0, 0, 0),
  ///   0.5,
  /// );
  /// ```
  factory Color.lerp(Color a, Color b, double t) {
    if (!a.isRgb || !b.isRgb) {
      return t < 0.5 ? a : b;
    }
    int channel(int x, int y) => (x + (y - x) * t).round().clamp(0, 255);
    return Color.rgb(channel(a.r, b.r), channel(a.g, b.g), channel(a.b, b.b));
  }

  /// The terminal's default color: its text color as a foreground, its
  /// background as a background.
  static const defaultColor = Color._(0);

  /// ANSI black, palette entry 0. The ANSI colors (palette 0 to 15) are
  /// what the terminal's theme makes them.
  static const black = Color.indexed(0);

  /// ANSI red, palette entry 1.
  static const red = Color.indexed(1);

  /// ANSI green, palette entry 2.
  static const green = Color.indexed(2);

  /// ANSI yellow, palette entry 3.
  static const yellow = Color.indexed(3);

  /// ANSI blue, palette entry 4.
  static const blue = Color.indexed(4);

  /// ANSI magenta, palette entry 5.
  static const magenta = Color.indexed(5);

  /// ANSI cyan, palette entry 6.
  static const cyan = Color.indexed(6);

  /// ANSI white, palette entry 7: a light gray in most themes.
  static const white = Color.indexed(7);

  /// ANSI bright black, palette entry 8: a dark gray in most themes.
  static const brightBlack = Color.indexed(8);

  /// ANSI bright white, palette entry 15.
  static const brightWhite = Color.indexed(15);

  /// Whether this is the terminal's default color ([defaultColor]).
  bool get isDefault => value == 0;

  /// Whether this is a 24-bit color (`Color.rgb`).
  bool get isRgb => (value & 0x1000000) != 0;

  /// Whether this is a palette entry (`Color.indexed`).
  bool get isIndexed => (value & 0x2000000) != 0;

  /// The palette entry of a `Color.indexed` color, 0 to 255; meaningless
  /// for another.
  int get index => value & 0xFF;

  /// The red of a `Color.rgb` color, 0 to 255; meaningless for another.
  int get r => (value >> 16) & 0xFF;

  /// The green of a `Color.rgb` color, 0 to 255; meaningless for another.
  int get g => (value >> 8) & 0xFF;

  /// The blue of a `Color.rgb` color, 0 to 255; meaningless for another.
  int get b => value & 0xFF;
}

/// The bits of text attributes, combined with `|` into a [Pen.attrs].
///
/// The underline styles are values of bits 3 to 5 ([underlineMask]), of
/// which a pen has one: `Attr.bold | Attr.curlyUnderline`, not two
/// underlines. A terminal that doesn't know an underline style draws a
/// plain one, or none.
///
/// ```dart
/// const pen = Pen(attrs: Attr.bold | Attr.italic);
/// ```
abstract final class Attr {
  /// Bold text (SGR 1); some terminals also brighten its color.
  static const int bold = 1 << 0;

  /// Faint text (SGR 2).
  static const int dim = 1 << 1;

  /// Italic text (SGR 3).
  static const int italic = 1 << 2;

  /// A single underline (SGR 4), the first of the underline styles, which
  /// are values of bits 3 to 5 ([underlineMask]; 0 for none).
  static const int underline = 1 << 3;

  /// A double underline (SGR 4:2).
  static const int doubleUnderline = 2 << 3;

  /// A curly underline (SGR 4:3), as spell checkers draw.
  static const int curlyUnderline = 3 << 3;

  /// A dotted underline (SGR 4:4).
  static const int dottedUnderline = 4 << 3;

  /// A dashed underline (SGR 4:5).
  static const int dashedUnderline = 5 << 3;

  /// The bits of the underline style: `attrs & Attr.underlineMask` is one
  /// of [underline] to [dashedUnderline], or 0.
  static const int underlineMask = 7 << 3;

  /// Blinking text (SGR 5).
  static const int blink = 1 << 6;

  /// The text and background colors swapped (SGR 7).
  static const int reverse = 1 << 7;

  /// Text not shown, its cells' background still is (SGR 8).
  static const int hidden = 1 << 8;

  /// A line through the text (SGR 9).
  static const int strike = 1 << 9;

  /// A line over the text (SGR 53).
  static const int overline = 1 << 10;

  /// Attributes that make a blank cell look different from an erased one.
  static const int visibleOnBlank = underlineMask | reverse | strike | overline;
}

/// A paint style. `null` colors inherit from the cell being painted over
/// (like Flutter text over a background); colors with alpha < 255 are
/// blended: the background over the existing one, the text over the
/// background the cell ends up with. A background with alpha 0 leaves the
/// cell's background as it was.
///
/// A canvas paints with a pen's id in a [StyleTable] ([StyleTable.pen]),
/// which turns it and the cell's style into the cell's new style. An
/// opaque pen (both colors set, alpha 255) makes the same style over any
/// cell; attributes, the underline color and the link are the pen's
/// whatever the cell had.
///
/// Green text over the background already there, and a half-transparent
/// highlight over it:
///
/// ```dart
/// final styles = StyleTable();
/// final text = styles.pen(const Pen(fg: Color.green, attrs: Attr.bold));
/// final highlight = styles.pen(
///   const Pen(bg: Color.rgb(255, 255, 0), bgAlpha: 64),
/// );
/// ```
final class Pen {
  /// A pen that paints [fg] text over [bg], both inherited when left out,
  /// with [attrs] (bits of [Attr]) and an underline of [underlineColor]
  /// (the text's color by default), and links the cells to [link].
  const Pen({
    this.fg,
    this.bg,
    this.fgAlpha = 255,
    this.bgAlpha = 255,
    this.attrs = 0,
    this.underlineColor = Color.defaultColor,
    this.link,
  });

  /// The text color; null keeps the cell's.
  final Color? fg;

  /// The background color; null keeps the cell's.
  final Color? bg;

  /// How opaque [fg] is, 0 to 255: under 255 it is blended over the
  /// background the cell ends up with. Default-colored text with alpha
  /// stays default while the terminal's text color is unknown
  /// ([StyleTable.defaultForegroundRgb]).
  final int fgAlpha;

  /// How opaque [bg] is, 0 to 255: under 255 it is blended over the cell's
  /// background; 0 leaves that as it was.
  final int bgAlpha;

  /// The text attributes, bits of [Attr]; they replace the cell's.
  final int attrs;

  /// The color of the underline ([Attr.underlineMask]); the default color
  /// draws it in the text's color.
  final Color underlineColor;

  /// Hyperlink target (OSC 8), e.g. `https://…` or `file:///…`; replaces
  /// the link of the cells painted over (like attributes, not inherited).
  final String? link;

  @override
  bool operator ==(Object other) =>
      other is Pen &&
      other.fg == fg &&
      other.bg == bg &&
      other.fgAlpha == fgAlpha &&
      other.bgAlpha == bgAlpha &&
      other.attrs == attrs &&
      other.underlineColor == underlineColor &&
      other.link == link;

  @override
  int get hashCode =>
      Object.hash(fg, bg, fgAlpha, bgAlpha, attrs, underlineColor, link);
}

/// The colors a terminal shows, which a [StyleTable] brings its colors
/// down to as it writes them.
enum ColorMode {
  /// 24-bit RGB: every color as it is.
  trueColor,

  /// The 256 palette entries: an RGB color is written as the nearest of
  /// the color cube and the grays.
  ansi256,

  /// The 16 ANSI colors: an RGB color or a palette entry above 15 is
  /// written as the nearest of them, measured by xterm's palette.
  ansi16,

  /// No colors: only attributes are written.
  none,
}

/// xterm's default palette: what a palette color is blended as where the
/// terminal didn't tell its own ([StyleTable.paletteRgb]), and what color
/// downgrading measures by.
final Int32List _palette = () {
  const base = <int>[
    0x000000, 0xcd0000, 0x00cd00, 0xcdcd00, 0x0000ee, 0xcd00cd, 0x00cdcd,
    0xe5e5e5, 0x7f7f7f, 0xff0000, 0x00ff00, 0xffff00, 0x5c5cff, 0xff00ff,
    0x00ffff, 0xffffff, //
  ];
  final p = Int32List(256)..setRange(0, 16, base);
  const levels = <int>[0, 95, 135, 175, 215, 255];
  for (var i = 0; i < 216; i++) {
    p[16 + i] =
        (levels[i ~/ 36] << 16) | (levels[(i ~/ 6) % 6] << 8) | levels[i % 6];
  }
  for (var i = 0; i < 24; i++) {
    final v = 8 + 10 * i;
    p[232 + i] = (v << 16) | (v << 8) | v;
  }
  return p;
}();

/// Interned cell styles (style id 0 = all defaults) and registered pens.
///
/// A cell holds a style id: its colors, attributes and link, each set of
/// them interned once ([style]). A canvas paints with pen ids ([pen]),
/// which [compose] turns, with the style of the cell painted over, into
/// the cell's new style, blending colors with alpha with the cell's and
/// the terminal's default colors ([defaultBackgroundRgb],
/// [defaultForegroundRgb], [paletteRgb]). The presenter writes a style's
/// SGR sequence ([sgrFromReset], [transition]) in [colorMode].
///
/// All lookups on the paint and encode paths are open-addressing probes into
/// typed arrays: no allocation once the working set of styles is known.
///
/// ```dart
/// final styles = StyleTable(colorMode: ColorMode.ansi256);
/// final warning = styles.pen(const Pen(fg: Color.yellow, attrs: Attr.bold));
/// final cell = styles.compose(0, warning); // over a default cell
/// print(styles.attrsOf(cell) & Attr.bold != 0); // true
/// ```
///
/// See also:
///
///  * [Screen.styles], the table of a screen, whose canvas paints with
///    its pens.
final class StyleTable {
  /// A table with only style 0, all defaults, and no pens.
  ///
  /// [colorMode] is the colors the terminal shows, true color by default;
  /// [styledUnderlines] whether it shows the underline styles, as it does
  /// by default; [defaultBackgroundRgb] the RGB of its default background,
  /// black by default, until the terminal tells it.
  StyleTable({
    this._colorMode = ColorMode.trueColor,
    this._styledUnderlines = true,
    this._defaultBg = 0,
  }) {
    _intern(0, 0, 0, 0, 0); // id 0
  }

  // ---- resolved styles ------------------------------------------------------
  var _fg = Int32List(64);
  var _bg = Int32List(64);
  var _ul = Int32List(64);
  var _attrs = Int32List(64);
  var _link = Int32List(64);
  final _uris = <String>[''];
  final _uriIds = <String, int>{};
  var _count = 0;
  var _styleSlots = Int32List(128)..fillRange(0, 128, -1);

  /// How many styles are interned: style ids are 0 to one less.
  int get length => _count;

  /// The text color of style [id].
  Color fgOf(int id) => Color._(_fg[id]);

  /// The background color of style [id].
  Color bgOf(int id) => Color._(_bg[id]);

  /// The underline color of style [id]; the default color for the text's.
  Color underlineColorOf(int id) => Color._(_ul[id]);

  /// The attributes of style [id], bits of [Attr].
  int attrsOf(int id) => _attrs[id];

  /// RGB the terminal's default background is assumed to have (for alpha
  /// blending over "default"). Can be filled from an OSC 11 query.
  int get defaultBackgroundRgb => _defaultBg;
  set defaultBackgroundRgb(int rgb) {
    if (rgb != _defaultBg) {
      _defaultBg = rgb;
      _clearComposeCache();
    }
  }

  int _defaultBg;

  /// RGB of the terminal's default text color (OSC 10), for blending
  /// default-colored text with alpha; while it is unknown (null) such text
  /// stays default.
  int? get defaultForegroundRgb => _defaultFg;
  set defaultForegroundRgb(int? rgb) {
    if (rgb != _defaultFg) {
      _defaultFg = rgb;
      _clearComposeCache();
    }
  }

  int? _defaultFg;

  /// RGB palette entry [index] (0..255) is blended as: the terminal's own
  /// where it told it (OSC 4, [setPaletteRgb]), xterm's otherwise.
  int paletteRgb(int index) => _rgbs[index & 0xFF];

  /// The RGB (0xRRGGBB) [color] shows as: its own; a palette entry's as
  /// [paletteRgb] has it; the default background's
  /// ([defaultBackgroundRgb]), or with [text] the default text color's
  /// ([defaultForegroundRgb]), null where the terminal has not told it.
  /// What a color is mixed from, a fade or a tint over cells of any color.
  int? rgbOf(Color color, {bool text = false}) {
    if (color.isRgb) {
      return color.value & 0xFFFFFF;
    }
    if (color.isDefault) {
      return text ? _defaultFg : _defaultBg;
    }
    return _rgbs[color.index & 0xFF];
  }

  /// The terminal shows palette entry [index] (0..255) as [rgb]
  /// (0xRRGGBB, from an OSC 4 query); null puts back xterm's. Colors with
  /// alpha over or under that entry are blended with it from then on.
  ///
  /// Throws a [RangeError] when [index] is not 0 to 255.
  void setPaletteRgb(int index, int? rgb) {
    RangeError.checkValueInInterval(index, 0, 255, 'index');
    final value = rgb == null ? _palette[index] : rgb & 0xFFFFFF;
    if (value == _rgbs[index]) {
      return;
    }
    if (identical(_rgbs, _palette)) {
      _rgbs = Int32List.fromList(_palette); // copied on the first change
    }
    _rgbs[index] = value;
    _clearComposeCache();
  }

  /// xterm's table until an entry is set.
  Int32List _rgbs = _palette;

  ColorMode _colorMode;

  /// The colors the terminal shows: a color it can't is written as the
  /// nearest it can.
  ///
  /// Setting it rewrites the SGR sequences from then on; the styles keep
  /// their colors as they were painted.
  ColorMode get colorMode => _colorMode;
  set colorMode(ColorMode m) {
    if (m == _colorMode) {
      return;
    }
    _colorMode = m;
    _sgr.clear();
    _transitions.clear();
  }

  bool _styledUnderlines;

  /// Whether the terminal shows the underline styles (SGR `4:2` to `4:5`,
  /// `TerminalCaps.styledUnderlines`); false writes each as a plain
  /// underline (`4`).
  ///
  /// Setting it rewrites the SGR sequences from then on, as [colorMode].
  bool get styledUnderlines => _styledUnderlines;
  set styledUnderlines(bool on) {
    if (on == _styledUnderlines) {
      return;
    }
    _styledUnderlines = on;
    _sgr.clear();
    _transitions.clear();
  }

  /// The attributes of style [id] as written: a styled underline a plain
  /// one where the terminal has no [styledUnderlines].
  int _sentAttrs(int id) {
    final a = _attrs[id];
    if (_styledUnderlines || (a & Attr.underlineMask) == 0) {
      return a;
    }
    return (a & ~Attr.underlineMask) | Attr.underline;
  }

  /// The id of the style of [fg] text over [bg] with [attrs], an underline
  /// of [underlineColor] and [link], interned: the same id for the same
  /// values. All left out, it is 0.
  int style({
    Color fg = Color.defaultColor,
    Color bg = Color.defaultColor,
    int attrs = 0,
    Color underlineColor = Color.defaultColor,
    String? link,
  }) => _intern(
    fg.value,
    bg.value,
    attrs,
    underlineColor.value,
    link == null ? 0 : linkId(link),
  );

  /// Id of a hyperlink target (0 = no link).
  int linkId(String uri) {
    if (uri.isEmpty) {
      return 0;
    }
    final cached = _uriIds[uri];
    if (cached != null) {
      return cached;
    }
    _uris.add(uri);
    return _uriIds[uri] = _uris.length - 1;
  }

  /// The link id of style [id] ([linkId]); 0 for none.
  int linkIdOf(int id) => _link[id];

  /// The hyperlink target of style [id], or null for none.
  String? linkOf(int id) => _link[id] == 0 ? null : _uris[_link[id]];

  /// The hyperlink target of [linkId] ([linkId]); empty for 0.
  String linkUri(int linkId) => _uris[linkId];

  /// A blank of this style can be produced by an erase (EL/ECH/ED/ICH/
  /// DCH/SU): nothing visible on a space and no hyperlink.
  @pragma('vm:prefer-inline')
  bool erasable(int id) =>
      (_attrs[id] & Attr.visibleOnBlank) == 0 && _link[id] == 0;

  static int _hash5(int a, int b, int c, int d, int e) {
    var h =
        a * 0x9E3779B1 ^
        (b * 0x85EBCA77) ^
        (c * 0xC2B2AE3D) ^
        (d * 0x27D4EB2F) ^
        (e * 0x165667B1);
    h ^= h >> 15;
    return h & 0x3FFFFFFF;
  }

  int _intern(int fg, int bg, int attrs, int ul, int link) {
    final mask = _styleSlots.length - 1;
    var slot = _hash5(fg, bg, attrs, ul, link) & mask;
    while (true) {
      final id = _styleSlots[slot];
      if (id < 0) {
        break;
      }
      if (_link[id] == link &&
          _fg[id] == fg &&
          _bg[id] == bg &&
          _attrs[id] == attrs &&
          _ul[id] == ul) {
        return id;
      }
      slot = (slot + 1) & mask;
    }
    final id = _count++;
    if (id == _fg.length) {
      _fg = _grow(_fg);
      _bg = _grow(_bg);
      _ul = _grow(_ul);
      _attrs = _grow(_attrs);
      _link = _grow(_link);
    }
    _fg[id] = fg;
    _bg[id] = bg;
    _attrs[id] = attrs;
    _link[id] = link;
    _ul[id] = ul;
    if (_count * 2 > _styleSlots.length) {
      _rehashStyles();
    } else {
      _styleSlots[slot] = id;
    }
    return id;
  }

  void _rehashStyles() {
    final n = _styleSlots.length * 2;
    _styleSlots = Int32List(n)..fillRange(0, n, -1);
    final mask = n - 1;
    for (var id = 0; id < _count; id++) {
      var slot =
          _hash5(_fg[id], _bg[id], _attrs[id], _ul[id], _link[id]) & mask;
      while (_styleSlots[slot] >= 0) {
        slot = (slot + 1) & mask;
      }
      _styleSlots[slot] = id;
    }
  }

  static Int32List _grow(Int32List a) => Int32List(a.length * 2)..setAll(0, a);

  // ---- blank appearance -----------------------------------------------------
  var _blank = Int32List(64)..fillRange(0, 64, -1);

  /// The style a *blank* cell of style [id] looks like: only the background
  /// and the attributes visible on a space matter, plus fg under reverse
  /// video and when it colours a line drawn on the space (strike-through,
  /// overline, an underline without its own colour). Two blanks with the
  /// same blank style are indistinguishable, so the presenter neither
  /// rewrites nor switches SGR for them.
  @pragma('vm:prefer-inline')
  int blankStyleOf(int id) {
    if (id < _blank.length) {
      final b = _blank[id];
      if (b >= 0) {
        return b;
      }
    }
    return _blankSlow(id);
  }

  int _blankSlow(int id) {
    final a = _attrs[id];
    final int result;
    if ((a & Attr.reverse) != 0) {
      result = id;
    } else {
      final keep = a & (Attr.underlineMask | Attr.strike | Attr.overline);
      final ul = (keep & Attr.underlineMask) != 0 ? _ul[id] : 0;
      final linesUseFg =
          (keep & (Attr.strike | Attr.overline)) != 0 ||
          ((keep & Attr.underlineMask) != 0 && ul == 0);
      result = _intern(linesUseFg ? _fg[id] : 0, _bg[id], keep, ul, _link[id]);
    }
    if (id >= _blank.length) {
      var n = _blank.length * 2;
      while (n <= id) {
        n *= 2;
      }
      final grown = Int32List(n)
        ..fillRange(0, n, -1)
        ..setRange(0, _blank.length, _blank);
      _blank = grown;
    }
    _blank[id] = result;
    return result;
  }

  // ---- pens -----------------------------------------------------------------
  final _penIds = <Pen, int>{};
  final _pens = <Pen>[];
  var _penOpaque = Int32List(16);

  /// Registers [pen] and returns its id (stable for the table's lifetime).
  int pen(Pen pen) {
    final existing = _penIds[pen];
    if (existing != null) {
      return existing;
    }
    final id = _pens.length;
    _pens.add(pen);
    _penIds[pen] = id;
    if (id == _penOpaque.length) {
      _penOpaque = _grow(_penOpaque);
    }
    _penOpaque[id] =
        pen.fg != null &&
            pen.bg != null &&
            pen.fgAlpha == 255 &&
            pen.bgAlpha == 255
        ? style(
            fg: pen.fg!,
            bg: pen.bg!,
            attrs: pen.attrs,
            underlineColor: pen.underlineColor,
            link: pen.link,
          )
        : -1;
    return id;
  }

  /// The pen registered as [id] ([pen]).
  Pen penOf(int id) => _pens[id];

  /// The resolved style id a pen always produces, or -1 when the result
  /// depends on the cell underneath (inherited or translucent colors).
  @pragma('vm:prefer-inline')
  int opaqueStyleOf(int penId) {
    assert(penId < _pens.length, _unknownPen);
    return _penOpaque[penId];
  }

  static const _unknownPen = 'pen id not registered in this StyleTable';

  // compose cache: (style, pen) -> style
  var _composeKeysA = Int32List(256)..fillRange(0, 256, -1);
  var _composeKeysB = Int32List(256);
  var _composeValues = Int32List(256);
  var _composeCount = 0;

  /// Style that results from painting with [penId] over a cell of [styleId].
  @pragma('vm:prefer-inline')
  int compose(int styleId, int penId) {
    assert(penId < _pens.length, _unknownPen);
    final opaque = _penOpaque[penId];
    if (opaque >= 0) {
      return opaque;
    }
    final mask = _composeKeysA.length - 1;
    var slot =
        ((styleId * 0x9E3779B1) ^ (penId * 0x85EBCA77)) & 0x3FFFFFFF & mask;
    while (true) {
      final a = _composeKeysA[slot];
      if (a < 0) {
        break;
      }
      if (a == styleId && _composeKeysB[slot] == penId) {
        return _composeValues[slot];
      }
      slot = (slot + 1) & mask;
    }
    final result = _composeSlow(styleId, penId);
    _composeKeysA[slot] = styleId;
    _composeKeysB[slot] = penId;
    _composeValues[slot] = result;
    if (++_composeCount * 2 > _composeKeysA.length) {
      _rehashCompose();
    }
    return result;
  }

  void _rehashCompose() {
    final oldA = _composeKeysA;
    final oldB = _composeKeysB;
    final oldV = _composeValues;
    final n = oldA.length * 2;
    _composeKeysA = Int32List(n)..fillRange(0, n, -1);
    _composeKeysB = Int32List(n);
    _composeValues = Int32List(n);
    final mask = n - 1;
    for (var i = 0; i < oldA.length; i++) {
      final a = oldA[i];
      if (a < 0) {
        continue;
      }
      var slot =
          ((a * 0x9E3779B1) ^ (oldB[i] * 0x85EBCA77)) & 0x3FFFFFFF & mask;
      while (_composeKeysA[slot] >= 0) {
        slot = (slot + 1) & mask;
      }
      _composeKeysA[slot] = a;
      _composeKeysB[slot] = oldB[i];
      _composeValues[slot] = oldV[i];
    }
  }

  void _clearComposeCache() {
    _composeKeysA.fillRange(0, _composeKeysA.length, -1);
    _composeCount = 0;
  }

  int _composeSlow(int styleId, int penId) {
    final p = _pens[penId];
    final existingBg = _bg[styleId];
    int bg;
    if (p.bg == null || p.bgAlpha == 0) {
      bg = existingBg;
    } else if (p.bgAlpha < 255) {
      bg = _blend(p.bg!.value, p.bgAlpha, existingBg);
    } else {
      bg = p.bg!.value;
    }
    // text blends over the background it ends up on (the pen's own one if
    // it sets one)
    int fg;
    if (p.fg == null) {
      fg = _fg[styleId];
    } else if (p.fgAlpha < 255 && (p.fg!.value != 0 || _defaultFg != null)) {
      fg = _blend(p.fg!.value, p.fgAlpha, bg, srcDefault: _defaultFg);
    } else {
      fg = p.fg!.value;
    }
    return _intern(
      fg,
      bg,
      p.attrs,
      p.underlineColor.value,
      p.link == null ? 0 : linkId(p.link!),
    );
  }

  int _rgbOf(int color, int defaultRgb) {
    if (color == 0) {
      return defaultRgb;
    }
    if ((color & 0x2000000) != 0) {
      return _rgbs[color & 0xFF];
    }
    return color & 0xFFFFFF;
  }

  /// [src] over [dstColor], a background. [srcDefault] is the RGB of a
  /// default [src] when that isn't the background's.
  int _blend(int src, int alpha, int dstColor, {int? srcDefault}) {
    final s = _rgbOf(src, srcDefault ?? _defaultBg);
    final d = _rgbOf(dstColor, _defaultBg);
    int ch(int shift) {
      final a = (s >> shift) & 0xFF;
      final b = (d >> shift) & 0xFF;
      return ((a * alpha + b * (255 - alpha)) / 255).round();
    }

    return 0x1000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
  }

  // ---- SGR ------------------------------------------------------------------
  final _sgr = <int, Uint8List>{};
  final _transitions = _PairCache<Uint8List>();
  static final _empty = Uint8List(0);

  /// Full SGR sequence for [id] starting from a reset state (`ESC[0;...m`).
  Uint8List sgrFromReset(int id) =>
      _sgr[id] ??= _encode(<int>[0, ..._params(id)]);

  /// Shortest SGR sequence that turns terminal state [from] into [to].
  /// Cached per pair, so steady-state rendering never builds strings.
  Uint8List transition(int from, int to) {
    if (from == to) {
      return _empty;
    }
    final cached = _transitions.get(from, to);
    if (cached != null) {
      return cached;
    }
    final viaReset = sgrFromReset(to);
    final delta = _encode(_deltaParams(from, to));
    final best = delta.length < viaReset.length ? delta : viaReset;
    _transitions.put(from, to, best);
    return best;
  }

  List<int> _params(int id) {
    final out = <int>[];
    _attrParams(0, _sentAttrs(id), out);
    _colorParams(_fg[id], 30, out);
    _colorParams(_bg[id], 40, out);
    if (_ul[id] != 0 && (_attrs[id] & Attr.underlineMask) != 0) {
      _colorParams(_ul[id], 50, out);
    }
    return out;
  }

  List<int> _deltaParams(int from, int to) {
    final out = <int>[];
    final fa = _sentAttrs(from);
    final ta = _sentAttrs(to);
    _attrParams(fa, ta, out);
    if (_fg[from] != _fg[to]) {
      _colorParams(_fg[to], 30, out, reset: true);
    }
    if (_bg[from] != _bg[to]) {
      _colorParams(_bg[to], 40, out, reset: true);
    }
    final ful = (fa & Attr.underlineMask) != 0 ? _ul[from] : 0;
    final tul = (ta & Attr.underlineMask) != 0 ? _ul[to] : 0;
    if (ful != tul) {
      _colorParams(tul, 50, out, reset: true);
    }
    return out;
  }

  /// Parameters that turn attributes [from] into [to].
  static void _attrParams(int from, int to, List<int> out) {
    // bold and dim share one reset (22)
    const weight = Attr.bold | Attr.dim;
    if ((from & weight) != (to & weight)) {
      if ((from & weight & ~to) != 0) {
        out.add(22);
      }
      final add = (from & weight & ~to) != 0
          ? to & weight
          : to & ~from & weight;
      if ((add & Attr.bold) != 0) {
        out.add(1);
      }
      if ((add & Attr.dim) != 0) {
        out.add(2);
      }
    }
    void flag(int bit, int on, int off) {
      if ((from & bit) == (to & bit)) {
        return;
      }
      out.add((to & bit) != 0 ? on : off);
    }

    flag(Attr.italic, 3, 23);
    final fu = from & Attr.underlineMask;
    final tu = to & Attr.underlineMask;
    if (fu != tu) {
      final u = tu >> 3;
      if (u == 0) {
        out.add(24);
      } else if (u == 1) {
        out.add(4);
      } else {
        out.add(-u); // emitted as "4:u"
      }
    }
    flag(Attr.blink, 5, 25);
    flag(Attr.reverse, 7, 27);
    flag(Attr.hidden, 8, 28);
    flag(Attr.strike, 9, 29);
    flag(Attr.overline, 53, 55);
  }

  /// [base] is 30 (fg), 40 (bg) or 50 (underline color: 58/59).
  void _colorParams(int color, int base, List<int> out, {bool reset = false}) {
    if (_colorMode == ColorMode.none) {
      return; // no color was ever sent, so none is reset either
    }
    if (color == 0) {
      if (reset) {
        out.add(base + 9);
      }
      return;
    }
    var c = color;
    if ((c & 0x1000000) != 0) {
      if (_colorMode == ColorMode.ansi256) {
        c = 0x2000000 | _rgbTo256(c & 0xFFFFFF);
      } else if (_colorMode == ColorMode.ansi16) {
        c = 0x2000000 | _nearest16(c & 0xFFFFFF);
      }
    } else if (_colorMode == ColorMode.ansi16 && (c & 0xFF) >= 16) {
      c = 0x2000000 | _nearest16(_palette[c & 0xFF]);
    }
    if (base == 50) {
      out.add(_underlineColorTag | c);
      return;
    }
    if ((c & 0x2000000) != 0) {
      final i = c & 0xFF;
      if (i < 8) {
        out.add(base + i);
      } else if (i < 16) {
        out.add(base + 60 + i - 8);
      } else {
        out
          ..add(base + 8)
          ..add(5)
          ..add(i);
      }
      return;
    }
    out
      ..add(base + 8)
      ..add(2)
      ..add((c >> 16) & 0xFF)
      ..add((c >> 8) & 0xFF)
      ..add(c & 0xFF);
  }

  /// Marks an underline color parameter, emitted in the colon form
  /// (`58:5:i`, `58:2::r:g:b`) SGR 58 was introduced with: a terminal that
  /// doesn't know SGR 58 usually skips such a parameter whole instead of
  /// reading the color's numbers as attributes (`5` blink, `2` dim).
  static const int _underlineColorTag = 1 << 32;

  static String _underlineColor(int c) {
    if ((c & 0x2000000) != 0) {
      return '58:5:${c & 0xFF}';
    }
    return '58:2::${(c >> 16) & 0xFF}:${(c >> 8) & 0xFF}:${c & 0xFF}';
  }

  static Uint8List _encode(List<int> params) {
    if (params.isEmpty) {
      return _empty;
    }
    final sb = StringBuffer('\x1b[');
    for (var i = 0; i < params.length; i++) {
      if (i > 0) {
        sb.write(';');
      }
      final p = params[i];
      if (p < 0) {
        sb.write('4:${-p}');
      } else if (p >= _underlineColorTag) {
        sb.write(_underlineColor(p ^ _underlineColorTag));
      } else {
        sb.write(p);
      }
    }
    sb.write('m');
    return Uint8List.fromList(sb.toString().codeUnits);
  }

  static int _rgbTo256(int rgb) {
    final r = (rgb >> 16) & 0xFF;
    final g = (rgb >> 8) & 0xFF;
    final b = rgb & 0xFF;
    int level(int v) => v < 48 ? 0 : (v < 115 ? 1 : (v - 35) ~/ 40);
    final ri = level(r);
    final gi = level(g);
    final bi = level(b);
    final cube = 16 + 36 * ri + 6 * gi + bi;
    final avg = (r + g + b) ~/ 3;
    final grayIdx = avg > 238 ? 23 : (avg - 3) ~/ 10;
    final gray = 232 + (grayIdx < 0 ? 0 : grayIdx);
    return _dist(rgb, _palette[gray]) < _dist(rgb, _palette[cube])
        ? gray
        : cube;
  }

  static int _nearest16(int rgb) {
    var best = 0;
    var bestD = 1 << 30;
    for (var i = 0; i < 16; i++) {
      final d = _dist(rgb, _palette[i]);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  static int _dist(int a, int b) {
    final dr = ((a >> 16) & 0xFF) - ((b >> 16) & 0xFF);
    final dg = ((a >> 8) & 0xFF) - ((b >> 8) & 0xFF);
    final db = (a & 0xFF) - (b & 0xFF);
    return 2 * dr * dr + 4 * dg * dg + 3 * db * db;
  }
}

/// Open-addressing map from a pair of small non-negative ints to [V].
final class _PairCache<V extends Object> {
  var _a = Int32List(256)..fillRange(0, 256, -1);
  var _b = Int32List(256);
  var _v = List<V?>.filled(256, null);
  var _count = 0;

  @pragma('vm:prefer-inline')
  static int _hash(int a, int b) =>
      ((a * 0x9E3779B1) ^ (b * 0x85EBCA77)) & 0x3FFFFFFF;

  V? get(int a, int b) {
    final mask = _a.length - 1;
    var slot = _hash(a, b) & mask;
    while (true) {
      final ka = _a[slot];
      if (ka < 0) {
        return null;
      }
      if (ka == a && _b[slot] == b) {
        return _v[slot];
      }
      slot = (slot + 1) & mask;
    }
  }

  void put(int a, int b, V value) {
    if ((_count + 1) * 2 > _a.length) {
      _grow();
    }
    final mask = _a.length - 1;
    var slot = _hash(a, b) & mask;
    while (_a[slot] >= 0 && !(_a[slot] == a && _b[slot] == b)) {
      slot = (slot + 1) & mask;
    }
    if (_a[slot] < 0) {
      _count++;
    }
    _a[slot] = a;
    _b[slot] = b;
    _v[slot] = value;
  }

  void clear() {
    _a.fillRange(0, _a.length, -1);
    _v.fillRange(0, _v.length, null);
    _count = 0;
  }

  void _grow() {
    final oa = _a;
    final ob = _b;
    final ov = _v;
    final n = oa.length * 2;
    _a = Int32List(n)..fillRange(0, n, -1);
    _b = Int32List(n);
    _v = List<V?>.filled(n, null);
    _count = 0;
    for (var i = 0; i < oa.length; i++) {
      if (oa[i] >= 0) {
        put(oa[i], ob[i], ov[i]!);
      }
    }
  }
}
