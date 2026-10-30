import 'dart:typed_data';

import 'bitmap.dart';
import 'limits.dart';
import 'zlib.dart';

// Examples can assume:
// import 'dart:io';

const _signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

const _ihdr = 0x49484452;
const _plte = 0x504C5445;
const _trns = 0x74524E53;
const _idat = 0x49444154;
const _iend = 0x49454E44;

/// The interlacing passes of Adam7: the first column and row of each, and
/// the steps between its columns and its rows.
const _adam7 = [
  (0, 0, 8, 8),
  (4, 0, 8, 8),
  (0, 4, 4, 8),
  (2, 0, 4, 4),
  (0, 2, 2, 4),
  (1, 0, 2, 2),
  (0, 1, 1, 2),
];

/// Whether [bytes] start with the PNG signature.
bool isPng(List<int> bytes) {
  if (bytes.length < _signature.length) {
    return false;
  }
  for (var i = 0; i < _signature.length; i++) {
    if (bytes[i] != _signature[i]) {
      return false;
    }
  }
  return true;
}

/// Decodes a PNG file.
///
/// Every colour type at every bit depth PNG allows is read, interlaced
/// (Adam7) or not, with the transparency of a tRNS chunk: alpha for the
/// entries of a palette, or a grey or RGB colour that is transparent. A
/// 16-bit sample keeps its high byte. Gamma and colour space chunks (gAMA,
/// cHRM, sRGB, iCCP) are ignored, the samples taken as they are, and so are
/// the other ancillary chunks: an APNG decodes to its default image. A
/// palette index past the palette's end is opaque black.
///
/// Throws a [FormatException] when [bytes] are not a PNG file, are cut
/// short, fail a chunk's CRC or hold an unknown critical chunk.
///
/// ```dart
/// final icon = decodePng(File('icon.png').readAsBytesSync());
/// final topLeft = icon.pixel(0, 0); // 0xAARRGGBB
/// ```
///
/// See also:
///
///  * `decodeImage`, for a file that may be a JPEG too.
Bitmap decodePng(Uint8List bytes) {
  if (!isPng(bytes)) {
    throw const FormatException('Not a PNG file');
  }
  final data = ByteData.sublistView(bytes);
  var pos = _signature.length;
  var width = 0;
  var height = 0;
  var depth = 0;
  var color = 0;
  var interlaced = false;
  Uint8List? palette;
  Uint8List? transparency;
  final compressed = BytesBuilder(copy: false);
  for (var ended = false; !ended;) {
    if (pos + 12 > bytes.length) {
      throw const FormatException('PNG file cut short');
    }
    final length = data.getUint32(pos);
    final type = data.getUint32(pos + 4);
    final start = pos + 8;
    final end = start + length;
    if (end + 4 > bytes.length) {
      throw const FormatException('PNG file cut short');
    }
    if (_crc32(bytes, pos + 4, end) != data.getUint32(end)) {
      throw const FormatException('PNG chunk fails its CRC');
    }
    if (width == 0 && type != _ihdr) {
      throw const FormatException('PNG file does not start with IHDR');
    }
    final body = Uint8List.sublistView(bytes, start, end);
    switch (type) {
      case _ihdr:
        if (length != 13) {
          throw const FormatException('PNG IHDR of a wrong length');
        }
        width = data.getUint32(start);
        height = data.getUint32(start + 4);
        depth = body[8];
        color = body[9];
        interlaced = body[12] == 1;
        if (!_validDepth(color, depth) ||
            body[10] != 0 ||
            body[11] != 0 ||
            body[12] > 1) {
          throw FormatException(
            'PNG of colour type $color, depth $depth is not supported',
          );
        }
        if (width == 0 || height == 0 || width * height > maxImagePixels) {
          throw FormatException('PNG of $width × $height pixels');
        }
      case _plte:
        palette = body;
      case _trns:
        transparency = body;
      case _idat:
        compressed.add(body);
      case _iend:
        ended = true;
      default:
        if (type & 0x20000000 == 0) {
          throw const FormatException('PNG holds an unknown critical chunk');
        }
    }
    pos = end + 4;
  }
  if (color == 3 && palette == null) {
    throw const FormatException('PNG of a palette without PLTE');
  }
  final bitsPerPixel = _channels(color) * depth;
  // the rows IHDR declares, a filter byte each: inflated no further, as a
  // few KB of deflate can hold gigabytes
  final passes = <(int, int, int, int, int, int)>[];
  var size = 0;
  for (final (x0, y0, dx, dy) in interlaced ? _adam7 : [(0, 0, 1, 1)]) {
    final passWidth = (width - x0 + dx - 1) ~/ dx;
    final passHeight = (height - y0 + dy - 1) ~/ dy;
    if (passWidth <= 0 || passHeight <= 0) {
      continue;
    }
    passes.add((x0, y0, dx, dy, passWidth, passHeight));
    size += passHeight * (((passWidth * bitsPerPixel + 7) >> 3) + 1);
  }
  final raw = zlibInflate(compressed.takeBytes(), limit: size);
  final rows = _Rows(width, height, color, depth, palette, transparency);
  final bpp = bitsPerPixel < 8 ? 1 : bitsPerPixel >> 3;
  var offset = 0;
  for (final (x0, y0, dx, dy, passWidth, passHeight) in passes) {
    final stride = (passWidth * bitsPerPixel + 7) >> 3;
    if (offset + passHeight * (stride + 1) > raw.length) {
      throw const FormatException('PNG image data cut short');
    }
    for (var row = 0; row < passHeight; row++) {
      final at = offset + 1;
      _unfilter(
        raw,
        raw[offset],
        at,
        row == 0 ? -1 : at - stride - 1,
        stride,
        bpp,
      );
      rows.expand(raw, at, passWidth, y0 + row * dy, x0, dx);
      offset += stride + 1;
    }
  }
  return Bitmap.fromRgba(width, height, rows.out);
}

