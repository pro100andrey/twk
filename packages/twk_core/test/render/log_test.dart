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
  test('a line added below a log scrolled back asks for no paint, and shows '
      'when scrolled into view', () {
    final v = View(8, 2);
    v.log
      ..add('one')
      ..add('two')
      ..add('three');
    v.frame();
    v.log.scrollBy(-1);
    expect(v.frame(), [' one', ' two']);
    v.log.add('four');
    expect(v.owner.hasWork, isFalse);
    expect(v.frame(), [' one', ' two']);
    v.log.scrollBy(2);
    expect(v.frame(), [' three', ' four']);
  });

  test('a line added inside the window of a log scrolled back is painted', () {
    final v = View(8, 3);
    v.log.add('one');
    v.frame();
    v.log.add('two');
    expect(v.owner.hasWork, isTrue);
    expect(v.frame(), [' one', ' two', '']);
  });

  test(
    'a fill of no foreground takes none from the lines that scrolled away',
    () {
      final screen = Screen(10, 4);
      final red = screen.styles.pen(const Pen(fg: Color.rgb(255, 0, 0)));
      final plain = screen.styles.pen(const Pen());
      final log = RenderLog(
        pen: screen.styles.pen(const Pen(bg: Color.rgb(0, 0, 40))),
        itemPen: (i, _) => i < 3 ? red : plain,
      );
      final owner = PipelineOwner(() {})
        ..root = RenderColumn([(log, 3), (RenderText('-', plain), 1)]);
      void frame() {
        owner
          ..flushLayout(10, 4)
          ..flushPaint(
            PaintContext(screen.canvas, screen.surface, screen.presenter),
          );
        screen.render();
      }

      for (var i = 0; i < 3; i++) {
        log.add('red $i');
      }
      frame();
      for (var i = 3; i < 6; i++) {
        log.add('line $i');
      }
      frame();
      final scrolled = screen.surface.styles[1];
      owner.markAllDirty();
      frame();
      expect(scrolled, screen.surface.styles[1]);
    },
  );

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
