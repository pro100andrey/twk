// A painter that writes Surface.cells itself and splits a wide glyph is
// caught in debug mode at the end of the paint flush, before the presenter
// diffs the surface.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// Paints [write] onto the surface's cells directly and damages row 0.
final class Raw extends RenderObject {
  Raw(this.write);

  final void Function(Surface s) write;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainWidth(10);
    height = c.constrainHeight(1);
  }

  @override
  void paint(PaintContext ctx) {
    write(ctx.surface);
    ctx.surface.markDirty(0, 0, 10);
  }
}

void paintRaw(void Function(Surface s) write) {
  final owner = PipelineOwner(() {})..root = Raw(write);
  final screen = Screen(10, 2);
  owner
    ..flushLayout(10, 2)
    ..flushPaint(PaintContext(screen.canvas, screen.surface, screen.presenter));
}

Matcher splits(String part) => throwsA(
  isA<AssertionError>().having(
    (e) => e.message,
    'message',
    allOf(contains(part), contains('breakWideAt')),
  ),
);

void main() {
  PipelineOwner.debugCheckIntrinsicsByDefault = true;
  test('a whole wide glyph is fine', () {
    paintRaw((s) {
      s.cells[2] = 0x4e2d | kWide;
      s.cells[3] = kCont;
    });
  });

  test('a wide glyph the canvas cuts at the edge is blanked, not split', () {
    final screen = Screen(10, 2);
    PipelineOwner(() {})
      ..root = Raw((s) {
        screen.canvas.text(9, 0, '中', 0);
      })
      ..flushLayout(10, 2)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
  });

  test('a wide cell without its continuation is caught', () {
    expect(
      () => paintRaw((s) => s.cells[2] = 0x4e2d | kWide),
      splits('no continuation cell'),
    );
  });

  test('a wide cell at the last column is caught', () {
    expect(
      () => paintRaw((s) => s.cells[9] = 0x4e2d | kWide),
      splits('last column'),
    );
  });

  test('an orphan continuation cell is caught', () {
    expect(
      () => paintRaw((s) => s.cells[4] = kCont),
      splits('no wide glyph'),
    );
  });

  test('a half overwritten beside the damage is caught', () {
    expect(
      () => paintRaw((s) {
        s
          ..cells[0] = 0x4e2d | kWide
          ..cells[1] = kCont
          ..clearDamage()
          ..cells[0] = kBlank
          ..markDirty(0, 0, 1);
      }),
      splits('no wide glyph'),
    );
  });
}
