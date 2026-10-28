// An edited paragraph splits and breaks again only what the edit can have
// changed. What it keeps must be, cluster for cluster and line for line,
// what the same spans give split and broken from scratch, and it must lay
// out, draw and map cells to text exactly as a fresh paragraph of them
// does: random edits of random mixed-script spans (bidi, emoji sequences,
// combining marks, CJK, line breaks, zero width spaces, lone surrogates),
// in both segmenter modes, at random widths, wraps, overflows, line limits
// and alignments.
import 'dart:math';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

const _pens = [
  Pen(),
  Pen(fg: Color.rgb(200, 0, 0)),
  Pen(fg: Color.rgb(0, 0, 200)),
];

/// What the text is made of: words of many scripts, spaces, and the
/// sequences that split or join clusters.
const _pieces = [
  'the', 'quick', 'well-known', '-v', '--', '-1', '42', 'x', 'a', 'Z.', //
  ' ', ' ', ' ', '  ', '\t', '\u3000', '\u2003',
  'привет', 'мир', 'αβγ', 'nai\u0308ve', 'e\u0301', '\u0301',
  '你好', '日本語', 'カタカナ', 'ー', '。', '「', '」', 'ゃ', 'ッ', '（', '）',
  '한국어', '\u1100\u1161\u11A8', '\u1100',
  'שלום', 'עולם', 'مرحبا', 'ب\u064E', '١٢٣', '(א)', '[ب]',
  '\u202B', '\u202E', '\u202C', '\u2067', '\u2069', '\u200E', '\u200F',
  '😀', '👨\u200D👩\u200D👧', '🇺🇦', '🇺', '👍🏽', '#\uFE0F\u20E3',
  '❤\uFE0F', '☺\uFE0E', '\u200D', '\uFE0F',
  '\n', '\r\n', '\r', '\u2028', '\u200B', '\u0007', '\u00AD', '—',
  'क\u094Dष', 'नमस\u094Dत\u0947', 'ภาษาไทย', '\uD83D', '\uDE00',
  // Prepend: joins what comes after it
  '\u0600', '\u0605١', '\u0D4E',
];

final class _Rig {
  _Rig(this.random)
    : mode = random.nextBool() ? TextMode.graphemes : TextMode.legacy,
      ambiguous = random.nextInt(4) == 0 ? 2 : 1,
      order = random.nextInt(3) == 0 ? TextOrder.visual : TextOrder.logical {
    screen = Screen(
      _maxWidth,
      _height,
      textMode: mode,
      ambiguousWidth: ambiguous,
    );
    edited = owner();
  }

  static const _maxWidth = 40;
  static const _height = 24;

  final Random random;
  final TextMode mode;
  final int ambiguous;
  final TextOrder order;
  late final Screen screen;
  late final PipelineOwner edited;
  final log = <String>[];

  /// An owner drawing on the screen in the order and mode of this rig.
  PipelineOwner owner() =>
      PipelineOwner(() {}, segmenter: screen.canvas.segmenter)
        ..textOrder = order;

  String piece() => _pieces[random.nextInt(_pieces.length)];

  String text([int most = 8]) {
    final b = StringBuffer();
    for (var n = random.nextInt(most + 1); n > 0; n--) {
      b.write(piece());
    }
    return b.toString();
  }

  (String, Pen) span([int most = 8]) =>
      (text(most), _pens[random.nextInt(_pens.length)]);

  List<(String, Pen)> spans() => [
    for (var n = 1 + random.nextInt(5); n > 0; n--) span(),
  ];

