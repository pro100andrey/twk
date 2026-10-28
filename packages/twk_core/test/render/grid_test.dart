// A grid lays its children out in the cells of its columns and rows: fixed
// tracks, fractions of the cells left and tracks as long as their content
// asks for, the cells shared out in whole cells; a child may span tracks.
// Painted frames go through the terminal emulator too, which must show
// what the screen holds.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/vt.dart';

/// A screen and a terminal emulator.
final class View {
  View(this.width, this.height)
    : screen = Screen(width, height),
      vt = Vt(width, height) {
    owner = PipelineOwner(() {}, segmenter: screen.canvas.segmenter);
  }

  final int width;
  final int height;
  final Screen screen;
  final Vt vt;
  late final PipelineOwner owner;

  /// Lays the tree out, paints what changed and shows the frame to the
  /// emulator; returns the rows of the screen.
  List<String> frame() {
    owner
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    final bytes = screen.render();
    if (bytes != null) {
      vt.feed(bytes);
    }
    expect(vt.errors, isEmpty, reason: 'what the emulator rejected');
    final rows = [
      for (var y = 0; y < height; y++)
        [
          for (var x = 0; x < width; x++)
            screen.glyphs.stringOf(screen.surface.cells[y * width + x]),
        ].join().trimRight(),
    ];
    expect(
      [for (final r in vt.dump().split('\n')) r.trimRight()],
      rows,
      reason: 'what the terminal shows',
    );
    return rows;
  }

  /// What [root] paints on the whole screen.
  List<String> show(RenderObject root) {
    owner.root = root;
    return frame();
  }

  /// A pen with an opaque background, as a repaint boundary needs.
  late final int opaque = screen.styles.pen(
    const Pen(bg: Color.rgb(0, 0, 0)),
  );
}

/// One line of [text] (one column per character), as wide as the text
/// within the constraints, which it asks for; a new [text] lays it out
/// again. Keeps the constraints it was last laid out with, and counts its
/// layouts and paints.
final class Label extends RenderObject {
  Label(this._text);

  String _text;
  BoxConstraints? got;
  var layouts = 0;
  var paints = 0;

  String get text => _text;
  set text(String t) {
    _text = t;
    markNeedsLayout();
  }

  @override
  void performLayout(BoxConstraints c) {
    layouts++;
    got = c;
    width = c.constrainW(_text.length);
    height = c.constrainH(1);
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
  void paint(PaintContext ctx) {
    paints++;
    ctx.canvas.text(0, 0, _text, ctx.canvas.styles.pen(const Pen()));
  }
}

/// Fills all the room it gets with [char]; asks for none.
final class Fill extends RenderObject {
  Fill(this.char);

  final String char;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
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
}

/// Asks for [minW], [maxW], [minH] and [maxH] at any extent; keeps the
/// extent it was last asked at for each.
final class Probe extends RenderObject {
  Probe({this.minW = 0, this.maxW = 0, this.minH = 0, this.maxH = 0});

  final int minW;
  final int maxW;
  final int minH;
  final int maxH;

  /// The extent last asked at: min width, max width, min height, max
  /// height (-1: never).
  final asked = List<int>.filled(4, -1);

  int _answer(int kind, int extent, int answer) {
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

/// [cells] cells of text that break anywhere: one cell wide at the least,
/// [cells] at the most, and as many rows as they fill at a width. Keeps
/// the width it was last asked for its height at.
final class Words extends RenderObject {
  Words(this.cells);

  final int cells;
  var askedAt = -1;

  int _rows(int width) {
    askedAt = width;
    return width <= 0 ? cells : (cells + width - 1) ~/ width;
  }

  @override
  int computeMinIntrinsicWidth(int height) => 1;

  @override
  int computeMaxIntrinsicWidth(int height) => cells;

  @override
  int computeMinIntrinsicHeight(int width) => _rows(width);

  @override
  int computeMaxIntrinsicHeight(int width) => _rows(width);

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) {}
}

/// A repaint boundary that fills all the room it gets with [char] in an
/// opaque [pen]; a new [char] repaints it on its own.
final class Panel extends RenderObject {
  Panel(this._char, this.pen);

