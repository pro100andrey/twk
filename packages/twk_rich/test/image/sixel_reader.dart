import 'dart:typed_data';

/// What a terminal draws of sixel data, the bytes between `ESC P` and
/// `ESC \`: the raster attributes' size and the colour of each pixel drawn.
final class SixelPicture {
  SixelPicture._(this.parameters, this.width, this.height, this.pixels);

  /// The numbers before `q`.
  final List<int> parameters;
  final int width;
  final int height;

  /// `0xRRGGBB` for each pixel drawn, null for those not.
  final List<int?> pixels;

  int? pixel(int x, int y) => pixels[y * width + x];
}

/// Reads sixel data as a terminal would, failing on anything drawn outside
/// the raster attributes' size and on what it does not know.
SixelPicture readSixel(Uint8List data) {
  var pos = 0;
  int number() {
    var n = 0;
    final start = pos;
    while (pos < data.length && data[pos] >= 0x30 && data[pos] <= 0x39) {
      n = n * 10 + data[pos++] - 0x30;
    }
    if (pos == start) {
      throw FormatException('number expected', data, pos);
    }
    return n;
  }

  List<int> numbers() {
    final out = [number()];
    while (pos < data.length && data[pos] == 0x3B) {
      pos++;
      out.add(number());
    }
    return out;
  }

  final parameters = data[0] == 0x71 ? <int>[] : numbers();
  if (data[pos++] != 0x71) {
    throw FormatException('q expected', data, pos - 1);
  }
  if (data[pos++] != 0x22) {
    throw FormatException('raster attributes expected', data, pos - 1);
  }
  final raster = numbers();
  if (raster.length != 4 || raster[0] != 1 || raster[1] != 1) {
    throw FormatException('square pixels expected: $raster');
  }
  final width = raster[2];
  final height = raster[3];
  final pixels = List<int?>.filled(width * height, null);
  final palette = <int, int>{};
  var color = 0;
  var x = 0;
  var y = 0;
  void draw(int sixel, int count) {
    for (var i = 0; i < count; i++, x++) {
      for (var bit = 0; bit < 6; bit++) {
        if (sixel & 1 << bit == 0) {
          continue;
        }
        if (x >= width || y + bit >= height) {
          throw FormatException('drawn outside at $x, ${y + bit}');
        }
        pixels[(y + bit) * width + x] =
            palette[color] ??
            (throw FormatException('colour $color undefined'));
      }
    }
  }

  while (pos < data.length) {
    final c = data[pos++];
    if (c == 0x23) {
      color = number();
      if (pos < data.length && data[pos] == 0x3B) {
        pos++;
        final definition = numbers();
        if (definition.length != 4 || definition[0] != 2) {
          throw FormatException('RGB colour expected: $definition');
        }
        int channel(int percent) => (percent * 255 + 50) ~/ 100;
        palette[color] =
            channel(definition[1]) << 16 |
            channel(definition[2]) << 8 |
            channel(definition[3]);
      }
    } else if (c == 0x21) {
      final count = number();
      draw(data[pos++] - 0x3F, count);
    } else if (c == 0x24) {
      x = 0;
    } else if (c == 0x2D) {
      x = 0;
      y += 6;
    } else if (c >= 0x3F && c <= 0x7E) {
      draw(c - 0x3F, 1);
    } else {
      throw FormatException('unknown byte', data, pos - 1);
    }
  }
  return SixelPicture._(parameters, width, height, pixels);
}
