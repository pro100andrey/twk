// The QR code widget: its modules drawn in half blocks with the quiet zone,
// read back cell by cell from the emulator its frames are written to, dark
// on light whatever the theme, two columns to a module where the canvas
// draws half blocks two wide, cut off within small constraints, new data,
// settings and colors shown, what its render object holds and its
// intrinsic size; and, where zbarimg is installed, what it draws decoded
// by it.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_rich/twk_rich.dart';
import 'package:twk_test/twk_test.dart';

const black = Color.rgb(0, 0, 0);
const white = Color.rgb(255, 255, 255);

/// The modules [shot] shows of a code at its top left, [side] modules a
/// side with its quiet zone, as a scanner sees them: those in [dark] dark,
/// those in [light] light. Two to a cell in half blocks, the glyph's
/// color above or below and the background's in the other half; or, with
/// [wide], a module to two cells of a row, by their background. Any other
/// color fails the test.
List<List<bool>> modulesOf(
  Shot shot,
  int side, {
  bool wide = false,
  Color dark = black,
  Color light = white,
}) {
  bool isDark(Color color) {
    expect(color, anyOf(dark, light));
    return color == dark;
  }

  return [
    for (var y = 0; y < side; y++)
      [
        for (var x = 0; x < side; x++)
          if (wide)
            isDark(shot.colors(y)[2 * x].$3) &&
                isDark(shot.colors(y)[2 * x + 1].$3)
          else
            switch (shot.colors(y ~/ 2)[x]) {
              ('█', final fg, _) => isDark(fg),
              ('▀', final fg, final bg) => isDark(y.isEven ? fg : bg),
              ('▄', final fg, final bg) => isDark(y.isEven ? bg : fg),
              (' ', _, final bg) => isDark(bg),
              final cell => fail('a cell of $cell'),
            },
      ],
  ];
}

/// [code] at the top left of a screen of [width] × [height] cells.
Shot shown(Widget code, int width, int height, {int ambiguousWidth = 1}) =>
    Shot(
      topLeft(code),
      width,
      height,
      ambiguousWidth: ambiguousWidth,
    );

/// [code] at the top left of what it is in.
Widget topLeft(Widget code) => Align(alignment: Alignment.topLeft, child: code);

/// The size of the code [shot] shows, in cells.
(int, int) sizeOf(Shot shot) {
  RenderObject? find(RenderObject o) {
    if (o is RenderQrCode) {
      return o;
    }
    RenderObject? found;
    o.visitChildren((child) => found ??= find(child));
    return found;
  }

  final code = find(shot.top)!;
  return (code.width, code.height);
}

/// The modules of [symbol] with [quiet] light ones around it.
List<List<bool>> withQuietZone(QrSymbol symbol, int quiet) {
  final side = symbol.size + 2 * quiet;
  bool at(int x, int y) =>
      x >= 0 &&
      y >= 0 &&
      x < symbol.size &&
      y < symbol.size &&
      symbol.isDark(x, y);
  return [
    for (var y = 0; y < side; y++)
      [for (var x = 0; x < side; x++) at(x - quiet, y - quiet)],
  ];
}

