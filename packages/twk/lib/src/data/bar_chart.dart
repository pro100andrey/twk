/// Values as bars side by side, in groups: [BarChart], its [Bar]s and
/// [BarGroup]s, and its [RenderBarChart].
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        Attr,
        Axis,
        BoxConstraints,
        Canvas,
        PaintContext,
        RenderObject,
        TextSegmenter;

import '../foundation/helpers.dart';
import '../framework/framework.dart';
import '../style/style.dart';
import 'chart_glyphs.dart';

/// One bar of a [BarChart]: its [value], the [label] beside it and the
/// [text] its value is shown as.
@immutable
final class Bar {
  /// A bar [value] long, with an optional [label] and [text], in the
  /// chart's styles with [style] and [valueStyle] merged over them.
  const Bar(
    this.value, {
    this.label,
    this.text,
    this.style = const Style(),
    this.valueStyle = const Style(),
  });

  /// How long the bar is; one of 0 or less, or not a number, is empty.
  final double value;

  /// The text under the bar (beside it, across), cut off at its width;
  /// null for none.
  final String? label;

  /// The value as shown; null for [value] with at most two decimals, empty
  /// for none.
  final String? text;

  /// Merged over the chart's [BarChart.barStyle] for this bar.
  final Style style;

  /// Merged over the chart's [BarChart.valueStyle] for this bar's value.
  final Style valueStyle;

  @override
  bool operator ==(Object other) =>
      other is Bar &&
      // the same value, not a number included
      (other.value == value || (other.value.isNaN && value.isNaN)) &&
      other.label == label &&
      other.text == text &&
      other.style == style &&
      other.valueStyle == valueStyle;

  @override
  int get hashCode =>
      Object.hash(value.isNaN ? 0 : value, label, text, style, valueStyle);
}

/// Bars of a [BarChart] side by side, with a [label] under them (after
/// them, across).
@immutable
final class BarGroup {
  /// The [bars] of one group, with [label] under them; null for none.
  const BarGroup(this.bars, {this.label});

  /// The bars, in order. Read, not copied.
  final List<Bar> bars;

  /// The text under the bars, centered and cut off at their extent; null
  /// for none. Across, it goes on the row after the bars, where
  /// [BarChart.groupGap] leaves one.
  final String? label;

  @override
  bool operator ==(Object other) =>
      other is BarGroup && other.label == label && sameList(other.bars, bars);

  @override
  int get hashCode => Object.hash(label, Object.hashAll(bars));
}

/// The bars of [groups] side by side, [barWidth] cells thick and [barGap]
/// apart, the groups [groupGap] apart; up from the bottom, or with a
/// [direction] of [Axis.horizontal] from the left, in eighths of a cell. A
/// bar is empty at 0 and as long as the chart allows at [max], by default
/// the largest value.
///
/// Up, each bar's label is under it, the group's under those, the rows
/// for them taken where any bar or group has one (the groups' first given
/// up when there is no room). Across, the labels go before the bars, as
/// wide as the widest, and a group's label on the row after its bars.
/// Bars that don't fit are cut off at the edge.
///
/// A bar's value goes inside the bar at its start, in the bar's style with
/// its colors swapped, where the cells the bar fills hold it; otherwise
/// just past the bar's end, in the bar's style, where it fits; [valueStyle]
/// is merged over either. Up, it is shown only where it fits the bar's
/// width.
///
/// As big as the constraints allow (as small along an axis they leave
/// unbounded); a repaint boundary, so new values repaint nothing else.
///
/// Three bars three cells thick, a cell apart, each with its day under it
/// and its value inside:
///
/// ```dart
/// const BarChart(
///   barWidth: 3,
///   groups: [
///     BarGroup([
///       Bar(3, label: 'Mon'),
///       Bar(5, label: 'Tue'),
///       Bar(2, label: 'Wed'),
///     ]),
///   ],
/// )
/// ```
///
/// See also:
///
///  * `Sparkline`, a row of values one cell each, without labels.
///  * `Chart`, values as points or lines on two axes.
final class BarChart extends LeafRenderObjectWidget {
  /// Shows [groups] of bars; asserts that [barWidth] is 1 or more and the
  /// gaps 0 or more.
  const BarChart({
    required this.groups,
    super.key,
    this.direction = Axis.vertical,
    this.barWidth = 1,
    this.barGap = 1,
    this.groupGap = 0,
    this.max,
    this.style = const Style(),
    this.barStyle = const Style(),
    this.valueStyle = const Style(),
    this.labelStyle = const Style(),
  }) : assert(barWidth >= 1, 'bars a cell thick or more'),
       assert(barGap >= 0 && groupGap >= 0, 'gaps of 0 cells or more');

