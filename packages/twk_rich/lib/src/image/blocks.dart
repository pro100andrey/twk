import 'dart:typed_data';

import 'package:twk/twk.dart' show Marker;

import 'bitmap.dart';
import 'scale.dart';

// Examples can assume:
// import 'dart:io';

/// How the cells of a [BlockImage] draw its pixels.
///
/// The glyphs of [quadrant], [sextant], [octant] and [braille] are the ones
/// of `Marker` (twk's charts), which says which Unicode they need.
enum BlockMode {
  /// Two pixels a cell, one above the other: `▀` in the upper's colour on
  /// the lower's.
  half(1, 2),

  /// Four pixels a cell, two by two: the quadrant block that splits them
  /// best in two colours, in the mean of one part on the mean of the other.
  /// Finer than [half], its colours less exact.
  quadrant(2, 2),

  /// Six pixels a cell, two across and three down, drawn as the sextant
  /// that splits them best in two colours, as [quadrant] does. Unicode 13:
  /// a font without it shows a gap or a box.
  sextant(2, 3),

  /// Eight pixels a cell, two across and four down, drawn as the octant
  /// that splits them best in two colours, as [quadrant] does. Unicode 16:
  /// fewer fonts have it than the sextants.
  octant(2, 4),

  /// Eight pixels a cell, two across and four down, drawn as braille dots
  /// in one colour on what is under the cell: a pixel at least half as
  /// bright as white is a dot, in the mean of the colours of the dots. The
  /// finest, and the one most fonts have, but one colour a cell.
  braille(2, 4),

  /// One pixel a cell, drawn as the character of ` .:-=+*#%@` that is as
  /// dense as the pixel is bright, in the pixel's colour. For a terminal
  /// of plain ASCII.
  ascii(1, 1);

  const BlockMode(this.across, this.down);

  /// The pixels a cell holds across.
  final int across;

  /// The pixels a cell holds down.
  final int down;
}

/// A cell of a [BlockImage]: [glyph] in [fg] on [bg], `0xRRGGBB` each, null
/// for the colour of what is under the cell.
final class BlockCell {
  /// A cell showing [glyph] in [fg] on [bg].
  const BlockCell(this.glyph, {this.fg, this.bg});

  /// A cell no pixel of the image is drawn in.
  static const empty = BlockCell(' ');

  /// The character the cell shows: `▀`, `▄`, a block, sextant, octant or
  /// braille character, an ASCII one, or a space.
  final String glyph;

  /// The colour of [glyph]'s ink, `0xRRGGBB`; null for what is under the
  /// cell.
  final int? fg;

  /// The colour of the rest of the cell, `0xRRGGBB`; null for what is under
  /// the cell.
  final int? bg;

  @override
  bool operator ==(Object other) =>
      other is BlockCell &&
      other.glyph == glyph &&
      other.fg == fg &&
      other.bg == bg;

  @override
  int get hashCode => Object.hash(glyph, fg, bg);

  @override
  String toString() {
    String hex(int? c) =>
        c == null ? '-' : '#${c.toRadixString(16).padLeft(6, '0')}';
    return 'BlockCell($glyph ${hex(fg)} on ${hex(bg)})';
  }
}

/// An image drawn with block characters in coloured cells, for a terminal
/// that shows no images: the half-block (or quadrant) fallback.
///
/// A photo printed 40 cells wide, without an app:
///
/// ```dart
/// final photo = decodeImage(File('photo.jpg').readAsBytesSync());
/// BlockImage(photo, columns: 40, rows: 20).toAnsi().forEach(print);
/// ```
///
/// See also:
///
///  * `Image`, the widget, which draws one of these where the terminal
///    shows no images.
final class BlockImage {
  /// [image] fitted to a box of [columns] × [rows] cells of [cell]'s size,
  /// as [fit] says (`CellFit`), each cell drawing [mode]'s pixels of it.
  ///
  /// A pixel whose alpha is below 128 is not drawn, one above it drawn as
  /// it is; where [background] (`0xRRGGBB`) is given, every pixel is
  /// blended over it and drawn.
  factory BlockImage(
    Bitmap image, {
    required int columns,
    required int rows,
    CellSize cell = CellSize.fallback,
    ImageFit fit = ImageFit.contain,
    BlockMode mode = BlockMode.half,
    int? background,
  }) {
    final fitted = CellFit(
      image.width,
      image.height,
      columns: columns,
      rows: rows,
      cell: cell,
      fit: fit,
    );
    final across = mode.across;
    final down = mode.down;
    var width = (fitted.width * across / cell.width).round();
    var height = (fitted.height * down / cell.height).round();
    width = width < 1
        ? 1
        : (width > columns * across ? columns * across : width);
    height = height < 1 ? 1 : (height > rows * down ? rows * down : height);
    final pixels = resize(
      image,
      width,
      height,
      cropX: fitted.cropX,
      cropY: fitted.cropY,
      cropWidth: fitted.cropWidth,
      cropHeight: fitted.cropHeight,
    );
    return BlockImage.fromPixels(pixels, mode: mode, background: background);
  }

