// A paragraph that keeps its paint (keepsPaint) repaints the rows that
// differ from what its cells hold, and what that leaves on the surface is
// what painting all of the tree leaves: over random edits of the text, its
// pens (translucent backgrounds among them), its width, its line limit and
// what is around it, a tree painted as marked and the same tree with an
// ordinary paragraph painted whole after each change show the same cells,
// the same styles and, through the presenter, the same screen.
import 'dart:async';
import 'dart:math';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/vt.dart';

const _pieces = <String>[
  'the', 'quick', 'brown', 'fox', 'jumps', 'over', 'lazy', 'dog', 'x', //
  ' ', ' ', ' ', '  ', '\n', '\n\n', '\n', '\n',
  'привет', 'мир', '你好世界', '日本語', 'ー', '😀', '👨‍👩‍👧',
  'é', 'naïve', 'שלום', '-', '—', '…', '\t',
];

const _pens = <Pen>[
  Pen(fg: Color.rgb(200, 200, 200)),
  Pen(fg: Color.rgb(255, 255, 255), attrs: Attr.bold),
  Pen(fg: Color.rgb(90, 200, 120), bg: Color.rgb(38, 44, 58)),
  Pen(bg: Color.rgb(200, 40, 40), bgAlpha: 128),
  Pen(fg: Color.rgb(255, 255, 0), bg: Color.rgb(0, 200, 0), bgAlpha: 90),
  Pen(fg: Color.rgb(220, 120, 120), attrs: Attr.italic),
];

const _backgrounds = <Pen>[
  Pen(fg: Color.rgb(200, 200, 200), bg: Color.rgb(16, 18, 24)),
  Pen(fg: Color.rgb(255, 255, 255), bg: Color.rgb(0, 90, 180)),
  Pen(fg: Color.rgb(16, 18, 24), bg: Color.rgb(250, 200, 80)),
];

/// A panel with a background around a paragraph, in a column with other
/// text, or under a text in a stack; random edits from `seed`: two builders
/// of one seed build the same tree and make the same edits.
final class _Builder {
  _Builder(int seed, this.styles, {required this.keeps})
    : rng = Random(seed),
      shape = seed % 6 {
    for (var i = 0, n = 1 + rng.nextInt(5); i < n; i++) {
      _parts.add([
        for (var k = 0, m = 8 + rng.nextInt(20); k < m; k++) _piece(),
      ]);
      _pens2.add(_pens[rng.nextInt(_pens.length)]);
    }
    _spans = _join();
    paragraph = RenderParagraph(
      _spans,
      wrap: rng.nextBool() ? TextWrap.word : TextWrap.grapheme,
      overflow: rng.nextInt(3) == 0 ? TextOverflow.ellipsis : TextOverflow.clip,
      maxLines: rng.nextInt(3) == 0 ? 3 + rng.nextInt(5) : null,
      align: TextAlign.values[rng.nextInt(TextAlign.values.length)],
      keepsPaint: keeps,
    );
    limit = RenderConstrainedBox(
      additionalConstraints: const BoxConstraints(maxW: 24, maxH: 12),
      child: paragraph,
    );
    panel = RenderBox(
      pen: styles.pen(_backgrounds[1 + rng.nextInt(2)]),
      padX: rng.nextInt(2),
      padY: rng.nextInt(2),
      boundary: rng.nextBool(),
      child: limit,
    );
    header = RenderText('header', styles.pen(_backgrounds[0]));
    note = RenderText('note 0', styles.pen(_backgrounds[0]));
    final body = switch (shape) {
      0 => panel,
      1 => RenderColumn([(header, 1), (panel, null), (note, 1)]),
      2 => RenderStack(
        children: [
          panel,
          RenderPadding(
            padding: EdgeInsets.only(left: 2 + rng.nextInt(8), top: 1),
            child: note,
          ),
        ],
      ),
      4 => RenderColumn([
        (header, 1),
        (
          RenderPadding(padding: const EdgeInsets.all(1), child: panel),
          null,
        ),
      ]),
      // a paragraph whose parents are not relayout boundaries
      5 => RenderColumn([
        (header, 1),
        (
          RenderRow([
            (RenderPadding(padding: EdgeInsets.zero, child: panel), null),
          ]),
          null,
        ),
        (note, 1),
      ]),
      _ => RenderRow([(panel, 28), (note, null)]),
    };
    root = RenderBox(
      pen: styles.pen(_backgrounds[0]),
      boundary: true,
      child: body,
    );
  }

  final Random rng;
  final StyleTable styles;
  final bool keeps;
  final int shape;
  final _parts = <List<String>>[];
  final _pens2 = <Pen>[];
  late List<(String, Pen)> _spans;
  late final RenderParagraph paragraph;
  late final RenderConstrainedBox limit;
  late final RenderBox panel;
  late final RenderText header;
  late final RenderText note;
  late final RenderObject root;