  /// The groups of bars, in order. Read, not copied: a new list with other
  /// bars repaints, one changed in place shows on the next paint.
  final List<BarGroup> groups;

  /// [Axis.vertical] for bars that grow up, [Axis.horizontal] for bars
  /// that grow to the right.
  final Axis direction;

  /// How thick each bar is, in cells.
  final int barWidth;

  /// The cells between two bars of a group.
  final int barGap;

  /// The cells between two groups.
  final int groupGap;

  /// The value of a bar as long as the chart allows, those above it too;
  /// null for the largest value.
  final double? max;

  /// The background ([Style.bg]) and the colors of what sets none, over
  /// the theme's text, over what is under it; merged under the other styles.
  final Style style;

  /// The bars' style, merged over [style].
  final Style barStyle;

  /// The values' style, merged over that of their bar.
  final Style valueStyle;

  /// The labels' style, merged over [style].
  final Style labelStyle;

  @override
  RenderBarChart createRenderObject(BuildContext context) => RenderBarChart(
    groups: groups,
    direction: direction,
    barWidth: barWidth,
    barGap: barGap,
    groupGap: groupGap,
    max: max,
    style: overText(context, style),
    barStyle: barStyle,
    valueStyle: valueStyle,
    labelStyle: labelStyle,
  );

  @override
  void updateRenderObject(BuildContext context, RenderBarChart renderObject) {
    renderObject
      ..groups = groups
      ..direction = direction
      ..barWidth = barWidth
      ..barGap = barGap
      ..groupGap = groupGap
      ..max = max
      ..style = overText(context, style)
      ..barStyle = barStyle
      ..valueStyle = valueStyle
      ..labelStyle = labelStyle;
  }
}

/// What a [BarChart] lays out and paints, in the styles given, the
/// terminal's default colors where they set none: none of them the
/// theme's.
final class RenderBarChart extends RenderObject {
  /// Lays out and paints [groups], with the settings a [BarChart] has;
  /// asserts what [BarChart.new] does.
  RenderBarChart({
    required this._groups,
    this._direction = Axis.vertical,
    this._barWidth = 1,
    this._barGap = 1,
    this._groupGap = 0,
    this._max,
    this._style = const Style(),
    this._barStyle = const Style(),
    this._valueStyle = const Style(),
    this._labelStyle = const Style(),
  }) : assert(_barWidth >= 1, 'bars a cell thick or more'),
       assert(_barGap >= 0 && _groupGap >= 0, 'gaps of 0 cells or more');

  List<BarGroup> _groups;

  /// The groups of bars, as [BarChart.groups]; a list with other bars
  /// repaints.
  List<BarGroup> get groups => _groups;
  set groups(List<BarGroup> g) {
    if (!sameList(g, _groups)) {
      _groups = g;
      markNeedsPaint();
    }
  }

  Axis _direction;

  /// Which way the bars grow, as [BarChart.direction].
  Axis get direction => _direction;
  set direction(Axis d) {
    if (d != _direction) {
      _direction = d;
      markNeedsPaint();
    }
  }

  int _barWidth;

  /// How thick each bar is, in cells, as [BarChart.barWidth]; asserted 1
  /// or more.
  int get barWidth => _barWidth;
  set barWidth(int w) {
    assert(w >= 1, 'bars a cell thick or more');
    if (w != _barWidth) {
      _barWidth = w;
      markNeedsPaint();
    }
  }

  int _barGap;

  /// The cells between two bars of a group, as [BarChart.barGap]; asserted
  /// 0 or more.
  int get barGap => _barGap;
  set barGap(int g) {
    assert(g >= 0, 'a gap of 0 cells or more');
    if (g != _barGap) {
      _barGap = g;
      markNeedsPaint();
    }
  }

  int _groupGap;

  /// The cells between two groups, as [BarChart.groupGap]; asserted 0 or
  /// more.
  int get groupGap => _groupGap;
  set groupGap(int g) {
    assert(g >= 0, 'a gap of 0 cells or more');
    if (g != _groupGap) {
      _groupGap = g;
      markNeedsPaint();
    }
  }

