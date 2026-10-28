// Canvas and surface edge cases the random scenes don't reach.
import 'dart:math';

import 'package:test/test.dart';
import 'package:twk_core/src/canvas.dart';
import 'package:twk_core/src/style.dart';
import 'package:twk_core/src/surface.dart';

void main() {
  late StyleTable styles;
  late Surface s;
  late Canvas cv;
  late int pen;
  setUp(() {
    styles = StyleTable();
    s = Surface(10, 2);
    cv = Canvas(s, styles, GlyphTable());
    pen = styles.pen(const Pen(fg: Color.red, bg: Color.blue));
  });

  test('covering the first half of a wide glyph damages the second', () {
    cv.text(2, 0, '你', pen);
    s.clearDamage();
    cv.fill(2, 0, 1, 1, pen, 0x41);
    expect(s.cells[3], kBlank);
    expect((s.dirtyLo[0], s.dirtyHi[0]), (2, 4));

    cv.text(2, 1, '你', pen);
    s
      ..clearDamage()
      ..blit(Surface(1, 1), 0, 0, 1, 1, 2, 1);
    expect(s.cells[13], kBlank);
    expect((s.dirtyLo[1], s.dirtyHi[1]), (2, 4));
  });

  test('blit within one surface copies overlapping rectangles intact', () {
    final glyphs = GlyphTable();
    final surface = Surface(4, 4);
    final canvas = Canvas(surface, styles, glyphs);
    List<String> rows() => [
      for (var y = 0; y < 4; y++)
        [
          for (var x = 0; x < 4; x++)
            if (surface.cells[y * 4 + x] & kCont == 0)
              glyphs.stringOf(surface.cells[y * 4 + x]),
        ].join(),
    ];
    for (var y = 0; y < 4; y++) {
      canvas.text(0, y, 'r$y', pen);
    }
    surface.blit(surface, 0, 0, 4, 3, 0, 1); // down by one row
    expect(rows(), ['r0  ', 'r0  ', 'r1  ', 'r2  ']);
    surface.blit(surface, 0, 0, 3, 4, 1, 0); // right by one column
    expect(rows(), ['rr0 ', 'rr0 ', 'rr1 ', 'rr2 ']);
  });

  test(
    'a self-blit equals a blit from a copy, rectangles off the edges too',
    () {
      final rnd = Random(3);
      for (var t = 0; t < 300; t++) {
        final a = Surface(8, 4);
        final cv = Canvas(a, styles, GlyphTable());
        for (var y = 0; y < 4; y++) {
          cv.text(rnd.nextInt(3) - 1, y, '你a好b', pen);
        }
        final b = Surface(8, 4)..blit(a, 0, 0, 8, 4, 0, 0);
        final copy = Surface(8, 4)..blit(a, 0, 0, 8, 4, 0, 0);
        final (sx, sy, w, h) = (
          rnd.nextInt(12) - 2,
          rnd.nextInt(6) - 1,
          rnd.nextInt(10),
          rnd.nextInt(6),
        );
        final (dx, dy) = (rnd.nextInt(12) - 2, rnd.nextInt(6) - 1);
        a.blit(a, sx, sy, w, h, dx, dy);
        b.blit(copy, sx, sy, w, h, dx, dy);
        expect(a.cells, b.cells, reason: 'blit($sx,$sy,$w,$h -> $dx,$dy)');
        expect(a.styles, b.styles);
      }
    },
  );

  test('a range of a glyph buffer draws as a run of a copy of it does', () {
    String row(Surface s) => [
      for (var x = 0; x < s.width; x++)
        switch (s.cells[x]) {
          final c when c & kCont != 0 => '>',
          kBlank => '.',
          final c => String.fromCharCode(c & kGlyphMask),
        },
    ].join();
    final shaped = cv.shape('ab你c好d');
    final g = shaped.glyphs;
    for (var start = 0; start <= g.length; start++) {
      for (var end = start; end <= g.length; end++) {
        for (var x = -2; x < 4; x++) {
          final a = Surface(6, 1);
          final b = Surface(6, 1);
          final ca = Canvas(a, styles, GlyphTable())..clipRect(1, 0, 4, 1);
          final cb = Canvas(b, styles, GlyphTable())..clipRect(1, 0, 4, 1);
          final copy = cb.shape('ab你c好d').glyphs.sublist(start, end);
          final wa = ca.runRange(x, 0, g, start, end, pen);
          final wb = cb.run(x, 0, GlyphRun(copy, 0), pen);
          final at = '[$start, $end) at $x';
          expect(row(a), row(b), reason: at);
          expect(a.styles, b.styles, reason: at);
          expect((a.dirtyLo[0], a.dirtyHi[0]), (b.dirtyLo[0], b.dirtyHi[0]));
          expect(wa, wb, reason: at);
        }
      }
    }
    expect(cv.runRange(0, 0, g, 2, 4, pen), 3, reason: '你c');
    expect(row(s), '你>c.......');
  });

  test('a wide fill keeps its columns wherever the clip cuts it', () {
    String row() => [
      for (var x = 0; x < 6; x++)
        switch (s.cells[x]) {
          final c when c & kWide != 0 => 'W',
          final c when c & kCont != 0 => '>',
          kBlank => '.',
          _ => '?',
        },
    ].join();
    final wide = Surface(6, 1);
    s = wide;
    cv = Canvas(wide, styles, GlyphTable())..text(-1, 0, '你你你你', pen);
    final text = row();
    cv
      ..fill(0, 0, 6, 1, pen) // blank
      ..fill(-1, 0, 8, 1, pen, 0x4F60);
    expect(row(), text, reason: 'same columns as text');
    expect(row(), '.W>W>.');

    cv
      ..fill(0, 0, 6, 1, pen)
      ..save()
      ..clipRect(1, 0, 5, 1)
      ..fill(0, 0, 6, 1, pen, 0x4F60)
      ..restore();
    expect(row(), '..W>W>', reason: 'the clip cuts the glyph at 0-1');
  });

  test('saves nest deeper than the stack first holds, and come back in '
      'order, frame after frame', () {
    final big = Surface(80, 1);
    final c = Canvas(big, styles, GlyphTable());
    for (var frame = 0; frame < 2; frame++) {
      c.reset();
      // 40 saves deep, each a column further and a column narrower
      for (var k = 0; k < 40; k++) {
        c
          ..save()
          ..translate(1, 0)
          ..clipRect(0, 0, 80 - 2 * k, 1);
      }
      for (var k = 39; k >= 0; k--) {
        c
          ..restore()
          // the origin and the clip as save k found them: a cell at column
          // 0 lands at k, inside the clip
          ..fill(0, 0, 1, 1, pen, 0x30 + k % 10);
      }
      expect(
        [for (var x = 0; x < 40; x++) big.cells[x] & 0x1FFFFF],
        [for (var x = 0; x < 40; x++) 0x30 + x % 10],
        reason: 'frame $frame',
      );
    }
  });

  test('a glyph table keeps the id and text of every cluster as it grows', () {
    final glyphs = GlyphTable();
    // clusters of a CJK letter and a combining mark, picked at random: some
    // share a slot of the table
    final random = Random(1);
    final clusters = {
      for (var i = 0; i < 5000; i++)
        String.fromCharCodes([
          0x4E00 + random.nextInt(20000),
          0x300 + random.nextInt(112),
        ]),
    }.toList();
    final ids = [for (final c in clusters) glyphs.intern(c, 0, c.length)];
    expect(ids.toSet(), hasLength(clusters.length));
    expect(glyphs.length, clusters.length);
    for (var i = 0; i < clusters.length; i++) {
      final c = clusters[i];
      expect(glyphs.stringOf(ids[i]), c);
      expect(glyphs.intern('x$c', 1, c.length + 1), ids[i], reason: c);
    }
    expect(glyphs.length, clusters.length, reason: 'nothing interned twice');
  });
}