  String _char;
  final int pen;

  String get char => _char;
  set char(String c) {
    _char = c;
    markNeedsPaint();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) =>
      ctx.canvas.fill(0, 0, width, height, pen, _char.codeUnitAt(0));
}

/// [child] in the cells from [row] and [column], spanning [rowSpan] rows
/// and [columnSpan] columns; placed after the child before it without a
/// row and a column.
RenderObject cell(
  RenderObject child, [
  int? row,
  int? column,
  int rowSpan = 1,
  int columnSpan = 1,
]) => child
  ..parentData = (GridParentData()
    ..row = row
    ..column = column
    ..rowSpan = rowSpan
    ..columnSpan = columnSpan);

/// The children of [o], in order.
List<RenderObject> childrenOf(RenderObject o) {
  final out = <RenderObject>[];
  o.visitChildren(out.add);
  return out;
}

/// Where each child of [o] is and how big it is: `x,y wxh`.
List<String> boxes(RenderObject o) => [
  for (final c in childrenOf(o))
    '${c.parentData.dx},${c.parentData.dy} ${c.width}x${c.height}',
];

/// The property [name] of [o]'s description; null without it.
String? property(RenderObject o, String name) {
  for (final p in o.describe().properties) {
    if (p.name == name) {
      return p.value;
    }
  }
  return null;
}

/// The widths of [grid]'s columns as laid out: `2 3 5`.
String? widths(RenderGrid grid) => property(grid, 'widths');

/// The heights of [grid]'s rows as laid out.
String? heights(RenderGrid grid) => property(grid, 'heights');

/// [grid] laid out within [c]; returns the widths of its columns.
String? widthsIn(RenderGrid grid, BoxConstraints c) {
  grid.layout(c, parentUsesSize: true);
  return widths(grid);
}

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
  test('tracks describe themselves and are equal by what they say', () {
    expect(
      [
        const GridTrack.fixed(5),
        const GridTrack.fr(2),
        const GridTrack.content(),
        const GridTrack.fr(1, min: 4),
        const GridTrack.content(min: 2, max: 10),
        const GridTrack.content(min: 3, max: 3),
      ].join(' '),
      '5 2fr content 1fr(4..∞) content(2..10) content(3)',
    );
    // a track made at run time
    final made = [
      for (final max in [3]) GridTrack.fr(1, max: max),
    ].single;
    expect(made, const GridTrack.fr(1, max: 3));
    expect(made.hashCode, const GridTrack.fr(1, max: 3).hashCode);
    expect(const GridTrack.fixed(0), isNot(const GridTrack.content(max: 0)));
  });

  group('fixed tracks', () {
    test('take their cells, each child laid out exactly as big as its '
        'cells', () {
      final a = Label('abcd');
      final grid = RenderGrid(
        columns: const [GridTrack.fixed(3), GridTrack.fixed(2)],
        rows: const [GridTrack.fixed(1), GridTrack.fixed(2)],
        children: [
          cell(a, 0, 0),
          cell(Label('ef'), 0, 1),
          cell(Fill('x'), 1, 0),
          cell(Fill('y'), 1, 1),
        ],
      )..layout(const BoxConstraints(0, 20, 0, 10), parentUsesSize: true);
      expect([grid.width, grid.height], [5, 3]);
      expect(boxes(grid), ['0,0 3x1', '3,0 2x1', '0,1 3x2', '3,1 2x2']);
      expect(a.got, const BoxConstraints.tight(3, 1));
      expect(View(6, 4).show(grid), ['abcef', 'xxxyy', 'xxxyy', '']);
    });

    test('are columnGap and rowGap apart, and a child that spans tracks '
        'takes the gaps between them', () {
      final grid = RenderGrid(
        columns: const [
          GridTrack.fixed(2),
          GridTrack.fixed(2),
          GridTrack.fixed(2),
        ],
        rows: const [GridTrack.fixed(1), GridTrack.fixed(1)],
        columnGap: 1,
        rowGap: 1,
        children: [
          cell(Fill('a'), 0, 0, 1, 2),
          cell(Fill('b'), 0, 2, 2),
          cell(Fill('c'), 1, 0),
          cell(Fill('d'), 1, 1),
        ],
      );
      expect(View(9, 4).show(grid), [
        'aaaaa bb',
        '      bb',
        'cc dd bb',
        '',
      ]);
      expect(boxes(grid), ['0,0 5x1', '6,0 2x3', '0,2 2x1', '3,2 2x1']);
    });
  });

