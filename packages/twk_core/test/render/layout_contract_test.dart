// The contract of layout, held in debug mode: a size within the constraints,
// a child laid out before it is painted, a paint that keeps the canvas
// balanced, no mark on an object from inside its own layout or paint.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// Takes [w] x [h] (past the constraints when [raw]), and lays its child out
/// unless [lay] is false; marks itself in its layout when [markSelf].
final class Box extends RenderObject with RenderObjectWithChildMixin {
  Box(
    this.w,
    this.h, {
    this.lay = true,
    this.markSelf = false,
    this.raw = false,
    this.leak = false,
    this.paintMark = false,
  });

  final int w;
  final int h;
  final bool lay;
  final bool markSelf;
  final bool raw;
  final bool leak;

  /// Marks itself for paint inside its paint.
  bool paintMark;

  @override
  void performLayout(BoxConstraints c) {
    if (markSelf) {
      markNeedsLayout();
    }
    if (lay) {
      child?.layout(c.loosen());
    }
    width = raw ? w : c.constrainWidth(w);
    height = raw ? h : c.constrainHeight(h);
  }

  @override
  void paint(PaintContext ctx) {
    if (leak) {
      ctx.canvas.save();
    }
    if (paintMark) {
      markNeedsPaint();
    }
    final k = child;
    if (k != null) {
      paintChild(ctx, k);
    }
  }
}

PipelineOwner frame(RenderObject root, List<String> reports) {
  final owner = PipelineOwner(() {})
    ..onError = (o, phase, error, stack) {
      reports.add('${phase.name}: $error');
    }
    ..root = root;
  final screen = Screen(20, 5);
  owner
    ..flushLayout(20, 5)
    ..flushPaint(PaintContext(screen.canvas, screen.surface, screen.presenter));
  return owner;
}

void main() {
  PipelineOwner.debugCheckIntrinsicsByDefault = true;
  test('a size outside the constraints is refused', () {
    final reports = <String>[];
    final root = Box(10, 2)..child = Box(50, 1, raw: true);
    frame(root, reports);
    expect(reports.join(), contains('outside its constraints'));
  });

  test('a child painted before it was laid out is refused', () {
    final reports = <String>[];
    final root = Box(10, 2, lay: false)..child = Box(3, 1);
    frame(root, reports);
    expect(reports.join(), contains('before it was laid out'));
  });

  test('a mark on an object inside its own layout is refused', () {
    final reports = <String>[];
    frame(Box(10, 2, markSelf: true), reports);
    expect(reports.join(), contains('inside its own performLayout'));
  });

  test('a paint that marks itself in a row is refused', () {
    final reports = <String>[];
    final root = Box(10, 2, paintMark: true);
    final owner = frame(root, reports);
    final screen = Screen(20, 5);
    for (var i = 0; i < 3; i++) {
      owner.flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    }
    expect(reports.join(), contains('three paints in a row'));
  });

  test('a mark in a paint that settles is not refused', () {
    final reports = <String>[];
    final root = Box(10, 2, paintMark: true);
    final owner = frame(root, reports);
    final screen = Screen(20, 5);
    owner.flushPaint(
      PaintContext(screen.canvas, screen.surface, screen.presenter),
    );
    root.paintMark = false;
    for (var i = 0; i < 4; i++) {
      owner.flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    }
    expect(reports, isEmpty);
  });

  test('a paint that saves the canvas and does not restore is refused', () {
    final reports = <String>[];
    final root = Box(10, 2)..child = Box(3, 1, leak: true);
    frame(root, reports);
    expect(reports.join(), contains('unmatched by restore()'));
  });

  test('the canvas counts its saves by debugSaveDepth', () {
    final c = Screen(4, 2).canvas;
    expect(c.debugSaveDepth, 0);
    c
      ..save()
      ..save();
    expect(c.debugSaveDepth, 2);
    c.restore();
    expect(c.debugSaveDepth, 1);
  });

  test('a well-behaved tree reports nothing', () {
    final reports = <String>[];
    frame(Box(10, 2)..child = Box(3, 1), reports);
    expect(reports, isEmpty);
  });
}
