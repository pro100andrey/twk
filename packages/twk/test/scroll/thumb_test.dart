// paintThumb in a painter of the app's own: whole cells a reversed blank
// or the glyph given, the cells covered in part eighth blocks; in its
// color over the cells' own background; across as well as down.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show GlyphTable, Surface;
import 'package:twk_test/twk_test.dart';

/// Paints a thumb from [start] to [end] in [steps] a cell on column 1
/// ([vertical]) or row 1, after filling the canvas with a background.
final class Thumb extends CellPainter {
  Thumb(
    this.start,
    this.end, {
    this.steps = 8,
    this.vertical = true,
    this.glyph,
  });

  final int start;
  final int end;
  final int steps;
  final bool vertical;
  final int? glyph;

  @override
  void paint(Canvas canvas, int width, int height) {
    canvas.fill(
      0,
      0,
      width,
      height,
      canvas.styles.pen(const Pen(bg: Color.rgb(1, 2, 3))),
    );
    paintThumb(
      canvas,
      const Style(fg: Color.rgb(200, 100, 0)),
      start: start,
      end: end,
      steps: steps,
      vertical: vertical,
      at: 1,
      glyph: glyph,
    );
  }

  @override
  bool shouldRepaint(Thumb oldDelegate) => true;
}

/// A cell as text: its glyph, after `~` when it is in reverse video.
String cellText(VtCell cell) =>
    '${cell.attrs & Attr.reverse != 0 ? '~' : ''}${cell.text}';

void main() {
  testTwk('down: whole cells reversed blanks, the ends eighth blocks', (
    t,
  ) async {
    // 3/8 of row 0 to 5/8 of row 3
    await t.pumpWidget(
      CustomPaint(painter: Thumb(5, 29), size: (3, 5)),
      size: (3, 5),
    );
    expect(
      [for (var y = 0; y < 5; y++) cellText(t.cell(1, y))],
      [
        '▃',
        '~ ',
        '~ ',
        '~▃',
        ' ',
      ],
    );
    // the thumb's color, over the background the cells had
    expect(t.cell(1, 0).fg, const Color.rgb(200, 100, 0).value);
    expect(t.cell(1, 0).bg, const Color.rgb(1, 2, 3).value);
    expect(t.cell(0, 1).text, ' ');
  });

  testTwk('across: the ends left and right eighth blocks', (t) async {
    await t.pumpWidget(
      CustomPaint(painter: Thumb(5, 19, vertical: false), size: (4, 3)),
      size: (4, 3),
    );
    expect(
      [for (var x = 0; x < 4; x++) cellText(t.cell(x, 1))],
      [
        '~▋',
        '~ ',
        '▍',
        ' ',
      ],
    );
  });

  testTwk('a glyph for the whole cells: a slim thumb in its color', (
    t,
  ) async {
    await t.pumpWidget(
      CustomPaint(
        painter: Thumb(1, 3, steps: 1, glyph: 0x2590),
        size: (3, 4),
      ),
      size: (3, 4),
    );
    expect(
      [for (var y = 0; y < 4; y++) cellText(t.cell(1, y))],
      [
        ' ',
        '▐',
        '▐',
        ' ',
      ],
    );
    expect(t.cell(1, 1).fg, const Color.rgb(200, 100, 0).value);
    expect(t.cell(1, 1).bg, const Color.rgb(1, 2, 3).value);
  });

  test('a step of a cell is an eighth where the canvas draws the blocks '
      'one column wide, else the cell', () {
    Canvas canvas(int ambiguousWidth) => Canvas(
      Surface(1, 1),
      StyleTable(),
      GlyphTable(),
      segmenter: TextSegmenter(ambiguousWidth: ambiguousWidth),
    );
    expect(thumbSteps(canvas(1), vertical: true), 8);
    expect(thumbSteps(canvas(1), vertical: false), 8);
    expect(thumbSteps(canvas(2), vertical: true), 1);
    expect(thumbSteps(canvas(2), vertical: false), 1);
  });
}
