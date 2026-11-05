// cellAt: the range of a cell and whether it is an ellipsis, in one query.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

RenderParagraph cut(String text, int width, {String? ellipsis}) =>
    RenderParagraph(
      [(text, const Pen())],
      wrap: TextWrap.none,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      ellipsis: ellipsis ?? '…',
    )..layout(BoxConstraints(minW: width, maxW: width, maxH: 100));

void main() {
  test('the ellipsis cell reports isEllipsis and the text it stands for', () {
    final p = cut('abcdefgh', 5);
    expect(p.cellAt(4, 0), (start: 4, end: 8, isEllipsis: true));
  });

  test('a three-column ellipsis is the cut text at each of its cells', () {
    final p = cut('abcdefgh', 6, ellipsis: '...');
    for (final x in [3, 4, 5]) {
      expect(p.cellAt(x, 0), (start: 3, end: 8, isEllipsis: true));
    }
  });

  test('a plain cell reports its cluster and is no ellipsis', () {
    final p = cut('abcdefgh', 5);
    for (var x = 0; x < 4; x++) {
      expect(p.cellAt(x, 0), (start: x, end: x + 1, isEllipsis: false));
    }
  });

  test('it agrees with textRangeAt wherever the range is not empty', () {
    final p = cut('abcdefgh', 5);
    for (var y = -1; y <= 1; y++) {
      for (var x = -1; x <= 6; x++) {
        final (s, e) = p.textRangeAt(x, y);
        final c = p.cellAt(x, y);
        expect(c == null ? s == e : (c.start, c.end) == (s, e), isTrue);
      }
    }
  });

  test('out of the text it is null', () {
    final p = cut('abc', 5);
    expect(p.cellAt(-1, 0), isNull);
    expect(p.cellAt(3, 0), isNull);
    expect(p.cellAt(0, -1), isNull);
    expect(p.cellAt(0, 1), isNull);
  });

  test('before a layout it is null', () {
    final p = RenderParagraph([('abc', const Pen())]);
    expect(p.cellAt(0, 0), isNull);
  });
}
