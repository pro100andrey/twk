// A fixed viewport through the test emulator: random scenes drawn in a
// rectangle of a screen whose every cell showed a pattern before, which
// must still show it after each frame and after the screen is handed back.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/src/presenter.dart';
import 'package:twk_core/src/surface.dart';
import 'package:twk_test/vt.dart';

import '../support/harness.dart';
import 'pattern.dart';

/// A presenter drawing a harness's surface in a viewport of an emulator
/// of `screenWidth` x `screenHeight` cells, which shows a pattern first
/// ([paintPattern]), its cursor at `cursor`.
final class Fixture {
  Fixture(
    this.view,
    int screenWidth,
    int screenHeight, {
    TerminalCaps caps = const TerminalCaps(),
    this.cursor = (3, 0),
  }) : hs = Harness(view.width, view.height),
       vt = Vt(screenWidth, screenHeight) {
    presenter = Presenter(
      view.width,
      view.height,
      hs.styles,
      hs.glyphs,
      caps: caps,
      viewport: view,
    )..screenWidth = screenWidth;
    paintPattern(vt, cursor);
    _outside = _shownOutside();
  }

  final Viewport view;
  final Harness hs;
  final Vt vt;
  late final Presenter presenter;

  /// Where the cursor was before the first frame.
  final (int, int) cursor;

  /// What the cells outside the viewport showed before the first frame.
  late final Map<(int, int), String> _outside;

  Surface get surface => hs.surface;

  Map<(int, int), String> _shownOutside() => shownOutside(vt, _inside);

  bool _inside(int x, int y) =>
      x >= view.left &&
      y >= view.top &&
      x < view.left + presenter.width &&
      y < view.top + presenter.height;

  /// Presents the surface and feeds the bytes to the emulator; returns
  /// them.
  String frame() {
    presenter.present(surface);
    final bytes = Uint8List.fromList(presenter.out.view);
    vt.feed(bytes);
    return latin1.decode(bytes);
  }

  /// Hands the screen back ([Presenter.leave]); returns the bytes.
  String leave({bool clear = false}) {
    presenter.leave(clear: clear);
    final bytes = Uint8List.fromList(presenter.out.view);
    vt.feed(bytes);
    return latin1.decode(bytes);
  }

  /// Cells outside the viewport that no longer show what they did.
  List<String> outsideChanges() => changes(_outside, _shownOutside());

  /// Cells of the viewport that don't show the surface's: glyph, its
  /// half, background, and a glyph's foreground. A glyph whose width
  /// terminals disagree on that could reach past the viewport's right edge
  /// must be blanks.
  List<String> mismatches() {
    final out = <String>[];
    final w = surface.width;
    final short = view.left + w != vt.width;
    for (var y = 0; y < surface.height; y++) {
      for (var x = 0; x < w; x++) {
        final c = surface.cells[y * w + x];
        final s = surface.styles[y * w + x];
        final v = vt.cell(view.left + x, view.top + y);
        if ((c & kSkip) != 0) {
          continue;
        }
        String? why;
        final lead = (c & kCont) != 0 ? surface.cells[y * w + x - 1] : c;
        final clipped =
            short &&
            (lead & kUncertain) != 0 &&
            x - ((c & kCont) != 0 ? 1 : 0) + hs.glyphs.maxWidthOf(lead) > w;
        if (clipped) {
          why = v.text == ' ' && v.role == 0 ? null : 'not blank: "${v.text}"';
        } else if ((c & kCont) != 0) {
          why = v.role == -1 ? null : 'not a trailing half';
        } else {
          final text = hs.glyphs.stringOf(c);
          final role = (c & kWide) != 0 ? 2 : 0;
          if (v.text != text || v.role != role) {
            why = 'want "$text"/$role, got "${v.text}"/${v.role}';
          } else if (hs.styles.bgOf(s).value != v.bg) {
            why = 'background';
          } else if (text != ' ' && hs.styles.fgOf(s).value != v.fg) {
            why = 'foreground';
          }
        }
        if (why != null) {
          out.add('($x,$y) $why');
        }
      }
    }
    return out.take(5).toList();
  }

  /// Everything the emulator found wrong.
  List<String> problems() => [
    ...vt.errors,
    if (vt.printWraps > 0) '${vt.printWraps} wraps',
    if (vt.syncDepth != 0) 'synchronized update left open',
  ];
}

/// Where the viewport is and what the terminal has.
typedef Case = (String, Viewport, int, int, TerminalCaps);

