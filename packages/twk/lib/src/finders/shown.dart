import 'package:twk_core/twk_core.dart' show RenderObject;

/// A rectangle of the screen's cells (of the inline region's, in the
/// inline mode): column and row of its first cell, and its size.
typedef ShownRect = ({int x, int y, int width, int height});

/// The cells of [target] the screen shows, in the coordinates of the root:
/// its bounds cut off where an ancestor cuts it off, as paint and a hit
/// test cut it; null when no cell is shown, or while it is detached.
///
/// ```dart
/// String where(RenderObject renderObject) => switch (shown(renderObject)) {
///   null => 'not shown',
///   (:final x, :final y, :final width, :final height) =>
///     '$width×$height at $x, $y',
/// };
/// ```
ShownRect? shown(RenderObject target) {
  if (target.owner == null) {
    return null;
  }
  final (gx, gy) = target.globalOffset;
  var x0 = gx;
  var y0 = gy;
  var x1 = gx + target.width;
  var y1 = gy + target.height;
  var ax = gx;
  var ay = gy;
  for (var o = target; o.parent != null; o = o.parent!) {
    ax -= o.parentData.dx;
    ay -= o.parentData.dy;
    final p = o.parent!;
    x0 = x0 > ax ? x0 : ax;
    y0 = y0 > ay ? y0 : ay;
    x1 = x1 < ax + p.width ? x1 : ax + p.width;
    y1 = y1 < ay + p.height ? y1 : ay + p.height;
  }
  return x0 < x1 && y0 < y1
      ? (x: x0, y: y0, width: x1 - x0, height: y1 - y0)
      : null;
}
