// TextSegmenter.width and fitText: the columns of a string and a string
// cut off to some, in the segmenter's text mode and ambiguous width.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

void main() {
  final narrow = TextSegmenter();
  final wide = TextSegmenter(ambiguousWidth: 2);
  final legacy = TextSegmenter(mode: TextMode.legacy);

  group('TextSegmenter.width', () {
    test("is stringWidth in the segmenter's mode and ambiguous width", () {
      const texts = [
        '',
        'plain',
        'a\tb\x01',
        'a │ b … c',
        '« ‹ 1 … 42 › »',
        'e\u0301 你好',
        '👍🏽 🇺🇦 👨‍👩‍👧',
        '\u0301x',
        'ab\r\ncd',
      ];
      for (final seg in [narrow, wide, legacy]) {
        for (final text in texts) {
          expect(
            seg.width(text),
            stringWidth(
              text,
              mode: seg.mode,
              ambiguousWidth: seg.ambiguousWidth,
            ),
            reason: '$text in ${seg.mode.name}, ${seg.ambiguousWidth}',
          );
        }
      }
    });

    test('takes an East Asian Ambiguous character as two columns where the '
        'segmenter does', () {
      expect(narrow.width('a │ b'), 5);
      expect(wide.width('a │ b'), 6);
      expect(wide.width('…'), 2);
      expect(wide.width('你'), 2);
    });

    test('sees the mode the segmenter is in now', () {
      final seg = TextSegmenter();
      expect(seg.width('👍🏽'), 2);
      seg.mode = TextMode.legacy;
      expect(seg.width('👍🏽'), 4);
      seg.ambiguousWidth = 2;
      expect(seg.width('│'), 2);
    });
  });

  group('fitText', () {
    test('is the text itself where it fits', () {
      expect(fitText(narrow, 'Errors', 6), 'Errors');
      expect(fitText(wide, 'a │ b', 6), 'a │ b');
      expect(fitText(narrow, '', 0), '');
    });

    test('keeps the clusters that fit before a one-column ellipsis', () {
      expect(fitText(narrow, 'Warnings (12)', 8), 'Warning…');
      expect(fitText(narrow, 'Warnings (12)', 1), '…');
      expect(fitText(narrow, '你好吗', 4), '你…');
      expect(fitText(narrow, '你好吗', 3), '你…');
      expect(fitText(narrow, 'e\u0301e\u0301e\u0301', 2), 'e\u0301…');
    });

    test('leaves two columns for the ellipsis where it takes two', () {
      expect(fitText(wide, 'Warnings (12)', 8), 'Warnin…');
      expect(wide.width(fitText(wide, 'Warnings (12)', 8)), 8);
      expect(fitText(wide, 'a │ b │ c', 5), 'a …');
    });

    test('cuts off without an ellipsis where it does not fit', () {
      expect(fitText(wide, 'Warnings', 1), 'W');
      expect(fitText(wide, '你好', 1), '');
    });

    test('is nothing in no columns', () {
      expect(fitText(narrow, 'Errors', 0), '');
      expect(fitText(narrow, 'Errors', -3), '');
    });

    test('is never wider than the columns it is given', () {
      const texts = [
        'Warnings (12)',
        'a │ b … c',
        '你好吗',
        '👍🏽👍🏽 x',
        '\u0301ab',
      ];
      for (final seg in [narrow, wide, legacy]) {
        for (final text in texts) {
          for (var w = 0; w <= seg.width(text); w++) {
            final fit = fitText(seg, text, w);
            expect(
              seg.width(fit),
              lessThanOrEqualTo(w),
              reason: '$text in $w, ${seg.mode.name} ${seg.ambiguousWidth}',
            );
            expect(text.startsWith(fit.replaceFirst(RegExp(r'…$'), '')), true);
          }
        }
      }
    });
  });
}
