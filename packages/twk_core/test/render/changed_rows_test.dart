// A TextPainter says which rows its last paint drew otherwise than the
// paint before: the rows built again, those that moved, and those that
// went. Nothing changed is 0 to 0; what rebuilds every row counts them all.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

const plain = Pen();
const red = Pen(fg: Color.rgb(200, 0, 0));

final segmenter = TextSegmenter();

final class _Rig {
  _Rig(String text, {this.order = TextOrder.logical})
    : painter = TextPainter([(text, plain)]),
      canvas = Canvas(Surface(20, 12), StyleTable(), GlyphTable());

  final TextPainter painter;
  final TextOrder order;
  final Canvas canvas;

  (int, int) paint([List<(String, Pen)>? spans, int? width]) {
    if (spans != null) {
      painter.spans = spans;
    }
    painter
      ..layout(
        BoxConstraints(maxW: width ?? 10, maxH: 12),
        segmenter: segmenter,
        order: order,
      )
      ..paint(canvas, 0, 0);
    return painter.changedRows;
  }
}

void main() {
  for (final order in TextOrder.values) {
    group('$order', () {
      test('the first paint counts every row', () {
        final r = _Rig('one\ntwo\nthree\nfour', order: order);
        expect(r.paint(), (0, 4));
      });

      test('a paint with nothing changed counts none', () {
        final r = _Rig('one\ntwo\nthree', order: order)..paint();
        expect(r.paint(), (0, 0));
        expect(r.paint(), (0, 0));
      });

      const six = 'aaa aaa\nbbb bbb\nccc ccc\nddd ddd\neee eee\nfff fff';

      test('one row edited counts it and those the edit reaches', () {
        // the rows from the one before to the one after: an edit is taken
        // as far as the first place the clusters line up again
        final r = _Rig(six, order: order)..paint();
        final (first, end) = r.paint([
          ('aaa aaa\nbbb bbb\nccc ccc\nddd dXd\neee eee\nfff fff', plain),
        ]);
        expect(first, inInclusiveRange(2, 3));
        expect(end, inInclusiveRange(4, 5));
      });

      test('rows far from the edits are not counted', () {
        final r = _Rig(six, order: order)..paint();
        final (first, end) = r.paint([
          ('aaa aaa\nbbb bbb\nccc ccc\nddd ddd\neee eee\nfff fXf', plain),
        ]);
        expect((first, end), (5, 6));
      });

      test('two rows edited count from the first to past the last', () {
        final r = _Rig(six, order: order)..paint();
        final (first, end) = r.paint([
          ('aaa aXa\nbbb bbb\nccc ccc\nddd ddd\neee eee\nfff fXf', plain),
        ]);
        expect((first, end), (0, 6));
      });

      test('a pen changed counts the rows it may have changed', () {
        final r = _Rig(six, order: order)..paint();
        final (first, end) = r.paint([(six, red)]);
        expect(first, 0);
        expect(end, 6);
      });

      test('a row inserted moves those below it', () {
        final r = _Rig(six, order: order)..paint();
        final (first, end) = r.paint([
          ('aaa aaa\nbbb bbb\nnew\nccc ccc\nddd ddd\neee eee\nfff fff', plain),
        ]);
        expect(first, inInclusiveRange(1, 2));
        expect(end, 7);
      });

      test('rows that went count', () {
        final r = _Rig(six, order: order)..paint();
        final (first, end) = r.paint([
          ('aaa aaa\nbbb bbb\nccc ccc\nddd ddd', plain),
        ]);
        expect(first, inInclusiveRange(2, 4));
        expect(end, 6);
      });

      test('a new width counts every row', () {
        final r = _Rig('one two three four', order: order)..paint();
        expect(r.paint(null, 8), (0, 3));
      });

      test('a typed word at the end counts its row only', () {
        final r = _Rig('aaa bbb\nccc ddd\neee fff\nggg', order: order)..paint();
        expect(r.paint([('aaa bbb\nccc ddd\neee fff\nggg h', plain)]), (3, 4));
      });
    });
  }
}
