// A TextPainter lays text out and paints it onto a canvas with no render
// tree: the segmenter and the text order are given to it, it paints at an
// offset, and answers the queries of a paragraph. Painted at the origin it
// draws what a RenderParagraph of the same text draws in a tree.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

const plain = Pen();
const red = Pen(fg: Color.rgb(200, 0, 0));

final segmenter = TextSegmenter();

/// The rows of [s] as text.
List<String> rows(Surface s, GlyphTable glyphs) => [
  for (var y = 0; y < s.height; y++)
    [
      for (var x = 0; x < s.width; x++)
        if ((s.cells[y * s.width + x] & kCont) == 0)
          glyphs.stringOf(s.cells[y * s.width + x]),
    ].join().trimRight(),
];

/// A painter's rows, laid out within [w] columns and painted at ([x], [y])
/// of a [cw] x [ch] canvas.
List<String> paintAlone(
  TextPainter p,
  int w, {
  int x = 0,
  int y = 0,
  int cw = 20,
  int ch = 4,
  TextOrder order = TextOrder.logical,
}) {
  final surface = Surface(cw, ch);
  final glyphs = GlyphTable();
  final canvas = Canvas(surface, StyleTable(), glyphs);
  p
    ..layout(
      BoxConstraints(maxWidth: w, maxHeight: ch),
      segmenter: segmenter,
      order: order,
    )
    ..paint(canvas, x, y);
  return rows(surface, glyphs);
}

/// The rows a paragraph of the same settings paints in a tree.
List<String> paintInTree(
  List<(String, Pen)> spans,
  int w, {
  int cw = 20,
  int ch = 4,
  TextWrap wrap = TextWrap.word,
  TextOverflow overflow = TextOverflow.clip,
  int? maxLines,
  TextAlign align = TextAlign.left,
  TextOrder order = TextOrder.logical,
}) {
  final screen = Screen(cw, ch);
  PipelineOwner(() {}, segmenter: screen.canvas.segmenter)
    ..textOrder = order
    ..root = RenderFlex(
      direction: Axis.vertical,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RenderConstrainedBox(
          additionalConstraints: BoxConstraints(maxWidth: w, maxHeight: ch),
          child: RenderParagraph(
            spans,
            wrap: wrap,
            overflow: overflow,
            maxLines: maxLines,
            align: align,
          ),
        ),
      ],
    )
    ..flushLayout(cw, ch)
    ..flushPaint(PaintContext(screen.canvas, screen.surface, screen.presenter));
  return rows(screen.surface, screen.glyphs);
}

