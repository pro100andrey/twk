// The contract of layout, held in debug mode: a size within the constraints,
// a child laid out before it is painted, no mark on an object from inside
// its own layout.
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
  });

  final int w;
  final int h;
  final bool lay;
  final bool markSelf;
  final bool raw;

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

  test('a well-behaved tree reports nothing', () {
    final reports = <String>[];
    frame(Box(10, 2)..child = Box(3, 1), reports);
    expect(reports, isEmpty);
  });
}