  group('fraction tracks', () {
    test('share the cells the others leave by their fractions', () {
      final grid = RenderGrid(
        columns: const [GridTrack.fixed(2), GridTrack.fr(1), GridTrack.fr(2)],
        rows: const [GridTrack.fr(1)],
        columnGap: 1,
        children: [Fill('a'), Fill('b'), Fill('c')],
      );
      // 8 cells left: 2.7 and 5.3
      expect(View(12, 1).show(grid), ['aa bbb ccccc']);
    });

    test('get the leftover cells first', () {
      var grid = RenderGrid(
        columns: const [GridTrack.fr(1), GridTrack.fr(1), GridTrack.fr(1)],
        rows: const [GridTrack.fr(1)],
        children: [Fill('a'), Fill('b'), Fill('c')],
      );
      expect(View(10, 1).show(grid), ['aaaabbbccc']);
      // whatever their fractions: 4.4, 2.2 and 4.4 cells
      grid = RenderGrid(
        columns: const [GridTrack.fr(2), GridTrack.fr(1), GridTrack.fr(2)],
        rows: const [GridTrack.fr(1)],
        children: [Fill('a'), Fill('b'), Fill('c')],
      );
      expect(View(11, 1).show(grid), ['aaaaabbcccc']);
    });

    test('stay within their bounds, the others sharing the rest', () {
      const ten = BoxConstraints.tight(10, 1);
      expect(
        widthsIn(
          RenderGrid(columns: const [GridTrack.fr(1, max: 2), GridTrack.fr(1)]),
          ten,
        ),
        '2 8',
      );
      // 5 and 5: the maximum takes more than the minimum adds
      expect(
        widthsIn(
          RenderGrid(
            columns: const [GridTrack.fr(1, min: 6), GridTrack.fr(1, max: 2)],
          ),
          ten,
        ),
        '8 2',
      );
      // 4, 3 and 3: the minimum adds
      expect(
        widthsIn(
          RenderGrid(
            columns: const [
              GridTrack.fr(1, min: 7),
              GridTrack.fr(1),
              GridTrack.fr(1),
            ],
          ),
          ten,
        ),
        '7 2 1',
      );
    });

    test('get no more than their minimum when the others take it all', () {
      final grid = RenderGrid(
        columns: const [
          GridTrack.fixed(10),
          GridTrack.fr(1),
          GridTrack.fr(1, min: 1),
        ],
      );
      final lines = printed(() {
        expect(widthsIn(grid, const BoxConstraints.tight(10, 1)), '10 0 1');
      });
      var asserts = false;
      assert(asserts = true, 'debug only');
      expect(lines, hasLength(asserts ? 1 : 0));
    });
  });