void main() {
  PipelineOwner.debugCheckIntrinsicsByDefault = true;
  test('new spans are painted the same whether or not a query came first', () {
    TextPainter changed() => TextPainter([('hello world', plain)])
      ..layout(
        const BoxConstraints(maxWidth: 12, maxHeight: 1),
        segmenter: segmenter,
      )
      ..spans = [('abc', plain)];
    String painted(TextPainter painter) {
      final surface = Surface(12, 1);
      final glyphs = GlyphTable();
      painter.paint(Canvas(surface, StyleTable(), glyphs), 0, 0);
      return rows(surface, glyphs).single;
    }

    final queried = changed();
    final range = queried.textRangeAt(4, 0);
    final plainly = changed();
    expect(painted(plainly), painted(queried));
    expect(painted(plainly), 'abc');
    expect(plainly.textRangeAt(4, 0), range);
    expect(queried.width, 11, reason: "the layout's");
  });

  group('layout', () {
    test('sizes itself to its widest line and its lines', () {
      final p = TextPainter([('hello big world', plain)])
        ..layout(
          const BoxConstraints(maxWidth: 8, maxHeight: 10),
          segmenter: segmenter,
        );
      expect((p.width, p.height), (5, 3), reason: '"hello" "big" "world"');
      p.layout(
        const BoxConstraints(maxWidth: 40, maxHeight: 10),
        segmenter: segmenter,
      );
      expect((p.width, p.height), (15, 1));
    });

    test('the constraints clamp the size', () {
      final p = TextPainter([('abc', plain)])
        ..layout(
          const BoxConstraints(
            minWidth: 10,
            maxWidth: 20,
            minHeight: 3,
            maxHeight: 5,
          ),
          segmenter: segmenter,
        );
      expect((p.width, p.height), (10, 3));
    });

    test('intrinsic sizes', () {
      final p = TextPainter([('hello big world', plain)]);
      expect(p.minIntrinsicWidth(segmenter), 5);
      expect(p.maxIntrinsicWidth(segmenter), 15);
      expect(p.intrinsicHeight(8, segmenter: segmenter), 3);
      expect(p.intrinsicHeight(100, segmenter: segmenter), 1);
      p.maxLines = 2;
      expect(p.intrinsicHeight(8, segmenter: segmenter), 2);
    });

    test('a property that changes nothing invalidates nothing', () {
      final p = TextPainter([('abc', plain)])
        ..layout(
          const BoxConstraints(maxWidth: 8, maxHeight: 3),
          segmenter: segmenter,
        );
      expect(p.takeInvalidation(), TextInvalidation.none);
      p
        ..wrap = TextWrap.word
        ..align = TextAlign.left
        ..spans = [('abc', plain)];
      expect(p.takeInvalidation(), TextInvalidation.none);
    });

    test('what a change invalidates', () {
      final p = TextPainter([('abc', plain)])
        ..layout(
          const BoxConstraints(maxWidth: 8, maxHeight: 3),
          segmenter: segmenter,
        )
        ..spans = [('abc', red)];
      expect(p.takeInvalidation(), TextInvalidation.paint, reason: 'pen only');
      p.align = TextAlign.right;
      expect(p.takeInvalidation(), TextInvalidation.paint);
      p.spans = [('abd', red)];
      expect(p.takeInvalidation(), TextInvalidation.layout, reason: 'text');
      p.wrap = TextWrap.none;
      expect(p.takeInvalidation(), TextInvalidation.layout);
      p
        ..align = TextAlign.center
        ..maxLines = 1;
      expect(
        p.takeInvalidation(),
        TextInvalidation.layout,
        reason: 'the stronger wins',
      );
      p
        ..overflow = TextOverflow.ellipsis
        ..layout(
          const BoxConstraints(maxWidth: 8, maxHeight: 3),
          segmenter: segmenter,
        );
      expect(p.takeInvalidation(), TextInvalidation.none, reason: 'laid out');
      p.ellipsis = '...';
      expect(p.takeInvalidation(), TextInvalidation.layout);
    });

    test('another segmenter is noticed', () {
      final p = TextPainter([('abc', plain)])
        ..layout(
          const BoxConstraints(maxWidth: 8, maxHeight: 3),
          segmenter: segmenter,
        );
      expect(p.segmenterChanged(segmenter), isFalse);
      expect(p.segmenterChanged(TextSegmenter(ambiguousWidth: 2)), isTrue);
    });
  });

  group('paint', () {
    test('at an offset', () {
      final p = TextPainter([('ab cd', plain)]);
      expect(paintAlone(p, 2, x: 3, y: 1), ['', '   ab', '   cd', '']);
    });

    test('again at another offset moves it', () {
      final surface = Surface(10, 3);
      final glyphs = GlyphTable();
      final canvas = Canvas(surface, StyleTable(), glyphs);
      final p = TextPainter([('hi', plain)])
        ..layout(
          const BoxConstraints(maxWidth: 10, maxHeight: 3),
          segmenter: segmenter,
        )
        ..paint(canvas, 0, 0);
      expect(rows(surface, glyphs), ['hi', '', '']);
      p.paint(canvas, 4, 2);
      expect(rows(surface, glyphs), ['hi', '', '    hi']);
    });

    test('spans paint in their pens', () {
      final surface = Surface(10, 1);
      final styles = StyleTable();
      final canvas = Canvas(surface, styles, GlyphTable());
      TextPainter([('ab', red), ('cd', plain)])
        ..layout(
          const BoxConstraints(maxWidth: 10, maxHeight: 1),
          segmenter: segmenter,
        )
        ..paint(canvas, 0, 0);
      StyleId at(int x) => StyleId(surface.styles[x]);
      expect(styles.fgOf(at(0)), const Color.rgb(200, 0, 0));
      expect(styles.fgOf(at(1)), const Color.rgb(200, 0, 0));
      expect(styles.fgOf(at(2)), isNot(const Color.rgb(200, 0, 0)));
    });

    test('an ellipsis stands for the text cut off', () {
      final p = TextPainter(
        [('abcdefgh', plain)],
        wrap: TextWrap.none,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      );
      expect(paintAlone(p, 5, x: 1), [' abcd…', '', '', '']);
      p.ellipsis = '..';
      expect(paintAlone(p, 5), ['abc..', '', '', '']);
    });

    test('an edit of the spans paints the new text', () {
      final p = TextPainter([('one', plain)]);
      expect(paintAlone(p, 10).first, 'one');
      p.spans = [('one two', plain)];
      expect(paintAlone(p, 10).first, 'one two');
    });

    test('painted at the origin it draws what a paragraph draws in a tree', () {
      final spans = [
        ('Error: ', red),
        ('the file could not be saved, the disk is full', plain),
        (' 日本語 é 👩‍🚀 end', plain),
      ];
      for (final wrap in TextWrap.values) {
        for (final align in TextAlign.values) {
          for (final overflow in TextOverflow.values) {
            for (final maxLines in <int?>[null, 2]) {
              final p = TextPainter(
                spans,
                wrap: wrap,
                align: align,
                overflow: overflow,
                maxLines: maxLines,
              );
              expect(
                paintAlone(p, 12, cw: 12),
                paintInTree(
                  spans,
                  12,
                  cw: 12,
                  wrap: wrap,
                  align: align,
                  overflow: overflow,
                  maxLines: maxLines,
                ),
                reason: '$wrap $align $overflow $maxLines',
              );
            }
          }
        }
      }
    });
  });

  group('queries', () {
    test('textRangeAt, cellAt and columnsOf', () {
      final p =
          TextPainter(
            [('one ', plain), ('two', red)],
            wrap: TextWrap.none,
          )..layout(
            const BoxConstraints(maxWidth: 20, maxHeight: 1),
            segmenter: segmenter,
          );
      expect(p.textRangeAt(5, 0), (5, 6));
      expect(p.cellAt(5, 0), (start: 5, end: 6, isEllipsis: false));
      expect(p.cellAt(15, 0), isNull);
      expect(p.columnsOf(4, 7, 0), (4, 7));
      expect(p.columnsOf(4, 7, 1), isNull);
    });

    test('before a layout they answer nothing', () {
      final p = TextPainter([('one', plain)]);
      expect(p.textRangeAt(1, 0), (0, 0));
      expect(p.columnsOf(0, 2, 0), isNull);
    });

    test('an ellipsis cell stands for the clusters it hides', () {
      final p =
          TextPainter(
            [('abcdefgh', plain)],
            wrap: TextWrap.none,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          )..layout(
            const BoxConstraints(minWidth: 5, maxWidth: 5, maxHeight: 100),
            segmenter: segmenter,
          );
      expect(p.cellAt(1, 0), (start: 1, end: 2, isEllipsis: false));
      expect(p.cellAt(4, 0), (start: 4, end: 8, isEllipsis: true));
    });
  });

  group('visual order', () {
    const hebrew = 'אבג';

    test('Hebrew is drawn as read when the order says so', () {
      final spans = [('abc $hebrew', plain)];
      final p = TextPainter(spans);
      expect(paintAlone(p, 10).first, 'abc $hebrew', reason: 'as stored');
      expect(
        paintAlone(p, 10, order: TextOrder.visual).first,
        'abc גבא',
        reason: 'the run reversed',
      );
      expect(
        paintAlone(p, 10).first,
        'abc $hebrew',
        reason: 'and back to stored',
      );
    });

    test('the queries follow where it is drawn', () {
      final p = TextPainter([('abc $hebrew', plain)], wrap: TextWrap.none);
      paintAlone(p, 10, order: TextOrder.visual);
      // drawn: a b c _ ג ב א
      expect(p.textRangeAt(4, 0), (6, 7), reason: 'the last letter first');
      expect(p.textRangeAt(6, 0), (4, 5));
      expect(p.columnsOf(4, 5, 0), (6, 7));
    });

    test('painted at the origin it draws what a paragraph draws in a tree', () {
      final spans = [('abc $hebrew (x) $hebrew', plain)];
      for (final align in TextAlign.values) {
        expect(
          paintAlone(
            TextPainter(spans, align: align),
            10,
            order: TextOrder.visual,
          ),
          paintInTree(spans, 10, align: align, order: TextOrder.visual),
          reason: '$align',
        );
      }
    });

    test('an ellipsis stands among the reordered text', () {
      final p = TextPainter(
        [('$hebrew $hebrew $hebrew', plain)],
        wrap: TextWrap.none,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      );
      final drawn = paintAlone(p, 6, order: TextOrder.visual).first;
      expect(drawn, contains('…'));
      expect(
        drawn,
        paintInTree(
          [('$hebrew $hebrew $hebrew', plain)],
          6,
          wrap: TextWrap.none,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          order: TextOrder.visual,
        ).first,
      );
    });
  });
}
