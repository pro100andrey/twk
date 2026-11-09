// columnsOf: where a range of the text is drawn on a row, the reverse of
// cellAt. Literal columns for a few rows; then, over rows in either order,
// cut, justified and wide, the columns of every cluster and of every span
// are those of the cells cellAt says draw text of it.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// [spans] laid out [width] wide by an owner drawing text in [order].
RenderParagraph laid(
  List<String> spans,
  int width, {
  TextOrder order = TextOrder.logical,
  TextWrap wrap = TextWrap.none,
  TextOverflow overflow = TextOverflow.clip,
  TextAlign align = TextAlign.left,
  int? maxLines,
}) {
  final p = RenderParagraph(
    [for (final s in spans) (s, const Pen())],
    wrap: wrap,
    overflow: overflow,
    align: align,
    maxLines: maxLines,
  );
  PipelineOwner(() {}, segmenter: TextSegmenter())
    ..textOrder = order
    ..root = RenderFlex(
      direction: Axis.vertical,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [p],
    )
    ..flushLayout(width, 6);
  return p;
}

/// The columns of row [y] of [p] that [RenderParagraph.cellAt] says draw
/// text of [start, end), as columnsOf should give them.
(int, int)? fromCells(RenderParagraph p, int start, int end, int y) {
  int? first;
  int? last;
  for (var x = 0; x < p.width; x++) {
    final c = p.cellAt(x, y);
    if (c != null && !c.isEllipsis && c.start < end && c.end > start) {
      first ??= x;
      last = x + 1;
    }
  }
  return first == null ? null : (first, last!);
}

void main() {
  PipelineOwner.debugCheckIntrinsicsByDefault = true;
  test('a span of a row in stored order is where its text is', () {
    final p = laid(['one ', 'two'], 20);
    expect(p.columnsOf(0, 4, 0), (0, 4));
    expect(p.columnsOf(4, 7, 0), (4, 7));
    expect(p.columnsOf(5, 6, 0), (5, 6));
  });

  test('a wide cluster takes both its columns', () {
    final p = laid(['a', '日本', 'b'], 20);
    expect(p.columnsOf(1, 3, 0), (1, 5));
    expect(p.columnsOf(2, 3, 0), (3, 5));
    expect(p.columnsOf(3, 4, 0), (5, 6));
  });

  test('in visual order a right-to-left span is where the row draws it, '
      'not where it would be stored', () {
    // drawn: end ‹ טחז ‹ והד ‹ גבא, the row right to left
    final p = laid(
      ['אבג', ' › ', 'דהו', ' › ', 'זחט', ' › ', 'end'],
      30,
      order: TextOrder.visual,
    );
    expect(p.columnsOf(0, 3, 0), (18, 21));
    expect(p.columnsOf(6, 9, 0), (12, 15));
    expect(p.columnsOf(12, 15, 0), (6, 9));
    expect(p.columnsOf(18, 21, 0), (0, 3));
  });

  test('text under an ellipsis, cut off or on another row has none', () {
    final cut = laid(['abc', 'defgh'], 5, overflow: TextOverflow.ellipsis);
    expect(cut.columnsOf(0, 3, 0), (0, 3));
    expect(cut.columnsOf(3, 4, 0), (3, 4));
    expect(cut.columnsOf(4, 8, 0), isNull, reason: 'under the ellipsis');
    final clipped = laid(['abcdefgh'], 5);
    expect(clipped.columnsOf(6, 8, 0), isNull);
    final wrapped = laid(['one two'], 4, wrap: TextWrap.word);
    expect(wrapped.columnsOf(4, 7, 0), isNull);
    expect(wrapped.columnsOf(4, 7, 1), (0, 3));
  });

  test('an empty range, a row out of the text and no layout have none', () {
    final p = laid(['abc'], 5);
    expect(p.columnsOf(1, 1, 0), isNull);
    expect(p.columnsOf(0, 3, -1), isNull);
    expect(p.columnsOf(0, 3, 1), isNull);
    expect(RenderParagraph([('abc', const Pen())]).columnsOf(0, 3, 0), isNull);
  });

  group('it is the reverse of cellAt', () {
    final cases = {
      'stored order': laid(['ab ', 'שלום', ' cd'], 20),
      'visual order': laid(
        ['ab ', 'שלום', ' עולם', ' cd'],
        20,
        order: TextOrder.visual,
      ),
      'a right-to-left row': laid(
        ['שלום ', 'abc', ' עולם'],
        20,
        order: TextOrder.visual,
        align: TextAlign.right,
      ),
      'cut at the end': laid(
        ['abcdef', 'ghij'],
        7,
        overflow: TextOverflow.ellipsis,
      ),
      'cut in the middle': laid(
        ['abcdef', 'ghij'],
        7,
        overflow: TextOverflow.ellipsisMiddle,
      ),
      'cut in visual order': laid(
        ['שלום ', 'עולם ', 'abc'],
        8,
        order: TextOrder.visual,
        overflow: TextOverflow.ellipsis,
      ),
      'justified': laid(
        ['one two ', 'three four five'],
        12,
        wrap: TextWrap.word,
        align: TextAlign.justify,
      ),
      'wide and centred': laid(
        ['日本', ' x ', '語'],
        12,
        align: TextAlign.center,
      ),
    };
    for (final MapEntry(key: name, value: p) in cases.entries) {
      test(name, () {
        final text = [for (final (s, _) in p.spans) s].join();
        var checked = 0;
        for (var y = 0; y < p.height; y++) {
          // each cluster drawn on the row, and each span
          final ranges = <(int, int)>{
            for (var x = 0; x < p.width; x++)
              if (p.cellAt(x, y) case final c? when !c.isEllipsis)
                (c.start, c.end),
          };
          var at = 0;
          for (final (s, _) in p.spans) {
            ranges.add((at, at + s.length));
            at += s.length;
          }
          ranges.add((0, text.length));
          for (final (start, end) in ranges) {
            expect(
              p.columnsOf(start, end, y),
              fromCells(p, start, end, y),
              reason: 'row $y, [$start, $end)',
            );
            checked++;
          }
        }
        expect(checked, greaterThan(p.height));
      });
    }
  });
}
