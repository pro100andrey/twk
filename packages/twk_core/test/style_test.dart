import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/src/style.dart';

void main() {
  test('rgbOf: an RGB its own, a palette entry as told or as xterm shows '
      'it, the default colors as told, null where they were not', () {
    final t = StyleTable();
    expect(t.rgbOf(const Color.rgb(1, 2, 3)), 0x010203);
    expect(t.rgbOf(Color.blue), 0x0000ee);
    t.setPaletteRgb(4, 0x1818b2);
    expect(t.rgbOf(Color.blue), 0x1818b2);
    expect(t.rgbOf(Color.defaultColor), t.defaultBackgroundRgb);
    expect(t.rgbOf(Color.defaultColor, text: true), isNull);
    t.defaultForegroundRgb = 0xfcfcfc;
    expect(t.rgbOf(Color.defaultColor, text: true), 0xfcfcfc);
  });

  test('translucent text blends over the background it ends up on', () {
    final t = StyleTable();
    final red = t.style(bg: const Color.rgb(255, 0, 0));
    final pen = t.pen(
      const Pen(
        fg: Color.rgb(255, 255, 255),
        fgAlpha: 128,
        bg: Color.rgb(0, 0, 255),
      ),
    );
    final id = t.compose(red, pen);
    expect(t.bgOf(id), const Color.rgb(0, 0, 255));
    expect(t.fgOf(id), const Color.rgb(128, 128, 255));
  });

  test('a fully transparent background changes nothing', () {
    final t = StyleTable();
    final pen = t.pen(const Pen(bg: Color.rgb(255, 255, 255), bgAlpha: 0));
    expect(t.bgOf(t.compose(0, pen)), Color.defaultColor);
    final blue = t.style(bg: Color.blue);
    expect(t.bgOf(t.compose(blue, pen)), Color.blue);
  });

  test('default-colored text with alpha uses the default text color', () {
    final t = StyleTable();
    final dim = t.pen(const Pen(fg: Color.defaultColor, fgAlpha: 128));
    // unknown default text color: the text stays default, not invisible
    expect(t.fgOf(t.compose(0, dim)), Color.defaultColor);
    t
      ..defaultForegroundRgb = 0xFFFFFF
      ..defaultBackgroundRgb = 0x000000;
    expect(t.fgOf(t.compose(0, dim)), const Color.rgb(128, 128, 128));
  });

  test('changing the default colors recomputes blends', () {
    final t = StyleTable();
    final glass = t.pen(const Pen(bg: Color.rgb(255, 255, 255), bgAlpha: 128));
    expect(t.bgOf(t.compose(0, glass)), const Color.rgb(128, 128, 128));
    t.defaultBackgroundRgb = 0xFFFFFF;
    expect(t.bgOf(t.compose(0, glass)), const Color.rgb(255, 255, 255));
  });

  test('a palette color blends as the terminal shows it where it told '
      '(OSC 4), as xterm does where it did not', () {
    final t = StyleTable()..defaultBackgroundRgb = 0x000000;
    final blue = t.pen(const Pen(bg: Color.blue, bgAlpha: 128));
    final red = t.pen(const Pen(bg: Color.red, bgAlpha: 128));
    // xterm's blue is 0x0000ee, its red 0xcd0000
    expect(t.paletteRgb(4), 0x0000ee);
    expect(t.bgOf(t.compose(0, blue)), const Color.rgb(0, 0, 119));
    t.setPaletteRgb(4, 0x89b4fa); // a themed terminal's blue
    expect(t.paletteRgb(4), 0x89b4fa);
    expect(t.bgOf(t.compose(0, blue)), const Color.rgb(69, 90, 125));
    expect(t.bgOf(t.compose(0, red)), const Color.rgb(103, 0, 0));
    // as the color blended over
    final white = t.pen(const Pen(bg: Color.rgb(255, 255, 255), bgAlpha: 128));
    expect(
      t.bgOf(t.compose(t.style(bg: Color.blue), white)),
      const Color.rgb(196, 218, 253),
    );
    // text, too
    final text = t.pen(const Pen(fg: Color.blue, fgAlpha: 128));
    expect(t.fgOf(t.compose(0, text)), const Color.rgb(69, 90, 125));
    t.setPaletteRgb(4, null);
    expect(t.paletteRgb(4), 0x0000ee);
    expect(t.bgOf(t.compose(0, blue)), const Color.rgb(0, 0, 119));
    expect(() => t.setPaletteRgb(256, 0), throwsRangeError);
  });

  test('a palette entry told leaves other tables as they were', () {
    final themed = StyleTable()..setPaletteRgb(4, 0x89b4fa);
    final plain = StyleTable();
    expect((themed.paletteRgb(4), plain.paletteRgb(4)), (0x89b4fa, 0x0000ee));
    // SGR stays the palette index: the terminal shows its own color
    expect(
      latin1.decode(themed.sgrFromReset(themed.style(fg: Color.blue))),
      '\x1b[0;34m',
    );
  });

  test('a pen id from another table is rejected', () {
    final t = StyleTable()..pen(const Pen(bg: Color.blue));
    expect(() => t.compose(0, 5), throwsA(isA<AssertionError>()));
    expect(() => t.opaqueStyleOf(5), throwsA(isA<AssertionError>()));
  });

  group('SGR per color mode', () {
    String sgr(StyleTable t, int id) => latin1
        .decode(t.sgrFromReset(id))
        .replaceAll('\x1b[', '')
        .replaceAll('m', '');
    String tr(StyleTable t, int a, int b) => latin1
        .decode(t.transition(a, b))
        .replaceAll('\x1b[', '')
        .replaceAll('m', '');
    // (fg, bg, attrs, underline color) -> what each mode emits from reset
    const red = Color.rgb(255, 0, 0);
    const cases = <(Pen, Map<ColorMode, String>)>[
      (
        Pen(fg: red),
        {
          ColorMode.trueColor: '0;38;2;255;0;0',
          ColorMode.ansi256: '0;38;5;196',
          ColorMode.ansi16: '0;91',
          ColorMode.none: '0',
        },
      ),
      (
        Pen(fg: Color.rgb(128, 128, 128)),
        {
          ColorMode.trueColor: '0;38;2;128;128;128',
          ColorMode.ansi256: '0;38;5;244', // the gray ramp, not the cube
          ColorMode.ansi16: '0;90',
          ColorMode.none: '0',
        },
      ),
      (
        Pen(bg: Color.rgb(255, 255, 255)),
        {
          ColorMode.trueColor: '0;48;2;255;255;255',
          ColorMode.ansi256: '0;48;5;231',
          ColorMode.ansi16: '0;107',
          ColorMode.none: '0',
        },
      ),
      (
        Pen(fg: Color.indexed(200), bg: Color.indexed(196)),
        {
          ColorMode.trueColor: '0;38;5;200;48;5;196',
          ColorMode.ansi256: '0;38;5;200;48;5;196',
          ColorMode.ansi16: '0;95;101', // nearest of the 16
          ColorMode.none: '0',
        },
      ),
      (
        Pen(fg: Color.yellow, bg: Color.indexed(12)),
        {
          ColorMode.trueColor: '0;33;104',
          ColorMode.ansi256: '0;33;104',
          ColorMode.ansi16: '0;33;104',
          ColorMode.none: '0',
        },
      ),
      (
        Pen(attrs: Attr.underline, underlineColor: red),
        {
          ColorMode.trueColor: '0;4;58:2::255:0:0',
          ColorMode.ansi256: '0;4;58:5:196',
          ColorMode.ansi16: '0;4;58:5:9',
          ColorMode.none: '0;4',
        },
      ),
      (
        Pen(fg: red, attrs: Attr.bold | Attr.italic),
        {
          ColorMode.trueColor: '0;1;3;38;2;255;0;0',
          ColorMode.ansi256: '0;1;3;38;5;196',
          ColorMode.ansi16: '0;1;3;91',
          ColorMode.none: '0;1;3',
        },
      ),
    ];
    for (final mode in ColorMode.values) {
      test(mode.name, () {
        final t = StyleTable(colorMode: mode);
        for (final (pen, want) in cases) {
          final id = t.style(
            fg: pen.fg ?? Color.defaultColor,
            bg: pen.bg ?? Color.defaultColor,
            attrs: pen.attrs,
            underlineColor: pen.underlineColor,
          );
          expect(sgr(t, id), want[mode], reason: '$pen');
        }
        final a = t.style(fg: red);
        final b = t.style(fg: const Color.rgb(128, 128, 128));
        final ul = t.style(attrs: Attr.underline, underlineColor: red);
        // without colors, red text and plain text look the same
        expect(tr(t, a, 0), mode == ColorMode.none ? '' : '0');
        expect(tr(t, ul, 0), '0');
        expect(
          tr(t, a, b),
          {
            ColorMode.trueColor: '38;2;128;128;128',
            ColorMode.ansi256: '38;5;244',
            ColorMode.ansi16: '90',
            ColorMode.none: '', // the two look the same without colors
          }[mode],
        );
      });
    }
  });

  test('styled underlines are plain ones on a terminal without them', () {
    String sgr(List<int> bytes) =>
        latin1.decode(bytes).replaceAll('\x1b[', '').replaceAll('m', '');
    final t = StyleTable(styledUnderlines: false);
    final curly = t.style(attrs: Attr.curlyUnderline);
    final dotted = t.style(attrs: Attr.dottedUnderline, fg: Color.red);
    final plain = t.style(attrs: Attr.underline);
    // Terminal.app reads 4:3 as 43, a yellow background
    expect(sgr(t.sgrFromReset(curly)), '0;4');
    expect(sgr(t.transition(curly, dotted)), '31');
    expect(t.transition(curly, plain), isEmpty);
    expect(sgr(t.transition(plain, 0)), '0');
    // nor an underline color, whose colon form it misreads too
    final red = t.style(attrs: Attr.curlyUnderline, underlineColor: Color.red);
    expect(sgr(t.sgrFromReset(red)), '0;4');
    expect(t.transition(curly, red), isEmpty);
    // a blank under it keeps the text's color for its line, the color the
    // underline has under the text
    final redText = t.style(
      fg: Color.red,
      attrs: Attr.curlyUnderline,
      underlineColor: Color.blue,
    );
    expect(t.fgOf(t.blankStyleOf(redText)), Color.red);

    final styled = StyleTable();
    final c = styled.style(attrs: Attr.curlyUnderline);
    final p = styled.style(attrs: Attr.underline);
    final r = styled.style(
      attrs: Attr.curlyUnderline,
      underlineColor: Color.red,
    );
    expect(sgr(styled.sgrFromReset(c)), '0;4:3');
    expect(sgr(styled.transition(c, p)), '4');
    expect(sgr(styled.sgrFromReset(r)), '0;4:3;58:5:1');
    // with its own color the line needs not the text's on a blank
    final blueOnRed = styled.style(
      fg: Color.red,
      attrs: Attr.curlyUnderline,
      underlineColor: Color.blue,
    );
    expect(styled.fgOf(styled.blankStyleOf(blueOnRed)), Color.defaultColor);
  });
}
