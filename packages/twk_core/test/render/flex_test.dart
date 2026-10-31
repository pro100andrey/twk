// A flex lays its children out along its main axis: the inflexible ones at
// the size they want, the flexible ones sharing what is left in whole cells,
// and places them as its alignments say.
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

/// Fills all the room it gets with [char]; keeps the constraints it was
/// last laid out with.
final class Fill extends RenderObject {
  Fill(this.char);

  final String char;
  BoxConstraints? got;

  @override
  void performLayout(BoxConstraints c) {
    got = c;
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

  @override
  String toString() => char;
}

/// [w] × [h] within the constraints.
final class Sized extends RenderObject {
  Sized(this.w, this.h);

  final int w;
  final int h;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(w);
    height = c.constrainH(h);
  }

  @override
  void paint(PaintContext ctx) {}
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

/// Makes [child], a child of a flex, flexible with [flex] and [fit].
void flexible(RenderObject child, int flex, [FlexFit fit = FlexFit.tight]) {
  (child.parentData as FlexParentData)
    ..flex = flex
    ..fit = fit;
}

/// The children of [o], in order.
List<RenderObject> childrenOf(RenderObject o) {
  final out = <RenderObject>[];
  o.visitChildren(out.add);
  return out;
}

/// Where each child of [flex] is and how big it is: `x,y wxh`.
List<String> boxes(RenderFlex flex) => [
  for (final c in childrenOf(flex))
    '${c.parentData.dx},${c.parentData.dy} ${c.width}x${c.height}',
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
  group('the children of a container', () {
    test('are kept in the order they are inserted, moved and removed', () {
      final [a, b, c, d] = [for (final s in 'abcd'.split('')) Label(s)];
      final flex = RenderFlex(children: [a, c]);
      expect(childrenOf(flex), [a, c]);
      flex.insert(b, after: a);
      expect(childrenOf(flex), [a, b, c]);
      flex.insert(d);
      expect(childrenOf(flex), [d, a, b, c]);
      flex.move(d, after: c);
      expect(childrenOf(flex), [a, b, c, d]);
      flex.move(c);
      expect(childrenOf(flex), [c, a, b, d]);
      flex.move(c);
      expect(childrenOf(flex), [c, a, b, d]);
      flex.remove(a);
      expect(childrenOf(flex), [c, b, d]);
      expect(a.parent, isNull);
      expect([flex.firstChild, flex.lastChild, flex.childCount], [c, d, 3]);
      expect([flex.childBefore(b), flex.childAfter(b)], [c, d]);
      expect([flex.childBefore(c), flex.childAfter(d)], [null, null]);
      flex.add(a);
      expect(childrenOf(flex), [c, b, d, a]);
      flex.removeAll();
      expect(childrenOf(flex), isEmpty);
      expect(
        [flex.firstChild, flex.lastChild, flex.childCount],
        [
          null,
          null,
          0,
        ],
      );
      expect([
        for (final x in [a, b, c, d]) x.parent,
      ], everyElement(isNull));
    });

    test('are laid out and painted again after a change to the list', () {
      final v = View(10, 1);
      final [a, b, c] = [for (final s in 'abc'.split('')) Label(s)];
      final flex = RenderFlex(children: [a, b, c]);
      expect(v.show(flex), ['abc']);
      flex.move(c);
      v.frame();
      expect(v.rows(), ['cab']);
      flex.remove(a);
      v.frame();
      expect(v.rows(), ['cb']);
      flex.insert(Label('d'), after: c);
      v.frame();
      expect(v.rows(), ['cdb']);
      flex.removeAll();
      v.frame();
      expect(v.rows(), ['']);
    });

    test('join and leave the pipeline with the container', () {
      final v = View(10, 1);
      final a = Label('a');
      final flex = RenderFlex(children: [a]);
      v.owner.root = flex;
      expect(a.owner, same(v.owner));
      final b = Label('b');
      flex.insert(b, after: a);
      expect(b.owner, same(v.owner));
      flex.remove(a);
      expect(a.owner, isNull);
    });
  });

  group('along the main axis', () {
    test('inflexible children are as long as they want, one after another, '
        'gap cells apart', () {
      final v = View(12, 1);
      expect(v.show(RenderFlex(children: [Label('ab'), Label('cde')])), [
        'abcde',
      ]);
      expect(
        v.show(RenderFlex(gap: 2, children: [Label('ab'), Label('cde')])),
        ['ab  cde'],
      );
      // no gap without a second child
      expect(v.show(RenderFlex(gap: 2, children: [Label('ab')])), ['ab']);
    });

    test('a column puts them one below another', () {
      final v = View(4, 5);
      final column = RenderFlex(
        direction: Axis.vertical,
        crossAxisAlignment: CrossAxisAlignment.start,
        gap: 1,
        children: [Label('ab'), Label('c')],
      );
      expect(v.show(column), ['ab', '', 'c', '', '']);
    });

    // three one-column children in 10 and 11 columns: 7 and 8 cells free
    const alignments = <MainAxisAlignment, List<String>>{
      MainAxisAlignment.start: ['abc', 'abc'],
      MainAxisAlignment.end: ['       abc', '        abc'],
      // the odd cell after them
      MainAxisAlignment.center: ['   abc', '    abc'],
      // the leftover cells to the first gaps
      MainAxisAlignment.spaceBetween: ['a    b   c', 'a    b    c'],
      // half a gap at either end
      MainAxisAlignment.spaceAround: ['  a  b  c', '  a   b  c'],
      MainAxisAlignment.spaceEvenly: ['  a  b  c', '  a  b  c'],
    };

    for (final MapEntry(key: alignment, value: want) in alignments.entries) {
      test('$alignment shares the free cells in whole cells', () {
        for (final (i, width) in [10, 11].indexed) {
          final v = View(width, 1);
          final flex = RenderFlex(
            mainAxisAlignment: alignment,
            children: [Label('a'), Label('b'), Label('c')],
          );
          expect(v.show(flex), [want[i]], reason: '$width columns');
        }
      });
    }

    test('an alignment adds the free cells to the gap', () {
      final v = View(12, 1);
      expect(
        v.show(
          RenderFlex(
            gap: 2,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [Label('a'), Label('b'), Label('c')],
          ),
        ),
        ['  a  b  c'],
      );
      expect(
        v.show(
          RenderFlex(
            gap: 1,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Label('a'), Label('b'), Label('c')],
          ),
        ),
        ['a     b    c'],
      );
    });

    test('a single child is placed as each alignment says', () {
      const want = <MainAxisAlignment, String>{
        MainAxisAlignment.start: 'a',
        MainAxisAlignment.end: '         a',
        MainAxisAlignment.center: '    a',
        MainAxisAlignment.spaceBetween: 'a',
        MainAxisAlignment.spaceAround: '     a',
        MainAxisAlignment.spaceEvenly: '     a',
      };
      final v = View(10, 1);
      for (final MapEntry(key: alignment, value: row) in want.entries) {
        final flex = RenderFlex(
          mainAxisAlignment: alignment,
          children: [Label('a')],
        );
        expect(v.show(flex), [row], reason: '$alignment');
      }
    });

    test('MainAxisSize.min makes the flex as long as its children', () {
      final flex = RenderFlex(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        gap: 1,
        children: [Label('ab'), Label('c')],
      )..layout(const BoxConstraints(0, 10, 0, 1), parentUsesSize: true);
      expect([flex.width, flex.height], [4, 1]);
      // nothing free to align with
      expect(boxes(flex), ['0,0 2x1', '3,0 1x1']);
      // unless the constraints ask for more
      flex.layout(const BoxConstraints(6, 10, 0, 1), parentUsesSize: true);
      expect(flex.width, 6);
      expect(boxes(flex), ['2,0 2x1', '5,0 1x1']);
    });

    test('MainAxisSize.max makes the flex as long as it may be', () {
      final flex = RenderFlex(children: [Label('ab')])
        ..layout(const BoxConstraints(0, 10, 0, 1), parentUsesSize: true);
      expect([flex.width, flex.height], [10, 1]);
    });

    test('an inflexible child may take up to the whole main axis', () {
      final fill = Fill('x');
      printed(() {
        RenderFlex(
          children: [Label('ab'), fill],
        ).layout(const BoxConstraints(0, 10, 0, 3), parentUsesSize: true);
      });
      expect(fill.got, const BoxConstraints(0, 10, 0, 3));
    });
  });

