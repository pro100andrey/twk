// A repaint boundary repaints only the rows of what was marked for paint
// in it, and what it paints there is what painting all of it would: over
// random trees and random changes, a tree painted as it was marked and the
// same tree painted whole after each change show the same cells, the same
// styles and, through the presenter, the same screen; boundaries in stacks
// among them, under what covers them.
import 'dart:async';
import 'dart:math';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/vt.dart';

const _texts = <String>[
  'plain',
  'longer text that is cut off',
  'ячейка',
  '你好世界',
  'emoji 🧪🚀',
  '',
  'a',
  '日本語の文',
  'x 👨‍👩‍👧 y',
];

/// The pens the trees paint with: those with an opaque background first
/// (`_opaque` of them), which a repaint boundary needs.
const _pens = <Pen>[
  Pen(fg: Color.rgb(200, 200, 200), bg: Color.rgb(16, 18, 24)),
  Pen(fg: Color.rgb(255, 255, 255), bg: Color.rgb(0, 90, 180)),
  Pen(fg: Color.rgb(16, 18, 24), bg: Color.rgb(250, 200, 80)),
  Pen(fg: Color.rgb(90, 200, 120), bg: Color.rgb(38, 44, 58), attrs: Attr.bold),
  Pen(fg: Color.rgb(80, 160, 255)),
  Pen(fg: Color.rgb(220, 120, 120), attrs: Attr.italic),
  Pen(bg: Color.rgb(200, 40, 40), bgAlpha: 128),
  Pen(fg: Color.rgb(255, 255, 0), bg: Color.rgb(0, 200, 0), bgAlpha: 90),
];
const _opaque = 4;

/// Builds a random tree and changes it, from `seed`: two builders of the
/// same seed build the same tree and make the same changes.
final class _Builder {
  _Builder(int seed, this.styles) : rng = Random(seed) {
    pens = [for (final p in _pens) styles.pen(p)];
  }

  final Random rng;
  final StyleTable styles;
  late final List<int> pens;

  final texts = <RenderText>[];
  final boxes = <RenderBox>[];
  final flexes = <RenderFlex>[];
  final viewports = <RenderViewport>[];
  final logs = <RenderLog>[];

  bool _boundary(int oneIn) => rng.nextInt(oneIn) == 0;

  int _pen({required bool opaque}) =>
      pens[rng.nextInt(opaque ? _opaque : pens.length)];

  String _text() => _texts[rng.nextInt(_texts.length)];

  RenderObject root() => RenderBox(
    pen: pens[0],
    boundary: rng.nextBool(),
    child: node(0),
  );

  RenderObject node(int depth) {
    switch (depth >= 3 ? rng.nextInt(3) : rng.nextInt(11)) {
      case 3:
        final boundary = _boundary(4);
        final b = RenderBox(
          pen: _pen(opaque: boundary),
          padX: rng.nextInt(2),
          padY: rng.nextInt(2),
          boundary: boundary,
          child: node(depth + 1),
        );
        boxes.add(b);
        return b;
      case 4 || 5:
        return _flex(depth, vertical: true, bounded: true);
      case 6 || 7:
        return _flex(depth, vertical: false, bounded: true);
      case 8:
        // a boundary in it, under what is after it, repaints on its own
        // and has that painted again over its cells: a wide glyph there
        // that its sides cut is painted whole
        final s = RenderStack(
          children: [
            for (var i = 0, n = 2 + rng.nextInt(2); i < n; i++)
              if (rng.nextBool())
                node(depth + 1)
              else
                RenderPadding(
                  padding: EdgeInsets.only(
                    left: rng.nextInt(4),
                    top: rng.nextInt(3),
                  ),
                  child: node(depth + 1),
                ),
          ],
        );
        return s;
      case 9:
        final v = RenderViewport(
          scrollOffset: rng.nextInt(4),
          child: _flex(depth, vertical: true, bounded: false),
        );
        viewports.add(v);
        return v;
      case 10:
        final itemPens = [for (var i = 0; i < 3; i++) _pen(opaque: false)];
        final log = RenderLog(
          pen: _pen(opaque: true),
          itemPen: (i, _) => itemPens[i % itemPens.length],
        );
        for (var i = 0, n = rng.nextInt(8); i < n; i++) {
          log.add('${_text()} $i');
        }
        logs.add(log);
        return log;
      default:
        final boundary = _boundary(6);
        final t = RenderText(
          _text(),
          _pen(opaque: boundary),
          boundary: boundary,
        );
        texts.add(t);
        return t;
    }
  }

  /// A row or a column of 1 to 5 children; in a [bounded] one some share
  /// what the others leave, in another every child has a fixed extent.
  RenderFlex _flex(int depth, {required bool vertical, required bool bounded}) {
    final children = <(RenderObject, int?)>[
      for (var i = 0, n = 1 + rng.nextInt(bounded ? 5 : 8); i < n; i++)
        (
          node(depth + 1),
          bounded && rng.nextInt(3) == 0
              ? null
              : 1 + rng.nextInt(vertical ? 3 : 12),
        ),
    ];
    final f = vertical ? RenderColumn(children) : RenderRow(children);
    flexes.add(f);
    return f;
  }

