// A hit test finds the render objects at a cell from the root down: each
// child in its own coordinates and cut off at its parent's bounds as paint
// cuts it, the one painted on top first, each object opaque, translucent
// or deferring to its children, into a result reused between events.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// A tree laid out on a screen of [width] × [height] cells, the errors its
/// objects throw kept in [errors].
final class View {
  View(this.width, this.height, RenderObject root) {
    owner = PipelineOwner(() {})
      ..onError = (_, _, error, _) {
        errors.add('$error');
      }
      ..root = root
      ..flushLayout(width, height);
  }

  final int width;
  final int height;
  late final PipelineOwner owner;
  final errors = <String>[];
  final result = HitTestResult();

  /// What the tree has at [x], [y]: each object hit, the deepest first, as
  /// its name and the cell in its own coordinates.
  List<String> at(int x, int y) {
    owner.hitTest(result, x, y);
    return [
      for (var i = 0; i < result.length; i++)
        '${nameOf(result[i])} ${result.xAt(i)},${result.yAt(i)}',
    ];
  }
}

/// A test object's name, a core object's type.
String nameOf(RenderObject o) =>
    '$o'.startsWith('Instance of') ? '${o.runtimeType}' : '$o';

/// Fills all the room it gets; says nothing of hit tests, as most objects
/// that paint their cells.
final class Fill extends RenderObject {
  Fill(this.name);

  final String name;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) {}

  @override
  String toString() => name;
}

/// [w] × [h] whatever the constraints say.
final class Sized extends RenderObject {
  Sized(this.name, this.w, this.h);

  final String name;
  final int w;
  final int h;

  @override
  void performLayout(BoxConstraints c) {
    width = w;
    height = h;
  }

  @override
  void paint(PaintContext ctx) {}

  @override
  String toString() => name;
}

/// As big as the room it gets, its child laid out loosely within it [dx]
/// columns in and [dy] rows down; a hit test does with it what [behavior]
/// says.
base class Area extends RenderObject with RenderObjectWithChildMixin {
  Area(
    this.name,
    this.behavior, {
    RenderObject? child,
    this.dx = 0,
    this.dy = 0,
  }) {
    this.child = child;
  }

  final String name;
  HitTestBehavior behavior;
  final int dx;
  final int dy;

  @override
  HitTestBehavior get hitTestBehavior => behavior;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
    final ch = child;
    if (ch != null) {
      ch.layout(BoxConstraints(0, width, 0, height));
      ch.parentData
        ..dx = dx
        ..dy = dy;
    }
  }

  @override
  void paint(PaintContext ctx) {}

  @override
  String toString() => name;
}

/// An [Area] that defers to its child, whose layout throws once the child
/// is laid out.
final class Broken extends Area {
  Broken(String name, {super.child})
    : super(name, HitTestBehavior.deferToChild);

  @override
  void performLayout(BoxConstraints c) {
    super.performLayout(c);
    throw StateError(name);
  }
}

/// [child] pinned in a stack as the named arguments say.
RenderObject pin(
  RenderObject child, {
  int? left,
  int? top,
  int? width,
  int? height,
}) => child
  ..parentData = (StackParentData()
    ..left = left
    ..top = top
    ..width = width
    ..height = height);

/// [child] in a grid's cells from [row] and [column], spanning [rowSpan]
/// rows and [columnSpan] columns.
RenderObject cell(
  RenderObject child,
  int row,
  int column, [
  int rowSpan = 1,
  int columnSpan = 1,
]) => child
  ..parentData = (GridParentData()
    ..row = row
    ..column = column
    ..rowSpan = rowSpan
    ..columnSpan = columnSpan);

