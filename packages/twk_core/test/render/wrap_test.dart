// A wrap lays its children out in runs: one after another along its main
// axis until the next would not fit, then on in a new run; the children
// of a run and the runs themselves placed as its alignments say.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// A render tree filling a whole screen.
final class View {
  View(this.width, this.height) : screen = Screen(width, height) {
    pen = screen.styles.pen(const Pen(bg: Color.rgb(0, 0, 0)));
    owner = PipelineOwner(() {});
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

  List<String> rows() => [
    for (var y = 0; y < height; y++)
      [
        for (var x = 0; x < width; x++)
          screen.glyphs.stringOf(screen.surface.cells[y * width + x]),
      ].join().trimRight(),
  ];

  /// What [root] paints on this screen.
  List<String> show(RenderObject root) {
    owner.root = root;
    frame();
    return rows();
  }
}

/// One line of [text] (one column per character), as wide as the text
/// within the constraints; a new [text] lays it out again. Counts its
/// layouts.
final class Label extends RenderObject {
  Label(this._text);

  String _text;
  var layouts = 0;

  String get text => _text;
  set text(String t) {
    _text = t;
    markNeedsLayout();
  }

  @override
  int computeMinIntrinsicWidth(int height) => _text.length;

  @override
  int computeMaxIntrinsicWidth(int height) => _text.length;

  @override
  int computeMinIntrinsicHeight(int width) => 1;

  @override
  int computeMaxIntrinsicHeight(int width) => 1;

  @override
  void performLayout(BoxConstraints c) {
    layouts++;
    width = c.constrainW(_text.length);
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) =>
      ctx.canvas.text(0, 0, _text, ctx.canvas.styles.pen(const Pen()));

  @override
  String toString() => _text;
}

/// [w] × [h] of [char] within the constraints.
final class Block extends RenderObject {
  Block(this.char, this.w, this.h);

  final String char;
  final int w;
  final int h;
  BoxConstraints? got;

  @override
  void performLayout(BoxConstraints c) {
    got = c;
    width = c.constrainW(w);
    height = c.constrainH(h);
  }

  @override
  void paint(PaintContext ctx) => ctx.canvas.fill(
    0,
    0,
    width,
    height,
    ctx.canvas.styles.pen(const Pen()),
    char.codeUnitAt(0),
  );

  @override
  String toString() => char;
}

/// Asks for [minW] and [maxW] at any height, and as many rows as the width
/// it is asked at holds [cells] in, for its min and max height; keeps the
/// extent it was last asked at for each.
final class Probe extends RenderObject {
  Probe({this.minW = 0, this.maxW = 0, this.cells = 0});

  final int minW;
  final int maxW;
  final int cells;

  /// The extent last asked at: min width, max width, min height, max
  /// height (-1: never).
  final asked = List<int>.filled(4, -1);

  int _answer(int kind, int extent, int answer) {
    asked[kind] = extent;
    return answer;
  }

  int _rows(int width) => width == 0 ? cells : (cells + width - 1) ~/ width;

  @override
  int computeMinIntrinsicWidth(int height) => _answer(0, height, minW);

  @override
  int computeMaxIntrinsicWidth(int height) => _answer(1, height, maxW);

  @override
  int computeMinIntrinsicHeight(int width) => _answer(2, width, _rows(width));

  @override
  int computeMaxIntrinsicHeight(int width) =>
      _answer(3, width, _rows(width) + 1);

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) {}
}

/// The children of [o], in order.
List<RenderObject> childrenOf(RenderObject o) {
  final out = <RenderObject>[];
  o.visitChildren(out.add);
  return out;
}

/// Where each child of [wrap] is and how big it is: `x,y wxh`.
List<String> boxes(RenderWrap wrap) => [
  for (final c in childrenOf(wrap))
    '${c.parentData.dx},${c.parentData.dy} ${c.width}x${c.height}',
];

/// Labels of mixed widths.
List<RenderObject> labels() => [
  for (final s in ['ab', 'cde', 'f', 'ghij']) Label(s),
];

/// What [body] prints.
List<String> printed(void Function() body) {
  final lines = <String>[];
  runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (_, _, _, line) => lines.add(line),
    ),
  );
  return lines;
}

