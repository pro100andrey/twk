// A TextPainter keeps where each cluster starts and finds where it ends: at
// the start of the next one of its span, else at the span's end, except
// after one the split dropped code units after (a zero width space, a mark
// without a base, the CR of a CR LF in legacy mode), and at the end of a
// head. The ranges the queries give and the text of the clusters of
// several code points drawn hold it, whatever the spans, and a head layout
// gives what the full one does.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

final graphemes = TextSegmenter();
final legacy = TextSegmenter(mode: TextMode.legacy);

/// A painter of [spans] laid out [w] wide by [seg], on one line or more.
TextPainter laid(
  List<String> spans,
  int w, {
  TextSegmenter? seg,
  int? maxLines,
  bool forceFull = false,
}) {
  final p = TextPainter(
    [for (final s in spans) (s, const Pen())],
    wrap: TextWrap.none,
    overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
    maxLines: maxLines,
  )..debugForceFull = forceFull;
  return p
    ..layout(BoxConstraints(maxW: w, maxH: 4), segmenter: seg ?? graphemes);
}

/// The clusters drawn on row [y] of [p], as cellAt gives them, one a
/// cluster.
List<(int, int)> clusters(TextPainter p, int y) => [
  for (var x = 0; x < p.width; x++)
    if (p.cellAt(x, y) case final c? when !c.isEllipsis) (c.start, c.end),
];

/// The text of each cell of the first row of [p] painted.
List<String> cells(TextPainter p) {
  final surface = Surface(p.width, 1);
  final glyphs = GlyphTable();
  p.paint(Canvas(surface, StyleTable(), glyphs), 0, 0);
  return [for (final g in surface.cells.take(p.width)) glyphs.stringOf(g)];
}

void main() {
  mainVisual();
  test('a zero width space goes with the cluster after it, inside a span '
      'and at its end', () {
    expect(clusters(laid(['ab​cd'], 10), 0), [
      (0, 1),
      (1, 2),
      (2, 4),
      (4, 5),
    ]);
    expect(clusters(laid(['ab​', 'cd'], 10), 0), [
      (0, 1),
      (1, 2),
      (2, 4),
      (4, 5),
    ]);
    // the cluster before it ends where it starts, the text tiled
    final p = laid(['ab​', '​cd'], 10);
    expect(clusters(p, 0), [(0, 1), (1, 2), (2, 5), (5, 6)]);
    expect(p.textRangeAt(1, 0), (1, 2));
    expect(p.textRangeAt(2, 0), (2, 5));
  });

  test('a cluster of several code points is drawn without what was dropped '
      'after it', () {
    expect(cells(laid(['é​x'], 3)).take(2), ['é', 'x']);
    expect(cells(laid(['xé​', 'y'], 3)).take(3), [
      'x',
      'é',
      'y',
    ]);
    // at the very end of the text
    expect(cells(laid(['é​'], 2)).first, 'é');
  });

  test('a mark without a base goes with the cluster after it', () {
    // a mark of no width the split drops as it drops a zero width control
    final p = laid(['a\ńb'], 4);
    expect(clusters(p, 0), [(0, 1)]);
    expect(clusters(p, 1), [(2, 4)]);
    // a spacing mark (Devanagari visarga) the canvas drops too
    final q = laid(['a\nःb'], 4);
    expect(clusters(q, 0), [(0, 1)]);
    expect(clusters(q, 1), [(2, 4)]);
    expect(q.textRangeAt(4, 0), (2, 2), reason: 'the next row starts at it');
  });

  test('in legacy mode the CR of CR LF goes with the line break', () {
    final p = laid(['a\r\nb'], 4, seg: legacy);
    expect(clusters(p, 0), [(0, 1)]);
    expect(clusters(p, 1), [(3, 4)]);
    expect(p.textRangeAt(3, 0), (3, 3), reason: 'the next row starts at b');
    // at the end of a span, the line break its last cluster
    final q = laid(['a\r\n', 'b'], 4, seg: legacy);
    expect(clusters(q, 0), [(0, 1)]);
    expect(clusters(q, 1), [(3, 4)]);
  });

  test('a head ending at a cluster that code units follow, or inside a '
      'span, gives what the full layout does', () {
    for (final spans in [
      ['abc​defghijkl'],
      ['ab́c​​defghijkl'],
      ['abcd', 'é​fghijkl'],
      ['abcdé', '​fghijkl'],
      ['a​', 'b​c​d​e​f​ghijkl'],
    ]) {
      for (var w = 2; w <= 8; w++) {
        final head = laid(spans, w, maxLines: 1);
        final full = laid(spans, w, maxLines: 1, forceFull: true);
        expect(head.debugHeadOnly, isTrue, reason: '$spans at $w');
        expect(clusters(head, 0), clusters(full, 0), reason: '$spans at $w');
        expect(cells(head), cells(full), reason: '$spans at $w');
        for (var x = -1; x <= w + 1; x++) {
          expect(
            head.textRangeAt(x, 0),
            full.textRangeAt(x, 0),
            reason: '$spans at $w, x $x',
          );
        }
      }
    }
  });
}

/// The rows [spans] draw [w] wide in visual order.
List<String> visualRows(List<String> spans, int w) {
  final p = TextPainter([for (final s in spans) (s, const Pen())])
    ..layout(
      BoxConstraints(maxW: w, maxH: 8),
      segmenter: graphemes,
      order: TextOrder.visual,
    );
  final surface = Surface(w, p.height);
  final glyphs = GlyphTable();
  p.paint(Canvas(surface, StyleTable(), glyphs), 0, 0);
  return [
    for (var y = 0; y < p.height; y++)
      [
        for (var x = 0; x < w; x++) glyphs.stringOf(surface.cells[y * w + x]),
      ].join(),
  ];
}

void mainVisual() {
  test('in visual order, text split into spans where code units are '
      'dropped draws as the text in one span does', () {
    for (final spans in [
      ['abc ', '​​​אבג def'],
      ['שלום ', '​עולם', '​​ abc'],
      ['x​', '​​דהו ', 'ok'],
    ]) {
      expect(
        visualRows(spans, 12),
        visualRows([spans.join()], 12),
        reason: '$spans',
      );
    }
  });
}