  group('across the main axis', () {
    // a child 4 rows tall makes the row 4 rows tall; where its one-row
    // sibling goes
    const want = <CrossAxisAlignment, String>{
      CrossAxisAlignment.start: '1,0 1x1',
      CrossAxisAlignment.end: '1,3 1x1',
      // the odd cell after it
      CrossAxisAlignment.center: '1,1 1x1',
    };
    for (final MapEntry(key: alignment, value: box) in want.entries) {
      test('$alignment places a child in the flex', () {
        final row = RenderFlex(
          crossAxisAlignment: alignment,
          children: [Sized(1, 4), Label('a')],
        )..layout(const BoxConstraints(0, 10, 0, 6), parentUsesSize: true);
        expect([row.width, row.height], [10, 4]);
        expect(boxes(row), ['0,0 1x4', box]);
        final column = RenderFlex(
          direction: Axis.vertical,
          crossAxisAlignment: alignment,
          children: [Sized(4, 1), Label('a')],
        )..layout(const BoxConstraints(0, 6, 0, 10), parentUsesSize: true);
        expect([column.width, column.height], [4, 10]);
        final [x, y] = box.split(' ').first.split(',');
        expect(boxes(column), ['0,0 4x1', '$y,$x 1x1']);
      });
    }

    test('CrossAxisAlignment.stretch makes the children as thick as the '
        'flex may be', () {
      final fill = Fill('x');
      final row = RenderFlex(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [Sized(1, 4), Label('a'), fill],
      );
      flexible(fill, 1);
      row.layout(const BoxConstraints(0, 10, 0, 6), parentUsesSize: true);
      expect([row.width, row.height], [10, 6]);
      expect(boxes(row), ['0,0 1x6', '1,0 1x6', '2,0 8x6']);
      expect(fill.got, const BoxConstraints(8, 8, 6, 6));
    });

    test('other alignments leave the children as thin as they want', () {
      final fill = Fill('x');
      RenderFlex(
        children: [fill],
      ).layout(const BoxConstraints(0, 10, 2, 6), parentUsesSize: true);
      expect(fill.got, const BoxConstraints(0, 10, 0, 6));
    });
  });

