/// A QR code as a widget: [QrCode], and the [RenderQrCode] it puts in the
/// render tree.
library;

import 'package:twk/twk.dart';

import 'symbol.dart';

// Examples can assume:
// import 'package:twk/twk.dart';

/// [data] as a QR code a phone's camera reads ([QrSymbol.encode]: the
/// mode of fewest bits that holds it, the smallest version it fits in at
/// [level], the mask the standard's penalty rules score lowest), with a
/// quiet zone of [quietZone] light modules around it, the 4 the standard
/// asks for by default. [QrCode.symbol] draws a symbol made already, such
/// as one of a version or a mask the app chose.
///
/// It is drawn in half blocks, two modules to a cell, one above the other,
/// so that a module is about as tall as it is wide: [dark] modules on
/// [light] ones, black on white by default whatever the theme and the
/// terminal's colors, since a scanner looks for dark modules on a light
/// ground. Where the canvas draws half blocks two columns wide (they are
/// East Asian ambiguous), each module is two blanks in its color, a row to
/// itself. See [RenderQrCode] for the size it takes.
///
/// The link a phone opens to sign in, under the text that says so:
///
/// ```dart
/// Column(
///   children: [
///     Text('Scan to sign in:'),
///     QrCode('https://example.com/device?code=4F7K-9QX2'),
///   ],
/// )
/// ```
///
/// See also:
///
///  * [QrSymbol], the modules of a code without drawing them.
final class QrCode extends LeafRenderObjectWidget {
  /// [data] encoded at [level], medium by default, with a quiet zone of
  /// [quietZone] light modules around it, in [dark] on [light]; data too
  /// long for any version at [level] is an [ArgumentError] when it is laid
  /// out.
  const QrCode(
    String this.data, {
    super.key,
    this.level = QrErrorCorrection.medium,
    this.quietZone = 4,
    this.dark = black,
    this.light = white,
  }) : symbol = null,
       assert(quietZone >= 0, 'quietZone < 0');

  /// [symbol] as a QR code, with a quiet zone of [quietZone] light modules
  /// around it, in [dark] on [light].
  const QrCode.symbol(
    QrSymbol this.symbol, {
    super.key,
    this.quietZone = 4,
    this.dark = black,
    this.light = white,
  }) : data = null,
       level = QrErrorCorrection.medium,
       assert(quietZone >= 0, 'quietZone < 0');

  /// Black, as 24-bit color: the palette's black may be any color a theme
  /// gives it.
  static const black = Color.rgb(0, 0, 0);

  /// White, as 24-bit color.
  static const white = Color.rgb(255, 255, 255);

  /// The text the code holds; null where [symbol] is given.
  final String? data;

  /// The error correction [data] is encoded with.
  final QrErrorCorrection level;

  /// The symbol drawn; null where [data] is given.
  final QrSymbol? symbol;

  /// The light modules around the symbol on each side.
  final int quietZone;

  /// The color of the dark modules.
  final Color dark;

  /// The color of the light modules and the quiet zone.
  final Color light;

  @override
  RenderQrCode createRenderObject(BuildContext context) => RenderQrCode(
    data: data,
    level: level,
    symbol: symbol,
    quietZone: quietZone,
    dark: dark,
    light: light,
  );

  @override
  void updateRenderObject(BuildContext context, RenderQrCode renderObject) {
    renderObject
      ..data = data
      ..level = level
      ..symbol = symbol
      ..quietZone = quietZone
      ..dark = dark
      ..light = light;
  }
}

/// What a [QrCode] lays out and paints: [symbol], or else [data] encoded
/// at [level] ([QrSymbol.encode]; data that does not fit in version 40 at
/// [level] is the [ArgumentError] its layout throws), with [quietZone]
/// light modules around it.
///
/// A side of the code with its quiet zone is `n` = [QrSymbol.size] + 2 ×
/// [quietZone] modules. It is `n` columns wide and `(n + 1) / 2` rows tall
/// (the lower half of its last row light), where the canvas draws half
/// blocks a column wide; `2n` columns wide and `n` rows tall where it
/// draws them two columns wide. Within constraints smaller than that it is
/// cut off at its right and bottom, and a scanner reads it no more.
final class RenderQrCode extends RenderObject {
  /// Draws [symbol], or else [data] encoded at [level]; one of the two is
  /// given.
  RenderQrCode({
    String? data,
    this._level = QrErrorCorrection.medium,
    QrSymbol? symbol,
    this._quietZone = 4,
    this._dark = QrCode.black,
    this._light = QrCode.white,
  }) : assert(data != null || symbol != null, 'neither data nor a symbol'),
       _data = data,
       _symbol = symbol;

  String? _data;

  /// The text encoded where [symbol] is null; a new one is encoded again
  /// at the next layout.
  String? get data => _data;
  set data(String? d) {
    if (d != _data) {
      _data = d;
      _encoded = null;
      _changed();
    }
  }

  QrErrorCorrection _level;

  /// The error correction [data] is encoded with.
  QrErrorCorrection get level => _level;
  set level(QrErrorCorrection l) {
    if (l != _level) {
      _level = l;
      _encoded = null;
      _changed();
    }
  }

