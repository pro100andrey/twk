// A one-line TextPainter cut at its end with an ellipsis splits and measures
// only the head of the text it can show, and the rest only when asked. The
// head layout must be the full layout seen from outside: these tests lay the
// same input out twice, once with `debugForceFull` (the whole text split and
// measured, as before) and once without, and compare everything a caller can
// observe: the cells and styles painted, the size, the text at every cell
// (`cellAt`, `textRangeAt`), `columnsOf`, the intrinsic widths, and what a
// later edit, width or segmenter makes of them.
import 'dart:math';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

const plain = Pen();
const red = Pen(fg: Color.rgb(200, 0, 0));
const blue = Pen(fg: Color.rgb(0, 0, 200), bg: Color.rgb(1, 2, 3));

final latin = TextSegmenter();
final ambiguous2 = TextSegmenter(ambiguousWidth: 2);
final legacy = TextSegmenter(mode: TextMode.legacy);

/// One side of a comparison: a painter of the settings, and what it painted.
final class Side {
  Side(
    List<(String, Pen)> spans, {
    required bool full,
    required TextWrap wrap,
    required String ellipsis,
    required TextAlign align,
    TextOverflow overflow = TextOverflow.ellipsis,
    int? maxLines = 1,
  }) : painter = TextPainter(
         spans,
         wrap: wrap,
         overflow: overflow,
         maxLines: maxLines,
         align: align,
         ellipsis: ellipsis,
       )..debugForceFull = full;

  final TextPainter painter;
  final glyphs = GlyphTable();
  final styles = StyleTable();
}

/// The cells and styles of a side painted onto a surface of cw x 3 at (1, 1).
List<int> painted(Side s, int cw) {
  final surface = Surface(cw, 3);
  final canvas = Canvas(surface, s.styles, s.glyphs);
  s.painter.paint(canvas, 1, 1);
  return [...surface.cells, ...surface.styles];
}

/// Lays the two sides out alike and fails where anything a caller can see
/// differs.
void agree(
  Side fast,
  Side full,
  int w,
  TextSegmenter seg,
  TextOrder order, {
  required String what,
}) {
  final c = BoxConstraints(0, w, 0, 3);
  fast.painter.layout(c, segmenter: seg, order: order);
  full.painter.layout(c, segmenter: seg, order: order);
  final p = fast.painter;
  final q = full.painter;
  expect(q.debugHeadOnly, isFalse, reason: '$what: the forced one is whole');
  expect((p.width, p.height), (q.width, q.height), reason: '$what: size');
  final cw = w + 4;
  expect(painted(fast, cw), painted(full, cw), reason: '$what: painted');
  var length = 0;
  for (final (t, _) in p.spans) {
    length += t.length;
  }
  for (var y = -1; y <= p.height + 1; y++) {
    for (var x = -1; x <= w + 2; x++) {
      expect(
        p.textRangeAt(x, y),
        q.textRangeAt(x, y),
        reason: '$what: textRangeAt($x, $y)',
      );
      expect(
        p.cellAt(x, y),
        q.cellAt(x, y),
        reason: '$what: cellAt($x, $y)',
      );
    }
  }
  final cuts = {0, 1, length ~/ 3, length ~/ 2, length - 1, length};
  for (final a in cuts) {
    for (final b in cuts) {
      expect(
        p.columnsOf(a, b, 0),
        q.columnsOf(a, b, 0),
        reason: '$what: columnsOf($a, $b)',
      );
    }
  }
  expect(
    p.columnsOf(0, length, 1),
    q.columnsOf(0, length, 1),
    reason: '$what: columnsOf another row',
  );
}

/// Whether the last [agreeAll] laid its text out as a head.
var headCase = false;