  group('flexible children', () {
    test('share what the others leave by their flex factors', () {
      final v = View(10, 1);
      final [x, y] = [Fill('x'), Fill('y')];
      final row = RenderFlex(gap: 1, children: [Label('ab'), x, y]);
      flexible(x, 1);
      flexible(y, 2);
      expect(v.show(row), ['ab xx yyyy']);
    });

    test('get the leftover cells first', () {
      final v = View(10, 1);
      var [x, y, z] = [Fill('x'), Fill('y'), Fill('z')];
      var row = RenderFlex(children: [x, y, z]);
      for (final c in [x, y, z]) {
        flexible(c, 1);
      }
      expect(v.show(row), ['xxxxyyyzzz']);
      // whatever their flex factors: 4.4, 2.2 and 4.4 cells
      final w = View(11, 1);
      [x, y, z] = [Fill('x'), Fill('y'), Fill('z')];
      row = RenderFlex(children: [x, y, z]);
      flexible(x, 2);
      flexible(y, 1);
      flexible(z, 2);
      expect(w.show(row), ['xxxxxyyzzzz']);
      // the first flexible ones, wherever the inflexible ones are
      [x, y] = [Fill('x'), Fill('y')];
      row = RenderFlex(children: [Label('a'), x, Label('bc'), y]);
      flexible(x, 1);
      flexible(y, 1);
      expect(v.show(row), ['axxxxbcyyy']);
    });

    test('fill their share with FlexFit.tight, take what they want of it '
        'with FlexFit.loose', () {
      final v = View(10, 1);
      final label = Label('ab');
      final x = Fill('x');
      final row = RenderFlex(children: [label, x]);
      flexible(label, 1, FlexFit.loose);
      flexible(x, 1);
      expect(v.show(row), ['abxxxxx']);
      expect(x.got, const BoxConstraints(5, 5, 0, 1));
      // what the loose child left is free for the alignment
      row.mainAxisAlignment = MainAxisAlignment.end;
      v.frame();
      expect(v.rows(), ['   abxxxxx']);
      flexible(x, 1, FlexFit.loose);
      row.markNeedsLayout();
      v.frame();
      expect(x.got, const BoxConstraints(0, 5, 0, 1));
    });

    test('get nothing when the others take it all', () {
      final v = View(10, 1);
      final x = Fill('x');
      final row = RenderFlex(children: [Label('abcdefghij'), x]);
      flexible(x, 1);
      expect(v.show(row), ['abcdefghij']);
      expect(x.got, const BoxConstraints(0, 0, 0, 1));
    });

    test('share what the constraints allow with MainAxisSize.min', () {
      final x = Fill('x');
      final row = RenderFlex(
        mainAxisSize: MainAxisSize.min,
        children: [Label('ab'), x],
      );
      flexible(x, 1);
      row.layout(const BoxConstraints(0, 10, 0, 1), parentUsesSize: true);
      expect(row.width, 10);
      expect(boxes(row), ['0,0 2x1', '2,0 8x1']);
    });

    test('are as long as they want along an unbounded main axis, the flex '
        'as long as its children whatever its MainAxisSize', () {
      final label = Label('abc');
      final sized = Sized(4, 1);
      final row = RenderFlex(gap: 1, children: [Label('ab'), label, sized]);
      flexible(label, 1);
      flexible(sized, 2, FlexFit.loose);
      row.layout(
        const BoxConstraints(0, BoxConstraints.unbounded, 0, 1),
        parentUsesSize: true,
      );
      expect([row.width, row.height], [11, 1]);
      expect(boxes(row), ['0,0 2x1', '3,0 3x1', '7,0 4x1']);
      row.layout(
        const BoxConstraints(12, BoxConstraints.unbounded, 0, 1),
        parentUsesSize: true,
      );
      expect(row.width, 12);
    });
  });

