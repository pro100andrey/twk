// Boxes with one child: padding around it, an alignment that places it,
// limits on its size, fractions of the room it gets and the size it would
// like to be; each asks for what its child asks for, adjusted.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// A render tree filling a whole screen.
final class View {
  View(this.width, this.height) : screen = Screen(width, height) {
    owner = PipelineOwner(() {});
  }

  final int width;
  final int height;
  final Screen screen;
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

/// [text] in a box of [w] × [h], whatever the constraints say; keeps the
/// constraints it was last laid out with and counts its layouts.
final class Stubborn extends RenderObject {
  Stubborn(this._text, this.w, this.h);

  String _text;
  String get text => _text;
  final int w;
  final int h;
  BoxConstraints? got;
  var layouts = 0;

  set text(String t) {
    _text = t;
    markNeedsLayout();
  }

  @override
  void performLayout(BoxConstraints c) {
    layouts++;
    got = c;
    width = w;
    height = h;
  }

  @override
  void paint(PaintContext ctx) {
    final pen = ctx.canvas.styles.pen(const Pen());
    for (var y = 0; y < h; y++) {
      ctx.canvas.text(0, y, _text, pen);
    }
  }
}

/// One line of [text] (one column per character), as wide as the text
/// within the constraints; keeps the constraints it was last laid out with.
final class Label extends RenderObject {
  Label(this._text);

  String _text;
  BoxConstraints? got;

  String get text => _text;
  set text(String t) {
    _text = t;
    markNeedsLayout();
  }

  @override
  void performLayout(BoxConstraints c) {
    got = c;
    width = c.constrainW(_text.length);
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) =>
      ctx.canvas.text(0, 0, _text, ctx.canvas.styles.pen(const Pen()));
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
}

/// Asks for [minW], [maxW], [minH] and [maxH] at any extent; keeps the
/// extent it was last asked at for each (-1: never).
final class Probe extends RenderObject {
  Probe({this.minW = 0, this.maxW = 0, this.minH = 0, this.maxH = 0});

  final int minW;
  final int maxW;
  final int minH;
  final int maxH;

  /// The extent last asked at: min width, max width, min height, max
  /// height.
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

/// Lays [child] out with no minimum, one column narrower than itself, as a
/// parent that uses the child's size, and draws a bar right after it.
/// Counts its layouts.
final class Hug extends RenderObject {
  Hug(this.child) {
    adopt(child);
  }

  final RenderObject child;
  var layouts = 0;

  @override
  void visitChildren(void Function(RenderObject) visit) => visit(child);

  @override
  void performLayout(BoxConstraints c) {
    layouts++;
    width = c.maxW;
    height = c.maxH;
    child.layout(
      BoxConstraints(0, c.maxW - 1, 0, c.maxH),
      parentUsesSize: true,
    );
  }

  @override
  void paint(PaintContext ctx) {
    paintChild(ctx, child);
    ctx.canvas.text(child.width, 0, '|', ctx.canvas.styles.pen(const Pen()));
  }
}

/// [child] laid out with any width, its own height at most, and a bar
/// painted after it; counts its layouts, as a row's main axis and a
/// horizontal scroll view lay a child out.
final class Unbounded extends RenderObject {
  Unbounded(this.child) {
    adopt(child);
  }

  final RenderObject child;
  var layouts = 0;

  @override
  void visitChildren(void Function(RenderObject) visit) => visit(child);

  @override
  void performLayout(BoxConstraints c) {
    layouts++;
    width = c.maxW;
    height = c.maxH;
    child.layout(
      BoxConstraints(0, BoxConstraints.unbounded, 0, c.maxH),
      parentUsesSize: true,
    );
  }

  @override
  void paint(PaintContext ctx) {
    paintChild(ctx, child);
    ctx.canvas.text(child.width, 0, '|', ctx.canvas.styles.pen(const Pen()));
  }
}

/// One column wide, asking to be [rows] tall; fills the height it gets
/// with [char], [rows] at most unless the height is tight.
final class Tall extends RenderObject {
  Tall(this.char, this.rows);

  final String char;
  final int rows;

  @override
  int computeMinIntrinsicWidth(int height) => 1;

  @override
  int computeMaxIntrinsicWidth(int height) => 1;

  @override
  int computeMinIntrinsicHeight(int width) => rows;