const _cases = <Case>[
  ('in the middle', Viewport.fixed(7, 3, 20, 7), 40, 14, TerminalCaps()),
  (
    'in the middle, with margins and REP',
    Viewport.fixed(7, 3, 20, 7),
    40,
    14,
    TerminalCaps(leftRightMargins: true, repeatChar: true),
  ),
  (
    'at the right edge, unsynchronized',
    Viewport.fixed(12, 2, 28, 8),
    40,
    12,
    TerminalCaps(synchronizedOutput: false),
  ),
  (
    'as wide as the screen',
    Viewport.fixed(0, 4, 40, 8),
    40,
    14,
    TerminalCaps(),
  ),
  ('at the top left', Viewport.fixed(0, 0, 24, 6), 40, 10, TerminalCaps()),
];

void main() {
  for (final (name, view, sw, sh, caps) in _cases) {
    test('$name: random frames leave every cell outside as it was, and '
        'the cursor where it was', () {
      for (var seed = 0; seed < 12; seed++) {
        final f = Fixture(view, sw, sh, caps: caps, cursor: (5, sh - 1));
        final rnd = Random(seed);
        for (var i = 0; i < 40; i++) {
          final ops = 1 + rnd.nextInt(4);
          for (var k = 0; k < ops; k++) {
            randomOp(f.hs, rnd);
          }
          f.frame();
          final at = 'seed $seed frame $i';
          expect(f.problems(), isEmpty, reason: at);
          expect(f.outsideChanges(), isEmpty, reason: at);
          expect(f.mismatches(), isEmpty, reason: at);
          expect((f.vt.cx, f.vt.cy), (5, sh - 1), reason: at);
          expect(f.vt.autowrap, isTrue, reason: at);
        }
        f.leave();
        expect(f.outsideChanges(), isEmpty, reason: 'seed $seed, left');
        expect((f.vt.cx, f.vt.cy), (5, sh - 1));
        expect((f.vt.fg, f.vt.bg, f.vt.attrs), (0, 0, 0));
      }
    });
  }

  test('rows are addressed with the offset; a frame turns autowrap off '
      'while it draws, the first saves the cursor with SGR reset, and each '
      'puts it back at its end', () {
    final f = Fixture(const Viewport.fixed(4, 2, 6, 2), 12, 5);
    f.hs.canvas
      ..text(0, 0, 'ab', f.hs.pens[2])
      ..text(0, 1, 'cd', f.hs.pens[2]);
    final first = f.frame();
    expect(first, startsWith('\x1b[?2026h\x1b[?7l\x1b[?25l\x1b[m'));
    expect(first, contains('\x1b7\x1b[3;5H'));
    expect(first, contains('\x1b[4;5H'));
    expect(first, endsWith('\x1b[?7h\x1b[m\x1b8\x1b[?2026l'));
    f.hs.canvas.text(1, 1, 'X', f.hs.pens[1]);
    final next = f.frame();
    expect(next, isNot(contains('\x1b7')), reason: 'saved once');
    expect(next, contains('\x1b[4;6H'));
    expect(next, startsWith('\x1b[?7l'), reason: 'autowrap off again');
    expect(next, endsWith('\x1b[?7h\x1b[m\x1b8'));
    expect(f.frame(), isEmpty, reason: 'nothing changed');
  });

  test('no row is cleared, erased to its end or shifted past a viewport '
      'that ends short of the right edge', () {
    final f = Fixture(const Viewport.fixed(2, 1, 20, 3), 30, 5);
    final pen = f.hs.pens[1];
    f.hs.canvas
      ..fill(0, 0, 20, 3, pen)
      ..text(0, 0, 'the quick brown fox', pen);
    final first = f.frame();
    expect(first, isNot(contains('\x1b[2J')));
    expect(first, isNot(contains('\x1b[K')));
    // typing in the middle of the row: a tail shift elsewhere
    f.hs.canvas.text(0, 0, 'the very quick brown', pen);
    final typed = f.frame();
    expect(typed, isNot(matches(RegExp(r'\x1b\[\d*[@P]'))));
    f.hs.canvas.fill(4, 1, 16, 1, pen);
    f.frame();
    expect(f.problems(), isEmpty);
    expect(f.outsideChanges(), isEmpty);
    expect(f.mismatches(), isEmpty);
  });

  test('a viewport at the right edge erases to the end of its rows', () {
    final f = Fixture(const Viewport.fixed(10, 1, 20, 3), 30, 5);
    final pen = f.hs.pens[3];
    f.hs.canvas
      ..fill(0, 0, 20, 3, pen)
      ..text(0, 0, 'ab', pen);
    expect(f.frame(), contains('\x1b[K'));
    expect(f.outsideChanges(), isEmpty);
    expect(f.mismatches(), isEmpty);
  });

  test('rows moved on the surface scroll in hardware only inside the '
      'viewport', () {
    for (final (view, caps, scroll) in [
      // as wide as the screen: DECSTBM over its rows
      (const Viewport.fixed(0, 2, 20, 6), const TerminalCaps(), '\x1b[3;8r'),
      // narrower, with margins: DECSLRM around its columns
      (
        const Viewport.fixed(3, 2, 12, 6),
        const TerminalCaps(leftRightMargins: true),
        '\x1b[4;15s',
      ),
      // narrower, without: no scroll, the rows are rewritten
      (const Viewport.fixed(3, 2, 12, 6), const TerminalCaps(), null),
    ]) {
      final f = Fixture(view, 20, 10, caps: caps);
      for (var y = 0; y < 6; y++) {
        f.hs.canvas.text(0, y, 'line $y', f.hs.pens[1]);
      }
      f.frame();
      f.surface.scrollRows(0, 6, 2);
      f.hs.canvas
        ..text(0, 4, 'line 6', f.hs.pens[1])
        ..text(0, 5, 'line 7', f.hs.pens[1]);
      final bytes = f.frame();
      if (scroll == null) {
        expect(bytes, isNot(contains(RegExp(r'\x1b\[\d+;\d+r'))));
        expect(f.presenter.stats.scrollOps, 0);
      } else {
        expect(bytes, contains(scroll));
        expect(f.presenter.stats.scrollOps, 1);
      }
      expect(f.problems(), isEmpty);
      expect(f.outsideChanges(), isEmpty);
      expect(f.mismatches(), isEmpty);
    }
  });

  test('a glyph terminals may draw wider is blanks where it could reach '
      'past the right edge, and drawn where the screen ends', () {
    for (final (left, drawn) in [(3, false), (14, true)]) {
      final f = Fixture(Viewport.fixed(left, 0, 6, 1), 20, 2);
      f.hs.canvas.text(5, 0, '❤', f.hs.pens[1]);
      expect(f.surface.cells[5] & kUncertain, isNot(0));
      final text = utf8.decode(latin1.encode(f.frame()));
      expect(text.contains('❤'), drawn, reason: 'at $left');
      expect(f.mismatches(), isEmpty);
      expect(f.outsideChanges(), isEmpty);
    }
  });

  test('a visible cursor stays in the viewport; hidden again, it goes back '
      'where the app found it', () {
    final f = Fixture(const Viewport.fixed(4, 1, 8, 2), 16, 4, cursor: (1, 3));
    f.presenter
      ..cursorVisible = true
      ..cursorX = 2
      ..cursorY = 1;
    f.frame();
    expect((f.vt.cx, f.vt.cy, f.vt.cursorVisible), (6, 2, true));
    f.presenter.cursorVisible = false;
    expect(f.frame(), '\x1b[?7l\x1b[?25l\x1b[?7h\x1b8');
    expect((f.vt.cx, f.vt.cy, f.vt.cursorVisible), (1, 3, false));
  });

  test('handed back, the viewport stays or is erased, and the cursor goes '
      'back; the next frame saves it again where it is then', () {
    final f = Fixture(const Viewport.fixed(4, 1, 8, 2), 16, 4, cursor: (1, 3));
    f.presenter
      ..cursorVisible = true
      ..cursorX = 2;
    f.hs.canvas.text(0, 0, 'kept', f.hs.pens[2]);
    f.frame();
    expect(f.leave(), '\x1b[m\x1b8');
    expect((f.vt.cx, f.vt.cy), (1, 3));
    expect(f.vt.lines[1].substring(4, 8), 'kept');
    expect(f.leave(), isEmpty, reason: 'put back already');

    // another program moved the cursor meanwhile
    f.vt.feed(utf8.encode('\x1b[3;2H'));
    f.presenter
      ..invalidate()
      ..cursorVisible = false;
    expect(f.frame(), contains('\x1b7'));
    expect((f.vt.cx, f.vt.cy), (1, 2));
    expect(f.leave(clear: true), contains('\x1b[8X'));
    expect(f.vt.lines[1].substring(4, 12).trim(), isEmpty);
    expect((f.vt.cx, f.vt.cy), (1, 2));
    expect(f.outsideChanges(), isEmpty);
    expect(f.problems(), isEmpty);
  });

  test('nothing is handed back before the first frame', () {
    final f = Fixture(const Viewport.fixed(1, 1, 4, 2), 8, 4);
    expect(f.leave(), isEmpty);
  });
}