  group('children that do not fit', () {
    test('are cut off at the bounds of the flex', () {
      final v = View(10, 4);
      final column = RenderFlex(
        direction: Axis.vertical,
        children: [Label('a'), Label('b'), Label('c')],
      );
      // the column gets the two middle rows
      printed(() {
        v.show(RenderBox(pen: v.pen, padY: 1, child: column));
      });
      expect(v.rows(), ['', 'a', 'b', '']);
    });

    test('are reported once, in debug', () {
      final v = View(5, 1);
      final row = RenderFlex(gap: 1, children: [Label('ab')]);
      final lines = printed(() {
        v.show(row);
        row.add(Label('cd'));
        v.frame();
        row.add(Label('ef'));
        v.frame();
        row.add(Label('gh'));
        v.frame();
      });
      var asserts = false;
      assert(asserts = true, 'debug only');
      expect(lines, [
        if (asserts)
          endsWith(
            ' warning A RenderFlex overflowed by 3 columns on the right.',
          ),
      ]);
      expect(v.rows(), ['ab cd']);
    });

    test("are reported to the owner's log route where it has one", () {
      final v = View(4, 1);
      final records = <LogRecord>[];
      v.owner.onLog = records.add;
      final lines = printed(
        () => v.show(RenderFlex(gap: 1, children: [Label('ab'), Label('cd')])),
      );
      var asserts = false;
      assert(asserts = true, 'debug only');
      expect(lines, isEmpty);
      expect(
        [for (final r in records) (r.level, r.message)],
        [
          if (asserts)
            (
              LogLevel.warning,
              'A RenderFlex overflowed by 1 column on the right.',
            ),
        ],
      );
    });
  });

  group('intrinsic sizes', () {
    test('along the main axis: the inflexible children and the gaps, plus '
        'what gives each flexible child what it asks for', () {
      final a = Probe(minW: 2, maxW: 3);
      final b = Probe(minW: 3, maxW: 4);
      final c = Probe(minW: 2, maxW: 10);
      final row = RenderFlex(gap: 1, children: [a, b, c]);
      flexible(b, 1);
      flexible(c, 2);
      // b asks for 3 of 3 flex: 9 cells shared; c for 2 of 3
      expect(row.getMinIntrinsicWidth(5), 2 + 2 + 9);
      expect(row.getMaxIntrinsicWidth(5), 3 + 2 + 15);
      expect([a.asked[0], b.asked[0], c.asked[0]], [5, 5, 5]);
      expect([a.asked[1], b.asked[1], c.asked[1]], [5, 5, 5]);
    });

    test('along the main axis: enough for every flexible child', () {
      final a = Probe(minW: 3);
      final b = Probe(minW: 1);
      final row = RenderFlex(children: [a, b]);
      flexible(a, 2);
      flexible(b, 1);
      // 4.5 cells
      expect(row.getMinIntrinsicWidth(1), 5);
      row.layout(const BoxConstraints(0, 5, 0, 1), parentUsesSize: true);
      // 3.3 and 1.7, the leftover cell to the first
      expect([a.width, b.width], [4, 1]);
    });

    test('across the main axis: the thickest child at the extent it would '
        'get', () {
      final a = Probe(maxW: 3, minH: 2, maxH: 5);
      final b = Probe(minH: 4, maxH: 1);
      final c = Probe(minH: 1, maxH: 6);
      final row = RenderFlex(gap: 1, children: [a, b, c]);
      flexible(b, 1);
      flexible(c, 1);
      expect(row.getMinIntrinsicHeight(10), 4);
      expect(row.getMaxIntrinsicHeight(10), 6);
      // a as wide as it wants; b and c share the 5 columns left
      expect([a.asked[2], b.asked[2], c.asked[2]], [3, 3, 2]);
      expect([a.asked[3], b.asked[3], c.asked[3]], [3, 3, 2]);
    });

    test('across the main axis: an inflexible child no longer than the '
        'flex', () {
      final a = Probe(maxW: 30, minH: 2);
      final row = RenderFlex(children: [a]);
      expect(row.getMinIntrinsicHeight(10), 2);
      expect(a.asked[2], 10);
    });

    test('of a column', () {
      final a = Probe(minW: 5, minH: 2, maxH: 2);
      final b = Probe(minW: 7, minH: 3);
      final column = RenderFlex(
        direction: Axis.vertical,
        gap: 1,
        children: [a, b],
      );
      flexible(b, 1);
      expect(column.getMinIntrinsicHeight(8), 2 + 1 + 3);
      expect([a.asked[2], b.asked[2]], [8, 8]);
      expect(column.getMinIntrinsicWidth(10), 7);
      expect([a.asked[0], b.asked[0]], [2, 7]);
    });
  });

