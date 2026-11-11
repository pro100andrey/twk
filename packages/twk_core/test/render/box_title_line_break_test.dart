// A box's title is one line: one with a line break draws whole without
// it, in the room measured for the whole text, as the canvas drew it.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// The top row of a 14 x 3 box titled [title].
String topRow(String title) {
  final screen = Screen(14, 3);
  PipelineOwner(() {}, segmenter: screen.canvas.segmenter)
    ..root = RenderDecoratedBox(
      border: const BoxBorder(
        top: Pen(),
        right: Pen(),
        bottom: Pen(),
        left: Pen(),
      ),
      titles: [BoxTitle(title)],
    )
    ..flushLayout(14, 3)
    ..flushPaint(PaintContext(screen.canvas, screen.surface, screen.presenter));
  final s = screen.surface;
  return [
    for (var x = 0; x < s.width; x++) screen.glyphs.stringOf(s.cells[x]),
  ].join();
}

void main() {
  PipelineOwner.debugCheckIntrinsicsByDefault = true;
  test('a title with a line break stays whole when its pen changes', () {
    final screen = Screen(14, 3);
    final box = RenderDecoratedBox(
      border: const BoxBorder.all(),
      titles: const [BoxTitle('ab\ncd')],
    );
    final owner = PipelineOwner(() {}, segmenter: screen.canvas.segmenter)
      ..root = box;
    String top() {
      owner
        ..flushLayout(14, 3)
        ..flushPaint(
          PaintContext(screen.canvas, screen.surface, screen.presenter),
        );
      final s = screen.surface;
      return [
        for (var x = 0; x < s.width; x++) screen.glyphs.stringOf(s.cells[x]),
      ].join();
    }

    final before = top();
    box.titles = const [BoxTitle('ab\ncd', pen: Pen(fg: Color.red))];
    expect(top(), before);
  });

  test('a title with line breaks draws whole without them', () {
    expect(topRow('ab\ncd'), topRow('abcd'));
    expect(topRow('ab\r\ncd'), topRow('abcd'));
    expect(topRow('ab cd'), topRow('abcd'));
    expect(topRow('abcd'), '┌abcd────────┐');
  });
}
