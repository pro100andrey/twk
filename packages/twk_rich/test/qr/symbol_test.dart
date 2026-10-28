// The QR encoder: the standard's worked example, every version and level
// under each mask as zint makes it, the mask the penalty rules choose, the
// characters each version holds as qrencode puts them in it, the modes,
// the versions chosen, and the tables and codes the symbols are built of.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_rich/src/qr/reed_solomon.dart';
import 'package:twk_rich/src/qr/symbol.dart';
import 'package:twk_rich/src/qr/tables.dart';

import 'cases.dart';

/// The lines of the fixture [name], without the comment that heads it.
List<List<String>> fixture(String name) => [
  for (final line in File('test/qr/fixtures/$name').readAsLinesSync())
    if (!line.startsWith('#')) line.split(' '),
];

/// [c]'s data as a symbol under [mask], or the one the rules choose.
QrSymbol symbolOf(QrCase c, {int? mask}) => c.mode == QrMode.byte
    ? QrSymbol.bytes(c.data, level: c.level, version: c.version, mask: mask)
    : QrSymbol.encode(
        String.fromCharCodes(c.data),
        level: c.level,
        version: c.version,
        mask: mask,
      );

String hashOf(QrSymbol symbol) => moduleHash(symbol.size, symbol.isDark);

void main() {
  group("the standard's worked example, 01234567 at 1-M", () {
    test('has its codewords', () {
      expect(
        qrCodewords(
          QrMode.numeric,
          '01234567'.codeUnits,
          QrErrorCorrection.medium,
          1,
        ),
        [
          // the data: mode, count, 012 345 67, terminator, pad codewords
          0x10, 0x20, 0x0C, 0x56, 0x61, 0x80, 0xEC, 0x11, //
          0xEC, 0x11, 0xEC, 0x11, 0xEC, 0x11, 0xEC, 0x11,
          // the error correction
          0xA5, 0x24, 0xD4, 0xC1, 0xED, 0x36, 0xC7, 0x87, 0x2C, 0x55,
        ],
      );
    });

    test('is the symbol zint makes of it, under the mask it chooses', () {
      final symbol = QrSymbol.encode('01234567');
      expect(symbol.version, 1);
      expect(symbol.level, QrErrorCorrection.medium);
      expect(symbol.mode, QrMode.numeric);
      expect(symbol.mask, 2);
      // zint -b QRCODE --dump --secure=2 -d 01234567
      const zint = [
        'FE 5B F8', '82 7A 08', 'BA 82 E8', 'BA C2 E8', 'BA BA E8', //
        '82 8A 08', 'FE AB F8', '00 98 00', 'BE 4B E0', '15 A9 60',
        '23 54 F8', '08 41 E0', '1F 94 80', '00 BE 60', 'FE 6B 00',
        '82 BE 28', 'BA 89 60', 'BA C9 00', 'BA B4 A0', '82 01 B0',
        'FE F4 A0',
      ];
      expect(
        [
          for (var y = 0; y < 21; y++)
            [
                  for (var x = 0; x < 24; x += 8)
                    [
                      for (var b = 0; b < 8; b++)
                        if (x + b < 21 && symbol.isDark(x + b, y)) 1 else 0,
                    ].fold(0, (byte, bit) => byte << 1 | bit),
                ]
                .map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0'))
                .join(' '),
        ],
        zint,
      );
    });
  });

  test('every version and level, under each mask, as zint makes it', () {
    final symbols = fixture('symbols.txt');
    final cases = qrCases();
    expect(symbols, hasLength(cases.length));
    for (var i = 0; i < cases.length; i++) {
      final c = cases[i];
      expect(symbols[i].first, '${c.version}-${c.levelLetter}');
      for (var mask = 0; mask < 8; mask++) {
        final symbol = symbolOf(c, mask: mask);
        expect(symbol.mask, mask);
        expect(symbol.mode, c.mode, reason: '$c');
        expect(hashOf(symbol), symbols[i][1 + mask], reason: '$c, mask $mask');
      }
    }
  });

  test('the mask the penalty rules score lowest is the one zint chooses', () {
    final symbols = fixture('symbols.txt');
    final cases = qrCases();
    for (var i = 0; i < cases.length; i++) {
      final symbol = symbolOf(cases[i]);
      expect('${symbol.mask}', symbols[i][9], reason: '${cases[i]}');
      expect(hashOf(symbol), symbols[i][1 + symbol.mask]);
    }
  });

  test('each version holds at each level the characters qrencode puts in '
      'it, in each mode', () {
    final capacity = fixture('capacity.txt');
    expect(capacity, hasLength(160));
    for (final [name, ...most] in capacity) {
      final [v, letter] = name.split('-');
      final version = int.parse(v);
      final level = QrErrorCorrection.values['LMQH'.indexOf(letter)];
      for (final mode in QrMode.values) {
        final count = int.parse(most[mode.index]);
        final reason = '$name ${mode.name}';
        expect(
          versionFor(mode, count, level, version),
          version,
          reason: reason,
        );
        expect(
          () => versionFor(mode, count + 1, level, version),
          throwsArgumentError,
          reason: reason,
        );
        if (version < 40) {
          expect(
            versionFor(mode, count + 1, level, null),
            version + 1,
            reason: reason,
          );
        }
      }
    }
    // the most of all, as the standard's Table 7 has them
    expect(capacity.last, ['40-H', '3057', '1852', '1273']);
    expect(capacity[156], ['40-L', '7089', '4296', '2953']);
  });

  group('the mode', () {
    test('of fewest bits that holds the text', () {
      expect(modeOf('0123456789'), QrMode.numeric);
      expect(modeOf(r'HELLO WORLD $%*+-./:09'), QrMode.alphanumeric);
      expect(modeOf('Hello'), QrMode.byte);
      expect(modeOf('ПРИВЕТ'), QrMode.byte);
      expect(modeOf(''), QrMode.byte);
      expect(QrSymbol.encode('12').mode, QrMode.numeric);
      expect(QrSymbol.encode('AB1').mode, QrMode.alphanumeric);
      expect(QrSymbol.encode('a').mode, QrMode.byte);
    });

    test('byte for text, as its UTF-8', () {
      const text = 'Grüße, мир, 世界';
      expect(
        hashOf(QrSymbol.encode(text, mask: 3)),
        hashOf(QrSymbol.bytes(utf8.encode(text), mask: 3)),
      );
      expect(
        hashOf(QrSymbol.encode('héllo', mask: 3)),
        isNot(hashOf(QrSymbol.bytes(latin1.encode('héllo'), mask: 3))),
      );
    });

    test('takes the bits the standard counts', () {
      expect(QrMode.numeric.dataBits(8), 27);
      expect(QrMode.numeric.dataBits(7), 24);
      expect(QrMode.numeric.dataBits(6), 20);
      expect(QrMode.alphanumeric.dataBits(5), 28);
      expect(QrMode.byte.dataBits(5), 40);
      expect(
        [
          for (final v in [9, 10, 26, 27]) QrMode.numeric.countBits(v),
        ],
        [
          10,
          12,
          12,
          14,
        ],
      );
      expect(QrMode.alphanumeric.countBits(1), 9);
      expect(QrMode.byte.countBits(40), 16);
    });
  });

  group('the version', () {
    test('the smallest the data fits in at the level', () {
      expect(
        QrSymbol.encode('A' * 25, level: QrErrorCorrection.low).version,
        1,
      );
      expect(
        QrSymbol.encode('A' * 26, level: QrErrorCorrection.low).version,
        2,
      );
      expect(QrSymbol.encode('A' * 25).version, 2);
      expect(
        QrSymbol.encode('1' * 7089, level: QrErrorCorrection.low).version,
        40,
      );
      expect(QrSymbol.encode('').version, 1);
      final symbol = QrSymbol.encode('x', version: 7);
      expect(symbol.version, 7);
      expect(symbol.size, 45);
    });

    test('data too long for it is an error', () {
      expect(
        () => QrSymbol.encode('1' * 7090, level: QrErrorCorrection.low),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'numeric data of 7090 characters does not fit in a QR code of '
                'any version at the low level',
          ),
        ),
      );
      expect(() => QrSymbol.encode('A' * 26, version: 1), throwsArgumentError);
      expect(() => QrSymbol.encode('a', version: 0), throwsRangeError);
      expect(() => QrSymbol.encode('a', version: 41), throwsRangeError);
      expect(() => QrSymbol.encode('a', mask: 8), throwsRangeError);
      expect(() => QrSymbol.bytes([256]), throwsRangeError);
    });
  });

  test('a module out of the symbol is a RangeError', () {
    final symbol = QrSymbol.encode('a');
    expect(symbol.isDark(0, 0), isTrue);
    expect(() => symbol.isDark(21, 0), throwsRangeError);
    expect(() => symbol.isDark(0, -1), throwsRangeError);
  });

  test('its rows as text', () {
    final rows = '${QrSymbol.encode('01234567')}'.split('\n');
    expect(rows, hasLength(21));
    expect(rows.first, '#######..#.##.#######');
    expect(rows[6], '#######.#.#.#.#######');
    expect(rows[7], '........#..##........');
  });

  group('tables and codes', () {
    test('the remainder bits of each version are those of Table 1', () {
      int remainder(int v) => dataModules(v) - totalCodewords(v) * 8;
      expect(
        [for (var v = 1; v <= 40; v++) remainder(v)],
        [
          0, //
          for (var v = 2; v <= 6; v++) 7,
          for (var v = 7; v <= 13; v++) 0,
          for (var v = 14; v <= 20; v++) 3,
          for (var v = 21; v <= 27; v++) 4,
          for (var v = 28; v <= 34; v++) 3,
          for (var v = 35; v <= 40; v++) 0,
        ],
      );
      expect(totalCodewords(1), 26);
      expect(totalCodewords(40), 3706);
    });

    test('the alignment patterns are evenly spaced from the last back', () {
      for (var v = 2; v <= 40; v++) {
        final centers = alignmentCenters[v - 1];
        expect(centers, hasLength(v ~/ 7 + 2), reason: 'version $v');
        expect(centers.first, 6);
        expect(centers.last, 4 * v + 17 - 7);
        final step = centers.last - centers[centers.length - 2];
        for (var k = 2; k < centers.length; k++) {
          expect(centers[k] - centers[k - 1], step, reason: 'version $v');
        }
      }
    });

    test('the generator polynomial of 7 codewords is that of Annex A', () {
      int alpha(int e) {
        var x = 1;
        for (var i = 0; i < e; i++) {
          x = ReedSolomon.multiply(x, 2);
        }
        return x;
      }

      expect(ReedSolomon.generator(7), [
        for (final e in [0, 87, 229, 146, 149, 238, 102, 21]) alpha(e),
      ]);
    });

    test('a codeword with its error correction divides by the generator', () {
      for (final degree in [7, 10, 13, 17, 22, 30]) {
        final data = [for (var i = 0; i < 40; i++) (i * 37 + degree) & 0xFF];
        final ec = ReedSolomon.remainder(data, degree);
        expect(
          ReedSolomon.remainder([...data, ...ec], degree),
          everyElement(0),
        );
      }
    });

    test('the format and the version information', () {
      expect(formatBits(QrErrorCorrection.medium, 0), 0x5412);
      expect(formatBits(QrErrorCorrection.low, 0), 0x77C4);
      expect(versionBits(7), 0x07C94);
      expect(versionBits(40), 0x28C69);
    });

    test('the masks of Table 10', () {
      List<String> pattern(int mask) => [
        for (var y = 0; y < 6; y++)
          [
            for (var x = 0; x < 6; x++)
              if (masks(mask, x, y)) '#' else '.',
          ].join(),
      ];
      expect(pattern(0).take(2), ['#.#.#.', '.#.#.#']);
      expect(pattern(1).take(2), ['######', '......']);
      expect(pattern(2).first, '#..#..');
      expect(pattern(3).take(2), ['#..#..', '..#..#']);
      expect(pattern(4).take(3), ['###...', '###...', '...###']);
      expect(pattern(5), [
        '######',
        '#.....',
        '#..#..',
        '#.#.#.',
        '#..#..',
        '#.....',
      ]);
      expect(pattern(6), [
        '######',
        '###...',
        '##.##.',
        '#.#.#.',
        '#.##.#',
        '#...##',
      ]);
      expect(pattern(7), [
        '#.#.#.',
        '...###',
        '#...##',
        '.#.#.#',
        '###...',
        '.###..',
      ]);
    });
  });
}
