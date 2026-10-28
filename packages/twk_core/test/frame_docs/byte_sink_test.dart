import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/src/byte_sink.dart';

void main() {
  String written(ByteSink sink) => latin1.decode(sink.view);

  test('a negative number is refused, not written', () {
    final sink = ByteSink()..ascii('x');
    expect(() => sink.decimal(-1), throwsRangeError);
    expect(written(sink), 'x');
  });

  test('decimalDigits is the length decimal writes', () {
    for (final v in [
      0, 9, 10, 99, 100, 999, 1000, 9999, 10000, 99999, 100000, //
      123456789, 1 << 40,
    ]) {
      final sink = ByteSink()..decimal(v);
      expect(written(sink), '$v');
      expect(decimalDigits(v), '$v'.length, reason: '$v');
    }
  });

  test('a code point is written as its UTF-8 bytes', () {
    for (final cp in [0x41, 0xE9, 0x20AC, 0x1F600]) {
      final sink = ByteSink(0)..codePoint(cp);
      expect(sink.view, utf8.encode(String.fromCharCode(cp)), reason: '$cp');
      final reserved = ByteSink(0)
        ..reserve(4)
        ..codePointReserved(cp);
      expect(reserved.view, sink.view, reason: '$cp reserved');
    }
  });

  test('csi writes ESC [, the number and the final byte', () {
    final sink = ByteSink()..csi(12, 0x48);
    expect(written(sink), '\x1b[12H');
  });

  test('removePrefix drops the first bytes and keeps the rest', () {
    final sink = ByteSink()
      ..ascii('abcdef')
      ..removePrefix(2);
    expect(written(sink), 'cdef');
    expect(sink.length, 4);
  });

  test('takeCopy keeps its bytes when the sink is written again', () {
    final sink = ByteSink()..ascii('one');
    final copy = sink.takeCopy();
    sink
      ..reset()
      ..ascii('two');
    expect(latin1.decode(copy), 'one');
    expect(written(sink), 'two');
  });
}
