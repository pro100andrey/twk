// The damage Surface.scrollRect leaves: the cells that moved with the
// rectangle keep the damage they had (moved along with them), the cells
// beside it keep their own, and only the rows the move exposes are new
// damage, as with scrollRows.
import 'package:test/test.dart';
import 'package:twk_core/src/canvas.dart';
import 'package:twk_core/src/style.dart';
import 'package:twk_core/src/surface.dart';

const _w = 12;
const _h = 6;

void main() {
  late StyleTable styles;
  late Surface s;
  late Canvas cv;
  late int pen;
  setUp(() {
    styles = StyleTable();
    s = Surface(_w, _h);
    cv = Canvas(s, styles, GlyphTable());
    pen = styles.pen(const Pen(fg: Color.red));
    for (var y = 0; y < _h; y++) {
      cv.text(0, y, 'row $y'.padRight(_w), pen);
    }
    s.clearDamage();
  });

  List<(int, int)?> damage() => [
    for (var y = 0; y < _h; y++)
      if (s.dirtyLo[y] < s.dirtyHi[y]) (s.dirtyLo[y], s.dirtyHi[y]) else null,
  ];

  test('a move up damages only the rows it exposes', () {
    s.scrollRect(0, _w - 1, 0, _h, 1);
    expect(damage(), [null, null, null, null, null, (0, _w - 1)]);
    expect(s.pendingScrolls, [0, _h, 1, 0, _w - 1]);
  });

  test('a move down damages only the rows it exposes', () {
    s.scrollRect(2, 8, 1, 5, -2);
    expect(damage(), [null, (2, 8), (2, 8), null, null, null]);
    expect(s.pendingScrolls, [1, 5, -2, 2, 8]);
  });

  test('damage inside the rectangle moves with its cells', () {
    cv.text(3, 4, 'ab', pen); // inside, moves to row 3
    s.scrollRect(1, 9, 0, _h, 1);
    expect(damage(), [null, null, null, (3, 5), null, (1, 9)]);
  });

  test('damage beside the rectangle stays where it is', () {
    cv.text(_w - 1, 2, '|', pen); // a scrollbar cell: does not move
    s.scrollRect(0, _w - 1, 0, _h, 1);
    expect(damage(), [null, null, (_w - 1, _w), null, null, (0, _w - 1)]);
  });

  test('damage across an edge splits: the inside moves, the rest stays', () {
    cv.text(0, 3, 'x' * _w, pen); // the whole row 3
    s.scrollRect(0, _w - 1, 0, _h, 1);
    // row 3 keeps its column beside; row 2 gets the inside of row 3
    expect(damage(), [null, null, (0, _w - 1), (_w - 1, _w), null, (0, 11)]);
  });

  test('damage outside the moved rows is left alone', () {
    cv.text(4, 0, 'top', pen);
    s.scrollRect(2, 10, 1, 4, 1);
    expect(damage(), [(4, 7), null, null, (2, 10), null, null]);
  });

  test('a wide glyph cut by an edge is damaged where it was blanked', () {
    cv.text(_w - 2, 1, '你', pen); // halves at columns 10 and 11
    s
      ..clearDamage()
      ..scrollRect(0, _w - 1, 0, _h, 1);
    expect(s.cells[1 * _w + _w - 1], kBlank);
    // the blanked half beside stays on row 1, the inside one moved to row 0
    expect(damage(), [
      (_w - 2, _w - 1),
      (_w - 1, _w),
      null,
      null,
      null,
      (0, 11),
    ]);
  });

  test('a move as tall as the rectangle blanks and damages all of it', () {
    s.scrollRect(2, 8, 1, 4, 3);
    expect(damage(), [null, (2, 8), (2, 8), (2, 8), null, null]);
    expect(s.pendingScrolls, isEmpty);
  });
}