  double? _max;

  /// The value of a bar as long as the chart allows, as [BarChart.max];
  /// null for the largest value.
  double? get max => _max;
  set max(double? m) {
    if (m != _max) {
      _max = m;
      markNeedsPaint();
    }
  }

  Style _style;

  /// The background and the colors of what sets none, as [BarChart.style]
  /// with the theme already under it.
  Style get style => _style;
  set style(Style s) {
    if (s != _style) {
      _style = s;
      markNeedsPaint();
    }
  }

  Style _barStyle;

  /// The bars' style, as [BarChart.barStyle].
  Style get barStyle => _barStyle;
  set barStyle(Style s) {
    if (s != _barStyle) {
      _barStyle = s;
      markNeedsPaint();
    }
  }

  Style _valueStyle;

  /// The values' style, as [BarChart.valueStyle].
  Style get valueStyle => _valueStyle;
  set valueStyle(Style s) {
    if (s != _valueStyle) {
      _valueStyle = s;
      markNeedsPaint();
    }
  }

  Style _labelStyle;

  /// The labels' style, as [BarChart.labelStyle].
  Style get labelStyle => _labelStyle;
  set labelStyle(Style s) {
    if (s != _labelStyle) {
      _labelStyle = s;
      markNeedsPaint();
    }
  }

  final _glyphs = ChartGlyphs();

  @override
  bool get isRepaintBoundary => true;

  // over what is under it, put back as it repaints on its own
  @override
  bool get keepsUnderlay => true;

