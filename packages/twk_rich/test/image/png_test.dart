import 'dart:io' show ZLibEncoder;
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_rich/image.dart';

import 'fixtures.dart';

void main() {
  group('decodePng', () {
    for (final name in fixtureNames('png')) {
      test('decodes $name to the pixels it was made of', () {
        final image = decodePng(fixture('$name.png'));
        final expected = fixture('$name.rgba');
        expect(image.width * image.height * 4, expected.length);
        expect(image.pixels, expected);
      });
    }

    test('reads the size from IHDR', () {
      final image = decodePng(fixture('rgb8_adam7_2x3.png'));
      expect((image.width, image.height), (2, 3));
    });

    test('gives known pixels', () {
      // (x * 37 + y * 91 + c * 53) % 256 for channel c, as
      // tool/image/fixtures.py makes the 8-bit samples.
      final rgba = decodePng(fixture('rgba8.png'));
      expect(rgba.pixel(0, 0), 0x9F00356A);
      expect(rgba.pixel(2, 1), 0x44A5DA0F);
      // A 16-bit sample keeps its high byte.
      final rgb16 = decodePng(fixture('rgb16.png'));
      expect(rgb16.pixel(1, 0) >> 16 & 0xFF, 7919 >> 8);
      // Palette entry i is (i * 67, i * 131, i * 29 + 7), its alpha i * 41
      // in the first half; index (x + 3 * y) % 4.
      final palette = decodePng(fixture('palette2_trns.png'));
      expect(palette.pixel(1, 0), 0x29438324);
      expect(palette.pixel(3, 0), 0xFFC9895E);
      // A colour key: grey 1 of 4 bits is transparent.
      final keyed = decodePng(fixture('gray4_trns.png'));
      expect(keyed.pixel(1, 0), 0x00111111);
      expect(keyed.pixel(2, 0), 0xFF222222);
      // One bit: 0 black, 1 white.
      final bits = decodePng(fixture('gray1.png'));
      expect(bits.pixel(0, 0), 0xFF000000);
      expect(bits.pixel(1, 0), 0xFFFFFFFF);
    });

    test('inflates no more than the rows IHDR declares', () {
      // 1 × 1 RGB is 4 bytes of rows; 16 MiB of zeros deflates to some
      // 16 KB, which a bomb of gigabytes is a few hundred times
      final png = _png(1, 1, Uint8List(16 << 20));
      expect(png.length, lessThan(64 << 10));
      expect(
        () => decodePng(png),
        throwsA(
          isFormatException.having(
            (e) => e.message,
            'message',
            contains('more than 4 bytes'),
          ),
        ),
      );
    });

    test('rejects what is not a PNG file', () {
      expect(
        () => decodePng(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
      final png = fixture('rgb8.png');
      expect(
        () => decodePng(Uint8List.sublistView(png, 0, png.length - 20)),
        throwsFormatException,
      );
      final corrupt = Uint8List.fromList(png)..[40] ^= 0xFF;
      expect(() => decodePng(corrupt), throwsFormatException);
    });

    test('skips an unknown ancillary chunk, rejects a critical one', () {
      final png = fixture('rgb8.png');
      // After the signature and IHDR's 25 bytes.
      Uint8List withChunk(String type) => Uint8List.fromList([
        ...png.sublist(0, 33),
        ..._chunk(type, [1, 2, 3]),
        ...png.sublist(33),
      ]);
      expect(decodePng(withChunk('quUx')).pixels, fixture('rgb8.rgba'));
      expect(() => decodePng(withChunk('QUUX')), throwsFormatException);
    });

    test('rejects a header PNG does not allow: a depth the colour type '
        'has not, a compression, filter or interlace method it has not', () {
      final rows = [0, 1, 2, 3];
      expect(
        decodePng(_png(1, 1, rows)).pixel(0, 0),
        0xFF010203,
      );
      for (final (depth, color, method, filter, interlace) in [
        (4, 2, 0, 0, 0),
        (8, 7, 0, 0, 0),
        (8, 2, 1, 0, 0),
        (8, 2, 0, 1, 0),
        (8, 2, 0, 0, 2),
      ]) {
        expect(
          () => decodePng(
            _png(
              1,
              1,
              rows,
              depth: depth,
              color: color,
              method: method,
              filter: filter,
              interlace: interlace,
            ),
          ),
          throwsA(
            isFormatException.having(
              (e) => e.message,
              'message',
              contains('not supported'),
            ),
          ),
          reason: 'depth $depth, colour $color, $method/$filter/$interlace',
        );
      }
    });

    test('rejects an image of no pixels, or of more than a decoder makes', () {
      for (final (width, height) in [(0, 1), (1, 0), (1 << 16, 1 << 13)]) {
        expect(
          () => decodePng(_png(width, height, const [0, 0, 0, 0])),
          throwsA(
            isFormatException.having(
              (e) => e.message,
              'message',
              'PNG of $width × $height pixels',
            ),
          ),
        );
      }
    });

    test('rejects a row filtered by a filter PNG does not have', () {
      expect(
        () => decodePng(_png(1, 1, [5, 1, 2, 3])),
        throwsA(
          isFormatException.having(
            (e) => e.message,
            'message',
            'PNG row of unknown filter 5',
          ),
        ),
      );
    });
  });

  group('encodePng', () {
    test('round-trips an opaque image as RGB', () {
      final image = _noise(37, 21, opaque: true);
      final png = encodePng(image);
      expect(png[25], 2, reason: 'colour type RGB');
      final decoded = decodePng(png);
      expect((decoded.width, decoded.height), (37, 21));
      expect(decoded.pixels, image.pixels);
    });

    test('round-trips alpha as RGBA', () {
      final image = _noise(19, 33, opaque: false);
      final png = encodePng(image);
      expect(png[25], 6, reason: 'colour type RGBA');
      expect(decodePng(png).pixels, image.pixels);
    });

    test('round-trips gradients, where each filter does best', () {
      final image = Bitmap(64, 48);
      for (var y = 0; y < 48; y++) {
        for (var x = 0; x < 64; x++) {
          image.setPixel(x, y, 0xFF000000 | x * 4 << 16 | y * 5 << 8 | x + y);
        }
      }
      for (final level in [0, 1, 9]) {
        expect(decodePng(encodePng(image, level: level)).pixels, image.pixels);
      }
    });

    test('round-trips a single pixel', () {
      final image = Bitmap(1, 1)..setPixel(0, 0, 0x80FF0000);
      expect(decodePng(encodePng(image)).pixel(0, 0), 0x80FF0000);
    });
  });
}

/// A PNG of [width] × [height] pixels whose rows, each with its filter
/// byte first, are [rows], deflated in one IDAT; RGB of 8 bits unless
/// [depth] and [color] say otherwise, and IHDR's [method], [filter] and
/// [interlace] as given.
Uint8List _png(
  int width,
  int height,
  List<int> rows, {
  int depth = 8,
  int color = 2,
  int method = 0,
  int filter = 0,
  int interlace = 0,
}) {
  List<int> u32(int v) => [
    v >> 24 & 0xFF,
    v >> 16 & 0xFF,
    v >> 8 & 0xFF,
    v & 0xFF,
  ];
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    ..._chunk('IHDR', [
      ...u32(width),
      ...u32(height),
      depth,
      color,
      method,
      filter,
      interlace,
    ]),
    ..._chunk('IDAT', ZLibEncoder().convert(rows)),
    ..._chunk('IEND', const []),
  ]);
}

/// A PNG chunk of [type] holding [body].
List<int> _chunk(String type, List<int> body) {
  final typed = [...type.codeUnits, ...body];
  var crc = 0xFFFFFFFF;
  for (final byte in typed) {
    crc ^= byte;
    for (var k = 0; k < 8; k++) {
      crc = crc & 1 != 0 ? 0xEDB88320 ^ crc >> 1 : crc >> 1;
    }
  }
  crc ^= 0xFFFFFFFF;
  List<int> u32(int v) => [
    v >> 24 & 0xFF,
    v >> 16 & 0xFF,
    v >> 8 & 0xFF,
    v & 0xFF,
  ];
  return [...u32(body.length), ...typed, ...u32(crc)];
}

Bitmap _noise(int width, int height, {required bool opaque}) {
  final random = Random(width * height);
  final image = Bitmap(width, height);
  for (var i = 0; i < image.pixels.length; i++) {
    image.pixels[i] = opaque && i % 4 == 3 ? 255 : random.nextInt(256);
  }
  return image;
}