/// [agree], then the intrinsic sizes (which split the rest of the text) and
/// the same layout again, then a narrower and a wider one.
void agreeAll(
  List<(String, Pen)> spans, {
  required int w,
  TextWrap wrap = TextWrap.none,
  String ellipsis = '…',
  TextAlign align = TextAlign.left,
  TextSegmenter? segmenter,
  TextOrder order = TextOrder.logical,
  String? tag,
}) {
  headCase = false;
  final seg = segmenter ?? latin;
  final what =
      '${tag ?? spans.map((s) => s.$1).join('|')} w=$w $wrap "$ellipsis" '
      '$align ${seg.mode.name}/${seg.ambiguousWidth} ${order.name}';
  Side side(bool full) => Side(
    spans,
    full: full,
    wrap: wrap,
    ellipsis: ellipsis,
    align: align,
  );
  final fast = side(false);
  final full = side(true);
  agree(fast, full, w, seg, order, what: what);
  if (fast.painter.debugHeadOnly) {
    headCase = true;
  }
  // asked its intrinsic widths, it measures the whole text
  for (final q in [fast, full]) {
    q.painter
      ..minIntrinsicWidth(seg)
      ..maxIntrinsicWidth(seg);
  }
  expect(
    fast.painter.maxIntrinsicWidth(seg),
    full.painter.maxIntrinsicWidth(seg),
  );
  expect(
    fast.painter.minIntrinsicWidth(seg),
    full.painter.minIntrinsicWidth(seg),
  );
  expect(fast.painter.debugHeadOnly, isFalse, reason: '$what: whole now');
  expect(fast.painter.debugDiffFromFresh(seg), isNull, reason: what);
  agree(fast, full, w, seg, order, what: '$what, after intrinsics');
  for (final w2 in [w + 7, if (w > 3) w - 3, 0, 1]) {
    agree(fast, full, w2, seg, order, what: '$what, then w=$w2');
  }
}