  /// One random change of the tree.
  void change() {
    switch (rng.nextInt(9)) {
      case 0 || 1 when texts.isNotEmpty:
        texts[rng.nextInt(texts.length)].text = _text();
      case 2 || 3 when texts.isNotEmpty:
        final t = texts[rng.nextInt(texts.length)];
        t.pen = _pen(opaque: t.boundary);
      case 4 when boxes.isNotEmpty:
        final b = boxes[rng.nextInt(boxes.length)];
        b.pen = _pen(opaque: b.boundary);
      case 5 when viewports.isNotEmpty:
        viewports[rng.nextInt(viewports.length)].scrollOffset = rng.nextInt(
          6,
        );
      case 6 when logs.isNotEmpty:
        logs[rng.nextInt(logs.length)].add(_text());
      case 7 when flexes.isNotEmpty:
        final f = flexes[rng.nextInt(flexes.length)];
        if (f.childCount > 1) {
          // the cells it leaves are its parent's to repaint
          f.remove(f.lastChild!);
        }
      case 8 when flexes.isNotEmpty:
        // flexible in a bounded flex, sized by the cross axis otherwise
        flexes[rng.nextInt(flexes.length)].add(node(3));
      default:
        if (texts.isNotEmpty) {
          texts[rng.nextInt(texts.length)].text = _text();
        }
    }
  }
}

/// A tree painted on a surface of its own, with a presenter feeding an
/// emulator.
final class _Painted {
  _Painted(this.w, this.h, this.canvas, this.builder)
    : surface = Surface(w, h),
      presenter = Presenter(w, h, canvas.styles, canvas.glyphs),
      vt = Vt(w, h) {
    owner = PipelineOwner(() {}, segmenter: canvas.segmenter)
      ..root = builder.root();
    ctx = PaintContext(canvas, surface, presenter);
  }

  final int w;
  final int h;
  final Canvas canvas;
  final _Builder builder;
  final Surface surface;
  final Presenter presenter;
  final Vt vt;
  late final PipelineOwner owner;
  late final PaintContext ctx;

  /// The cells painted by the last [frame].
  var damaged = 0;

  /// Lays out and paints what was marked, everything when [whole]; then
  /// presents it.
  void frame({required bool whole}) {
    if (whole) {
      owner.markAllDirty();
    }
    canvas.surface = surface;
    // the overflows of random flexes, which are no news here, not logged
    runZoned(
      () => owner
        ..flushLayout(w, h)
        ..flushPaint(ctx),
      zoneSpecification: ZoneSpecification(print: (_, _, _, _) {}),
    );
    damaged = 0;
    for (var y = 0; y < h; y++) {
      final n = surface.dirtyHi[y] - surface.dirtyLo[y];
      damaged += n > 0 ? n : 0;
    }
    if (presenter.present(surface) != 0) {
      vt.feed(presenter.out.view);
    }
  }
}

/// Where [a] and [b] show different cells, described; null where nowhere.
String? _difference(_Painted a, _Painted b) {
  final s = a.surface;
  final t = b.surface;
  for (var i = 0; i < s.cells.length; i++) {
    if (s.cells[i] != t.cells[i] || s.styles[i] != t.styles[i]) {
      final y = i ~/ a.w;
      return 'cell ${i % a.w},$y: '
          '${s.cells[i].toRadixString(16)}/${s.styles[i]} painted as marked, '
          '${t.cells[i].toRadixString(16)}/${t.styles[i]} painted whole\n'
          '  as marked: ${a.vt.lines[y]}\n'
          '  whole:     ${b.vt.lines[y]}';
    }
  }
  for (var y = 0; y < a.h; y++) {
    if (a.vt.lines[y] != b.vt.lines[y]) {
      return 'screen row $y: "${a.vt.lines[y]}" presented as marked, '
          '"${b.vt.lines[y]}" whole';
    }
  }
  return null;
}

void main() {
  test('a tree painted as marked shows what one painted whole does', () {
    const w = 40;
    const h = 16;
    var asMarked = 0;
    var whole = 0;
    for (var seed = 0; seed < 400; seed++) {
      final styles = StyleTable();
      final canvas = Canvas(Surface(w, h), styles, GlyphTable());
      final a = _Painted(w, h, canvas, _Builder(seed, styles));
      final b = _Painted(w, h, canvas, _Builder(seed, styles));
      a.frame(whole: false);
      b.frame(whole: true);

      expect(_difference(a, b), isNull, reason: 'seed $seed, first frame');
      for (var step = 0; step < 25; step++) {
        final changes = 1 + a.builder.rng.nextInt(3);
        b.builder.rng.nextInt(3);
        for (var i = 0; i < changes; i++) {
          a.builder.change();
          b.builder.change();
        }
        a.frame(whole: false);
        b.frame(whole: true);
        asMarked += a.damaged;
        whole += b.damaged;
        expect(
          _difference(a, b),
          isNull,
          reason: 'seed $seed, step $step',
        );
      }
    }
    // and it painted less: not the whole of every boundary every time
    expect(asMarked, lessThan(whole * 0.6));
  });
}