  test('a child whose size the flex uses lays the flex out again', () {
    final v = View(10, 1);
    final [a, b] = [Label('ab'), Label('cd')];
    expect(v.show(RenderFlex(children: [a, b])), ['abcd']);
    a.text = 'abx';
    v.frame();
    expect(v.rows(), ['abxcd']);
    // the same constraints: b has nothing to do
    expect([a.layouts, b.layouts], [2, 1]);
  });

  test('a new setting lays the flex out again', () {
    final v = View(6, 3);
    final flex = RenderFlex(children: [Label('a'), Label('b')]);
    // in a box that lets it be smaller than the screen
    v.show(RenderBox(pen: v.pen, child: flex));
    expect(boxes(flex), ['0,0 1x1', '1,0 1x1']);
    flex.gap = 1;
    v.frame();
    expect(boxes(flex), ['0,0 1x1', '2,0 1x1']);
    flex.mainAxisAlignment = MainAxisAlignment.end;
    v.frame();
    expect(boxes(flex), ['3,0 1x1', '5,0 1x1']);
    flex.crossAxisAlignment = CrossAxisAlignment.stretch;
    v.frame();
    expect(boxes(flex), ['3,0 1x3', '5,0 1x3']);
    flex.direction = Axis.vertical;
    v.frame();
    expect(boxes(flex), ['0,0 6x1', '0,2 6x1']);
    flex.gap = 0;
    v.frame();
    expect(boxes(flex), ['0,1 6x1', '0,2 6x1']);
    flex.mainAxisSize = MainAxisSize.min;
    v.frame();
    expect(boxes(flex), ['0,0 6x1', '0,1 6x1']);
    expect(v.rows(), ['a', 'b', '']);
    expect(
      [
        flex.direction,
        flex.mainAxisSize,
        flex.mainAxisAlignment,
        flex.crossAxisAlignment,
        flex.gap,
      ],
      [
        Axis.vertical,
        MainAxisSize.min,
        MainAxisAlignment.end,
        CrossAxisAlignment.stretch,
        0,
      ],
    );
  });

  test('flexible children of a column share the rows the fixed ones '
      'leave', () {
    final v = View(4, 5);
    final column = RenderColumn([
      (Label('a'), 1),
      (Fill('x'), null),
      (Fill('y'), null),
    ]);
    expect(v.show(column), ['a', 'xxxx', 'xxxx', 'yyyy', 'yyyy']);
  });

  test('a flexible child that would show something, left no cells by the '
      'others, is reported once, in debug; one that asks for none, as a '
      'Spacer, is not', () {
    final v = View(4, 1);
    final records = <LogRecord>[];
    v.owner.onLog = records.add;
    final wants = Probe(maxW: 2);
    final spacer = Probe();
    final row = RenderFlex(children: [Label('abcd'), spacer, wants]);
    flexible(wants, 1);
    flexible(spacer, 1);
    v.show(row);
    row.markNeedsLayout();
    v.frame();
    var asserts = false;
    assert(asserts = true, 'debug only');
    expect(
      [for (final r in records) (r.level, r.message)],
      [
        if (asserts)
          (
            LogLevel.warning,
            'A RenderFlex gave a flexible child, a Probe, 0 columns of its 4, '
                'which the inflexible children took: it shows nothing of the 2 '
                'columns it would. Give those children less, or the flexible '
                'one a size.',
          ),
      ],
    );
    expect(v.rows(), ['abcd']);
  });
}
