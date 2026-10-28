/// Datasets plotted finer than the cells against two axes: [Chart], its
/// [Dataset]s and [ChartAxis]es, and its [RenderChart].
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        BorderType,
        BoxConstraints,
        Canvas,
        Color,
        PaintContext,
        RenderObject,
        TextSegmenter;

import '../foundation/helpers.dart';
import '../framework/framework.dart';
import '../style/style.dart';
import 'chart_glyphs.dart';
import 'dot_canvas.dart';
import 'dot_grid.dart';
import 'dot_painter.dart';
import 'marker.dart';

// Examples can assume:
// import 'dart:math' as math;

/// How a [Dataset] is drawn.
enum GraphType {
  /// A dot at each point.
  scatter,

  /// Lines from each point to the next.
  line,
}

/// Where a [Chart] puts its legend in its plot.
enum LegendPosition {
  /// In the plot's top left corner.
  topLeft,

  /// At the plot's top, centered.
  top,

  /// In the plot's top right corner, the default.
  topRight,

  /// At the plot's left, halfway down.
  left,

  /// At the plot's right, halfway down.
  right,

  /// In the plot's bottom left corner.
  bottomLeft,

  /// At the plot's bottom, centered.
  bottom,

  /// In the plot's bottom right corner.
  bottomRight,
}

/// Points of a [Chart], drawn as [type] in [color], named [name] in the
/// legend.
@immutable
final class Dataset {
  /// The points [data], as dots by default, in the terminal's default
  /// color and with no name.
  const Dataset({
    required this.data,
    this.name = '',
    this.type = GraphType.scatter,
    this.color = Color.defaultColor,
  });

  /// The points, x and y. Read, not copied.
  final List<(double, double)> data;

  /// The name in the legend; empty for none.
  final String name;

  /// How the points are drawn.
  final GraphType type;

  /// The color of the dots, and of the name in the legend.
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is Dataset &&
      other.name == name &&
      other.type == type &&
      other.color == color &&
      sameList(other.data, data);

  @override
  int get hashCode => Object.hash(name, type, color, Object.hashAll(data));
}

/// An axis of a [Chart]: the values it spans ([bounds]), its [labels] and
/// [title].
@immutable
final class ChartAxis {
  /// An axis from one of [bounds] to the other, its labels worked out
  /// from them unless [labels] are given.
  const ChartAxis({
    required this.bounds,
    this.title,
    this.labels,
    this.style = const Style(),
  });

  /// The values at the ends of the axis: the left and right ends of the x
  /// axis, the bottom and top ends of the y axis.
  final (double, double) bounds;

  /// The axis' name, at the top left of the chart for the y axis, under
  /// the labels at the right for the x axis; null for none.
  final String? title;

  /// The labels, spread evenly from the first end of the axis to the
  /// other; every second, third and so on of them where they would touch.
  /// Null for labels worked out from the bounds: their values are 1, 2 or
  /// 5 times a power of ten apart, the least apart that keep a blank
  /// between two of them. Empty for none.
  final List<String>? labels;

  /// The style of the axis' line, ticks, labels and title, merged over the
  /// chart's.
  final Style style;

  @override
  bool operator ==(Object other) =>
      other is ChartAxis &&
      other.bounds == bounds &&
      other.title == title &&
      other.style == style &&
      (identical(other.labels, labels) ||
          (other.labels != null &&
              labels != null &&
              sameList(other.labels!, labels!)));

  @override
  int get hashCode => Object.hash(
    bounds,
    title,
    style,
    labels == null ? null : Object.hashAll(labels!),
  );
}

