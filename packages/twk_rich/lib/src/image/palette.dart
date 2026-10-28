import 'dart:typed_data';

import 'bitmap.dart';

/// The pixels of a bitmap as indexes into a palette of colours.
final class Indexed {
  Indexed._(this.width, this.height, this.colors, this.indexes);

  /// [image]'s pixels in at most [maxColors] colours: its own where it has
  /// no more, else those median cut finds, with Floyd–Steinberg dithering
  /// where [dither] says.
  ///
  /// A pixel is transparent (index -1) where its alpha is below 128, its
  /// colour taken as it is otherwise; where [background] (`0xRRGGBB`) is
  /// given, every pixel is blended over it instead and none is
  /// transparent.
  factory Indexed.of(
    Bitmap image, {
    int maxColors = 256,
    bool dither = true,
    int? background,
  }) {
    assert(maxColors >= 1 && maxColors <= 256, 'from 1 to 256 colours');
    final count = image.width * image.height;
    final rgb = Int32List(count);
    final source = image.pixels;
    for (var i = 0, p = 0; i < count; i++, p += 4) {
      final a = source[p + 3];
      if (background != null) {
        rgb[i] =
            _blend(source[p], background >> 16 & 0xFF, a) << 16 |
            _blend(source[p + 1], background >> 8 & 0xFF, a) << 8 |
            _blend(source[p + 2], background & 0xFF, a);
      } else {
        rgb[i] = a < 128
            ? -1
            : source[p] << 16 | source[p + 1] << 8 | source[p + 2];
      }
    }
    final indexes = Int16List(count);
    final exact = _exact(rgb, maxColors);
    if (exact != null) {
      final colors = Int32List.fromList(exact.keys.toList());
      for (var i = 0; i < count; i++) {
        indexes[i] = rgb[i] < 0 ? -1 : exact[rgb[i]]!;
      }
      return Indexed._(image.width, image.height, colors, indexes);
    }
    final colors = _medianCut(rgb, maxColors);
    final nearest = _Nearest(colors);
    if (!dither) {
      for (var i = 0; i < count; i++) {
        final c = rgb[i];
        indexes[i] = c < 0
            ? -1
            : nearest.of(c >> 16 & 0xFF, c >> 8 & 0xFF, c & 0xFF);
      }
      return Indexed._(image.width, image.height, colors, indexes);
    }
    final width = image.width;
    // The error each pixel of this row and the next takes, 3 channels and a
    // pixel more on either side.
    var errors = Int32List((width + 2) * 3);
    var next = Int32List((width + 2) * 3);
    for (var y = 0, i = 0; y < image.height; y++) {
      for (var x = 0; x < width; x++, i++) {
        final c = rgb[i];
        if (c < 0) {
          indexes[i] = -1;
          continue;
        }
        final e = (x + 1) * 3;
        final r = _clamp((c >> 16 & 0xFF) + (errors[e] >> 4));
        final g = _clamp((c >> 8 & 0xFF) + (errors[e + 1] >> 4));
        final b = _clamp((c & 0xFF) + (errors[e + 2] >> 4));
        final index = nearest.of(r, g, b);
        indexes[i] = index;
        final chosen = colors[index];
        final dr = r - (chosen >> 16 & 0xFF);
        final dg = g - (chosen >> 8 & 0xFF);
        final db = b - (chosen & 0xFF);
        // 7/16 right, 3/16 below left, 5/16 below, 1/16 below right.
        errors[e + 3] += dr * 7;
        errors[e + 4] += dg * 7;
        errors[e + 5] += db * 7;
        next[e - 3] += dr * 3;
        next[e - 2] += dg * 3;
        next[e - 1] += db * 3;
        next[e] += dr * 5;
        next[e + 1] += dg * 5;
        next[e + 2] += db * 5;
        next[e + 3] += dr;
        next[e + 4] += dg;
        next[e + 5] += db;
      }
      final done = errors..fillRange(0, errors.length, 0);
      errors = next;
      next = done;
    }
    return Indexed._(image.width, image.height, colors, indexes);
  }

  /// The bitmap's width in pixels.
  final int width;

  /// The bitmap's height in pixels.
  final int height;

  /// The palette, `0xRRGGBB` each.
  final Int32List colors;

  /// The index of each pixel's colour in [colors], row by row; -1 where it
  /// is transparent.
  final Int16List indexes;
}

int _blend(int value, int background, int alpha) =>
    (value * alpha + background * (255 - alpha) + 127) ~/ 255;

int _clamp(int v) => v < 0
    ? 0
    : v > 255
    ? 255
    : v;

/// The colours of [rgb] and their indexes where they are no more than
/// [maxColors], in the order they come; null where they are more.
Map<int, int>? _exact(Int32List rgb, int maxColors) {
  final colors = <int, int>{};
  var last = -1;
  for (final c in rgb) {
    if (c < 0 || c == last) {
      continue;
    }
    last = c;
    if (!colors.containsKey(c)) {
      if (colors.length == maxColors) {
        return null;
      }
      colors[c] = colors.length;
    }
  }
  return colors;
}