void main() {
  group('a hit test', () {
    test('finds the objects at a cell from the deepest to the root, each '
        'with the cell in its own coordinates', () {
      final v = View(
        10,
        5,
        RenderPadding(
          padding: const EdgeInsets.only(left: 2, top: 1),
          child: RenderPositionedBox(
            alignment: Alignment.bottomRight,
            child: RenderConstrainedBox(
              additionalConstraints: const BoxConstraints.tightFor(
                width: 3,
                height: 2,
              ),
              child: Fill('a'),
            ),
          ),
        ),
      );
      expect(v.at(8, 4), [
        'a 1,1',
        'RenderConstrainedBox 1,1',
        'RenderPositionedBox 6,3',
        'RenderPadding 8,4',
      ]);
      expect(v.at(7, 3), [
        'a 0,0',
        'RenderConstrainedBox 0,0',
        'RenderPositionedBox 5,2',
        'RenderPadding 7,3',
      ]);
    });

    test('finds nothing where only objects that defer to their children '
        'are, nor outside the root', () {
      final v = View(
        10,
        5,
        RenderPadding(
          padding: const EdgeInsets.only(left: 2, top: 1),
          child: RenderPositionedBox(
            alignment: Alignment.bottomRight,
            child: RenderConstrainedBox(
              additionalConstraints: const BoxConstraints.tightFor(
                width: 3,
                height: 2,
              ),
              child: Fill('a'),
            ),
          ),
        ),
      );
      expect(v.at(6, 3), isEmpty);
      expect(v.at(0, 0), isEmpty);
      expect(v.at(9, 2), isEmpty);
      expect(v.at(9, 4).first, 'a 2,1');
      expect(v.at(10, 4), isEmpty);
      expect(v.at(-1, 4), isEmpty);
      expect(v.at(9, 5), isEmpty);
    });

    test('misses what sticks out of its parent, as paint cuts it off', () {
      final v = View(
        10,
        1,
        RenderStack(
          children: [
            Fill('under'),
            pin(
              RenderPositionedBox(
                alignment: Alignment.topLeft,
                child: Sized('big', 6, 1),
              ),
              left: 0,
              top: 0,
              width: 3,
              height: 1,
            ),
          ],
        ),
      );
      expect(v.at(2, 0), [
        'big 2,0',
        'RenderPositionedBox 2,0',
        'RenderStack 2,0',
      ]);
      expect(v.at(4, 0), ['under 4,0', 'RenderStack 4,0']);
    });

    test('misses what sticks out of any ancestor, though inside its '
        'parent', () {
      final inner = RenderStack(
        children: [pin(Fill('c'), left: 1, top: 1, width: 4, height: 2)],
      );
      final outer = RenderStack(
        children: [
          Fill('under'),
          pin(inner, left: 5, top: 2, width: 6, height: 6),
        ],
      );
      final v = View(
        12,
        8,
        RenderStack(
          children: [pin(outer, left: 0, top: 0, width: 8, height: 5)],
        ),
      );
      expect(v.at(7, 4), [
        'c 1,1',
        'RenderStack 2,2',
        'RenderStack 7,4',
        'RenderStack 7,4',
      ]);
      // inside the inner stack and c, outside the outer stack
      expect(v.at(8, 3), isEmpty);
      expect(v.at(9, 4), isEmpty);
    });

    test('tests the children of a stack from the last, painted on top', () {
      final c = Fill('c');
      final stack = RenderStack(
        children: [
          Fill('a'),
          pin(Fill('b'), left: 1, top: 0, width: 3, height: 2),
          pin(c, left: 2, top: 1, width: 3, height: 2),
        ],
      );
      final v = View(6, 3, stack);
      expect(v.at(0, 0), ['a 0,0', 'RenderStack 0,0']);
      expect(v.at(1, 1), ['b 0,1', 'RenderStack 1,1']);
      expect(v.at(2, 1), ['c 0,0', 'RenderStack 2,1']);
      expect(v.at(4, 2), ['c 2,1', 'RenderStack 4,2']);
      stack.move(c, after: stack.firstChild);
      v.owner.flushLayout(6, 3);
      expect(v.at(2, 1), ['b 1,1', 'RenderStack 2,1']);
      expect(v.at(4, 2), ['c 2,1', 'RenderStack 4,2']);
    });

    test('tests the children of a grid from the last, painted on top; its '
        'gaps and empty cells hit nothing', () {
      final b = cell(Fill('b'), 0, 1, 2);
      final grid = RenderGrid(
        columns: const [GridTrack.fixed(2), GridTrack.fixed(2)],
        rows: const [GridTrack.fixed(1), GridTrack.fixed(1)],
        columnGap: 1,
        children: [cell(Fill('a'), 0, 0, 1, 2), b],
      );
      final v = View(6, 2, grid);
      expect(v.at(1, 0), ['a 1,0', 'RenderGrid 1,0']);
      expect(v.at(2, 0), ['a 2,0', 'RenderGrid 2,0']);
      expect(v.at(3, 0), ['b 0,0', 'RenderGrid 3,0']);
      expect(v.at(4, 1), ['b 1,1', 'RenderGrid 4,1']);
      expect(v.at(2, 1), isEmpty);
      expect(v.at(0, 1), isEmpty);
      expect(v.at(5, 0), isEmpty);
      grid.move(b);
      v.owner.flushLayout(6, 2);
      expect(v.at(3, 0), ['a 3,0', 'RenderGrid 3,0']);
      expect(v.at(3, 1), ['b 0,1', 'RenderGrid 3,1']);
    });

    test('tests the children of a flex; its gaps hit what is under it', () {
      final v = View(
        5,
        1,
        RenderStack(
          children: [
            Fill('under'),
            RenderFlex(gap: 1, children: [Sized('a', 2, 1), Sized('b', 2, 1)]),
          ],
        ),
      );
      expect(v.at(1, 0), ['a 1,0', 'RenderFlex 1,0', 'RenderStack 1,0']);
      expect(v.at(2, 0), ['under 2,0', 'RenderStack 2,0']);
      expect(v.at(3, 0), ['b 0,0', 'RenderFlex 3,0', 'RenderStack 3,0']);
    });
  });

  group('the behaviour of an object', () {
    /// [over] on top of a fill, its child one column in.
    View stacked(Area over) =>
        View(4, 1, RenderStack(children: [Fill('under'), over]));

    test('opaque: hit anywhere in it, it hides what it covers', () {
      final v = stacked(
        Area('over', HitTestBehavior.opaque, child: Sized('kid', 1, 1), dx: 1),
      );
      expect(v.at(0, 0), ['over 0,0', 'RenderStack 0,0']);
      expect(v.at(1, 0), ['kid 0,0', 'over 1,0', 'RenderStack 1,0']);
    });

    test('translucent: added anywhere in it, it lets what it covers be hit '
        'unless a child of it is', () {
      final v = stacked(
        Area(
          'glass',
          HitTestBehavior.translucent,
          child: Sized('kid', 1, 1),
          dx: 1,
        ),
      );
      expect(v.at(0, 0), ['glass 0,0', 'under 0,0', 'RenderStack 0,0']);
      expect(v.at(1, 0), ['kid 0,0', 'glass 1,0', 'RenderStack 1,0']);
    });

    test('translucent over translucent: all of them are added', () {
      final v = stacked(
        Area(
          'glass',
          HitTestBehavior.translucent,
          child: Area('pane', HitTestBehavior.translucent),
          dx: 1,
        ),
      );
      expect(v.at(2, 0), [
        'pane 1,0',
        'glass 2,0',
        'under 2,0',
        'RenderStack 2,0',
      ]);
    });

    test('deferToChild: hit only where a child of it is', () {
      final area = Area(
        'frame',
        HitTestBehavior.deferToChild,
        child: Sized('kid', 1, 1),
        dx: 1,
      );
      final v = stacked(area);
      expect(v.at(0, 0), ['under 0,0', 'RenderStack 0,0']);
      expect(v.at(1, 0), ['kid 0,0', 'frame 1,0', 'RenderStack 1,0']);
      area.behavior = HitTestBehavior.opaque;
      expect(v.at(0, 0), ['frame 0,0', 'RenderStack 0,0']);
    });

    test('an object that shows an error is hit anywhere in it, its '
        'children not tested', () {
      final v = View(
        4,
        2,
        RenderStack(
          children: [
            Fill('under'),
            pin(
              Broken('broken', child: Sized('kid', 1, 1)),
              left: 0,
              top: 0,
              width: 3,
              height: 2,
            ),
          ],
        ),
      );
      expect(v.errors, ['Bad state: broken']);
      expect(v.at(0, 0), ['broken 0,0', 'RenderStack 0,0']);
      expect(v.at(2, 1), ['broken 2,1', 'RenderStack 2,1']);
      expect(v.at(3, 0), ['under 3,0', 'RenderStack 3,0']);
    });
  });

  group('the objects of the core', () {
    test('those that paint their cells are opaque', () {
      final leaves = <RenderObject>[
        RenderText('ab', 0),
        RenderParagraph(const [('ab', Pen())]),
        RenderErrorBox('x'),
        RenderDivider(),
        RenderLog(pen: 0, itemPen: (_, _) => 0),
      ];
      for (final leaf in leaves) {
        final v = View(4, 1, RenderStack(children: [Fill('under'), leaf]));
        expect(v.at(0, 0), [
          '${leaf.runtimeType} 0,0',
          'RenderStack 0,0',
        ], reason: '${leaf.runtimeType}');
      }
    });

    test('a box is hit anywhere in it, its child first', () {
      final v = View(
        5,
        3,
        RenderStack(
          children: [
            Fill('under'),
            RenderBox(pen: 0, padX: 1, padY: 1, child: Sized('kid', 1, 1)),
          ],
        ),
      );
      expect(v.at(0, 0), ['RenderBox 0,0', 'RenderStack 0,0']);
      expect(v.at(1, 1), ['kid 0,0', 'RenderBox 1,1', 'RenderStack 1,1']);
    });

    test('a decorated box without a background is hit on its border and '
        'titles and where its child is; with one, anywhere', () {
      final box = RenderDecoratedBox(
        border: const BoxBorder(left: Pen(), top: Pen()),
        titles: const [BoxTitle('ab', alignment: Alignment.bottomRight)],
        child: Sized('kid', 1, 1),
      );
      final v = View(
        5,
        4,
        RenderStack(
          children: [
            Fill('under'),
            pin(box, left: 0, top: 0, width: 5, height: 4),
          ],
        ),
      );
      expect(v.at(0, 2), ['RenderDecoratedBox 0,2', 'RenderStack 0,2']);
      expect(v.at(3, 0), ['RenderDecoratedBox 3,0', 'RenderStack 3,0']);
      expect(v.at(4, 3), ['RenderDecoratedBox 4,3', 'RenderStack 4,3']);
      expect(v.at(1, 1), [
        'kid 0,0',
        'RenderDecoratedBox 1,1',
        'RenderStack 1,1',
      ]);
      expect(v.at(2, 3), ['under 2,3', 'RenderStack 2,3']);
      expect(v.at(2, 2), ['under 2,2', 'RenderStack 2,2']);
      box.background = const Pen(bg: Color.rgb(0, 0, 0));
      expect(v.at(2, 2), ['RenderDecoratedBox 2,2', 'RenderStack 2,2']);
      expect(v.at(2, 3), ['RenderDecoratedBox 2,3', 'RenderStack 2,3']);
    });
  });

  group('the result', () {
    test('is emptied by each hit test, and grows for a path deeper than it '
        'holds', () {
      RenderObject tree = Fill('leaf');
      for (var i = 0; i < 40; i++) {
        tree = RenderPadding(padding: EdgeInsets.zero, child: tree);
      }
      final v = View(2, 1, tree);
      final path = v.at(1, 0);
      expect(path, hasLength(41));
      expect(path.first, 'leaf 1,0');
      expect(path.skip(1).toSet(), {'RenderPadding 1,0'});
      expect(v.result.capacity, greaterThanOrEqualTo(41));
      expect(v.at(2, 0), isEmpty);
      expect(() => v.result[0], throwsRangeError);
    });

    test('is reused over a 200×60 tree without growing', () {
      // 60 rows of 20 fills 10 columns wide, each in a padding
      final v = View(
        200,
        60,
        RenderColumn([
          for (var y = 0; y < 60; y++)
            (
              RenderRow([
                for (var x = 0; x < 20; x++)
                  (
                    RenderPadding(
                      padding: EdgeInsets.zero,
                      child: Fill('${10 * x},$y'),
                    ),
                    10,
                  ),
              ]),
              1,
            ),
        ]),
      );
      final result = v.result;
      v.at(0, 0);
      final capacity = result.capacity;
      final wrong = <String>[];
      for (var y = 0; y < 60; y++) {
        for (var x = 0; x < 200; x++) {
          v.owner.hitTest(result, x, y);
          final name = '${x - x % 10},$y';
          if (result.length != 4 ||
              '${result[0]}' != name ||
              result.xAt(0) != x % 10 ||
              result.yAt(0) != 0 ||
              result.xAt(3) != x ||
              result.yAt(3) != y) {
            wrong.add('$x,$y');
          }
        }
      }
      expect(wrong, isEmpty);
      expect(identical(v.result, result), isTrue);
      expect(result.capacity, capacity);
    });
  });
}
