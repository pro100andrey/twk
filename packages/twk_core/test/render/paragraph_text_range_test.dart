// A paragraph tells the text a cell of it shows, as offsets into the text
// of its spans joined: where selecting with the mouse starts and ends.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

const plain = Pen();
const red = Pen(fg: Color.rgb(200, 0, 0));

/// [text] (or [spans]) laid out [width] columns wide.
RenderParagraph laid(
  String text,
  int width, {
  List<(String, Pen)>? spans,
  TextWrap wrap = TextWrap.word,
  TextAlign align = TextAlign.left,
  TextOverflow overflow = TextOverflow.clip,
  int? maxLines,
}) => RenderParagraph(
  spans ?? [(text, plain)],
  wrap: wrap,
  align: align,
  overflow: overflow,
  maxLines: maxLines,
)..layout(BoxConstraints(width, width, 0, 100));

/// The ranges of the cells of row [y] from the column left of the
/// paragraph to the one right of it, `start-end`, or `start` when empty.
List<String> row(RenderParagraph p, int y) => [
  for (var x = -1; x <= p.width; x++)
    switch (p.textRangeAt(x, y)) {
      (final s, final e) when s == e => '$s',
      (final s, final e) => '$s-$e',
    },
];

void main() {
  test('the cluster a cell shows, by offsets into the spans joined; right '
      'of the text the end, left of it the start', () {
    final p = laid('', 7, spans: [('hel', plain), ('lo', red)]);
    expect(row(p, 0), [
      '0',
      '0-1',
      '1-2',
      '2-3',
      '3-4',
      '4-5',
      '5',
      '5',
      '5',
    ]);
  });

  test('a wrapped row: right of its text where the next row starts, after '
      'the spaces it hangs', () {
    final p = laid('hello  world', 7);
    expect(p.height, 2);
    expect(row(p, 0), [
      '0',
      '0-1',
      '1-2',
      '2-3',
      '3-4',
      '4-5',
      '7',
      '7',
      '7',
    ]);
    expect(row(p, 1), [
      '7',
      '7-8',
      '8-9',
      '9-10',
      '10-11',
      '11-12',
      '12',
      '12',
      '12',
    ]);
  });

  test('above the first row the start of the text, below the last its '
      'end', () {
    final p = laid('hello world', 7);
    expect(p.textRangeAt(3, -1), (0, 0));
    expect(p.textRangeAt(-5, -1), (0, 0));
    expect(p.textRangeAt(3, 2), (11, 11));
    expect(p.textRangeAt(30, 9), (11, 11));
  });

  test('a line break: right of the row after it, CR LF and what takes no '
      'cell with the cluster after them', () {
    final p = laid('one\r\ntwo', 7);
    expect(row(p, 0), ['0', '0-1', '1-2', '2-3', '5', '5', '5', '5', '5']);
    expect(row(p, 1).sublist(0, 3), ['5', '5-6', '6-7']);
    final zw = laid('a​b', 7);
    expect(row(zw, 0).sublist(0, 4), ['0', '0-1', '1-3', '3']);
  });

  test('either cell of a wide cluster, a cluster of several code points', () {
    final p = laid('a中b👍🏽é', 8);
    expect(row(p, 0), [
      '0',
      '0-1',
      '1-2',
      '1-2',
      '2-3',
      '3-7',
      '3-7',
      '7-9',
      '9',
      '9',
    ]);
  });

  test('a row placed across its width: left of its text where it starts', () {
    final center = laid('ab', 6, align: TextAlign.center);
    expect(row(center, 0), ['0', '0', '0', '0-1', '1-2', '2', '2', '2']);
    final right = laid('ab', 6, align: TextAlign.right);
    expect(row(right, 0), ['0', '0', '0', '0', '0', '0-1', '1-2', '2']);
  });

  test('a justified row: a gap it stretches is the space before it', () {
    final p = laid('aa bb cc dd', 9, align: TextAlign.justify);
    expect(p.height, 2);
    expect(row(p, 0), [
      '0',
      '0-1',
      '1-2',
      '2-3',
      '2-3',
      '3-4',
      '4-5',
      '5-6',
      '6-7',
      '7-8',
      '9',
    ]);
  });

  test('an ellipsis: the clusters it stands for', () {
    const text = 'abcdefgh';
    String at(TextOverflow overflow, int x) {
      final (s, e) = laid(
        text,
        5,
        overflow: overflow,
        maxLines: 1,
      ).textRangeAt(x, 0);
      return text.substring(s, e);
    }

    expect(at(TextOverflow.ellipsis, 3), 'd');
    expect(at(TextOverflow.ellipsis, 4), 'efgh');
    expect(at(TextOverflow.ellipsisMiddle, 1), 'b');
    expect(at(TextOverflow.ellipsisMiddle, 2), 'cdef');
    expect(at(TextOverflow.ellipsisMiddle, 3), 'g');
    expect(at(TextOverflow.ellipsisStart, 0), 'abcd');
    expect(at(TextOverflow.ellipsisStart, 1), 'e');
  });

  test('lines cut off at the start each: an ellipsis stands for the start '
      'of its own line, after the line break before it', () {
    const text = 'abcdefgh\nijklmnop';
    final p = laid(
      text,
      5,
      wrap: TextWrap.none,
      overflow: TextOverflow.ellipsisStart,
    );
    String at(int x, int y) {
      final (s, e) = p.textRangeAt(x, y);
      return s == e ? '$s' : text.substring(s, e);
    }

    expect(
      [for (var x = 0; x < 6; x++) at(x, 0)],
      [
        'abcd',
        'e',
        'f',
        'g',
        'h',
        '9',
      ],
    );
    expect(
      [for (var x = 0; x < 6; x++) at(x, 1)],
      [
        'ijkl',
        'm',
        'n',
        'o',
        'p',
        '17',
      ],
    );
  });

  test('rows cut off: right of the last row shown, the end of the text', () {
    final p = laid('one two three', 4, maxLines: 1);
    expect(p.height, 1);
    expect(p.textRangeAt(3, 0), (13, 13));
    expect(p.textRangeAt(2, 0), (2, 3));
  });

  test('new text: the ranges of its layout', () {
    final p = laid('ab', 6)
      ..spans = [('xyz', plain)]
      ..layout(const BoxConstraints(6, 6, 0, 100));
    expect(row(p, 0).sublist(0, 5), ['0', '0-1', '1-2', '2-3', '3']);
  });

  test('a mark with no base, and the CR of CR LF split code point by code '
      'point, with the cluster after them', () {
    final mark = laid('\u093Fab', 7);
    expect(row(mark, 0).sublist(0, 4), ['0', '0-2', '2-3', '3']);
    final p = RenderParagraph([('one\r\ntwo', plain)]);
    PipelineOwner(() {}, segmenter: TextSegmenter(mode: TextMode.legacy))
      ..root = p
      ..flushLayout(7, 2);
    expect(row(p, 0), ['0', '0-1', '1-2', '2-3', '5', '5', '5', '5', '5']);
    expect(row(p, 1).sublist(0, 5), ['5', '5-6', '6-7', '7-8', '8']);
  });

  test('a layout finds no offsets: the first query after the text is split '
      'does, once', () {
    final p = laid('hello world', 7);
    expect(p.debugOffsetsFound, 0);
    expect(p.textRangeAt(1, 1), (7, 8));
    expect(p.textRangeAt(0, 0), (0, 1));
    expect(p.debugOffsetsFound, 1);
    p.layout(const BoxConstraints(5, 5, 0, 100));
    expect(p.textRangeAt(0, 1), (6, 7));
    expect(p.debugOffsetsFound, 1);
    p
      ..spans = [('xyz', plain)]
      ..layout(const BoxConstraints(5, 5, 0, 100));
    expect(p.debugOffsetsFound, 1);
    expect(p.textRangeAt(2, 0), (2, 3));
    expect(p.debugOffsetsFound, 2);
  });
}
