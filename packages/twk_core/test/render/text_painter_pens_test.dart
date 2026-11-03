// A TextPainter given new spans keeps the ids of the pens that are as they
// were and looks up the others: after any run of edits, painted or not in
// between, onto one style table or a new one, every cell has the style a
// new painter of the same spans gives it.
import 'dart:math';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

final segmenter = TextSegmenter();

const _width = 60;
const _box = BoxConstraints(0, _width, 0, 1);

/// What painting [p] onto a fresh row of [styles] gives each cell: its
/// colors and attributes.
List<(Color?, Color?, int)> paintRow(TextPainter p, StyleTable styles) {
  final surface = Surface(_width, 1);
  p
    ..layout(_box, segmenter: segmenter)
    ..paint(Canvas(surface, styles, GlyphTable()), 0, 0);
  return [
    for (var x = 0; x < _width; x++)
      (
        styles.fgOf(StyleId(surface.styles[x])),
        styles.bgOf(StyleId(surface.styles[x])),
        styles.attrsOf(StyleId(surface.styles[x])),
      ),
  ];
}

void main() {
  test('after edits of the spans each cell has the style of its span', () {
    final random = Random(7);
    // pens made at run time, so that equal ones are not one object
    Pen pen() => switch (random.nextInt(5)) {
      0 => const Pen(),
      1 => Pen(fg: Color.rgb(200, 0, random.nextInt(2))),
      2 => Pen(bg: Color.rgb(0, 0, 100 + random.nextInt(2))),
      3 => const Pen(attrs: Attr.bold),
      _ => const Pen(fg: Color.rgb(0, 150, 0), attrs: Attr.underline),
    };
    String text() => ['', 'a', 'bc', 'def '][random.nextInt(4)];
    (String, Pen) span() => (text(), pen());

    var spans = [for (var k = 0; k < 6; k++) span()];
    final p = TextPainter(spans, wrap: TextWrap.none);
    var styles = StyleTable();
    var edits = 0;
    var painted = 0;
    for (var round = 0; round < 3000; round++) {
      final next = List.of(spans);
      final k = next.isEmpty ? 0 : random.nextInt(next.length);
      switch (random.nextInt(6)) {
        case 0 when next.isNotEmpty:
          next[k] = (next[k].$1, pen());
        case 1:
          next.insert(
            next.isEmpty ? 0 : random.nextInt(next.length + 1),
            span(),
          );
        case 2 when next.length > 1:
          next.removeAt(k);
        case 3 when next.isNotEmpty:
          next[k] = (text(), next[k].$2);
        case 4:
          // several at once, apart from each other
          for (var j = 0; j < next.length; j += 1 + random.nextInt(4)) {
            next[j] = (next[j].$1, pen());
          }
        default:
          // the same spans again, in a new list
          break;
      }
      spans = next;
      p.spans = spans;
      edits++;
      if (random.nextInt(4) == 0) {
        // the next edit before a paint
        continue;
      }
      if (random.nextInt(50) == 0) {
        styles = StyleTable();
      }
      final row = paintRow(p, styles);
      final fresh = paintRow(TextPainter(spans, wrap: TextWrap.none), styles);
      expect(row, fresh, reason: 'round $round: $spans');
      painted++;
    }
    expect(edits, 3000);
    expect(painted, greaterThan(2000));
  });

  test('a pen changed before the first paint is looked up', () {
    final styles = StyleTable();
    final p = TextPainter([('ab', const Pen())], wrap: TextWrap.none)
      ..spans = [('ab', const Pen(fg: Color.rgb(9, 9, 9)))];
    expect(paintRow(p, styles).first.$1, const Color.rgb(9, 9, 9));
  });
}
