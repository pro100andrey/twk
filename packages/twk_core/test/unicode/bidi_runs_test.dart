// The paragraphs and runs a BidiText hands out, as a caller reads them.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

void main() {
  test("a run's direction follows its level: odd right to left", () {
    final bidi = BidiText('abc אבג def');
    final runs = bidi.visualRuns(0, bidi.text.length);
    expect(
      [for (final r in runs) (r.start, r.end, r.direction)],
      [
        (0, 4, TextDirection.ltr),
        (4, 7, TextDirection.rtl),
        (7, 11, TextDirection.ltr),
      ],
    );
  });

  test('a paragraph and a run print their range and level', () {
    final bidi = BidiText('אבג', direction: TextDirection.rtl);
    expect('${bidi.paragraphs.single}', 'BidiParagraph(0, 3, 1)');
    expect('${bidi.visualRuns(0, 3).single}', 'BidiRun(0, 3, 1)');
  });
}
