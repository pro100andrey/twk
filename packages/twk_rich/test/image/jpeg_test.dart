import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_rich/image.dart';

import 'fixtures.dart';

void main() {
  group('decodeJpeg', () {
    for (final name in fixtureNames('jpg')) {
      // libjpeg's own conversion is followed exactly; ImageMagick converts
      // CMYK to RGB in floating point.
      final tolerance = name.contains('cmyk') || name.contains('ycck') ? 1 : 0;
      test('decodes $name as libjpeg does', () {
        final image = decodeJpeg(fixture('$name.jpg'));
        expect(
          (image.width, image.height),
          name == 'jpeg_noise' ? (48, 32) : (37, 23),
        );
        expect(
          _maxDifference(image.pixels, fixture('$name.rgba')),
          lessThanOrEqualTo(tolerance),
        );
      });
    }

    test('decodes data cut short as far as it goes', () {
      final whole = fixture('jpeg420.jpg');
      final image = decodeJpeg(
        Uint8List.sublistView(whole, 0, whole.length - 40),
      );
      expect((image.width, image.height), (37, 23));
      final expected = fixture('jpeg420.rgba');
      // The first row of MCUs is all there, the last not.
      expect(
        image.pixels.sublist(0, 37 * 16 * 4),
        expected.sublist(0, 37 * 16 * 4),
      );
      expect(image.pixels, isNot(expected));
    });

    test('steps over stray and fill bytes before a marker, and bytes '
        'after the data of a scan', () {
      final file = fixture('jpeg444.jpg');
      final at = _segment(file, 0xDB);
      final padded = Uint8List.fromList([
        ...file.sublist(0, at),
        0x00, 0x12, 0xFF, 0xFF, // a stray byte or two, fill
        ...file.sublist(at, file.length - 2),
        ...List.filled(8, 0x00), // after the scan's data
        ...file.sublist(file.length - 2),
      ]);
      expect(decodeJpeg(padded).pixels, fixture('jpeg444.rgba'));
    });

    test('steps over bytes before a restart marker', () {
      final file = fixture('jpeg_restart.jpg');
      var rst = _segment(file, 0xDA);
      while (!(file[rst] == 0xFF && file[rst + 1] == 0xD0)) {
        rst++;
      }
      final padded = Uint8List.fromList([
        ...file.sublist(0, rst),
        ...List.filled(8, 0x00),
        ...file.sublist(rst),
      ]);
      expect(decodeJpeg(padded).pixels, fixture('jpeg_restart.rgba'));
    });

    test('takes three components named R, G and B as RGB without an Adobe '
        'marker', () {
      final file = fixture('jpeg_rgb.jpg');
      final adobe = _segment(file, 0xEE);
      final length = file[adobe + 2] << 8 | file[adobe + 3];
      final named = Uint8List.fromList([
        ...file.sublist(0, adobe),
        ...file.sublist(adobe + 2 + length),
      ]);
      expect(_segment(named, 0xEE), -1);
      expect(decodeJpeg(named).pixels, fixture('jpeg_rgb.rgba'));
    });

    test('decodes data that ends at another marker where a restart marker '
        'should be as data cut short, its end grey', () {
      final file = fixture('jpeg_restart.jpg');
      // the data of the first interval, its last bytes and the restart
      // marker after them cut off
      final rst = _segment(file, 0xDA) + 200;
      final cut = Uint8List.sublistView(file, 0, rst);
      final ended = Uint8List.fromList([...cut, 0xFF, 0xD9]);
      final image = decodeJpeg(ended);
      expect((image.width, image.height), (37, 23));
      expect(image.pixels, decodeJpeg(cut).pixels);
      for (final shift in [16, 8, 0]) {
        expect(
          image.pixel(36, 22) >> shift & 0xFF,
          closeTo(128, 4),
          reason: 'the end grey',
        );
      }
      expect(image.pixels, isNot(fixture('jpeg_restart.rgba')));
    });

    test('rejects an image of more pixels than a decoder makes, of two '
        'components, or a scan of a component it has not', () {
      final file = fixture('jpeg444.jpg');
      final sof = _segment(file, 0xC0);
      final huge = Uint8List.fromList(file)
        ..setRange(sof + 5, sof + 9, [0xFF, 0xFF, 0xFF, 0xFF]);
      expect(
        () => decodeJpeg(huge),
        throwsA(
          isFormatException.having(
            (e) => e.message,
            'message',
            'JPEG of 65535 × 65535 pixels',
          ),
        ),
      );
      final two = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xC0, 0, 14, 8, 0, 16, 0, 16, 2, //
        1, 0x11, 0, 2, 0x11, 0, 0xFF, 0xD9,
      ]);
      expect(
        () => decodeJpeg(two),
        throwsA(
          isFormatException.having(
            (e) => e.message,
            'message',
            'JPEG of 2 components is not supported',
          ),
        ),
      );
      final sos = _segment(file, 0xDA);
      final stranger = Uint8List.fromList(file)..[sos + 5] = 9;
      expect(
        () => decodeJpeg(stranger),
        throwsA(
          isFormatException.having(
            (e) => e.message,
            'message',
            'JPEG scan of component 9',
          ),
        ),
      );
    });

    test('rejects the kinds of JPEG it does not read', () {
      List<int> frame(int marker, int precision) => [
        0xFF, 0xD8, 0xFF, marker, 0, 11, precision, 0, 16, 0, 16, 1, 1, //
        0x11, 0, 0xFF, 0xD9,
      ];
      for (final (marker, precision) in [(0xC3, 8), (0xC9, 8), (0xC1, 12)]) {
        expect(
          () => decodeJpeg(Uint8List.fromList(frame(marker, precision))),
          throwsA(isA<FormatException>()),
          reason: 'SOF ${marker.toRadixString(16)} of $precision bits',
        );
      }
    });

    test('rejects what is not a JPEG file', () {
      expect(
        () => decodeJpeg(Uint8List.fromList([0xFF, 0xD8])),
        throwsFormatException,
      );
      expect(
        () => decodeJpeg(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9])),
        throwsFormatException,
      );
    });
  });
}

/// Where the first segment of [marker] starts in the JPEG file [bytes],
/// its 0xFF: the segments before the first scan stepped over by their
/// lengths; -1 where there is none.
int _segment(Uint8List bytes, int marker) {
  var pos = 2;
  while (pos + 3 < bytes.length && bytes[pos] == 0xFF) {
    if (bytes[pos + 1] == marker) {
      return pos;
    }
    if (bytes[pos + 1] == 0xDA) {
      break;
    }
    pos += 2 + (bytes[pos + 2] << 8 | bytes[pos + 3]);
  }
  return -1;
}

int _maxDifference(Uint8List a, Uint8List b) {
  expect(a.length, b.length);
  var max = 0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    if (d > max) {
      max = d;
    }
  }
  return max;
}