void main() {
  group('runs', () {
    // the runs of the labels at each width, gap 1 and run gap 1
    const runs = <int, List<String>>{
      13: ['ab cde f ghij'],
      12: ['ab cde f', '', 'ghij'],
      8: ['ab cde f', '', 'ghij'],
      7: ['ab cde', '', 'f ghij'],
      5: ['ab', '', 'cde f', '', 'ghij'],
      // a child as long as the wrap at most
      3: ['ab', '', 'cde', '', 'f', '', 'ghi'],
    };
    for (final MapEntry(key: width, value: want) in runs.entries) {
      test('children of mixed widths wrap at $width columns', () {
        final v = View(width, 7);
        final wrap = RenderWrap(gap: 1, runGap: 1, children: labels());
        expect(v.show(wrap), [
          ...want,
          for (var i = want.length; i < 7; i++) '',
        ]);
      });
    }

    test('makes as many runs as its children need', () {
      final v = View(3, 12);
      final wrap = RenderWrap(
        children: [for (var i = 0; i < 12; i++) Label('${i % 10}' * 2)],
      );
      expect(v.show(wrap), [for (var i = 0; i < 12; i++) '${i % 10}' * 2]);
    });

    test('without gaps the children of a run touch, and so do the runs', () {
      final v = View(6, 3);
      expect(v.show(RenderWrap(children: labels())), ['abcdef', 'ghij', '']);
    });

    test('a vertical wrap fills columns downwards and wraps at the '
        'height', () {
      final v = View(10, 4);
      final wrap = RenderWrap(
        direction: Axis.vertical,
        gap: 1,
        runGap: 1,
        children: [
          Block('a', 1, 2),
          Block('b', 2, 1),
          Block('c', 1, 3),
          Block('d', 1, 1),
          Block('e', 3, 4),
        ],
      );
      expect(v.show(wrap), [
        'a  c d eee',
        'a  c   eee',
        '   c   eee',
        'bb     eee',
      ]);
      expect(boxes(wrap), [
        '0,0 1x2',
        '0,3 2x1',
        '3,0 1x3',
        '5,0 1x1',
        '7,0 3x4',
      ]);
    });

    test('along an unbounded main axis the children make one run', () {
      final wrap = RenderWrap(gap: 1, children: labels())
        ..layout(
          const BoxConstraints(0, BoxConstraints.unbounded, 0, 5),
          parentUsesSize: true,
        );
      expect([wrap.width, wrap.height], [13, 1]);
      expect(boxes(wrap), ['0,0 2x1', '3,0 3x1', '7,0 1x1', '9,0 4x1']);
    });

    test('each child may take up to the whole main axis and the whole '
        'cross axis', () {
      final block = Block('x', 20, 20);
      final wrap = RenderWrap(children: [Label('ab'), block]);
      printed(() {
        wrap.layout(const BoxConstraints(0, 10, 0, 6), parentUsesSize: true);
      });
      expect(block.got, const BoxConstraints(0, 10, 0, 6));
      expect(boxes(wrap), ['0,0 2x1', '0,1 10x6']);
    });
  });

  group('size', () {
    test('as long as the longest run, as thick as the runs and the gaps '
        'between them', () {
      final wrap = RenderWrap(gap: 1, runGap: 1, children: labels())
        ..layout(const BoxConstraints(0, 7, 0, 10), parentUsesSize: true);
      expect([wrap.width, wrap.height], [6, 3]);
    });

    test('or as the constraints ask, if that is more', () {
      final wrap = RenderWrap(gap: 1, children: labels())
        ..layout(const BoxConstraints(9, 9, 4, 10), parentUsesSize: true);
      expect([wrap.width, wrap.height], [9, 4]);
    });

    test('nothing without children', () {
      final wrap = RenderWrap(gap: 1, runGap: 1)
        ..layout(const BoxConstraints(0, 9, 0, 9), parentUsesSize: true);
      expect([wrap.width, wrap.height], [0, 0]);
    });
  });

  group('alignment', () {
    // a run of three one-column children and one of nine columns, in 10
    // and 11 columns: 7 and 8 cells free in the first, 1 and 2 in the
    // second
    const alignments = <WrapAlignment, List<List<String>>>{
      WrapAlignment.start: [
        ['abc', 'ddddddddd'],
        ['abc', 'ddddddddd'],
      ],
      WrapAlignment.end: [
        ['       abc', ' ddddddddd'],
        ['        abc', '  ddddddddd'],
      ],
      // the odd cell after them
      WrapAlignment.center: [
        ['   abc', 'ddddddddd'],
        ['    abc', ' ddddddddd'],
      ],
      // the leftover cells to the first gaps; a single child at the start
      WrapAlignment.spaceBetween: [
        ['a    b   c', 'ddddddddd'],
        ['a    b    c', 'ddddddddd'],
      ],
      // half a gap at either end
      WrapAlignment.spaceAround: [
        ['  a  b  c', ' ddddddddd'],
        ['  a   b  c', ' ddddddddd'],
      ],
      WrapAlignment.spaceEvenly: [
        ['  a  b  c', ' ddddddddd'],
        ['  a  b  c', ' ddddddddd'],
      ],
    };
    for (final MapEntry(key: alignment, value: want) in alignments.entries) {
      test('$alignment shares the free cells of each run in whole '
          'cells', () {
        for (final (i, width) in [10, 11].indexed) {
          final v = View(width, 2);
          final wrap = RenderWrap(
            alignment: alignment,
            children: [
              for (final s in ['a', 'b', 'c', 'ddddddddd']) Label(s),
            ],
          );
          expect(v.show(wrap), want[i], reason: '$width columns');
        }
      });
    }

    // three runs of a row each in 7 rows: 4 rows free
    const runAlignments = <WrapAlignment, List<String>>{
      WrapAlignment.start: ['ab', 'c', 'de', '', '', '', ''],
      WrapAlignment.end: ['', '', '', '', 'ab', 'c', 'de'],
      WrapAlignment.center: ['', '', 'ab', 'c', 'de', '', ''],
      WrapAlignment.spaceBetween: ['ab', '', '', 'c', '', '', 'de'],
      WrapAlignment.spaceAround: ['', 'ab', '', '', 'c', '', 'de'],
      WrapAlignment.spaceEvenly: ['', 'ab', '', 'c', '', 'de', ''],
    };
    for (final MapEntry(key: alignment, value: want) in runAlignments.entries) {
      test('$alignment shares the free cells across the runs', () {
        final v = View(3, 7);
        final wrap = RenderWrap(
          gap: 1,
          runAlignment: alignment,
          children: [Label('ab'), Label('c'), Label('de')],
        );
        expect(v.show(wrap), want);
      });
    }

    // a child 3 rows tall makes the run 3 rows tall; where its siblings of
    // 1 and 2 rows go
    const crossAlignments = <WrapCrossAlignment, List<String>>{
      WrapCrossAlignment.start: ['1,0 1x1', '2,0 1x2'],
      WrapCrossAlignment.end: ['1,2 1x1', '2,1 1x2'],
      // the odd cell after it
      WrapCrossAlignment.center: ['1,1 1x1', '2,0 1x2'],
    };
    for (final MapEntry(key: alignment, value: want)
        in crossAlignments.entries) {
      test('$alignment places each child in its run', () {
        final row = RenderWrap(
          crossAxisAlignment: alignment,
          runGap: 1,
          children: [
            Block('a', 1, 3),
            Block('b', 1, 1),
            Block('c', 1, 2),
            Block('d', 3, 1),
          ],
        )..layout(const BoxConstraints(0, 3, 0, 9), parentUsesSize: true);
        expect([row.width, row.height], [3, 5]);
        expect(boxes(row), ['0,0 1x3', ...want, '0,4 3x1']);
        final column = RenderWrap(
          direction: Axis.vertical,
          crossAxisAlignment: alignment,
          children: [Block('a', 3, 1), Block('b', 1, 1), Block('c', 2, 1)],
        )..layout(const BoxConstraints(0, 9, 0, 3), parentUsesSize: true);
        expect([column.width, column.height], [3, 3]);
        expect(boxes(column), [
          '0,0 3x1',
          for (final box in want)
            switch (box.split(' ')) {
              [final at, final size] =>
                '${at.split(',').reversed.join(',')} '
                    '${size.split('x').reversed.join('x')}',
              _ => box,
            },
        ]);
      });
    }
  });

  group('runs that do not fit', () {
    test('are cut off at the bounds of the wrap', () {
      final v = View(5, 2);
      printed(() {
        expect(v.show(RenderWrap(gap: 1, children: labels())), [
          'ab',
          'cde f',
        ]);
      });
    });

    test('are reported once, in debug', () {
      final v = View(5, 2);
      final wrap = RenderWrap(gap: 1, children: [Label('ab'), Label('cd')]);
      final lines = printed(() {
        v.show(wrap);
        wrap.add(Label('ef'));
        v.frame();
        wrap.add(Label('ghi'));
        v.frame();
        wrap.add(Label('jk'));
        v.frame();
      });
      var asserts = false;
      assert(asserts = true, 'debug only');
      expect(lines, [
        if (asserts)
          endsWith(' warning A RenderWrap overflowed by 1 row on the bottom.'),
      ]);
      expect(v.rows(), ['ab cd', 'ef']);
      final vertical = View(2, 1);
      final column = RenderWrap(
        direction: Axis.vertical,
        children: [Label('a'), Label('b'), Label('c')],
      );
      expect(
        printed(() => vertical.show(column)),
        [
          if (asserts)
            endsWith(
              ' warning A RenderWrap overflowed by 1 column on the right.',
            ),
        ],
      );
    });

    test("are reported to the owner's log route where it has one", () {
      final v = View(2, 1);
      final records = <LogRecord>[];
      v.owner.onLog = records.add;
      final column = RenderWrap(
        direction: Axis.vertical,
        children: [Label('a'), Label('b'), Label('c')],
      );
      var asserts = false;
      assert(asserts = true, 'debug only');
      expect(printed(() => v.show(column)), isEmpty);
      expect(
        [for (final r in records) (r.level, r.message)],
        [
          if (asserts)
            (
              LogLevel.warning,
              'A RenderWrap overflowed by 1 column on the right.',
            ),
        ],
      );
    });

    test('are described with what overflows', () {
      final v = View(5, 2);
      final wrap = RenderWrap(gap: 1, runGap: 1, children: labels());
      printed(() => v.show(wrap));
      final node = wrap.describe();
      expect('$node', contains('overflow: 3 rows'));
      expect(node.flags, contains(DiagnosticsFlag.overflow));
      final fits = View(13, 1)..show(wrap);
      expect(fits.rows(), ['ab cde f ghij']);
      expect(wrap.describe().flags, isNot(contains(DiagnosticsFlag.overflow)));
    });
  });

  group('intrinsic sizes', () {
    test('along the main axis: the longest child at least, all in one run '
        'at most', () {
      final a = Probe(minW: 2, maxW: 3);
      final b = Probe(minW: 4, maxW: 5);
      final c = Probe(minW: 1, maxW: 2);
      final wrap = RenderWrap(gap: 1, runGap: 3, children: [a, b, c]);
      expect(wrap.getMinIntrinsicWidth(7), 4);
      expect(wrap.getMaxIntrinsicWidth(7), 3 + 5 + 2 + 2);
      expect([a.asked[0], b.asked[0], c.asked[0]], [7, 7, 7]);
      expect([a.asked[1], b.asked[1], c.asked[1]], [7, 7, 7]);
    });

    test('across the main axis: the runs the children make at the length '
        'they want, each as thick as its thickest child', () {
      final a = Probe(maxW: 3, cells: 6);
      final b = Probe(maxW: 5, cells: 5);
      final c = Probe(maxW: 2, cells: 2);
      final wrap = RenderWrap(gap: 1, runGap: 1, children: [a, b, c]);
      // a; b and c
      expect(wrap.getMinIntrinsicHeight(8), 2 + 1 + 1);
      expect([a.asked[2], b.asked[2], c.asked[2]], [3, 5, 2]);
      expect(wrap.getMaxIntrinsicHeight(8), 3 + 1 + 2);
      expect([a.asked[3], b.asked[3], c.asked[3]], [3, 5, 2]);
      const unbounded = BoxConstraints.unbounded;
      expect(
        [a.asked[1], b.asked[1], c.asked[1]],
        [unbounded, unbounded, unbounded],
      );
      // a child no longer than the wrap: a; b; c
      expect(wrap.getMinIntrinsicHeight(4), 2 + 1 + 2 + 1 + 1);
      expect(b.asked[2], 4);
      // all in one run
      expect(wrap.getMinIntrinsicHeight(unbounded), 2);
    });

    test('of a vertical wrap', () {
      final column = RenderWrap(
        direction: Axis.vertical,
        gap: 1,
        runGap: 1,
        children: labels(),
      );
      expect(column.getMinIntrinsicHeight(5), 1);
      expect(column.getMaxIntrinsicHeight(5), 4 + 3);
      // ab and cde; f and ghij
      expect(column.getMinIntrinsicWidth(3), 3 + 1 + 4);
      expect(column.getMaxIntrinsicWidth(3), 3 + 1 + 4);
      expect(column.getMaxIntrinsicWidth(1), 2 + 1 + 3 + 1 + 1 + 1 + 4);
    });
  });

  test('a child whose size the wrap uses lays the wrap out again, and may '
      'go to another run', () {
    final v = View(8, 2);
    final [a, b, c] = [Label('ab'), Label('cd'), Label('ef')];
    expect(v.show(RenderWrap(gap: 1, children: [a, b, c])), ['ab cd ef', '']);
    a.text = 'abx';
    v.frame();
    expect(v.rows(), ['abx cd', 'ef']);
    // the same constraints: b and c have nothing to do
    expect([a.layouts, b.layouts, c.layouts], [2, 1, 1]);
  });

  test('a new setting lays the wrap out again', () {
    final v = View(5, 4);
    final wrap = RenderWrap(children: [Label('ab'), Label('c'), Label('de')]);
    v.show(wrap);
    expect(boxes(wrap), ['0,0 2x1', '2,0 1x1', '3,0 2x1']);
    wrap.gap = 1;
    v.frame();
    expect(boxes(wrap), ['0,0 2x1', '3,0 1x1', '0,1 2x1']);
    wrap.runGap = 1;
    v.frame();
    expect(boxes(wrap), ['0,0 2x1', '3,0 1x1', '0,2 2x1']);
    wrap.alignment = WrapAlignment.end;
    v.frame();
    expect(boxes(wrap), ['1,0 2x1', '4,0 1x1', '3,2 2x1']);
    wrap.runAlignment = WrapAlignment.end;
    v.frame();
    expect(boxes(wrap), ['1,1 2x1', '4,1 1x1', '3,3 2x1']);
    // runs of ab and c, and of de
    wrap.direction = Axis.vertical;
    v.frame();
    expect(boxes(wrap), ['0,1 2x1', '0,3 1x1', '3,3 2x1']);
    wrap.crossAxisAlignment = WrapCrossAlignment.end;
    v.frame();
    expect(boxes(wrap), ['0,1 2x1', '1,3 1x1', '3,3 2x1']);
    expect(
      [
        wrap.direction,
        wrap.alignment,
        wrap.runAlignment,
        wrap.crossAxisAlignment,
        wrap.gap,
        wrap.runGap,
      ],
      [
        Axis.vertical,
        WrapAlignment.end,
        WrapAlignment.end,
        WrapCrossAlignment.end,
        1,
        1,
      ],
    );
    expect(
      '${wrap.describe()}',
      'RenderWrap ‹vertical, alignment: end, runAlignment: end, '
          'crossAxisAlignment: end, gap: 1, runGap: 1, constraints: tight›',
    );
  });

  test('a hit finds the child of a later run at its cell', () {
    final v = View(5, 2);
    final [a, b, c] = [Label('ab'), Label('cd'), Label('e')];
    v.show(RenderWrap(gap: 1, children: [a, b, c]));
    final result = HitTestResult();
    v.owner.hitTest(result, 0, 1);
    expect(result[0], same(c));
    v.owner.hitTest(result, 4, 0);
    expect(result[0], same(b));
    expect(result.xAt(0), 1);
  });
}