  /// [spans] with one random edit: text typed, deleted or replaced at any
  /// code unit (splitting surrogate pairs and clusters as it may), spans
  /// split, joined, added and taken away, a pen changed, nothing changed.
  List<(String, Pen)> edit(List<(String, Pen)> spans) {
    final s = List.of(spans);
    final k = s.isEmpty ? 0 : random.nextInt(s.length);
    final roll = random.nextInt(20);
    if (s.isEmpty || roll == 0) {
      s.insert(s.isEmpty ? 0 : random.nextInt(s.length + 1), span());
      return s;
    }
    final (t, pen) = s[k];
    final at = random.nextInt(t.length + 1);
    final to = at + random.nextInt(t.length - at + 1);
    switch (roll) {
      case 1 when s.length > 1:
        s.removeAt(k);
      case 2:
        s
          ..[k] = (t.substring(0, at), pen)
          ..insert(k + 1, (t.substring(at), _pens[random.nextInt(3)]));
      case 3 when k + 1 < s.length:
        s
          ..[k] = ('$t${s[k + 1].$1}', pen)
          ..removeAt(k + 1);
      case 4:
        s[k] = (t, _pens[random.nextInt(_pens.length)]);
      case 5:
        s[k] = (String.fromCharCodes(t.codeUnits), pen);
      case 6:
        return this.spans();
      case 7 || 8 || 9:
        // a character typed or taken back, as in a field
        s[k] = random.nextBool() || t.isEmpty
            ? (t.substring(0, at) + piece() + t.substring(at), pen)
            : (t.substring(0, max(0, at - 1)) + t.substring(at), pen);
      case 10 || 11:
        s[k] = (t.substring(0, at) + t.substring(to), pen);
      default:
        s[k] = (t.substring(0, at) + text(3) + t.substring(to), pen);
    }
    return s;
  }

  final _widths = Expando<int>('width');

  /// Lays [p] out [width] wide on [o], as a binding does: all of it again
  /// when the width is new.
  void layOut(RenderParagraph p, PipelineOwner o, int width) {
    if (_widths[o] != width) {
      _widths[o] = width;
      o.markAllDirty();
    }
    if (p.parent == null) {
      o.root = RenderFlex(
        direction: Axis.vertical,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [p],
      );
    }
    o.flushLayout(width, _height);
  }

  /// The cells and pens [p] paints, on a cleared screen.
  List<int> paint(RenderParagraph p) {
    screen.surface.clear();
    screen.canvas.reset();
    p.paint(PaintContext(screen.canvas, screen.surface, screen.presenter));
    return [...screen.surface.cells, ...screen.surface.styles];
  }
}

/// Checks [p], edited, against a paragraph made from scratch of its spans
/// and settings, laid out [width] wide.
void _check(_Rig rig, RenderParagraph p, int width, String context) {
  final reason = '$context\n${rig.log.join('\n')}';
  final diff = p.debugDiffFromFresh();
  expect(diff, isNull, reason: reason);
  final f = RenderParagraph(
    p.spans,
    wrap: p.wrap,
    overflow: p.overflow,
    maxLines: p.maxLines,
    align: p.align,
  );
  rig.layOut(f, rig.owner(), width);
  expect((p.width, p.height), (f.width, f.height), reason: reason);
  expect(rig.paint(p), rig.paint(f), reason: '$reason\npainted');
  final rows = [
    -1,
    0,
    p.height - 1,
    p.height,
    rig.random.nextInt(p.height + 1),
  ];
  for (final y in rows) {
    for (var x = -1; x <= width; x++) {
      expect(
        p.textRangeAt(x, y),
        f.textRangeAt(x, y),
        reason: '$reason\ntext at ($x, $y)',
      );
    }
  }
  expect(
    [
      p.computeMinIntrinsicWidth(0),
      p.computeMaxIntrinsicWidth(0),
      p.computeMinIntrinsicHeight(width),
      p.computeMaxIntrinsicHeight(width ~/ 2 + 1),
    ],
    [
      f.computeMinIntrinsicWidth(0),
      f.computeMaxIntrinsicWidth(0),
      f.computeMinIntrinsicHeight(width),
      f.computeMaxIntrinsicHeight(width ~/ 2 + 1),
    ],
    reason: '$reason\nintrinsics',
  );
}

/// [spans] as text and pen numbers, every code point not printable ASCII
/// as its number.
String _show(List<(String, Pen)> spans) => [
  for (final (t, pen) in spans) '${_escaped(t)}/${_pens.indexOf(pen)}',
].join(' | ');

String _escaped(String t) => [
  for (final r in t.runes)
    if (r < 0x20 || r > 0x7E)
      'U+${r.toRadixString(16)}'
    else
      String.fromCharCode(r),
].join();

