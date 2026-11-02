// Boxes with one child: padding, alignment, sizes, fractions of the room
// there is and the size of the content given to the render objects of the
// core, the child's render object put into theirs, swapped and taken out
// with the child.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show
        RenderConstrainedBox,
        RenderFractionallySizedBox,
        RenderIntrinsicWidth,
        RenderPadding,
        RenderPositionedBox;

import 'view.dart';

void main() {
  group('Padding', () {
    test('insets its child', () {
      final v = View(6, 3)
        ..pump(const Padding(padding: EdgeInsets.all(1), child: Fill('x')));
      expect(v.rows(), ['', ' xxxx', '']);
    });

    test('a new padding changes the same render object', () {
      final v = View(6, 3)
        ..pump(const Padding(padding: EdgeInsets.all(1), child: Fill('x')));
      final padding = v.top;
      v.pump(const Padding(padding: EdgeInsets.x(2), child: Fill('x')));
      expect(v.top, same(padding));
      expect((padding as RenderPadding).padding, const EdgeInsets.x(2));
      expect(v.rows(), ['  xx', '  xx', '  xx']);
    });

    test('without a child is as big as its padding', () {
      final v = View(6, 1)
        ..pump(
          const Row(
            children: [
              Label('a'),
              Padding(padding: EdgeInsets.x(2)),
              Label('b'),
            ],
          ),
        );
      expect(v.rows(), ['a    b']);
    });
  });

  group('Align', () {
    test('places its child as its alignment says', () {
      final v = View(5, 3)
        ..pump(
          const Align(alignment: Alignment.bottomRight, child: Label('ab')),
        );
      expect(v.rows(), ['', '', '   ab']);
    });

    test('with a factor is that many times as big as its child', () {
      final v = View(8, 1)
        ..pump(
          const Row(
            children: [
              Align(
                alignment: Alignment.centerRight,
                widthFactor: 2,
                child: Label('ab'),
              ),
              Label('|'),
            ],
          ),
        );
      expect(v.rows(), ['  ab|']);
    });

    test('new settings change the same render object', () {
      final v = View(6, 3)..pump(const Align(child: Label('ab')));
      final box = v.top;
      expect(v.rows(), ['', '  ab', '']);
      v.pump(
        const Align(
          alignment: Alignment.topLeft,
          widthFactor: 1,
          heightFactor: 2,
          child: Label('ab'),
        ),
      );
      expect(v.top, same(box));
      expect(
        [
          (box as RenderPositionedBox).alignment,
          box.widthFactor,
          box.heightFactor,
        ],
        [Alignment.topLeft, 1, 2],
      );
      // the screen gives the box all of it
      expect(v.rows(), ['ab', '', '']);
    });

    test('in a scroll view is as tall as its child, as in Flutter', () {
      final v = View(6, 4)
        ..pump(
          const SingleChildScrollView(
            child: Column(
              children: [
                Align(alignment: Alignment.centerRight, child: Label('ab')),
                Label('cd'),
              ],
            ),
          ),
        );
      expect(v.rows(), ['    ab', '  cd', '', '']);
    });

    test("in a list's row is as tall as its child, so each row is a "
        'row', () {
      final v = View(6, 4)
        ..pump(
          ListView(
            children: [
              for (final name in ['ab', 'cd'])
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Label(name),
                      ),
                    ),
                    const Label('|'),
                  ],
                ),
            ],
          ),
        );
      expect(v.rows(), ['ab   |', 'cd   |', '', '']);
    });
  });

  group('Center', () {
    test('puts its child in the middle, the odd cell after it', () {
      final even = View(6, 3)..pump(const Center(child: Label('ab')));
      expect(even.rows(), ['', '  ab', '']);
      final odd = View(7, 4)..pump(const Center(child: Label('ab')));
      expect(odd.rows(), ['', '  ab', '', '']);
    });

    test('with factors is that many times as big as its child', () {
      final v = View(8, 4)
        ..pump(
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(widthFactor: 3, heightFactor: 2, child: Label('ab')),
              Label('|'),
            ],
          ),
        );
      expect(v.rows(), ['  ab  |', '', '', '']);
    });
  });

  group('SizedBox', () {
    test('makes its child as big as it says', () {
      final v = View(8, 3)
        ..pump(
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 3, height: 2, child: Fill('x')),
              Label('|'),
            ],
          ),
        );
      expect(v.rows(), ['xxx|', 'xxx', '']);
    });

    test('leaves the child as long as it wants along an axis left out', () {
      final v = View(8, 3)
        ..pump(
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 3, child: Fill('x')),
              Label('|'),
            ],
          ),
        );
      expect(v.rows(), ['xxx|', 'xxx', 'xxx']);
    });

    test('without a child is that big itself', () {
      final v = View(6, 1)
        ..pump(
          const Row(children: [Label('a'), SizedBox(width: 2), Label('b')]),
        );
      expect(v.rows(), ['a  b']);
    });

    test('expand is as big as it may be, shrink as small', () {
      final v = View(4, 2)
        ..pump(
          const Align(
            alignment: Alignment.topLeft,
            child: SizedBox.expand(child: Label('ab')),
          ),
        );
      final expand = childrenOf(v.top).single;
      expect([expand.width, expand.height], [4, 2]);
      expect(childrenOf(expand).single.width, 4);
      v.pump(
        const Row(
          children: [
            Label('a'),
            SizedBox.shrink(child: Fill('x')),
            Label('b'),
          ],
        ),
      );
      expect(v.rows(), ['ab', '']);
    });

    test('a new size changes the same render object', () {
      final v = View(8, 1)
        ..pump(
          const Row(
            children: [
              SizedBox(width: 3, child: Fill('x')),
              Label('|'),
            ],
          ),
        );
      final box = childrenOf(v.top).first;
      v.pump(
        const Row(
          children: [
            SizedBox(width: 5, child: Fill('x')),
            Label('|'),
          ],
        ),
      );
      expect(childrenOf(v.top).first, same(box));
      expect(
        (box as RenderConstrainedBox).additionalConstraints,
        const BoxConstraints.tightFor(width: 5),
      );
      expect(v.rows(), ['xxxxx|']);
    });
  });

  group('ConstrainedBox', () {
    test('keeps its child within its constraints', () {
      final v = View(8, 1)
        ..pump(
          const Row(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(4, 5, 0, 1),
                child: Label('abcdefg'),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(2, 5, 0, 1),
                child: Label('a'),
              ),
              Label('|'),
            ],
          ),
        );
      expect(v.rows(), ['abcdea |']);
    });

    test('new constraints change the same render object', () {
      final v = View(8, 1)
        ..pump(
          const ConstrainedBox(
            constraints: BoxConstraints(0, 3, 0, 1),
            child: Label('abcdef'),
          ),
        );
      final box = v.top;
      v.pump(
        const ConstrainedBox(
          constraints: BoxConstraints(0, 5, 0, 1),
          child: Label('abcdef'),
        ),
      );
      expect(v.top, same(box));
      // the screen's constraints are tight
      expect(
        (box as RenderConstrainedBox).additionalConstraints,
        const BoxConstraints(0, 5, 0, 1),
      );
    });
  });

  group('FractionallySizedBox', () {
    test('makes its child a fraction of the room there is, rounded to the '
        'nearest cell', () {
      final v = View(9, 3)
        ..pump(
          const FractionallySizedBox(
            widthFactor: 0.5,
            heightFactor: 1 / 3,
            alignment: Alignment.topLeft,
            child: Fill('x'),
          ),
        );
      // 4.5 columns are 5, a row is one
      expect(v.rows(), ['xxxxx', '', '']);
    });

    test('along an axis without a factor gives its child all of the room', () {
      final v = View(8, 2)
        ..pump(const FractionallySizedBox(widthFactor: 0.25, child: Fill('x')));
      expect(v.rows(), ['   xx', '   xx']);
    });

    test('in a row, takes a fraction of the row: the room is bounded', () {
      final v = View(10, 1)
        ..pump(
          const Row(
            children: [
              Expanded(
                child: FractionallySizedBox(
                  widthFactor: 0.3,
                  alignment: Alignment.centerLeft,
                  child: Fill('x'),
                ),
              ),
              Label('|'),
            ],
          ),
        );
      expect(v.rows(), ['xxx      |']);
    });

    test('new factors change the same render object', () {
      final v = View(8, 1)
        ..pump(const FractionallySizedBox(widthFactor: 0.5, child: Fill('x')));
      final box = v.top;
      v.pump(
        const FractionallySizedBox(
          widthFactor: 0.25,
          alignment: Alignment.centerRight,
          child: Fill('x'),
        ),
      );
      expect(v.top, same(box));
      expect(
        [
          (box as RenderFractionallySizedBox).widthFactor,
          box.heightFactor,
          box.alignment,
        ],
        [0.25, null, Alignment.centerRight],
      );
      expect(v.rows(), ['      xx']);
    });
  });

  group('IntrinsicWidth', () {
    test('makes its child as wide as its content', () {
      final v = View(12, 2)
        ..pump(
          const Align(
            alignment: Alignment.topLeft,
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('short'),
                  Box(
                    style: Style(bg: Color.blue),
                    child: Text('longest'),
                  ),
                ],
              ),
            ),
          ),
        );
      final box = childrenOf(v.top).single;
      expect([box.width, box.height], [7, 2]);
      expect(v.rows(), ['short', 'longest']);
    });

    test('rounds up to its steps', () {
      final v = View(12, 4)
        ..pump(
          const Align(
            alignment: Alignment.topLeft,
            child: IntrinsicWidth(
              stepWidth: 4,
              stepHeight: 3,
              child: Text('hello'),
            ),
          ),
        );
      final box = childrenOf(v.top).single;
      expect([box.width, box.height], [8, 3]);
    });

    test('new steps change the same render object', () {
      final v = View(12, 1)
        ..pump(const IntrinsicWidth(stepWidth: 2, child: Text('a')));
      final box = v.top;
      v.pump(const IntrinsicWidth(stepHeight: 2, child: Text('a')));
      expect(v.top, same(box));
      expect(
        [(box as RenderIntrinsicWidth).stepWidth, box.stepHeight],
        [null, 2],
      );
    });
  });

  group('IntrinsicHeight', () {
    test('makes a row whose children stretch as tall as its tallest '
        'child', () {
      final v = View(12, 5)
        ..pump(
          const Align(
            alignment: Alignment.topLeft,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Box(border: Border.all(), child: Text('a')),
                  Text('b\nc\nd', wrap: TextWrap.none),
                ],
              ),
            ),
          ),
        );
      expect(v.rows(), ['┌─┐b', '│a│c', '└─┘d', '', '']);
    });
  });

  group('the child of a box', () {
    test('is replaced by the render object of a new child', () {
      final v = View(4, 1)
        ..pump(
          Padding(
            padding: const EdgeInsets.x(1),
            child: Toggle(() => const Label('a'), () => const Fill('x')),
          ),
        );
      final box = v.top as RenderObjectWithChildMixin;
      final first = box.child;
      expect(v.rows(), [' a']);
      toggleIn(v.root).toggle();
      v.frame();
      expect(box.child, isNot(same(first)));
      expect(first!.parent, isNull);
      expect(v.rows(), [' xx']);
    });

    test('is taken out when the box has none, and put back', () {
      final v = View(4, 1)
        ..pump(
          Toggle(
            () => const SizedBox(width: 2, child: Fill('x')),
            () => const SizedBox(width: 2),
          ),
        );
      final box = v.top as RenderObjectWithChildMixin;
      final child = box.child;
      expect(v.rows(), ['xxxx']);
      toggleIn(v.root).toggle();
      v.frame();
      expect([box.child, child!.parent], [null, null]);
      expect(v.rows(), ['']);
      toggleIn(v.root).toggle();
      v.frame();
      expect(box.child, isNotNull);
      expect(v.rows(), ['xxxx']);
    });

    test('goes on through widgets in between', () {
      final v = View(4, 1)..pump(const Center(child: Wrapper(Label('ab'))));
      final box = v.top as RenderObjectWithChildMixin;
      expect(box.child, isA<RenderLabel>());
      expect(v.rows(), [' ab']);
    });
  });
}