/// Whether zbarimg, a QR decoder, is installed.
final bool hasZbar = () {
  try {
    return Process.runSync('zbarimg', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}();

/// What zbarimg reads from [modules] drawn as a bitmap, 4 pixels a module;
/// null where it finds no code.
String? decode(List<List<bool>> modules, Directory dir) {
  const scale = 4;
  final side = modules.length;
  final pbm = StringBuffer('P1\n${side * scale} ${side * scale}\n');
  for (final row in modules) {
    final line = [
      for (final dark in row)
        for (var k = 0; k < scale; k++)
          if (dark) '1' else '0',
    ].join(' ');
    for (var k = 0; k < scale; k++) {
      pbm.writeln(line);
    }
  }
  final file = File('${dir.path}/code.pbm')..writeAsStringSync('$pbm');
  final result = Process.runSync('zbarimg', [
    '--quiet',
    '--raw',
    file.path,
  ], stdoutEncoding: utf8);
  if (result.exitCode != 0) {
    return null;
  }
  final out = result.stdout as String;
  return out.endsWith('\n') ? out.substring(0, out.length - 1) : out;
}

void main() {
  test('draws the modules in half blocks, a quiet zone of 4 around them', () {
    final symbol = QrSymbol.encode('HELLO WORLD');
    final side = symbol.size + 8;
    final shot = shown(const QrCode('HELLO WORLD'), side + 3, side ~/ 2 + 3);
    expect(sizeOf(shot), (side, (side + 1) ~/ 2));
    expect(modulesOf(shot, side), withQuietZone(symbol, 4));
    // the lower half of the last row is light, a module more of quiet zone
    expect(
      shot.colors(side ~/ 2).take(side).map((cell) => cell.$1).toSet(),
      {' '},
    );
    expect(shot.rows.first.trim(), isEmpty);
    expect(shot.rows[2].substring(4, 11), '█▀▀▀▀▀█');
  });

  test('round-trips through the emulator in every version and level', () {
    for (var version = 1; version <= 40; version += 3) {
      for (final level in QrErrorCorrection.values) {
        final symbol = QrSymbol.encode(
          'VERSION $version',
          level: level,
          version: version,
        );
        final side = symbol.size + 4;
        final shot = shown(
          QrCode.symbol(symbol, quietZone: 2),
          side,
          (side + 1) ~/ 2,
        );
        expect(
          modulesOf(shot, side),
          withQuietZone(symbol, 2),
          reason: '$version-$level',
        );
      }
    }
  });

  test('takes the quiet zone it is given', () {
    final symbol = QrSymbol.encode('1');
    for (final quiet in [0, 1, 2, 6]) {
      final side = symbol.size + 2 * quiet;
      final shot = shown(
        QrCode('1', quietZone: quiet),
        side + 2,
        (side + 1) ~/ 2 + 1,
      );
      expect(sizeOf(shot), (side, (side + 1) ~/ 2), reason: 'quiet $quiet');
      expect(modulesOf(shot, side), withQuietZone(symbol, quiet));
    }
  });

  test('dark on light whatever the theme, or in the colors given', () {
    final symbol = QrSymbol.encode('theme');
    final side = symbol.size + 8;
    for (final brightness in Brightness.values) {
      final shot = shown(
        TerminalBrightness(
          brightness: brightness,
          child: const Theme.adaptive(
            child: DefaultTextStyle(
              style: Style(fg: Color.red, bg: Color.blue, attrs: Attr.bold),
              child: QrCode('theme'),
            ),
          ),
        ),
        side,
        (side + 1) ~/ 2,
      );
      expect(modulesOf(shot, side), withQuietZone(symbol, 4));
    }
    const navy = Color.rgb(0, 0, 80);
    const cream = Color.rgb(255, 250, 230);
    final shot = shown(
      const QrCode('theme', dark: navy, light: cream),
      side,
      (side + 1) ~/ 2,
    );
    expect(
      modulesOf(shot, side, dark: navy, light: cream),
      withQuietZone(symbol, 4),
    );
  });

  test('two columns to a module where half blocks are two wide', () {
    final symbol = QrSymbol.encode('ambiguous');
    final side = symbol.size + 8;
    final shot = shown(
      const QrCode('ambiguous'),
      2 * side,
      side,
      ambiguousWidth: 2,
    );
    expect(sizeOf(shot), (2 * side, side));
    expect(shot.anyWide, isFalse);
    expect(modulesOf(shot, side, wide: true), withQuietZone(symbol, 4));
  });

  test('shows new data, a new level and a new symbol', () {
    final shot = shown(const QrCode('1'), 60, 30);
    expect(sizeOf(shot), (29, 15));
    shot.pump(topLeft(const QrCode('a longer text, version 3 at least')));
    final longer = QrSymbol.encode('a longer text, version 3 at least');
    expect(longer.version, 3);
    expect(sizeOf(shot).$1, longer.size + 8);
    expect(modulesOf(shot, longer.size + 8), withQuietZone(longer, 4));
    shot.pump(
      topLeft(
        const QrCode(
          'a longer text, version 3 at least',
          level: QrErrorCorrection.high,
        ),
      ),
    );
    final high = QrSymbol.encode(
      'a longer text, version 3 at least',
      level: QrErrorCorrection.high,
    );
    expect(modulesOf(shot, high.size + 8), withQuietZone(high, 4));
    final masked = QrSymbol.encode('1', mask: 5);
    shot.pump(topLeft(QrCode.symbol(masked, quietZone: 1)));
    expect(modulesOf(shot, masked.size + 2), withQuietZone(masked, 1));
  });

  test('repaints in new colors', () {
    final symbol = QrSymbol.encode('colors');
    final side = symbol.size + 8;
    final shot = shown(const QrCode('colors'), side, (side + 1) ~/ 2);
    expect(modulesOf(shot, side), withQuietZone(symbol, 4));
    const navy = Color.rgb(0, 0, 80);
    const cream = Color.rgb(255, 250, 230);
    shot.pump(topLeft(const QrCode('colors', dark: navy)));
    expect(modulesOf(shot, side, dark: navy), withQuietZone(symbol, 4));
    shot.pump(topLeft(const QrCode('colors', dark: navy, light: cream)));
    expect(
      modulesOf(shot, side, dark: navy, light: cream),
      withQuietZone(symbol, 4),
    );
  });

  test('its render object holds what the widget last gave it', () {
    final shot = shown(const QrCode('1'), 60, 30);
    RenderQrCode code() {
      RenderQrCode? find(RenderObject o) {
        if (o is RenderQrCode) {
          return o;
        }
        RenderQrCode? found;
        o.visitChildren((child) => found ??= find(child));
        return found;
      }

      return find(shot.top)!;
    }

    final first = code();
    expect(
      (first.data, first.level, first.symbol, first.quietZone),
      ('1', QrErrorCorrection.medium, null, 4),
    );
    expect((first.dark, first.light), (QrCode.black, QrCode.white));
    final symbol = QrSymbol.encode('2', mask: 3);
    const navy = Color.rgb(0, 0, 80);
    shot.pump(
      topLeft(QrCode.symbol(symbol, quietZone: 2, dark: navy, light: black)),
    );
    expect(code(), same(first));
    expect(first.symbol, same(symbol));
    expect(
      (first.data, first.quietZone, first.dark, first.light),
      (null, 2, navy, black),
    );
    shot.pump(topLeft(const QrCode('3', level: QrErrorCorrection.high)));
    expect((first.data, first.level), ('3', QrErrorCorrection.high));
  });

  test('is as wide and as tall as its modules, intrinsically', () {
    final code = RenderQrCode(data: '1');
    expect(code.getMinIntrinsicWidth(0), 29);
    expect(code.getMaxIntrinsicWidth(0), 29);
    expect(code.getMinIntrinsicHeight(0), 15);
    expect(code.getMaxIntrinsicHeight(0), 15);
    code.quietZone = 1;
    expect(code.getMaxIntrinsicWidth(100), 23);
    expect(code.getMaxIntrinsicHeight(100), 12);
  });

  test('is cut off within constraints too small for it', () {
    final symbol = QrSymbol.encode('cut');
    final side = symbol.size + 8;
    final shot = shown(
      const Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 20, height: 6, child: QrCode('cut')),
      ),
      side,
      side,
    );
    expect(sizeOf(shot), (20, 6));
    final full = shown(const QrCode('cut'), side, side);
    for (var y = 0; y < 6; y++) {
      expect(
        shot.colors(y).take(20).toList(),
        full.colors(y).take(20).toList(),
      );
      expect(shot.rows[y].length, lessThanOrEqualTo(20));
    }
    expect(shot.rows.skip(6).every((row) => row.isEmpty), isTrue);
  });

  testTwk('data too long for any version is an error in its place', (
    t,
  ) async {
    await t.pumpWidget(
      QrCode('1' * 7090, level: QrErrorCorrection.low),
      size: (60, 6),
    );
    expect(t.lines.join(), contains('7090 characters'));
  });

  group('read by zbarimg', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('qr_code_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test(
      'what it draws is the text, in every mode and level',
      () {
        final texts = [
          '01234567',
          'HELLO WORLD',
          'https://example.com/sign-in?code=4F7A-19C2',
          'Grüße, мир, 世界 🙂',
          'WIFI:T:WPA;S:home;P:correct horse battery staple;;',
          '3141592653589793238462643383279502884197169399375105820974944',
          [for (var i = 0; i < 700; i++) 'abcdefghij'[i * 7 % 10]].join(),
        ];
        for (final text in texts) {
          for (final level in QrErrorCorrection.values) {
            final symbol = QrSymbol.encode(text, level: level);
            final side = symbol.size + 8;
            for (final ambiguous in [1, 2]) {
              final wide = ambiguous == 2;
              final shot = shown(
                QrCode(text, level: level),
                wide ? 2 * side : side,
                wide ? side : (side + 1) ~/ 2,
                ambiguousWidth: ambiguous,
              );
              expect(
                decode(modulesOf(shot, side, wide: wide), dir),
                text,
                reason: '${symbol.version}-${level.name} $text',
              );
            }
          }
        }
      },
      skip: hasZbar ? false : 'zbarimg is not installed',
    );
  });
}
