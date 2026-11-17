import 'dart:typed_data';

import 'animated.dart';
import 'bitmap.dart';
import 'limits.dart';

// Examples can assume:
// import 'dart:io';

/// Whether [bytes] start with a GIF signature (`GIF87a` or `GIF89a`).
bool isGif(List<int> bytes) =>
    bytes.length >= 6 &&
    bytes[0] == 0x47 &&
    bytes[1] == 0x49 &&
    bytes[2] == 0x46 &&
    bytes[3] == 0x38 &&
    (bytes[4] == 0x37 || bytes[4] == 0x39) &&
    bytes[5] == 0x61;

/// The most frames a GIF may have.
const int _maxFrames = 1 << 14;

/// Decodes the frames of a GIF file, each composed on the logical screen
/// as its disposal method says (none, leave, restore to the background,
/// restore to the previous), transparent pixels leaving what is under them,
/// the screen starting transparent. Interlaced frames and local colour
/// tables are read. A frame's delay is its graphic control extension's (a
/// delay of 10 ms or less shows for 100 ms, as browsers show it), and the
/// plays are those its NETSCAPE2.0 loop count asks for, a count of repeats
/// after the first play ([AnimatedImage.loops]; one play where the file has
/// none).
///
/// A file cut short after its first frame decodes to the frames it has.
///
/// Throws a [FormatException] when [bytes] are not a GIF file, hold no
/// frame, or have a frame that does not decode or whose data is invalid.
///
/// ```dart
/// final gif = decodeGif(File('spinner.gif').readAsBytesSync());
/// print('${gif.frames.length} frames, ${gif.duration} a play');
/// ```
///
/// See also:
///
///  * `decodeImage`, which reads the first frame of a GIF.
AnimatedImage decodeGif(Uint8List bytes) {
  if (!isGif(bytes)) {
    throw const FormatException('Not a GIF file');
  }
  final r = _Reader(bytes)..pos = 6;
  final width = r.u16();
  final height = r.u16();
  final flags = r.u8();
  r.take(2); // the background index and the aspect ratio
  if (width == 0 || height == 0 || width * height > maxImagePixels) {
    throw FormatException('GIF of $width × $height pixels');
  }
  Uint8List? globalColors;
  if (flags & 0x80 != 0) {
    globalColors = r.take(3 << ((flags & 7) + 1));
  }
  final canvas = Bitmap(width, height);
  final frames = <ImageFrame>[];
  var loops = 1;
  // the graphic control of the next image
  var delay = 0;
  var disposal = 0;
  var transparent = -1;
  // what the previous frame asks of the canvas before the next draws
  var lastDisposal = 0;
  var lastRect = (0, 0, 0, 0);
  Uint8List? restore;
  try {
    for (var ended = false; !ended;) {
      switch (r.u8()) {
        case 0x3B:
          ended = true;
        case 0x21:
          final label = r.u8();
          if (label == 0xF9) {
            final size = r.u8();
            if (size < 4) {
              throw const FormatException('GIF graphic control too short');
            }
            final packed = r.u8();
            disposal = packed >> 2 & 7;
            delay = r.u16();
            final index = r.u8();
            transparent = packed & 1 != 0 ? index : -1;
            r
              ..take(size - 4)
              ..skipBlocks();
          } else if (label == 0xFF) {
            final size = r.u8();
            final id = r.take(size);
            final name = String.fromCharCodes(id);
            final isLoop = name == 'NETSCAPE2.0' || name == 'ANIMEXTS1.0';
            for (var n = r.u8(); n > 0; n = r.u8()) {
              final block = r.take(n);
              if (isLoop && n >= 3 && block[0] == 1) {
                final again = block[1] | block[2] << 8;
                // a count of repeats after the first play, 0 for ever
                loops = again == 0 ? 0 : again + 1;
              }
            }
          } else {
            r.skipBlocks();
          }
        case 0x2C:
          final left = r.u16();
          final top = r.u16();
          final w = r.u16();
          final h = r.u16();
          final packed = r.u8();
          if (w == 0 || h == 0 || left + w > width || top + h > height) {
            throw const FormatException('GIF frame outside its screen');
          }
          if (frames.length >= _maxFrames ||
              (frames.length + 1) * width * height > maxImagePixels) {
            throw const FormatException('GIF of too many frames');
          }
          final colors = packed & 0x80 != 0
              ? r.take(3 << ((packed & 7) + 1))
              : globalColors;
          final indices = _lzw(r, w * h);
          // what the previous frame leaves under this one
          switch (lastDisposal) {
            case 2:
              _clear(canvas, lastRect);
            case 3:
              if (restore != null) {
                canvas.pixels.setAll(0, restore);
              }
          }
          restore = disposal == 3 ? Uint8List.fromList(canvas.pixels) : null;
          _draw(
            canvas,
            indices,
            colors,
            (left, top, w, h),
            interlaced: packed & 0x40 != 0,
            transparent: transparent,
          );
          frames.add(
            ImageFrame(
              Bitmap.fromRgba(
                width,
                height,
                Uint8List.fromList(canvas.pixels),
              ),
              frameDelay(delay * 10000),
            ),
          );
          lastDisposal = disposal;
          lastRect = (left, top, w, h);
          delay = 0;
          disposal = 0;
          transparent = -1;
        default:
          throw const FormatException('GIF holds an unknown block');
      }
    }
  } on FormatException {
    if (frames.isEmpty) {
      rethrow;
    }
  }
  if (frames.isEmpty) {
    throw const FormatException('GIF without a frame');
  }
  return AnimatedImage(frames, loops: loops);
}

