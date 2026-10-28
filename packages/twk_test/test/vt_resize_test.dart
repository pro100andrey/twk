// A resize of a terminal that keeps what its screen shows: rows cut or
// padded at the right, the rows above the cursor scrolled off when the
// screen gets shorter than its row, lines taken back from the scrollback
// when it gets taller and the terminal pulls them.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_test/vt.dart';

/// A normal screen of [w] × [h] fed [s].
Vt fed(String s, {int w = 10, int h = 4, bool scrollback = true}) => Vt(
  w,
  h,
  scrollback: scrollback,
  allowLineFeed: true,
)..feed(utf8.encode(s));

void main() {
  test('a screen shorter than the cursor row scrolls the rows above it into '
      'the scrollback', () {
    final vt = fed('a\r\nb\r\nc\r\nd')..resizeKeeping(10, 2);
    expect(vt.lines, ['a', 'b', 'c', 'd']);
    expect(vt.history, hasLength(2));
    expect((vt.cx, vt.cy, vt.height), (1, 1, 2));
  });

  test('without a scrollback the rows scrolled off are gone', () {
    final vt = fed('a\r\nb\r\nc\r\nd', scrollback: false)..resizeKeeping(10, 2);
    expect(vt.lines, ['c', 'd']);
    expect(vt.history, isEmpty);
  });

  test('a screen shorter than the rows below the cursor cuts them', () {
    final vt = fed('a\r\nb\r\nc\x1b[2A')..resizeKeeping(10, 2);
    expect(vt.lines, ['a', 'b']);
    expect((vt.cx, vt.cy), (1, 0));
  });

  test('a taller screen gains blank rows at the bottom', () {
    final vt = fed('a\r\nb\r\nc\r\nd')
      ..resizeKeeping(10, 2)
      ..resizeKeeping(10, 4);
    expect(vt.lines, ['a', 'b', 'c', 'd', '', '']);
    expect(vt.cy, 1);
  });

  test('a taller screen that pulls takes lines back from the scrollback', () {
    final vt = fed('a\r\nb\r\nc\r\nd')
      ..resizeKeeping(10, 2)
      ..resizeKeeping(10, 3, pull: true);
    expect(vt.lines, ['a', 'b', 'c', 'd']);
    expect(vt.history, hasLength(1));
    expect(vt.cy, 2);
    vt.resizeKeeping(10, 6, pull: true);
    expect(vt.lines, ['a', 'b', 'c', 'd', '', '']);
    expect(vt.history, isEmpty);
  });

  test('a narrower screen cuts its rows at the right, a wide glyph cut in '
      'half becomes a blank, and the cursor stays in it', () {
    final vt = fed('ab界cd')..resizeKeeping(3, 4);
    expect(vt.lines.first, 'ab');
    expect(vt.cell(2, 0).text, ' ');
    expect((vt.cx, vt.width), (2, 3));
  });

  test("Konsole's lines: a row the screen gains is empty", () {
    final vt = Vt(5, 1, konsoleLines: true, allowLineFeed: true)
      ..feed(utf8.encode('\x1b[44mab'))
      ..resizeKeeping(5, 2)
      // DCH on the empty new row leaves it as it is
      ..feed(utf8.encode('\x1b[2;1H\x1b[P'));
    expect([for (var x = 0; x < 5; x++) vt.cell(x, 1).bg], [0, 0, 0, 0, 0]);
  });
}
