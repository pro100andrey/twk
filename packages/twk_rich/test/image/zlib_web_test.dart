// The zlib of the web (lib/src/image/zlib_web.dart), run on the VM against
// dart:io's: what dart:io deflates at every level it inflates, and what it
// deflates dart:io inflates; and both inflating no further than a bound.
import 'dart:io' show ZLibDecoder, ZLibEncoder;
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_rich/src/image/zlib_io.dart' as io;
import 'package:twk_rich/src/image/zlib_web.dart';

/// Kinds of data: none, a byte, text that repeats, noise, and runs long
/// enough for distances far back.
Map<String, Uint8List> samples() {
  final random = Random(7);
  return {
    'nothing': Uint8List(0),
    'a byte': Uint8List.fromList([42]),
    'text': Uint8List.fromList(
      List.generate(
        5000,
        (i) => 'the gallery, page by page. '.codeUnitAt(i % 27),
      ),
    ),
    'noise': Uint8List.fromList(
      List.generate(70000, (_) => random.nextInt(256)),
    ),
    'runs': Uint8List.fromList(
      List.generate(200000, (i) => (i ~/ 3000) % 7 == 0 ? i & 0xFF : 7),
    ),
  };
}

void main() {
  for (final MapEntry(key: name, value: data) in samples().entries) {
    test('inflates $name as dart:io deflated it, at every level', () {
      for (final level in [0, 1, 6, 9]) {
        final deflated = ZLibEncoder(level: level).convert(data);
        expect(zlibInflate(deflated), data, reason: 'level $level');
      }
    });

    test('deflates $name into what dart:io inflates', () {
      final deflated = zlibDeflate(data);
      expect(ZLibDecoder().convert(deflated), data);
      expect(zlibInflate(deflated), data);
    });
  }

  test('fails on what is not a zlib stream, or one cut or wrong', () {
    final good = ZLibEncoder().convert(samples()['text']!);
    expect(() => zlibInflate([1, 2, 3]), throwsFormatException);
    expect(
      () => zlibInflate([0x78, 0x9C, ...List.filled(8, 0)]),
      throwsFormatException,
    );
    expect(
      () => zlibInflate(good.sublist(0, good.length ~/ 2)),
      throwsFormatException,
    );
    final wrong = Uint8List.fromList(good);
    wrong[wrong.length - 1] ^= 1;
    expect(() => zlibInflate(wrong), throwsFormatException);
  });

  test('inflates up to the limit given, and fails past it', () {
    for (final (name, inflate) in [
      ('web', zlibInflate),
      ('dart:io', io.zlibInflate),
    ]) {
      for (final MapEntry(key: sample, value: data) in samples().entries) {
        final deflated = ZLibEncoder().convert(data);
        expect(
          inflate(deflated, limit: data.length),
          data,
          reason: '$name, $sample',
        );
        if (data.isNotEmpty) {
          expect(
            () => inflate(deflated, limit: data.length - 1),
            throwsFormatException,
            reason: '$name, $sample',
          );
        }
      }
    }
  });
}