  group('content tracks', () {
    test('are as long as their children want when there are cells for '
        'it; rows and columns past the lists are content tracks', () {
      final grid = RenderGrid(
        columns: const [GridTrack.content(), GridTrack.fr(1)],
        columnGap: 1,
        children: [
          Label('Name'),
          Label('Bob'),
          Label('E-mail'),
          Label('bob@example.com'),
        ],
      );
      expect(View(12, 3).show(grid), ['Name   Bob', 'E-mail bob@e', '']);
      expect([widths(grid), heights(grid)], ['6 5', '1 1']);
    });

    test('shrink towards what their children need by even parts of the '
        'cells there are, those left over going to the first', () {
      RenderGrid grid() => RenderGrid(
        columns: const [GridTrack.content(), GridTrack.content()],
        children: [Probe(minW: 2, maxW: 10), Probe(minW: 4, maxW: 6)],
      );
      expect(widthsIn(grid(), const BoxConstraints(0, 30, 0, 1)), '10 6');
      // 2 and 4 needed, 6 cells more: 2 each, then the second wants no more
      expect(widthsIn(grid(), const BoxConstraints.tight(12, 1)), '6 6');
      expect(widthsIn(grid(), const BoxConstraints.tight(11, 1)), '5 6');
      expect(widthsIn(grid(), const BoxConstraints.tight(6, 1)), '2 4');
      final even = RenderGrid(
        columns: const [GridTrack.content(), GridTrack.content()],
        children: [Probe(maxW: 10), Probe(maxW: 10)],
      );
      expect(widthsIn(even, const BoxConstraints.tight(5, 1)), '3 2');
    });

    test('stay within their bounds', () {
      final long = Label('abcdefg');
      final grid = RenderGrid(
        columns: const [
          GridTrack.content(min: 3, max: 5),
          GridTrack.content(min: 3, max: 5),
          GridTrack.content(min: 3),
        ],
        children: [Label('ab'), long],
      );
      expect(widthsIn(grid, const BoxConstraints(0, 30, 0, 5)), '3 5 3');
      expect([grid.width, grid.height], [11, 1]);
      expect(long.got, const BoxConstraints.tight(5, 1));
    });

    test('of rows ask their children for heights at the widths of the '
        'columns they span', () {
      final a = Words(12);
      final b = Words(12);
      final grid = RenderGrid(
        columns: const [GridTrack.fixed(4), GridTrack.fixed(2)],
        children: [cell(a, 0, 0, 1, 2), cell(b, 1, 0)],
      )..layout(const BoxConstraints(0, 10, 0, 10), parentUsesSize: true);
      expect(heights(grid), '2 3');
      expect([a.askedAt, b.askedAt], [6, 4]);
    });
  });

  group('a child that spans tracks', () {
    test('grows the content tracks it spans by even parts of what it '
        'lacks, gaps included', () {
      RenderGrid grid() => RenderGrid(
        columns: const [
          GridTrack.fixed(2),
          GridTrack.content(),
          GridTrack.content(),
        ],
        rows: const [GridTrack.fixed(1)],
        columnGap: 1,
        children: [cell(Probe(minW: 5, maxW: 13), 0, 0, 1, 3)],
      );
      // it needs 1 more and wants 8 more than that: 4 each
      expect(widthsIn(grid(), const BoxConstraints(0, 30, 0, 1)), '2 5 4');
      expect(widthsIn(grid(), const BoxConstraints.tight(9, 1)), '2 3 2');
      expect(widthsIn(grid(), const BoxConstraints.tight(5, 1)), '2 1 0');
    });

    test('grows the content rows it spans', () {
      final grid = RenderGrid(
        columns: const [GridTrack.fixed(2)],
        rows: const [GridTrack.content(), GridTrack.content()],
        children: [cell(Probe(minH: 3, maxH: 3), 0, 0, 2)],
      )..layout(const BoxConstraints(0, 10, 0, 10), parentUsesSize: true);
      expect(heights(grid), '2 1');
    });

    test('grows nothing when it spans a fraction track, which gives it the '
        'cells', () {
      final long = Label('abcdefghij');
      final grid = RenderGrid(
        columns: const [GridTrack.content(), GridTrack.fr(1)],
        children: [cell(Label('ab'), 0, 0), cell(long, 1, 0, 1, 2)],
      );
      expect(widthsIn(grid, const BoxConstraints.tight(12, 2)), '2 10');
      expect(boxes(grid)[1], '0,1 12x1');
    });

    test('is sized after those that span fewer tracks', () {
      final grid = RenderGrid(
        columns: const [
          GridTrack.content(),
          GridTrack.content(),
          GridTrack.content(),
        ],
        rows: const [GridTrack.fixed(1), GridTrack.fixed(1)],
        children: [
          cell(Probe(minW: 6, maxW: 6), 0, 0, 1, 3),
          cell(Probe(minW: 4, maxW: 4), 1, 0, 1, 2),
        ],
      );
      // 2 and 2 for the second, then 1 and 1 more for the first
      expect(widthsIn(grid, const BoxConstraints(0, 30, 0, 2)), '3 3 0');
    });
  });

