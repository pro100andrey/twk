import 'dart:typed_data';

import 'bitmap.dart';

/// The size in pixels of a terminal's cell.
final class CellSize {
  /// A cell of [width] × [height] pixels, both above 0.
  const CellSize(this.width, this.height)
    : assert(width > 0 && height > 0, 'a cell has pixels');

  /// The size a terminal reports, or [fallback] where it reports none (a
  /// size of 0).
  factory CellSize.reported(int width, int height) =>
      width > 0 && height > 0 ? CellSize(width, height) : fallback;

  /// 10 × 20 pixels, for a terminal that does not say: a cell twice as tall
  /// as it is wide, as most fonts make it.
  static const fallback = CellSize(10, 20);

  /// The cell's width in pixels.
  final int width;

  /// The cell's height in pixels.
  final int height;

  @override
  bool operator ==(Object other) =>
      other is CellSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'CellSize($width × $height)';
}

/// How an image fills a box of cells.
enum ImageFit {
  /// As large as fits in the box, its aspect kept: all of it shown.
  contain,

  /// As small as covers the box, its aspect kept: what is outside cut off,
  /// as much from either side.
  cover,

  /// Stretched to the box.
  fill,

  /// As [contain], but never larger than it is.
  scaleDown,
}

/// Where an image goes in a box of cells: the cells it takes from the box's
/// top left, the pixels it is scaled to and the part of it shown.
final class CellFit {
  /// The fit of an image of [imageWidth] × [imageHeight] pixels in a box of
  /// [columns] × [rows] cells of [cell]'s size, as [fit] says.
  ///
  /// The box's height in pixels is taken down to a multiple of
  /// [bandHeight] (but not below it): 6 for sixel, which draws bands of 6
  /// pixels, a band past the box scrolling the terminal.
  factory CellFit(
    int imageWidth,
    int imageHeight, {
    required int columns,
    required int rows,
    CellSize cell = CellSize.fallback,
    ImageFit fit = ImageFit.contain,
    int bandHeight = 1,
  }) {
    assert(imageWidth > 0 && imageHeight > 0, 'an image has pixels');
    assert(columns > 0 && rows > 0, 'a box has cells');
    final boxWidth = columns * cell.width;
    var boxHeight = rows * cell.height;
    boxHeight -= boxHeight % bandHeight;
    if (boxHeight < bandHeight) {
      boxHeight = bandHeight;
    }
    var width = boxWidth;
    var height = boxHeight;
    var cropX = 0;
    var cropY = 0;
    var cropWidth = imageWidth;
    var cropHeight = imageHeight;
    final scaleX = boxWidth / imageWidth;
    final scaleY = boxHeight / imageHeight;
    switch (fit) {
      case ImageFit.fill:
        break;
      case ImageFit.cover:
        final scale = scaleX > scaleY ? scaleX : scaleY;
        cropWidth = _clamp((boxWidth / scale).round(), 1, imageWidth);
        cropHeight = _clamp((boxHeight / scale).round(), 1, imageHeight);
        cropX = (imageWidth - cropWidth) ~/ 2;
        cropY = (imageHeight - cropHeight) ~/ 2;
      case ImageFit.contain || ImageFit.scaleDown:
        var scale = scaleX < scaleY ? scaleX : scaleY;
        if (fit == ImageFit.scaleDown && scale > 1) {
          scale = 1;
        }
        width = _clamp((imageWidth * scale).round(), 1, boxWidth);
        height = _clamp((imageHeight * scale).round(), 1, boxHeight);
    }
    return CellFit._(
      columns: (width + cell.width - 1) ~/ cell.width,
      rows: (height + cell.height - 1) ~/ cell.height,
      width: width,
      height: height,
      cropX: cropX,
      cropY: cropY,
      cropWidth: cropWidth,
      cropHeight: cropHeight,
    );
  }

  const CellFit._({
    required this.columns,
    required this.rows,
    required this.width,
    required this.height,
    required this.cropX,
    required this.cropY,
    required this.cropWidth,
    required this.cropHeight,
  });

  /// The columns the image takes, from the box's left; fewer than the
  /// box's where it is contained in it.
  final int columns;

  /// The rows the image takes, from the box's top; fewer than the box's
  /// where it is contained in it.
  final int rows;

  /// The width in pixels the image is scaled to.
  final int width;

  /// The height in pixels the image is scaled to.
  final int height;

  /// The left of the part of the image shown, in its pixels: 0 but where
  /// it covers the box.
  final int cropX;

  /// The top of the part of the image shown, in its pixels: 0 but where it
  /// covers the box.
  final int cropY;

  /// The width of the part of the image shown, in its pixels: all of it
  /// but where it covers the box.
  final int cropWidth;

  /// The height of the part of the image shown, in its pixels: all of it
  /// but where it covers the box.
  final int cropHeight;

  /// [image], of the size this fit was made for, scaled as it says.
  Bitmap scale(Bitmap image) => resize(
    image,
    width,
    height,
    cropX: cropX,
    cropY: cropY,
    cropWidth: cropWidth,
    cropHeight: cropHeight,
  );

  @override
  bool operator ==(Object other) =>
      other is CellFit &&
      other.columns == columns &&
      other.rows == rows &&
      other.width == width &&
      other.height == height &&
      other.cropX == cropX &&
      other.cropY == cropY &&
      other.cropWidth == cropWidth &&
      other.cropHeight == cropHeight;

  @override
  int get hashCode => Object.hash(
    columns,
    rows,
    width,
    height,
    cropX,
    cropY,
    cropWidth,
    cropHeight,
  );

