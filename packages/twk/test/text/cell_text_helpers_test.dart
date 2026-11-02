// The helpers for an app's own cell text, from twk.dart: fitText cutting the
// start or the middle, padCells and breakLines, by a segmenter's widths.
import 'package:test/test.dart';
import 'package:twk/twk.dart';

void main() {
  final narrow = TextSegmenter();
  final wide = TextSegmenter(ambiguousWidth: 2);

  test('fitText cuts a path from the start, wide letters by columns', () {
    const o = TextOverflow.ellipsisStart;
    expect(
      fitText(narrow, '/home/日本語/file.dart', 13, overflow: o),
      '…語/file.dart',
    );
    expect(fitText(wide, 'a│b│c│d', 5, overflow: o), '…│d');
  });

  test('padCells pads to columns, not code units', () {
    expect(padCells(narrow, '日本', 6), '日本  ');
    expect(padCells(wide, '│', 3, alignment: TextAlign.right), ' │');
  });

  test('breakLines breaks as a Text does', () {
    expect(breakLines(TextSegmenter(), 'well-known words', 8), [
      (0, 5),
      (5, 10),
      (11, 16),
    ]);
  });
}