  @override
  int computeMaxIntrinsicHeight(int width) => rows;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(1);
    height = c.constrainH(rows);
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

/// Lays [o] out within [c] as a parent that uses its size; returns
/// `x,y wxh` of its child.
String layOut(RenderObject o, BoxConstraints c) {
  o.layout(c, parentUsesSize: true);
  RenderObject? child;
  o.visitChildren((c) => child = c);
  final at = child!.parentData;
  return '${at.dx},${at.dy} ${child!.width}x${child!.height}';
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
  group('EdgeInsets', () {
    test('are the cells on each side', () {
      const insets = EdgeInsets.only(left: 1, top: 2, right: 3, bottom: 4);
      expect(
        [insets.left, insets.top, insets.right, insets.bottom],
        [1, 2, 3, 4],
      );
      expect([insets.horizontal, insets.vertical], [4, 6]);
    });

    test('are made for every side, the sides or the top and bottom', () {
      expect(
        const EdgeInsets.all(2),
        const EdgeInsets.only(left: 2, top: 2, right: 2, bottom: 2),
      );
      expect(const EdgeInsets.x(2), const EdgeInsets.only(left: 2, right: 2));
      expect(const EdgeInsets.y(2), const EdgeInsets.only(top: 2, bottom: 2));
      expect([EdgeInsets.zero.horizontal, EdgeInsets.zero.vertical], [0, 0]);
      expect(const EdgeInsets.x(1), isNot(const EdgeInsets.y(1)));
      expect(const EdgeInsets.x(1).hashCode, const EdgeInsets.x(1).hashCode);
    });
  });

  group('RenderPadding', () {
    test('lays its child out inside the padding', () {
      final label = Label('ab');
      final padding = RenderPadding(
        padding: const EdgeInsets.only(left: 2, top: 1, right: 3, bottom: 1),
        child: label,
      );
      expect(layOut(padding, const BoxConstraints(0, 10, 0, 5)), '2,1 2x1');
      expect(label.got, const BoxConstraints(0, 5, 0, 3));
      // as big as the child and the padding
      expect([padding.width, padding.height], [7, 3]);
    });

    test('is as big as its constraints ask for at least', () {
      final label = Label('ab');
      final padding = RenderPadding(
        padding: const EdgeInsets.all(1),
        child: label,
      );
      expect(layOut(padding, const BoxConstraints(6, 10, 4, 5)), '1,1 4x2');
      expect(label.got, const BoxConstraints(4, 8, 2, 3));
      expect([padding.width, padding.height], [6, 4]);
    });

    test('leaves its child no room when the padding takes it all', () {
      final label = Label('ab');
      final padding = RenderPadding(
        padding: const EdgeInsets.x(3),
        child: label,
      );
      expect(layOut(padding, const BoxConstraints(2, 5, 0, 1)), '3,0 0x1');
      expect(label.got, const BoxConstraints(0, 0, 0, 1));
      expect([padding.width, padding.height], [5, 1]);
    });

    test('without a child is as big as the padding', () {
      final padding = RenderPadding(padding: const EdgeInsets.all(2))
        ..layout(const BoxConstraints(0, 10, 0, 3), parentUsesSize: true);
      expect([padding.width, padding.height], [4, 3]);
    });

    test('paints its child inside the padding', () {
      final v = View(5, 4);
      final root = RenderPadding(
        padding: const EdgeInsets.only(left: 1, top: 1, right: 2),
        child: Fill('x'),
      );
      expect(v.show(root), ['', ' xx', ' xx', ' xx']);
    });

    test('a new padding lays it out again', () {
      final v = View(5, 3);
      final root = RenderPadding(
        padding: const EdgeInsets.all(1),
        child: Fill('x'),
      );
      expect(v.show(root), ['', ' xxx', '']);
      root.padding = const EdgeInsets.y(1);
      v.frame();
      expect(root.padding, const EdgeInsets.y(1));
      expect(v.rows(), ['', 'xxxxx', '']);
    });

    test('adds the padding to what its child asks for at the extent '
        'inside it', () {
      final child = Probe(minW: 3, maxW: 7, minH: 1, maxH: 2);
      final padding = RenderPadding(
        padding: const EdgeInsets.only(left: 1, top: 2, right: 3, bottom: 4),
        child: child,
      );
      expect(intrinsics(padding, 10), [7, 11, 7, 8]);
      expect(child.asked, [4, 4, 6, 6]);
      // at least 0
      expect(intrinsics(padding, 3), [7, 11, 7, 8]);
      expect(child.asked, [0, 0, 0, 0]);
      expect(
        intrinsics(RenderPadding(padding: const EdgeInsets.x(2)), 5),
        [4, 4, 0, 0],
      );
    });
  });

  group('Alignment', () {
    test('puts a child at the start, in the middle or at the end', () {
      expect(
        [
          for (final x in [-1, 0, 1]) Alignment(x, 0).dx(4),
        ],
        [0, 2, 4],
      );
      expect(
        [
          for (final y in [-1, 0, 1]) Alignment(0, y).dy(4),
        ],
        [0, 2, 4],
      );
    });

    test('in the middle, puts the odd cell after the child', () {
      expect([Alignment.center.dx(5), Alignment.center.dy(5)], [2, 2]);
      // a child 5 cells longer sticks out 2 cells before, 3 after
      expect([Alignment.center.dx(-5), Alignment.center.dy(-5)], [-2, -2]);
      expect([Alignment.topLeft.dx(-5), Alignment.bottomRight.dy(-5)], [0, -5]);
    });

    test('has a name for each of the nine places', () {
      expect(
        [
          Alignment.topLeft,
          Alignment.topCenter,
          Alignment.topRight,
          Alignment.centerLeft,
          Alignment.center,
          Alignment.centerRight,
          Alignment.bottomLeft,
          Alignment.bottomCenter,
          Alignment.bottomRight,
        ],
        [
          for (final y in [-1, 0, 1])
            for (final x in [-1, 0, 1]) Alignment(x, y),
        ],
      );
    });
  });

  group('RenderPositionedBox', () {
    test('places its child as its alignment says, the odd cell after it '
        'in the middle', () {
      // a 2x1 child in 7x4 and in 8x5: 5x3 and 6x4 cells free
      final want = <Alignment, List<String>>{
        Alignment.topLeft: ['0,0', '0,0'],
        Alignment.topCenter: ['2,0', '3,0'],
        Alignment.topRight: ['5,0', '6,0'],
        Alignment.centerLeft: ['0,1', '0,2'],
        Alignment.center: ['2,1', '3,2'],
        Alignment.centerRight: ['5,1', '6,2'],
        Alignment.bottomLeft: ['0,3', '0,4'],
        Alignment.bottomCenter: ['2,3', '3,4'],
        Alignment.bottomRight: ['5,3', '6,4'],
      };
      for (final MapEntry(key: alignment, value: at) in want.entries) {
        for (final (i, (w, h)) in [(7, 4), (8, 5)].indexed) {
          final box = RenderPositionedBox(
            alignment: alignment,
            child: Label('ab'),
          );
          expect(
            layOut(box, BoxConstraints(0, w, 0, h)),
            '${at[i]} 2x1',
            reason: '$w x $h, ${alignment.x} ${alignment.y}',
          );
          expect([box.width, box.height], [w, h]);
        }
      }
    });

    test('lays its child out with no minimum', () {
      final fill = Fill('x');
      RenderPositionedBox(
        child: fill,
      ).layout(const BoxConstraints(4, 8, 2, 3), parentUsesSize: true);
      expect(fill.got, const BoxConstraints(0, 8, 0, 3));
    });

    test('centres its child by default', () {
      final v = View(7, 3);
      expect(v.show(RenderPositionedBox(child: Label('abc'))), [
        '',
        '  abc',
        '',
      ]);
    });

    test('is its factor times as long as its child along an axis with '
        'one', () {
      final box = RenderPositionedBox(widthFactor: 2, child: Label('ab'));
      expect(layOut(box, const BoxConstraints(0, 10, 0, 5)), '1,2 2x1');
      expect([box.width, box.height], [4, 5]);
      box
        ..widthFactor = null
        ..heightFactor = 3;
      expect(layOut(box, const BoxConstraints(0, 10, 0, 5)), '4,1 2x1');
      expect([box.width, box.height], [10, 3]);
      // within the constraints
      box
        ..widthFactor = 6
        ..heightFactor = 0;
      expect(layOut(box, const BoxConstraints(0, 10, 2, 5)), '4,0 2x1');
      expect([box.width, box.height], [10, 2]);
      expect([box.widthFactor, box.heightFactor], [6, 0]);
    });

    test('without a child is as long as the constraints allow, or as short '
        'along an axis with a factor', () {
      const c = BoxConstraints(1, 10, 2, 5);
      final box = RenderPositionedBox(heightFactor: 2)
        ..layout(c, parentUsesSize: true);
      expect([box.width, box.height], [10, 2]);
      box
        ..heightFactor = null
        ..widthFactor = 3
        ..layout(c, parentUsesSize: true);
      expect([box.width, box.height], [1, 5]);
    });

    test('a new alignment places the child again', () {
      final v = View(5, 1);
      final box = RenderPositionedBox(child: Label('ab'));
      expect(v.show(box), [' ab']);
      box.alignment = Alignment.centerRight;
      v.frame();
      expect(box.alignment, Alignment.centerRight);
      expect(v.rows(), ['   ab']);
    });

    test('cuts off a child that sticks out of it', () {
      final v = View(9, 3);
      final child = Stubborn('abcdefg', 7, 3);
      final box = RenderPositionedBox(child: child);
      // three columns and one row in the middle of the screen
      final root = RenderPadding(
        padding: const EdgeInsets.only(left: 3, top: 1, right: 3, bottom: 1),
        child: box,
      );
      expect(v.show(root), ['', '   cde', '']);
      expect(child.parentData.dx, -2);
      box.alignment = Alignment.topLeft;
      v.frame();
      expect(v.rows(), ['', '   abc', '']);
    });

    test('is a relayout boundary unless a factor makes it as big as its '
        'child', () {
      final v = View(10, 1);
      final label = Label('ab');
      final box = RenderPositionedBox(
        alignment: Alignment.centerLeft,
        child: label,
      );
      final hug = Hug(box);
      expect(v.show(hug), ['ab       |']);
      label.text = 'abc';
      v.frame();
      expect(v.rows(), ['abc      |']);
      expect(hug.layouts, 1);
      // as wide as its child: the parent lays the bar out after it again
      box.widthFactor = 1;
      v.frame();
      expect(v.rows(), ['abc|']);
      expect(hug.layouts, 2);
      label.text = 'ab';
      v.frame();
      expect(v.rows(), ['ab|']);
      expect(hug.layouts, 3);
    });

    test('along an axis of any length it is as long as its child, through '
        'a padding too, and without one as short as the constraints '
        'allow', () {
      const any = BoxConstraints.unbounded;
      final box = RenderPositionedBox(child: Label('ab'))
        ..layout(const BoxConstraints(0, 10, 0, any), parentUsesSize: true);
      expect([box.width, box.height], [10, 1]);
      box.layout(const BoxConstraints(0, any, 0, 3), parentUsesSize: true);
      expect([box.width, box.height], [2, 3]);
      final padded = RenderPadding(
        padding: const EdgeInsets.all(1),
        child: RenderPositionedBox(child: Label('ab')),
      )..layout(const BoxConstraints(0, 10, 0, any), parentUsesSize: true);
      expect([padded.width, padded.height], [10, 3]);
      final empty = RenderPositionedBox()
        ..layout(const BoxConstraints(0, any, 2, any), parentUsesSize: true);
      expect([empty.width, empty.height], [0, 2]);
    });

    test('along an axis of any length it is no relayout boundary: a child '
        'that grows grows it, and the parent lays out after it', () {
      final v = View(10, 1);
      final label = Label('ab');
      final parent = Unbounded(
        RenderPositionedBox(alignment: Alignment.centerLeft, child: label),
      );
      expect(v.show(parent), ['ab|']);
      label.text = 'abcd';
      v.frame();
      expect(v.rows(), ['abcd|']);
      expect(parent.layouts, 2);
    });

    test('asks for what its child asks for, times its factors', () {
      final child = Probe(minW: 3, maxW: 7, minH: 1, maxH: 2);
      final box = RenderPositionedBox(child: child);
      expect(intrinsics(box, 10), [3, 7, 1, 2]);
      expect(child.asked, [10, 10, 10, 10]);
      box
        ..widthFactor = 2
        ..heightFactor = 3;
      expect(intrinsics(box, 10), [6, 14, 3, 6]);
      expect(intrinsics(RenderPositionedBox(), 5), [0, 0, 0, 0]);
    });
  });

  group('RenderConstrainedBox', () {
    test('lays its child out within both its constraints and the '
        'additional ones', () {
      final label = Label('abcdefgh');
      final box = RenderConstrainedBox(
        additionalConstraints: const BoxConstraints(2, 6, 1, 1 << 30),
        child: label,
      );
      expect(layOut(box, const BoxConstraints(0, 10, 0, 5)), '0,0 6x1');
      expect(label.got, const BoxConstraints(2, 6, 1, 5));
      expect([box.width, box.height], [6, 1]);
      // additional constraints beyond its own are brought within them
      box.additionalConstraints = const BoxConstraints(12, 20, 0, 3);
      expect(layOut(box, const BoxConstraints(0, 10, 2, 5)), '0,0 10x2');
      expect(label.got, const BoxConstraints(10, 10, 2, 3));
      expect(box.additionalConstraints, const BoxConstraints(12, 20, 0, 3));
    });

    test('without a child is as small as both allow', () {
      final box = RenderConstrainedBox(
        additionalConstraints: const BoxConstraints.tightFor(width: 4),
      )..layout(const BoxConstraints(0, 10, 1, 5), parentUsesSize: true);
      expect([box.width, box.height], [4, 1]);
    });

    test('with unbounded tight constraints fills its own', () {
      final fill = Fill('x');
      final box = RenderConstrainedBox(
        additionalConstraints: const BoxConstraints.tightFor(
          width: BoxConstraints.unbounded,
          height: BoxConstraints.unbounded,
        ),
        child: fill,
      )..layout(const BoxConstraints(0, 10, 0, 5), parentUsesSize: true);
      expect(fill.got, const BoxConstraints.tight(10, 5));
      expect([box.width, box.height], [10, 5]);
    });

    test('new additional constraints lay its parent out again', () {
      final v = View(10, 1);
      final box = RenderConstrainedBox(
        additionalConstraints: const BoxConstraints.tight(4, 1),
        child: Label('ab'),
      );
      final hug = Hug(box);
      expect(v.show(hug), ['ab  |']);
      box.additionalConstraints = const BoxConstraints.tight(6, 1);
      v.frame();
      expect(v.rows(), ['ab    |']);
      expect(hug.layouts, 2);
    });

    test('asks for what its child asks for within the additional '
        'constraints', () {
      final child = Probe(minW: 3, maxW: 7, minH: 1, maxH: 2);
      final box = RenderConstrainedBox(
        additionalConstraints: const BoxConstraints(4, 6, 0, 1 << 30),
        child: child,
      );
      expect(intrinsics(box, 10), [4, 6, 1, 2]);
      expect(child.asked, [10, 10, 10, 10]);
    });

    test('asks for a tight extent without asking its child', () {
      final child = Probe(minW: 3, maxW: 7, minH: 1, maxH: 2);
      final box = RenderConstrainedBox(
        additionalConstraints: const BoxConstraints.tightFor(width: 5),
        child: child,
      );
      expect(intrinsics(box, 10), [5, 5, 1, 2]);
      expect(child.asked, [-1, -1, 10, 10]);
      final other = Probe(minW: 3, maxW: 7, minH: 1, maxH: 2);
      final box2 = RenderConstrainedBox(
        additionalConstraints: const BoxConstraints.tightFor(height: 4),
        child: other,
      );
      expect(intrinsics(box2, 10), [3, 7, 4, 4]);
      expect(other.asked, [10, 10, -1, -1]);
    });

    test('with an unbounded minimum asks for what its child asks for', () {
      final child = Probe(minW: 3, maxW: 7, minH: 1, maxH: 2);
      final box = RenderConstrainedBox(
        additionalConstraints: const BoxConstraints.tightFor(
          width: BoxConstraints.unbounded,
          height: BoxConstraints.unbounded,
        ),
        child: child,
      );
      expect(intrinsics(box, 10), [3, 7, 1, 2]);
      expect(
        intrinsics(
          RenderConstrainedBox(
            additionalConstraints: const BoxConstraints(2, 3, 1, 4),
          ),
          5,
        ),
        [2, 2, 1, 1],
      );
    });
  });

  group('RenderFractionallySizedBox', () {
    test('lays its child out at fractions of its max extents, as big as '
        'it may be', () {
      final fill = Fill('x');
      final box = RenderFractionallySizedBox(
        widthFactor: 0.5,
        heightFactor: 1 / 3,
        child: fill,
      );
      expect(layOut(box, const BoxConstraints(0, 10, 0, 7)), '2,2 5x2');
      expect(fill.got, const BoxConstraints.tight(5, 2));
      expect([box.width, box.height], [10, 7]);
    });

    test('rounds a fraction to the nearest cell, a half up', () {
      // extent, factor, cells
      const cases = [
        (5, 0.5, 3),
        (7, 0.5, 4),
        (10, 0.25, 3),
        (10, 1 / 3, 3),
        (10, 2 / 3, 7),
        (100, 0.29, 29),
        (100, 0.57, 57),
        (3, 0.1, 0),
        (4, 0.0, 0),
        (4, 1.0, 4),
      ];
      for (final (extent, factor, cells) in cases) {
        final fill = Fill('x');
        RenderFractionallySizedBox(widthFactor: factor, child: fill).layout(
          BoxConstraints(0, extent, 0, 1),
          parentUsesSize: true,
        );
        expect(fill.got!.maxW, cells, reason: '$factor of $extent');
      }
    });

    test('along an axis without a factor lays its child out within its '
        'constraints', () {
      final fill = Fill('x');
      final box = RenderFractionallySizedBox(widthFactor: 0.5, child: fill);
      expect(layOut(box, const BoxConstraints(0, 10, 2, 6)), '2,0 5x6');
      expect(fill.got, const BoxConstraints(5, 5, 2, 6));
    });

    test('along an unbounded axis is as long as its child, whatever the '
        'factor', () {
      final label = Label('ab');
      final box = RenderFractionallySizedBox(
        widthFactor: 0.5,
        heightFactor: 0.5,
        alignment: Alignment.topLeft,
        child: label,
      );
      expect(
        layOut(box, const BoxConstraints(0, 10, 0, BoxConstraints.unbounded)),
        '0,0 5x1',
      );
      expect(
        label.got,
        const BoxConstraints(5, 5, 0, BoxConstraints.unbounded),
      );
      expect([box.width, box.height], [10, 1]);
    });

    test('without a child is as big as it may be, as short as it may be '
        'along an unbounded axis', () {
      final box = RenderFractionallySizedBox(widthFactor: 0.5)
        ..layout(
          const BoxConstraints(0, 10, 1, BoxConstraints.unbounded),
          parentUsesSize: true,
        );
      expect([box.width, box.height], [10, 1]);
    });

    test('cuts off a child a factor above 1 makes bigger than itself', () {
      final v = View(4, 2);
      final box = RenderFractionallySizedBox(
        widthFactor: 2,
        heightFactor: 0.5,
        alignment: Alignment.topRight,
        child: Label('abcdefgh'),
      );
      expect(v.show(box), ['efgh', '']);
      expect(layOut(box, const BoxConstraints.tight(4, 2)), '-4,0 8x1');
    });

    test('new factors or a new alignment lay it out again', () {
      final v = View(8, 1);
      final box = RenderFractionallySizedBox(
        widthFactor: 0.5,
        alignment: Alignment.centerLeft,
        child: Fill('x'),
      );
      expect(v.show(box), ['xxxx']);
      box.widthFactor = 0.25;
      v.frame();
      expect(v.rows(), ['xx']);
      box.alignment = Alignment.centerRight;
      v.frame();
      expect(v.rows(), ['      xx']);
      box.widthFactor = null;
      v.frame();
      expect(v.rows(), ['xxxxxxxx']);
    });

    test('asks for the extent whose fraction is what its child asks for at '
        'its fraction of the other', () {
      final child = Probe(minW: 3, maxW: 7, minH: 1, maxH: 2);
      final box = RenderFractionallySizedBox(
        widthFactor: 0.5,
        heightFactor: 0.25,
        child: child,
      );
      expect(intrinsics(box, 10), [5, 13, 2, 6]);
      expect(child.asked, [3, 3, 5, 5]);
      // which is what the child then gets: 13 columns give it 7
      final fill = Fill('x');
      RenderFractionallySizedBox(widthFactor: 0.5, child: fill).layout(
        const BoxConstraints(0, 13, 0, 1),
        parentUsesSize: true,
      );
      expect(fill.got!.maxW, 7);
      // no fraction of any extent gives the child anything
      expect(
        intrinsics(
          RenderFractionallySizedBox(
            widthFactor: 0,
            heightFactor: 0,
            child: Probe(minW: 3, maxW: 7, minH: 1, maxH: 2),
          ),
          10,
        ),
        [0, 0, 0, 0],
      );
      final free = Probe(minW: 3, maxW: 7, minH: 1, maxH: 2);
      expect(
        intrinsics(RenderFractionallySizedBox(child: free), 10),
        [3, 7, 1, 2],
      );
      expect(intrinsics(RenderFractionallySizedBox(), 10), [0, 0, 0, 0]);
    });

    test('asks for the fewest cells whose fraction, rounded, is what its '
        'child asks for, where a product in floating point rounds the other '
        'way', () {
      final box = RenderFractionallySizedBox(
        widthFactor: 0.7,
        child: Probe(minW: 11, maxW: 32),
      );
      // 15 × 0.7 is 10.5, rounded up to 11; 45 × 0.7 is 31.499…
      expect(box.getMinIntrinsicWidth(1), 15);
      expect(box.getMaxIntrinsicWidth(1), 46);
      final fill = Fill('x');
      RenderFractionallySizedBox(widthFactor: 0.7, child: fill).layout(
        const BoxConstraints(0, 15, 0, 1),
        parentUsesSize: true,
      );
      expect(fill.got!.maxW, 11);
    });

    test('a new height factor lays it out again; the factors and the '
        'alignment read back as set', () {
      final v = View(1, 8);
      final box = RenderFractionallySizedBox(
        heightFactor: 0.5,
        alignment: Alignment.topCenter,
        child: Fill('x'),
      );
      expect(v.show(box), [...List.filled(4, 'x'), '', '', '', '']);
      box.heightFactor = 0.25;
      v.frame();
      expect(v.rows(), ['x', 'x', '', '', '', '', '', '']);
      expect(
        (box.widthFactor, box.heightFactor, box.alignment),
        (null, 0.25, Alignment.topCenter),
      );
    });
  });

  group('RenderIntrinsicWidth', () {
    test('makes its child as wide as it would like to be at its most '
        'height', () {
      final child = Probe(maxW: 4);
      final box = RenderIntrinsicWidth(child: child);
      expect(layOut(box, const BoxConstraints(0, 10, 0, 5)), '0,0 4x5');
      expect(child.asked[1], 5);
      expect([box.width, box.height], [4, 5]);
    });

    test('within its constraints; a tight width stays as it is', () {
      final child = Probe(maxW: 4);
      final box = RenderIntrinsicWidth(child: child);
      expect(layOut(box, const BoxConstraints(6, 10, 0, 5)), '0,0 6x5');
      final other = Probe(maxW: 4);
      final tight = RenderIntrinsicWidth(child: other);
      expect(layOut(tight, const BoxConstraints(8, 8, 0, 5)), '0,0 8x5');
      expect(other.asked, [-1, -1, -1, -1]);
    });

    test('rounds what its child would like up to its steps', () {
      final child = Probe(maxW: 4, maxH: 3);
      final box = RenderIntrinsicWidth(
        stepWidth: 3,
        stepHeight: 2,
        child: child,
      );
      expect(layOut(box, const BoxConstraints(0, 10, 0, 8)), '0,0 6x4');
      // the height at the width it gets
      expect(child.asked, [-1, 8, -1, 6]);
    });

    test('asks for what its child would like, rounded up to its steps', () {
      final child = Probe(minW: 2, maxW: 4, minH: 1, maxH: 3);
      final box = RenderIntrinsicWidth(
        stepWidth: 3,
        stepHeight: 2,
        child: child,
      );
      expect(intrinsics(box, 10), [6, 6, 2, 4]);
      expect(child.asked, [-1, 10, 10, 10]);
      // at an unbounded width, the heights at the width it would like
      box.getMinIntrinsicHeight(BoxConstraints.unbounded);
      expect(child.asked[2], 6);
      expect(intrinsics(RenderIntrinsicWidth(), 10), [0, 0, 0, 0]);
    });

    test('without a child is as small as the constraints allow', () {
      final box = RenderIntrinsicWidth(stepWidth: 2)
        ..layout(const BoxConstraints(1, 10, 2, 5), parentUsesSize: true);
      expect([box.width, box.height], [1, 2]);
    });

    test('new steps lay it out again', () {
      final v = View(10, 1);
      final box = RenderIntrinsicWidth(child: Tall('x', 1));
      final hug = Hug(box);
      expect(v.show(hug), ['x|']);
      box.stepWidth = 4;
      v.frame();
      expect(v.rows(), ['xxxx|']);
      expect(hug.layouts, 2);
    });

    test('a new height step lays it out again', () {
      final v = View(3, 6);
      final box = RenderIntrinsicWidth(child: Tall('x', 1));
      expect(v.show(Hug(box)), ['x|', '', '', '', '', '']);
      box.stepHeight = 3;
      v.frame();
      expect(v.rows(), ['x|', 'x', 'x', '', '', '']);
      expect((box.stepWidth, box.stepHeight), (null, 3));
    });
  });

  group('RenderIntrinsicHeight', () {
    test('makes its child as tall as it would like to be at its most '
        'width', () {
      final child = Probe(maxH: 3);
      final box = RenderIntrinsicHeight(child: child);
      expect(layOut(box, const BoxConstraints(0, 10, 0, 8)), '0,0 10x3');
      expect(child.asked[3], 10);
      expect([box.width, box.height], [10, 3]);
      final other = Probe(maxH: 3);
      expect(
        layOut(
          RenderIntrinsicHeight(child: other),
          const BoxConstraints(0, 10, 5, 5),
        ),
        '0,0 10x5',
      );
      expect(other.asked, [-1, -1, -1, -1]);
    });

    test('makes a row whose children stretch across it as tall as its '
        'tallest child', () {
      final v = View(4, 5);
      RenderFlex row() => RenderFlex(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [Tall('a', 1), Tall('b', 3), Tall('c', 2)],
      );
      RenderObject top(RenderObject child) =>
          RenderPositionedBox(alignment: Alignment.topLeft, child: child);
      expect(v.show(top(RenderIntrinsicHeight(child: row()))), [
        'abc',
        'abc',
        'abc',
        '',
        '',
      ]);
      expect(v.show(top(row())), ['abc', 'abc', 'abc', 'abc', 'abc']);
    });

    test('asks for what its child would like at the height it would like', () {
      final child = Probe(minW: 2, maxW: 4, minH: 1, maxH: 3);
      final box = RenderIntrinsicHeight(child: child);
      expect(intrinsics(box, 10), [2, 4, 3, 3]);
      expect(child.asked, [10, 10, -1, 10]);
      box.getMaxIntrinsicWidth(BoxConstraints.unbounded);
      expect(child.asked[1], 3);
      expect(intrinsics(RenderIntrinsicHeight(), 10), [0, 0, 0, 0]);
    });

    test('without a child is as small as the constraints allow', () {
      final box = RenderIntrinsicHeight()
        ..layout(const BoxConstraints(1, 10, 2, 5), parentUsesSize: true);
      expect([box.width, box.height], [1, 2]);
    });
  });

  test('a box laid out again within the same constraints gives its child '
      'the same constraints object', () {
    final v = View(10, 5);
    final a = Stubborn('a', 1, 1);
    final b = Stubborn('b', 1, 1);
    final c = Label('c');
    final boxes = [
      RenderPadding(padding: const EdgeInsets.all(1), child: a),
      RenderPositionedBox(widthFactor: 1, heightFactor: 1, child: b),
      RenderConstrainedBox(
        additionalConstraints: const BoxConstraints(0, 5, 0, 1),
        child: c,
      ),
    ];
    final column = RenderFlex(
      direction: Axis.vertical,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: boxes,
    );
    v.show(column);
    final got = [a.got, b.got, c.got];
    a.text = 'x';
    b.text = 'y';
    c.text = 'z';
    v.frame();
    expect(v.rows(), ['', ' x', '', 'y', 'z']);
    expect([a.got, b.got, c.got], [same(got[0]), same(got[1]), same(got[2])]);
    expect([a.layouts, b.layouts], [2, 2]);
  });
}