bool _validDepth(int color, int depth) => switch (color) {
  0 => depth == 1 || depth == 2 || depth == 4 || depth == 8 || depth == 16,
  3 => depth == 1 || depth == 2 || depth == 4 || depth == 8,
  2 || 4 || 6 => depth == 8 || depth == 16,
  _ => false,
};

int _channels(int color) => switch (color) {
  2 => 3,
  4 => 2,
  6 => 4,
  _ => 1,
};

/// Reverses the filter of the row of [stride] bytes at [at], the row before
/// it at [prior] (-1 for none), [bpp] bytes to a pixel.
void _unfilter(
  Uint8List raw,
  int filter,
  int at,
  int prior,
  int stride,
  int bpp,
) {
  final end = at + stride;
  switch (filter) {
    case 0:
      break;
    case 1:
      for (var i = at + bpp; i < end; i++) {
        raw[i] += raw[i - bpp];
      }
    case 2:
      if (prior >= 0) {
        for (var i = at, j = prior; i < end; i++, j++) {
          raw[i] += raw[j];
        }
      }
    case 3:
      if (prior < 0) {
        for (var i = at + bpp; i < end; i++) {
          raw[i] += raw[i - bpp] >> 1;
        }
      } else {
        for (var i = at, j = prior; i < at + bpp && i < end; i++, j++) {
          raw[i] += raw[j] >> 1;
        }
        for (var i = at + bpp, j = prior + bpp; i < end; i++, j++) {
          raw[i] += (raw[i - bpp] + raw[j]) >> 1;
        }
      }
    case 4:
      if (prior < 0) {
        // With no row above, Paeth picks the byte to the left.
        for (var i = at + bpp; i < end; i++) {
          raw[i] += raw[i - bpp];
        }
      } else {
        for (var i = at, j = prior; i < at + bpp && i < end; i++, j++) {
          raw[i] += raw[j];
        }
        for (var i = at + bpp, j = prior + bpp; i < end; i++, j++) {
          final a = raw[i - bpp];
          final b = raw[j];
          final c = raw[j - bpp];
          final pa = (b - c).abs();
          final pb = (a - c).abs();
          final pc = (a + b - c - c).abs();
          raw[i] += pa <= pb && pa <= pc
              ? a
              : pb <= pc
              ? b
              : c;
        }
      }
    default:
      throw FormatException('PNG row of unknown filter $filter');
  }
}

/// Turns the unfiltered rows of a PNG into RGBA pixels.
final class _Rows {
  _Rows(
    this.width,
    int height,
    this.color,
    this.depth,
    Uint8List? palette,
    Uint8List? transparency,
  ) : out = Uint8List(width * height * 4) {
    if (palette != null && color == 3) {
      final colors = palette.length ~/ 3;
      for (var i = 0; i < 256; i++) {
        _palette[i * 4 + 3] = 255;
        if (i < colors) {
          _palette[i * 4] = palette[i * 3];
          _palette[i * 4 + 1] = palette[i * 3 + 1];
          _palette[i * 4 + 2] = palette[i * 3 + 2];
        }
      }
      if (transparency != null) {
        for (var i = 0; i < transparency.length && i < 256; i++) {
          _palette[i * 4 + 3] = transparency[i];
        }
      }
    } else if (transparency != null) {
      if (color == 0 && transparency.length >= 2) {
        _key = transparency[0] << 8 | transparency[1];
      } else if (color == 2 && transparency.length >= 6) {
        _key =
            (transparency[0] << 8 | transparency[1]) << 32 |
            (transparency[2] << 8 | transparency[3]) << 16 |
            (transparency[4] << 8 | transparency[5]);
      }
    }
  }

