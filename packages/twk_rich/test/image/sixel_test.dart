import 'dart:convert';
import 'dart:math';

import 'package:test/test.dart';
import 'package:twk_rich/image.dart';

import 'sixel_reader.dart';

void main() {
  group('encodeSixel', () {
    test('writes parameters, raster attributes and the palette first', () {
      final image = Bitmap(3, 2);
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 3; x++) {
          image.setPixel(x, y, 0xFFFF0000);
        }
      }
      final text = ascii.decode(encodeSixel(image));
      expect(text, startsWith('0;1;0q"1;1;3;2#0;2;100;0;0'));
      // Rows 0 and 1 of the band: bits 1 + 2, '?' + 3.
      expect(text, endsWith('#0BBB'));
    });

    test('draws an image of few colours in its own colours', () {
      // Colours whose channels are whole percents read back exactly.
      const colors = [0xFF0000, 0x00FF00, 0x0000FF, 0xFFFFFF, 0x000000];
      final image = Bitmap(23, 17);
      for (var y = 0; y < 17; y++) {
        for (var x = 0; x < 23; x++) {
          image.setPixel(x, y, 0xFF000000 | colors[(x ~/ 3 + y ~/ 2) % 5]);
        }
      }
      final picture = readSixel(encodeSixel(image));
      expect(picture.parameters, [0, 1, 0]);
      expect((picture.width, picture.height), (23, 17));
      for (var y = 0; y < 17; y++) {
        for (var x = 0; x < 23; x++) {
          expect(picture.pixel(x, y), image.pixel(x, y) & 0xFFFFFF);
        }
      }
    });

    test('runs of four or more alike as !n', () {
      final image = Bitmap(40, 6);
      for (var y = 0; y < 6; y++) {
        for (var x = 0; x < 40; x++) {
          image.setPixel(x, y, 0xFF336699);
        }
      }
      final text = ascii.decode(encodeSixel(image));
      expect(text, endsWith('#0!40~'));
      expect(readSixel(encodeSixel(image)).pixel(39, 5), 0x336699);
    });

    test('leaves transparent pixels undrawn', () {
      final image = Bitmap(8, 9);
      for (var y = 0; y < 9; y++) {
        for (var x = 0; x < 8; x++) {
          image.setPixel(x, y, (x + y).isEven ? 0xFF00FF00 : 0x7F0000FF);
        }
      }
      final picture = readSixel(encodeSixel(image));
      for (var y = 0; y < 9; y++) {
        for (var x = 0; x < 8; x++) {
          expect(picture.pixel(x, y), (x + y).isEven ? 0x00FF00 : null);
        }
      }
    });

    for (final dither in [false, true]) {
      test('leaves transparent pixels undrawn among more colours than '
          'the palette holds, ${dither ? '' : 'not '}dithered', () {
        final image = Bitmap(16, 16);
        for (var y = 0; y < 16; y++) {
          for (var x = 0; x < 16; x++) {
            image.setPixel(
              x,
              y,
              x == y ? 0x00000000 : 0xFF000000 | x * 16 << 16 | y * 16 << 8,
            );
          }
        }
        final picture = readSixel(
          encodeSixel(image, colors: 8, dither: dither),
        );
        for (var y = 0; y < 16; y++) {
          for (var x = 0; x < 16; x++) {
            expect(
              picture.pixel(x, y) == null,
              x == y,
              reason: '($x, $y) drawn only where it is opaque',
            );
          }
        }
      });
    }

    test('blends every pixel over a background where one is given', () {
      final image = Bitmap(2, 1)
        ..setPixel(0, 0, 0x00FF0000)
        ..setPixel(1, 0, 0xFF00FF00);
      final picture = readSixel(encodeSixel(image, background: 0xFFFFFF));
      expect(picture.pixel(0, 0), 0xFFFFFF);
      expect(picture.pixel(1, 0), 0x00FF00);
    });

    for (final dither in [false, true]) {
      test('quantises a picture of many colours '
          '${dither ? 'with' : 'without'} dithering', () {
        final image = _picture(64, 40);
        final picture = readSixel(encodeSixel(image, dither: dither));
        final palette = <int?>{...picture.pixels};
        expect(palette, hasLength(lessThanOrEqualTo(256)));
        expect(palette, isNot(contains(null)));
        var error = 0;
        for (var y = 0; y < 40; y++) {
          for (var x = 0; x < 64; x++) {
            final a = image.pixel(x, y);
            final b = picture.pixel(x, y)!;
            for (var shift = 0; shift < 24; shift += 8) {
              error += ((a >> shift & 0xFF) - (b >> shift & 0xFF)).abs();
            }
          }
        }
        // The mean error of a channel.
        expect(error / (64 * 40 * 3), lessThan(dither ? 8 : 5));
      });
    }

    test('quantises to as few colours as asked', () {
      final picture = readSixel(encodeSixel(_picture(32, 32), colors: 8));
      expect(<int?>{...picture.pixels}, hasLength(lessThanOrEqualTo(8)));
    });
  });

  group('sixelImage', () {
    test('scales to the box in whole bands of six pixels', () {
      // 3 rows of 17 pixels: 51, taken down to 48, 8 bands.
      final encoded = sixelImage(
        _picture(100, 100),
        columns: 10,
        rows: 3,
        cell: const CellSize(9, 17),
      );
      expect((encoded.pixelWidth, encoded.pixelHeight), (48, 48));
      final picture = readSixel(encoded.data);
      expect((picture.width, picture.height), (48, 48));
    });

    test('covers the box, cut to it', () {
      final encoded = sixelImage(
        _picture(100, 50),
        columns: 4,
        rows: 2,
        fit: ImageFit.cover,
      );
      expect((encoded.pixelWidth, encoded.pixelHeight), (40, 36));
    });
  });
}

/// Smooth colours with noise on them.
Bitmap _picture(int width, int height) {
  final random = Random(1);
  final image = Bitmap(width, height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      int channel(double v) =>
          (v * 255 + random.nextInt(17) - 8).round().clamp(0, 255);
      image.setPixel(
        x,
        y,
        0xFF000000 |
            channel(x / width) << 16 |
            channel(y / height) << 8 |
            channel((x + y) / (width + height)),
      );
    }
  }
  return image;
}
