// A LabelPainter cuts a label to its room as a Text does: with the ellipsis
// where that fits, plainly at the room where it does not, drawing nothing
// past it; and a label is one line, drawn whole without its line breaks as
// the canvas drew it, its marks where they were.
import 'package:test/test.dart';
import 'package:twk/src/text/label_painter.dart';
import 'package:twk_core/twk_core.dart';

const red = Pen(fg: Color.rgb(200, 0, 0));

/// What [paint] leaves on a row of 12 cells, painting at column 2.
(String, List<Color?>) row(void Function(LabelPainter, Canvas) paint) {
  final surface = Surface(12, 1);
  final glyphs = GlyphTable();
  final styles = StyleTable();
  final canvas = Canvas(surface, styles, glyphs);
  paint(LabelPainter(), canvas);
  return (
    [for (final g in surface.cells) glyphs.stringOf(g)].join(),
    [for (final s in surface.styles) styles.fgOf(StyleId(s))],
  );
}

void main() {
  test('a room narrower than the ellipsis cuts the label plainly at it', () {
    for (final (room, drawn) in [(2, 'ab'), (1, 'a'), (0, ''), (-1, '')]) {
      final (text, _) = row(
        (p, c) => p
          ..set('abcdefgh', const Pen(), c.segmenter)
          ..paint(c, null, 2, 0, room: room, ellipsis: '...'),
      );
      expect(text, '  ${drawn.padRight(10)}', reason: 'room $room');
    }
  });

  test('a room the ellipsis fits in cuts the label with it', () {
    final (text, _) = row(
      (p, c) => p
        ..set('abcdefgh', const Pen(), c.segmenter)
        ..paint(c, null, 2, 0, room: 5, ellipsis: '...'),
    );
    expect(text, '  ab...     ');
  });

  test('a label with line breaks draws whole without them, its marks where '
      'they were', () {
    final (text, colors) = row(
      (p, c) => p
        ..set('a\nbc\r\nd', const Pen(), c.segmenter, marks: [2], markPen: red)
        ..paint(c, null, 2, 0),
    );
    expect(text, '  abcd      ');
    // the mark at offset 2 is "b", the third cell drawn
    expect(colors[3], const Color.rgb(200, 0, 0));
    expect(colors[2], isNot(const Color.rgb(200, 0, 0)));
    expect(colors[4], isNot(const Color.rgb(200, 0, 0)));
  });
}
