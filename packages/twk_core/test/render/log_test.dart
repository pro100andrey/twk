// A log holds the lines added to it and shows the last ones, following its
// end; scrolled back it stays where it was put as lines are added, until it
// is scrolled to the end again.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// A log filling a screen of [width] × [height] cells.
final class View {
  View(this.width, this.height) : screen = Screen(width, height) {
    final pen = screen.styles.pen(const Pen(bg: Color.rgb(0, 0, 0)));
    log = RenderLog(pen: pen, itemPen: (_, _) => pen);
    owner = PipelineOwner(() {})..root = log;
  }

  final int width;
  final int height;
  final Screen screen;
  late final RenderLog log;
  late final PipelineOwner owner;

  /// Lays out and paints what changed; returns the rows of the screen.
  List<String> frame() {
    owner
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    screen.render();
    return [
      for (var y = 0; y < height; y++)
        [
          for (var x = 0; x < width; x++)
            screen.glyphs.stringOf(screen.surface.cells[y * width + x]),
        ].join().trimRight(),
    ];
  }
}

void main() {
  test('holds the lines added and shows the last ones, following its end', () {
    final v = View(8, 2);
    expect(v.log.length, 0);
    v.log
      ..add('one')
      ..add('two')
      ..add('three');
    expect(v.log.length, 3);
    expect(v.frame(), [' two', ' three']);
    v.log.add('four');
    expect(v.frame(), [' three', ' four']);
  });

  test('scrolled back, it stays as lines are added, until scrolled to the '
      'end', () {
    final v = View(8, 2);
    for (final line in ['one', 'two', 'three']) {
      v.log.add(line);
    }
    v.frame();
    v.log.scrollBy(-1);
    expect(v.log.stickToEnd, isFalse);
    expect(v.frame(), [' one', ' two']);
    v.log.add('four');
    expect(v.frame(), [' one', ' two']);
    // kept within the lines: no further back than the first
    v.log.scrollBy(-5);
    expect(v.frame(), [' one', ' two']);
    v.log.scrollBy(5);
    expect(v.log.stickToEnd, isTrue);
    expect(v.frame(), [' three', ' four']);
  });
}