  /// The cells of [pixels] as they are, a cell for each [BlockMode.across] ×
  /// [BlockMode.down] of them; those past its
  /// right or bottom edge are not drawn.
  ///
  /// [background] as for the default constructor.
  factory BlockImage.fromPixels(
    Bitmap pixels, {
    BlockMode mode = BlockMode.half,
    int? background,
  }) {
    final across = mode.across;
    final down = mode.down;
    final columns = (pixels.width + across - 1) ~/ across;
    final rows = (pixels.height + down - 1) ~/ down;
    // Each pixel as 0xRRGGBB, -1 where it is not drawn.
    int at(int x, int y) {
      if (x >= pixels.width || y >= pixels.height) {
        return -1;
      }
      final argb = pixels.pixel(x, y);
      final a = argb >>> 24;
      if (background == null) {
        return a < 128 ? -1 : argb & 0xFFFFFF;
      }
      var rgb = 0;
      for (var shift = 16; shift >= 0; shift -= 8) {
        final v = argb >> shift & 0xFF;
        final b = background >> shift & 0xFF;
        rgb |= (v * a + b * (255 - a) + 127) ~/ 255 << shift;
      }
      return rgb;
    }

    final cells = <BlockCell>[];
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final x = column * across;
        final y = row * down;
        cells.add(
          _blockCell(mode, [
            for (var dy = 0; dy < down; dy++)
              for (var dx = 0; dx < across; dx++) at(x + dx, y + dy),
          ]),
        );
      }
    }
    return BlockImage._(columns, rows, List.unmodifiable(cells));
  }

  BlockImage._(this.columns, this.rows, this.cells)
    : glyphs = List.unmodifiable([
        for (final cell in cells) cell.glyph.runes.first,
      ]);

  /// The cells it takes across.
  final int columns;

  /// The cells it takes down.
  final int rows;

  /// The cells, row by row.
  final List<BlockCell> cells;

  /// The code point of each cell's [BlockCell.glyph], row by row: what a
  /// paint draws, without taking it from the string each time.
  final List<int> glyphs;

  /// The cell at [column] and [row], from the top left.
  BlockCell cellAt(int column, int row) => cells[row * columns + column];

  /// The rows of cells as text with SGR colours (24-bit), each ending with
  /// the colours reset, to write to a terminal as they are.
  List<String> toAnsi() => [
    for (var row = 0; row < rows; row++) _ansiRow(row),
  ];

  String _ansiRow(int row) {
    final out = StringBuffer();
    int? fg;
    int? bg;
    var styled = false;
    for (var column = 0; column < columns; column++) {
      final cell = cellAt(column, row);
      if (cell.glyph != ' ' && cell.fg != fg) {
        fg = cell.fg;
        out.write(_sgr(38, fg));
        styled = true;
      }
      if (cell.bg != bg) {
        bg = cell.bg;
        out.write(_sgr(48, bg));
        styled = true;
      }
      out.write(cell.glyph);
    }
    if (styled) {
      out.write('\x1b[0m');
    }
    return out.toString();
  }
}

String _sgr(int base, int? color) => color == null
    ? '\x1b[${base + 1}m'
    : '\x1b[$base;2;${color >> 16};${color >> 8 & 0xFF};${color & 0xFF}m';

BlockCell _half(int top, int bottom) {
  if (top < 0) {
    return bottom < 0 ? BlockCell.empty : BlockCell('▄', fg: bottom);
  }
  return BlockCell('▀', fg: top, bg: bottom < 0 ? null : bottom);
}

/// The glyph strings of each of [marker]'s patterns.
List<String> _glyphs(Marker marker) => List.unmodifiable([
  for (var p = 0; p < marker.patterns; p++)
    String.fromCharCode(marker.glyphOf(p)),
]);

final List<String> _quadrantGlyphs = _glyphs(Marker.quadrant);
final List<String> _sextantGlyphs = _glyphs(Marker.sextant);
final List<String> _octantGlyphs = _glyphs(Marker.octant);
final List<String> _brailleGlyphs = _glyphs(Marker.braille);

/// The glyphs a cell of [mode] shows by the pixels in its ink: bit `k` the
/// pixel `k`, row by row from the top left.
List<String> _glyphsOf(BlockMode mode) => switch (mode) {
  BlockMode.quadrant => _quadrantGlyphs,
  BlockMode.sextant => _sextantGlyphs,
  BlockMode.octant => _octantGlyphs,
  _ => _brailleGlyphs,
};

/// The splits of the quadrant's four pixels tried, by the pixels in the
/// foreground: all alike first, then halves, then the rest; each with the
/// top left in the foreground, the other way round being the same split.
const _quadrantSplits = [15, 3, 5, 1, 7, 9, 11, 13];

