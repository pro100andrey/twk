import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:twk_core/src/canvas.dart';
import 'package:twk_core/src/style.dart';
import 'package:twk_core/src/surface.dart';
import 'package:twk_core/src/unicode/unicode.dart';

import 'support/harness.dart' show samples;

void main() {
  group(
    'UAX #29 conformance (GraphemeBreakTest.txt, Unicode $unicodeVersion)',
    () {
      final lines = File('test/data/GraphemeBreakTest.txt').readAsLinesSync();
      var cases = 0;
      for (final (n, raw) in lines.indexed) {
        final line = raw.split('#').first.trim();
        if (line.isEmpty) {
          continue;
        }
        cases++;
        test('line ${n + 1}', () {
          final tokens = line.split(RegExp(r'\s+'));
          final units = <int>[];
          final expected = <int>[];
          for (final t in tokens) {
            if (t == '÷') {
              expected.add(units.length);
            } else if (t != '×') {
              final cp = int.parse(t, radix: 16);
              if (cp > 0xFFFF) {
                final v = cp - 0x10000;
                units
                  ..add(0xD800 + (v >> 10))
                  ..add(0xDC00 + (v & 0x3FF));
              } else {
                units.add(cp);
              }
            }
          }
          final s = String.fromCharCodes(units);
          final actual = <int>[
            0,
            for (final (_, end) in graphemeBoundaries(s)) end,
          ];
          expect(actual, expected, reason: raw);
        });
      }
      test('has cases', () => expect(cases, greaterThan(500)));
    },
  );

  group('widths (grapheme mode)', () {
    int w(String s) => stringWidth(s);
    test('ascii / latin / cyrillic', () {
      expect(w('hello'), 5);
      expect(w('мир'), 3);
      expect(w('e\u{301}'), 1, reason: 'combining acute');
    });
    test('cjk / hangul', () {
      expect(w('你好'), 4);
      expect(w('\u{1100}\u{1161}\u{11A8}'), 2, reason: 'conjoining jamo L V T');
      expect(w('한'), 2);
    });
    test('emoji', () {
      expect(w('🧪'), 2);
      expect(w('❤'), 1);
      expect(w('❤\u{FE0F}'), 2, reason: 'VS16 requests emoji presentation');
      expect(w('👨\u{200D}👩\u{200D}👧'), 2, reason: 'ZWJ family is one cell');
      expect(w('🇺🇦'), 2, reason: 'flag');
      expect(w('👍🏽'), 2, reason: 'skin tone modifier');
    });
    test('lone surrogates never join and draw nothing', () {
      expect(graphemeBoundaries('\u{D83D}\u{1F3FD}').toList(), [
        (0, 1),
        (1, 3),
      ]);
      expect(graphemeBoundaries('a\u{DC4D}\u{301}').toList(), [
        (0, 1),
        (1, 2),
        (2, 3),
      ]);
      expect(stringWidth('\u{D83D}'), 0);
      expect(stringWidth('x\u{D83D}', mode: TextMode.legacy), 1);
    });
    test('controls and lone marks draw nothing', () {
      expect(w('\x1b'), 0);
      expect(w('\u{301}'), 0);
      expect(w('\uD800'), 0, reason: 'lone surrogate');
    });
    test('ambiguous', () {
      expect(stringWidth('±'), 1);
      expect(stringWidth('±', ambiguousWidth: 2), 2);
      expect(stringWidth('±'), 1, reason: 'no call keeps the last width');
      expect(() => stringWidth('±', ambiguousWidth: 3), throwsA(anything));
    });
    test('ASCII: a printable character and a tab a column, controls none', () {
      for (final mode in TextMode.values) {
        for (var c = 0; c < 0x80; c++) {
          final printable = (c >= 0x20 && c < 0x7F) || c == 0x09;
          expect(
            stringWidth('a${String.fromCharCode(c)}b', mode: mode),
            printable ? 3 : 2,
            reason: '$mode U+${c.toRadixString(16)}',
          );
        }
        expect(stringWidth('\r\n', mode: mode), 0);
      }
      // ASCII before a mark that joins it, and the mode of each call
      expect(stringWidth('ab́'), 2);
      expect(stringWidth('a7️'), 3, reason: 'an emoji presentation');
      expect(stringWidth('a7️⃣'), 3, reason: 'a keycap');
      expect(stringWidth('a7️', mode: TextMode.legacy), 2);
      expect(stringWidth('́x'), 1);
      expect(stringWidth('́x', mode: TextMode.legacy), 1);
      expect(stringWidth('aः'), 1);
      expect(stringWidth('aः', mode: TextMode.legacy), 2);
      expect(stringWidth('aः'), 1, reason: 'no call keeps the last mode');
    });
  });

  group('widths (legacy wcwidth mode)', () {
    int w(String s) => stringWidth(s, mode: TextMode.legacy);
    test('zwj sequence splits into separate cells', () {
      expect(w('👨\u{200D}👩'), 4);
      expect(w('❤\u{FE0F}'), 1);
      expect(w('e\u{301}'), 1);
    });
  });

  group('uncertainty flag', () {
    final seg = TextSegmenter();
    final scan = ClusterScan();
    bool unc(String s) {
      seg.scan(s, 0, scan);
      return scan.uncertain;
    }

    test('plain text is certain', () {
      expect(unc('a'), isFalse);
      expect(unc('я'), isFalse);
      expect(unc('你'), isFalse);
      expect(unc('e\u{301}'), isFalse);
      expect(unc('─'), isFalse);
    });
    test('emoji / ambiguous / sequences are uncertain', () {
      expect(unc('🧪'), isTrue);
      expect(unc('❤\u{FE0F}'), isTrue);
      expect(unc('🇺🇦'), isTrue);
    });
    test('ambiguous width is configuration, not uncertainty', () {
      expect(unc('±'), isFalse);
      expect(unc('─'), isFalse);
    });
  });

  test('stringWidth is the width Canvas.text draws', () {
    final rnd = Random(7);
    const extra = [
      '\t',
      '\u0903',
      '\u{1F3FD}',
      '\uFF9E',
      '\u0301',
      'a',
      '\x01',
    ];
    for (final mode in TextMode.values) {
      final styles = StyleTable();
      final pen = styles.pen(const Pen());
      final canvas = Canvas(
        Surface(400, 1),
        styles,
        GlyphTable(),
        segmenter: TextSegmenter(mode: mode),
      );
      for (var t = 0; t < 3000; t++) {
        final s = [
          for (var k = rnd.nextInt(6); k > 0; k--)
            if (rnd.nextBool())
              samples[rnd.nextInt(samples.length)]
            else
              extra[rnd.nextInt(extra.length)],
        ].join();
        expect(
          stringWidth(s, mode: mode),
          canvas.text(0, 0, s, pen),
          reason: '${mode.name} ${jsonEncode(s)}',
        );
      }
    }
  });
}
