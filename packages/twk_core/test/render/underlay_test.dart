// A repaint boundary that keeps an underlay paints over what its parent
// painted under it, also when it repaints on its own: the cells' styles
// it marked once (a selection) do not stay, the parent's background
// shows; where its parent has not painted since it moved, nothing is put
// back. One that keeps none keeps its old cells' colors.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// A row of [text] over what is under it, with no background of its own:
/// its first cell marked with [mark] while [marked].
final class _Leaf extends RenderObject {
  _Leaf(this.text, this.ink, this.mark, {required this.underlay});

  String text;
  final int ink;
  final int mark;
  final bool underlay;
  var marked = false;

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get keepsUnderlay => underlay;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = 1;
  }

  @override
  void paint(PaintContext ctx) {
    ctx.canvas
      ..fill(0, 0, width, height, ink)
      ..text(0, 0, text, ink);
    if (marked) {
      ctx.canvas.fill(0, 0, 1, 1, mark);
    }
  }
}

/// [leaf] on a box of [background], a column in, on a screen 10 × 3.
final class _View {
  _View({required bool underlay}) : screen = Screen(10, 3) {
    final styles = screen.styles;
    background = styles.pen(const Pen(bg: Color.rgb(0x22, 0x25, 0x2c)));
    leaf = _Leaf(
      'ab',
      styles.pen(const Pen(fg: Color.rgb(0xe6, 0xe8, 0xeb))),
      styles.pen(const Pen(bg: Color.rgb(0x2b, 0x45, 0x66))),
      underlay: underlay,
    );
    box = RenderBox(pen: background, padX: 1, padY: 1, child: leaf);
    owner = PipelineOwner(() {}, segmenter: screen.canvas.segmenter)
      ..root = box;
  }

  final Screen screen;
  late final int background;
  late final _Leaf leaf;
  late final RenderBox box;
  late final PipelineOwner owner;

  void frame() => owner
    ..flushLayout(10, 3)
    ..flushPaint(
      PaintContext(screen.canvas, screen.surface, screen.presenter),
    );

  /// The background of the cell [x], [y].
  Color bgAt(int x, int y) =>
      screen.styles.bgOf(screen.surface.styles[y * 10 + x]);
}

const _box = Color.rgb(0x22, 0x25, 0x2c);
const _mark = Color.rgb(0x2b, 0x45, 0x66);

void main() {
  test("on its parent's background, painted with it and on its own", () {
    final v = _View(underlay: true)..frame();
    expect(v.bgAt(1, 1), _box);
    expect(v.bgAt(5, 1), _box);
    v.leaf
      ..marked = true
      ..markNeedsPaint();
    v.frame();
    expect(v.bgAt(1, 1), _mark);
    // repainted on its own, unmarked: the box's background again
    v.leaf
      ..marked = false
      ..text = 'abc'
      ..markNeedsPaint();
    v.frame();
    expect(v.bgAt(1, 1), _box);
    expect(v.bgAt(2, 1), _box);
  });

  test('without an underlay its old colors stay: why it is kept', () {
    final v = _View(underlay: false)..frame();
    v.leaf
      ..marked = true
      ..markNeedsPaint();
    v.frame();
    v.leaf
      ..marked = false
      ..markNeedsPaint();
    v.frame();
    expect(v.bgAt(1, 1), _mark);
  });

  test("follows its parent's background when the parent repaints", () {
    final v = _View(underlay: true)..frame();
    v.box.pen = v.screen.styles.pen(const Pen(bg: Color.rgb(9, 9, 9)));
    v.frame();
    v.leaf
      ..text = 'x'
      ..markNeedsPaint();
    v.frame();
    expect(v.bgAt(1, 1), const Color.rgb(9, 9, 9));
    expect(v.bgAt(4, 1), const Color.rgb(9, 9, 9));
  });
}
