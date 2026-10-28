// Presenter behaviour at the edges a canvas doesn't draw to: damage that
// splits a wide glyph, and a fixed viewport handed back erased.
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/vt.dart';

import '../support/harness.dart';

void main() {
  test('damage that starts on the right half of a wide glyph rewrites the '
      'whole glyph', () {
    final hs = Harness(10, 1);
    hs.canvas.text(0, 0, '你好', hs.pens[1]);
    hs.frame();
    // 好 becomes 世 in the cells, damaged on its right half only
    hs.surface.cells[2] = 0x4E16 | kWide;
    hs.surface.markDirty(0, 3, 4);
    hs.frame();
    expect(hs.vt.errors, isEmpty);
    expect(hs.mismatches(), isEmpty);
    expect(hs.vt.lines.first.trimRight(), '你世');
  });

  test('damage that ends on the left half of a wide glyph rewrites the '
      'whole glyph, and knows both halves are on the terminal', () {
    final hs = Harness(10, 1);
    hs.canvas.text(0, 0, '你好', hs.pens[1]);
    hs.frame();
    final style = hs.styles.style(fg: Color.red);
    hs.surface
      ..cells[0] = 0x4E16 | kWide
      ..styles[0] = style
      ..styles[1] = style
      ..markDirty(0, 0, 1);
    hs.frame();
    expect(hs.vt.errors, isEmpty);
    expect(hs.mismatches(), isEmpty);
    expect(hs.vt.lines.first.trimRight(), '世好');
    hs.surface.markAllDirty();
    expect(hs.frame(), 0, reason: 'what the terminal shows is known');
  });

  test('a fixed viewport at the right edge is erased to the end of its rows '
      'when handed back cleared, the cells left of it kept', () {
    final vt = Vt(10, 3)
      ..feed('\x1b[1;1Hleft\x1b[2;1Hleft\x1b[3;1Hleft'.codeUnits);
    final styles = StyleTable();
    final glyphs = GlyphTable();
    final surface = Surface(6, 2);
    final presenter = Presenter(
      6,
      2,
      styles,
      glyphs,
      viewport: const Viewport.fixed(4, 1, 6, 2),
    )..screenWidth = 10;
    Canvas(surface, styles, glyphs)
      ..text(0, 0, 'view', styles.pen(const Pen()))
      ..text(0, 1, 'port', styles.pen(const Pen()));
    presenter.present(surface);
    vt.feed(Uint8List.fromList(presenter.out.view));
    expect(vt.lines, ['left', 'leftview', 'leftport']);
    final n = presenter.leave(clear: true);
    final bytes = String.fromCharCodes(presenter.out.view.sublist(0, n));
    expect(bytes, contains('\x1b[K'));
    vt.feed(presenter.out.view.sublist(0, n));
    expect(vt.lines, ['left', 'left', 'left']);
  });
}
