import 'bitmap.dart';
import 'scale.dart';

// Examples can assume:
// import 'dart:io';

/// How the cells of a [BlockImage] draw its pixels.
enum BlockMode {
  /// Two pixels a cell, one above the other: `▀` in the upper's colour on
  /// the lower's.
  half,

  /// Four pixels a cell, two by two: the quadrant block that splits them
  /// best in two colours, in the mean of one part on the mean of the other.
  /// Finer than [half], its colours less exact.
  quadrant,
}

/// A cell of a [BlockImage]: [glyph] in [fg] on [bg], `0xRRGGBB` each, null
/// for the colour of what is under the cell.
final class BlockCell {
  /// A cell showing [glyph] in [fg] on [bg].
  const BlockCell(this.glyph, {this.fg, this.bg});

  /// A cell no pixel of the image is drawn in.
  static const empty = BlockCell(' ');

  /// The block character the cell shows: `▀`, `▄`, a quadrant block, or
  /// a space.
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
    final across = mode == BlockMode.half ? 1 : 2;
    var width = (fitted.width * across / cell.width).round();
    var height = (fitted.height * 2 / cell.height).round();
    width = width < 1
        ? 1
        : (width > columns * across ? columns * across : width);
    height = height < 1 ? 1 : (height > rows * 2 ? rows * 2 : height);
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

  /// The cells of [pixels] as they are, a cell for each 1 × 2 of them
  /// ([BlockMode.half]) or 2 × 2 ([BlockMode.quadrant]); those past its
  /// right or bottom edge are not drawn.
  ///
  /// [background] as for the default constructor.
  factory BlockImage.fromPixels(
    Bitmap pixels, {
    BlockMode mode = BlockMode.half,
    int? background,
  }) {
    final across = mode == BlockMode.half ? 1 : 2;
    final columns = (pixels.width + across - 1) ~/ across;
    final rows = (pixels.height + 1) ~/ 2;
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
        final y = row * 2;
        if (mode == BlockMode.half) {
          cells.add(_half(at(column, y), at(column, y + 1)));
        } else {
          final x = column * 2;
          cells.add(
            _quadrant([at(x, y), at(x + 1, y), at(x, y + 1), at(x + 1, y + 1)]),
          );
        }
      }
    }
    return BlockImage._(columns, rows, List.unmodifiable(cells));
  }

  BlockImage._(this.columns, this.rows, this.cells);

  /// The cells it takes across.
  final int columns;

  /// The cells it takes down.
  final int rows;

  /// The cells, row by row.
  final List<BlockCell> cells;

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

/// The quadrant blocks by the pixels they cover: bit 0 the top left, 1 the
/// top right, 2 the bottom left, 3 the bottom right.
const _quadrants = [
  ' ', '▘', '▝', '▀', '▖', '▌', '▞', '▛', //
  '▗', '▚', '▐', '▜', '▄', '▙', '▟', '█',
];

/// The splits tried of four pixels drawn, by the pixels in the foreground:
/// all alike first, then halves, then the rest; each with the top left in
/// the foreground, the other way round being the same split.
const _splits = [15, 3, 5, 1, 7, 9, 11, 13];

BlockCell _quadrant(List<int> pixels) {
  var drawn = 0;
  for (var i = 0; i < 4; i++) {
    if (pixels[i] >= 0) {
      drawn |= 1 << i;
    }
  }
  if (drawn == 0) {
    return BlockCell.empty;
  }
  if (drawn != 15) {
    return BlockCell(_quadrants[drawn], fg: _mean(pixels, drawn));
  }
  var best = 15;
  var bestError = double.infinity;
  for (final split in _splits) {
    final error = _error(pixels, split) + _error(pixels, 15 ^ split);
    if (error < bestError) {
      best = split;
      bestError = error;
    }
  }
  if (best == 15) {
    final c = _mean(pixels, 15);
    return BlockCell('▀', fg: c, bg: c);
  }
  return BlockCell(
    _quadrants[best],
    fg: _mean(pixels, best),
    bg: _mean(pixels, 15 ^ best),
  );
}

/// The mean colour of the pixels in [mask].
int _mean(List<int> pixels, int mask) {
  var n = 0;
  var r = 0;
  var g = 0;
  var b = 0;
  for (var i = 0; i < 4; i++) {
    if (mask & 1 << i != 0) {
      final c = pixels[i];
      n++;
      r += c >> 16;
      g += c >> 8 & 0xFF;
      b += c & 0xFF;
    }
  }
  final half = n >> 1;
  return (r + half) ~/ n << 16 | (g + half) ~/ n << 8 | (b + half) ~/ n;
}

/// The sum of the squared distances of the pixels in [mask] from their
/// mean.
double _error(List<int> pixels, int mask) {
  if (mask == 0) {
    return 0;
  }
  var n = 0;
  final sums = [0, 0, 0];
  final squares = [0, 0, 0];
  for (var i = 0; i < 4; i++) {
    if (mask & 1 << i != 0) {
      n++;
      for (var c = 0; c < 3; c++) {
        final v = pixels[i] >> (16 - c * 8) & 0xFF;
        sums[c] += v;
        squares[c] += v * v;
      }
    }
  }
  var error = 0.0;
  for (var c = 0; c < 3; c++) {
    error += squares[c] - sums[c] * sums[c] / n;
  }
  return error;
}
