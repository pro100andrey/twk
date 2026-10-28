// What every render object has: constraints that are values, a list of
// children kept in order, a hit test result reused between events, flags
// that change how it is painted, a check before each paint, and layout
// callbacks that may change what a parent asked of it.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// As wide as [columns] says it would like to be, which a layout callback
/// may change; one row tall.
final class Grower extends RenderObject {
  Grower(this.columns);

  int columns;

  @override
  int computeMaxIntrinsicWidth(int height) => columns;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(columns);
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) {}
}

/// Counts the times it was checked before a paint.
final class Checked extends RenderObject {
  var checks = 0;

  @override
  void beforePaint() => checks++;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) {}
}

/// Lays the tree of [owner] out and paints it on [screen], [w] × [h]
/// cells.
void frame(PipelineOwner owner, Screen screen, int w, int h) => owner
  ..flushLayout(w, h)
  ..flushPaint(PaintContext(screen.canvas, screen.surface, screen.presenter));

void main() {
  group('BoxConstraints', () {
    test('are equal, with equal hashes, when their limits are', () {
      const a = BoxConstraints(0, 10, 1, 5);
      expect(a, const BoxConstraints(0, 10, 1, 5));
      expect(a.hashCode, const BoxConstraints(0, 10, 1, 5).hashCode);
      expect(a, isNot(const BoxConstraints(0, 10, 1, 6)));
      expect(
        const BoxConstraints.tightFor(width: 3),
        const BoxConstraints(3, 3, 0, BoxConstraints.unbounded),
      );
    });

    test('hold a size between their limits', () {
      const c = BoxConstraints(2, 10, 1, 5);
      expect([c.constrainW(0), c.constrainW(7), c.constrainW(99)], [2, 7, 10]);
      expect([c.constrainH(0), c.constrainH(3), c.constrainH(99)], [1, 3, 5]);
      expect(c.isTight, isFalse);
      expect(const BoxConstraints.tight(4, 2).isTight, isTrue);
    });
  });

  group('a list of children', () {
    test('refuses to put a child after an object that is not one', () {
      final flex = RenderFlex(children: [Grower(1)]);
      final stranger = Grower(1);
      expect(
        () => flex.insert(Grower(1), after: stranger),
        throwsA(
          isA<AssertionError>().having(
            (e) => '${e.message}',
            'message',
            contains('is not a child of'),
          ),
        ),
      );
      expect(
        () => flex.move(flex.firstChild!, after: stranger),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  test('a hit test result is empty until an object is hit, and again once '
      'reset', () {
    final result = HitTestResult();
    expect(result.isEmpty, isTrue);
    final grower = Grower(3)..layout(const BoxConstraints.tight(3, 1));
    final owner = PipelineOwner(() {})
      ..root = grower
      ..hitTest(result, 1, 0);
    expect(result.isEmpty, isFalse);
    owner.hitTest(result, 5, 0);
    expect(result.isEmpty, isTrue);
  });

  test('its paint flags read back as set, off by default', () {
    final o = Grower(1);
    expect((o.paintedWhenCutOff, o.repaintedWhole), (false, false));
    o
      ..paintedWhenCutOff = true
      ..repaintedWhole = true;
    expect((o.paintedWhenCutOff, o.repaintedWhole), (true, true));
  });

  test('checked before each paint while it is attached and says so, from '
      'the moment it does', () {
    final screen = Screen(4, 1);
    final checked = Checked();
    final owner = PipelineOwner(() {})..root = checked;
    frame(owner, screen, 4, 1);
    expect(checked.checkedBeforePaint, isFalse);
    expect(checked.checks, 0);
    checked
      ..checkedBeforePaint = true
      ..markNeedsPaint();
    frame(owner, screen, 4, 1);
    expect(checked.checks, 1);
    checked
      ..checkedBeforePaint = false
      ..markNeedsPaint();
    frame(owner, screen, 4, 1);
    expect(checked.checks, 1);
  });

  test('checked before each paint, an object that does nothing then '
      'paints as it would', () {
    final screen = Screen(4, 1);
    final text = RenderText('ab', 0)..checkedBeforePaint = true;
    final owner = PipelineOwner(() {})..root = text;
    frame(owner, screen, 4, 1);
    expect(screen.glyphs.stringOf(screen.surface.cells[1]), 'b');
  });

  test('a layout callback outside a frame that changes what a parent asked '
      'for marks the parent for layout', () {
    final grower = Grower(2);
    final parent = RenderPadding(padding: EdgeInsets.zero, child: grower)
      ..layout(const BoxConstraints(0, 10, 0, 1), parentUsesSize: true);
    expect(parent.getMaxIntrinsicWidth(1), 2);
    expect(parent.debugNeedsLayout, isFalse);
    grower.invokeLayoutCallback(() => grower.columns = 5);
    expect(parent.debugNeedsLayout, isTrue);
    expect(parent.getMaxIntrinsicWidth(1), 5);
  });

  test('a layout callback that changes nothing asked for leaves the parent '
      'alone', () {
    final grower = Grower(2);
    final parent = RenderPadding(padding: EdgeInsets.zero, child: grower)
      ..layout(const BoxConstraints(0, 10, 0, 1), parentUsesSize: true);
    expect(parent.getMaxIntrinsicWidth(1), 2);
    grower.invokeLayoutCallback(() {});
    expect(parent.debugNeedsLayout, isFalse);
  });
}