  String _piece() => _pieces[rng.nextInt(_pieces.length)];

  /// The spans: the pieces of each joined, in its pen.
  List<(String, Pen)> _join() => [
    for (var i = 0; i < _parts.length; i++) (_parts[i].join(), _pens2[i]),
  ];

  /// One random change.
  void change() {
    switch (rng.nextInt(14)) {
      case 0 || 1 || 2 || 3:
        // a word typed or deleted somewhere
        final part = _parts[rng.nextInt(_parts.length)];
        final at = rng.nextInt(part.length);
        if (rng.nextBool() && part.length > 3) {
          part.removeAt(at);
        } else {
          part.insert(at, _piece());
        }
        _set();
      case 4:
        // a piece replaced
        final part = _parts[rng.nextInt(_parts.length)];
        part[rng.nextInt(part.length)] = _piece();
        _set();
      case 5:
        // a span of another pen
        _pens2[rng.nextInt(_pens2.length)] = _pens[rng.nextInt(_pens.length)];
        _set();
      case 6:
        limit.additionalConstraints = BoxConstraints(
          maxW: 10 + rng.nextInt(20),
          maxH: 4 + rng.nextInt(12),
        );
      case 7:
        paragraph.maxLines = rng.nextBool() ? null : 2 + rng.nextInt(6);
      case 8:
        paragraph.align =
            TextAlign.values[rng.nextInt(TextAlign.values.length)];
      case 9:
        note.text = 'note ${rng.nextInt(1000)}';
      case 10:
        panel.pen = styles.pen(_backgrounds[rng.nextInt(_backgrounds.length)]);
      case 11 || 12:
        // a whole line put in or taken out: the rows after it move as
        // they were
        final part = _parts[rng.nextInt(_parts.length)];
        final breaks = [
          for (var i = 0; i < part.length; i++)
            if (part[i] == '\n') i,
        ];
        if (breaks.isNotEmpty) {
          final at = breaks[rng.nextInt(breaks.length)];
          if (rng.nextBool() || at == 0) {
            part.insertAll(at + 1, ['ab', '\n']);
          } else {
            part.removeRange(at - 1, at + 1);
          }
          _set();
        }
      default:
        // the same text again
        paragraph.spans = List.of(_spans);
    }
  }

  void _set() {
    _spans = _join();
    paragraph.spans = _spans;
  }
}

