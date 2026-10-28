// What a render object asks for before it is laid out agrees with what it
// draws, is worked out once until the object changes, and a parent that
// asked is laid out again when it does.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// A render tree filling a whole screen of the given text mode and
/// ambiguous width; layout measures text with the canvas's segmenter.
final class View {
  View(
    this.width,
    this.height, {
    TextMode textMode = TextMode.graphemes,
    int ambiguousWidth = 1,
  }) : screen = Screen(
         width,
         height,
         textMode: textMode,
         ambiguousWidth: ambiguousWidth,
       ) {
    pen = screen.styles.pen(const Pen(bg: Color.rgb(0, 0, 0)));
    owner = PipelineOwner(() {}, segmenter: screen.canvas.segmenter);
  }

  final int width;
  final int height;
  final Screen screen;
  late final int pen;
  late final PipelineOwner owner;

  void frame() {
    owner
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    screen.render();
  }

  /// The text of each row; a wide glyph's second cell adds nothing.
  List<String> rows() => [
    for (var y = 0; y < height; y++)
      [
        for (var x = 0; x < width; x++)
          if ((screen.surface.cells[y * width + x] & kCont) == 0)
            screen.glyphs.stringOf(screen.surface.cells[y * width + x]),
      ].join().trimRight(),
  ];
}

/// Asks for [minW], [maxW], [minH] and [maxH] at any extent; keeps the
/// extent it was last asked at for each and counts what it worked out.
final class Probe extends RenderObject {
  Probe({this.minW = 0, this.maxW = 0, this.minH = 0, this.maxH = 0});

  final int minW;
  int maxW;
  final int minH;
  final int maxH;

  /// The extent last asked at: min width, max width, min height, max
  /// height (-1: never).
  final asked = List<int>.filled(4, -1);
  var computed = 0;

  /// Asks for [w] as its max width from now on.
  void wantMaxW(int w) {
    maxW = w;
    markNeedsLayout();
  }

  int _answer(int kind, int extent, int answer) {
    computed++;
    asked[kind] = extent;
    return answer;
  }

  @override
  int computeMinIntrinsicWidth(int height) => _answer(0, height, minW);

  @override
  int computeMaxIntrinsicWidth(int height) => _answer(1, height, maxW);

  @override
  int computeMinIntrinsicHeight(int width) => _answer(2, width, minH);

  @override
  int computeMaxIntrinsicHeight(int width) => _answer(3, width, maxH);

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) {}
}

/// Lays its child out as wide as the child asks to be when [asks] (else as
/// wide as it is itself) and draws a bar right after it. Counts its
/// layouts.
final class Hug extends RenderObject {
  Hug(this.child, this.pen, {this.asks = true}) {
    adopt(child);
  }

  final RenderObject child;
  final int pen;
  final bool asks;
  var layouts = 0;

  @override
  void visitChildren(void Function(RenderObject) visit) => visit(child);

  @override
  void performLayout(BoxConstraints c) {
    layouts++;
    width = c.maxW;
    height = c.maxH;
    var w = width;
    if (asks) {
      final wants = child.getMaxIntrinsicWidth(height);
      w = wants < width ? wants : width;
    }
    child.layout(BoxConstraints.tight(w, height));
  }

  @override
  void paint(PaintContext ctx) {
    paintChild(ctx, child);
    ctx.canvas.text(child.width, 0, '|', pen);
  }
}

/// Every intrinsic size of [o] at [extent]: min and max width, min and max
/// height.
List<int> intrinsics(RenderObject o, int extent) => [
  o.getMinIntrinsicWidth(extent),
  o.getMaxIntrinsicWidth(extent),
  o.getMinIntrinsicHeight(extent),
  o.getMaxIntrinsicHeight(extent),
];

