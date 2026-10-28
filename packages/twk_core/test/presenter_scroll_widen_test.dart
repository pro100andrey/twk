// A scroll of a rectangle narrower than the screen on a terminal without
// left/right margins (DECSLRM): the presenter scrolls the whole rows
// (DECSTBM) when the cells outside the rectangle are fewer than those
// inside, and rewrites only those of the cells outside that the move left
// different — a log's scrollbar column, a border.
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/src/graphics.dart';
import 'package:twk_core/src/presenter.dart';

import 'support/harness.dart';

const _w = 40;
const _h = 12;

/// A log in columns [0, 39) and its scrollbar in column 39: a track with
/// the thumb on its last [thumb] rows, as while following.
void paintLog(Harness hs, {int first = 0, int thumb = 3}) {
  final h = hs.surface.height;
  for (var y = 0; y < h; y++) {
    hs.canvas.text(0, y, line(first + y), hs.pens[1]);
  }
  paintBar(hs, thumb: thumb);
}

void paintBar(Harness hs, {required int thumb}) {
  final h = hs.surface.height;
  for (var y = 0; y < h; y++) {
    hs.canvas.text(_w - 1, y, y >= h - thumb ? '█' : '│', hs.pens[2]);
  }
}

/// Log line [i]: words that differ from those of the lines around it, as
/// a real log's do.
String line(int i) => [
  for (var k = 0; k < 8; k++) _words[(i * 7 + k * 3) % _words.length],
].join(' ').padRight(_w - 1).substring(0, _w - 1);

const _words = [
  'GET',
  '/api/v1/items',
  '200',
  'took',
  '12ms',
  'user=42',
  'cache',
  'miss',
  'POST',
  'retry',
  'queue',
  'worker-3',
  'ok',
  'WARN',
  'slow',
  'db',
];

/// Appends line [i] at the bottom of the log as LogView does: the log's
/// columns move up a row, the scrollbar is drawn again.
void append(Harness hs, int i, {int thumb = 3}) {
  final h = hs.surface.height;
  hs.surface.scrollRect(0, _w - 1, 0, h, 1);
  hs.canvas.text(0, h - 1, line(i), hs.pens[1]);
  paintBar(hs, thumb: thumb);
}

void main() {
  test('an appended log line scrolls the whole rows and rewrites the '
      'scrollbar cells it moved', () {
    final hs = Harness(_w, _h);
    paintLog(hs);
    hs.frame();
    append(hs, _h);
    final bytes = hs.frame();
    expect(hs.vt.errors, isEmpty);
    expect(hs.mismatches(), isEmpty);
    expect(hs.presenter.stats.scrollOps, 1);
    expect(hs.presenter.stats.rectScrollOps, 0);
    // the new line (39 cells), DECSTBM + SU, and the two scrollbar cells
    // the move changed (the thumb's top moved up a row, its bottom left a
    // blank): not the 12 x 39 cells of the log
    expect(bytes, lessThan(200), reason: 'wrote $bytes bytes');
  });

  test('the thumb moving with the line costs its cells only', () {
    final hs = Harness(_w, _h);
    paintLog(hs, thumb: 6);
    hs.frame();
    for (var i = 0; i < 5; i++) {
      append(hs, _h + i, thumb: 5 - i);
      final bytes = hs.frame();
      expect(hs.mismatches(), isEmpty, reason: 'line $i');
      expect(hs.presenter.stats.scrollOps, 1, reason: 'line $i');
      expect(bytes, lessThan(220), reason: 'line $i wrote $bytes bytes');
    }
  });

  test('the inline mode scrolls the region rows with DL and IL', () {
    final hs = Harness.inline(_w, _h, screenHeight: 20);
    paintLog(hs);
    hs.frame();
    append(hs, _h);
    final bytes = hs.frame();
    expect(hs.vt.errors, isEmpty);
    expect(hs.mismatches(), isEmpty);
    expect(hs.historyChanges(), isEmpty);
    expect(hs.presenter.stats.scrollOps, 1);
    expect(bytes, lessThan(200), reason: 'wrote $bytes bytes');
  });

  test('more cells outside than inside: the moved rows are rewritten', () {
    final hs = Harness(_w, _h);
    paintLog(hs);
    hs.frame();
    hs.surface.scrollRect(0, 15, 0, _h, 1);
    hs.canvas.text(0, _h - 1, 'new line'.padRight(15), hs.pens[1]);
    hs.frame();
    expect(hs.mismatches(), isEmpty);
    expect(hs.presenter.stats.scrollOps, 0);
  });

  test('a wide glyph across the rectangle edge: the rows are rewritten', () {
    final hs = Harness(_w, _h);
    paintLog(hs);
    hs.canvas.text(_w - 3, 4, '中', hs.pens[1]); // columns 37 and 38
    hs.frame();
    hs.surface.scrollRect(0, _w - 2, 0, _h, 1);
    hs.canvas.text(0, _h - 1, line(_h).substring(0, _w - 2), hs.pens[1]);
    hs.frame();
    expect(hs.mismatches(), isEmpty);
    expect(hs.presenter.stats.scrollOps, 0);
  });

  test('an image outside the rectangle: the rows are rewritten', () {
    final hs = Harness(
      _w,
      _h,
      caps: const TerminalCaps(graphics: GraphicsProtocol.sixel),
    );
    paintLog(hs);
    final img = TerminalImage(
      GraphicsProtocol.sixel,
      Uint8List.fromList('0;1;0q"1;1;10;20#0;2;0;0;0#0~~~~'.codeUnits),
      pixelWidth: 10,
      pixelHeight: 20,
    );
    hs.canvas
      ..fill(_w - 1, 2, 1, 1, hs.pens[3])
      ..image(_w - 1, 2, 1, 1, img);
    hs.frame();
    expect(hs.vt.images, hasLength(1));
    append(hs, _h);
    hs.canvas
      ..fill(_w - 1, 2, 1, 1, hs.pens[3])
      ..image(_w - 1, 2, 1, 1, img);
    hs.frame();
    expect(hs.mismatches(), isEmpty);
    expect(hs.presenter.stats.scrollOps, 0);
  });

  test('a later move carries the cells left to rewrite with it', () {
    final hs = Harness(_w, _h);
    paintLog(hs);
    // a scrollbar column whose every row differs
    for (var y = 0; y < _h; y++) {
      hs.canvas.text(_w - 1, y, String.fromCharCode(0x61 + y), hs.pens[2]);
    }
    hs.frame();
    // the log moves up in rows [0, 6), leaving the scrollbar's cells
    // there to rewrite; then rows [4, 12) move down 3, taking the rows
    // [4, 6) to [7, 9), below the rows the first move left
    hs.surface.scrollRect(0, _w - 1, 0, 6, 1);
    hs.canvas.text(0, 5, line(100), hs.pens[1]);
    hs.surface.scrollRows(4, _h, -3);
    for (var y = 4; y < 7; y++) {
      hs.canvas.text(0, y, line(200 + y), hs.pens[1]);
    }
    hs.frame();
    expect(hs.mismatches(), isEmpty);
    expect(hs.presenter.stats.scrollOps, 2);
  });
}
