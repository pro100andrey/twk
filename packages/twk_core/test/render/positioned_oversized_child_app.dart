// Prints what a RenderPositionedBox shows of a child bigger than it can be
// (7 × 3 in 3 × 1 cells), centred and then at the top left, and the child's
// offset: `dart run` has asserts off, which the test of it relies on, as the
// size-within-constraints assert forbids such a child.
//
//   dart run test/render/positioned_oversized_child_app.dart
import 'dart:io';

import 'package:twk_core/twk_core.dart';

final class _Stubborn extends RenderObject {
  _Stubborn(this.text, this.w, this.h);

  final String text;
  final int w;
  final int h;

  @override
  void performLayout(BoxConstraints c) {
    width = w;
    height = h;
  }

  @override
  void paint(PaintContext ctx) {
    final pen = ctx.canvas.styles.pen(const Pen());
    for (var y = 0; y < h; y++) {
      ctx.canvas.text(0, y, text, pen);
    }
  }
}

void main() {
  var asserts = false;
  assert(asserts = true, 'finds out');
  final screen = Screen(9, 3);
  final child = _Stubborn('abcdefg', 7, 3);
  final box = RenderPositionedBox(child: child);
  // three columns and one row in the middle of the screen
  final owner = PipelineOwner(() {}, segmenter: screen.canvas.segmenter)
    ..root = RenderPadding(
      padding: const EdgeInsets.only(left: 3, top: 1, right: 3, bottom: 1),
      child: box,
    );

  void frame() {
    owner
      ..flushLayout(9, 3)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    screen.render();
    for (var y = 0; y < 3; y++) {
      stdout.writeln(
        [
          for (var x = 0; x < 9; x++)
            screen.glyphs.stringOf(screen.surface.cells[y * 9 + x]),
        ].join().trimRight(),
      );
    }
  }

  stdout.writeln('asserts=$asserts');
  frame();
  stdout.writeln('dx=${child.parentData.dx}');
  box.alignment = Alignment.topLeft;
  frame();
}
