// A repaint boundary under a wide glyph of what covers it, which one of
// its sides cuts, is repainted as rows of the boundary above it: a
// boundary inside that one, marked for the same frame, whose rows those
// held is not painted again; one outside them is. A glyph of its own the
// clip of an ancestor cuts is no such glyph: it repaints on its own.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// A screen with a tree on it.
final class View {
  View(this.width, this.height, RenderObject root)
    : screen = Screen(width, height) {
    owner = PipelineOwner(() {}, segmenter: screen.canvas.segmenter)
      ..root = root;
  }

  final int width;
  final int height;
  final Screen screen;
  late final PipelineOwner owner;

  /// Lays out and paints what was marked; returns the rows of the screen,
  /// a wide glyph's second column left out.
  List<String> frame() {
    owner
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    screen.render();
    final cells = screen.surface.cells;
    return [
      for (var y = 0; y < height; y++)
        [
          for (var x = 0; x < width; x++)
            if (cells[y * width + x] & kCont == 0)
              screen.glyphs.stringOf(cells[y * width + x]),
        ].join(),
    ];
  }

  /// Expects the cells and the styles to be what a whole paint leaves.
  void expectAsWhole() {
    final s = screen.surface;
    final cells = List.of(s.cells);
    final styles = List.of(s.styles);
    owner.markAllDirty();
    frame();
    expect(cells, s.cells, reason: 'the cells a whole paint leaves');
    expect(styles, s.styles, reason: 'the styles a whole paint leaves');
  }
}

/// [text] on its first row over an opaque background in all the room it
/// gets, counting its paints; a repaint boundary unless [boundary] is off.
final class Panel extends RenderObject {
  Panel(this._text, {this.boundary = true});

  String _text;
  String get text => _text;
  set text(String t) {
    _text = t;
    markNeedsPaint();
  }

  final bool boundary;
  var paints = 0;

  @override
  bool get isRepaintBoundary => boundary;

  @override
  bool get sizedByParent => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) {
    paints++;
    final pen = ctx.canvas.styles.pen(const Pen(bg: Color.rgb(0, 0, 0)));
    ctx.canvas
      ..fill(0, 0, width, height, pen)
      ..text(0, 0, _text, pen);
  }
}

/// [width] columns wide, its child [childWidth]: wider, the child is cut
/// off at this object's right side.
final class Narrow extends RenderObject with RenderObjectWithChildMixin {
  Narrow(this.w, this.childWidth, RenderObject c) {
    child = c;
  }

  final int w;
  final int childWidth;

  @override
  void performLayout(BoxConstraints c) {
    width = w;
    height = c.maxH;
    child!.layout(BoxConstraints.tight(childWidth, height));
  }

  @override
  void paint(PaintContext ctx) => paintChild(ctx, child!);
}

/// A repaint boundary that fills its room and paints its child over it,
/// counting its paints.
final class Frame extends RenderObject with RenderObjectWithChildMixin {
  Frame(RenderObject c) {
    child = c;
  }

  var paints = 0;

  @override
  bool get isRepaintBoundary => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
    child!.layout(BoxConstraints.tight(width, height));
  }

  @override
  void paint(PaintContext ctx) {
    paints++;
    final pen = ctx.canvas.styles.pen(const Pen(bg: Color.rgb(0, 0, 0)));
    ctx.canvas.fill(0, 0, width, height, pen);
    paintChild(ctx, child!);
  }
}

/// [child] pinned as the named arguments say.
RenderObject pin(
  RenderObject child, {
  int? left,
  int? top,
  int? width,
  int? height,
}) {
  final at = StackParentData()
    ..left = left
    ..top = top
    ..width = width
    ..height = height;
  return child..parentData = at;
}

/// A stack in a [Frame]: the boundary [under] at the left of row 0, text
/// over it whose 你 its right side cuts, and [other], a boundary deeper
/// down than [under], at the right of row [otherRow].
Frame covered(Panel under, Panel other, {required int otherRow}) => Frame(
  RenderStack(
    children: [
      pin(under, left: 0, top: 0, width: 4, height: 1),
      // 你 at columns 3 and 4
      pin(Panel('ab你cd', boundary: false), left: 1, top: 0, width: 6),
      pin(Narrow(2, 2, other), left: 8, top: otherRow, height: 1),
    ],
  ),
);

void main() {
  test('a boundary marked with one under a wide glyph cut is not painted '
      'again when the rows repainted above held it', () {
    final under = Panel('.');
    final other = Panel('o');
    final frame = covered(under, other, otherRow: 0);
    final v = View(10, 2, frame);
    expect(v.frame()[0], '.ab你cd o ');
    final paints = (frame.paints, other.paints);
    under.text = ':';
    other.text = 'p';
    expect(v.frame()[0], ':ab你cd p ');
    // row 0 repainted across in the frame, the other boundary with it
    expect(frame.paints, paints.$1 + 1);
    expect(other.paints, paints.$2 + 1, reason: 'painted once');
    v.expectAsWhole();
  });

  test('one marked outside the rows repainted above repaints on its own', () {
    final under = Panel('.');
    final other = Panel('o');
    final frame = covered(under, other, otherRow: 1);
    final v = View(10, 2, frame);
    expect(v.frame(), ['.ab你cd   ', '        o ']);
    final paints = (frame.paints, other.paints);
    under.text = ':';
    other.text = 'p';
    expect(v.frame(), [':ab你cd   ', '        p ']);
    expect(frame.paints, paints.$1 + 1);
    expect(other.paints, paints.$2 + 1);
    v.expectAsWhole();
  });

  test('a boundary whose own wide glyph the clip of an ancestor cuts '
      'repaints on its own', () {
    final cut = Panel('abc你de');
    final frame = Frame(
      RenderStack(
        children: [
          // cut off after column 3: 你 at 3 and 4 shows as a blank
          pin(Narrow(4, 8, cut), left: 0, top: 0, height: 2),
          // over it, so that it is painted over
          pin(Panel('x', boundary: false), left: 1, top: 1, width: 1),
        ],
      ),
    );
    final v = View(10, 2, frame);
    expect(v.frame(), ['abc       ', ' x        ']);
    final paints = (frame.paints, cut.paints);
    cut.text = 'abd你de';
    expect(v.frame(), ['abd       ', ' x        ']);
    expect(frame.paints, paints.$1, reason: 'the frame is not repainted');
    expect(cut.paints, paints.$2 + 1);
    v.expectAsWhole();
  });
}
