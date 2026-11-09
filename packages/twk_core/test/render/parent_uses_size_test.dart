// A parent that reads a child's size in its layout has to lay the child out
// with parentUsesSize: true, or the child is a relayout boundary and the
// parent's layout goes stale when the child resizes. Held in debug mode.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// Takes [w] x [h].
final class Leaf extends RenderObject {
  Leaf(this.w, this.h);
  int w;
  int h;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainWidth(w);
    height = c.constrainHeight(h);
  }

  @override
  void paint(PaintContext ctx) {}
}

/// Wraps its child, sizing itself by the child's width; lays the child out
/// with [usesSize] and reads the size when [read].
final class Wrap1 extends RenderObject with RenderObjectWithChildMixin {
  Wrap1({this.usesSize = false, this.read = true, this.tight = false});
  final bool usesSize;
  final bool read;
  final bool tight;

  @override
  void performLayout(BoxConstraints c) {
    final k = child!
      ..layout(
        tight ? const BoxConstraints.tight(3, 1) : c.loosen(),
        parentUsesSize: usesSize,
      );
    final w = read ? k.width : 1;
    final h = read ? k.height : 1;
    width = c.constrainWidth(w);
    height = c.constrainHeight(h);
  }

  @override
  void paint(PaintContext ctx) {
    final k = child!;
    // a read in paint is not a layout read
    final w = k.width;
    assert(w >= 0, 'a width');
    paintChild(ctx, k);
  }
}

List<String> frame(RenderObject root) {
  final reports = <String>[];
  final owner = PipelineOwner(() {})
    ..onError = (o, phase, error, stack) {
      reports.add('${phase.name}: $error');
    }
    ..root = root;
  final screen = Screen(20, 5);
  owner
    ..flushLayout(20, 5)
    ..flushPaint(PaintContext(screen.canvas, screen.surface, screen.presenter));
  return reports;
}

void main() {
  test(
    'a width read of a child laid out without parentUsesSize is refused',
    () {
      final reports = frame(Wrap1()..child = Leaf(4, 1));
      expect(reports, hasLength(1));
      expect(reports.single, contains('laid it out without parentUsesSize'));
      expect(reports.single, contains('width'));
    },
  );

  test('a child laid out with parentUsesSize may be read', () {
    final root = Wrap1(usesSize: true)..child = Leaf(4, 1);
    expect(frame(root), isEmpty);
    expect(root.child!.width, 4);
  });

  test('a parent that reads nothing needs no parentUsesSize', () {
    expect(frame(Wrap1(read: false)..child = Leaf(4, 1)), isEmpty);
  });

  test('a tight child can be read: its size cannot change', () {
    expect(frame(Wrap1(tight: true)..child = Leaf(4, 1)), isEmpty);
  });

  test('a parent reading its own size, or anything reading after layout, '
      'is fine', () {
    final root = Wrap1(read: false)..child = Leaf(4, 1);
    expect(frame(root), isEmpty);
    expect(root.child!.width, 4);
  });
}