void main() {
  test('edited at random, a paragraph keeps what one made from scratch '
      'has, and draws and maps cells to text as it does', () {
    var cases = 0;
    for (var seed = 0; seed < 1000; seed++) {
      final rig = _Rig(Random(seed));
      final r = rig.random;
      var spans = rig.spans();
      var width = 1 + r.nextInt(_Rig._maxWidth);
      final p = RenderParagraph(
        spans,
        wrap: TextWrap.values[r.nextInt(3) == 0 ? r.nextInt(3) : 0],
        overflow: TextOverflow.values[r.nextInt(TextOverflow.values.length)],
        maxLines: r.nextBool() ? null : 1 + r.nextInt(6),
        align: TextAlign.values[r.nextInt(TextAlign.values.length)],
      );
      rig.log.add(
        'seed $seed, ${rig.mode}, ambiguous ${rig.ambiguous}, ${rig.order}, '
        '${p.wrap}, ${p.overflow}, maxLines ${p.maxLines}, ${p.align}',
      );
      rig.layOut(p, rig.edited, width);
      for (var step = 0; step < 16; step++) {
        // one edit or a few before the next layout, the lines counted at
        // the width they were broken at between them at times
        for (var n = 1 + (r.nextInt(4) == 0 ? r.nextInt(3) : 0); n > 0; n--) {
          spans = rig.edit(spans);
          p.spans = spans;
          rig.log.add('step $step: ${_show(spans)}');
          // asked between edits: the lines counted at the width they are
          // broken at, the text split for its width
          switch (r.nextInt(6)) {
            case 0:
              p.computeMinIntrinsicHeight(width);
            case 1:
              p.computeMinIntrinsicWidth(0);
          }
        }
        if (r.nextInt(8) == 0) {
          width = 1 + r.nextInt(_Rig._maxWidth);
          rig.log.add('width $width');
        }
        if (r.nextInt(16) == 0) {
          p.maxLines = r.nextBool() ? null : 1 + r.nextInt(6);
          rig.log.add('maxLines ${p.maxLines}');
        }
        rig.layOut(p, rig.edited, width);
        _check(rig, p, width, 'seed $seed step $step at $width columns');
        cases++;
      }
    }
    expect(cases, 16000);
  });

  test('a character typed into a long paragraph splits about it again, '
      'and breaks again the lines it moves', () {
    final rig = _Rig(Random(1));
    const sentence =
        'The presenter of the core, written in plain Dart — 你好世界, '
        'привет мир, שלום 😀 — breaks lines by word. ';
    final base = [for (var k = 0; k < 120; k++) (sentence, _pens[k % 3])];
    final p = RenderParagraph(base);
    rig.layOut(p, rig.edited, 40);
    expect(p.debugClustersSplit, greaterThan(9000));
    expect(p.debugLinesBroken, greaterThan(300));
    // a word pushed to the next line moves every line after it in text
    // that repeats itself, which then is all broken again: the rest are
    // the line typed into
    var local = 0;
    for (var k = 1; k <= 20; k++) {
      final spans = List.of(base)
        ..[0] = (
          sentence.substring(0, 14) +
              'abcdefghijklmnopqrst'.substring(0, k) +
              sentence.substring(14),
          base.first.$2,
        );
      final split = p.debugClustersSplit;
      final broken = p.debugLinesBroken;
      p.spans = spans;
      rig.layOut(p, rig.edited, 40);
      expect(
        p.debugClustersSplit - split,
        lessThan(8),
        reason: 'clusters split again for character $k',
      );
      if (p.debugLinesBroken - broken <= 3) {
        local++;
      }
      _check(rig, p, 40, 'character $k');
    }
    expect(local, greaterThanOrEqualTo(17));
  });

  test('two edits before a layout, neither moving the text after it, '
      'break the lines of both again', () {
    final rig = _Rig(Random(3));
    final line = 'abcd ' * 4;
    final text = line * 8;
    final p = RenderParagraph([(text, _pens[0])]);
    rig.layOut(p, rig.edited, 20);
    // a letter for another on the first line, and one for an ideograph,
    // as many code units but a cell wider, on the fifth
    final at = 4 * line.length + 2;
    // what an intrinsic width asks splits the first edit on its own
    p.spans = [('x${text.substring(1)}', _pens[0])];
    expect(p.computeMinIntrinsicWidth(0), 4);
    p.spans = [
      ('x${text.substring(1, at)}你${text.substring(at + 1)}', _pens[0]),
    ];
    rig.layOut(p, rig.edited, 20);
    _check(rig, p, 20, 'two edits');
  });

  test('a Prepend typed before where the text is as it was joins the '
      'cluster after it', () {
    // a hyphen a line starts at, the letter or the space before it joined
    // to a Prepend; with the space, a line may break after the hyphen
    const hyphen = 'aaaaaaaaaa-bbbbbbbbbbbbbbbbbb cc';
    const spaced = 'aaaaaaaaa -bbbbbbbbbbbbbbbbbb cc';
    const edits = [
      (hyphen, 'aaaaaaaaa\u0600-bbbbbbbbbbbbbbbbbb cc'),
      (hyphen, spaced),
      (hyphen, 'aaaaaaaa\u0600a-bbbbbbbbbbbbbbbbbb cc'),
      (spaced, 'aaaaaaaaa\u0600 -bbbbbbbbbbbbbbbbbb cc'),
    ];
    for (final mode in TextMode.values) {
      final screen = Screen(20, 8, textMode: mode);
      final o = PipelineOwner(() {}, segmenter: screen.canvas.segmenter);
      for (final (before, after) in edits) {
        final p = RenderParagraph([(before, const Pen())]);
        o
          ..root = p
          ..markAllDirty()
          ..flushLayout(10, 8);
        for (final text in [after, before]) {
          p.spans = [(text, const Pen())];
          o.flushLayout(10, 8);
          expect(p.debugDiffFromFresh(), isNull, reason: '$mode $text');
        }
      }
    }
  });

  test('edits at the edges of spans and lines lay out as from scratch', () {
    final rig = _Rig(Random(2));
    final cases = <List<List<(String, Pen)>>>[
      // typed into an empty span, as into a field after a prompt
      [
        [('> ', _pens[1]), ('', _pens[2])],
        [('> ', _pens[1]), ('a', _pens[2])],
        [('> ', _pens[1]), ('ab', _pens[2])],
        [('> ', _pens[1]), ('', _pens[2])],
      ],
      // a zero width space at the start of the span after the edit
      [
        [('ab', _pens[0]), ('', _pens[1]), ('\u200Bcd', _pens[2])],
        [('ab', _pens[0]), ('x', _pens[1]), ('\u200Bcd', _pens[2])],
        [('ab', _pens[0]), ('', _pens[1]), ('\u200Bcd', _pens[2])],
        [('ab', _pens[0]), ('\u200Bcd', _pens[2])],
      ],
      // CR then LF, LF taken away, a line break at the end
      [
        [('one two\r', _pens[0]), ('three', _pens[1])],
        [('one two\r\nthree', _pens[0])],
        [('one two\rthree\n', _pens[0])],
        [('one two\rthree\n\n', _pens[0])],
        [('one two', _pens[0])],
      ],
      // a mark typed after a plain letter joins it; a ZWJ joins emoji
      [
        [('cafe latte', _pens[0])],
        [('cafe\u0301 latte', _pens[0])],
        [('😀 x', _pens[0])],
        [('😀\u200D😀 x', _pens[0])],
        [('😀\u200D x', _pens[0])],
      ],
    ];
    for (final (k, edits) in cases.indexed) {
      for (final width in [3, 7, 40]) {
        final p = RenderParagraph(
          edits.first,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
        final o = rig.owner();
        rig.layOut(p, o, width);
        for (final spans in edits.skip(1)) {
          p.spans = spans;
          rig.log
            ..clear()
            ..add('case $k at $width: ${_show(spans)}');
          rig.layOut(p, o, width);
          _check(rig, p, width, 'case $k');
        }
      }
    }
  });
}
