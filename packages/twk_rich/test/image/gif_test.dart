import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_rich/image.dart';

import 'fixtures.dart';
import 'gif_builder.dart';

const red = 0xFFFF0000;
const green = 0xFF00FF00;
const blue = 0xFF0000FF;
const white = 0xFFFFFFFF;
const clear = 0;

/// Red, green, blue and white as global colours.
const palette = [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255];

/// The pixels of [image] as `0xAARRGGBB`, row by row.
List<int> argb(Bitmap image) => [
  for (var y = 0; y < image.height; y++)
    for (var x = 0; x < image.width; x++) image.pixel(x, y),
];

/// The canvas of each frame of [bytes].
List<List<int>> canvases(Uint8List bytes) => [
  for (final f in decodeGif(bytes).frames) argb(f.bitmap),
];

void main() {
  group('decodeGif against Pillow', () {
    for (final name in ['anim_noise', 'anim_plain']) {
      test('$name: every frame, delay and play count', () {
        final expected = ByteData.sublistView(fixture('$name.frames'));
        final width = expected.getUint32(0, Endian.little);
        final height = expected.getUint32(4, Endian.little);
        final plays = expected.getUint32(8, Endian.little);
        final count = expected.getUint32(12, Endian.little);
        final image = decodeGif(fixture('$name.gif'));
        expect((image.width, image.height), (width, height));
        expect(image.frames, hasLength(count));
        expect(image.loops, plays);
        var at = 16;
        final bytes = fixture('$name.frames');
        for (final frame in image.frames) {
          final delay = expected.getUint32(at, Endian.little);
          at += 4;
          final size = width * height * 4;
          expect(frame.delay.inMilliseconds, delay);
          expect(frame.bitmap.pixels, bytes.sublist(at, at + size));
          at += size;
        }
      });
    }
  });

  group('decodeGif', () {
    test('frames of the screen size, with their delays; one play unless the '
        'file loops', () {
      final bytes = gifBytes(2, 2, palette, [
        GifImage(2, 2, [0, 0, 0, 0], delayCs: 5),
        GifImage(2, 2, [1, 1, 1, 1], delayCs: 25),
      ]);
      final image = decodeGif(bytes);
      expect((image.width, image.height, image.loops), (2, 2, 1));
      expect(image.isAnimated, isTrue);
      expect(
        [for (final f in image.frames) f.delay],
        [const Duration(milliseconds: 50), const Duration(milliseconds: 250)],
        reason: 'in centiseconds, 5 and 25',
      );
      expect(canvases(bytes), [
        [red, red, red, red],
        [green, green, green, green],
      ]);
    });

    test('a delay of 10 ms or less shows for 100 ms, as browsers show it', () {
      final bytes = gifBytes(1, 1, palette, [
        GifImage(1, 1, [0]),
        GifImage(1, 1, [1], delayCs: 1),
        GifImage(1, 1, [1], delayCs: 2),
      ]);
      expect(
        [for (final f in decodeGif(bytes).frames) f.delay.inMilliseconds],
        [
          100,
          100,
          20,
        ],
      );
    });

    test('NETSCAPE2.0 gives the repeats: none for ever, n one play and n '
        'more', () {
      List<int> plays(int? loop) => [
        decodeGif(
          gifBytes(1, 1, palette, [
            GifImage(1, 1, [0]),
          ], loop: loop),
        ).loops,
      ];
      expect(plays(null), [1]);
      expect(plays(0), [0]);
      expect(plays(2), [3]);
      expect(plays(300), [301]);
    });

    test('a frame at its place on the screen, over what was drawn', () {
      final bytes = gifBytes(3, 2, palette, [
        GifImage(3, 2, [3, 3, 3, 3, 3, 3]),
        GifImage(2, 1, [2, 2], left: 1, top: 1),
      ]);
      expect(canvases(bytes), [
        [white, white, white, white, white, white],
        [white, white, white, white, blue, blue],
      ]);
    });

    test('the screen starts transparent, and so is a pixel the frame has '
        'no colour for', () {
      final bytes = gifBytes(2, 1, palette, [
        GifImage(1, 1, [0]),
      ]);
      expect(canvases(bytes).single, [red, clear]);
    });

    test('the transparent index leaves what is under it', () {
      final bytes = gifBytes(2, 1, palette, [
        GifImage(2, 1, [0, 0]),
        GifImage(2, 1, [3, 2], transparent: 3),
      ]);
      expect(canvases(bytes), [
        [red, red],
        [red, blue],
      ]);
    });

    test('disposal 1 and 0 leave the frame', () {
      for (final disposal in [0, 1]) {
        final bytes = gifBytes(2, 1, palette, [
          GifImage(2, 1, [0, 0], disposal: disposal),
          GifImage(1, 1, [2], transparent: 3),
        ]);
        expect(canvases(bytes).last, [blue, red], reason: 'disposal $disposal');
      }
    });

    test('disposal 2 makes the frame transparent, and only its rectangle', () {
      final bytes = gifBytes(3, 1, palette, [
        GifImage(3, 1, [0, 0, 0]),
        GifImage(2, 1, [1, 1], left: 1, disposal: 2),
        GifImage(1, 1, [2], transparent: 3),
      ]);
      expect(canvases(bytes), [
        [red, red, red],
        [red, green, green],
        [blue, clear, clear],
      ]);
    });

    test('disposal 3 restores what the frame covered', () {
      final bytes = gifBytes(3, 1, palette, [
        GifImage(3, 1, [0, 0, 0]),
        GifImage(2, 1, [1, 1], left: 1, disposal: 3),
        GifImage(1, 1, [2]),
      ]);
      expect(canvases(bytes), [
        [red, red, red],
        [red, green, green],
        [blue, red, red],
      ]);
    });

    test('an interlaced frame is stored in the passes 0, 4, 2, 1 of 8, 4, 4 '
        'and 2', () {
      // row i of the picture has index i % 4 + ...: stored order is the
      // rows 0, 4, 2, 6, 1, 3, 5, 7
      final stored = [0, 0, 1, 1, 2, 2, 3, 3];
      final bytes = gifBytes(1, 8, palette, [
        GifImage(1, 8, stored, interlaced: true),
      ]);
      // file row k is picture row [0, 4, 2, 6, 1, 3, 5, 7][k]
      final rows = [0, 4, 2, 6, 1, 3, 5, 7];
      final expected = List.filled(8, 0);
      for (var k = 0; k < 8; k++) {
        expected[rows[k]] = [red, green, blue, white][stored[k]];
      }
      expect(canvases(bytes).single, expected);
    });

    test('a local colour table, for the frame alone', () {
      final bytes = gifBytes(2, 1, palette, [
        GifImage(1, 1, [0], localColors: [1, 2, 3, 4, 5, 6]),
        GifImage(1, 1, [0], left: 1),
      ]);
      expect(canvases(bytes).last, [0xFF010203, red]);
    });

    test('a GIF87a without extensions: one frame of no delay', () {
      final bytes = gifBytes(1, 1, palette, [
        GifImage(1, 1, [1]),
      ], header89: false);
      final image = decodeGif(bytes);
      expect(image.frames, hasLength(1));
      expect(image.isAnimated, isFalse);
      expect(argb(image.frames.single.bitmap), [green]);
    });

    test('a file cut short after a frame has the frames before the cut', () {
      final bytes = gifBytes(1, 1, palette, [
        GifImage(1, 1, [0]),
        GifImage(1, 1, [1]),
      ], trailer: false);
      expect(decodeGif(bytes).frames, hasLength(2), reason: 'no trailer');
      final first = gifBytes(1, 1, palette, [
        GifImage(1, 1, [0]),
      ]).length;
      final cut = Uint8List.sublistView(bytes, 0, first + 8);
      expect(decodeGif(cut).frames, hasLength(1));
    });

    test('a frame of invalid data after a first is refused when reached', () {
      final bytes = gifBytes(2, 1, palette, [
        GifImage(2, 1, [0, 0]),
        GifImage(2, 1, [0, 0]),
      ]);
      // the last frame's LZW data, up to its block's end and the trailer
      final bad = Uint8List.fromList(bytes)
        ..fillRange(bytes.length - 4, bytes.length - 2, 0xFF);
      final image = decodeGif(bad);
      expect(image.frameCount, 2, reason: 'not dropped');
      expect(argb(image.bitmapAt(0)), [red, red]);
      expect(() => image.bitmapAt(1), throwsFormatException);
      expect(() => image.bitmapAt(1), throwsFormatException, reason: 'again');
      expect(argb(image.bitmapAt(0)), [red, red], reason: 'the first still');
    });

    test('a frame past the screen is clipped to it', () {
      final bytes = gifBytes(2, 2, palette, [
        GifImage(2, 2, [0, 1, 2, 3], left: 1, top: 1),
      ]);
      expect(canvases(bytes), [
        [clear, clear, clear, red],
      ]);
    });

    test('a frame past the screen restores only what it covered', () {
      final bytes = gifBytes(2, 1, palette, [
        GifImage(2, 1, [2, 2]),
        GifImage(2, 1, [1, 1], left: 1, disposal: 3),
        GifImage(1, 1, [3]),
      ]);
      expect(canvases(bytes), [
        [blue, blue],
        [blue, green],
        [white, blue],
      ]);
    });

    test('a frame of more pixels than an animation may have is refused', () {
      expect(
        () => decodeGif(
          gifBytes(2, 2, palette, [
            GifImage(4000, 4000, [0], left: 1),
          ]),
        ),
        throwsFormatException,
      );
    });

    test('a screen past what an animation may have is refused', () {
      expect(
        () => decodeGif(
          gifBytes(4096, 4096, palette, [
            GifImage(1, 1, [0]),
          ]),
        ),
        throwsFormatException,
      );
      expect(
        () => decodeGif(
          gifBytes(16384, 16384, palette, [
            GifImage(1, 1, [0], disposal: 3),
          ]),
        ),
        throwsFormatException,
      );
    });

    test('an unknown block after frames ends the file, as it does in '
        'browsers', () {
      final bytes = gifBytes(2, 1, palette, [
        GifImage(2, 1, [0, 1]),
        GifImage(2, 1, [1, 0]),
      ], trailer: false);
      final withUnknown = Uint8List.fromList([...bytes, 0x99, 1, 2, 3]);
      expect(canvases(withUnknown), [
        [red, green],
        [green, red],
      ]);
      final first = Uint8List.fromList([
        ...gifBytes(2, 1, palette, [], trailer: false),
        0x99,
        1,
      ]);
      expect(() => decodeGif(first), throwsFormatException);
    });

    test('an LZW minimum code size past 8 is refused', () {
      final bytes = gifBytes(2, 1, palette, [
        GifImage(2, 1, [0, 0]),
      ]);
      for (final size in [9, 11]) {
        final bad = Uint8List.fromList(bytes)..[bytes.length - 6] = size;
        expect(() => decodeGif(bad), throwsFormatException, reason: '$size');
      }
    });

    test('what is no GIF, has no frame, or cuts its first, is refused', () {
      expect(() => decodeGif(Uint8List(0)), throwsFormatException);
      expect(
        () => decodeGif(Uint8List.fromList('GIF89a'.codeUnits)),
        throwsFormatException,
      );
      expect(
        () => decodeGif(gifBytes(1, 1, palette, [])),
        throwsFormatException,
        reason: 'no frame',
      );
      final bytes = gifBytes(2, 2, palette, [
        GifImage(2, 2, [0, 0, 0, 0]),
      ]);
      expect(
        () => decodeGif(Uint8List.sublistView(bytes, 0, bytes.length - 4)),
        throwsFormatException,
      );
    });

    test('an LZW stream of a code past its table is refused', () {
      final bytes = gifBytes(2, 1, palette, [
        GifImage(2, 1, [0, 0]),
      ]);
      // after the image descriptor (10 bytes) and the minimum code size and
      // block length: set every code bit
      final at = bytes.length - 1 - 1 - 3;
      final bad = Uint8List.fromList(bytes)..fillRange(at, at + 3, 0xFF);
      expect(() => decodeGif(bad), throwsFormatException);
    });
  });

  group('GIF in the image functions', () {
    final bytes = gifBytes(3, 2, palette, [
      GifImage(3, 2, [0, 1, 2, 3, 0, 1]),
      GifImage(3, 2, [1, 1, 1, 1, 1, 1]),
    ]);

    test('ImageFormat.of tells it, decodeImage reads its first frame', () {
      expect(ImageFormat.of(bytes), ImageFormat.gif);
      expect(isGif(bytes), isTrue);
      expect(argb(decodeImage(bytes)), [red, green, blue, white, red, green]);
    });

    test('imageSize reads the screen, without decoding', () {
      expect(imageSize(bytes), (width: 3, height: 2));
      expect(
        () => imageSize(Uint8List.sublistView(bytes, 0, 8)),
        throwsFormatException,
      );
    });

    test('decodeAnimation: the frames of a GIF, one frame for a still', () {
      expect(decodeAnimation(bytes).frames, hasLength(2));
      final still = decodeAnimation(fixture('rgb8.png'));
      expect(still.frames, hasLength(1));
      expect(still.isAnimated, isFalse);
      final jpeg = decodeAnimation(fixture('jpeg444.jpg'));
      expect(jpeg.frames, hasLength(1));
      expect(
        () => decodeAnimation(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    });
  });

  group('AnimatedImage composed as it is reached', () {
    /// Frames of 4 × 4 that draw, over each other, a growing square, now
    /// leaving it, now restoring the screen to what it was, now clearing it.
    final bytes = gifBytes(4, 4, palette, [
      for (var i = 0; i < 12; i++)
        GifImage(
          2,
          2,
          List.filled(4, i % 3),
          left: i % 3,
          top: i % 2,
          disposal: i % 4,
          transparent: i % 5 == 4 ? 3 : null,
          delayCs: 5,
        ),
    ]);

    test('any order of reaching them gives the canvases in order', () {
      final expected = canvases(bytes);
      final image = decodeGif(bytes, windowBytes: 3 * 4 * 4 * 4);
      // from the end, jumps forward and back, each frame again
      for (final i in [11, 3, 3, 7, 0, 5, 11, 10, 2, 9, 1, 8, 4, 6, 0]) {
        expect(argb(image.bitmapAt(i)), expected[i], reason: 'frame $i');
      }
    });

    test('a bitmap given is not drawn on by the frames after it', () {
      final image = decodeGif(bytes, windowBytes: 0);
      final first = argb(image.bitmapAt(0));
      image.bitmapAt(11);
      expect(argb(image.bitmapAt(0)), first);
    });

    test('only a window of the frames is kept, one at least', () {
      final composed = <int>[];
      var next = 0;
      AnimatedImage make(int windowBytes) => AnimatedImage.composed(
        width: 10,
        height: 10,
        delays: List.filled(20, const Duration(milliseconds: 10)),
        windowBytes: windowBytes,
        compose: () {
          composed.add(next++);
          return Bitmap(10, 10);
        },
        rewind: () => next = 0,
      );
      // a frame is 400 bytes
      final image = make(1000);
      for (var i = 0; i < 20; i++) {
        image.bitmapAt(i);
        expect(image.keptFrames, lessThanOrEqualTo(2));
      }
      expect(composed, List.generate(20, (i) => i), reason: 'each once');
      image
        ..bitmapAt(19)
        ..bitmapAt(18);
      expect(composed, hasLength(20), reason: 'the last two are kept');
      image.bitmapAt(0);
      expect(composed.length, 21, reason: 'composed again from the first');
      expect(make(0).keptFrames, 0);
      expect((make(0)..bitmapAt(5)).keptFrames, 1);
    });

    test('a long animation is not composed up front', () {
      final big = gifBytes(2, 2, palette, [
        for (var i = 0; i < 300; i++) GifImage(2, 2, List.filled(4, i % 4)),
      ]);
      final image = decodeGif(big);
      expect(image.frameCount, 300);
      expect(image.keptFrames, 1, reason: 'the first, which is checked');
      image.bitmapAt(100);
      expect(image.keptFrames, 101, reason: 'within the window');
    });
  });

  group('AnimatedImage', () {
    AnimatedImage image(int loops) => AnimatedImage([
      for (final ms in [100, 200, 300])
        ImageFrame(Bitmap(1, 1), Duration(milliseconds: ms)),
    ], loops: loops);

    test('the frame at a time: by the delays, the plays repeating', () {
      final a = image(0);
      expect(a.duration, const Duration(milliseconds: 600));
      int at(int ms) => a.indexAt(Duration(milliseconds: ms));
      expect(
        [at(0), at(99), at(100), at(299), at(300), at(599), at(600)],
        [
          0,
          0,
          1,
          1,
          2,
          2,
          0,
        ],
      );
      expect(at(6100), 1, reason: 'the tenth play');
      expect(a.indexAt(const Duration(milliseconds: -5)), 0);
    });

    test('after its plays the last frame stays', () {
      final a = image(2);
      expect(a.indexAt(const Duration(milliseconds: 1199)), 2);
      expect(a.indexAt(const Duration(milliseconds: 650)), 0);
      expect(a.indexAt(const Duration(milliseconds: 1200)), 2);
      expect(a.indexAt(const Duration(hours: 9)), 2);
    });

    test('when the next frame starts, none after the last play', () {
      Duration? next(AnimatedImage a, int ms) =>
          a.nextChangeAfter(Duration(milliseconds: ms));
      final forever = image(0);
      expect(next(forever, 0), const Duration(milliseconds: 100));
      expect(next(forever, 150), const Duration(milliseconds: 300));
      expect(next(forever, 599), const Duration(milliseconds: 600));
      expect(next(forever, 600), const Duration(milliseconds: 700));
      final twice = image(2);
      expect(next(twice, 450), const Duration(milliseconds: 600));
      expect(next(twice, 599), const Duration(milliseconds: 600));
      expect(next(twice, 800), const Duration(milliseconds: 900));
      expect(next(twice, 900), isNull);
      expect(next(twice, 1200), isNull);
      expect(next(twice, 1100), isNull, reason: 'in the last frame');
      expect(
        AnimatedImage([ImageFrame(Bitmap(1, 1), Duration.zero)])
            .nextChangeAfter(Duration.zero),
        isNull,
      );
    });
  });
}