  group('along an unbounded axis the grid', () {
    test('is as long as its children want, the fraction tracks at the '
        'fewest cells per part that give each what it asks for', () {
      final grid = RenderGrid(
        columns: const [GridTrack.content(), GridTrack.fr(1), GridTrack.fr(2)],
        rows: const [GridTrack.fr(1)],
        children: [Label('abc'), Label('ab'), Label('abcde')],
      );
      const unbounded = BoxConstraints.unbounded;
      // 2 cells for the first part, 3 per part for the second
      expect(
        widthsIn(grid, const BoxConstraints(0, unbounded, 0, unbounded)),
        '3 3 6',
      );
      expect([grid.width, grid.height], [12, 1]);
    });

    test('stretches its fraction tracks to the least it may be', () {
      final grid = RenderGrid(
        columns: const [GridTrack.content(), GridTrack.fr(1), GridTrack.fr(2)],
        rows: const [GridTrack.fr(1)],
        children: [Label('abc'), Label('ab'), Label('abcde')],
      );
      expect(
        widthsIn(
          grid,
          const BoxConstraints(20, BoxConstraints.unbounded, 1, 1),
        ),
        '3 6 11',
      );
    });
  });

  group('intrinsic sizes', () {
    test('of the columns: the content tracks at what their children need '
        'or want, at any height', () {
      final probe = Probe(minW: 3, maxW: 7);
      final grid = RenderGrid(
        columns: const [GridTrack.fixed(2), GridTrack.content()],
        columnGap: 1,
        children: [cell(probe, 0, 1)],
      );
      expect(grid.getMinIntrinsicWidth(5), 2 + 1 + 3);
      expect(grid.getMaxIntrinsicWidth(5), 2 + 1 + 7);
      expect(probe.asked.sublist(0, 2), [
        BoxConstraints.unbounded,
        BoxConstraints.unbounded,
      ]);
      expect(RenderGrid().getMaxIntrinsicWidth(5), 0);
    });

    test('of the columns: the fraction tracks at the fewest cells per part '
        'that give each what its children ask for', () {
      final grid = RenderGrid(
        columns: const [GridTrack.fr(1), GridTrack.fr(2)],
        children: [Probe(minW: 3, maxW: 5), Probe(minW: 2, maxW: 4)],
      );
      expect(grid.getMinIntrinsicWidth(1), 3 + 6);
      expect(grid.getMaxIntrinsicWidth(1), 5 + 10);
      expect(widthsIn(grid, const BoxConstraints.tight(9, 1)), '3 6');
    });

    test('of the columns: a child that spans fraction tracks asks for what '
        'the others do not give it', () {
      final grid = RenderGrid(
        columns: const [GridTrack.fixed(2), GridTrack.fr(1), GridTrack.fr(1)],
        children: [cell(Probe(minW: 10, maxW: 12), 0, 0, 1, 3)],
      );
      expect(grid.getMinIntrinsicWidth(1), 2 + 4 + 4);
      expect(grid.getMaxIntrinsicWidth(1), 2 + 5 + 5);
    });

    test('of the rows: what their children ask for at the widths of the '
        'columns sized in the width, with the gaps', () {
      final a = Words(12);
      final b = Words(6);
      final grid = RenderGrid(
        columns: const [GridTrack.fr(1), GridTrack.fr(1)],
        rowGap: 1,
        children: [a, b, cell(Label('c'), 1, 0)],
      );
      expect(grid.getMinIntrinsicHeight(8), 3 + 1 + 1);
      expect([a.askedAt, b.askedAt], [4, 4]);
      expect(grid.getMaxIntrinsicHeight(12), 2 + 1 + 1);
      expect([a.askedAt, b.askedAt], [6, 6]);
    });
  });