  @override
  bool get sizedByParent => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW < BoxConstraints.unbounded ? c.maxW : c.minW;
    height = c.maxH < BoxConstraints.unbounded ? c.maxH : c.minH;
  }

  // what a paint draws with: the chart's style, the label pen, the
  // segmenter and the value of the longest bar
  late Style _base;
  var _labelPen = 0;
  late TextSegmenter _segmenter;
  var _top = 0.0;

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    _base = overUnder(_style);
    canvas.fill(0, 0, width, height, _base.penIn(canvas.styles));
    _labelPen = _base.merge(_labelStyle).penIn(canvas.styles);
    _segmenter = canvas.segmenter;
    _glyphs.use(_segmenter);
    var top = _max;
    if (top == null) {
      for (final group in _groups) {
        for (final bar in group.bars) {
          if (bar.value.isFinite && (top == null || bar.value > top)) {
            top = bar.value;
          }
        }
      }
    }
    _top = top ?? 0;
    if (_direction == Axis.vertical) {
      _paintUp(canvas);
    } else {
      _paintAcross(canvas);
    }
  }

  /// The steps of [bar] when [most] fill it: none where no bar has a
  /// length.
  int _steps(Bar bar, int most) {
    if (!(_top > 0)) {
      return 0;
    }
    final f = bar.value / _top;
    return f >= 1 ? most : (f > 0 ? (f * most).round() : 0);
  }

  /// Draws [text] in [pen] from column [x] of row [y], cut off at [cells]
  /// columns, centered in them when [center] is set.
  void _text(
    Canvas canvas,
    int x,
    int y,
    int cells,
    String text,
    int pen, {
    bool center = false,
  }) {
    if (cells <= 0 || text.isEmpty) {
      return;
    }
    final w = _segmenter.width(text);
    canvas
      ..save()
      ..clipRect(x, y, cells, 1)
      ..text(center && w < cells ? x + (cells - w) ~/ 2 : x, y, text, pen)
      ..restore();
  }

  /// Bars that grow up from the bottom, their labels and their groups'
  /// under them.
  void _paintUp(Canvas canvas) {
    var barLabels = false;
    var groupLabels = false;
    for (final group in _groups) {
      groupLabels = groupLabels || group.label != null;
      for (final bar in group.bars) {
        barLabels = barLabels || bar.label != null;
      }
    }
    // the rows of the bars and those of the labels under them, the
    // groups' given up first: the bars keep a row
    var rows = height;
    if (barLabels && rows > 1) {
      rows--;
    } else {
      barLabels = false;
    }
    if (groupLabels && rows > 1) {
      rows--;
    } else {
      groupLabels = false;
    }
    final steps = _glyphs.upSteps;
    final most = rows * steps;
    var x = 0;
    for (var g = 0; g < _groups.length && x < width; g++) {
      final group = _groups[g];
      if (g > 0) {
        x += _groupGap;
      }
      final start = x;
      for (var b = 0; b < group.bars.length; b++) {
        if (b > 0) {
          x += _barGap;
        }
        final bar = group.bars[b];
        final barStyle = _base.merge(_barStyle).merge(bar.style);
        final pen = barStyle.penIn(canvas.styles);
        final s = _steps(bar, most);
        final full = s ~/ steps;
        canvas.fill(x, rows - full, _barWidth, full, pen, _glyphs.up(steps));
        if (s > full * steps) {
          final part = _glyphs.up(s - full * steps);
          canvas.fill(x, rows - 1 - full, _barWidth, 1, pen, part);
        }
        final text = bar.text ?? formatValue(bar.value);
        if (text.isNotEmpty &&
            _segmenter.width(text) <= _barWidth &&
            rows > 0) {
          // inside where the bar fills its first row, else over its end
          final inside = s >= steps;
          final y = inside ? rows - 1 : rows - 1 - (s + steps - 1) ~/ steps;
          if (y >= 0) {
            final style = inside
                ? barStyle.merge(const Style(attrs: Attr.reverse))
                : barStyle;
            _text(
              canvas,
              x,
              y,
              _barWidth,
              text,
              style
                  .merge(_valueStyle)
                  .merge(bar.valueStyle)
                  .penIn(canvas.styles),
              center: true,
            );
          }
        }
        if (barLabels && bar.label != null) {
          _text(
            canvas,
            x,
            rows,
            _barWidth,
            bar.label!,
            _labelPen,
            center: true,
          );
        }
        x += _barWidth;
      }
      final label = group.label;
      if (groupLabels && label != null) {
        _text(
          canvas,
          start,
          barLabels ? rows + 1 : rows,
          x - start,
          label,
          _labelPen,
          center: true,
        );
      }
    }
  }

  /// Bars that grow to the right, their labels before them and their
  /// groups' after them.
  void _paintAcross(Canvas canvas) {
    var labels = 0;
    for (final group in _groups) {
      for (final bar in group.bars) {
        final label = bar.label;
        if (label != null) {
          final w = _segmenter.width(label);
          labels = w > labels ? w : labels;
        }
      }
    }
    // the labels and a blank before the bars, where a bar cell is left
    final left = labels > 0 && labels + 1 < width ? labels + 1 : 0;
    final cells = width - left;
    final steps = _glyphs.acrossSteps;
    final most = cells * steps;
    var y = 0;
    for (var g = 0; g < _groups.length && y < height; g++) {
      final group = _groups[g];
      if (g > 0) {
        y += _groupGap;
      }
      for (var b = 0; b < group.bars.length; b++) {
        if (b > 0) {
          y += _barGap;
        }
        final bar = group.bars[b];
        final barStyle = _base.merge(_barStyle).merge(bar.style);
        final pen = barStyle.penIn(canvas.styles);
        final s = _steps(bar, most);
        final full = s ~/ steps;
        canvas.fill(left, y, full, _barWidth, pen, _glyphs.across(steps));
        if (s > full * steps) {
          final part = _glyphs.across(s - full * steps);
          canvas.fill(left + full, y, 1, _barWidth, pen, part);
        }
        final mid = y + _barWidth ~/ 2;
        final text = bar.text ?? formatValue(bar.value);
        if (text.isNotEmpty) {
          // inside where the bar's full cells hold it, else past its end
          final w = _segmenter.width(text);
          final full = s ~/ steps;
          final end = (s + steps - 1) ~/ steps;
          final style = w <= full
              ? barStyle.merge(const Style(attrs: Attr.reverse))
              : (end + w <= cells ? barStyle : null);
          if (style != null) {
            _text(
              canvas,
              w <= full ? left : left + end,
              mid,
              w,
              text,
              style
                  .merge(_valueStyle)
                  .merge(bar.valueStyle)
                  .penIn(canvas.styles),
            );
          }
        }
        final label = bar.label;
        if (left > 0 && label != null) {
          _text(canvas, 0, mid, labels, label, _labelPen);
        }
        y += _barWidth;
      }
      final label = group.label;
      if (_groupGap > 0 && label != null) {
        _text(canvas, left, y, cells, label, _labelPen);
      }
    }
  }
}