  final int width;
  final int color;
  final int depth;
  final Uint8List out;
  final _palette = Uint8List(256 * 4);

  /// The raw grey sample, or the three raw RGB samples packed 16 bits
  /// each, that is transparent; -1 for none.
  var _key = -1;

  /// Writes the [count] pixels of the row at [at] in [raw] to row [y] of
  /// the image, from column [x0] on, [dx] apart.
  void expand(Uint8List raw, int at, int count, int y, int x0, int dx) {
    final out = this.out;
    var o = (y * width + x0) * 4;
    final step = dx * 4;
    final key = _key;
    if (depth < 8) {
      final mask = (1 << depth) - 1;
      final scale = 255 ~/ mask;
      final palette = color == 3;
      for (var i = 0, bit = 0; i < count; i++, bit += depth, o += step) {
        final v = raw[at + (bit >> 3)] >> (8 - depth - (bit & 7)) & mask;
        if (palette) {
          out[o] = _palette[v * 4];
          out[o + 1] = _palette[v * 4 + 1];
          out[o + 2] = _palette[v * 4 + 2];
          out[o + 3] = _palette[v * 4 + 3];
        } else {
          final g = v * scale;
          out[o] = g;
          out[o + 1] = g;
          out[o + 2] = g;
          out[o + 3] = v == key ? 0 : 255;
        }
      }
      return;
    }
    final wide = depth == 16;
    var p = at;
    switch (color) {
      case 0:
        for (var i = 0; i < count; i++, o += step) {
          final g = raw[p];
          final v = wide ? g << 8 | raw[p + 1] : g;
          p += wide ? 2 : 1;
          out[o] = g;
          out[o + 1] = g;
          out[o + 2] = g;
          out[o + 3] = v == key ? 0 : 255;
        }
      case 2:
        if (!wide) {
          for (var i = 0; i < count; i++, o += step, p += 3) {
            final r = raw[p];
            final g = raw[p + 1];
            final b = raw[p + 2];
            out[o] = r;
            out[o + 1] = g;
            out[o + 2] = b;
            out[o + 3] = key >= 0 && (r << 32 | g << 16 | b) == key ? 0 : 255;
          }
        } else {
          for (var i = 0; i < count; i++, o += step, p += 6) {
            final r = raw[p] << 8 | raw[p + 1];
            final g = raw[p + 2] << 8 | raw[p + 3];
            final b = raw[p + 4] << 8 | raw[p + 5];
            out[o] = r >> 8;
            out[o + 1] = g >> 8;
            out[o + 2] = b >> 8;
            out[o + 3] = key >= 0 && (r << 32 | g << 16 | b) == key ? 0 : 255;
          }
        }
      case 3:
        for (var i = 0; i < count; i++, o += step, p++) {
          final v = raw[p] * 4;
          out[o] = _palette[v];
          out[o + 1] = _palette[v + 1];
          out[o + 2] = _palette[v + 2];
          out[o + 3] = _palette[v + 3];
        }
      case 4:
        final size = wide ? 4 : 2;
        for (var i = 0; i < count; i++, o += step, p += size) {
          final g = raw[p];
          out[o] = g;
          out[o + 1] = g;
          out[o + 2] = g;
          out[o + 3] = raw[p + size ~/ 2];
        }
      default:
        if (!wide && dx == 1) {
          out.setRange(o, o + count * 4, raw, p);
        } else {
          final size = wide ? 2 : 1;
          for (var i = 0; i < count; i++, o += step) {
            out[o] = raw[p];
            out[o + 1] = raw[p + size];
            out[o + 2] = raw[p + 2 * size];
            out[o + 3] = raw[p + 3 * size];
            p += 4 * size;
          }
        }
    }
  }
}

