// The emulator's Konsole lines (Vt.konsoleLines): each row as long as what
// was written or erased on it; DCH works within that length and appends its
// blanks, in the current colours, at its end.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_test/vt.dart';

/// Each cell of row [y]: its text, or `#` for a blank with a background.
String _row(Vt vt, int y) => [
  for (var x = 0; x < vt.width; x++)
    if (vt.cell(x, y).bg != 0) '#' else vt.cell(x, y).text,
].join();

void main() {
  test('a row taken back from the scrollback narrower holds no more cells '
      'than the screen is wide', () {
    final vt = Vt(
      20,
      2,
      konsoleLines: true,
      scrollback: true,
      allowLineFeed: true,
    )..feed(utf8.encode('abcdefghijklmno\x1b[2;1H\n'));
    expect(vt.history, hasLength(1));
    vt
      ..resizeKeeping(10, 3, pull: true)
      ..feed(utf8.encode('\x1b[1;3H\x1b[44m\x1b[4P'));
    expect(vt.errors, isEmpty);
    expect(_row(vt, 0), 'abghij####');
  });

  test('an erasure short of the margin stretches the line, whatever its '
      'colours', () {
    final vt = Vt(12, 1, konsoleLines: true)
      ..feed(utf8.encode('abc\x1b[6G\x1b[2X\x1b[1G\x1b[44m\x1b[P'));
    expect(vt.errors, isEmpty);
    expect(_row(vt, 0), 'bc    #     ');
  });

  test('a DCH reaching past the line deletes only up to its end', () {
    // the line ends at a wide glyph's right half; the count reaches past
    // it, onto cells the line does not hold
    final vt = Vt(12, 1, konsoleLines: true)
      ..feed(utf8.encode('ab你\x1b[1G\x1b[44m\x1b[9P'));
    expect(vt.errors, isEmpty);
    expect(_row(vt, 0), '####        ');
  });
}
