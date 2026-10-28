import 'dart:typed_data';

import 'bitmap.dart';
import 'palette.dart';

/// [image] as sixel, at its size: the bytes a terminal takes between
/// `ESC P` and `ESC \`.
///
/// They are the parameters `0;1;0` (a pixel not drawn keeps what is under
/// it), `q`, the raster attributes `"1;1;W;H` (square pixels, the image's
/// size), the palette (`#i;2;r;g;b`, in percent) and the image in bands of
/// six rows, a colour at a time, runs of four or more alike `!n`.
///
/// The palette is [image]'s own colours where it has no more than
/// [colors] (at most 256), else [colors] found by median cut, Floyd–
/// Steinberg [dither]ed. A pixel whose alpha is below 128 is not drawn,
/// one above it drawn as it is; where [background] (`0xRRGGBB`) is given,
/// every pixel is blended over it and drawn.
///
/// The terminal draws whole bands: an image whose height is not a multiple
/// of 6 takes the rest of its last band, in which it draws nothing.
Uint8List encodeSixel(
  Bitmap image, {
  int colors = 256,
  bool dither = true,
  int? background,
}) {
  final indexed = Indexed.of(
    image,
    maxColors: colors,
    dither: dither,
    background: background,
  );
  final width = image.width;
  final height = image.height;
  final palette = indexed.colors;
  final indexes = indexed.indexes;
  final out = _Output()
    ..text('0;1;0q"1;1;')
    ..number(width)
    ..byte(0x3B)
    ..number(height);
  for (var i = 0; i < palette.length; i++) {
    final c = palette[i];
    out
      ..byte(0x23)
      ..number(i)
      ..text(';2;')
      ..number(_percent(c >> 16 & 0xFF))
      ..byte(0x3B)
      ..number(_percent(c >> 8 & 0xFF))
      ..byte(0x3B)
      ..number(_percent(c & 0xFF));
  }
  final count = palette.length;
  // For each colour, the six bits of each column of the band.
  final bits = Uint8List(count * width);
  final first = Int32List(count)..fillRange(0, count, -1);
  final last = Int32List(count);
  final used = Int32List(count);
  for (var top = 0; top < height; top += 6) {
    var usedCount = 0;
    for (var row = 0; row < 6 && top + row < height; row++) {
      final bit = 1 << row;
      final at = (top + row) * width;
      for (var x = 0; x < width; x++) {
        final c = indexes[at + x];
        if (c < 0) {
          continue;
        }
        if (first[c] < 0) {
          used[usedCount++] = c;
          first[c] = x;
          last[c] = x;
        } else if (x < first[c]) {
          first[c] = x;
        } else if (x > last[c]) {
          last[c] = x;
        }
        bits[c * width + x] |= bit;
      }
    }
    if (top > 0) {
      out.byte(0x2D);
    }
    for (var u = 0; u < usedCount; u++) {
      final c = used[u];
      if (u > 0) {
        out.byte(0x24);
      }
      out
        ..byte(0x23)
        ..number(c);
      final start = c * width;
      final from = first[c];
      final to = last[c];
      if (from > 0) {
        out.run(0x3F, from);
      }
      for (var x = from; x <= to;) {
        final v = bits[start + x];
        var end = x + 1;
        while (end <= to && bits[start + end] == v) {
          end++;
        }
        out.run(0x3F + v, end - x);
        x = end;
      }
      bits.fillRange(start + from, start + to + 1, 0);
      first[c] = -1;
    }
  }
  return out.bytes;
}

int _percent(int v) => (v * 100 + 127) ~/ 255;

/// A growing buffer of ASCII.
final class _Output {
  var _buffer = Uint8List(1 << 12);
  var _length = 0;

  Uint8List get bytes => Uint8List.sublistView(_buffer, 0, _length);

  void byte(int b) {
    if (_length == _buffer.length) {
      _grow(1);
    }
    _buffer[_length++] = b;
  }

  void text(String s) {
    for (var i = 0; i < s.length; i++) {
      byte(s.codeUnitAt(i));
    }
  }

  void number(int n) {
    if (n >= 10) {
      number(n ~/ 10);
    }
    byte(0x30 + n % 10);
  }

  /// [count] of [char], as `!count char` where that is shorter.
  void run(int char, int count) {
    if (count > 3) {
      byte(0x21);
      number(count);
      byte(char);
    } else {
      for (var i = 0; i < count; i++) {
        byte(char);
      }
    }
  }

  void _grow(int more) {
    final grown = Uint8List((_buffer.length + more) * 2)
      ..setRange(0, _length, _buffer);
    _buffer = grown;
  }
}
