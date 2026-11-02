// The pipeline's lists of marked boundaries and Surface.pendingScrolls keep
// their storage from frame to frame (a growable list's clear gives it up,
// and the next frame grows a new one): through frames that mark few and
// many, every mark is served exactly once and nothing is left over.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

final class _Cell extends RenderObject {
  var paints = 0;

  @override
  bool get isRepaintBoundary => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW < BoxConstraints.unbounded ? c.maxW : 8;
    height = 1;
  }

  @override
  void paint(PaintContext ctx) => paints++;
}

void main() {
  test(
    'boundaries marked in frames of 1, 70, 3 and 70 are painted once each',
    () {
      final cells = [for (var i = 0; i < 70; i++) _Cell()];
      final screen = Screen(8, 70);
      final owner = PipelineOwner(() {})
        ..root = RenderColumn([for (final c in cells) (c, 1)]);
      void frame() {
        owner
          ..flushLayout(8, 70)
          ..flushPaint(
            PaintContext(screen.canvas, screen.surface, screen.presenter),
          );
      }

      frame();
      expect(cells.map((c) => c.paints), everyElement(1));
      for (final marked in [1, 70, 3, 70]) {
        final before = [for (final c in cells) c.paints];
        // the deepest first: the order they are marked in is not the order
        // they are painted in
        for (var i = marked - 1; i >= 0; i--) {
          cells[i].markNeedsPaint();
        }
        frame();
        expect(owner.dirtyBoundaries, 0);
        expect(owner.hasWork, isFalse);
        for (var i = 0; i < 70; i++) {
          expect(
            cells[i].paints,
            before[i] + (i < marked ? 1 : 0),
            reason: '$i',
          );
        }
      }
    },
  );

  test('pendingScrolls holds the moves of a frame, grown past its start', () {
    final s = Surface(10, 40);
    for (final moves in [1, 20, 2, 20]) {
      for (var i = 0; i < moves; i++) {
        s.scrollRows(i, i + 10, 1);
      }
      expect(s.pendingScrolls, hasLength(moves * 5));
      expect(s.pendingScrolls.sublist((moves - 1) * 5), [
        moves - 1,
        moves + 9,
        1,
        0,
        10,
      ]);
      s.clearDamage();
      expect(s.pendingScrolls, isEmpty);
    }
  });
}
