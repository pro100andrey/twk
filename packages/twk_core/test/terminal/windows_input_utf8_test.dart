// WindowsInput's UTF-16 to UTF-8 (utf8OfUnits), on every platform: the
// bytes dart:convert gives for the same units, pairs and lone surrogates
// alike.
import 'dart:convert';
import 'dart:math';

import 'package:test/test.dart';
import 'package:twk_core/src/terminal/windows_input.dart';

List<int> _dartConvert(List<int> units) =>
    utf8.encode(String.fromCharCodes(units));

void main() {
  test('ASCII, two-, three- and four-byte characters', () {
    for (final text in ['', 'abc', 'é', '日本', '😀', 'a😀b日é\u{10FFFF}']) {
      expect(utf8OfUnits(text.codeUnits), utf8.encode(text), reason: text);
    }
  });

  test('a surrogate without its other half is U+FFFD', () {
    for (final units in [
      [0xD800],
      [0xDC00],
      [0x61, 0xD83D],
      [0xDE00, 0xD83D],
      [0xD83D, 0x61, 0xDE00],
      [0xDBFF, 0xDBFF, 0xDFFF],
    ]) {
      expect(utf8OfUnits(units), _dartConvert(units), reason: '$units');
    }
  });

  test('any units, as dart:convert encodes them', () {
    final random = Random(7);
    // the edges of each encoding's range, the surrogates among them
    const picks = [
      0x00, 0x7F, 0x80, 0x7FF, 0x800, 0xD7FF, 0xD800, 0xDBFF, 0xDC00, //
      0xDFFF, 0xE000, 0xFFFD, 0xFFFF,
    ];
    for (var round = 0; round < 2000; round++) {
      final units = [
        for (var i = random.nextInt(40); i > 0; i--)
          if (random.nextBool())
            picks[random.nextInt(picks.length)]
          else
            random.nextInt(0x10000),
      ];
      expect(utf8OfUnits(units), _dartConvert(units), reason: '$units');
    }
  });
}