/// [datasets] plotted against [xAxis] and [yAxis], with a [marker] finer
/// than the cells (see [DotCanvas]), each dataset covering those before
/// it cell by cell.
///
/// The y axis' labels go at the left, right-aligned at the rows of their
/// values, a tick (`┤`) on the axis' line beside each; the x axis' under
/// its line, centered at the columns of their values as far as the chart's
/// edges let them, a tick (`┬`) on the line above each. Labels that would
/// touch are thinned out (see [ChartAxis.labels]). The plot keeps a row
/// and a column: where the chart has too few rows, the titles are given up
/// first, then the x labels and the x axis' line; where it has too few
/// columns, the y labels and then the y axis' line.
///
/// The legend, in a box in the plot at [legendPosition], lists the
/// datasets that have a name in their colors; it is left out where it
/// would take more than half the plot's width or height. Where the canvas
/// draws box drawing two columns wide (it is East Asian ambiguous), the
/// lines are ASCII.
///
/// As big as the constraints allow (as small along an axis they leave
/// unbounded); a repaint boundary, so new data repaints nothing else.
///
/// A line of a sine wave over the x values 0 to 10, named in the legend:
///
/// ```dart
/// Chart(
///   datasets: [
///     Dataset(
///       name: 'sin',
///       type: GraphType.line,
///       data: [for (var x = 0.0; x <= 10; x += 0.5) (x, math.sin(x))],
///     ),
///   ],
///   xAxis: const ChartAxis(bounds: (0, 10), title: 'x'),
///   yAxis: const ChartAxis(bounds: (-1, 1)),
/// )
/// ```
///
/// See also:
///
///  * [DotCanvas], for shapes drawn finer than the cells without axes.
///  * `Sparkline` and `BarChart`, values as bars.
final class Chart extends LeafRenderObjectWidget {
  /// Plots [datasets] against [xAxis] and [yAxis].
  const Chart({
    required this.datasets,
    required this.xAxis,
    required this.yAxis,
    super.key,
    this.marker = Marker.braille,
    this.legendPosition = LegendPosition.topRight,
    this.style = const Style(),
  });

  /// The datasets, the first drawn first. Read, not copied: a new list
  /// with other data repaints, one changed in place shows on the next
  /// paint.
  final List<Dataset> datasets;

  /// The axis along the bottom: the x values from the left to the right.
  final ChartAxis xAxis;

  /// The axis at the left: the y values from the bottom to the top.
  final ChartAxis yAxis;

  /// How the dots are shown.
  final Marker marker;

  /// Where the legend goes; null for none.
  final LegendPosition? legendPosition;

  /// The chart's colors: the background ([Style.bg]) and the text color
  /// of the axes and the legend, over the theme's background and text.
  final Style style;

  @override
  RenderChart createRenderObject(BuildContext context) => RenderChart(
    datasets: datasets,
    xAxis: xAxis,
    yAxis: yAxis,
    marker: marker,
    legendPosition: legendPosition,
    style: overTheme(context, style),
  );

  @override
  void updateRenderObject(BuildContext context, RenderChart renderObject) {
    renderObject
      ..datasets = datasets
      ..xAxis = xAxis
      ..yAxis = yAxis
      ..marker = marker
      ..legendPosition = legendPosition
      ..style = overTheme(context, style);
  }
}

/// A label of an axis: the cell it goes at along the axis (from the top
/// for the y axis) and its text.
typedef _Label = (int, String);

/// What a [Chart] lays out and paints, in the style given, the terminal's
/// default colors where it sets none: none of it the theme's.
final class RenderChart extends RenderObject {
  /// Lays out and paints [datasets] against the axes, with the settings a
  /// [Chart] has.
  RenderChart({
    required this._datasets,
    required this._xAxis,
    required this._yAxis,
    this._marker = Marker.braille,
    this._legendPosition = LegendPosition.topRight,
    this._style = const Style(),
  });

  List<Dataset> _datasets;

  /// The datasets, as [Chart.datasets]; a list with other data repaints.
  List<Dataset> get datasets => _datasets;
  set datasets(List<Dataset> d) {
    if (!sameList(d, _datasets)) {
      _datasets = d;
      markNeedsPaint();
    }
  }

