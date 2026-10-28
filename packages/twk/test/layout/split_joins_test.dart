// A split view filling a pane of a split view across it, laid out on its
// own, has the outer view's dividers beside that pane painted again only
// when the joints they draw with its dividers changed: its dividers moved,
// or it no longer joins them. What repainted is told by a cell scribbled
// over on the screen between frames: a repaint draws it again.
import 'package:test/test.dart';
import 'package:twk/twk.dart';

import 'view.dart';

SplitPane pane(String char, {int minSize = 1}) =>
    SplitPane(child: Fill(char), minSize: minSize);

/// Panes `a` and `b` along [direction], the least of `a` [minSize], over
/// a pane `c` of a split view one below another.
Widget nested({
  required int minSize,
  Axis direction = Axis.horizontal,
  SplitController? controller,
}) => SplitView(
  direction: Axis.vertical,
  panes: [
    SplitPane(
      child: SplitView(
        direction: direction,
        controller: controller,
        panes: [
          pane('a', minSize: minSize),
          pane('b'),
        ],
      ),
    ),
    pane('c'),
  ],
);

/// Writes `X` over the cell at ([x], [y]) of [view]'s screen, outside of
/// any frame.
void scribble(View view, int x, int y) {
  final canvas = view.screen.canvas;
  canvas.text(x, y, 'X', canvas.styles.pen(const Pen()));
}

void main() {
  test('a relayout of the inner view that keeps its dividers repaints no '
      'outer divider', () {
    final view = View(9, 5)
      ..pump(Toggle(() => nested(minSize: 1), () => nested(minSize: 2)));
    expect(view.rows(), [
      'aaaa│bbbb',
      'aaaa│bbbb',
      '────┴────',
      'ccccccccc',
      'ccccccccc',
    ]);
    scribble(view, 0, 2);
    // a least that binds nothing: only the inner view is laid out again
    toggleIn(view.root).toggle();
    view.frame();
    expect(view.rows(), [
      'aaaa│bbbb',
      'aaaa│bbbb',
      'X───┴────',
      'ccccccccc',
      'ccccccccc',
    ]);
  });

  test('an inner divider moved redraws the joint where it now meets', () {
    final controller = SplitController();
    addTearDown(controller.dispose);
    final view = View(9, 5)..pump(nested(minSize: 1, controller: controller));
    expect(view.rows()[2], '────┴────');
    scribble(view, 0, 2);
    controller.fractions = [0.75, 0.25];
    view.frame();
    expect(view.rows(), [
      'aaaaaa│bb',
      'aaaaaa│bb',
      '──────┴──',
      'ccccccccc',
      'ccccccccc',
    ]);
  });

  test('an inner view turned along the outer one leaves the joint', () {
    final view = View(9, 5)
      ..pump(
        Toggle(
          () => nested(minSize: 1),
          () => nested(minSize: 1, direction: Axis.vertical),
        ),
      );
    expect(view.rows()[2], '────┴────');
    toggleIn(view.root).toggle();
    view.frame();
    expect(view.rows()[2], '─────────');
  });
}
