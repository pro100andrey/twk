/// Drawing into a [DotGrid] in data coordinates: [DotPainter] and the
/// [Shape]s drawn with it.
library;

import 'dart:math' as math;

import 'package:twk_core/twk_core.dart' show Color;

import 'dot_grid.dart';

/// Sets the dots of a [DotGrid] at points of a data space: x grows to the
/// right from [xBounds].$1 to [xBounds].$2, y upwards from [yBounds].$1 to
/// [yBounds].$2. The bounds fall on the outermost dots, a point between
/// dots on the nearest; nothing outside the bounds is drawn.
final class DotPainter {
  /// Draws into [grid], sized already, between [xBounds] and [yBounds]:
  /// bounds that enclose no space draw nothing.
  DotPainter(this.grid, this.xBounds, this.yBounds)
    : _sx = (grid.width - 1) / (xBounds.$2 - xBounds.$1),
      _sy = (grid.height - 1) / (yBounds.$2 - yBounds.$1),
      _valid =
          xBounds.$2 > xBounds.$1 &&
          yBounds.$2 > yBounds.$1 &&
          (xBounds.$2 - xBounds.$1).isFinite &&
          (yBounds.$2 - yBounds.$1).isFinite &&
          grid.width > 0 &&
          grid.height > 0;

  /// What the dots are set in.
  final DotGrid grid;

  /// The left and right ends of the x axis.
  final (double, double) xBounds;

  /// The bottom and top ends of the y axis.
  final (double, double) yBounds;

  // dots per data unit across and down
  final double _sx;
  final double _sy;

  // the bounds enclose some space and the grid some dots
  final bool _valid;

  /// Whether ([x], [y]) is within the bounds.
  bool _inside(double x, double y) =>
      _valid &&
      x >= xBounds.$1 &&
      x <= xBounds.$2 &&
      y >= yBounds.$1 &&
      y <= yBounds.$2;

  /// Dots across from the left to [x], a fraction between dots.
  double _across(double x) => (x - xBounds.$1) * _sx;

  /// Dots down from the top to [y], a fraction between dots.
  double _down(double y) => (yBounds.$2 - y) * _sy;

  /// The dot ([x], [y]) falls on, across and down from the top left; null
  /// outside the bounds.
  (int, int)? dotAt(double x, double y) =>
      _inside(x, y) ? (_across(x).round(), _down(y).round()) : null;

  /// Sets the dot [x] across and [y] down from the top left.
  void dot(int x, int y, Color color) => grid.set(x, y, color);

  /// Sets the dot ([x], [y]) falls on.
  void point(double x, double y, Color color) {
    if (_inside(x, y)) {
      grid.set(_across(x).round(), _down(y).round(), color);
    }
  }

  /// Sets the dots on the line from ([x1], [y1]) to ([x2], [y2]), as far as
  /// it runs inside the bounds.
  void line(double x1, double y1, double x2, double y2, Color color) {
    if (_valid) {
      _segment(_across(x1), _down(y1), _across(x2), _down(y2), color);
    }
  }

  // the part of a segment inside the grid, as fractions of its length
  var _t0 = 0.0;
  var _t1 = 1.0;

  /// Sets the dots nearest the segment from ([ax], [ay]) to ([bx], [by]),
  /// in dots from the top left, as far as it runs inside the grid.
  void _segment(double ax, double ay, double bx, double by, Color color) {
    if (!(ax.isFinite && ay.isFinite && bx.isFinite && by.isFinite)) {
      return;
    }
    // Liang-Barsky: cut the segment to the dots' rectangle
    final dx = bx - ax;
    final dy = by - ay;
    _t0 = 0.0;
    _t1 = 1.0;
    if (!_clip(-dx, ax) ||
        !_clip(dx, grid.width - 1 - ax) ||
        !_clip(-dy, ay) ||
        !_clip(dy, grid.height - 1 - ay)) {
      return;
    }
    var x = (ax + _t0 * dx).round();
    var y = (ay + _t0 * dy).round();
    final x1 = (ax + _t1 * dx).round();
    final y1 = (ay + _t1 * dy).round();
    // Bresenham
    final sx = x < x1 ? 1 : -1;
    final sy = y < y1 ? 1 : -1;
    final ex = (x1 - x).abs();
    final ey = -(y1 - y).abs();
    var err = ex + ey;
    while (true) {
      grid.set(x, y, color);
      if (x == x1 && y == y1) {
        return;
      }
      final e2 = 2 * err;
      if (e2 >= ey) {
        err += ey;
        x += sx;
      }
      if (e2 <= ex) {
        err += ex;
        y += sy;
      }
    }
  }