  ChartAxis _xAxis;

  /// The axis along the bottom, as [Chart.xAxis]; an unequal one repaints.
  ChartAxis get xAxis => _xAxis;
  set xAxis(ChartAxis a) {
    if (a != _xAxis) {
      _xAxis = a;
      markNeedsPaint();
    }
  }

  ChartAxis _yAxis;

  /// The axis at the left, as [Chart.yAxis]; an unequal one repaints.
  ChartAxis get yAxis => _yAxis;
  set yAxis(ChartAxis a) {
    if (a != _yAxis) {
      _yAxis = a;
      markNeedsPaint();
    }
  }

  Marker _marker;

  /// How the dots are shown, as [Chart.marker].
  Marker get marker => _marker;
  set marker(Marker m) {
    if (m != _marker) {
      _marker = m;
      markNeedsPaint();
    }
  }

  LegendPosition? _legendPosition;

  /// Where the legend goes, as [Chart.legendPosition]; null for none.
  LegendPosition? get legendPosition => _legendPosition;
  set legendPosition(LegendPosition? p) {
    if (p != _legendPosition) {
      _legendPosition = p;
      markNeedsPaint();
    }
  }

  Style _style;

  /// The chart's colors, as [Chart.style] with the theme already under
  /// it.
  Style get style => _style;
  set style(Style s) {
    if (s != _style) {
      _style = s;
      markNeedsPaint();
    }
  }

