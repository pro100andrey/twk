// What a BoxConstraints and an EdgeInsets are asked: the ways to make one
// as Flutter makes them, and what is made of one (loosened, tightened,
// deflated, held within another, its bounds and extremes).
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

void main() {
  const unbounded = BoxConstraints.unbounded;
  const c = BoxConstraints(
    minWidth: 2,
    maxWidth: 10,
    minHeight: 1,
    maxHeight: 5,
  );

  group('BoxConstraints', () {
    test('loose is at most the size, down to nothing', () {
      expect(
        const BoxConstraints.loose(8, 3),
        const BoxConstraints(maxWidth: 8, maxHeight: 3),
      );
    });

    test('expand is the biggest, or the size given along an axis', () {
      const all = BoxConstraints.expand();
      expect(all.hasInfiniteWidth && all.hasInfiniteHeight, isTrue);
      expect(
        const BoxConstraints.expand(width: 4),
        const BoxConstraints(
          minWidth: 4,
          maxWidth: 4,
          minHeight: unbounded,
        ),
      );
      // held within the parent's constraints it fills them
      expect(all.enforce(c), const BoxConstraints.tight(10, 5));
    });

    test('copyWith changes the bounds given and keeps the rest', () {
      expect(c.copyWith(), c);
      expect(
        c.copyWith(maxWidth: 20, minHeight: 0),
        const BoxConstraints(minWidth: 2, maxWidth: 20, maxHeight: 5),
      );
    });

    test('loosen drops the minimums', () {
      expect(c.loosen(), const BoxConstraints.loose(10, 5));
    });

    test('enforce brings every bound within the other constraints', () {
      const outer = BoxConstraints(
        minWidth: 4,
        maxWidth: 8,
        minHeight: 2,
        maxHeight: 3,
      );
      expect(c.enforce(outer), outer);
      expect(
        const BoxConstraints.loose(6, 2).enforce(outer),
        const BoxConstraints(
          minWidth: 4,
          maxWidth: 6,
          minHeight: 2,
          maxHeight: 2,
        ),
      );
    });

    test('tighten makes the axes given the one size, held within the '
        'bounds', () {
      expect(c.tighten(), c);
      expect(
        c.tighten(width: 6),
        const BoxConstraints(
          minWidth: 6,
          maxWidth: 6,
          minHeight: 1,
          maxHeight: 5,
        ),
      );
      expect(
        c.tighten(width: 99, height: 0),
        const BoxConstraints.tight(10, 1),
      );
    });

    test('deflate takes the insets off, none below 0, unbounded stays', () {
      expect(
        c.deflate(const EdgeInsets.symmetric(horizontal: 1, vertical: 1)),
        const BoxConstraints(maxWidth: 8, maxHeight: 3),
      );
      expect(
        c.deflate(const EdgeInsets.all(9)),
        const BoxConstraints.tight(0, 0),
      );
      expect(
        const BoxConstraints(minWidth: 3).deflate(const EdgeInsets.x(1)),
        const BoxConstraints(minWidth: 1),
      );
    });

    test('widthConstraints and heightConstraints keep one axis', () {
      expect(
        c.widthConstraints(),
        const BoxConstraints(minWidth: 2, maxWidth: 10),
      );
      expect(
        c.heightConstraints(),
        const BoxConstraints(minHeight: 1, maxHeight: 5),
      );
    });

    test('hasTight, hasBounded and hasInfinite say what the axes allow', () {
      const w = BoxConstraints.tightFor(width: 3);
      expect(
        [w.hasTightWidth, w.hasTightHeight, w.hasBoundedWidth],
        [true, false, true],
      );
      expect(w.hasBoundedHeight, isFalse);
      expect(c.hasBoundedWidth && c.hasBoundedHeight, isTrue);
      expect(c.hasInfiniteWidth || c.hasInfiniteHeight, isFalse);
      expect(const BoxConstraints.expand(height: 2).hasInfiniteWidth, isTrue);
      expect(const BoxConstraints.expand(height: 2).hasInfiniteHeight, isFalse);
    });

    test('biggest and smallest are the extremes', () {
      expect(c.biggest, (width: 10, height: 5));
      expect(c.smallest, (width: 2, height: 1));
    });
  });

  group('EdgeInsets', () {
    test('symmetric is the cells across and down, 0 unless given', () {
      expect(
        const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        const EdgeInsets.only(left: 2, right: 2, top: 1, bottom: 1),
      );
      expect(const EdgeInsets.symmetric(vertical: 1), const EdgeInsets.y(1));
      expect(const EdgeInsets.symmetric(horizontal: 3).top, 0);
    });

    test('fromLTRB takes left, top, right, bottom', () {
      const e = EdgeInsets.fromLTRB(1, 2, 3, 4);
      expect([e.left, e.top, e.right, e.bottom], [1, 2, 3, 4]);
    });
  });
}