  @override
  String toString() =>
      'CellFit($columns × $rows cells, $width × $height pixels of '
      '$cropWidth × $cropHeight at $cropX, $cropY)';
}

int _clamp(int v, int low, int high) => v < low
    ? low
    : v > high
    ? high
    : v;

/// [image] scaled to [width] × [height] pixels; only its part of
/// [cropWidth] × [cropHeight] pixels from ([cropX], [cropY]) where those
/// are given.
///
/// Where the image shrinks, each pixel is the mean of those under it, each
/// weighed by how much of it is; where it grows, the pixels between are
/// interpolated (bilinear). Alpha is premultiplied, so that a transparent
/// pixel's colour does not bleed. A part of the size of the result is
/// copied as it is.
Bitmap resize(
  Bitmap image,
  int width,
  int height, {
  int cropX = 0,
  int cropY = 0,
  int? cropWidth,
  int? cropHeight,
}) {
  final sourceWidth = cropWidth ?? image.width - cropX;
  final sourceHeight = cropHeight ?? image.height - cropY;
  assert(
    cropX >= 0 &&
        cropY >= 0 &&
        sourceWidth > 0 &&
        sourceHeight > 0 &&
        cropX + sourceWidth <= image.width &&
        cropY + sourceHeight <= image.height,
    'the part is in the image',
  );
  assert(width > 0 && height > 0, 'the result has pixels');
  final pixels = image.pixels;
  final out = Bitmap(width, height);
  if (sourceWidth == width && sourceHeight == height) {
    for (var y = 0; y < height; y++) {
      final from = ((cropY + y) * image.width + cropX) * 4;
      out.pixels.setRange(y * width * 4, (y + 1) * width * 4, pixels, from);
    }
    return out;
  }
  final xs = _Weights(cropX, sourceWidth, width);
  final ys = _Weights(cropY, sourceHeight, height);
  final top = ys.starts[0];
  final bottom = ys.starts[height - 1] + ys.counts[height - 1];
  // Rows across first, premultiplied, for the rows the columns take.
  final across = Float32List(width * (bottom - top) * 4);
  final stride = image.width;
  for (var y = top, t = 0; y < bottom; y++) {
    for (var x = 0; x < width; x++, t += 4) {
      var r = 0.0;
      var g = 0.0;
      var b = 0.0;
      var a = 0.0;
      final count = xs.counts[x];
      var p = (y * stride + xs.starts[x]) * 4;
      for (var k = 0, w = x * xs.taps; k < count; k++, w++, p += 4) {
        final weight = xs.weights[w] * pixels[p + 3];
        r += weight * pixels[p];
        g += weight * pixels[p + 1];
        b += weight * pixels[p + 2];
        a += weight;
      }
      across[t] = r;
      across[t + 1] = g;
      across[t + 2] = b;
      across[t + 3] = a;
    }
  }
  final result = out.pixels;
  final rowStep = width * 4;
  for (var y = 0, o = 0; y < height; y++) {
    final count = ys.counts[y];
    final first = (ys.starts[y] - top) * rowStep;
    for (var x = 0; x < width; x++, o += 4) {
      var r = 0.0;
      var g = 0.0;
      var b = 0.0;
      var a = 0.0;
      var t = first + x * 4;
      for (var k = 0, w = y * ys.taps; k < count; k++, w++, t += rowStep) {
        final weight = ys.weights[w];
        r += weight * across[t];
        g += weight * across[t + 1];
        b += weight * across[t + 2];
        a += weight * across[t + 3];
      }
      if (a < 0.5) {
        continue;
      }
      result[o] = _byte(r / a);
      result[o + 1] = _byte(g / a);
      result[o + 2] = _byte(b / a);
      result[o + 3] = _byte(a);
    }
  }
  return out;
}

int _byte(double v) {
  final rounded = (v + 0.5).toInt();
  return rounded > 255 ? 255 : rounded;
}

/// The source pixels each pixel of a row or column of the result takes,
/// and how much of each.
final class _Weights {
  _Weights(int start, int length, int size)
    : starts = Int32List(size),
      counts = Int32List(size),
      taps = _taps(length, size),
      weights = Float32List(size * _taps(length, size)) {
    final scale = length / size;
    final end = start + length;
    for (var i = 0; i < size; i++) {
      final int low;
      final int high;
      if (scale > 1) {
        // The part of the source under the pixel.
        final from = start + i * scale;
        final to = from + scale;
        low = from.floor();
        high = _clamp(to.ceil(), low + 1, end);
        for (var j = low; j < high; j++) {
          final w =
              (to < j + 1 ? to : j + 1.0) - (from > j ? from : j.toDouble());
          weights[i * taps + j - low] = w > 0 ? w : 0;
        }
      } else {
        // The two source pixels nearest the pixel's centre.
        final center = start + (i + 0.5) * scale - 0.5;
        low = _clamp(center.floor(), start, end - 1);
        high = low + 1 < end ? low + 2 : low + 1;
        final w = center - low;
        if (high - low == 2 && w > 0) {
          weights[i * taps] = 1 - w;
          weights[i * taps + 1] = w;
        } else {
          weights[i * taps] = 1;
        }
      }
      var sum = 0.0;
      for (var j = 0; j < high - low; j++) {
        sum += weights[i * taps + j];
      }
      for (var j = 0; j < high - low; j++) {
        weights[i * taps + j] /= sum;
      }
      starts[i] = low;
      counts[i] = high - low;
    }
  }

  static int _taps(int length, int size) {
    final scale = length / size;
    return scale > 1 ? scale.ceil() + 1 : 2;
  }

  final Int32List starts;
  final Int32List counts;
  final int taps;
  final Float32List weights;
}
