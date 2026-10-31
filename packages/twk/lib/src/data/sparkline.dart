/// A row of bars, one per value: [Sparkline] and its [RenderSparkline].
library;

import 'package:twk_core/twk_core.dart'
    show BoxConstraints, PaintContext, RenderObject;

import '../foundation/helpers.dart';
import '../framework/framework.dart';
import '../style/style.dart';
import '../text/widgets.dart';
import 'chart_glyphs.dart';

/// [data] as bars a column wide that grow upwards in eighths of a cell,
/// oldest to the left: the last values that fit, the newest at the right
/// edge once they fill it. While fewer than fit, they end at the right
/// edge, as a chart of time whose newest value is now, or with [fromRight]
/// false start at the left one. A bar is empty at [min] and
/// fills every row at [max], by default the largest value shown. As wide
/// as it may be and a row tall, taller where the constraints ask for more
/// rows; a repaint boundary, so new data repaints nothing else.
///
/// The load of the last minutes, two rows tall, a full bar at 100:
///
/// ```dart
/// const SizedBox(
///   height: 2,
///   child: Sparkline(data: [12, 40, 33, 87, 60, 25], max: 100),
/// )
/// ```
///
/// See also:
///
///  * `BarChart`, bars with labels and values, in groups.
///  * `Chart`, values as points or lines against two axes.
final class Sparkline extends LeafRenderObjectWidget {
  /// Shows [data] as bars from [min] to [max].
  const Sparkline({
    required this.data,
    super.key,
    this.min = 0,
    this.max,
    this.style = const Style(),
    this.fromRight = true,
  });

  /// The values, oldest first. Read, not copied: a new list with other
  /// values repaints, one changed in place shows on the next paint.
  final List<double> data;

  /// The value of an empty bar; those below it are empty.
  final double min;

  /// The value of a bar that fills every row, those above it too; null for
  /// the largest value shown.
  final double? max;

  /// The bars' color ([Style.fg]) and the background ([Style.bg]), over
  /// the [DefaultTextStyle] and, under that, the theme's text and
  /// background: those it leaves unset are the default text style's, else
  /// the theme's, so a sparkline in a `Table`'s cell takes its row's
  /// colours.
  final Style style;

  /// Whether fewer values than fit end at the right edge, the columns
  /// left of them empty, as by default; false starts them at the left
  /// one.
  final bool fromRight;

  @override
  RenderSparkline createRenderObject(BuildContext context) => RenderSparkline(
    data: data,
    min: min,
    max: max,
    style: overText(context, DefaultTextStyle.of(context).merge(style)),
    fromRight: fromRight,
  );

  @override
  void updateRenderObject(BuildContext context, RenderSparkline renderObject) {
    renderObject
      ..data = data
      ..min = min
      ..max = max
      ..style = overText(
        context,
        DefaultTextStyle.of(context).merge(style),
      )
      ..fromRight = fromRight;
  }
}

/// What a [Sparkline] lays out and paints, in the style given, the
/// terminal's default colors where it sets none: none of it the theme's.
final class RenderSparkline extends RenderObject {
  /// Lays out and paints [data], with the settings a [Sparkline] has.
  RenderSparkline({
    required this._data,
    this._min = 0,
    this._max,
    this._style = const Style(),
    this._fromRight = true,
  });

  List<double> _data;

  /// The values, oldest first, as [Sparkline.data]; a list with other
  /// values repaints.
  List<double> get data => _data;
  set data(List<double> d) {
    if (!sameList(d, _data)) {
      _data = d;
      markNeedsPaint();
    }
  }

  double _min;

  /// The value of an empty bar, as [Sparkline.min].
  double get min => _min;
  set min(double m) {
    if (m != _min) {
      _min = m;
      markNeedsPaint();
    }
  }

  double? _max;

  /// The value of a full bar, as [Sparkline.max]; null for the largest
  /// value shown.
  double? get max => _max;
  set max(double? m) {
    if (m != _max) {
      _max = m;
      markNeedsPaint();
    }
  }

  Style _style;

  /// The bars' style, as [Sparkline.style] with the default text style and
  /// the theme already under it.
  Style get style => _style;
  set style(Style s) {
    if (s != _style) {
      _style = s;
      markNeedsPaint();
    }
  }

  bool _fromRight;

  /// Whether fewer values than fit end at the right edge, as
  /// [Sparkline.fromRight].
  bool get fromRight => _fromRight;
  set fromRight(bool r) {
    if (r != _fromRight) {
      _fromRight = r;
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
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final pen = overUnder(_style).penIn(canvas.styles);
    canvas.fill(0, 0, width, height, pen);
    final n = _data.length < width ? _data.length : width;
    final first = _data.length - n;
    var top = _max;
    if (top == null) {
      for (var i = first; i < _data.length; i++) {
        final v = _data[i];
        if (v.isFinite && (top == null || v > top)) {
          top = v;
        }
      }
    }
    if (top == null || !(top > _min) || height == 0) {
      return;
    }
    final glyphs = _glyphs..use(canvas.segmenter);
    final steps = glyphs.upSteps;
    final most = height * steps;
    final whole = glyphs.up(steps);
    final x0 = _fromRight ? width - n : 0;
    for (var col = 0; col < n; col++) {
      final f = (_data[first + col] - _min) / (top - _min);
      // steps from the bottom; none for a value below min or none at all
      final s = f >= 1 ? most : (f > 0 ? (f * most).round() : 0);
      final full = s ~/ steps;
      canvas.fill(x0 + col, height - full, 1, full, pen, whole);
      if (s > full * steps) {
        final part = glyphs.up(s - full * steps);
        canvas.fill(x0 + col, height - 1 - full, 1, 1, pen, part);
      }
    }
  }
}
