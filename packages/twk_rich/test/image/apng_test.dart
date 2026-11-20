import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_rich/image.dart';

import 'fixtures.dart';

/// Pillow's frames of `<name>.apng`: tool/image/anim_fixtures.py.
void expectFrames(AnimatedImage image, String name) {
  final bytes = fixture('$name.frames');
  final expected = ByteData.sublistView(bytes);
  final width = expected.getUint32(0, Endian.little);
  final height = expected.getUint32(4, Endian.little);
  expect((image.width, image.height), (width, height));
  expect(image.loops, expected.getUint32(8, Endian.little));
  expect(image.frames, hasLength(expected.getUint32(12, Endian.little)));
  var at = 16;
  for (final (i, frame) in image.frames.indexed) {
    final size = width * height * 4;
    expect(
      frame.delay.inMilliseconds,
      expected.getUint32(at, Endian.little),
      reason: 'delay of frame $i',
    );
    expect(
      frame.bitmap.pixels,
      bytes.sublist(at + 4, at + 4 + size),
      reason: 'pixels of frame $i',
    );
    at += 4 + size;
  }
}

/// The pixels of [image] as `0xAARRGGBB`.
List<int> argb(Bitmap image) => [
  for (var y = 0; y < image.height; y++)
    for (var x = 0; x < image.width; x++) image.pixel(x, y),
];

/// A frame of [apngBytes]: [w] × [h] pixels of [color] at ([x], [y]),
/// [dispose] and [blend] as the fcTL says, a delay of [num] / [den] s.
final class F {
  F(
    this.x,
    this.y,
    this.w,
    this.h,
    this.color, {
    this.dispose = 0,
    this.blend = 0,
    this.num = 1,
    this.den = 10,
  });

  final int x;
  final int y;
  final int w;
  final int h;
  final int color;
  final int dispose;
  final int blend;
  final int num;
  final int den;
}

/// An APNG of a [width] × [height] canvas of [frames], the first of which
/// is the default image too.
Uint8List apngBytes(int width, int height, List<F> frames) {
  final out = BytesBuilder()
    ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void add(String type, List<int> body) {
    final bytes = Uint8List(12 + body.length);
    ByteData.sublistView(bytes).setUint32(0, body.length);
    bytes
      ..setAll(4, type.codeUnits)
      ..setAll(8, body);
    _crc(bytes, 0);
    out.add(bytes);
  }

  List<int> u32s(List<int> values) {
    final b = Uint8List(values.length * 4);
    for (var i = 0; i < values.length; i++) {
      ByteData.sublistView(b).setUint32(i * 4, values[i]);
    }
    return b;
  }

  // a frame's compressed data: RGBA rows of the filter 0
  Uint8List stream(int w, int h, int argb) {
    final row = [
      0,
      for (var x = 0; x < w; x++) ...[
        argb >> 16 & 0xFF,
        argb >> 8 & 0xFF,
        argb & 0xFF,
        argb >>> 24,
      ],
    ];
    return Uint8List.fromList(
      ZLibEncoder().convert([for (var y = 0; y < h; y++) ...row]),
    );
  }

  add('IHDR', [
    ...u32s([width, height]),
    8,
    6,
    0,
    0,
    0,
  ]);
  add('acTL', u32s([frames.length, 0]));
  var sequence = 0;
  for (final (i, f) in frames.indexed) {
    add('fcTL', [
      ...u32s([sequence++, f.w, f.h, f.x, f.y]),
      f.num >> 8,
      f.num & 0xFF,
      f.den >> 8,
      f.den & 0xFF,
      f.dispose,
      f.blend,
    ]);
    final data = stream(f.w, f.h, f.color);
    if (i == 0) {
      add('IDAT', data);
    } else {
      add('fdAT', [
        ...u32s([sequence++]),
        ...data,
      ]);
    }
  }
  add('IEND', const []);
  return out.takeBytes();
}

