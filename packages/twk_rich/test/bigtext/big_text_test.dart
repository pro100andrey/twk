// Each font drawing a sample, what it covers and what stands in for what
// it does not, characters without a glyph, braille and ASCII where blocks
// and box drawing are two columns wide, fitting the largest font, the
// alignment of lines, the style, and the widget configuring its render
// object.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_rich/twk_rich.dart';
import 'package:twk_test/twk_test.dart' show Shot;

const red = Color.rgb(255, 0, 0);
const grey = Color.rgb(1, 2, 3);

/// [widget] on a screen of [width] × [height] cells.
Shot shown(Widget widget, int width, int height, {int ambiguousWidth = 1}) {
  final shot = Shot(widget, width, height, ambiguousWidth: ambiguousWidth);
  expect(shot.vt.errors, isEmpty);
  return shot;
}

/// The rows the emulator shows for [text] in [font], on a screen as big as
/// the text.
List<String> drawn(
  String text,
  BigFont font, {
  MissingGlyph missing = MissingGlyph.box,
}) {
  final o = RenderBigText(text, fonts: [font], missing: missing)
    ..layout(
      const BoxConstraints(
        0,
        BoxConstraints.unbounded,
        0,
        BoxConstraints.unbounded,
      ),
    );
  return shown(
    BigText(text, font: font, missing: missing),
    o.width,
    o.height,
  ).rows;
}

/// The font a [BigText] of [text] picks from [fonts] on a screen of
/// [width] × [height] cells.
BigFont fitted(
  String text,
  int width,
  int height, {
  List<BigFont> fonts = BigFont.sizes,
}) => (shown(BigText(text, fonts: fonts), width, height).top as RenderBigText)
    .font;

/// The Cyrillic letters of Russian and Ukrainian.
const capitals = 'АБВГҐДЕЄЁЖЗИІЇЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ';
const lowercase = 'абвгґдеєёжзиіїйклмнопрстуфхцчшщъыьэюя';

/// Glyph and background of each cell of row [y] of [shot].
List<(String, Color)> backgrounds(Shot shot, int y) => [
  for (final (glyph, _, bg) in shot.colors(y)) (glyph, bg),
];

