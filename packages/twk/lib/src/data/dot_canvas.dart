/// A drawing surface finer than the cells: [DotCanvas], what it draws with
/// ([DotContext]) and its render object ([RenderDotCanvas]).
library;

import 'package:twk_core/twk_core.dart'
    show BoxConstraints, Canvas, Color, PaintContext, RenderObject;

import '../framework/framework.dart';
import '../style/style.dart';
import 'chart_glyphs.dart';
import 'dot_grid.dart';
import 'dot_painter.dart';
import 'marker.dart';

/// What a [DotCanvas] draws on each paint.
typedef DotDrawer = void Function(DotContext context);

/// Shapes and labels drawn finer than the cells: [draw] sets dots at
/// points of a data space ([xBounds] across, [yBounds] upwards), which
/// [marker] shows several to a cell. As big as it may be; a repaint
/// boundary that paints every cell, the blank ones in [background], the
/// labels whose style sets no text color in the theme's
/// ([ThemeData.text]).
///
/// A circle in a square, its center named, on a space 10 units each way:
///
/// ```dart
/// DotCanvas(
///   xBounds: (0, 10),
///   yBounds: (0, 10),
///   draw: (c) => c
///     ..draw(const Shape.rectangle(1, 1, 8, 8))
///     ..draw(const Shape.circle(5, 5, 3, color: Color.rgb(255, 0, 0)))
///     ..label(5, 5, 'center'),
/// )
/// ```
///
/// See also:
///
///  * `Chart`, datasets drawn the same way against two axes.
///  * [Shape], what [DotContext.draw] draws.
final class DotCanvas extends LeafRenderObjectWidget {
  /// Draws with [draw] on the space between [xBounds] and [yBounds].
  const DotCanvas({
    required this.draw,
    required this.xBounds,
    required this.yBounds,
    super.key,
    this.marker = Marker.braille,
    this.background,
  });

  /// Draws the shapes and labels; called on every paint. A new function
  /// repaints the canvas.
  final DotDrawer draw;

  /// The left and right ends of the x axis.
  final (double, double) xBounds;

  /// The bottom and top ends of the y axis.
  final (double, double) yBounds;

  /// How the dots are shown.
  final Marker marker;

  /// The background of every cell; null for the theme's
  /// ([ThemeData.background]).
  final Color? background;

  @override
  RenderDotCanvas createRenderObject(BuildContext context) {
    final canvas = RenderDotCanvas(
      draw: draw,
      xBounds: xBounds,
      yBounds: yBounds,
    );
    updateRenderObject(context, canvas);
    return canvas;
  }

  @override
  void updateRenderObject(BuildContext context, RenderDotCanvas renderObject) {
    final theme = overTheme(context, const Style());
    renderObject
      ..draw = draw
      ..xBounds = xBounds
      ..yBounds = yBounds
      ..marker = marker
      ..background = background ?? theme.bg ?? Color.defaultColor
      ..labelColor = theme.fg ?? Color.defaultColor;
  }
}

/// What a [DotDrawer] draws with: [draw] shapes in layers ([layer]), and
/// [label] points with text on top of them.
final class DotContext {
  /// Draws with [painter], no labels yet.
  DotContext(this.painter);

  /// Sets the dots of the grid in data coordinates.
  final DotPainter painter;

  final _labels = <(int, int, String, Style)>[];

  /// Sets the dots of [shape] in the current layer.
  void draw(Shape shape) => shape.draw(painter);

  /// Ends the current layer: what is drawn from here on covers what was
  /// drawn before, cell by cell (see [DotGrid]).
  void layer() => painter.grid.layer();

  /// Writes [text] in [style] from the cell ([x], [y]) falls in, over every
  /// layer; left out when the point is outside the bounds.
  void label(double x, double y, String text, [Style style = const Style()]) {
    final dot = painter.dotAt(x, y);
    if (dot != null) {
      final marker = painter.grid.marker;
      _labels.add((
        dot.$1 ~/ marker.dotsAcross,
        dot.$2 ~/ marker.dotsDown,
        text,
        style,
      ));
    }
  }

  /// Draws the grid at ([x], [y]) of [canvas] over [background], and the
  /// labels over it, in [labelColor] where their style sets no text color.
  void paint(
    Canvas canvas,
    int x,
    int y,
    Color background, {
    Color labelColor = Color.defaultColor,
  }) {
    painter.grid.paint(canvas, x, y, background);
    final under = Style(fg: labelColor);
    for (final (col, row, text, style) in _labels) {
      canvas.text(
        x + col,
        y + row,
        text,
        under.merge(style).penIn(canvas.styles),
      );
    }
  }
}

/// What a [DotCanvas] lays out and paints: as big as the constraints allow
/// (as small along an axis they leave unbounded), a repaint boundary that
/// draws into a [DotGrid] kept between paints; in the colors given, none
/// of them the theme's.
final class RenderDotCanvas extends RenderObject {
  /// Lays out and paints what [draw] draws, with the settings a
  /// [DotCanvas] has; the colors left out are the terminal's defaults.
  RenderDotCanvas({
    required this._draw,
    required this._xBounds,
    required this._yBounds,
    this._marker = Marker.braille,
    this._background = Color.defaultColor,
    this._labelColor = Color.defaultColor,
  });

  DotDrawer _draw;

  /// Draws the shapes and labels on each paint, as [DotCanvas.draw]; another
  /// function repaints.
  DotDrawer get draw => _draw;
  set draw(DotDrawer d) {
    if (!identical(d, _draw)) {
      _draw = d;
      markNeedsPaint();
    }
  }

  (double, double) _xBounds;

  /// The left and right ends of the x axis, as [DotCanvas.xBounds].
  (double, double) get xBounds => _xBounds;
  set xBounds((double, double) b) {
    if (b != _xBounds) {
      _xBounds = b;
      markNeedsPaint();
    }
  }

  (double, double) _yBounds;

  /// The bottom and top ends of the y axis, as [DotCanvas.yBounds].
  (double, double) get yBounds => _yBounds;
  set yBounds((double, double) b) {
    if (b != _yBounds) {
      _yBounds = b;
      markNeedsPaint();
    }
  }

  Marker _marker;

  /// How the dots are shown, as [DotCanvas.marker].
  Marker get marker => _marker;
  set marker(Marker m) {
    if (m != _marker) {
      _marker = m;
      markNeedsPaint();
    }
  }

  Color _background;

  /// The background of every cell.
  Color get background => _background;
  set background(Color c) {
    if (c != _background) {
      _background = c;
      markNeedsPaint();
    }
  }

  Color _labelColor;

  /// The text color of a label whose style sets none.
  Color get labelColor => _labelColor;
  set labelColor(Color c) {
    if (c != _labelColor) {
      _labelColor = c;
      markNeedsPaint();
    }
  }

  final _grid = DotGrid();

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW < BoxConstraints.unbounded ? c.maxW : c.minW;
    height = c.maxH < BoxConstraints.unbounded ? c.maxH : c.minH;
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    _grid.reset(width, height, _marker, canvas.segmenter);
    final context = DotContext(DotPainter(_grid, _xBounds, _yBounds));
    _draw(context);
    context.paint(canvas, 0, 0, _background, labelColor: _labelColor);
  }
}