/// At most [maxColors] colours for [rgb] by median cut: the colours, 5
/// bits a channel, split into boxes, the box most worth it split each time
/// across its longest side where half its pixels are on either side; each
/// box's colour the mean of the pixels in it.
Int32List _medianCut(Int32List rgb, int maxColors) {
  final counts = Int32List(1 << 15);
  final sums = Float64List(3 << 15);
  for (final c in rgb) {
    if (c < 0) {
      continue;
    }
    final bin = (c >> 9 & 0x7C00) | (c >> 6 & 0x3E0) | (c >> 3 & 0x1F);
    counts[bin]++;
    sums[bin * 3] += c >> 16 & 0xFF;
    sums[bin * 3 + 1] += c >> 8 & 0xFF;
    sums[bin * 3 + 2] += c & 0xFF;
  }
  final bins = Int32List.fromList([
    for (var bin = 0; bin < counts.length; bin++)
      if (counts[bin] > 0) bin,
  ]);
  final boxes = [_Box(bins, 0, bins.length, counts)];
  while (boxes.length < maxColors) {
    _Box? best;
    for (final box in boxes) {
      if (box.end - box.start > 1 &&
          (best == null || box.priority > best.priority)) {
        best = box;
      }
    }
    if (best == null) {
      break;
    }
    boxes
      ..remove(best)
      ..addAll(best.split(bins, counts));
  }
  return Int32List.fromList([
    for (final box in boxes) box.mean(bins, counts, sums),
  ]);
}

/// The bins from [start] up to [end] of a list of them.
final class _Box {
  _Box(Int32List bins, this.start, this.end, Int32List counts) {
    final low = [31, 31, 31];
    final high = [0, 0, 0];
    for (var i = start; i < end; i++) {
      final bin = bins[i];
      pixels += counts[bin];
      for (var c = 0; c < 3; c++) {
        final v = bin >> (10 - c * 5) & 0x1F;
        if (v < low[c]) {
          low[c] = v;
        }
        if (v > high[c]) {
          high[c] = v;
        }
      }
    }
    for (var c = 0; c < 3; c++) {
      final range = high[c] - low[c];
      if (range > longest) {
        longest = range;
        side = c;
      }
    }
  }

  final int start;
  final int end;
  var pixels = 0;
  var longest = -1;
  var side = 0;

  /// How much splitting the box is worth: its pixels times its longest
  /// side.
  double get priority => pixels.toDouble() * (longest + 1);

  List<_Box> split(Int32List bins, Int32List counts) {
    final shift = 10 - side * 5;
    final sorted = bins.sublist(start, end)
      ..sort((a, b) => (a >> shift & 0x1F) - (b >> shift & 0x1F));
    bins.setRange(start, end, sorted);
    var seen = 0;
    var middle = start + 1;
    for (var i = start; i < end - 1; i++) {
      seen += counts[bins[i]];
      middle = i + 1;
      if (seen * 2 >= pixels) {
        break;
      }
    }
    return [_Box(bins, start, middle, counts), _Box(bins, middle, end, counts)];
  }

  int mean(Int32List bins, Int32List counts, Float64List sums) {
    var r = 0.0;
    var g = 0.0;
    var b = 0.0;
    for (var i = start; i < end; i++) {
      final bin = bins[i];
      r += sums[bin * 3];
      g += sums[bin * 3 + 1];
      b += sums[bin * 3 + 2];
    }
    return (r / pixels).round() << 16 |
        (g / pixels).round() << 8 |
        (b / pixels).round();
  }
}

/// The nearest colour of a palette to a colour, remembered for each colour
/// of 5 bits a channel.
final class _Nearest {
  _Nearest(this.colors)
    : _cache = Int16List(1 << 15)..fillRange(0, 1 << 15, -1);

  final Int32List colors;
  final Int16List _cache;

  int of(int r, int g, int b) {
    final bin = (r >> 3) << 10 | (g >> 3) << 5 | b >> 3;
    final cached = _cache[bin];
    if (cached >= 0) {
      return cached;
    }
    // The middle of the bin.
    final cr = r & 0xF8 | 4;
    final cg = g & 0xF8 | 4;
    final cb = b & 0xF8 | 4;
    var best = 0;
    var bestDistance = 1 << 30;
    for (var i = 0; i < colors.length; i++) {
      final c = colors[i];
      final dr = (c >> 16 & 0xFF) - cr;
      final dg = (c >> 8 & 0xFF) - cg;
      final db = (c & 0xFF) - cb;
      final distance = dr * dr + dg * dg + db * db;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    _cache[bin] = best;
    return best;
  }
}
