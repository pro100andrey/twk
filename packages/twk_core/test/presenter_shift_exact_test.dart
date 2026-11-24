// A row shift (ICH, DCH) where frames are not atomic: every step of the
// frame is on the screen, so the presenter shifts a row there only where
// each glyph it moves lands on the cell the frame has it in. A glyph shifted
// anywhere else would show there until written over (TearCheck).
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/src/presenter.dart';
import 'package:twk_test/vt.dart';

import 'support/harness.dart';

const _noSync = TerminalCaps(synchronizedOutput: false);

/// The output of the frame from row [before] to row [after], on [caps],
/// and what it tore.
({String out, int shifted, List<String> torn}) _frame(
  TerminalCaps caps,
  String before,
  String after,
) {
  final hs = Harness(30, 1, caps: caps);
  hs.canvas.text(0, 0, before, hs.pens[0]);
  hs.frame();
  hs.canvas.text(0, 0, after.padRight(30), hs.pens[0]);
  final check = TearCheck(hs.vt)..begin();
  hs.frame();
  final torn = check.end();
  expect(hs.mismatches(), isEmpty);
  return (
    out: latin1.decode(hs.presenter.out.view),
    shifted: hs.presenter.stats.shiftedRows,
    torn: torn,
  );
}

void main() {
  test('a key typed into a row still shifts it, with no tear', () {
    final f = _frame(
      _noSync,
      '0123456789abcdefghij',
      '01X23456789abcdefghij',
    );
    expect(f.shifted, 1, reason: f.out);
    expect(f.out, contains('\x1b[@'));
    expect(f.torn, isEmpty);
  });

  test('a shift that would take glyphs to cells the frame writes over: '
      'taken where frames are atomic, the row rewritten where not', () {
    const before = 'abcdefghijklmnopqrstuvwxyz';
    const after = 'abXYZcdefghijklmnQQqrstuvwxyz';
    final synced = _frame(const TerminalCaps(), before, after);
    expect(synced.shifted, 1, reason: synced.out);
    final f = _frame(_noSync, before, after);
    expect(f.shifted, 0, reason: f.out);
    expect(f.torn, isEmpty);
  });
}
