// The mark a cut line ends with is a value, `…` by default: fitText, a
// paragraph and the titles of a box cut with `...` the same way, the
// ellipsis' own columns taken from the room.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

import 'paragraph_test.dart' show View, plain;

List<String> lay(
  String text,
  int width, {
  required String ellipsis,
  TextOverflow overflow = TextOverflow.ellipsis,
  int ambiguousWidth = 1,
  int? maxLines = 1,
}) {
  final v = View(width, 6, ambiguousWidth: ambiguousWidth);
  return v.show(
    RenderParagraph(
      [(text, plain)],
      wrap: TextWrap.none,
      overflow: overflow,
      maxLines: maxLines,
      ellipsis: ellipsis,
    ),
  );
}

void main() {
  final narrow = TextSegmenter();
  final wide = TextSegmenter(ambiguousWidth: 2);

  group('fitText with an ellipsis of three columns', () {
    test('takes its columns from the room, at the end, start or middle', () {
      expect(
        fitText(narrow, 'Warnings (12)', 8, ellipsis: '...'),
        'Warni...',
      );
      expect(
        fitText(
          narrow,
          '/usr/local/bin',
          8,
          overflow: TextOverflow.ellipsisStart,
          ellipsis: '...',
        ),
        '...l/bin',
      );
      expect(
        fitText(
          narrow,
          '/usr/local/bin',
          8,
          overflow: TextOverflow.ellipsisMiddle,
          ellipsis: '...',
        ),
        '/us...in',
      );
      expect(fitText(narrow, 'short', 8, ellipsis: '...'), 'short');
    });

    test('is left out where it does not fit; none beside a blank', () {
      expect(fitText(narrow, 'abcdef', 2, ellipsis: '...'), 'ab');
      expect(fitText(narrow, 'abcdef', 3, ellipsis: '...'), '...');
      expect(fitText(narrow, 'ab   cdefgh', 7, ellipsis: '...'), 'ab...');
    });

    test('is the width of the ellipsis in the cjk columns, not one', () {
      // `…` is two columns there, `...` three whatever the setting
      expect(fitText(wide, 'Warnings (12)', 8), 'Warnin…');
      expect(fitText(wide, 'Warnings (12)', 8, ellipsis: '...'), 'Warni...');
    });

    test('is what a paragraph cuts with the same mark', () {
      const texts = ['abcdefghijklmnop', '你好世界你好世界', 'a你b好c世d界e'];
      for (final (seg, ambiguous) in [(narrow, 1), (wide, 2)]) {
        for (final text in texts) {
          for (final o in [
            TextOverflow.ellipsis,
            TextOverflow.ellipsisStart,
            TextOverflow.ellipsisMiddle,
          ]) {
            for (var w = 3; w < seg.width(text); w++) {
              expect(
                fitText(seg, text, w, overflow: o, ellipsis: '...'),
                lay(
                  text,
                  w,
                  overflow: o,
                  ellipsis: '...',
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

  group('a paragraph with an ellipsis of three columns', () {
    test('draws it in the cut and keeps the rest of the line', () {
      expect(lay('abcdefgh', 6, ellipsis: '...'), ['abc...']);
      expect(
        lay('abcdefgh', 6, ellipsis: '...', overflow: .ellipsisStart),
        ['...fgh'],
      );
      expect(
        lay('abcdefgh', 6, ellipsis: '...', overflow: .ellipsisMiddle),
        ['ab...h'],
      );
      // the default mark is unchanged
      expect(lay('abcdefgh', 6, ellipsis: '…'), ['abcde…']);
    });

    test('maxLines: the last line shown ends with it', () {
      final v = View(5, 4);
      expect(
        v.show(
          RenderParagraph(
            [('abcdefghijkl', plain)],
            wrap: TextWrap.none,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            ellipsis: '...',
          ),
        ),
        ['ab...'],
      );
      expect(
        v.show(
          RenderParagraph(
            [('abcde fghij klmno', plain)],
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
            ellipsis: '...',
          ),
        ),
        ['abcde', 'fg...'],
      );
    });

    test('cellAt and textRangeAt: all three cells stand for the cut', () {
      final p = RenderParagraph(
        [('abcdefgh', plain)],
        wrap: TextWrap.none,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        ellipsis: '...',
      )..layout(const BoxConstraints(minW: 6, maxW: 6, maxH: 100));
      expect(
        [
          for (var x = 0; x < 6; x++)
            if (p.cellAt(x, 0)?.isEllipsis ?? false) x,
        ],
        [3, 4, 5],
      );
      expect(p.textRangeAt(2, 0), (2, 3));
      for (final x in [3, 4, 5]) {
        expect(p.textRangeAt(x, 0), (3, 8), reason: 'column $x');
      }
    });

    test('a new ellipsis lays the paragraph out again', () {
      final v = View(6, 2);
      final p = RenderParagraph(
        [('abcdefgh', plain)],
        wrap: TextWrap.none,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      );
      v.owner.root = p;
      expect(v.frame()[0], 'abcde…');
      p.ellipsis = '...';
      expect(v.frame()[0], 'abc...');
      p.ellipsis = '…';
      expect(v.frame()[0], 'abcde…');
    });

    test('an ellipsis of two columns, one of a cluster of several code '
        'points', () {
      expect(lay('abcdefgh', 6, ellipsis: '全'), ['abcd全']);
      expect(lay('abcdefgh', 6, ellipsis: 'éé'), [
        'abcdéé',
      ]);
    });
  });

  group('the titles of a box', () {
    List<String> top(String ellipsis, {String title = 'a long title'}) {
      final v = View(10, 3);
      v.owner.root = RenderDecoratedBox(
        border: const BoxBorder.all(type: BorderType.ascii),
        titles: [BoxTitle(title)],
        ellipsis: ellipsis,
      );
      return v.frame();
    }

    test('end with it where they do not fit', () {
      expect(top('\u2026')[0], '+a long\u2026-+');
      expect(top('...')[0], '+a lon...+');
      expect(top('...', title: 'short')[0], '+short---+');
    });

    test('a new ellipsis repaints them', () {
      final v = View(10, 3);
      final box = RenderDecoratedBox(
        border: const BoxBorder.all(type: BorderType.ascii),
        titles: const [BoxTitle('a long title')],
      );
      v.owner.root = box;
      expect(v.frame()[0], '+a long\u2026-+');
      box.ellipsis = '...';
      expect(v.frame()[0], '+a lon...+');
    });
  });
}
