// A TextPainter finds where each cluster starts from how far the one before
// it in its span is, a checkpoint every 64 clusters and the start of each
// span's first: over texts of many blocks, with clusters and dropped runs
// of 15 code units or more, edited at random anywhere, what it finds is
// what a painter split from scratch has, and so are the ranges its queries
// give and the clusters of several code points it draws.
import 'dart:math';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// What the texts are made of: words, spaces, clusters and runs the split
/// drops, some of 15 code units or more.
final List<String> _pieces = [
  'the', 'quick', 'brown', 'fox', 'a', 'x', ' ', ' ', '  ', '\t', //
  'привет', '你好', 'é', '😀', '👨‍👩‍👧‍👦', '🇺🇦',
  '\n', '\r\n', '​', 'ः', 'क्ष',
  // a cluster of 17 code units, and runs of 16 dropped after a cluster
  'a${'́' * 16}',
  '​' * 16,
  '\u0007' * 20,
];

const _width = 30;

final class _Rig {
  _Rig(this.random)
    : seg = TextSegmenter(
        mode: random.nextInt(3) == 0 ? TextMode.legacy : TextMode.graphemes,
      );

  final Random random;
  final TextSegmenter seg;

  String piece() => _pieces[random.nextInt(_pieces.length)];

  String text(int most) {
    final b = StringBuffer();
    for (var n = random.nextInt(most + 1); n > 0; n--) {
      b.write(piece());
    }
    return b.toString();
  }

  List<(String, Pen)> spans() => [
    for (var n = 1 + random.nextInt(6); n > 0; n--) (text(60), const Pen()),
  ];

  /// [spans] with one edit anywhere: typed, deleted, replaced, a span
  /// added, taken away, split or joined.
  List<(String, Pen)> edit(List<(String, Pen)> spans) {
    final s = List.of(spans);
    final k = random.nextInt(s.length);
    final t = s[k].$1;
    final at = random.nextInt(t.length + 1);
    final to = at + random.nextInt(min(t.length - at, 40) + 1);
    switch (random.nextInt(10)) {
      case 0:
        s.insert(random.nextInt(s.length + 1), (text(20), const Pen()));
      case 1 when s.length > 1:
        s.removeAt(k);
      case 2:
        s
          ..[k] = (t.substring(0, at), const Pen())
          ..insert(k + 1, (t.substring(at), const Pen()));
      case 3 when k + 1 < s.length:
        s
          ..[k] = ('$t${s[k + 1].$1}', const Pen())
          ..removeAt(k + 1);
      case 4 || 5 || 6:
        s[k] = (t.substring(0, at) + piece() + t.substring(at), const Pen());
      case 7:
        s[k] = (t.substring(0, at) + t.substring(to), const Pen());
      default:
        s[k] = (t.substring(0, at) + text(4) + t.substring(to), const Pen());
    }
    return s;
  }

  TextPainter painter(List<(String, Pen)> spans) => TextPainter(spans)
    ..layout(
      const BoxConstraints(maxW: _width, maxH: 1 << 20),
      segmenter: seg,
    );

  /// What [p] answers and draws, cell by cell over its first rows, and
  /// the ranges between them.
  List<Object?> answers(TextPainter p) {
    final rows = min(p.height, 40);
    final surface = Surface(_width, rows);
    final glyphs = GlyphTable();
    p.paint(Canvas(surface, StyleTable(), glyphs), 0, 0);
    return [
      for (var y = 0; y < rows; y++)
        for (var x = -1; x <= _width; x++) ...[
          p.cellAt(x, y),
          p.textRangeAt(x, y),
          if (x >= 0 && x < _width)
            glyphs.stringOf(surface.cells[y * _width + x]),
        ],
    ];
  }
}

void main() {
  test('edited at random, a long text starts its clusters where a text '
      'split from scratch does', () {
    var checked = 0;
    for (var seed = 0; seed < 40; seed++) {
      final rig = _Rig(Random(seed));
      var spans = rig.spans();
      final p = rig.painter(spans);
      for (var round = 0; round < 25; round++) {
        spans = rig.edit(spans);
        p
          ..spans = spans
          ..layout(
            const BoxConstraints(maxW: _width, maxH: 1 << 20),
            segmenter: rig.seg,
          );
        final reason = 'seed $seed, round $round';
        // most edits made with nothing asked for in between: on
        // checkpoints not found yet as on those found
        if (seed.isOdd && round % 4 != 3) {
          checked++;
          continue;
        }
        expect(p.debugDiffFromFresh(rig.seg), isNull, reason: reason);
        if (round % 5 == 4) {
          expect(
            rig.answers(p),
            rig.answers(rig.painter(spans)),
            reason: reason,
          );
        }
        checked++;
      }
    }
    expect(checked, 1000);
  });

  test('the texts span many checkpoints and keep counts aside', () {
    // the generator makes what the test is about: texts of hundreds of
    // clusters, and runs of 15 code units or more
    final rig = _Rig(Random(1));
    final lengths = [
      for (var i = 0; i < 20; i++)
        rig.spans().fold(0, (n, s) => n + s.$1.length),
    ];
    expect(lengths.where((n) => n > 640), isNotEmpty);
    expect(_pieces.where((p) => p.length >= 16), hasLength(3));
  });
}
