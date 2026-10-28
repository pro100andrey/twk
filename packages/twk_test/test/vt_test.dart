// The emulator's screen, cursor and SGR as the bytes fed to it leave them,
// and the errors it reports for what a terminal would show wrong.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart' show Attr, Color;
import 'package:twk_test/vt.dart';

void main() {
  test('printed text goes into the cells with the style SGR set, and CUP '
      'moves the cursor', () {
    final vt = Vt(20, 2)
      ..feed(utf8.encode('\x1b[1;31mhi\x1b[0m\x1b[2;3Hthere'));
    expect(vt.lines, ['hi', '  there']);
    expect(vt.cell(0, 0).attrs, Attr.bold);
    expect(vt.cell(0, 0).fg, Color.red.value);
    expect(vt.cell(2, 0).fg, 0);
    expect((vt.cx, vt.cy), (7, 1));
    expect(vt.dump(), '${'hi'.padRight(20)}\n${'  there'.padRight(20)}');
  });

  test("a cell's colors as Color: the default, an entry of the palette, "
      "one of 24 bits, and the underline's", () {
    final vt = Vt(3, 1)
      ..feed(utf8.encode('a\x1b[31;48;2;1;2;3;58:5:200mb\x1b[0m'));
    final plain = vt.cell(0, 0);
    expect(plain.fgColor, Color.defaultColor);
    expect(plain.bgColor, Color.defaultColor);
    expect(plain.ulColor, Color.defaultColor);
    final styled = vt.cell(1, 0);
    expect(styled.fgColor, Color.red);
    expect(styled.bgColor, const Color.rgb(1, 2, 3));
    expect(styled.ulColor, const Color.indexed(200));
  });

  test('a sequence cut off at the end of what is fed waits for the rest', () {
    final vt = Vt(10, 1)
      ..feed(utf8.encode('a\x1b[3'))
      ..feed(utf8.encode('1mb'));
    expect(vt.lines, ['ab']);
    expect(vt.cell(1, 0).fg, Color.red.value);
    expect(vt.errors, isEmpty);
  });

  test('a raw control byte is an error, thrown when strict', () {
    expect(() => Vt(10, 1).feed([0x61, 0x07]), throwsStateError);
    final vt = Vt(10, 1, strict: false)..feed([0x61, 0x07, 0x62]);
    expect(vt.errors, ['raw control byte 0x7']);
    expect(vt.lines, ['ab']);
  });

  test('LF is an error unless allowed, and then moves the cursor down', () {
    final vt = Vt(10, 2, strict: false)..feed(utf8.encode('a\nb'));
    expect(vt.errors, ['raw control byte 0xa']);
    final lf = Vt(10, 2, allowLineFeed: true)..feed(utf8.encode('a\nb'));
    expect(lf.lines, ['a', ' b']);
  });

  test('a print past the last column wraps, which is an error', () {
    final vt = Vt(3, 2, strict: false)..feed(utf8.encode('abcd'));
    expect(vt.errors, ['print after last column wrapped']);
    expect(vt.printWraps, 1);
    expect(vt.lines, ['abc', 'd']);
  });
}
