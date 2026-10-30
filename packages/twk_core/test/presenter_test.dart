// Presenter edge cases the random scenes don't reach.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/src/canvas.dart';
import 'package:twk_core/src/presenter.dart';
import 'package:twk_core/src/style.dart';
import 'package:twk_core/src/surface.dart';

import 'support/harness.dart';

void main() {
  test('decorated blanks are rewritten when only their colour changes', () {
    for (final attrs in [Attr.strike, Attr.overline, Attr.underline]) {
      final hs = Harness(16, 1);
      final a = hs.styles.pen(
        Pen(fg: Color.white, bg: Color.black, attrs: attrs),
      );
      final b = hs.styles.pen(
        Pen(fg: Color.brightBlack, bg: Color.black, attrs: attrs),
      );
      hs.canvas.text(0, 0, 'buy      milk', a);
      hs.frame();
      hs.canvas.text(0, 0, 'buy      milk', b);
      hs.frame();
      expect(hs.mismatches(), isEmpty, reason: 'attrs $attrs');
    }
  });

  test('a one-column scroll rectangle is not replayed with DECSLRM', () {
    final hs = Harness(10, 4, caps: const TerminalCaps(leftRightMargins: true));
    for (var y = 0; y < 4; y++) {
      hs.canvas.text(0, y, 'row$y abcd', hs.pens[1]);
    }
    hs.frame();
    hs.surface.scrollRect(5, 6, 0, 4, 1);
    hs.canvas.text(5, 3, 'z', hs.pens[1]);
    hs.frame();
    expect(hs.vt.errors, isEmpty);
    expect(hs.mismatches(), isEmpty);
  });

  test('a hidden cursor rests where the shown one would on the whole '
      'screen, not where the frame wrote last, where it is asked to', () {
    // a terminal that marks the cursor's row (iTerm2's cursor guide)
    final hs = Harness(20, 4);
    hs.presenter
      ..restsCursor = true
      ..cursorX = 3
      ..cursorY = 1;
    for (final (x, y) in [(10, 3), (15, 0), (0, 2)]) {
      hs.canvas.text(x, y, 'ab', hs.pens[1]);
      hs.frame();
      expect(hs.vt.cursorVisible, isFalse);
      expect((hs.vt.cx, hs.vt.cy), (3, 1), reason: '($x, $y)');
    }
    // nothing changed: not a byte, the cursor where it is
    expect(hs.frame(), 0);
    expect(hs.mismatches(), isEmpty);
  });

  test('a hidden cursor not asked to rest stays where the frame wrote '
      'last, no byte spent on it', () {
    final hs = Harness(20, 4);
    hs.presenter
      ..cursorX = 3
      ..cursorY = 1;
    hs.canvas.text(10, 3, 'ab', hs.pens[1]);
    hs.frame();
    expect((hs.vt.cx, hs.vt.cy), (12, 3));
    expect(hs.mismatches(), isEmpty);
  });

  test('inline, a hidden cursor stays where the region left it', () {
    final hs = Harness.inline(20, 3, screenHeight: 10)
      ..presenter.restsCursor = true
      ..presenter.cursorX = 3;
    hs.canvas.text(10, 2, 'ab', hs.pens[1]);
    hs.frame();
    expect(hs.vt.cx, isNot(3));
    expect(hs.mismatches(), isEmpty);
  });

  test('invalidate() forgets the cursor state too', () {
    final hs = Harness(10, 2);
    hs.presenter.cursorVisible = false;
    hs.canvas.text(0, 0, 'a', hs.pens[1]);
    hs.frame();
    // another program ran meanwhile and showed the cursor as a bar
    hs.vt.feed(Uint8List.fromList('\x1b[?25h\x1b[6 q'.codeUnits));
    hs.presenter.invalidate();
    hs.frame();
    expect(hs.vt.cursorVisible, isFalse);

    hs.presenter
      ..cursorVisible = true
      ..cursorShape = CursorShape.block;
    hs.frame();
    hs.vt.feed(Uint8List.fromList('\x1b[6 q'.codeUnits));
    hs.presenter.invalidate();
    hs.frame();
    expect(hs.vt.cursorShape, CursorShape.block.code);
  });

  test('hyperlink targets keep non-ASCII characters, percent-encoded', () {
    final hs = Harness(10, 1);
    final pen = hs.styles.pen(
      const Pen(link: 'https://ru.wikipedia.org/wiki/Мир a\x07'),
    );
    hs.canvas.text(0, 0, 'link', pen);
    hs.frame();
    expect(
      latin1.decode(hs.presenter.out.view),
      contains(
        '\x1b]8;;https://ru.wikipedia.org/wiki/%D0%9C%D0%B8%D1%80%20a%07'
        '\x1b\\',
      ),
    );
  });

  test('underline colors use the colon form of SGR 58', () {
    final hs = Harness(10, 1);
    final rgb = hs.styles.pen(
      const Pen(attrs: Attr.underline, underlineColor: Color.rgb(1, 2, 3)),
    );
    final indexed = hs.styles.pen(
      const Pen(attrs: Attr.underline, underlineColor: Color.indexed(200)),
    );
    hs.canvas
      ..text(0, 0, 'a', rgb)
      ..text(2, 0, 'b', indexed);
    hs.frame();
    final out = latin1.decode(hs.presenter.out.view);
    expect(out, contains('58:2::1:2:3'));
    expect(out, contains('58:5:200'));
    expect(hs.mismatches(), isEmpty);
  });

  test('fills never put side by side what a terminal would join', () {
    // Hangul L jamo, spacing mark, width-1 Extend, Prepend, soft hyphen,
    // regional indicator
    for (final cp in [0x1100, 0x093F, 0xFF9E, 0x0600, 0xAD, 0x1F1E6]) {
      final hs = Harness(12, 1);
      hs.canvas
        ..fill(0, 0, 6, 1, hs.pens[1], cp)
        ..text(6, 0, 'XYZ', hs.pens[1]);
      hs.frame();
      expect(hs.vt.errors, isEmpty, reason: cp.toRadixString(16));
      expect(hs.mismatches(), isEmpty, reason: cp.toRadixString(16));
    }
    // what stands alone still fills
    for (final cp in [0x2500, 0x2591, 0x78, 0x4F60]) {
      final hs = Harness(12, 1);
      hs.canvas.fill(0, 0, 6, 1, hs.pens[1], cp);
      expect(hs.surface.cells[0] & 0x1FFFFF, cp);
    }
  });

  test('a frame that only moves the visible cursor leaves it shown', () {
    final hs = Harness(20, 3);
    hs.canvas.text(0, 0, 'hello', hs.pens[1]);
    hs.presenter
      ..cursorVisible = true
      ..cursorX = 2
      ..cursorY = 1;
    hs.frame();
    // nothing drawn: the cursor jumps once, hiding it prevents no flicker
    hs.presenter.cursorX = 9;
    hs.frame();
    expect(_out(hs), '\x1b[7C');
    hs.presenter.cursorShape = CursorShape.bar;
    hs.frame();
    expect(_out(hs), '\x1b[6 q');
    expect(hs.vt.cursorVisible, isTrue);
    expect((hs.vt.cx, hs.vt.cy), (9, 1));
    // a cell drawn: hidden while the presenter moves around to draw it
    hs.canvas.text(0, 2, 'x', hs.pens[1]);
    hs.frame();
    expect(_out(hs), startsWith('\x1b[?25l'));
    expect(_out(hs), endsWith('\x1b[?25h'));
    expect(hs.vt.cursorVisible, isTrue);
    expect((hs.vt.cx, hs.vt.cy), (9, 1));
  });

  test('a blank before text takes the text SGR when it looks the same', () {
    final hs = Harness(30, 2)..frame();
    // the text pens have no background: the text keeps the fill's
    hs.canvas
      ..fill(0, 0, 30, 1, hs.pens[1])
      ..text(1, 0, 'abc', hs.pens[2])
      ..fill(0, 1, 30, 1, hs.pens[3])
      ..text(14, 1, 'def', hs.pens[4]);
    hs.frame();
    expect(hs.mismatches(), isEmpty);
    // one SGR per row: the blank (and the ECH of the blank run) is drawn
    // in the SGR its text needs, the tail erased in it too
    final sgrs = _sgrs(_out(hs));
    expect(sgrs, hasLength(2));
    expect(sgrs[0], contains('38;2;255;140;0;48;2;20;20;30'));
    expect(sgrs[1], contains('31;48;2;38;44;58'));
    // the row repainted, only the blank changed: it keeps its own SGR (the
    // glyph's would be spent on one blank)
    hs.canvas.fill(0, 0, 1, 1, hs.pens[3]);
    hs.frame();
    hs.canvas
      ..fill(0, 0, 30, 1, hs.pens[1])
      ..text(1, 0, 'abc', hs.pens[2]);
    hs.frame();
    expect(hs.mismatches(), isEmpty);
    expect(_out(hs), isNot(contains('255;140;0')));
  });

  test('a parameter equal to its default is left out', () {
    final hs = Harness(30, 4);
    for (var y = 0; y < 4; y++) {
      hs.canvas.text(0, y, 'row $y of the quick brown fox', hs.pens[1]);
    }
    hs.presenter
      ..cursorVisible = true
      ..cursorX = 5
      ..cursorY = 1;
    hs.frame();
    String moveCursor(int x, int y) {
      hs.presenter
        ..cursorX = x
        ..cursorY = y;
      hs.frame();
      expect((hs.vt.cx, hs.vt.cy), (x, y));
      return _out(hs);
    }

    // CUF, CUB, CUU and CUD by 1
    expect(moveCursor(6, 1), '\x1b[C');
    expect(moveCursor(5, 1), '\x1b[D');
    expect(moveCursor(5, 0), '\x1b[A');
    expect(moveCursor(5, 1), '\x1b[B');
    // ICH 1 and DCH 1
    hs.canvas.text(0, 2, 'row 2 oxf the quick brown fox', hs.pens[1]);
    hs.frame();
    expect(_out(hs), contains('\x1b[@'));
    hs.canvas
      ..fill(0, 2, 30, 1, hs.pens[10])
      ..text(0, 2, 'row 2 of the quick brown fox', hs.pens[1]);
    hs.frame();
    expect(_out(hs), contains('\x1b[P'));
    expect(hs.mismatches(), isEmpty);
    // SGR 0 before SU 1 and SD 1; CUP to column 1 without the column
    hs.canvas.text(29, 3, '!', hs.pens[1]);
    hs.frame();
    hs.surface.scrollRows(0, 4, 1);
    hs.canvas.text(0, 3, 'new row', hs.pens[1]);
    hs.frame();
    expect(_out(hs), contains('\x1b[m\x1b[1;4r\x1b[S\x1b[r\x1b[4H'));
    hs.surface.scrollRows(0, 4, -1);
    hs.canvas.text(0, 0, 'top', hs.pens[1]);
    hs.frame();
    expect(_out(hs), contains('\x1b[m\x1b[1;4r\x1b[T\x1b[r\x1b[H'));
    expect(hs.mismatches(), isEmpty);
  });

  test('reserved cells are never written or erased', () {
    var touched = 0;
    for (var seed = 0; seed < 300; seed++) {
      final rnd = Random(seed);
      final w = 4 + rnd.nextInt(20);
      final h = 1 + rnd.nextInt(6);
      final hs = Harness(w, h);
      final ix = rnd.nextInt(w - 2);
      final iy = rnd.nextInt(h);
      final iw = 1 + rnd.nextInt(min(4, w - ix));
      // drawn outside the cell model, the cursor put back where the
      // presenter left it
      void image() => hs.vt.feed(
        Uint8List.fromList(
          '\x1b7\x1b[${iy + 1};${ix + 1}H${'@' * iw}\x1b8'.codeUnits,
        ),
      );
      hs.canvas.reserve(ix, iy, iw, 1);
      hs.frame();
      image(); // drawn outside the cell model
      for (var f = 0; f < 12; f++) {
        for (var k = rnd.nextInt(5); k > 0; k--) {
          final pen = hs.pens[rnd.nextInt(hs.pens.length)];
          final x = rnd.nextInt(w + 4) - 2;
          final y = rnd.nextInt(h);
          if (rnd.nextBool()) {
            hs.canvas.text(x, y, samples[rnd.nextInt(samples.length)], pen);
          } else {
            hs.canvas.fill(x, y, rnd.nextInt(w + 1), 1 + rnd.nextInt(2), pen);
          }
        }
        hs.canvas.reserve(ix, iy, iw, 1);
        hs.frame();
        expect(hs.mismatches(), isEmpty);
        for (var x = ix; x < ix + iw; x++) {
          if (hs.vt.cell(x, iy).text != '@') {
            touched++;
            image();
            break;
          }
        }
      }
      // released: the cells are drawn again
      hs.canvas.fill(0, iy, w, 1, hs.pens[1], 0x78);
      hs.frame();
      expect(hs.mismatches(), isEmpty);
    }
    expect(touched, 0);
  });

  test('a growing inline region writes only the row it gains', () {
    final hs = Harness.inline(12, 2, screenHeight: 6, history: [r'$ run']);
    void paint(List<String> rows) {
      for (var y = 0; y < rows.length; y++) {
        hs.canvas.text(0, y, rows[y], hs.pens[2]);
      }
      hs.frame();
    }

    paint(['first', 'second']);
    hs.resizeRegion(3);
    paint(['first', 'second', 'third']);
    final out = utf8.decode(hs.presenter.out.view);
    expect(out, contains('\n'));
    expect(out, isNot(contains('first')));
    expect(out, isNot(contains('second')));
    expect(out, contains('third'));
    expect(hs.mismatches(), isEmpty);
    expect(hs.vt.lines, [r'$ run', 'first', 'second', 'third', '', '']);
  });

  test('an inline region hands the screen back below itself, or '
      'erased', () {
    for (final clear in [false, true]) {
      final hs = Harness.inline(12, 2, screenHeight: 6, history: [r'$ run']);
      expect(hs.presenter.leave(clear: clear), 0, reason: 'no frame yet');
      hs.canvas
        ..text(0, 0, 'first', hs.pens[2])
        ..text(0, 1, 'second', hs.pens[2]);
      hs.presenter
        ..cursorVisible = true
        ..cursorX = 3
        ..cursorY = 0;
      hs.frame();
      hs.vt.feed(
        hs.presenter.out.view.sublist(0, hs.presenter.leave(clear: clear)),
      );
      expect(hs.vt.lines, [
        r'$ run',
        if (!clear) ...['first', 'second'],
        '',
        '',
        '',
        if (clear) ...['', ''],
      ]);
      expect((hs.vt.cx, hs.vt.cy), (0, clear ? 1 : 3), reason: 'clear $clear');
      expect(hs.vt.fg | hs.vt.bg | hs.vt.attrs, 0, reason: 'SGR reset');
    }
  });

  group('rows committed to the history', () {
    /// An inline harness whose region shows [live], one row each.
    Harness region(
      List<String> live, {
      required int screenHeight,
      int width = 12,
      List<String> history = const [r'$ run'],
    }) {
      final hs = Harness.inline(
        width,
        live.length,
        screenHeight: screenHeight,
        history: history,
      );
      for (var y = 0; y < live.length; y++) {
        hs.canvas.text(0, y, live[y], hs.pens[2]);
      }
      hs.frame();
      return hs;
    }

    /// [lines] on rows of their own, as wide as [hs]'s region.
    Surface rowsOf(Harness hs, List<(String, int)> lines, {int? width}) {
      final rows = Surface(width ?? hs.surface.width, lines.length);
      final c = Canvas(rows, hs.styles, hs.glyphs);
      for (var y = 0; y < lines.length; y++) {
        c.text(0, y, lines[y].$1, lines[y].$2);
      }
      return rows;
    }

    void expectIntact(Harness hs) {
      expect(hs.mismatches(), isEmpty, reason: 'the region');
      expect(hs.committedMismatches(), isEmpty, reason: 'committed rows');
      expect(hs.notBlankBelow(), isEmpty);
      expect(hs.frame(), 0, reason: 'nothing left to write');
    }

    test('go in above the region, which moves down as it is', () {
      final hs = region(['live 1', 'live 2'], screenHeight: 8);
      hs.commit(
        rowsOf(hs, [('done 你好', hs.pens[8]), ('a link', hs.pens[11])]),
      );
      hs.frame();
      expect(hs.vt.lines, [
        r'$ run',
        'done 你好',
        'a link',
        'live 1',
        'live 2',
        '',
        '',
        '',
      ]);
      final out = _out(hs);
      expect(out, contains('\x1b[2L'));
      expect(out, isNot(contains('live')), reason: 'not drawn again');
      expect(hs.presenter.stats.committedRows, 2);
      expectIntact(hs);
    });

    test('more than the screen has room for go in a few at a time, in '
        'order, pushing the history into the scrollback', () {
      final hs = region(
        ['live 1', 'live 2', 'live 3'],
        screenHeight: 6,
        history: ['h1', 'h2'],
      );
      hs.commit(rowsOf(hs, [for (var i = 0; i < 7; i++) ('c$i', hs.pens[2])]));
      hs.frame();
      expect(hs.vt.lines, [
        'h1',
        'h2',
        for (var i = 0; i < 7; i++) 'c$i',
        'live 1',
        'live 2',
        'live 3',
      ]);
      final out = _out(hs);
      expect('\x1b[3L'.allMatches(out), hasLength(2));
      expect(out, contains('\x1b[L'));
      expect(out, isNot(contains('live')));
      expectIntact(hs);
    });

    test('are printed over the region, which is drawn again below them, '
        'when the screen height is unknown or the region fills it', () {
      for (final known in [0, 3]) {
        final hs = region(['live 1', 'live 2', 'live 3'], screenHeight: 3);
        hs.presenter.screenHeight = known;
        hs.commit(
          rowsOf(hs, [('done 1', hs.pens[5]), ('done 2', hs.pens[2])]),
        );
        hs.frame();
        expect(hs.vt.lines, [
          r'$ run',
          'done 1',
          'done 2',
          'live 1',
          'live 2',
          'live 3',
        ], reason: 'screen height $known');
        expect(hs.vt.history, hasLength(3));
        expect(_out(hs), contains('live 1'));
        expectIntact(hs);
      }
    });

    test('before the first frame go where the region would have '
        'started', () {
      for (final atLineStart in [true, false]) {
        final hs = Harness.inline(
          12,
          1,
          screenHeight: 6,
          history: ['h1', r'$ run'],
          atLineStart: atLineStart,
        );
        hs.canvas.text(0, 0, 'live', hs.pens[2]);
        hs.commit(rowsOf(hs, [('first', hs.pens[2])]));
        hs.frame();
        expect(hs.vt.lines, [
          'h1',
          r'$ run',
          'first',
          'live',
          '',
          '',
        ], reason: 'at line start $atLineStart');
        expectIntact(hs);
      }
    });

    test('rows wider or narrower than the region are cut or padded, as '
        'are rows pending when the width changes', () {
      final hs = region(['live'], screenHeight: 6);
      hs
        ..commit(rowsOf(hs, [('abcdefghijk你好', hs.pens[8])], width: 15))
        ..commit(rowsOf(hs, [('short', hs.pens[8])], width: 5));
      hs.frame();
      expect(hs.vt.lines.skip(1).take(3), ['abcdefghijk', 'short', 'live']);
      hs
        ..commit(rowsOf(hs, [('abcdefgh你', hs.pens[8])]))
        ..resizeTerminal(9, 6)
        ..canvas.text(0, 0, 'live', hs.pens[2])
        ..frame();
      expect(hs.vt.lines.skip(1).take(4), [
        'abcdefghi',
        'short',
        'abcdefgh',
        'live',
      ]);
      expectIntact(hs);
    });

    test('only an inline region takes them', () {
      final hs = Harness(10, 3);
      expect(() => hs.presenter.commit(Surface(10, 1)), throwsStateError);
    });
  });
}

/// The bytes of the last frame, one character per byte.
String _out(Harness hs) => latin1.decode(hs.presenter.out.view);

/// The SGR sequences in [out], in order.
List<String> _sgrs(String out) => [
  for (final m in RegExp(r'\x1b\[[0-9;:]*m').allMatches(out)) m[0]!,
];