/// The splits of a cell of [n] pixels tried: all alike first, then every
/// other with the first pixel in the foreground.
List<int> _splitsOf(int n) => n == 4
    ? _quadrantSplits
    : [(1 << n) - 1, for (var m = 1; m < (1 << n) - 1; m += 2) m];

final Map<int, List<int>> _splits = {
  for (final n in const [4, 6, 8]) n: _splitsOf(n),
};

/// The ramp of the ascii mode, from the darkest to the brightest pixel.
const _ramp = ' .:-=+*#%@';

/// A pixel `0xRRGGBB` as bright as at least this (of 255) is ink in braille.
const _brailleThreshold = 128;

int _luma(int rgb) =>
    (299 * (rgb >> 16) + 587 * (rgb >> 8 & 0xFF) + 114 * (rgb & 0xFF)) ~/ 1000;

/// The sums over every subset of a cell's pixels, to tell the best split
/// of its colours in two.
final class _Sums {
  _Sums(int pixels)
    : n = Int32List(1 << pixels),
      r = Int32List(1 << pixels),
      g = Int32List(1 << pixels),
      b = Int32List(1 << pixels),
      squares = Int32List(1 << pixels);

  final Int32List n;
  final Int32List r;
  final Int32List g;
  final Int32List b;
  final Int32List squares;

  /// The sums of every subset of [pixels]; one not drawn (negative) counts
  /// as black.
  void fill(List<int> pixels) {
    final all = (1 << pixels.length) - 1;
    for (var mask = 1; mask <= all; mask++) {
      final low = mask & -mask;
      final rest = mask ^ low;
      final p = pixels[low.bitLength - 1];
      final c = p < 0 ? 0 : p;
      final cr = c >> 16;
      final cg = c >> 8 & 0xFF;
      final cb = c & 0xFF;
      n[mask] = n[rest] + 1;
      r[mask] = r[rest] + cr;
      g[mask] = g[rest] + cg;
      b[mask] = b[rest] + cb;
      squares[mask] = squares[rest] + cr * cr + cg * cg + cb * cb;
    }
  }

  /// The mean colour of the pixels in [mask].
  int mean(int mask) {
    final count = n[mask];
    final half = count >> 1;
    return (r[mask] + half) ~/ count << 16 |
        (g[mask] + half) ~/ count << 8 |
        (b[mask] + half) ~/ count;
  }

  /// The sum of the squared distances of the pixels in [mask] from their
  /// mean.
  double error(int mask) {
    if (mask == 0) {
      return 0;
    }
    final count = n[mask];
    return squares[mask] -
        (r[mask] * r[mask] + g[mask] * g[mask] + b[mask] * b[mask]) / count;
  }
}

final Map<int, _Sums> _sums = {
  for (final n in const [4, 6, 8]) n: _Sums(n),
};

/// The cell of [mode] showing [pixels] (row by row, -1 for one not drawn).
BlockCell _blockCell(BlockMode mode, List<int> pixels) {
  switch (mode) {
    case BlockMode.half:
      return _half(pixels[0], pixels[1]);
    case BlockMode.ascii:
      final c = pixels[0];
      return c < 0
          ? BlockCell.empty
          : BlockCell(_ramp[_luma(c) * _ramp.length ~/ 256], fg: c);
    case BlockMode.braille:
      var lit = 0;
      for (var i = 0; i < pixels.length; i++) {
        if (pixels[i] >= 0 && _luma(pixels[i]) >= _brailleThreshold) {
          lit |= 1 << i;
        }
      }
      if (lit == 0) {
        return BlockCell.empty;
      }
      final sums = _sums[8]!..fill(pixels);
      return BlockCell(_brailleGlyphs[lit], fg: sums.mean(lit));
    case BlockMode.quadrant || BlockMode.sextant || BlockMode.octant:
      break;
  }
  final n = pixels.length;
  final full = (1 << n) - 1;
  final glyphs = _glyphsOf(mode);
  var drawn = 0;
  for (var i = 0; i < n; i++) {
    if (pixels[i] >= 0) {
      drawn |= 1 << i;
    }
  }
  if (drawn == 0) {
    return BlockCell.empty;
  }
  final sums = _sums[n]!..fill(pixels);
  if (drawn != full) {
    return BlockCell(glyphs[drawn], fg: sums.mean(drawn));
  }
  var best = full;
  var bestError = double.infinity;
  for (final split in _splits[n]!) {
    final error = sums.error(split) + sums.error(full ^ split);
    if (error < bestError) {
      best = split;
      bestError = error;
    }
  }
  if (best == full) {
    final c = sums.mean(full);
    return BlockCell('▀', fg: c, bg: c);
  }
  return BlockCell(
    glyphs[best],
    fg: sums.mean(best),
    bg: sums.mean(full ^ best),
  );
}
