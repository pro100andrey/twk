// Boxes whose child is laid out or shown otherwise than their own
// constraints and place say: LimitedBox along unbounded axes only,
// OverflowBox and SizedOverflowBox with other constraints, the child
// sticking out cut off at their edges, and Transform.translate, which
// paints and hit-tests its child moved without laying it out again.
import 'package:test/test.dart';
import 'package:twk/twk.dart';

import 'view.dart';

/// The render object hit deepest at [x], [y] of [v].
RenderObject? hitAt(View v, int x, int y) {
  final result = HitTestResult();
  v.top.hitTest(result, x, y);
  return result.isEmpty ? null : result[0];
}

/// The first render object under [o], or [o], that has no children.
RenderObject leafOf(RenderObject o) {
  final children = childrenOf(o);
  return children.isEmpty ? o : leafOf(children.first);
}

void main() {
  group('LimitedBox', () {
    test('limits its child along an unbounded axis only', () {
      final v = View(6, 4)
        ..pump(
          const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LimitedBox(maxWidth: 2, maxHeight: 2, child: Fill('x')),
                Label('|'),
              ],
            ),
          ),
        );
      // the scrolled column leaves the height unbounded, not the width
      expect(v.rows(), ['xxxxxx', 'xxxxxx', '|', '']);
    });

    test('a new limit lays the same render object out again', () {
      Widget limited(int rows) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LimitedBox(maxHeight: rows, child: const Fill('x')),
            const Label('|'),
          ],
        ),
      );
      final v = View(6, 4)..pump(limited(2));
      final fill = leafOf(v.top);
      v.pump(limited(1));
      expect(leafOf(v.top), same(fill));
      expect(fill.height, 1);
      expect(v.rows(), ['xxxxxx', '|', '', '']);
    });

    test('without a child is as small as the constraints allow', () {
      final v = View(6, 1)
        ..pump(
          const Row(
            children: [
              Label('a'),
              LimitedBox(maxWidth: 3),
              Label('b'),
            ],
          ),
        );
      expect(v.rows(), ['ab']);
    });
  });

  group('OverflowBox', () {
    test('gives its child constraints of its own, the child sticking out '
        'on both sides as the alignment says, cut off at its edges', () {
      final v = View(9, 1)
        ..pump(
          const Row(
            children: [
              Label('['),
              SizedBox(
                width: 3,
                child: OverflowBox(
                  minWidth: 5,
                  maxWidth: 5,
                  child: Label('abcde'),
                ),
              ),
              Label(']'),
            ],
          ),
        );
      expect(v.rows(), ['[bcd]']);
    });

    test('a limit given wins over the one it crosses, and limits not given '
        "are the box's own", () {
      final v = View(6, 3)
        ..pump(
          const Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 4,
              height: 2,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: 6,
                child: Fill('x'),
              ),
            ),
          ),
        );
      // 6 wide (its max raised to its min), 2 tall (the box's own), cut
      // off at the box's 4 columns
      expect(v.rows(), ['xxxx', 'xxxx', '']);
      final fill = leafOf(v.top);
      expect((fill.width, fill.height), (6, 2));
    });

    test('a smaller child is placed by the alignment, the box as big as it '
        'may be, and new settings lay the same render object out again', () {
      final v = View(5, 3)
        ..pump(
          const OverflowBox(
            alignment: Alignment.bottomRight,
            maxWidth: 2,
            maxHeight: 1,
            child: Fill('x'),
          ),
        );
      expect(v.rows(), ['', '', '   xx']);
      final box = v.top;
      expect((box.width, box.height), (5, 3));
      v.pump(
        const OverflowBox(
          alignment: Alignment.topLeft,
          maxWidth: 3,
          maxHeight: 1,
          child: Fill('x'),
        ),
      );
      expect(v.top, same(box));
      expect(v.rows(), ['xxx', '', '']);
    });

    test('the child takes the mouse where it shows', () {
      final v = View(5, 1)
        ..pump(
          const OverflowBox(
            alignment: Alignment.centerRight,
            maxWidth: 2,
            child: Fill('x'),
          ),
        );
      final fill = leafOf(v.top);
      expect(hitAt(v, 4, 0), same(fill));
      expect(hitAt(v, 0, 0), isNot(same(fill)));
    });
  });

  group('SizedOverflowBox', () {
    test('is its size, and lays its child out within its own constraints, '
        'cut off at its edges', () {
      final v = View(8, 1)
        ..pump(
          const Row(
            children: [
              Label('['),
              SizedOverflowBox(
                size: (2, 1),
                alignment: Alignment.centerLeft,
                child: Label('abcd'),
              ),
              Label(']'),
            ],
          ),
        );
      expect(v.rows(), ['[ab]']);
      final label = leafOf(childrenOf(v.top)[1]);
      expect(label.width, 4);
    });

    test('a new size lays the same render object out again', () {
      final v = View(8, 1)
        ..pump(
          const Row(
            children: [
              SizedOverflowBox(size: (2, 1), child: Label('abcd')),
              Label(']'),
            ],
          ),
        );
      final box = childrenOf(v.top).first;
      // centered: a column sticks out on each side
      expect(v.rows(), ['bc]']);
      v.pump(
        const Row(
          children: [
            SizedOverflowBox(size: (4, 1), child: Label('abcd')),
            Label(']'),
          ],
        ),
      );
      expect(childrenOf(v.top).first, same(box));
      expect(v.rows(), ['abcd]']);
      expect(box.getMaxIntrinsicWidth(1), 4);
    });
  });

  group('Transform.translate', () {
    test('paints its child moved, cut off at its own place, laid out as if '
        'it were not moved', () {
      final v = View(10, 2)
        ..pump(
          const Row(
            children: [
              Label('['),
              Transform.translate(offset: (1, 0), child: Label('abc')),
              Label(']'),
            ],
          ),
        );
      expect(v.rows(), ['[ ab]', '']);
      v.pump(
        const Row(
          children: [
            Label('['),
            Transform.translate(offset: (-2, 0), child: Label('abc')),
            Label(']'),
          ],
        ),
      );
      expect(v.rows(), ['[c  ]', '']);
    });

    test('a move keeps the render objects', () {
      final v = View(6, 3)
        ..pump(const Transform.translate(offset: (0, 0), child: Fill('x')));
      final box = v.top;
      final fill = leafOf(box);
      v.pump(const Transform.translate(offset: (2, 1), child: Fill('x')));
      expect(v.top, same(box));
      expect(leafOf(box), same(fill));
      expect(v.rows(), ['', '  xxxx', '  xxxx']);
    });

    test('the mouse finds the child where it shows, or with '
        'transformHitTests off where it would be unmoved', () {
      final v = View(6, 1)
        ..pump(
          const Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 4,
              child: Transform.translate(offset: (2, 0), child: Fill('x')),
            ),
          ),
        );
      final fill = leafOf(v.top);
      expect(hitAt(v, 2, 0), same(fill));
      expect(hitAt(v, 1, 0), isNull);
      v.pump(
        const Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 4,
            child: Transform.translate(
              offset: (2, 0),
              transformHitTests: false,
              child: Fill('x'),
            ),
          ),
        ),
      );
      expect(v.rows(), ['  xx']);
      expect(hitAt(v, 0, 0), same(fill));
    });
  });
}