  final _grid = DotGrid();
  final _glyphs = ChartGlyphs();

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW < BoxConstraints.unbounded ? c.maxW : c.minW;
    height = c.maxH < BoxConstraints.unbounded ? c.maxH : c.minH;
  }

  // the segmenter of the canvas painted on
  late TextSegmenter _segmenter;

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final styles = canvas.styles;
    final base = opaque(_style);
    final pen = base.penIn(styles);
    canvas.fill(0, 0, width, height, pen);
    if (width == 0 || height == 0) {
      return;
    }
    _segmenter = canvas.segmenter;
    final lines = (_glyphs..use(_segmenter)).lines(BorderType.single);
    final xPen = base.merge(_xAxis.style).penIn(styles);
    final yPen = base.merge(_yAxis.style).penIn(styles);

    // the rows: the plot keeps one, the x axis' line, its labels and the
    // titles take one each where it does
    var rows = height;
    final xLine = rows > 1;
    if (xLine) {
      rows--;
    }
    final xLabelled = xLine && !(_xAxis.labels?.isEmpty ?? false) && rows > 1;
    if (xLabelled) {
      rows--;
    }
    final xTitle = _xAxis.title ?? '';
    final xTitled = xTitle.isNotEmpty && rows > 1;
    if (xTitled) {
      rows--;
    }
    final yTitle = _yAxis.title ?? '';
    final yTitled = yTitle.isNotEmpty && rows > 1;
    if (yTitled) {
      rows--;
    }
    final top = yTitled ? 1 : 0;
    final lineRow = top + rows;

    // the marker the grid draws with, and the y labels at its rows
    _grid.reset(0, rows, _marker, _segmenter);
    final down = _grid.marker.dotsDown;
    final across = _grid.marker.dotsAcross;
    final yLabels = _yAxis.labels?.isEmpty ?? false
        ? const <_Label>[]
        : _place(_yAxis, rows, down, true, (labels) {
            // a row apart; worked out, a blank row between
            final apart = _yAxis.labels == null ? 2 : 1;
            for (var i = 1; i < labels.length; i++) {
              if (labels[i - 1].$1 - labels[i].$1 < apart) {
                return false;
              }
            }
            return true;
          });

    // the columns: the plot keeps one, the y axis' line and its labels
    // take theirs where it does
    var cols = width;
    final yLine = cols > 1;
    if (yLine) {
      cols--;
    }
    var labelsWidth = 0;
    for (final (_, text) in yLabels) {
      labelsWidth = math.max(labelsWidth, _segmenter.width(text));
    }
    final yLabelled = yLine && labelsWidth > 0 && cols > labelsWidth;
    if (yLabelled) {
      cols -= labelsWidth;
    }
    final left = width - cols;

    // the x labels, each from the column it starts at
    final xLabels = !xLabelled
        ? const <_Label>[]
        : _place(_xAxis, cols, across, false, (labels) {
            var end = -1;
            for (final (cell, text) in labels) {
              final start = _xStart(left + cell, text);
              if (start <= end) {
                return false;
              }
              end = start + _segmenter.width(text);
            }
            return true;
          });

    // the plot
    _grid.reset(cols, rows, _marker, _segmenter);
    final painter = DotPainter(_grid, _xAxis.bounds, _yAxis.bounds);
    for (final dataset in _datasets) {
      (dataset.type == GraphType.line
              ? Shape.polyline(dataset.data, color: dataset.color)
              : Shape.points(dataset.data, color: dataset.color))
          .draw(painter);
      _grid.layer();
    }
    _grid.paint(canvas, left, top, base.bg!);

    // the axes, their ticks, labels and titles
    if (yLine) {
      canvas.fill(
        left - 1,
        top,
        1,
        lineRow - top,
        yPen,
        lines.glyph(up: true, down: true),
      );
      if (yLabelled) {
        final tick = lines.glyph(up: true, down: true, left: true);
        for (final (row, text) in yLabels) {
          canvas
            ..fill(left - 1, top + row, 1, 1, yPen, tick)
            ..text(
              labelsWidth - _segmenter.width(text),
              top + row,
              text,
              yPen,
            );
        }
      }
    }
    if (xLine) {
      canvas.fill(
        left,
        lineRow,
        width - left,
        1,
        xPen,
        lines.glyph(left: true, right: true),
      );
      if (yLine) {
        canvas.fill(
          left - 1,
          lineRow,
          1,
          1,
          xPen,
          lines.glyph(up: true, right: true),
        );
      }
      final tick = lines.glyph(left: true, right: true, down: true);
      for (final (col, text) in xLabels) {
        canvas
          ..fill(left + col, lineRow, 1, 1, xPen, tick)
          ..text(_xStart(left + col, text), lineRow + 1, text, xPen);
      }
    }
    if (xTitled) {
      final w = _segmenter.width(xTitle);
      canvas.text(
        w < width ? width - w : 0,
        lineRow + (xLabelled ? 2 : 1),
        xTitle,
        xPen,
      );
    }
    if (yTitled) {
      canvas.text(0, 0, yTitle, yPen);
    }
    _paintLegend(canvas, base, lines, left, top, cols, rows);
  }

  /// The column a label at [col] starts at: centered there as far as the
  /// chart's edges let it.
  int _xStart(int col, String text) {
    final w = _segmenter.width(text);
    final start = col - (w - 1) ~/ 2;
    return start + w > width ? math.max(0, width - w) : math.max(0, start);
  }

  /// The labels of [axis] along [cells] cells of [dots] dots each (counted
  /// from the top where [fromTop] is set), the first value's first: its
  /// own labels thinned out until [fit] takes them, or those worked out
  /// from its bounds the least apart that [fit] takes. None where the
  /// bounds enclose nothing.
  List<_Label> _place(
    ChartAxis axis,
    int cells,
    int dots,
    bool fromTop,
    bool Function(List<_Label> labels) fit,
  ) {
    final (lo, hi) = axis.bounds;
    if (!(hi > lo) || !(hi - lo).isFinite || cells <= 0) {
      return const [];
    }
    final scale = (cells * dots - 1) / (hi - lo);
    int cellOf(double v) {
      final dot = ((fromTop ? hi - v : v - lo) * scale).round();
      return dot.clamp(0, cells * dots - 1) ~/ dots;
    }

    final given = axis.labels;
    if (given != null) {
      final n = given.length;
      for (var every = 1; every <= n; every++) {
        final labels = [
          for (var i = 0; i < n; i += every)
            (cellOf(n == 1 ? lo : lo + (hi - lo) * i / (n - 1)), given[i]),
        ];
        if (fit(labels)) {
          return labels;
        }
      }
      return const [];
    }
    // steps of 1, 2 and 5 times a power of ten, from one a cell apart up
    var power = math
        .pow(10, (math.log((hi - lo) / cells) / math.ln10).floor())
        .toDouble();
    var exponent = (math.log(power) / math.ln10).round();
    for (var tries = 0; tries < 64; tries++) {
      for (final m in const [1, 2, 5]) {
        final step = m * power;
        final decimals = exponent < 0 ? -exponent : 0;
        final first = (lo / step - 1e-9).ceil();
        final last = (hi / step + 1e-9).floor();
        final labels = [
          for (var k = first; k <= last; k++)
            (cellOf(k * step), _format(k * step, decimals)),
        ];
        if (labels.length <= 1 || fit(labels)) {
          return labels;
        }
      }
      power *= 10;
      exponent++;
    }
    return const [];
  }

  /// Draws the legend in the plot, [cols] × [rows] cells from ([left],
  /// [top]), where it fits in half of each.
  void _paintLegend(
    Canvas canvas,
    Style base,
    BorderType lines,
    int left,
    int top,
    int cols,
    int rows,
  ) {
    final position = _legendPosition;
    if (position == null) {
      return;
    }
    var names = 0;
    var widest = 0;
    for (final dataset in _datasets) {
      if (dataset.name.isNotEmpty) {
        names++;
        widest = math.max(widest, _segmenter.width(dataset.name));
      }
    }
    final w = widest + 2;
    final h = names + 2;
    if (names == 0 || 2 * w > cols || 2 * h > rows) {
      return;
    }
    final x =
        left +
        switch (position) {
          .topLeft || .left || .bottomLeft => 0,
          .top || .bottom => (cols - w) ~/ 2,
          .topRight || .right || .bottomRight => cols - w,
        };
    final y =
        top +
        switch (position) {
          .topLeft || .top || .topRight => 0,
          .left || .right => (rows - h) ~/ 2,
          .bottomLeft || .bottom || .bottomRight => rows - h,
        };
    final styles = canvas.styles;
    final pen = base.penIn(styles);
    final across = lines.glyph(left: true, right: true);
    final down = lines.glyph(up: true, down: true);
    // the box: its corners, its edges, the rows of the names down its sides
    canvas
      ..fill(x, y, w, h, pen)
      ..fill(x, y, 1, 1, pen, lines.glyph(right: true, down: true))
      ..fill(x + w - 1, y, 1, 1, pen, lines.glyph(down: true, left: true))
      ..fill(x, y + h - 1, 1, 1, pen, lines.glyph(up: true, right: true))
      ..fill(x + w - 1, y + h - 1, 1, 1, pen, lines.glyph(up: true, left: true))
      ..fill(x + 1, y, w - 2, 1, pen, across)
      ..fill(x + 1, y + h - 1, w - 2, 1, pen, across)
      ..fill(x, y + 1, 1, h - 2, pen, down)
      ..fill(x + w - 1, y + 1, 1, h - 2, pen, down);
    var row = y + 1;
    for (final dataset in _datasets) {
      if (dataset.name.isEmpty) {
        continue;
      }
      canvas.text(
        x + 1,
        row,
        dataset.name,
        base.merge(Style(fg: dataset.color)).penIn(styles),
      );
      row++;
    }
  }
}

/// [value] with [decimals] decimals; no minus sign on a zero.
String _format(double value, int decimals) {
  final s = value.toStringAsFixed(decimals);
  return s.startsWith('-') && double.parse(s) == 0 ? s.substring(1) : s;
}
