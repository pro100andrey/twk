// An edited paragraph in visual order resolves again only the levels the
// edit can have changed (UAX #9) and orders again only the rows it can have
// touched. What it keeps must be, unit for unit and row for row, what the
// same spans give laid out from scratch: random edits of random text of
// Hebrew, Arabic and Latin words, numbers of both kinds, brackets,
// neutrals, marks, line breaks and now and then an explicit embedding or
// isolate, at random widths, wraps, overflows, line limits and alignments.
import 'dart:math';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

const _pens = [
  Pen(),
  Pen(fg: Color.rgb(200, 0, 0)),
  Pen(fg: Color.rgb(0, 0, 200)),
];

/// What the text is made of, most of it words of either direction.
const _pieces = [
  'the', 'quick', 'brown', 'well-known', 'x', 'Dart', //
  'שלום', 'עולם', 'מילה', 'ספר', 'א', //
  'مرحبا', 'بالعالم', 'كلمة', 'ب\u064E', 'ي', //
  '42', '1234', '5.6', '-7', '١٢٣', '٤٫٥', r'$9', '%', '#', //
  ' ', ' ', ' ', ' ', '  ', '\t', //
  '(', ')', '[', ']', '{', '}', '«', '»', '<', '>', '\u2329', '\u3009', //
  '(א)', '[ب]', '(x)', '!', '?', ',', '.', ':', '-', '/', '+', //
  '\u0301', '\u05B8', '\u200D', '\u200B', '\u00AD', '\u200E', '\u200F',
  '\u{10800}', '\u{1E900}', '\u{1D400}', '😀', //
];

/// Rarer pieces: line breaks and the explicit formatting characters.
const _rare = [
  '\n', '\r\n', '\r', '\u2029', '\u001C', //
  '\u202A', '\u202B', '\u202D', '\u202E', '\u202C', //
  '\u2066', '\u2067', '\u2068', '\u2069',
];

final class _Rig {
  _Rig(this.random)
    : mode = random.nextBool() ? TextMode.graphemes : TextMode.legacy,
      rare = random.nextInt(3) == 0 ? 0.02 : 0.0 {
    screen = Screen(_maxWidth, _height, textMode: mode);
    edited = owner();
  }

  static const _maxWidth = 40;
  static const _height = 30;

  final Random random;
  final TextMode mode;

  /// How often a piece is a line break or an explicit formatting
  /// character: never in two rigs of three.
  final double rare;
  late final Screen screen;
  late final PipelineOwner edited;
  final log = <String>[];

  PipelineOwner owner() =>
      PipelineOwner(() {}, segmenter: screen.canvas.segmenter)
        ..textOrder = TextOrder.visual;

  String piece() => random.nextDouble() < rare
      ? _rare[random.nextInt(_rare.length)]
      : _pieces[random.nextInt(_pieces.length)];

  String text(int most) {
    final b = StringBuffer();
    for (var n = random.nextInt(most + 1); n > 0; n--) {
      b
        ..write(piece())
        ..write(random.nextInt(3) == 0 ? '' : ' ');
    }
    return b.toString();
  }

  (String, Pen) span([int most = 30]) =>
      (text(most), _pens[random.nextInt(_pens.length)]);

  List<(String, Pen)> spans() => [
    for (var n = 1 + random.nextInt(4); n > 0; n--) span(),
  ];

