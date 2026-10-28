/// What the data tests draw on: a dot canvas shown on a [Shot] of its
/// own; and a widget that counts its paints.
library;

import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart' show Shot;

/// [draw] shown on a [RenderDotCanvas] of [width] × [height] cells of
/// [marker], whose data space is by default one unit per dot: x from 0 at
/// the leftmost dot, y from 0 at the lowest (from 0 to 1 along an axis of
/// one dot).
Shot drawn(
  int width,
  int height,
  DotDrawer draw, {
  Marker marker = Marker.braille,
  (double, double)? x,
  (double, double)? y,
  Color background = Color.defaultColor,
  int ambiguousWidth = 1,
  String? under,
}) => Shot.render(
  RenderDotCanvas(
    draw: draw,
    xBounds: x ?? (0, _last(width * marker.dotsAcross)),
    yBounds: y ?? (0, _last(height * marker.dotsDown)),
    marker: marker,
    background: background,
  ),
  width,
  height,
  ambiguousWidth: ambiguousWidth,
  under: under,
);

/// The data coordinate of the last of [dots] one unit apart; 1 for one.
double _last(int dots) => dots > 2 ? dots - 1 : 1;

/// Paints counted: how many times the [Counted] it is given painted.
final class PaintCount {
  var paints = 0;
}

/// One row of blanks as wide as it may be, which counts its paints in
/// [count]; what tells whether a neighbour repainted it.
final class Counted extends LeafRenderObjectWidget {
  const Counted(this.count);

  final PaintCount count;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCounted(count);
}

final class _RenderCounted extends RenderObject {
  _RenderCounted(this.count);

  final PaintCount count;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) => count.paints++;
}