void main() {
  group('decodeApng against Pillow', () {
    for (final name in ['anim_over', 'anim_background']) {
      test('$name: every frame composed, with its delay and the plays', () {
        expectFrames(decodeApng(fixture('$name.apng')), name);
      });
    }

    test('the frames reached backwards are those reached in order', () {
      for (final name in ['anim_over', 'anim_background']) {
        final inOrder = decodeApng(fixture('$name.apng'));
        final image = decodeApng(fixture('$name.apng'), windowBytes: 0);
        for (var i = inOrder.frameCount - 1; i >= 0; i--) {
          expect(
            image.bitmapAt(i).pixels,
            inOrder.bitmapAt(i).pixels,
            reason: '$name frame $i',
          );
        }
        expect(image.keptFrames, 1);
      }
    });

    test('anim_default: an IDAT before the first fcTL is no frame', () {
      final image = decodeApng(fixture('anim_default.apng'));
      expect(image.frames, hasLength(3), reason: 'the three after it');
      expect(image.frames.first.bitmap.pixel(0, 0), 0, reason: 'not red');
      expect(decodePng(fixture('anim_default.apng')).pixel(0, 0), 0xFFFF0000);
    });
  });

  group('composing', () {
    const red = 0xFFFF0000;
    const blue = 0xFF0000FF;

    test('dispose to the previous canvas restores what was before the '
        'frame', () {
      final image = decodeApng(
        apngBytes(3, 1, [
          F(0, 0, 3, 1, red),
          F(1, 0, 2, 1, blue, dispose: 2),
          F(0, 0, 1, 1, 0xFF00FF00),
        ]),
      );
      expect(
        [for (final f in image.frames) argb(f.bitmap)],
        [
          [red, red, red],
          [red, blue, blue],
          [0xFF00FF00, red, red],
        ],
      );
    });

    test('a first frame that disposes to the previous canvas does as to the '
        'background', () {
      final image = decodeApng(
        apngBytes(2, 1, [
          F(0, 0, 2, 1, red, dispose: 2),
          F(0, 0, 1, 1, blue),
        ]),
      );
      expect(argb(image.frames.last.bitmap), [blue, 0]);
    });

    test('blend over mixes by alpha, source replaces', () {
      List<int> second(int blend) => argb(
        decodeApng(
          apngBytes(1, 1, [
            F(0, 0, 1, 1, red),
            F(0, 0, 1, 1, 0x800000FF, blend: blend),
          ]),
        ).frames.last.bitmap,
      );
      // blue at 128/255 over opaque red: opaque, half way
      expect(second(1), [0xFF7F0080]);
      expect(second(0), [0x800000FF]);
    });

    test('a delay of a fraction of a second, none for the 1/100 default', () {
      final image = decodeApng(
        apngBytes(1, 1, [
          F(0, 0, 1, 1, red, den: 4),
          F(0, 0, 1, 1, red, den: 0),
          F(0, 0, 1, 1, red, num: 0, den: 1),
        ]),
      );
      expect(
        [for (final f in image.frames) f.delay.inMilliseconds],
        [
          250,
          100,
          100,
        ],
      );
    });
  });

  group('decodePng and decodeAnimation', () {
    test('decodePng reads the default image of an APNG', () {
      final apng = fixture('anim_over.apng');
      final first = decodePng(apng);
      expect(first.pixel(0, 0), 0xFFFF0000);
      expect(decodeImage(apng).pixels, first.pixels);
    });

    test('a PNG without acTL is one frame, the image decodePng reads', () {
      final png = fixture('rgba8.png');
      final image = decodeApng(png);
      expect(image.frames, hasLength(1));
      expect(image.isAnimated, isFalse);
      expect(image.frames.single.bitmap.pixels, decodePng(png).pixels);
    });

    test('decodeAnimation reads an APNG as decodeApng does', () {
      final image = decodeAnimation(fixture('anim_background.apng'));
      expect(image.isAnimated, isTrue);
      expect(image.frames, hasLength(4));
    });
  });

  group('a damaged APNG', () {
    test('a canvas past what an animation may have is refused', () {
      expect(
        () => decodeApng(apngBytes(4096, 4096, [F(0, 0, 1, 1, 0xFFFF0000)])),
        throwsFormatException,
      );
    });

    test('fails the CRC of a chunk like a PNG', () {
      final bytes = Uint8List.fromList(fixture('anim_over.apng'));
      bytes[bytes.length - 20] ^= 0xFF;
      expect(() => decodeApng(bytes), throwsFormatException);
    });

    test('a frame outside its canvas is refused', () {
      // the fcTL's x offset past the canvas, its CRC made again
      final bytes = Uint8List.fromList(fixture('anim_over.apng'));
      final at = _find(bytes, 'fcTL') + 4;
      ByteData.sublistView(bytes).setUint32(at + 4 + 12, 100);
      _crc(bytes, at - 4);
      expect(() => decodeApng(bytes), throwsFormatException);
    });
  });
}

int _find(Uint8List bytes, String type) {
  final codes = type.codeUnits;
  outer:
  for (var i = 4; i < bytes.length - 4; i++) {
    for (var j = 0; j < 4; j++) {
      if (bytes[i + j] != codes[j]) {
        continue outer;
      }
    }
    return i - 4;
  }
  throw StateError('no $type');
}

/// Writes the CRC of the chunk at [at] (its length field) again.
void _crc(Uint8List bytes, int at) {
  final data = ByteData.sublistView(bytes);
  final length = data.getUint32(at);
  var crc = 0xFFFFFFFF;
  for (var i = at + 4; i < at + 8 + length; i++) {
    crc ^= bytes[i];
    for (var k = 0; k < 8; k++) {
      crc = crc & 1 != 0 ? 0xEDB88320 ^ crc >>> 1 : crc >>> 1;
    }
  }
  data.setUint32(at + 8 + length, crc ^ 0xFFFFFFFF);
}
