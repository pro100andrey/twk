// Output added in pieces: it parses as it would whole, whatever a piece
// cuts, and the lines ended before a piece arrives are the same objects
// after it.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/twk.dart';

/// Output with every kind of sequence, character and control the stream
/// keeps state for while a piece is cut off.
const output =
    '\x1B[1;38:2::255:128:0mbold orange\x1B[m 漢字 e\u0301 😀\r\n'
    '\x1B]8;id=1;https://x.dev\x1B\\link\x1B]8;;\x07 '
    '\x1B]0;title\x07\x1BP+q544e\x1B\\\u009B4:3m\u009Bmplain\n'
    '10%\r\x1B[32m50%\x1B[K\r100%\x1B[0m\ta\bb\n'
    '\x1B[48;5;17m\x1B_Gf=100;AAAA\x1B\\last';

void main() {
  final whole = parseAnsi(output);

  test('the output parses to what is expected', () {
    expect(whole, [
      [
        const Span(
          'bold orange',
          Style(fg: Color.rgb(255, 128, 0), attrs: Attr.bold),
        ),
        const Span(' 漢字 e\u0301 😀'),
      ],
      [
        const Span('link', Style(link: 'https://x.dev')),
        const Span(' plain'),
      ],
      [
        const Span('100%', Style(fg: Color.green)),
        const Span('    b'),
      ],
      [const Span('last', Style(bg: Color.indexed(17)))],
    ]);
  });

  test('text cut anywhere parses as it does whole', () {
    for (var k = 0; k <= output.length; k++) {
      final stream = AnsiStream()
        ..add(output.substring(0, k))
        ..add(output.substring(k))
        ..close();
      expect(stream.lines, whole, reason: 'cut at $k');
    }
  });

  test('text a code unit at a time parses as it does whole', () {
    final stream = AnsiStream();
    for (var k = 0; k < output.length; k++) {
      stream.add(output[k]);
    }
    stream.close();
    expect(stream.lines, whole);
  });

  test('bytes cut anywhere parse as the text does whole', () {
    final bytes = utf8.encode(output);
    for (var k = 0; k <= bytes.length; k++) {
      final stream = AnsiStream()
        ..addBytes(bytes.sublist(0, k))
        ..addBytes(bytes.sublist(k))
        ..close();
      expect(stream.lines, whole, reason: 'cut at $k');
    }
  });

  test('bytes a byte at a time parse as the text does whole', () {
    final stream = AnsiStream();
    for (final byte in utf8.encode(output)) {
      stream.addBytes([byte]);
    }
    stream.close();
    expect(stream.lines, whole);
  });

  test('bytes that are not UTF-8 are U+FFFD', () {
    final stream = AnsiStream()
      ..addBytes([0x61, 0xFF, 0x62, 0xE6, 0xBC])
      ..close();
    expect(stream.lines, [
      [const Span('a\uFFFDb\uFFFD')],
    ]);
  });

  test('a surrogate pair cut in two is one character', () {
    final stream = AnsiStream()
      ..add('\uD83D')
      ..add('\uDE00\tx');
    expect(stream.lines, [
      [const Span('😀      x')],
    ]);
  });

  test('a surrogate left alone at the end is U+FFFD', () {
    final stream = AnsiStream()
      ..add('a\uD83D')
      ..close();
    expect(stream.lines, [
      [const Span('a\uFFFD')],
    ]);
  });

  group('while it streams in', () {
    test('the line being written is the last of the lines', () {
      final stream = AnsiStream()..add('one\ntw');
      expect(stream.lines, [
        [const Span('one')],
        [const Span('tw')],
      ]);
      expect(stream.settled, 1);
      stream.add('o\r\x1B[31mTWO');
      expect(stream.lines.last, [const Span('TWO', Style(fg: Color.red))]);
      expect(stream.settled, 1);
    });

    test('an ended line is the same object when more arrives', () {
      final stream = AnsiStream()..add('one\ntwo');
      final first = stream.lines.first;
      stream.add('\nthree\n');
      expect(stream.lines.first, same(first));
      expect(stream.settled, 3);
    });

    test('a sequence not yet ended shows nothing of itself', () {
      final stream = AnsiStream()..add('a\x1B[3');
      expect(stream.lines, [
        [const Span('a')],
      ]);
      stream.add('1mb');
      expect(stream.lines, [
        [const Span('a'), const Span('b', Style(fg: Color.red))],
      ]);
    });

    test('closing ends the last line and drops a sequence not ended', () {
      final stream = AnsiStream()..add('a\nb\x1B]8;;u');
      expect(stream.settled, 1);
      stream.close();
      expect(stream.settled, 2);
      expect(stream.lines, [
        [const Span('a')],
        [const Span('b')],
      ]);
    });

    test('nothing is added once closed', () {
      final stream = AnsiStream()..close();
      expect(() => stream.add('a'), throwsStateError);
      expect(() => stream.addBytes([0x61]), throwsStateError);
    });
  });
}