final class _Painted {
  _Painted(this.w, this.h, this.canvas, this.builder)
    : surface = Surface(w, h),
      presenter = Presenter(w, h, canvas.styles, canvas.glyphs),
      vt = Vt(w, h) {
    owner = PipelineOwner(() {}, segmenter: canvas.segmenter)
      ..root = builder.root;
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
  var damaged = 0;

  void frame({required bool whole}) {
    if (whole) {
      owner.markAllDirty();
    }
    canvas.surface = surface;
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

String? _difference(_Painted a, _Painted b) {
  final s = a.surface;
  final t = b.surface;
  for (var i = 0; i < s.cells.length; i++) {
    if (s.cells[i] != t.cells[i] || s.styles[i] != t.styles[i]) {
      final y = i ~/ a.w;
      return 'cell ${i % a.w},$y: '
          '${s.cells[i].toRadixString(16)}/${s.styles[i]} kept, '
          '${t.cells[i].toRadixString(16)}/${t.styles[i]} whole\n'
          '  kept:  ${a.vt.lines[y]}\n'
          '  whole: ${b.vt.lines[y]}';
    }
  }
  for (var y = 0; y < a.h; y++) {
    if (a.vt.lines[y] != b.vt.lines[y]) {
      return 'screen row $y: "${a.vt.lines[y]}" kept, "${b.vt.lines[y]}" whole';
    }
  }
  return null;
}

RenderFlex _stack(List<RenderObject> children) => RenderFlex(
  direction: Axis.vertical,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: children,
);

void main() {
  // a paragraph in a tree of `around` (in a root box), edited by `edit`
  ({RenderParagraph paragraph, void Function() frame}) rig(
    RenderObject Function(RenderParagraph) around,
    String text, {
    TextWrap wrap = TextWrap.word,
  }) {
    final styles = StyleTable();
    final surface = Surface(30, 12);
    final canvas = Canvas(surface, styles, GlyphTable());
    final paragraph = RenderParagraph(
      [(text, const Pen())],
      wrap: wrap,
      keepsPaint: true,
    );
    final owner = PipelineOwner(() {}, segmenter: canvas.segmenter)
      ..root = RenderBox(
        pen: styles.pen(_backgrounds[0]),
        boundary: true,
        child: around(paragraph),
      );
    final ctx = PaintContext(
      canvas,
      surface,
      Presenter(30, 12, styles, canvas.glyphs),
    );
    void frame() => owner
      ..flushLayout(30, 12)
      ..flushPaint(ctx);
    frame();
    frame();
    return (paragraph: paragraph, frame: frame);
  }

  test('an edit that holds the size lays out only the paragraph', () {
    final note = RenderText('note', 0);
    final r = rig(
      (p) => _stack([p, note]),
      'one\ntwo\nthree',
    );
    r.paragraph.spans = const [('one\ntwo\nthrew', Pen())];
    r.frame();
    expect(r.paragraph.debugKeptPaints, 1);
  });

  test('an edit that changes the size lays the parent out', () {
    final note = RenderText('note', 0);
    final r = rig(
      (p) => _stack([p, note]),
      'one\ntwo\nthree',
    );
    expect(note.parentData.dy, 3);
    r.paragraph.spans = const [('one\ntwo\nthree\nfour', Pen())];
    r.frame();
    expect(r.paragraph.height, 4);
    expect(note.parentData.dy, 4);
    r.paragraph.spans = const [('one\ntwo', Pen())];
    r.frame();
    expect(note.parentData.dy, 2);
  });

  test('an edit that changes what a parent read of it lays it out', () {
    // the paragraph is as wide as the widest line, in a box as wide as it
    // is: its own width holds at the tight constraints it was given
    final note = RenderText('note', 0);
    late RenderIntrinsicWidth wide;
    final r = rig(
      (p) {
        wide = RenderIntrinsicWidth(child: p);
        return _stack([wide, note]);
      },
      'ab\ncd',
      wrap: TextWrap.none,
    );
    expect(wide.width, 2);
    r.paragraph.spans = const [('ab\ncdefgh', Pen())];
    r.frame();
    expect(wide.width, 6);
    expect(r.paragraph.width, 6);
  });

  test('keepsPaint changed on a paragraph laid out takes effect', () {
    final r = rig((p) => RenderColumn([(p, null)]), 'one\ntwo');
    final p = r.paragraph;
    expect(p.isRepaintBoundary, isTrue);
    p.keepsPaint = false;
    r.frame();
    expect(p.isRepaintBoundary, isFalse);
    p.spans = const [('one\ntwa', Pen())];
    r.frame();
    expect(p.debugKeptPaints, 0);
    p.keepsPaint = true;
    r.frame();
    p.spans = const [('one\ntwb', Pen())];
    r.frame();
    expect(p.debugKeptPaints, 1);
  });

  test('a paint with nothing changed goes on keeping the paint', () {
    const w = 20;
    const h = 4;
    final styles = StyleTable();
    final surface = Surface(w, h);
    final canvas = Canvas(surface, styles, GlyphTable());
    final paragraph = RenderParagraph(const [
      ('one\ntwo\nthree', Pen()),
    ], keepsPaint: true);
    final owner = PipelineOwner(() {}, segmenter: canvas.segmenter)
      ..root = RenderBox(
        pen: styles.pen(_backgrounds[0]),
        boundary: true,
        child: RenderConstrainedBox(
          additionalConstraints: const BoxConstraints(
            minW: w,
            maxW: w,
            minH: h,
            maxH: h,
          ),
          child: paragraph,
        ),
      );
    final ctx = PaintContext(
      canvas,
      surface,
      Presenter(w, h, styles, canvas.glyphs),
    );
    void frame() => owner
      ..flushLayout(w, h)
      ..flushPaint(ctx);

    frame();
    paragraph.markNeedsPaint();
    frame();
    paragraph.spans = const [('one\ntwo\nthrew', Pen())];
    frame();

    expect(paragraph.debugKeptPaints, 1);
  });

  test(
    'a paragraph that keeps its paint shows what one painted whole does',
    () {
      const w = 40;
      const h = 16;
      var kept = 0;
      var keptPaints = 0;
      var whole = 0;
      for (var seed = 0; seed < 300; seed++) {
        final styles = StyleTable();
        final canvas = Canvas(Surface(w, h), styles, GlyphTable());
        final a = _Painted(w, h, canvas, _Builder(seed, styles, keeps: true));
        final b = _Painted(w, h, canvas, _Builder(seed, styles, keeps: false));
        a.frame(whole: false);
        b.frame(whole: true);
        expect(_difference(a, b), isNull, reason: 'seed $seed, first frame');
        for (var step = 0; step < 30; step++) {
          final changes = 1 + a.builder.rng.nextInt(2);
          b.builder.rng.nextInt(2);
          for (var i = 0; i < changes; i++) {
            a.builder.change();
            b.builder.change();
          }
          a.frame(whole: false);
          b.frame(whole: true);
          kept += a.damaged;
          whole += b.damaged;
          expect(_difference(a, b), isNull, reason: 'seed $seed, step $step');
        }
        keptPaints += a.builder.paragraph.debugKeptPaints;
      }
      // it painted rows alone, and fewer cells than painting everything did
      expect(keptPaints, greaterThan(100));
      expect(kept, lessThan(whole));
    },
  );
}