  /// [spans] with one random edit: mostly a piece typed or taken back, as
  /// in a field; else a range deleted or replaced, a span split, joined,
  /// added or taken away.
  List<(String, Pen)> edit(List<(String, Pen)> spans) {
    final s = List.of(spans);
    final k = s.isEmpty ? 0 : random.nextInt(s.length);
    final roll = random.nextInt(16);
    if (s.isEmpty || roll == 0) {
      s.insert(s.isEmpty ? 0 : random.nextInt(s.length + 1), span(6));
      return s;
    }
    final (t, pen) = s[k];
    final at = random.nextInt(t.length + 1);
    final to = at + random.nextInt(min(t.length - at, 12) + 1);
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
      case 4 || 5:
        s[k] = (t.substring(0, at) + t.substring(to), pen);
      case 6 || 7:
        s[k] = (t.substring(0, at) + text(3) + t.substring(to), pen);
      default:
        s[k] = random.nextBool() || t.isEmpty
            ? (t.substring(0, at) + piece() + t.substring(at), pen)
            : (t.substring(0, max(0, at - 1)) + t.substring(at), pen);
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
/// and settings, laid out [width] wide: what it keeps, what it paints and
/// the text at each cell.
void _check(_Rig rig, RenderParagraph p, int width, String context) {
  final reason = '$context\n${rig.log.join('\n')}';
  expect(p.debugDiffFromFresh(), isNull, reason: reason);
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
  for (final y in [0, p.height - 1, rig.random.nextInt(p.height + 1)]) {
    for (var x = -1; x <= width; x++) {
      expect(
        p.textRangeAt(x, y),
        f.textRangeAt(x, y),
        reason: '$reason\ntext at ($x, $y)',
      );
    }
  }
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

/// A long paragraph of [n] times [sentence], one span each, laid out
/// [width] wide on [rig] and painted.
RenderParagraph _long(_Rig rig, String sentence, int width, {int n = 60}) {
  final p = RenderParagraph([
    for (var k = 0; k < n; k++) (sentence, _pens[k % 3]),
  ]);
  rig
    ..layOut(p, rig.edited, width)
    ..paint(p);
  return p;
}

void main() {
  test('edited at random, a paragraph in visual order keeps the levels, '
      'lines and rows one made from scratch has', () {
    var cases = 0;
    for (var seed = 0; seed < 400; seed++) {
      final rig = _Rig(Random(seed));
      final r = rig.random;
      var spans = rig.spans();
      var width = 1 + r.nextInt(_Rig._maxWidth);
      final p = RenderParagraph(
        spans,
        wrap: TextWrap.values[r.nextInt(4) == 0 ? r.nextInt(3) : 0],
        overflow: r.nextInt(3) == 0
            ? TextOverflow.values[r.nextInt(TextOverflow.values.length)]
            : TextOverflow.clip,
        maxLines: r.nextInt(3) == 0 ? 1 + r.nextInt(8) : null,
        align: TextAlign.values[r.nextInt(TextAlign.values.length)],
      );
      rig.log.add(
        'seed $seed, ${rig.mode}, rare ${rig.rare}, ${p.wrap}, '
        '${p.overflow}, maxLines ${p.maxLines}, ${p.align}',
      );
      rig
        ..layOut(p, rig.edited, width)
        ..paint(p);
      for (var step = 0; step < 24; step++) {
        // one edit or a few before the next layout, painted or not
        for (var n = 1 + (r.nextInt(4) == 0 ? r.nextInt(3) : 0); n > 0; n--) {
          spans = rig.edit(spans);
          p.spans = spans;
          rig.log.add('step $step: ${_show(spans)}');
          if (r.nextInt(4) == 0) {
            p.computeMinIntrinsicHeight(width);
          }
        }
        if (r.nextInt(12) == 0) {
          width = 1 + r.nextInt(_Rig._maxWidth);
          rig.log.add('width $width');
        }
        if (r.nextInt(20) == 0) {
          p.align = TextAlign.values[r.nextInt(TextAlign.values.length)];
          rig.log.add('align ${p.align}');
        }
        rig.layOut(p, rig.edited, width);
        if (r.nextInt(4) != 0) {
          _check(rig, p, width, 'seed $seed step $step at $width columns');
          cases++;
        }
      }
    }
    expect(cases, greaterThan(6000));
  });

  test('a character typed into a long paragraph resolves the levels about '
      'it again, and orders again only the rows it changed', () {
    for (final (name, sentence) in [
      (
        'left to right',
        'The presenter (of the core) writes שָׁלוֹם עולם and مرحبا 1234 '
            'only where cells changed. ',
      ),
      (
        'right to left',
        'פסקה נשברת לפי מילים [ולא אותיות] עם Dart ו-5678 ומילה '
            'בְּעברית. ',
      ),
      ('Arabic', 'تنكسر الفقرة بين الكلمات (والأرقام ١٢٣ و456) هُنا. '),
    ]) {
      final rig = _Rig(Random(7));
      final p = _long(rig, sentence, 40);
      final units = sentence.length * 60;
      expect(p.debugLevelsResolved, units, reason: name);
      expect(p.debugLinesOrdered, p.height, reason: name);
      // more lines than the rows shown; a cluster of several code points
      // among them, as the first one painted orders every row again
      expect(p.height, _Rig._height, reason: name);
      expect(p.debugLinesBroken, greaterThan(60), reason: name);
      // typed into the middle and the end of words, a space among them
      var local = 0;
      const typed = 'ab שׁ ق9 x (y) עִם z';
      final base = p.spans;
      for (var k = 1; k <= typed.length; k++) {
        final resolved = p.debugLevelsResolved;
        final broken = p.debugLinesBroken;
        final ordered = p.debugLinesOrdered;
        p.spans = List.of(base)
          ..[7] = (
            sentence.substring(0, 12) +
                typed.substring(0, k) +
                sentence.substring(12),
            base[7].$2,
          );
        rig.layOut(p, rig.edited, 40);
        rig.log
          ..clear()
          ..add('$name, character $k: ${_show(p.spans)}');
        _check(rig, p, 40, '$name, character $k');
        expect(
          p.debugLevelsResolved - resolved,
          lessThan(sentence.length),
          reason: '$name: levels resolved again for character $k',
        );
        final rows = p.debugLinesOrdered - ordered;
        final lines = p.debugLinesBroken - broken;
        expect(
          rows,
          lessThanOrEqualTo(lines + 2),
          reason: '$name: rows ordered again for character $k',
        );
        if (lines <= 3) {
          local++;
        }
      }
      // a word pushed to the next line moves every line after it in text
      // that repeats itself, which then is all broken again
      expect(local, greaterThanOrEqualTo(typed.length - 4), reason: name);
    }
  });

  test('an edit of one paragraph of several resolves only that one again, '
      'all of it where an explicit embedding is', () {
    final rig = _Rig(Random(9));
    const words = 'שלום world (עולם) and مرحبا 12 ';
    final plain = '${words * 8}\n';
    final embedded = '${words * 4}\u202B${words * 4}\u202C\n';
    final open = '${words * 4}(${words * 4}\n';
    final closed = '${words * 8}) עוד\n';
    for (final (name, second, again) in [
      ('plain', plain, lessThan(words.length)),
      ('embedded', embedded, embedded.length + 1),
      // a bracket left open pairs with none
      ('open', open, lessThan(words.length)),
      // the bracket typed pairs with one after it: all between them
      ('closed', closed, inInclusiveRange(words.length * 4, closed.length)),
    ]) {
      final p = RenderParagraph([
        (plain, _pens[0]),
        (second, _pens[1]),
        (plain, _pens[2]),
      ]);
      rig
        ..layOut(p, rig.edited, 30)
        ..paint(p);
      final resolved = p.debugLevelsResolved;
      final at = second.length ~/ 2;
      final typed = name == 'closed' ? '(' : 'x';
      p.spans = [
        (plain, _pens[0]),
        ('${second.substring(0, at)}$typed${second.substring(at)}', _pens[1]),
        (plain, _pens[2]),
      ];
      rig.layOut(p, rig.edited, 30);
      rig.log
        ..clear()
        ..add(name);
      _check(rig, p, 30, name);
      expect(p.debugLevelsResolved - resolved, again, reason: name);
    }
  });
}
