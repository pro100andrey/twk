// Boxes that paint under or over a child: a ColoredBox's fill and size, a
// DecoratedBox under its child (a Box, a gradient under it) and over it
// (lines over the child's edges, which the mouse passes by), and a
// Container put together as Flutter's is: the padding inside the
// decoration, the margin outside, the size between them.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show RenderDecoratedBox;

import 'view.dart';

const red = Color.rgb(200, 0, 0);
const blue = Color.rgb(0, 0, 200);

/// The background of the cell at [x], [y] of [v].
Color bgAt(View v, int x, int y) =>
    v.screen.styles.bgOf(v.screen.surface.styles[y * v.width + x]);

/// The text color of the cell at [x], [y] of [v].
Color fgAt(View v, int x, int y) =>
    v.screen.styles.fgOf(v.screen.surface.styles[y * v.width + x]);

/// The render object hit deepest at [x], [y] of [v].
RenderObject? hitAt(View v, int x, int y) {
  final result = HitTestResult();
  v.top.hitTest(result, x, y);
  return result.isEmpty ? null : result[0];
}

void main() {
  group('ColoredBox', () {
    test('fills its cells under its child, as big as the child', () {
      final v = View(6, 2)
        ..pump(
          const Align(
            alignment: Alignment.topLeft,
            child: ColoredBox(color: blue, child: Label('ab')),
          ),
        );
      expect(v.rows(), ['ab', '']);
      expect([bgAt(v, 0, 0), bgAt(v, 1, 0)], [blue, blue]);
      expect(bgAt(v, 2, 0), isNot(blue));
      expect(bgAt(v, 0, 1), isNot(blue));
    });

    test('without a child is as small as the constraints allow', () {
      final v = View(6, 1)
        ..pump(
          const Row(
            children: [
              Label('a'),
              ColoredBox(color: blue),
              Label('b'),
            ],
          ),
        );
      expect(v.rows(), ['ab']);
      expect(bgAt(v, 1, 0), isNot(blue));
    });

    test('a new color repaints the same render object, which the mouse '
        'hits anywhere in its cells', () {
      final v = View(4, 1)
        ..pump(const ColoredBox(color: blue, child: SizedBox.expand()));
      final box = v.top;
      v.pump(const ColoredBox(color: red, child: SizedBox.expand()));
      expect(v.top, same(box));
      expect(bgAt(v, 3, 0), red);
      expect(hitAt(v, 3, 0), same(box));
    });
  });

  group('DecoratedBox', () {
    test('under its child is a Box: the style fills it, the border goes '
        'around the child and the titles on its edges', () {
      final v = View(6, 3)
        ..pump(
          const DecoratedBox(
            decoration: BoxDecoration(
              style: Style(bg: blue),
              border: Border.all(),
              titles: [BorderTitle('t')],
            ),
            child: Fill('x'),
          ),
        );
      expect(v.rows(), ['┌t───┐', '│xxxx│', '└────┘']);
      expect(v.top, isA<RenderDecoratedBox>());
      expect([bgAt(v, 0, 0), bgAt(v, 2, 1)], [blue, blue]);
    });

    test('a gradient goes under the box', () {
      final v = View(4, 3)
        ..pump(
          const DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(),
              gradient: Gradient([red, blue]),
            ),
            child: Label('ab'),
          ),
        );
      expect(v.rows(), ['┌──┐', '│ab│', '└──┘']);
      expect(bgAt(v, 0, 1), red);
      expect(bgAt(v, 3, 1), blue);
    });

    test("over its child draws the border over the child's edges, the "
        'lines in the colors of the style, and lets the mouse through to '
        'the child', () {
      final v = View(5, 3)
        ..pump(
          const DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              style: Style(fg: red, bg: blue),
              border: Border.all(),
              titles: [BorderTitle('t')],
            ),
            child: ColoredBox(color: red, child: Fill('x')),
          ),
        );
      expect(v.rows(), ['┌t──┐', '│xxx│', '└───┘']);
      expect(fgAt(v, 0, 0), red);
      expect(fgAt(v, 1, 0), red);
      expect(bgAt(v, 0, 0), blue);
      // the style is not filled: the child's background shows inside
      expect(bgAt(v, 2, 1), red);
      final hit = hitAt(v, 0, 0);
      expect(hit, isNotNull);
      expect(hit, isNot(isA<RenderDecoratedBox>()));
    });

    test('over its child keeps the constraints it was given: a tight '
        "size is the child's, the border on its edges", () {
      final v = View(8, 4)
        ..pump(
          const Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 6,
              height: 3,
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(border: Border.all()),
                child: ColoredBox(color: red, child: Label('ab')),
              ),
            ),
          ),
        );
      expect(v.rows(), ['┌────┐', '│    │', '└────┘', '']);
      // the child under the lines as big as the box
      expect(bgAt(v, 4, 1), red);
      expect(bgAt(v, 6, 1), isNot(red));
    });

    test('over its child, a gradient colors its text', () {
      final v = View(2, 1)
        ..pump(
          const DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(gradient: Gradient([red, blue])),
            child: Label('ab'),
          ),
        );
      expect(v.rows(), ['ab']);
      expect([fgAt(v, 0, 0), fgAt(v, 1, 0)], [red, blue]);
    });
  });

  group('Container', () {
    test('puts the padding inside the decoration and the margin outside', () {
      final v = View(9, 7)
        ..pump(
          const Container(
            margin: EdgeInsets.all(1),
            padding: EdgeInsets.x(1),
            decoration: BoxDecoration(
              style: Style(bg: blue),
              border: Border.all(),
            ),
            child: Fill('x'),
          ),
        );
      expect(v.rows(), [
        '',
        ' ┌─────┐',
        ' │ xxx │',
        ' │ xxx │',
        ' │ xxx │',
        ' └─────┘',
        '',
      ]);
      // the margin is not filled, the padding is
      expect(bgAt(v, 0, 0), isNot(blue));
      expect(bgAt(v, 2, 2), blue);
    });

    test('a width and a height size the box inside the margin, and the '
        'alignment places the child inside the padding', () {
      final v = View(10, 5)
        ..pump(
          const Align(
            alignment: Alignment.topLeft,
            child: Container(
              width: 6,
              height: 3,
              margin: EdgeInsets.only(left: 2, top: 1),
              padding: EdgeInsets.x(1),
              color: blue,
              alignment: Alignment.bottomRight,
              child: Label('ab'),
            ),
          ),
        );
      expect(v.rows(), ['', '', '', '     ab', '']);
      expect([bgAt(v, 2, 1), bgAt(v, 7, 3)], [blue, blue]);
      expect(
        [bgAt(v, 1, 1), bgAt(v, 8, 3), bgAt(v, 2, 4)],
        [
          isNot(blue),
          isNot(blue),
          isNot(blue),
        ],
      );
    });

    test('the constraints are tightened to the width, within them', () {
      final v = View(10, 1)
        ..pump(
          const Row(
            children: [
              Container(
                width: 8,
                constraints: BoxConstraints(0, 4, 0, 1),
                color: blue,
              ),
              Label('|'),
            ],
          ),
        );
      expect(v.rows(), ['    |']);
    });

    test('without a child or tight constraints, as big as it may be, as '
        'small along an unbounded axis', () {
      final v = View(6, 3)
        ..pump(
          const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(color: blue),
                Label('|'),
              ],
            ),
          ),
        );
      expect(v.rows(), ['|', '', '']);
      // as wide as the scrolled column lets it be, but no row tall
      expect(bgAt(v, 5, 0), isNot(blue));
      v.pump(const Container(color: blue));
      expect(bgAt(v, 5, 2), blue);
    });

    test('a foreground decoration is drawn over the child and the padding', () {
      final v = View(6, 3)
        ..pump(
          const Container(
            padding: EdgeInsets.all(1),
            foregroundDecoration: BoxDecoration(border: Border.all()),
            child: Fill('x'),
          ),
        );
      expect(v.rows(), ['┌────┐', '│xxxx│', '└────┘']);
    });

    test('a foreground decoration keeps the size given to the child: the '
        'decoration under it and the padding fill it', () {
      final v = View(10, 5)
        ..pump(
          const Align(
            alignment: Alignment.topLeft,
            child: Container(
              width: 8,
              height: 4,
              padding: EdgeInsets.all(1),
              decoration: BoxDecoration(style: Style(bg: blue)),
              foregroundDecoration: BoxDecoration(border: Border.all()),
              child: Label('ab'),
            ),
          ),
        );
      expect(v.rows(), ['┌──────┐', '│ab    │', '│      │', '└──────┘', '']);
      // the decoration under the child as big as the container
      expect(bgAt(v, 6, 2), blue);
      expect(bgAt(v, 8, 2), isNot(blue));
    });

    test('with nothing but a child is the child', () {
      final v = View(4, 1)..pump(const Container(child: Label('ab')));
      expect(v.rows(), ['ab']);
      expect(v.top, isA<RenderLabel>());
    });
  });

  group('BoxDecoration', () {
    test('decorations are equal when their style, border, gradient and '
        'titles, in order, are; and equal ones hash alike', () {
      BoxDecoration make({List<BorderTitle> titles = const []}) =>
          BoxDecoration(
            style: const Style(fg: red),
            border: const Border.all(),
            titles: titles,
          );
      const a = BorderTitle('a');
      const b = BorderTitle('b');
      expect(make(titles: [a, b]), make(titles: [a, b]));
      expect(make(titles: [a, b]).hashCode, make(titles: [a, b]).hashCode);
      expect(make(titles: [a, b]), isNot(make(titles: [b, a])));
      expect(make(titles: [a]), isNot(make(titles: [a, b])));
      expect(make(), isNot(const BoxDecoration(style: Style(fg: red))));
      expect(
        const BoxDecoration(gradient: Gradient([red, blue])),
        isNot(const BoxDecoration(gradient: Gradient([blue, red]))),
      );
    });
  });
}