/// Encodes [image] as a PNG file of 8-bit RGB where it is opaque, else
/// RGBA, not interlaced, deflated at zlib [level] (0 to 9): by default 1,
/// the fastest that compresses, since the file is for a terminal to decode
/// at once (level 6 takes three times as long for a sixth less of a
/// photo). Each row is filtered with the filter whose bytes sum the least
/// as signed values, libpng's choice.
///
/// A red square, written to a file:
///
/// ```dart
/// final square = Bitmap(16, 16);
/// for (var y = 0; y < 16; y++) {
///   for (var x = 0; x < 16; x++) {
///     square.setPixel(x, y, 0xFFFF0000);
///   }
/// }
/// File('square.png').writeAsBytesSync(encodePng(square));
/// ```
Uint8List encodePng(Bitmap image, {int level = 1}) {
  final width = image.width;
  final height = image.height;
  final pixels = image.pixels;
  final opaque = image.isOpaque;
  final bpp = opaque ? 3 : 4;
  final stride = width * bpp;
  final filtered = Uint8List(height * (stride + 1));
  var row = Uint8List(stride);
  var prior = Uint8List(stride);
  final candidates = [for (var i = 0; i < 5; i++) Uint8List(stride)];
  for (var y = 0; y < height; y++) {
    if (opaque) {
      for (var x = 0, s = y * width * 4, d = 0; x < width; x++, s += 4) {
        row[d++] = pixels[s];
        row[d++] = pixels[s + 1];
        row[d++] = pixels[s + 2];
      }
    } else {
      row.setRange(0, stride, pixels, y * stride);
    }
    var best = 0;
    var bestSum = 1 << 62;
    // Paeth first, which wins most rows of a photo, so that the others
    // can stop as soon as they lose.
    for (final filter in const [4, 1, 2, 3, 0]) {
      final sum = _filter(row, prior, filter, bpp, candidates[filter], bestSum);
      if (sum < bestSum) {
        best = filter;
        bestSum = sum;
      }
    }
    final at = y * (stride + 1);
    filtered[at] = best;
    filtered.setRange(at + 1, at + 1 + stride, candidates[best]);
    final previous = prior;
    prior = row;
    row = previous;
  }
  final out = BytesBuilder(copy: false)
    ..add(_signature)
    ..add(
      _chunk(
        _ihdr,
        (ByteData(13)
              ..setUint32(0, width)
              ..setUint32(4, height)
              ..setUint8(8, 8)
              ..setUint8(9, opaque ? 2 : 6))
            .buffer
            .asUint8List(),
      ),
    )
    ..add(_chunk(_idat, zlibDeflate(filtered, level: level)))
    ..add(_chunk(_iend, const []));
  return out.takeBytes();
}

/// Filters [row] with [filter] into [out], [prior] the row above (zeros
/// above the first); returns the sum of the bytes of [out] as signed
/// values, or [limit] once it is that much.
int _filter(
  Uint8List row,
  Uint8List prior,
  int filter,
  int bpp,
  Uint8List out,
  int limit,
) {
  final length = row.length;
  var sum = 0;
  // The first pixel: nothing to its left.
  for (var i = 0; i < bpp; i++) {
    final v = switch (filter) {
      2 || 4 => row[i] - prior[i],
      3 => row[i] - (prior[i] >> 1),
      _ => row[i],
    };
    out[i] = v;
    final b = v & 0xFF;
    sum += b < 128 ? b : 256 - b;
  }
  // The rest, a row at a time stopping where the sum reaches the limit.
  const chunk = 256;
  for (var from = bpp; from < length && sum < limit; from += chunk) {
    final to = from + chunk < length ? from + chunk : length;
    switch (filter) {
      case 0:
        for (var i = from; i < to; i++) {
          final v = row[i];
          out[i] = v;
          sum += v < 128 ? v : 256 - v;
        }
      case 1:
        for (var i = from; i < to; i++) {
          final v = (row[i] - row[i - bpp]) & 0xFF;
          out[i] = v;
          sum += v < 128 ? v : 256 - v;
        }
      case 2:
        for (var i = from; i < to; i++) {
          final v = (row[i] - prior[i]) & 0xFF;
          out[i] = v;
          sum += v < 128 ? v : 256 - v;
        }
      case 3:
        for (var i = from; i < to; i++) {
          final v = (row[i] - ((row[i - bpp] + prior[i]) >> 1)) & 0xFF;
          out[i] = v;
          sum += v < 128 ? v : 256 - v;
        }
      default:
        for (var i = from; i < to; i++) {
          final a = row[i - bpp];
          final b = prior[i];
          final c = prior[i - bpp];
          final pa = (b - c).abs();
          final pb = (a - c).abs();
          final pc = (a + b - c - c).abs();
          final predicted = pa <= pb && pa <= pc
              ? a
              : pb <= pc
              ? b
              : c;
          final v = (row[i] - predicted) & 0xFF;
          out[i] = v;
          sum += v < 128 ? v : 256 - v;
        }
    }
  }
  return sum < limit ? sum : limit;
}

Uint8List _chunk(int type, List<int> body) {
  final out = Uint8List(body.length + 12);
  ByteData.sublistView(out)
    ..setUint32(0, body.length)
    ..setUint32(4, type);
  out.setRange(8, 8 + body.length, body);
  ByteData.sublistView(out).setUint32(
    8 + body.length,
    _crc32(out, 4, 8 + body.length),
  );
  return out;
}

final Uint32List _crcTable = _crcTableOf();

Uint32List _crcTableOf() {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[n] = c;
  }
  return table;
}

/// The CRC-32 of [bytes] from [start] up to [end], as PNG computes it.
int _crc32(List<int> bytes, int start, int end) {
  final table = _crcTable;
  var c = 0xFFFFFFFF;
  for (var i = start; i < end; i++) {
    c = table[(c ^ bytes[i]) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}