void main() {
  group('a head layout is the full layout', () {
    final long = 'abcdefghij' * 40;

    test('latin text cut at the end', () {
      for (final wrap in TextWrap.values) {
        for (final w in [0, 1, 2, 5, 9, 10, 11, 40, 399, 400, 401, 5000]) {
          agreeAll([(long, plain)], w: w, wrap: wrap);
        }
      }
    });

    test('the head is all that is split', () {
      final p = TextPainter(
        [(long, plain)],
        wrap: TextWrap.none,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      )..layout(const BoxConstraints(0, 20, 0, 1), segmenter: latin);
      expect(p.debugHeadOnly, isTrue);
      expect(p.debugClustersSplit, lessThan(40));
      expect(p.debugLinesBroken, 1);
      final full =
          TextPainter(
              [(long, plain)],
              wrap: TextWrap.none,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            )
            ..debugForceFull = true
            ..layout(const BoxConstraints(0, 20, 0, 1), segmenter: latin);
      expect(full.debugClustersSplit, 400);
    });

    test('a wider layout splits a head at its width, not the whole text', () {
      Side side({required bool full}) => Side(
        [(long, plain)],
        full: full,
        wrap: TextWrap.none,
        ellipsis: '…',
        align: TextAlign.left,
      );
      final fast = side(full: false);
      final whole = side(full: true);
      agree(fast, whole, 20, latin, TextOrder.logical, what: 'at 20');
      final first = fast.painter.debugClustersSplit;
      agree(fast, whole, 60, latin, TextOrder.logical, what: 'then at 60');
      expect(fast.painter.debugHeadOnly, isTrue);
      expect(fast.painter.debugClustersSplit - first, lessThan(100));
      // an intrinsic height asks a layout of its width
      fast.painter.intrinsicHeight(120, segmenter: latin);
      expect(fast.painter.debugHeadOnly, isTrue);
      agree(fast, whole, 120, latin, TextOrder.logical, what: 'then at 120');
    });

    test('a head that stopped at the first line break serves every width', () {
      Side side({required bool full}) => Side(
        [('Title\n$long', plain)],
        full: full,
        wrap: TextWrap.none,
        ellipsis: '…',
        align: TextAlign.left,
      );
      final fast = side(full: false);
      final whole = side(full: true);
      agree(fast, whole, 20, latin, TextOrder.logical, what: 'at 20');
      final first = fast.painter.debugClustersSplit;
      expect(first, lessThan(10));
      for (final w in [40, 80, 200]) {
        agree(fast, whole, w, latin, TextOrder.logical, what: 'then at $w');
      }
      expect(fast.painter.debugHeadOnly, isTrue);
      expect(fast.painter.debugClustersSplit, first, reason: 'split once');
    });

    test('grapheme clusters at the cut', () {
      const family = '\u{1F468}‍\u{1F469}‍\u{1F467}';
      const flag = '\u{1F1FA}\u{1F1F8}';
      const accent = 'é';
      for (final unit in [family, flag, accent, 'ạ̈', '\u{1F44D}\u{1F3FD}']) {
        for (var w = 0; w < 24; w++) {
          for (final lead in ['', 'x', 'xy', 'xyz  ']) {
            agreeAll([('$lead${unit * 20}', plain)], w: w);
            agreeAll(
              [('$lead${unit * 20}', plain)],
              w: w,
              wrap: TextWrap.grapheme,
            );
          }
        }
      }
    });

    test('wide CJK at the boundary', () {
      for (var w = 0; w < 14; w++) {
        for (final lead in ['', 'a', 'ab']) {
          for (final wrap in TextWrap.values) {
            agreeAll([('$lead${'世界' * 15}', plain)], w: w, wrap: wrap);
            agreeAll([('${lead}ab${'日本語、' * 9}', plain)], w: w, wrap: wrap);
          }
        }
      }
    });

    test('a tab, and blanks before the cut', () {
      for (var w = 0; w < 16; w++) {
        for (final wrap in TextWrap.values) {
          agreeAll([('ab\tcd\tef\tgh\t${'x' * 30}', plain)], w: w, wrap: wrap);
          agreeAll(
            [('abc${' ' * 12}def${' ' * 12}${'g' * 20}', plain)],
            w: w,
            wrap: wrap,
          );
          agreeAll([('${' ' * 20}abc def', plain)], w: w, wrap: wrap);
          agreeAll([('ab${' ' * 40}', plain)], w: w, wrap: wrap);
          agreeAll(
            [('ab  　 \t cd${' ' * 3}${'e' * 30}', plain)],
            w: w,
            wrap: wrap,
          );
        }
      }
    });

    test('spaces far past the room are split whole', () {
      for (var w = 0; w < 12; w++) {
        for (final wrap in TextWrap.values) {
          agreeAll([('ab${' ' * 60}${'cd' * 20}', plain)], w: w, wrap: wrap);
          agreeAll(
            [('ab${' ' * (w + 20)}${'cd' * 20}', plain)],
            w: w,
            wrap: wrap,
          );
          agreeAll([('${' ' * 80}x${' ' * 80}', plain)], w: w, wrap: wrap);
        }
      }
      final p = TextPainter(
        [('ab${' ' * 60}${'cd' * 20}', plain)],
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      )..layout(const BoxConstraints(0, 5, 0, 1), segmenter: latin);
      expect(p.debugHeadOnly, isFalse, reason: 'the head gave up');
      expect(p.debugDiffFromFresh(latin), isNull);
    });

    test('the ellipsis wider than the room, and a multi-column one', () {
      for (final e in ['…', '...', '', '世', '.. ..', '··']) {
        for (var w = 0; w < 9; w++) {
          for (final wrap in TextWrap.values) {
            agreeAll([(long, plain)], w: w, wrap: wrap, ellipsis: e);
            agreeAll(
              [('hello wide ${'世' * 20}', plain)],
              w: w,
              wrap: wrap,
              ellipsis: e,
            );
          }
        }
      }
    });

    test('ambiguous width 2, and legacy text mode', () {
      for (final seg in [ambiguous2, legacy]) {
        for (var w = 0; w < 14; w++) {
          for (final text in [
            '±°¡${'±x' * 12}',
            'éé${'ä' * 12}',
            '\u{1F468}‍\u{1F469}${'ab' * 10}\u{1F1FA}\u{1F1F8}',
            'ab​cd${'ef ' * 10}',
          ]) {
            for (final wrap in TextWrap.values) {
              agreeAll([(text, plain)], w: w, wrap: wrap, segmenter: seg);
              agreeAll(
                [(text, plain)],
                w: w,
                wrap: wrap,
                segmenter: seg,
                ellipsis: '...',
              );
            }
          }
        }
      }
    });

    test('a text that fits, or ends at the room', () {
      for (final wrap in TextWrap.values) {
        for (final t in ['', 'a', 'abc', 'abc ', 'abc   ', 'abcde', 'abcdef']) {
          for (var w = 0; w < 9; w++) {
            agreeAll([(t, plain)], w: w, wrap: wrap);
          }
        }
      }
      final p = TextPainter(
        [('abc', plain)],
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      )..layout(const BoxConstraints(0, 20, 0, 1), segmenter: latin);
      expect(p.debugHeadOnly, isFalse, reason: 'the text ended in the room');
    });

    test('line breaks in the text', () {
      for (final wrap in TextWrap.values) {
        for (final t in [
          'abc\ndef',
          'abc\r\ndef',
          'abcdefghijk\nlmnopqrstuv',
          '${'a' * 30}\n${'b' * 30}',
          '\n${'a' * 30}',
          'ab\n',
          'ab\n\n\n${'c' * 30}',
          'ab cd',
          'abc\rdef${'g' * 30}',
        ]) {
          for (var w = 0; w < 14; w++) {
            agreeAll([(t, plain)], w: w, wrap: wrap);
          }
        }
      }
    });

    test('spans with their pens, empty ones among them', () {
      for (final wrap in TextWrap.values) {
        for (var w = 0; w < 16; w++) {
          agreeAll(
            [
              ('', plain),
              ('hello ', red),
              ('', blue),
              ('big 世界 ', blue),
              ('wide ', plain),
              ('world ${'x' * 30}', red),
              ('', plain),
            ],
            w: w,
            wrap: wrap,
          );
        }
      }
    });

    test('every alignment', () {
      for (final align in TextAlign.values) {
        for (var w = 0; w < 14; w++) {
          for (final wrap in TextWrap.values) {
            agreeAll(
              [('one two three four five six ${'x' * 30}', plain)],
              w: w,
              wrap: wrap,
              align: align,
            );
          }
        }
      }
    });

    test('visual order: text with nothing to reorder stays a head', () {
      final p =
          TextPainter(
            [(long, plain)],
            wrap: TextWrap.none,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          )..layout(
            const BoxConstraints(0, 20, 0, 1),
            segmenter: latin,
            order: TextOrder.visual,
          );
      expect(p.debugHeadOnly, isTrue);
      for (var w = 0; w < 14; w++) {
        agreeAll([(long, plain)], w: w, order: TextOrder.visual);
      }
    });

    test('visual order: right-to-left text is resolved as a whole', () {
      for (final wrap in TextWrap.values) {
        for (final t in [
          '${'abc ' * 10}אבג ${'def ' * 10}',
          'אבג ${'abc ' * 20}',
          '${'abc ' * 20}אבג (xyz) 123',
          'العربية ${'x' * 40} א',
          '${'x' * 40} אבגדהוזחטיך',
          '(${'a' * 10}) א [${'b' * 30}]',
        ]) {
          for (var w = 0; w < 24; w += 1) {
            agreeAll([(t, plain)], w: w, wrap: wrap, order: TextOrder.visual);
            agreeAll([(t, plain)], w: w, wrap: wrap);
          }
        }
      }
      // the order changes after a head layout
      final p = TextPainter(
        [('${'abc ' * 20}אבג tail', plain)],
        wrap: TextWrap.none,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      )..layout(const BoxConstraints(0, 20, 0, 1), segmenter: latin);
      expect(p.debugHeadOnly, isTrue);
      p.layout(
        const BoxConstraints(0, 20, 0, 1),
        segmenter: latin,
        order: TextOrder.visual,
      );
      expect(p.debugHeadOnly, isFalse);
      expect(p.debugDiffFromFresh(latin), isNull);
    });

    test('random text, settings and widths', () {
      final random = Random(0x7e47);
      const pieces = [
        'a',
        'b',
        'cd',
        ' ',
        '  ',
        'word',
        '-',
        'x-y',
        '\t',
        '世',
        '界、',
        'é',
        '\u{1F468}‍\u{1F469}',
        '\u{1F1FA}\u{1F1F8}',
        '±',
        '​',
        '\n',
        '\r\n',
        'א',
        'ا',
        '1',
        '(',
        ')',
        '̀',
        '\u{1F44D}\u{1F3FD}',
      ];
      const ellipses = ['…', '...', '', '世', '-'];
      final segmenters = [latin, ambiguous2, legacy];
      var heads = 0;
      for (var i = 0; i < 1500; i++) {
        final spans = <(String, Pen)>[];
        for (var k = random.nextInt(4) + 1; k > 0; k--) {
          final b = StringBuffer();
          for (var n = random.nextInt(40); n > 0; n--) {
            b.write(pieces[random.nextInt(pieces.length)]);
          }
          spans.add((b.toString(), [plain, red, blue][random.nextInt(3)]));
        }
        agreeAll(
          spans,
          w: random.nextInt(30),
          wrap: TextWrap.values[random.nextInt(3)],
          ellipsis: ellipses[random.nextInt(ellipses.length)],
          align: TextAlign.values[random.nextInt(TextAlign.values.length)],
          segmenter: segmenters[random.nextInt(3)],
          order: random.nextInt(3) == 0 ? TextOrder.visual : TextOrder.logical,
          tag: 'random $i',
        );
        if (headCase) {
          heads++;
        }
      }
      expect(heads, greaterThan(300), reason: 'most are laid out as heads');
    });
  });

  group('where the head ends is a cluster boundary the scan reaches', () {
    // The end is found before the scan (`_headEnd`) and bounds its loop, so
    // the clusters split are exactly those up to it: counted here, and
    // compared with the full layout over every width.
    int split(
      List<(String, Pen)> spans,
      int w, {
      TextSegmenter? segmenter,
      bool headOnly = true,
    }) {
      final p = TextPainter(
        spans,
        wrap: TextWrap.none,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      )..layout(BoxConstraints(0, w, 0, 1), segmenter: segmenter ?? latin);
      expect(p.debugHeadOnly, headOnly, reason: '$spans w=$w');
      return p.debugClustersSplit;
    }

    void same(List<(String, Pen)> spans, {TextSegmenter? segmenter}) {
      for (var w = 0; w < 14; w++) {
        agreeAll(spans, w: w, segmenter: segmenter);
      }
    }

    final tail = 'jklmnopqrstuvwxyz' * 8;

    test('a head ending at the end of a span', () {
      final spans = [('abcdefghi', plain), (tail, red)];
      expect(split(spans, 8), 9);
      same(spans);
      same([('abcdefghi', plain), ('', red), (tail, red)]);
    });

    test('marks that continue in the next span', () {
      final spans = [('abcdefgh', plain), ('\u0301ijk$tail', red)];
      expect(split(spans, 8), 9);
      same(spans);
      same([('abcdefg', plain), ('h\u0301', red), ('\u0301i$tail', blue)]);
      same(spans, segmenter: legacy);
    });

    test('a mark without a base is dropped, and the scan steps on', () {
      for (final seg in [latin, legacy]) {
        same([('\u0903\u0903\u0301abcdefgh$tail', plain)], segmenter: seg);
        same([('\u0903a\u0903\u0903bcdefgh$tail', plain)], segmenter: seg);
        same([('abcdefg', plain), ('\u0903\u0903\u0301hi$tail', red)]);
      }
    });

    test('a zero width space after the stop is not read', () {
      same([('abcdefghi', plain), ('\u200B$tail', red)]);
      same([('abcdefghi\u200B$tail', plain)]);
    });

    test('CR LF at the stop', () {
      for (final seg in [latin, legacy]) {
        final spans = [('abc\r\n$tail', plain)];
        expect(split(spans, 8, segmenter: seg), 4);
        same(spans, segmenter: seg);
        // the CR ends one span and the LF starts the next
        same([('abc\r', plain), ('\n$tail', red)], segmenter: seg);
        same([('abcdefgh\r\n$tail', plain)], segmenter: seg);
        same([('abcdefghi\r\n$tail', plain)], segmenter: seg);
        same([('a\rb\n$tail', plain)], segmenter: seg);
      }
    });

    test('tabs, wide, ambiguous and spaces at the stop', () {
      for (final seg in [latin, legacy, ambiguous2]) {
        same([('a\tb\t\tc\td$tail', plain)], segmenter: seg);
        same([('世界世界世界世界世界$tail', plain)], segmenter: seg);
        same([('a世b世c世d世$tail', plain)], segmenter: seg);
        same([('±°±°±°±°±°±°$tail', plain)], segmenter: seg);
        same([('ab${' ' * 40}$tail', plain)], segmenter: seg);
        same([('ab${' ' * 5}$tail', plain)], segmenter: seg);
        same([('é́e\u0301 x\u{1F44D}\u{1F3FD}y$tail', plain)], segmenter: seg);
      }
    });
  });

  group('a head that is edited, or asked for more', () {
    String text(int n, [String piece = 'abcdefghij ']) => piece * n;

    TextPainter make(List<(String, Pen)> spans, {bool full = false}) =>
        TextPainter(
          spans,
          wrap: TextWrap.none,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        )..debugForceFull = full;

    test('an edit after the first layout', () {
      final edits = <List<(String, Pen)>>[
        [(text(50), plain)],
        [('X${text(50)}', plain)],
        [('abc', plain)],
        [(text(50), red)],
        [(text(50), plain), (text(5), red)],
        [('', plain), (text(3), blue), (text(50), plain)],
        [('${text(50)}\n${text(5)}', plain)],
        [('世界${text(50)}', plain)],
        [(text(60), plain)],
      ];
      final a = Side(
        [(text(100), plain)],
        full: false,
        wrap: TextWrap.none,
        ellipsis: '…',
        align: TextAlign.left,
      );
      final b = Side(
        [(text(100), plain)],
        full: true,
        wrap: TextWrap.none,
        ellipsis: '…',
        align: TextAlign.left,
      );
      for (final e in [...edits, ...edits.reversed]) {
        a.painter.spans = e;
        b.painter.spans = e;
        agree(
          a,
          b,
          20,
          latin,
          TextOrder.logical,
          what: 'edit to ${e.length} spans',
        );
      }
      expect(a.painter.debugDiffFromFresh(latin), isNull);
    });

    test('an edit after the head leaves it a head, split anew', () {
      final p = make([(text(500), plain)])
        ..layout(const BoxConstraints(0, 20, 0, 1), segmenter: latin);
      expect(p.debugHeadOnly, isTrue);
      final was = p.debugClustersSplit;
      p
        ..spans = [('${text(500)}!', plain)]
        ..layout(const BoxConstraints(0, 20, 0, 1), segmenter: latin);
      expect(p.debugHeadOnly, isTrue);
      expect(p.debugClustersSplit - was, lessThan(40));
    });

    test('a wider layout splits a head of its width, a narrower one none', () {
      final p = make([(text(500), plain)])
        ..layout(const BoxConstraints(0, 20, 0, 1), segmenter: latin);
      final n = p.debugClustersSplit;
      p.layout(const BoxConstraints(0, 12, 0, 1), segmenter: latin);
      expect(p.debugClustersSplit, n, reason: 'the head serves a narrower one');
      expect(p.debugHeadOnly, isTrue);
      p.layout(const BoxConstraints(0, 60, 0, 1), segmenter: latin);
      expect(p.debugHeadOnly, isTrue, reason: 'a head of 60 columns');
      expect(p.debugClustersSplit - n, lessThan(100));
      expect(p.debugDiffFromFresh(latin), isNull);
    });

    test('a new overflow, wrap, maxLines, ellipsis or segmenter', () {
      const c = BoxConstraints(0, 20, 0, 3);
      for (final change in <void Function(TextPainter)>[
        (p) => p.overflow = TextOverflow.clip,
        (p) => p.overflow = TextOverflow.ellipsisStart,
        (p) => p.maxLines = 2,
        (p) => p.maxLines = null,
        (p) => p.wrap = TextWrap.word,
        (p) => p.ellipsis = '...',
        (p) => p.ellipsis = '',
        (p) => p.align = TextAlign.right,
      ]) {
        final p = make([(text(200), plain)])..layout(c, segmenter: latin);
        final q = make([(text(200), plain)], full: true)
          ..layout(c, segmenter: latin);
        change(p);
        change(q);
        p.layout(c, segmenter: latin);
        q.layout(c, segmenter: latin);
        expect((p.width, p.height), (q.width, q.height));
        expect(p.debugDiffFromFresh(latin), isNull);
        for (var x = 0; x < 22; x++) {
          expect(p.textRangeAt(x, 0), q.textRangeAt(x, 0));
        }
      }
      final p = make([(text(200), plain)])
        ..layout(c, segmenter: latin)
        ..layout(c, segmenter: ambiguous2);
      expect(p.debugDiffFromFresh(ambiguous2), isNull);
      p.layout(c, segmenter: legacy);
      expect(p.debugDiffFromFresh(legacy), isNull);
    });

    test('the intrinsic height at another width', () {
      final p = make([(text(500), plain)])
        ..layout(const BoxConstraints(0, 20, 0, 1), segmenter: latin);
      final q = make([(text(500), plain)], full: true);
      for (final w in [5, 20, 3, 80, 1]) {
        expect(
          p.intrinsicHeight(w, segmenter: latin),
          q.intrinsicHeight(w, segmenter: latin),
        );
      }
    });
  });

  group('the debug counters of a head', () {
    test(
      'debugClustersSplit counts the clusters split, the whole text later',
      () {
        final p = TextPainter(
          [('abcdefghij' * 100, plain)],
          wrap: TextWrap.none,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        )..layout(const BoxConstraints(0, 10, 0, 1), segmenter: latin);
        expect(p.debugClustersSplit, inInclusiveRange(10, 40));
        expect(p.maxIntrinsicWidth(latin), 1000);
        expect(p.debugClustersSplit, greaterThanOrEqualTo(1000));
        expect(p.debugHeadOnly, isFalse);
      },
    );

    test('debugLinesBroken counts the lines broken', () {
      final p = TextPainter(
        [('abc def ' * 100, plain)],
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      )..layout(const BoxConstraints(0, 10, 0, 1), segmenter: latin);
      expect(p.debugHeadOnly, isTrue);
      expect(p.debugLinesBroken, inInclusiveRange(1, 2));
    });

    test('debugOffsetsFound counts the finds, textRangeAt asks for one', () {
      final p = TextPainter(
        [('abcdefghij' * 100, plain)],
        wrap: TextWrap.none,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      )..layout(const BoxConstraints(0, 10, 0, 1), segmenter: latin);
      expect(p.debugOffsetsFound, 0);
      expect(p.textRangeAt(9, 0), (
        9,
        1000,
      ), reason: 'the ellipsis, to the end');
      expect(p.debugOffsetsFound, 1);
      expect(p.debugHeadOnly, isTrue, reason: 'a query splits no more');
    });

    test(
      'debugLevelsResolved and debugBidiUnitsCopied see no text in a head',
      () {
        final p =
            TextPainter(
              [('abcdefghij' * 100, plain)],
              wrap: TextWrap.none,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            )..layout(
              const BoxConstraints(0, 10, 0, 1),
              segmenter: latin,
              order: TextOrder.visual,
            );
        expect(p.debugHeadOnly, isTrue);
        expect(p.debugLevelsResolved, 0);
        expect(p.debugBidiUnitsCopied, 0);
        expect(p.debugLinesOrdered, 0);
        // with something to reorder the whole text is resolved
        final r =
            TextPainter(
              [('abcdefghij' * 100 + 'א', plain)],
              wrap: TextWrap.none,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            )..layout(
              const BoxConstraints(0, 10, 0, 1),
              segmenter: latin,
              order: TextOrder.visual,
            );
        expect(r.debugHeadOnly, isFalse);
        expect(r.debugLevelsResolved, 1001);
      },
    );

    test(
      'debugDiffFromFresh splits the rest and compares with a fresh one',
      () {
        final p = TextPainter(
          [('abcdefghij' * 100, plain)],
          wrap: TextWrap.none,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        )..layout(const BoxConstraints(0, 10, 0, 1), segmenter: latin);
        expect(p.debugHeadOnly, isTrue);
        expect(p.debugDiffFromFresh(latin), isNull);
        expect(p.debugHeadOnly, isFalse);
        p.layout(const BoxConstraints(0, 10, 0, 1), segmenter: latin);
        expect(p.debugDiffFromFresh(latin), isNull);
      },
    );
  });

  group('what a head layout draws', () {
    test('the cut text with the ellipsis, the hidden text under it', () {
      final p = TextPainter(
        [('hello ', plain), ('big world', red)],
        wrap: TextWrap.none,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      )..layout(const BoxConstraints(0, 8, 0, 1), segmenter: latin);
      final glyphs = GlyphTable();
      final surface = Surface(10, 1);
      p.paint(Canvas(surface, StyleTable(), glyphs), 0, 0);
      final row = [
        for (var x = 0; x < 10; x++)
          if ((surface.cells[x] & kCont) == 0)
            glyphs.stringOf(surface.cells[x]),
      ].join();
      expect(row, startsWith('hello b…'));
      expect(p.cellAt(7, 0), (start: 7, end: 15, isEllipsis: true));
      expect(p.cellAt(6, 0), (start: 6, end: 7, isEllipsis: false));
      expect(p.width, 8);
    });
  });
}