/// Makes [rect], left, top, width and height, of [canvas] transparent.
void _clear(Bitmap canvas, (int, int, int, int) rect) {
  final (left, top, w, h) = rect;
  for (var y = top; y < top + h; y++) {
    final from = (y * canvas.width + left) * 4;
    canvas.pixels.fillRange(from, from + w * 4, 0);
  }
}

/// The rows of an interlaced image of [height] rows, in the order they are
/// stored: row k of the file is row `order[k]` of the image.
List<int> _interlaced(int height) => [
  for (final (start, step) in const [(0, 8), (4, 8), (2, 4), (1, 2)])
    for (var y = start; y < height; y += step) y,
];

/// Draws the colour [indices] of a frame at [rect] on [canvas]; those of
/// [transparent] leave what is there.
void _draw(
  Bitmap canvas,
  Uint8List indices,
  Uint8List? colors,
  (int, int, int, int) rect, {
  required bool interlaced,
  required int transparent,
}) {
  final (left, top, w, h) = rect;
  final out = canvas.pixels;
  final palette = colors ?? Uint8List(0);
  final order = interlaced ? _interlaced(h) : null;
  for (var k = 0; k < h; k++) {
    final y = order == null ? k : order[k];
    var o = ((top + y) * canvas.width + left) * 4;
    for (var x = 0; x < w; x++, o += 4) {
      final i = indices[k * w + x];
      if (i == transparent) {
        continue;
      }
      if (i * 3 + 2 < palette.length) {
        out[o] = palette[i * 3];
        out[o + 1] = palette[i * 3 + 1];
        out[o + 2] = palette[i * 3 + 2];
      } else {
        out[o] = 0;
        out[o + 1] = 0;
        out[o + 2] = 0;
      }
      out[o + 3] = 255;
    }
  }
}

/// Reads an image's LZW data (its minimum code size, then sub-blocks) into
/// [count] colour indices; a stream that ends early leaves the rest zero.
Uint8List _lzw(_Reader r, int count) {
  final minimum = r.u8();
  if (minimum < 1 || minimum > 11) {
    throw FormatException('GIF with an LZW code size of $minimum');
  }
  final compressed = BytesBuilder(copy: false);
  for (var n = r.u8(); n > 0; n = r.u8()) {
    compressed.add(r.take(n));
  }
  final data = compressed.takeBytes();
  final out = Uint8List(count);
  final clear = 1 << minimum;
  final end = clear + 1;
  // the table: each code is its prefix's string and one more byte
  final prefix = Int16List(4096);
  final suffix = Uint8List(4096);
  final lengths = Uint16List(4096);
  for (var i = 0; i < clear; i++) {
    suffix[i] = i;
    lengths[i] = 1;
  }
  var size = minimum + 1;
  var next = end + 1;
  var previous = -1;
  var bits = 0;
  var accumulated = 0;
  var pos = 0;
  var written = 0;
  while (written < count) {
    while (bits < size && pos < data.length) {
      accumulated |= data[pos++] << bits;
      bits += 8;
    }
    if (bits < size) {
      break;
    }
    final code = accumulated & ((1 << size) - 1);
    accumulated >>= size;
    bits -= size;
    if (code == clear) {
      size = minimum + 1;
      next = end + 1;
      previous = -1;
      continue;
    }
    if (code == end) {
      break;
    }
    int first;
    if (previous < 0) {
      if (code >= clear) {
        throw const FormatException('GIF LZW stream starts with a bad code');
      }
      out[written++] = code;
      previous = code;
      continue;
    }
    var entry = code;
    if (code >= next) {
      if (code > next) {
        throw const FormatException('GIF LZW code past the table');
      }
      // the string of the previous code and its own first byte
      entry = previous;
    }
    // write the string of [entry] backwards from its end
    final length = lengths[entry];
    var at = written + length - 1;
    first = entry;
    for (var c = entry; ; c = prefix[c]) {
      if (at < count) {
        out[at] = suffix[c];
      }
      at--;
      if (lengths[c] == 1) {
        first = c;
        break;
      }
    }
    var added = length;
    if (code >= next) {
      // the new code's string ends with the first byte of the previous
      if (written + added < count) {
        out[written + added] = suffix[first];
      }
      added++;
    }
    written += added;
    if (next < 4096) {
      prefix[next] = previous;
      suffix[next] = suffix[first];
      lengths[next] = lengths[previous] + 1;
      next++;
      if (next == 1 << size && size < 12) {
        size++;
      }
    }
    previous = code;
  }
  return out;
}

/// Reads [data] in order, a [FormatException] where it is cut short.
final class _Reader {
  _Reader(this.data);

  final Uint8List data;
  var pos = 0;

  static const _cut = FormatException('GIF file cut short');

  int u8() {
    if (pos >= data.length) {
      throw _cut;
    }
    return data[pos++];
  }

  int u16() {
    final low = u8();
    return low | u8() << 8;
  }

  Uint8List take(int n) {
    if (pos + n > data.length) {
      throw _cut;
    }
    final v = Uint8List.sublistView(data, pos, pos + n);
    pos += n;
    return v;
  }

  /// Skips sub-blocks up to and with the terminator.
  void skipBlocks() {
    for (var n = u8(); n > 0; n = u8()) {
      take(n);
    }
  }
}
