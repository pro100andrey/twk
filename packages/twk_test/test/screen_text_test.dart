// The screen as text: colors and attributes by name, a cell's style, the
// rows of the emulator plain or with their styles marked, and the screen
// and render tree as a failure message shows them.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// An emulator [width] × [height] fed [text].
Vt _fed(String text, {int width = 10, int height = 3}) =>
    Vt(width, height)..feed(utf8.encode(text));

void main() {
  test('a color by its name in Color, by its index past the 16, by its '
      'hex of 24 bits, or as the default; colorOf makes the Color', () {
    expect(colorName(0), 'default');
    expect(colorName(Color.red.value), 'red');
    expect(colorName(const Color.indexed(9).value), 'brightRed');
    expect(colorName(const Color.indexed(200).value), 'indexed(200)');
    expect(colorName(const Color.rgb(16, 32, 48).value), '#102030');
    expect(colorOf(0), Color.defaultColor);
    expect(colorOf(Color.red.value), Color.red);
    expect(colorOf(const Color.rgb(1, 2, 3).value), const Color.rgb(1, 2, 3));
  });

  test('attributes by the names of Attr, in the order of the bits, an '
      'underline by its kind', () {
    expect(attrNames(0), isEmpty);
    expect(attrNames(Attr.bold | Attr.strike), ['bold', 'strike']);
    expect(attrNames(Attr.curlyUnderline), ['curlyUnderline']);
  });

  test("a cell's style: attributes, color, background, underline color, "
      'each left out when it is the default; marked as a snapshot marks '
      'it', () {
    final vt = _fed('\x1b[1;31;48;2;16;32;48;58:5:4m[\x1b[0mb');
    expect(styleOf(vt.cell(0, 0)), 'bold red on #102030 ul=blue');
    expect(styleOf(vt.cell(1, 0)), '');
    expect(markedCell(vt.cell(0, 0)), '[bold red on #102030 ul=blue][[[/]');
    expect(markedCell(vt.cell(1, 0)), 'b');
  });

  test('a row as text, a wide glyph once and without the blanks that end '
      'it; with styles, each run of one style marked', () {
    final vt = _fed('界a\x1b[1mbc\x1b[0m d');
    expect(rowText(vt, 0), '界abc d');
    expect(rowText(vt, 0, styles: true), '界a[bold]bc[/] d');
    expect(rowText(vt, 1), '');
  });

  test('the rows of the screen without the empty rows that end it; the '
      'screen as a failure message shows it, rows numbered, the blank '
      'rows summed up', () {
    final vt = _fed('\x1b[1mok\x1b[0m');
    expect(screenRows(vt), ['ok']);
    expect(screenRows(vt, styles: true), ['[bold]ok[/]']);
    expect(describeScreen(vt), '0│ok\n(rows 1–2 blank)');
    expect(
      describeScreen(vt, styles: true),
      '0│[bold]ok[/]\n(rows 1–2 blank)',
    );
    expect(
      describeApp(vt, null),
      'screen 10×3:\n0│ok\n(rows 1–2 blank)\n\nrender tree:\nnone',
    );
    expect(
      describeApp(vt, null, styles: true),
      'screen 10×3:\n0│[bold]ok[/]\n(rows 1–2 blank)\n\nrender tree:\nnone',
    );
    expect(describeApp(vt, null, screen: false), 'render tree:\nnone');
  });
}