  QrSymbol? _symbol;

  /// The symbol drawn, in place of [data] encoded; another one, not the
  /// very same object, is laid out again.
  QrSymbol? get symbol => _symbol;
  set symbol(QrSymbol? s) {
    if (!identical(s, _symbol)) {
      _symbol = s;
      _changed();
    }
  }

  int _quietZone;

  /// The light modules around the symbol on each side; not negative.
  int get quietZone => _quietZone;
  set quietZone(int q) {
    assert(q >= 0, 'quietZone < 0');
    if (q != _quietZone) {
      _quietZone = q;
      _changed();
    }
  }

  Color _dark;

  /// The color of the dark modules; a new one is painted again.
  Color get dark => _dark;
  set dark(Color c) {
    if (c != _dark) {
      _dark = c;
      markNeedsPaint();
    }
  }

  Color _light;

  /// The color of the light modules and the quiet zone; a new one is
  /// painted again.
  Color get light => _light;
  set light(Color c) {
    if (c != _light) {
      _light = c;
      markNeedsPaint();
    }
  }

  void _changed() {
    _rows = null;
    markNeedsLayout();
  }

  QrSymbol? _encoded;

  /// The symbol drawn: [symbol], or [data] encoded at [level].
  QrSymbol get shown =>
      _symbol ?? (_encoded ??= QrSymbol.encode(_data!, level: _level));

  // the rows painted and the canvas's width of half blocks they are for
  List<String>? _rows;
  var _rowsWide = false;

  /// Whether the canvas draws half blocks two columns wide.
  bool get _wide => !_oneColumn(owner?.segmenter ?? _detached);

  /// The modules of a side with the quiet zone.
  int get _side => shown.size + 2 * _quietZone;

  int get _columns => _wide ? 2 * _side : _side;
  int get _lines => _wide ? _side : (_side + 1) ~/ 2;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(_columns);
    height = c.constrainH(_lines);
  }

  @override
  int computeMinIntrinsicWidth(int height) => _columns;

  @override
  int computeMaxIntrinsicWidth(int height) => _columns;

  @override
  int computeMinIntrinsicHeight(int width) => _lines;

  @override
  int computeMaxIntrinsicHeight(int width) => _lines;

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final wide = _wide;
    if (_rows == null || wide != _rowsWide) {
      _rows = wide ? _wideRows() : _halfRows();
      _rowsWide = wide;
    }
    final rows = _rows!;
    if (!wide) {
      final pen = Style(fg: _dark, bg: _light).penIn(canvas.styles);
      for (var y = 0; y < rows.length && y < height; y++) {
        canvas.text(0, y, rows[y], pen);
      }
      return;
    }
    // runs of modules of a color, as blanks on it
    final pens = [
      Style(bg: _light).penIn(canvas.styles),
      Style(bg: _dark).penIn(canvas.styles),
    ];
    for (var y = 0; y < rows.length && y < height; y++) {
      final row = rows[y];
      var x = 0;
      while (x < row.length && 2 * x < width) {
        final dark = row.codeUnitAt(x);
        var end = x + 1;
        while (end < row.length && row.codeUnitAt(end) == dark) {
          end++;
        }
        canvas.text(2 * x, y, '  ' * (end - x), pens[dark - _light0]);
        x = end;
      }
    }
  }

  /// Whether the module in column [x] of row [y] of the code with its
  /// quiet zone is dark.
  bool _darkAt(QrSymbol symbol, int x, int y) {
    final sx = x - _quietZone;
    final sy = y - _quietZone;
    return sx >= 0 &&
        sy >= 0 &&
        sx < symbol.size &&
        sy < symbol.size &&
        symbol.isDark(sx, sy);
  }

  /// The rows of cells in half blocks, two modules to a cell.
  List<String> _halfRows() {
    final symbol = shown;
    final side = _side;
    return [
      for (var y = 0; y < side; y += 2)
        String.fromCharCodes([
          for (var x = 0; x < side; x++)
            _halfBlocks[(_darkAt(symbol, x, y) ? 1 : 0) |
                (_darkAt(symbol, x, y + 1) ? 2 : 0)],
        ]),
    ];
  }

  /// The rows of modules, a character each: [_light0] light, the one after
  /// it dark.
  List<String> _wideRows() {
    final symbol = shown;
    final side = _side;
    return [
      for (var y = 0; y < side; y++)
        String.fromCharCodes([
          for (var x = 0; x < side; x++)
            _light0 + (_darkAt(symbol, x, y) ? 1 : 0),
        ]),
    ];
  }
}

/// The cell of two modules, by which are dark: 1 the upper, 2 the lower.
const _halfBlocks = [0x20, 0x2580, 0x2584, 0x2588];

/// The character [RenderQrCode._wideRows] writes for a light module.
const _light0 = 0x30;

final _scan = ClusterScan();
final _detached = TextSegmenter();

/// Whether [seg] measures each half block, and the full block, a column
/// wide, for sure.
bool _oneColumn(TextSegmenter seg) {
  for (final cp in _halfBlocks.skip(1)) {
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