void main() {
  group('the fonts', () {
    test('block draws half blocks, 4 rows to a line', () {
      expect(drawn('Big 42%', BigFont.block), [
        '█▀▀▀▄  ▀              ▄█  ▄▀▀▀▄ ██  ▄',
        '█▄▄▄▀ ▀█  ▄▀▀▀█     ▄▀ █     ▄▀   ▄▀',
        '█   █  █  ▀▄▄▄█     ▀▀▀█▀  ▄▀   ▄▀ ▄▄',
        '▀▀▀▀  ▀▀▀  ▄▄▄▀        ▀  ▀▀▀▀▀    ▀▀',
      ]);
      expect(drawn('Привіт', BigFont.block), [
        '█▀▀▀█                    ▀',
        '█   █ █▀▀▀▄ █  ▄█ █▀▀▀▄ ▀█  ▀▀█▀▀',
        '█   █ █▄▄▄▀ █▄▀ █ █▀▀▀▄  █    █',
        '▀   ▀ █     ▀   ▀ ▀▀▀▀  ▀▀▀   ▀',
      ]);
    });

    test('large draws blocks two cells wide, 8 rows to a line', () {
      expect(drawn('1:2', BigFont.large), [
        '    ██              ██████',
        '  ████      ████  ██      ██',
        '    ██      ████          ██',
        '    ██                  ██',
        '    ██      ████      ██',
        '    ██      ████    ██',
        '  ██████          ██████████',
        '',
      ]);
    });

    test('thin draws box drawing, 3 rows to a line', () {
      expect(drawn('TUI 12:30', BigFont.thin), [
        '╶┬╴ ╷ ╷ ╶┬╴    ╶┐  ╶─┐   ╶─┐ ┌─┐',
        ' │  │ │  │      │  ┌─┘ : ╶─┤ │ │',
        ' ╵  └─┘ ╶┴╴    ╶┴╴ └─╴   ╶─┘ └─┘',
      ]);
    });

    test('small draws 3×5 pixels in half blocks, 3 rows to a line', () {
      expect(drawn('Tiny 9°', BigFont.small), [
        '▀█▀ ▀█▀ █▄ █ █ █    █▀█ ▄▀▄',
        ' █   █  █ ▀█  █     ▀▀█  ▀',
        ' ▀  ▀▀▀ ▀  ▀  ▀     ▀▀',
      ]);
    });

    test('block and large have a glyph for ASCII and Cyrillic', () {
      final box = drawn('\u{E000}', BigFont.block);
      final bigBox = drawn('\u{E000}', BigFont.large);
      for (final c in [
        for (var cp = 0x21; cp < 0x7F; cp++) String.fromCharCode(cp),
        '°',
        ...capitals.split(''),
        ...lowercase.split(''),
      ]) {
        expect(drawn(c, BigFont.block), isNot(box), reason: c);
        expect(drawn(c, BigFont.large), isNot(bigBox), reason: c);
      }
    });

    test('thin and small have a glyph for capitals, digits and the common '
        'punctuation', () {
      for (final font in [BigFont.thin, BigFont.small]) {
        final box = drawn('\u{E000}', font);
        for (final c in [
          ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.split(''),
          ...r'''!"#%'()*+,-./:;<=>?[\]_|°'''.split(''),
          ...capitals.split(''),
        ]) {
          expect(drawn(c, font), isNot(box), reason: '$font $c');
        }
      }
    });
  });

  group('stand-ins', () {
    test('thin and small draw lowercase in capitals', () {
      for (final font in [BigFont.thin, BigFont.small]) {
        expect(drawn('tiny ёж', font), drawn('TINY ЁЖ', font));
      }
    });

    test('an accented letter is drawn without its accent', () {
      expect(drawn('Café', BigFont.block), drawn('Cafe', BigFont.block));
      expect(drawn('Й', BigFont.thin), drawn('И', BigFont.thin));
      expect(drawn('Й', BigFont.thin), ['╷┌┐', '│││', '└┘╵']);
    });

    test('a Cyrillic letter is drawn as the Latin one it looks like', () {
      expect(drawn('АВОРуха', BigFont.block), drawn('ABOPyxa', BigFont.block));
    });
  });

  group('a character without a glyph', () {
    test('is the font box, as big as a letter', () {
      expect(drawn('中', BigFont.block), [
        '█▀▀▀█',
        '█   █',
        '█   █',
        '▀▀▀▀▀',
      ]);
      expect(drawn('中', BigFont.thin), ['╔═╗', '║ ║', '╚═╝']);
    });

    test('is itself on the middle row, as wide as it is drawn', () {
      expect(drawn('A中B', BigFont.block, missing: MissingGlyph.plain), [
        '▄▀▀▀▄    █▀▀▀▄',
        '█▄▄▄█ 中 █▄▄▄▀',
        '█   █    █   █',
        '▀   ▀    ▀▀▀▀',
      ]);
    });

    test('that is not drawn takes no room', () {
      for (final missing in MissingGlyph.values) {
        expect(
          drawn('A\u0007́B', BigFont.block, missing: missing),
          drawn('AB', BigFont.block),
        );
      }
    });
  });

  group('where blocks and box drawing are two columns wide', () {
    test('blocks are braille of the same pixels', () {
      final shot = shown(
        const BigText('Big 42%', font: BigFont.block),
        38,
        4,
        ambiguousWidth: 2,
      );
      expect(shot.rows, [
        '⣿⠛⠛⠛⣤  ⠛              ⣤⣿  ⣤⠛⠛⠛⣤ ⣿⣿  ⣤',
        '⣿⣤⣤⣤⠛ ⠛⣿  ⣤⠛⠛⠛⣿     ⣤⠛ ⣿     ⣤⠛   ⣤⠛',
        '⣿   ⣿  ⣿  ⠛⣤⣤⣤⣿     ⠛⠛⠛⣿⠛  ⣤⠛   ⣤⠛ ⣤⣤',
        '⠛⠛⠛⠛  ⠛⠛⠛  ⣤⣤⣤⠛        ⠛  ⠛⠛⠛⠛⠛    ⠛⠛',
      ]);
      expect(shot.anyWide, isFalse);
      final large = shown(
        const BigText('1', font: BigFont.large),
        10,
        8,
        ambiguousWidth: 2,
      );
      expect(large.rows.first, '    ⣿⣿');
      expect(large.anyWide, isFalse);
    });

    test('box drawing is ASCII', () {
      final shot = shown(
        const BigText('TUI 12:30', font: BigFont.thin),
        33,
        3,
        ambiguousWidth: 2,
      );
      expect(shot.rows, [
        '-+- | | -+-    -+  --+   --+ +-+',
        ' |  | |  |      |  +-+ : --+ | |',
        ' |  +-+ -+-    -+- +--   --+ +-+',
      ]);
      expect(shot.anyWide, isFalse);
      expect(
        shown(
          const BigText('O', font: BigFont.thin),
          3,
          3,
          ambiguousWidth: 2,
        ).rows,
        ['.-.', '| |', "'-'"],
      );
    });
  });

  group('fitting', () {
    test('picks the largest font the text fits in', () {
      // 42 is 22 × 8 cells in large, 11 × 4 in block, 7 × 3 in small
      expect(fitted('42', 22, 8), BigFont.large);
      expect(fitted('42', 21, 8), BigFont.block);
      expect(fitted('42', 22, 7), BigFont.block);
      expect(fitted('42', 10, 4), BigFont.small);
      expect(fitted('42', 11, 3), BigFont.small);
    });

    test('counts every line and the rows between them', () {
      // 17 rows in large, 9 in block, 7 in small
      expect(fitted('4\n2', 20, 17), BigFont.large);
      expect(fitted('4\n2', 20, 16), BigFont.block);
      expect(fitted('4\n2', 20, 8), BigFont.small);
    });

    test('takes the last font, cut off, when the text fits in none', () {
      final shot = shown(const BigText('42'), 5, 2);
      expect((shot.top as RenderBigText).font, BigFont.small);
      expect(shot.rows, ['█ █ ▀', '▀▀█ ▄']);
    });

    test('tries the fonts given, in order', () {
      final fonts = [BigFont.thin, BigFont.small];
      expect(fitted('42', 7, 3, fonts: fonts), BigFont.thin);
      expect(fitted('42', 6, 3, fonts: fonts), BigFont.small);
    });

    test('draws in the font given whatever the room', () {
      final shot = shown(const BigText('1', font: BigFont.large), 7, 3);
      expect((shot.top as RenderBigText).font, BigFont.large);
      expect(shot.rows, ['    ██', '  ████', '    ██']);
    });

    test('is as wide as its widest line and as tall as its lines', () {
      final o = RenderBigText('42\n1', fonts: const [BigFont.block])
        ..layout(const BoxConstraints(0, 100, 0, 100));
      expect((o.width, o.height), (11, 9));
      o.layout(const BoxConstraints(20, 100, 10, 100));
      expect((o.width, o.height), (20, 10));
      o.layout(const BoxConstraints(0, 5, 0, 3));
      expect((o.width, o.height), (5, 3));
    });

    test('tells its intrinsic sizes from the fonts that fit', () {
      final o = RenderBigText('42');
      expect(o.getMaxIntrinsicWidth(100), 22);
      expect(o.getMaxIntrinsicWidth(4), 11);
      expect(o.getMaxIntrinsicWidth(2), 7);
      expect(o.getMinIntrinsicWidth(100), 7);
      expect(o.getMinIntrinsicHeight(22), 8);
      expect(o.getMaxIntrinsicHeight(21), 4);
      expect(o.getMinIntrinsicHeight(1), 3);
    });
  });

  group('alignment', () {
    test('places a line in the middle or at the right', () {
      expect(
        shown(
          const BigText('I', font: BigFont.block, align: TextAlign.center),
          9,
          4,
        ).rows,
        ['   ▀█▀', '    █', '    █', '   ▀▀▀'],
      );
      expect(
        shown(
          const BigText('I', font: BigFont.block, align: TextAlign.right),
          9,
          4,
        ).rows,
        ['      ▀█▀', '       █', '       █', '      ▀▀▀'],
      );
    });

    test('places each line on its own, a blank row apart', () {
      expect(
        shown(
          const BigText('1\n42', font: BigFont.block, align: TextAlign.center),
          11,
          9,
        ).rows,
        [
          '    ▄█',
          '     █',
          '     █',
          '    ▀▀▀',
          '',
          '  ▄█  ▄▀▀▀▄',
          '▄▀ █     ▄▀',
          '▀▀▀█▀  ▄▀',
          '   ▀  ▀▀▀▀▀',
        ],
      );
    });
  });

  group('the style', () {
    test('colors the letters, over its background on every cell', () {
      final shot = shown(
        const BigText(
          'I',
          font: BigFont.block,
          style: Style(fg: red, bg: grey),
        ),
        4,
        4,
      );
      expect(shot.colors(0).take(3), [
        ('▀', red, grey),
        ('█', red, grey),
        ('▀', red, grey),
      ]);
      expect(backgrounds(shot, 3), [
        ('▀', grey),
        ('▀', grey),
        ('▀', grey),
        (' ', grey),
      ]);
    });

    test('keeps the background drawn under it without one', () {
      final shot = shown(
        const Box(
          style: Style(bg: grey),
          child: BigText(
            'I',
            font: BigFont.block,
            style: Style(fg: red),
          ),
        ),
        4,
        4,
      );
      expect(shot.colors(1)[1], ('█', red, grey));
      expect(backgrounds(shot, 1), [
        (' ', grey),
        ('█', grey),
        (' ', grey),
        (' ', grey),
      ]);
    });

    test('is merged onto the default text style', () {
      final shot = shown(
        const DefaultTextStyle(
          style: Style(fg: red, bg: grey),
          child: BigText(
            'I',
            font: BigFont.block,
            style: Style(bg: red),
          ),
        ),
        3,
        4,
      );
      expect(shot.colors(1)[1], ('█', red, red));
    });
  });

  group('BigText', () {
    test('rebuilt, configures the same render object', () {
      final shot = shown(const BigText('1', font: BigFont.block), 9, 4);
      final o = shot.top;
      shot.pump(
        const BigText('O', font: BigFont.thin, align: TextAlign.right),
      );
      expect(shot.top, same(o));
      expect(shot.rows, ['      ╭─╮', '      │ │', '      ╰─╯', '']);
      shot.pump(
        const BigText(
          '中',
          font: BigFont.thin,
          missing: MissingGlyph.plain,
          style: Style(bg: grey),
        ),
      );
      expect(shot.top, same(o));
      expect(shot.rows, ['', '中', '', '']);
      expect(backgrounds(shot, 3)[8], (' ', grey));
    });

    test('its render object holds what the widget last gave it', () {
      Widget under(BigText text) => DefaultTextStyle(
        style: const Style(bg: grey),
        child: text,
      );
      final shot = shown(under(const BigText('1')), 9, 4);
      final o = shot.top as RenderBigText;
      expect(o.fonts, BigFont.sizes);
      expect(
        (o.text, o.align, o.style, o.missing),
        ('1', TextAlign.left, const Style(bg: grey), MissingGlyph.box),
      );
      shot.pump(
        under(
          const BigText(
            '2',
            fonts: [BigFont.thin, BigFont.small],
            align: TextAlign.center,
            style: Style(fg: red),
            missing: MissingGlyph.plain,
          ),
        ),
      );
      expect(shot.top, same(o));
      expect(o.fonts, [BigFont.thin, BigFont.small]);
      expect(
        (o.text, o.align, o.style, o.missing),
        (
          '2',
          TextAlign.center,
          const Style(fg: red, bg: grey),
          MissingGlyph.plain,
        ),
      );
      shot.pump(under(const BigText('2', font: BigFont.block)));
      expect(o.fonts, [BigFont.block]);
    });
  });
}