void main() {
  group('RenderText', () {
    // text: its columns with graphemes and an ambiguous width of 1, of 2,
    // then the same in legacy mode
    const columns = <String, List<int>>{
      'hello': [5, 5, 5, 5],
      // wide
      '你好': [4, 4, 4, 4],
      // uncertain: an emoji ZWJ sequence, an emoji presentation selector
      '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}': [2, 2, 6, 6],
      '\u2764\uFE0F': [2, 2, 1, 1],
      // ambiguous
      '±α': [2, 4, 2, 4],
      // a combining mark, a mark without a base
      'e\u0301': [1, 1, 1, 1],
      '\u0301x': [1, 1, 1, 1],
      // a spacing mark without a base: dropped in grapheme mode, a cell of
      // its own in legacy mode
      '\u093Ex': [1, 1, 2, 2],
      // a tab is drawn as one blank, another control not at all
      'a\tb\x01': [3, 3, 3, 3],
      // a conjunct
      '\u0915\u094D\u0937\u093F': [1, 1, 3, 3],
    };
    const settings = [
      (TextMode.graphemes, 1),
      (TextMode.graphemes, 2),
      (TextMode.legacy, 1),
      (TextMode.legacy, 2),
    ];

    for (final (k, (mode, ambiguous)) in settings.indexed) {
      test(
        'is as wide as it is drawn (${mode.name}, ambiguous $ambiguous)',
        () {
          final v = View(20, 2, textMode: mode, ambiguousWidth: ambiguous);
          for (final MapEntry(key: s, value: want) in columns.entries) {
            final text = RenderText(s, v.pen);
            v.owner.root = text;
            v.frame();
            final drawn = v.screen.canvas.shape(s).width;
            expect(
              [text.getMinIntrinsicWidth(2), text.getMaxIntrinsicWidth(2)],
              [want[k], want[k]],
              reason: s.runes.map((r) => r.toRadixString(16)).join(' '),
            );
            expect(want[k], drawn, reason: 'what the canvas draws');
          }
        },
      );
    }

    test('is one row tall at any width', () {
      final v = View(10, 3);
      final text = RenderText('hello', v.pen);
      v.owner.root = text;
      for (final w in [0, 2, 5, 100]) {
        expect(
          [text.getMinIntrinsicHeight(w), text.getMaxIntrinsicHeight(w)],
          [1, 1],
        );
      }
    });

    test('a new text is measured again', () {
      final v = View(10, 1);
      final text = RenderText('hello', v.pen);
      v.owner.root = text;
      v.frame();
      expect(text.getMaxIntrinsicWidth(1), 5);
      text.text = '你好你好';
      expect(text.getMaxIntrinsicWidth(1), 8);
      v.frame();
      text.text = 'hi';
      expect(text.text, 'hi');
      expect(text.getMinIntrinsicWidth(1), 2);
    });

    test('is measured as the owner it is attached to draws it', () {
      const family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}';
      final legacy = View(10, 1, textMode: TextMode.legacy);
      final text = RenderText(family, legacy.pen);
      // detached, it is measured as a default canvas draws it
      expect(text.getMaxIntrinsicWidth(1), 2);
      legacy.owner.root = text;
      expect(text.getMaxIntrinsicWidth(1), 6);
    });
  });

  group('RenderBox', () {
    test('adds its padding to what its child asks for', () {
      final v = View(10, 1);
      final child = Probe(minW: 3, maxW: 7, minH: 1, maxH: 2);
      final box = RenderBox(pen: v.pen, padX: 2, padY: 1, child: child);
      expect(intrinsics(box, 10), [7, 11, 3, 4]);
      // the child is asked about the room inside the padding
      expect(child.asked, [8, 8, 6, 6]);
      expect(intrinsics(box, 1), [7, 11, 3, 4]);
      expect(child.asked, [0, 0, 0, 0]);
    });

    test('without a child asks for its padding', () {
      final v = View(10, 1);
      final box = RenderBox(pen: v.pen, padX: 2, padY: 1);
      expect(intrinsics(box, 10), [4, 4, 2, 2]);
    });
  });

  group('RenderColumn', () {
    test('is as wide as its widest child at the height it gets', () {
      final a = Probe(minW: 3, maxW: 5);
      final flex = Probe(minW: 6, maxW: 4);
      final c = Probe(minW: 1, maxW: 9);
      final column = RenderColumn([(a, 2), (flex, null), (c, 1)]);
      expect(column.getMinIntrinsicWidth(10), 6);
      expect(column.getMaxIntrinsicWidth(10), 9);
      // fixed children at their heights, the flexible one at what is left
      expect([a.asked[0], flex.asked[0], c.asked[0]], [2, 7, 1]);
      expect([a.asked[1], flex.asked[1], c.asked[1]], [2, 7, 1]);
      column.getMinIntrinsicWidth(2);
      expect(flex.asked[0], 0);
    });

    test('is as tall as its fixed heights and its flexible child', () {
      final a = Probe(minH: 7, maxH: 7);
      final flex = Probe(minH: 3, maxH: 5);
      final column = RenderColumn([(a, 2), (flex, null), (Probe(), 1)]);
      expect(column.getMinIntrinsicHeight(8), 6);
      expect(column.getMaxIntrinsicHeight(8), 8);
      expect(flex.asked, [-1, -1, 8, 8]);
      // a fixed child gets its height whatever it asks for
      expect(a.asked, [-1, -1, -1, -1]);
    });
  });

  group('RenderRow', () {
    test('is as wide as its fixed widths and its flexible child', () {
      final a = Probe(minW: 7, maxW: 7);
      final flex = Probe(minW: 3, maxW: 5);
      final row = RenderRow([(a, 2), (flex, null), (Probe(), 1)]);
      expect(row.getMinIntrinsicWidth(8), 6);
      expect(row.getMaxIntrinsicWidth(8), 8);
      expect(flex.asked, [8, 8, -1, -1]);
      expect(a.asked, [-1, -1, -1, -1]);
    });

    test('is as tall as its tallest child at the width it gets', () {
      final a = Probe(minH: 3, maxH: 5);
      final flex = Probe(minH: 6, maxH: 4);
      final c = Probe(minH: 1, maxH: 9);
      final row = RenderRow([(a, 2), (flex, null), (c, 1)]);
      expect(row.getMinIntrinsicHeight(10), 6);
      expect(row.getMaxIntrinsicHeight(10), 9);
      expect([a.asked[2], flex.asked[2], c.asked[2]], [2, 7, 1]);
      expect([a.asked[3], flex.asked[3], c.asked[3]], [2, 7, 1]);
      row.getMinIntrinsicHeight(2);
      expect(flex.asked[2], 0);
    });

    test('of texts is as wide as they are drawn', () {
      final v = View(20, 1, ambiguousWidth: 2);
      final row = RenderRow([
        (RenderText('ab', v.pen), 4),
        (RenderText('你好±', v.pen), null),
      ]);
      v.owner.root = row;
      expect(
        [row.getMinIntrinsicWidth(1), row.getMaxIntrinsicWidth(1)],
        [
          10,
          10,
        ],
      );
    });
  });

  test('a log asks for nothing: it scrolls what it holds', () {
    final v = View(10, 3);
    final log = RenderLog(pen: v.pen, itemPen: (_, _) => v.pen);
    v.owner.root = log;
    for (var i = 0; i < 5; i++) {
      log.add('line $i');
    }
    v.frame();
    expect(intrinsics(log, 10), [0, 0, 0, 0]);
  });

  group('answers', () {
    test('are worked out once per extent until markNeedsLayout', () {
      final v = View(10, 1);
      final probe = Probe(minW: 3);
      v.owner.root = probe;
      v.frame();
      expect([probe.getMinIntrinsicWidth(5), probe.computed], [3, 1]);
      expect([probe.getMinIntrinsicWidth(5), probe.computed], [3, 1]);
      expect([probe.getMinIntrinsicWidth(6), probe.computed], [3, 2]);
      expect([probe.getMaxIntrinsicWidth(6), probe.computed], [0, 3]);
      expect([probe.getMinIntrinsicWidth(6), probe.computed], [3, 3]);
      probe.markNeedsLayout();
      expect([probe.getMinIntrinsicWidth(6), probe.computed], [3, 4]);
      expect([probe.getMaxIntrinsicWidth(6), probe.computed], [0, 5]);
    });

    test("of a container follow a child's change", () {
      final v = View(10, 2);
      final probe = Probe(maxW: 4);
      final column = RenderColumn([(probe, 1), (Probe(maxW: 2), null)]);
      v.owner.root = column;
      v.frame();
      expect(column.getMaxIntrinsicWidth(2), 4);
      probe.wantMaxW(9);
      expect(column.getMaxIntrinsicWidth(2), 9);
    });
  });

  group('a parent that asked', () {
    test('is laid out again when its child changes', () {
      final v = View(10, 1);
      final text = RenderText('ab', v.pen);
      final hug = Hug(text, v.pen);
      v.owner.root = hug;
      v.frame();
      expect(v.rows(), ['ab|']);
      text.text = 'abcd';
      v.frame();
      expect(v.rows(), ['abcd|']);
      expect(hug.layouts, 2);
    });

    test('is laid out again through a container in between', () {
      final v = View(10, 1);
      final text = RenderText('ab', v.pen);
      final hug = Hug(RenderBox(pen: v.pen, padX: 1, child: text), v.pen);
      v.owner.root = hug;
      v.frame();
      expect(v.rows(), [' ab |']);
      text.text = 'a你';
      v.frame();
      expect(v.rows(), [' a你 |']);
    });
  });

  test('a parent that did not ask is not laid out with its child', () {
    final v = View(10, 1);
    final text = RenderText('ab', v.pen);
    final hug = Hug(text, v.pen, asks: false);
    v.owner.root = hug;
    v.frame();
    text.text = 'abcd';
    v.frame();
    expect(v.rows(), ['abcd']);
    expect(hug.layouts, 1);
  });
}