  /// Narrows [_t0, _t1] to where `p * t <= q`; false when nothing is left.
  bool _clip(double p, double q) {
    if (p == 0) {
      return q >= 0;
    }
    final r = q / p;
    if (p < 0) {
      if (r > _t1) {
        return false;
      }
      if (r > _t0) {
        _t0 = r;
      }
    } else {
      if (r < _t0) {
        return false;
      }
      if (r < _t1) {
        _t1 = r;
      }
    }
    return true;
  }
}

/// Something drawn on a [DotPainter] in its data coordinates. Those made
/// here are drawn in their `color`, by default the terminal's text color.
abstract class Shape {
  /// A shape of a subclass, which sets its dots in [draw].
  const Shape();

  /// A dot at each of [points].
  const factory Shape.points(List<(double, double)> points, {Color color}) =
      _Points;

  /// The line from ([x1], [y1]) to ([x2], [y2]).
  const factory Shape.line(
    double x1,
    double y1,
    double x2,
    double y2, {
    Color color,
  }) = _Line;

  /// The outline of the rectangle [width] wide and [height] tall whose
  /// bottom left corner is ([x], [y]).
  const factory Shape.rectangle(
    double x,
    double y,
    double width,
    double height, {
    Color color,
  }) = _Rectangle;

  /// The circle of [radius] around ([x], [y]), round in data coordinates
  /// (an ellipse on screen where the axes scale apart).
  const factory Shape.circle(
    double x,
    double y,
    double radius, {
    Color color,
  }) = _Circle;

  /// Lines from each of [points] to the next; a dot for one point.
  const factory Shape.polyline(List<(double, double)> points, {Color color}) =
      _Polyline;

  /// Sets the dots of this shape on [painter].
  void draw(DotPainter painter);
}

final class _Points extends Shape {
  const _Points(this.points, {this.color = Color.defaultColor});

  final List<(double, double)> points;
  final Color color;

  @override
  void draw(DotPainter painter) {
    for (final (x, y) in points) {
      painter.point(x, y, color);
    }
  }
}

final class _Line extends Shape {
  const _Line(
    this.x1,
    this.y1,
    this.x2,
    this.y2, {
    this.color = Color.defaultColor,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final Color color;

  @override
  void draw(DotPainter painter) => painter.line(x1, y1, x2, y2, color);
}

final class _Rectangle extends Shape {
  const _Rectangle(
    this.x,
    this.y,
    this.width,
    this.height, {
    this.color = Color.defaultColor,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final Color color;

  @override
  void draw(DotPainter painter) {
    final right = x + width;
    final top = y + height;
    painter
      ..line(x, y, right, y, color)
      ..line(right, y, right, top, color)
      ..line(right, top, x, top, color)
      ..line(x, top, x, y, color);
  }
}

// the most sides a circle is drawn with
const int _maxSides = 1 << 14;

final class _Circle extends Shape {
  const _Circle(this.x, this.y, this.radius, {this.color = Color.defaultColor});

  final double x;
  final double y;
  final double radius;
  final Color color;

  @override
  void draw(DotPainter painter) {
    if (!painter._valid || !(radius >= 0 && radius.isFinite)) {
      return;
    }
    final cx = painter._across(x);
    final cy = painter._down(y);
    final rx = radius * painter._sx;
    final ry = radius * painter._sy;
    final r = math.max(rx, ry);
    if (!(r < 0.5)) {
      // a polygon whose sides stray at most a quarter dot from the circle
      final n = math.pi / math.acos(1 - 0.25 / r);
      final sides = n < _maxSides ? math.max(16, n.ceil()) : _maxSides;
      var px = cx + rx;
      var py = cy;
      for (var k = 1; k <= sides; k++) {
        final a = 2 * math.pi * k / sides;
        final qx = cx + rx * math.cos(a);
        final qy = cy - ry * math.sin(a);
        painter._segment(px, py, qx, qy, color);
        px = qx;
        py = qy;
      }
    } else if (cx.isFinite && cy.isFinite) {
      painter.dot(cx.round(), cy.round(), color);
    }
  }
}

final class _Polyline extends Shape {
  const _Polyline(this.points, {this.color = Color.defaultColor});

  final List<(double, double)> points;
  final Color color;

  @override
  void draw(DotPainter painter) {
    if (points.length == 1) {
      final (x, y) = points.single;
      painter.point(x, y, color);
    }
    for (var i = 1; i < points.length; i++) {
      final (x1, y1) = points[i - 1];
      final (x2, y2) = points[i];
      painter.line(x1, y1, x2, y2, color);
    }
  }
}
