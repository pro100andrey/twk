// The cell under a visible block cursor is written in its own foreground:
// Konsole paints the block in it, and a blank is otherwise written in
// whatever style looks the same on a space (the foreground of the line
// written last).
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

import 'support/harness.dart';

const _own = Color.rgb(200, 200, 200);
const Color _other = Color.red;
const _bg = Color.rgb(20, 20, 30);

/// A field row "ab" and below it a status row in another foreground on the
/// same background; the cursor after "ab".
Harness _field(CursorShape? shape, {int cursorX = 3}) {
  final hs = Harness(10, 2);
  hs.presenter
    ..cursorVisible = shape != null
    ..cursorShape = shape ?? CursorShape.terminalDefault
    ..cursorX = cursorX
    ..cursorY = 0;
  _paint(hs, 'abc');
  hs.frame();
  // the status line written last: the pen the next frame starts in
  hs.canvas.text(0, 1, 'STATUS', _b);
  hs.frame();
  return hs;
}

/// A Backspace in the field of [_field]: the "b" becomes a blank.
Harness _backspaced(CursorShape? shape) {
  final hs = _field(shape);
  hs.presenter
    ..cursorX = 1
    ..cursorY = 0;
  _paint(hs, 'a c');
  hs.canvas.text(0, 1, 'STATUS', _b);
  hs.frame();
  return hs;
}

late int _a;
late int _b;

void _paint(Harness hs, String text) {
  _a = hs.styles.pen(const Pen(fg: _own, bg: _bg));
  _b = hs.styles.pen(const Pen(fg: _other, bg: _bg));
  hs.canvas
    ..fill(0, 0, hs.surface.width, 1, _a)
    ..text(0, 0, text, _a)
    ..fill(0, 1, hs.surface.width, 1, _b)
    ..text(0, 1, 'status', _b);
}

Color _fgAt(Harness hs, int x, int y) => hs.vt.cell(x, y).fgColor;

void main() {
  for (final shape in [
    CursorShape.terminalDefault,
    CursorShape.block,
    CursorShape.blinkingBlock,
  ]) {
    test('$shape: the blank a Backspace leaves under the cursor is in the '
        "field's foreground, not the status line's", () {
      final hs = _backspaced(shape);
      expect(_fgAt(hs, 1, 0), _own);
      expect(hs.vt.errors, isEmpty);
    });
  }

  test('the cursor moving over blanks written in another foreground '
      'rewrites the cell it reaches, once, and the cell it leaves nothing', () {
    final hs = _field(CursorShape.block);
    expect(_fgAt(hs, 5, 0), Color.defaultColor);
    hs.presenter.cursorX = 5;
    hs.frame();
    expect(_fgAt(hs, 5, 0), _own);
    expect(
      _fgAt(hs, 4, 0),
      Color.defaultColor,
      reason: 'the cell left is not touched',
    );
    expect(
      String.fromCharCodes(hs.presenter.out.view),
      '\x1b[?25l\x1b[6G\x1b[38;2;200;200;200m \x1b[D\x1b[?25h',
    );
    // nothing changes: not a byte, the cell is known to be its own
    expect(hs.frame(), 0);
    // another row changes: the cursor's cell is not written again
    hs.canvas.text(0, 1, 'status', _b);
    final bytes = hs.frame();
    expect(
      String.fromCharCodes(hs.presenter.out.view),
      isNot(contains('\x1b[38;2;200;200;200m')),
    );
    expect(bytes, greaterThan(0));
    expect(_fgAt(hs, 5, 0), _own);
  });

  test('a blank rewritten in the cursor row is written again', () {
    final hs = _field(CursorShape.block);
    hs.presenter.cursorX = 5;
    hs.frame();
    // the row changes elsewhere, the status line's pen written last
    hs.canvas.text(8, 0, 'x', _a);
    hs.canvas.text(0, 1, 'STATUS', _b);
    hs.frame();
    expect(_fgAt(hs, 5, 0), _own);
  });

  test('a row the terminal shifts under the cursor writes its cell again', () {
    final hs = Harness(12, 2);
    hs.presenter
      ..cursorVisible = true
      ..cursorShape = CursorShape.block
      ..cursorX = 11
      ..cursorY = 0;
    _paint(hs, 'abcdefghij');
    hs.frame();
    expect(_fgAt(hs, 11, 0), _own);
    // a character deleted in front of it: the terminal's DCH appends a
    // blank in the pen it has, in the cursor's cell
    _paint(hs, 'acdefghij');
    hs.canvas.text(0, 1, 'STATUS', _b);
    hs.frame();
    expect(
      String.fromCharCodes(hs.presenter.out.view),
      contains('\x1b[P'),
      reason: 'the row is shifted',
    );
    expect(_fgAt(hs, 11, 0), _own);
    expect(hs.vt.errors, isEmpty);
  });

  test('a cursor past the last column is the last cell', () {
    final hs = _field(CursorShape.block, cursorX: 40);
    expect(_fgAt(hs, 9, 0), _own);
    expect(hs.vt.errors, isEmpty);
  });

  test('a cell of another look under the cursor is written in it', () {
    final hs = _field(CursorShape.block);
    final c = hs.styles.pen(const Pen(fg: Color.green, bg: _bg));
    hs.canvas.text(3, 0, ' ', c);
    hs.frame();
    expect(_fgAt(hs, 3, 0), Color.green);
  });

  for (final shape in [
    CursorShape.bar,
    CursorShape.blinkingBar,
    CursorShape.underline,
    CursorShape.blinkingUnderline,
  ]) {
    test('$shape: the blank under the cursor is left as the diff wrote it', () {
      final hs = _backspaced(shape);
      expect(_fgAt(hs, 1, 0), _other);
    });
  }

  test('no cursor shown: the blank is left as the diff wrote it', () {
    final hs = _backspaced(null);
    expect(_fgAt(hs, 1, 0), _other);
  });

  test('a screen forgotten writes the cell again', () {
    final hs = _field(CursorShape.block);
    expect(hs.frame(), 0);
    hs.presenter.invalidate();
    hs.vt.feed(const [0x1b, 0x5b, 0x32, 0x4a]); // the terminal was cleared
    hs.frame();
    expect(_fgAt(hs, 2, 0), _own);
  });
}
