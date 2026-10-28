// Konsole's lines (TerminalCaps.konsoleLines): as long as what was written
// on them; DCH appends its blanks, in the current colours, at that length —
// mid-row on a short line — not at the right margin, and ICH inserts them
// in the default colours. The emulator models it (Vt.konsoleLines); the
// presenter shifts a row there only with the default SGR, which comes out
// right on a terminal taken for Konsole that does as xterm does too.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/src/presenter.dart';
import 'package:twk_core/src/style.dart';
import 'package:twk_test/vt.dart';

import 'support/harness.dart';

const _konsole = TerminalCaps(konsoleLines: true);

/// The terminals a row is shifted on: Konsole, a terminal taken for Konsole
/// that does as xterm does (BCE), and xterm.
const List<(String, TerminalCaps, bool)> _terminals = [
  ('Konsole', _konsole, true),
  ('taken for Konsole', _konsole, false),
  ('xterm', TerminalCaps(), false),
];

/// Each cell of row [y]: its text, or `#` for a blank with a background.
String _row(Vt vt, int y) => [
  for (var x = 0; x < vt.width; x++)
    if (vt.cell(x, y).bg != 0) '#' else vt.cell(x, y).text,
].join();

void main() {
  test("the emulator's Konsole lines: DCH ends the line it holds", () {
    final konsole = Vt(12, 1, konsoleLines: true);
    final xterm = Vt(12, 1);
    for (final vt in [konsole, xterm]) {
      vt.feed(utf8.encode('abcdefgh\x1b[1G\x1b[44m\x1b[2P'));
    }
    expect(_row(xterm, 0), 'cdefgh    ##');
    expect(_row(konsole, 0), 'cdefgh##    ');

    // past its end nothing moves; an erasure to the margin in the default
    // colours cuts it back, one in a colour stretches it to the margin
    konsole.feed(utf8.encode('\x1b[10G\x1b[P\x1b[m\x1b[5G\x1b[K\x1b[1G\x1b[P'));
    expect(_row(konsole, 0), 'def         ');
    konsole.feed(utf8.encode('\x1b[44m\x1b[6G\x1b[K\x1b[m\x1b[1G\x1b[2P'));
    expect(_row(konsole, 0), 'f  #######  ');
  });

  test('a row shifted left under a coloured SGR keeps its colours', () {
    // the relayout highlight of `twk run` on Konsole: a coloured cell on a
    // row, then a deletion on the next, whose line stops short of the margin
    // and whose right edge is to take that colour
    for (final (name, caps, lines) in _terminals) {
      final konsole = caps.konsoleLines;
      final hs = Harness(30, 2, caps: caps, vtKonsoleLines: lines);
      final blue = hs.styles.pen(const Pen(bg: Color.blue));
      hs.canvas
        ..text(0, 0, 'title', hs.pens[0])
        ..text(0, 1, '0123456789abcdefghij', hs.pens[0]);
      hs.frame();
      hs.canvas
        ..text(29, 0, ' ', blue)
        ..text(2, 1, '56789abcdefghij     ', hs.pens[0])
        ..text(27, 1, '   ', blue);
      hs.frame();
      final out = latin1.decode(hs.presenter.out.view);
      expect(hs.mismatches(), isEmpty, reason: '$name: $out');
      expect(hs.presenter.stats.shiftedRows, 1, reason: out);
      // on Konsole the DCH comes after a reset, elsewhere in the colour
      expect(
        out,
        contains(
          konsole ? ' \x1b[m\x1b[2;3H\x1b[3P' : '\x1b[44m \x1b[2;3H\x1b[3P',
        ),
      );
    }
  });

  test('a row shifted right under a coloured SGR inserts default blanks', () {
    // Konsole's ICH inserts them in the default colours whatever the SGR,
    // xterm's in the current background: only after a reset are both alike
    for (final (name, caps, lines) in _terminals) {
      final konsole = caps.konsoleLines;
      final hs = Harness(30, 2, caps: caps, vtKonsoleLines: lines);
      final blue = hs.styles.pen(const Pen(bg: Color.blue));
      hs.canvas
        ..text(0, 0, 'title', hs.pens[0])
        ..text(0, 1, '0123456789abcdefghij', hs.pens[0]);
      hs.frame();
      hs.canvas
        ..text(29, 0, ' ', blue)
        ..text(2, 1, '   23456789abcdefghij', hs.pens[0]);
      hs.frame();
      final out = latin1.decode(hs.presenter.out.view);
      expect(hs.mismatches(), isEmpty, reason: '$name: $out');
      expect(hs.presenter.stats.shiftedRows, 1, reason: out);
      // on Konsole the ICH comes after a reset; elsewhere in the colour,
      // whose blanks are then written over
      expect(
        out,
        contains(
          konsole ? ' \x1b[m\x1b[2;3H\x1b[3@' : '\x1b[44m \x1b[2;3H\x1b[3@',
        ),
      );
    }
  });
}
