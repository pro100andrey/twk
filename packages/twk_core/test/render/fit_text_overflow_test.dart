// fitText cutting the start or the middle, padCells, and fitText against the
// paragraph that cuts the same text with the same overflow.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

import 'paragraph_test.dart' show lay;

void main() {
  final narrow = TextSegmenter();
  final wide = TextSegmenter(ambiguousWidth: 2);

  group('fitText overflow', () {
    test('the start: "…" and the end that fits', () {
      const o = TextOverflow.ellipsisStart;
      expect(fitText(narrow, '/usr/local/bin', 8, overflow: o), '…cal/bin');
      expect(fitText(narrow, 'short', 8, overflow: o), 'short');
      expect(fitText(narrow, '你好世界', 6, overflow: o), '…世界');
      expect(fitText(narrow, '你好世界', 4, overflow: o), '…界');
      expect(fitText(wide, '/usr/local/bin', 8, overflow: o), '…al/bin');
      expect(fitText(narrow, 'abcdef', 1, overflow: o), '…');
      expect(fitText(wide, 'abcdef', 1, overflow: o), 'f');
      expect(fitText(narrow, 'abcdef', 0, overflow: o), '');
    });

    test('the middle: both ends, the start half or more', () {
      const o = TextOverflow.ellipsisMiddle;
      expect(fitText(narrow, 'hello world', 8, overflow: o), 'hell…rld');
      expect(fitText(narrow, '/usr/local/bin', 8, overflow: o), '/usr…bin');
      expect(fitText(narrow, '你好世界你好', 7, overflow: o), '你…你好');
      expect(fitText(narrow, 'abcdef', 1, overflow: o), '…');
      expect(fitText(wide, 'abcdef', 1, overflow: o), 'a');
    });

    test('clip cuts the end with no ellipsis', () {
      const o = TextOverflow.clip;
      expect(fitText(narrow, 'abcdef', 3, overflow: o), 'abc');
      expect(fitText(narrow, '你好世', 3, overflow: o), '你');
    });

    test('no cluster is split and the result fits', () {
      const texts = ['éééé', '👍🏽👍🏽 xy', '你好吗 a│b'];
      for (final seg in [narrow, wide]) {
        for (final text in texts) {
          for (final o in TextOverflow.values) {
            for (var w = 0; w <= seg.width(text); w++) {
              final fit = fitText(seg, text, w, overflow: o);
              expect(seg.width(fit), lessThanOrEqualTo(w < 0 ? 0 : w));
            }
          }
        }
      }
    });

    test('is what a paragraph cuts, where no blank is next to the cut', () {
      const texts = ['abcdefghijklmnop', '你好世界你好世界', 'a你b好c世d界e'];
      for (final (seg, ambiguous) in [(narrow, 1), (wide, 2)]) {
        for (final text in texts) {
          for (final o in [
            TextOverflow.ellipsis,
            TextOverflow.ellipsisStart,
            TextOverflow.ellipsisMiddle,
          ]) {
            for (var w = 2; w < seg.width(text); w++) {
              expect(
                fitText(seg, text, w, overflow: o),
                lay(
                  text,
                  w,
                  wrap: TextWrap.none,
                  overflow: o,
                  ambiguousWidth: ambiguous,
                ).single.trimRight(),
                reason: '$text at $w with $o',
              );
            }
          }
        }
      }
    });
  });

  group('padCells', () {
    test('pads to the columns, wide letters counting two', () {
      expect(padCells(narrow, 'ab', 5), 'ab   ');
      expect(padCells(narrow, '日本', 6), '日本  ');
      expect(padCells(narrow, 'ab', 5, alignment: TextAlign.right), '   ab');
      expect(padCells(narrow, '日本', 7, alignment: TextAlign.center), ' 日本  ');
    });

    test('the ambiguous width counts as the segmenter has it', () {
      expect(padCells(wide, 'a│', 5), 'a│  ');
      expect(padCells(narrow, 'a│', 5), 'a│   ');
    });

    test('a text as wide or wider stays as it is', () {
      expect(padCells(narrow, 'abcd', 4), 'abcd');
      expect(padCells(narrow, '日本語', 4), '日本語');
      expect(padCells(narrow, 'a', 0), 'a');
    });
  });
}
