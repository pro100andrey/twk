// Prints the rows of a row that overflows by 2 columns, drawn with the
// overflow marker turned on, as the process runs: `dart run` has asserts
// off, which overflow_no_asserts_test.dart relies on.
//
//   dart run test/render/overflow_no_asserts_app.dart
import 'dart:io';

import 'package:twk_core/twk_core.dart';

final class _Label extends RenderObject {
  _Label(this.text);

  final String text;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainWidth(text.length);
    height = c.constrainHeight(1);
  }

  @override
  void paint(PaintContext ctx) =>
      ctx.canvas.text(0, 0, text, ctx.canvas.styles.pen(const Pen()));
}

void main() {
  var asserts = false;
  assert(asserts = true, 'finds out');
  final screen = Screen(6, 2);
  final owner = PipelineOwner(() {}, segmenter: screen.canvas.segmenter)
    ..debugOverflowIndicator = true
    ..root = RenderFlex(children: [_Label('abcd'), _Label('efgh')])
    ..flushLayout(6, 2)
    ..flushPaint(PaintContext(screen.canvas, screen.surface, screen.presenter));
  screen.render();
  stdout.writeln('asserts=$asserts');
  for (var y = 0; y < 2; y++) {
    stdout.writeln(
      [
        for (var x = 0; x < 6; x++)
          screen.glyphs.stringOf(screen.surface.cells[y * 6 + x]),
      ].join().trimRight(),
    );
  }
  stdout.writeln(owner.debugOverflowIndicator);
}