  group('placement', () {
    test('a child without a row and a column goes after the one before '
        'it, on the next row when it would reach past the last column', () {
      final grid = RenderGrid(
        columns: const [
          GridTrack.fixed(1),
          GridTrack.fixed(1),
          GridTrack.fixed(1),
        ],
        children: [
          Label('a'),
          cell(Label('b'), 1, 1),
          Label('c'),
          Label('d'),
          cell(Label('ef'), null, null, 1, 2),
          cell(Label('gh'), null, null, 1, 2),
        ],
      );
      expect(View(3, 5).show(grid), ['a', ' bc', 'def', 'gh', '']);
    });

    test('without columns, each such child is on a row of its own', () {
      final grid = RenderGrid(children: [Label('a'), Label('bc')])
        ..layout(const BoxConstraints(0, 10, 0, 10), parentUsesSize: true);
      expect(boxes(grid), ['0,0 2x1', '0,1 2x1']);
    });

    test('cells another child takes are not skipped: children that '
        'overlap are painted in order', () {
      final grid = RenderGrid(
        columns: const [GridTrack.fixed(2), GridTrack.fixed(2)],
        children: [
          cell(Label('ab'), 0, 0, 2),
          Label('cd'),
          Label('XY'),
        ],
      );
      expect(View(4, 2).show(grid), ['abcd', 'XY']);
    });
  });

  test('a repaint boundary that repaints on its own leaves the children '
      'after it that overlap it on top', () {
    final v = View(6, 2);
    final under = Panel('.', v.opaque);
    final over = Label('ab');
    final beside = Label('cd');
    final grid = RenderGrid(
      columns: const [GridTrack.fixed(4), GridTrack.fixed(2)],
      rows: const [GridTrack.fixed(2)],
      children: [cell(under, 0, 0), cell(over, 0, 0), cell(beside, 0, 1)],
    );
    expect(v.show(grid), ['ab..cd', '....']);
    under.char = ':';
    expect(v.frame(), ['ab::cd', '::::']);
    expect([over.paints, beside.paints], [2, 1]);
  });

  test('tracks that do not fit are cut off at the bounds of the grid, '
      'reported once in debug, and described', () {
    final v = View(10, 1);
    final grid = RenderGrid(
      columns: const [
        GridTrack.fixed(4),
        GridTrack.fixed(4),
        GridTrack.fixed(4),
      ],
      rows: const [GridTrack.fixed(2)],
      children: [Label('aaaa'), Label('bbbb'), Label('cccc')],
    );
    var shown = <String>[];
    final lines = printed(() {
      v.show(grid);
      grid.markNeedsLayout();
      shown = v.frame();
    });
    var asserts = false;
    assert(asserts = true, 'debug only');
    expect(lines, [
      if (asserts)
        endsWith(
          ' warning A RenderGrid overflowed by 2 columns on the right and '
          '1 row on the bottom.',
        ),
    ]);
    expect(shown, ['aaaabbbbcc']);
    expect(property(grid, 'overflow'), '2 columns, 1 row');
    expect(grid.describe().flags, contains(DiagnosticsFlag.overflow));
  });

  test("tracks that do not fit are reported to the owner's log route "
      'where it has one', () {
    final v = View(4, 1);
    final records = <LogRecord>[];
    v.owner.onLog = records.add;
    final grid = RenderGrid(
      columns: const [GridTrack.fixed(4), GridTrack.fixed(4)],
      rows: const [GridTrack.fixed(1)],
      children: [Label('aaaa'), Label('bbbb')],
    );
    var asserts = false;
    assert(asserts = true, 'debug only');
    expect(printed(() => v.show(grid)), isEmpty);
    expect(
      [for (final r in records) (r.level, r.message)],
      [
        if (asserts)
          (
            LogLevel.warning,
            'A RenderGrid overflowed by 4 columns on the right.',
          ),
      ],
    );
  });

