// Sequences and controls other than SGR, OSC 8 and those that write a line
// leave nothing in the text: none of them can reach the screen the spans
// are drawn on. stripAnsi takes the same sequences out and keeps the rest
// of the text as it is, controls and all.
import 'dart:convert';
import 'dart:math';

import 'package:test/test.dart';
import 'package:twk/twk.dart';

/// The text of the lines of [text], one string per line.
List<String> plain(String text) => [
  for (final line in parseAnsi(text)) line.map((span) => span.text).join(),
];

/// Whether [s] has a C0 or C1 control or DEL.
bool hasControl(String s) => s.codeUnits.any(
  (c) => c < 0x20 || c == 0x7F || (c >= 0x80 && c < 0xA0),
);

void main() {
  final sequences = <(String, String)>[
    (
      'cursor moves',
      '\x1B[2J\x1B[H\x1B[3;4Ha\x1B[A\x1B[2B\x1B[5C\x1B[Db\x1B[10G',
    ),
    ('cursor saves', '\x1B[sa\x1B[u\x1B7b\x1B8'),
    ('erase in display', 'a\x1B[J\x1B[1J\x1B[2J\x1B[3Jb'),
    ('scrolling', 'a\x1B[5S\x1B[2T\x1B[1;5rb\x1BM\x1BD\x1BE'),
    ('insert and delete', 'a\x1B[3@\x1B[2P\x1B[4L\x1B[M\x1B[9Xb'),
    ('private modes', '\x1B[?1049h\x1B[?25la\x1B[?1000;1006h\x1B[?2004lb'),
    ('queries', 'a\x1B[6n\x1B[c\x1B[>c\x1B[?u\x1B[?2026\$pb'),
    ('kitty keyboard', 'a\x1B[>1u\x1B[<ub'),
    ('cursor shape', 'a\x1B[2 qb'),
    ('ESC sequences', '\x1B(Ba\x1B)0\x1B#8\x1Bc\x1B=\x1B>b'),
    ('window title', '\x1B]0;title\x07a\x1B]2;title\x1B\\b'),
    ('clipboard', 'a\x1B]52;c;cm0gLXJmIH4=\x07b'),
    ('palette', 'a\x1B]4;1;rgb:ff/00/00\x1B\\\x1B]104\x07b'),
    ('DCS', 'a\x1BP+q544e\x1B\\\x1BP\$qm\x1B\\b'),
    ('APC', 'a\x1B_Gf=100,a=T;AAAA\x1B\\b'),
    ('PM and SOS', 'a\x1B^private\x1B\\\x1BXstring\x1B\\b'),
    ('8-bit CSI', 'a\u009B2J\u009B?1049hb'),
    ('8-bit OSC', 'a\u009D0;title\u009Cb'),
    (
      '8-bit DCS, SOS, PM and APC',
      'a\u0090q\u009C\u0098s\u009C\u009Ep\u009C\u009Fa\u009Cb',
    ),
    ('other C1 controls', 'a\u0084\u0085\u0088\u008D\u0096b'),
    ('ST alone', 'a\x1B\\\u009Cb'),
    ('CAN ends a sequence', 'a\x1B[31\x18b'),
    ('SUB ends a sequence', 'a\x1B]0;title\x1Ab'),
    ('a sequence ended by CAN in a string', 'a\x1BPq\x18b'),
    ('ESC in a sequence starts another', 'a\x1B[3\x1B[mb'),
    ('ESC twice', 'a\x1B\x1B[mb'),
    ('DEL inside a sequence', 'a\x1B[3\x7F1mb'),
  ];
  final controls = <(String, String)>[
    ('C0 controls', 'a\x00\x01\x07\x0E\x0F\x10\x1C\x1Fb'),
    ('DEL', 'a\x7Fb'),
  ];
  for (final (name, text) in [...sequences, ...controls]) {
    test('$name leave the text alone', () => expect(plain(text), ['ab']));
  }

  test('ESC before a character other than ASCII leaves the character', () {
    expect(plain('\x1Bé'), ['é']);
  });

  test('a character ending an escape sequence is not text', () {
    expect(plain('a\x1Bxb'), ['ab']);
    expect(plain('a\x1B(xb'), ['ab']);
  });

  test('controls inside a sequence act', () {
    expect(parseAnsi('\x1B[3\n1mx'), [
      <Span>[],
      [const Span('x', Style(fg: Color.red))],
    ]);
  });

  test('a sequence that is not ended swallows the rest', () {
    expect(plain('a\x1B]0;never ended\nb'), ['a']);
    expect(plain('a\x1BPnever ended\x07\nb'), ['a']);
    expect(plain('a\x1B[1;2'), ['a']);
    expect(plain('a\x1B'), ['a']);
  });

  test('an overlong OSC is dropped', () {
    final url = 'x' * 100000;
    expect(parseAnsi('\x1B]8;;$url\x07y'), [
      [const Span('y')],
    ]);
  });

  test('a CSI with too many parameters is dropped', () {
    expect(parseAnsi('\x1B[${'1;' * 10000}31mx'), [
      [const Span('x')],
    ]);
  });

  test('random bytes leave no control in the text or a link', () {
    const alphabet = [
      0x1B, 0x1B, 0x1B, 0x5B, 0x5B, 0x5D, 0x50, 0x5F, 0x5E, 0x58, 0x5C, //
      0x3B, 0x3A, 0x3F, 0x3E, 0x38, 0x32, 0x35, 0x31, 0x30, 0x34, 0x6D, //
      0x48, 0x4A, 0x4B, 0x68, 0x6C, 0x07, 0x18, 0x1A, 0x0D, 0x0A, 0x08, //
      0x09, 0x00, 0x7F, 0x61, 0x20, 0xC2, 0x9B, 0x9D, 0x9C, 0x90, 0xE6, //
      0xBC, 0xA2, 0xCC, 0x81, 0xF0, 0x9F, 0x98, 0x80, 0xFF, 0x80, 0x24, //
    ];
    for (var seed = 0; seed < 200; seed++) {
      final random = Random(seed);
      final bytes = [
        for (var k = 0; k < 400; k++) alphabet[random.nextInt(alphabet.length)],
      ];
      final stream = AnsiStream()
        ..addBytes(bytes)
        ..close();
      for (final line in stream.lines) {
        for (final span in line) {
          expect(hasControl(span.text), isFalse, reason: 'seed $seed');
          expect(span.text, isNotEmpty, reason: 'seed $seed');
          final link = span.style.link;
          if (link != null) {
            expect(hasControl(link), isFalse, reason: 'seed $seed');
          }
        }
      }
    }
  });

  group('stripAnsi', () {
    for (final (name, text) in sequences) {
      test('$name leave the text alone', () {
        expect(stripAnsi(text), 'ab');
      });
    }
    for (final (name, text) in controls) {
      test('keeps $name', () => expect(stripAnsi(text), text));
    }

    test('keeps tabs, line breaks, carriage returns, backspaces and wide '
        'characters as they are', () {
      const text = 'a\tb\r\nc\rd\x08e\x0C日本語 🙂 e\u0301\n';
      expect(stripAnsi('\x1B[1;31m$text\x1B[m'), text);
    });

    test('keeps the controls within an escape or a CSI', () {
      expect(stripAnsi('a\x1B[3\n1mb'), 'a\nb');
      expect(stripAnsi('a\x1B(\tBb'), 'a\tb');
    });

    test('keeps a character other than ASCII after ESC', () {
      expect(stripAnsi('a\x1Bé'), 'aé');
    });

    test('takes out the character that ends an escape sequence', () {
      expect(stripAnsi('a\x1Bxb'), 'ab');
      expect(stripAnsi('a\x1B(xb'), 'ab');
    });

    test('takes out the rest after a sequence that is not ended', () {
      expect(stripAnsi('a\x1B]0;never ended\nb'), 'a');
      expect(stripAnsi('a\x1BPnever ended\x07\nb'), 'a');
      expect(stripAnsi('a\x1B[1;2'), 'a');
      expect(stripAnsi('a\x1B'), 'a');
    });

    test('takes out an overlong OSC and a CSI with too many parameters', () {
      expect(stripAnsi('a\x1B]8;;${'x' * 100000}\x07b'), 'ab');
      expect(stripAnsi('a\x1B[${'1;' * 10000}31mb'), 'ab');
    });

    test('of random text only takes characters out, leaving no ESC or C1 '
        'control, and leaves text without them as it is', () {
      const alphabet = [
        0x1B, 0x1B, 0x1B, 0x5B, 0x5B, 0x5D, 0x50, 0x5F, 0x5E, 0x58, 0x5C, //
        0x3B, 0x3A, 0x3F, 0x3E, 0x38, 0x32, 0x35, 0x31, 0x30, 0x34, 0x6D, //
        0x48, 0x4A, 0x4B, 0x68, 0x6C, 0x07, 0x18, 0x1A, 0x0D, 0x0A, 0x08, //
        0x09, 0x00, 0x7F, 0x61, 0x20, 0xC2, 0x9B, 0x9D, 0x9C, 0x90, 0xE6, //
        0xBC, 0xA2, 0xCC, 0x81, 0xF0, 0x9F, 0x98, 0x80, 0xFF, 0x80, 0x24, //
      ];
      const decoder = Utf8Decoder(allowMalformed: true);
      for (var seed = 0; seed < 200; seed++) {
        final random = Random(seed);
        final text = decoder.convert([
          for (var k = 0; k < 400; k++)
            alphabet[random.nextInt(alphabet.length)],
        ]);
        final stripped = stripAnsi(text);
        expect(
          stripped.codeUnits.any((c) => c == 0x1B || (c >= 0x80 && c < 0xA0)),
          isFalse,
          reason: 'seed $seed',
        );
        var at = 0;
        for (final c in stripped.codeUnits) {
          at = text.codeUnits.indexOf(c, at) + 1;
          expect(at, isPositive, reason: 'seed $seed');
        }
        expect(stripAnsi(stripped), stripped, reason: 'seed $seed');
      }
    });
  });
}
