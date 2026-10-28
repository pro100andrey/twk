/// What the highlighting tests show widgets on: a screen of their own,
/// built, laid out and painted as a frame does, read cell by cell.
library;

import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show PaintContext, PipelineOwner, Screen, kCont;

/// A widget tree on a screen of [width] × [height] cells, whose canvas
/// takes ambiguous characters as `ambiguousWidth` columns.
final class Painted {
  Painted(Widget widget, this.width, this.height, {int ambiguousWidth = 1})
    : screen = Screen(width, height, ambiguousWidth: ambiguousWidth) {
    pump(widget);
  }

  final int width;
  final int height;
  final Screen screen;
  final _owner = BuildOwner();
  late final _pipeline = PipelineOwner(
    () {},
    segmenter: screen.canvas.segmenter,
  );
  RootElement? _root;
  RenderObject? _top;

  /// Shows [widget]: builds what is dirty, lays out and paints what
  /// changed, and renders the frame.
  void pump(Widget widget) {
    _root = RootWidget(child: widget).attach(_owner, _root);
    _owner.buildScope();
    final top = _root!.renderObject!;
    if (!identical(top, _top)) {
      _pipeline.root = top;
      _top = top;
    }
    _pipeline
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    _owner.finalizeTree();
    screen.render();
  }

  /// The rows of the screen, without the blanks that end them.
  List<String> get rows => [
    for (var y = 0; y < height; y++)
      [
        for (var x = 0; x < width; x++)
          if (_cell(x, y) & kCont == 0) screen.glyphs.stringOf(_cell(x, y)),
      ].join().trimRight(),
  ];

  /// The text color of the cell at [x], [y].
  Color fg(int x, int y) => screen.styles.fgOf(_style(x, y));

  /// The [Attr] bits of the cell at [x], [y].
  int attrs(int x, int y) => screen.styles.attrsOf(_style(x, y));

  int _cell(int x, int y) => screen.surface.cells[y * width + x];
  int _style(int x, int y) => screen.surface.styles[y * width + x];
}