  test('a child whose size a content track uses lays the grid out '
      'again', () {
    final v = View(10, 1);
    final name = Label('ab');
    final value = Label('cd');
    final grid = RenderGrid(
      columns: const [GridTrack.content(), GridTrack.fixed(3)],
      rows: const [GridTrack.fixed(1)],
      children: [name, value],
    );
    expect(v.show(grid), ['abcd']);
    name.text = 'abx';
    expect(v.frame(), ['abxcd']);
    // the same cells: the value has nothing to do
    expect([name.layouts, value.layouts], [2, 1]);
  });

  test('new tracks and gaps lay the grid out again; the same tracks in '
      'another list do not', () {
    final grid = RenderGrid(
      columns: const [GridTrack.fixed(1), GridTrack.fixed(1)],
      rows: const [GridTrack.fixed(1), GridTrack.fixed(1)],
      children: [cell(Fill('a'), 0, 0), cell(Fill('b'), 1, 1)],
    );
    const loose = BoxConstraints(0, 10, 0, 10);
    List<String> after(void Function() change) {
      change();
      grid.layout(loose, parentUsesSize: true);
      return boxes(grid);
    }

    expect(after(() {}), ['0,0 1x1', '1,1 1x1']);
    expect(after(() => grid.columnGap = 1), ['0,0 1x1', '2,1 1x1']);
    expect(after(() => grid.rowGap = 2), ['0,0 1x1', '2,3 1x1']);
    expect(
      after(
        () => grid.columns = const [GridTrack.fixed(2), GridTrack.fixed(1)],
      ),
      [
        '0,0 2x1',
        '3,3 1x1',
      ],
    );
    expect(
      after(() => grid.rows = const [GridTrack.fixed(1), GridTrack.fixed(3)]),
      [
        '0,0 2x1',
        '3,3 1x3',
      ],
    );
    grid
      ..columns = List.of(grid.columns)
      ..rows = List.of(grid.rows)
      ..columnGap = 1
      ..rowGap = 2;
    expect(grid.debugNeedsLayout, isFalse);
    expect(
      [grid.columns, grid.rows, grid.columnGap, grid.rowGap],
      [
        [const GridTrack.fixed(2), const GridTrack.fixed(1)],
        [const GridTrack.fixed(1), const GridTrack.fixed(3)],
        1,
        2,
      ],
    );
  });

  test('describes its tracks, gaps and their lengths, and its children '
      'their cells', () {
    final grid = RenderGrid(
      columns: const [
        GridTrack.fixed(2),
        GridTrack.fr(1),
        GridTrack.content(min: 2, max: 10),
      ],
      rows: const [GridTrack.fr(1, min: 4)],
      columnGap: 1,
      rowGap: 2,
      children: [cell(Label('ab'), 0, 1, 1, 2), Label('c')],
    );
    View(12, 8).show(grid);
    final node = grid.describe();
    expect(
      '$node',
      'RenderGrid ‹columns: 2 1fr content(2..10), rows: 1fr(4..∞), '
          'columnGap: 1, rowGap: 2, widths: 2 6 2, heights: 5 1, '
          'constraints: tight›',
    );
    final [a, c] = [for (final child in node.children) '$child'];
    expect(
      a,
      'Label ‹row: 0, column: 1, columnSpan: 2, offset: 3,0, constraints: '
      'tight›',
    );
    expect(c, 'Label ‹offset: 0,7, constraints: tight›');
    expect('${RenderGrid().describe()}', 'RenderGrid');
  });

  test('a child with a row and no column shows the error in the place of '
      'the grid', () {
    final v = View(60, 3);
    final reports = <String>[];
    v.owner.onError = (object, phase, error, stack) =>
        reports.add('${phase.name} ${object.runtimeType}');
    final grid = RenderGrid(
      children: [Label('a')..parentData = (GridParentData()..row = 1)],
    );
    v.show(grid);
    var asserts = false;
    assert(asserts = true, 'debug only');
    if (asserts) {
      expect(grid.debugError, contains('a row and a column, or neither'));
      expect(reports, ['layout RenderGrid']);
    }
  });
}
