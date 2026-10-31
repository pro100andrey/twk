/// How far along something is: [Gauge], a bar that fills its cells, and
/// [LineGauge], a line after a label; their [RenderGauge] and
/// [RenderLineGauge].
library;

import 'package:twk_core/twk_core.dart'
    show Attr, BorderType, BoxConstraints, Color, PaintContext, RenderObject;

import '../foundation/format.dart';
import '../foundation/helpers.dart';
import '../framework/framework.dart';
import '../style/style.dart';
import '../text/widgets.dart';
import 'chart_glyphs.dart';

/// [ratio] of its width filled from the left, in eighths of a cell, on
/// every row, with [label] in the middle of the middle row, or with
/// [percentage] the ratio as a percentage. As wide as it may be and a row
/// tall, taller
/// where the constraints ask for more rows; a repaint boundary, so a new
/// ratio repaints nothing else.
///
/// A download two thirds done, its label over it:
///
/// ```dart
/// const Gauge(ratio: 2 / 3, label: '2 of 3 files')
/// ```
///
/// The same with the percentage over it, `66%`:
///
/// ```dart
/// const Gauge(ratio: 2 / 3, percentage: true)
/// ```
///
/// See also:
///
///  * [LineGauge], the same as a thin line after its label.
///  * `ProgressBar`, for progress without a known end too.
final class Gauge extends LeafRenderObjectWidget {
  /// Fills [ratio] of its width, [label] over it.
  const Gauge({
    required this.ratio,
    super.key,
    this.label,
    this.percentage = false,
    this.style = const Style(),
    this.labelStyle = const Style(),
  }) : assert(
         label == null || !percentage,
         'a label or the percentage, not both',
       );

  /// How much of the gauge is filled, from 0 to 1; a ratio beyond them
  /// counts as the nearest, one that is not a number as 0.
  final double ratio;

  /// The text over the gauge, cut off at its edges; null for none, or for
  /// the percentage with [percentage].
  final String? label;

  /// Whether the ratio shows over the gauge, where [label] is null, as a
  /// whole percentage, cut rather than rounded (`42%`, `100%` only once it
  /// is full).
  final bool percentage;

  /// The filled part's color ([Style.fg]) and the background ([Style.bg]),
  /// over the [DefaultTextStyle] and, under that, the theme's text and
  /// background.
  final Style style;

  /// Merged over [style] for the label, whose colors are swapped where the
  /// gauge is filled under it.
  final Style labelStyle;

  @override
  RenderGauge createRenderObject(BuildContext context) => RenderGauge(
    ratio: ratio,
    label: label,
    percentage: percentage,
    style: _styleAt(context, style),
    labelStyle: labelStyle,
  );

  @override
  void updateRenderObject(BuildContext context, RenderGauge renderObject) {
    renderObject
      ..ratio = ratio
      ..label = label
      ..percentage = percentage
      ..style = _styleAt(context, style)
      ..labelStyle = labelStyle;
  }
}

/// [ratio] as a line after [label] (or with [percentage] the ratio as a
/// percentage) and a blank: the part from the left filled in
/// [filledStyle], the rest in [unfilledStyle], to the nearest half cell
/// where [type] has a line that ends in the middle of a cell. On the
/// middle row; as wide as it may be and a row tall, taller where the
/// constraints ask for more rows; a repaint boundary, so a new ratio
/// repaints nothing else.
///
/// `segmented: true` draws a column a cell instead of the line, a meter
/// of segments; its figures after it in a `Row`:
///
/// ```dart
/// Row(
///   children: [
///     const Expanded(
///       child: LineGauge(
///         ratio: 84 / 112,
///         segmented: true,
///         filledStyle: Style(fg: Color.green),
///       ),
///     ),
///     const Text(' 84/112'),
///   ],
/// )
/// ```
///
/// A heavy line, its filled part green, after the percentage:
///
/// ```dart
/// const LineGauge(
///   ratio: 0.42,
///   percentage: true,
///   type: BorderType.heavy,
///   filledStyle: Style(fg: Color.rgb(0, 200, 0)),
/// )
/// ```
///
/// See also:
///
///  * [Gauge], the same as a bar that fills its cells.
final class LineGauge extends LeafRenderObjectWidget {
  /// Shows [ratio] as a line after [label].
  const LineGauge({
    required this.ratio,
    super.key,
    this.label,
    this.percentage = false,
    this.type = BorderType.single,
    this.style = const Style(),
    this.filledStyle = const Style(),
    this.unfilledStyle = const Style(),
    this.segmented = false,
  }) : assert(
         label == null || !percentage,
         'a label or the percentage, not both',
       );

  /// How much of the line is filled, from 0 to 1; a ratio beyond them
  /// counts as the nearest, one that is not a number as 0.
  final double ratio;

  /// The text before the line, cut off at the right edge; null (or empty)
  /// for none, or for the percentage with [percentage].
  final String? label;

  /// Whether the ratio shows before the line, where [label] is null, as a
  /// whole percentage, cut rather than rounded (`42%`).
  final bool percentage;

  /// The lines drawn: their horizontal piece, and the piece that reaches
  /// left only for a half cell. Where the canvas draws them two columns
  /// wide (box drawing is East Asian ambiguous), [BorderType.ascii].
  final BorderType type;

  /// The background, and the label's style, over the [DefaultTextStyle]
  /// and, under that, the theme's text: over what is under the gauge
  /// where it sets no background (`RenderObject.keepsUnderlay`).
  final Style style;

  /// Merged over [style] for the filled part of the line.
  final Style filledStyle;

  /// Merged over [style] for the rest of the line.
  final Style unfilledStyle;

  /// Whether the line is a column a cell (`▍`, a bar `|` where block
  /// elements are two columns wide) instead of [type]'s line, in whole
  /// cells: a meter of segments.
  final bool segmented;

  @override
  RenderLineGauge createRenderObject(BuildContext context) => RenderLineGauge(
    ratio: ratio,
    label: label,
    percentage: percentage,
    type: type,
    segmented: segmented,
    style: _styleAt(context, style),
    filledStyle: filledStyle,
    unfilledStyle: unfilledStyle,
  );

  @override
  void updateRenderObject(BuildContext context, RenderLineGauge renderObject) {
    renderObject
      ..ratio = ratio
      ..label = label
      ..percentage = percentage
      ..type = type
      ..segmented = segmented
      ..style = _styleAt(context, style)
      ..filledStyle = filledStyle
      ..unfilledStyle = unfilledStyle;
  }
}

/// [style] over the [DefaultTextStyle] at [context], over the theme's
/// text, with no background of the theme's: a gauge paints over what is
/// under it (a `Table`'s row, the selection's among them, a dialog, a
/// gradient). [context] depends on both.
Style _styleAt(BuildContext context, Style style) => Theme.of(
  context,
).text.merge(DefaultTextStyle.of(context)).merge(style);

/// What both gauges have: a ratio, a label and a style; as wide as the
/// constraints allow (as narrow where they leave the width unbounded) and
/// a row tall, a repaint boundary.
abstract base class _RenderGaugeBase extends RenderObject {
  _RenderGaugeBase(this._ratio, this._label, this._percentage, this._style);

  double _ratio;

  /// How much is filled, as [Gauge.ratio] and [LineGauge.ratio].
  double get ratio => _ratio;
  set ratio(double r) {
    // not a number is not equal to itself
    if (r != _ratio && !(r.isNaN && _ratio.isNaN)) {
      _ratio = r;
      markNeedsPaint();
    }
  }

  String? _label;

  /// The text shown, as [Gauge.label] and [LineGauge.label]; null for
  /// none, or for the ratio as a percentage with [percentage].
  String? get label => _label;
  set label(String? l) {
    if (l != _label) {
      _label = l;
      markNeedsPaint();
    }
  }

  bool _percentage;

  /// Whether the ratio shows as a percentage where [label] is null, as
  /// [Gauge.percentage] and [LineGauge.percentage].
  bool get percentage => _percentage;
  set percentage(bool p) {
    if (p != _percentage) {
      _percentage = p;
      markNeedsPaint();
    }
  }

  // what is shown: the label, the percentage, or nothing
  String get _text => _label ?? (_percentage ? formatPercent(_ratio) : '');

  Style _style;

  /// The gauge's style, as [Gauge.style] and [LineGauge.style] with the
  /// default text style and the theme already under it.
  Style get style => _style;
  set style(Style s) {
    if (s != _style) {
      _style = s;
      markNeedsPaint();
    }
  }

  final _glyphs = ChartGlyphs();

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get keepsUnderlay => true;

  @override
  bool get sizedByParent => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW < BoxConstraints.unbounded ? c.maxW : c.minW;
    height = c.constrainH(1);
  }

  // the row it takes where nothing sets its height

  @override
  int computeMinIntrinsicHeight(int width) => 1;

  @override
  int computeMaxIntrinsicHeight(int width) => 1;
}

/// What a [Gauge] lays out and paints, in the styles given, the
/// terminal's default colors where they set none: none of them the
/// theme's.
final class RenderGauge extends _RenderGaugeBase {
  /// Lays out and paints [ratio], with the settings a [Gauge] has.
  RenderGauge({
    required double ratio,
    String? label,
    bool percentage = false,
    Style style = const Style(),
    this._labelStyle = const Style(),
  }) : super(ratio, label, percentage, style);

  Style _labelStyle;

  /// The label's style, as [Gauge.labelStyle].
  Style get labelStyle => _labelStyle;
  set labelStyle(Style s) {
    if (s != _labelStyle) {
      _labelStyle = s;
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final base = const Style(fg: Color.defaultColor).merge(_style);
    final pen = base.penIn(canvas.styles);
    canvas.fill(0, 0, width, height, pen);
    final g = _glyphs..use(canvas.segmenter);
    // the cells filled whole, which the label shows swapped over
    final full = g.blocks(canvas, 0, 0, width, height, _ratio, pen);
    final text = _text;
    final w = canvas.segmenter.width(text);
    final x = w < width ? (width - w) ~/ 2 : 0;
    final y = height ~/ 2;
    final labelStyle = base.merge(_labelStyle);
    // over the full cells, swapped; over the rest, as it is
    canvas
      ..save()
      ..clipRect(0, y, full, 1)
      ..text(
        x,
        y,
        text,
        labelStyle.merge(const Style(attrs: Attr.reverse)).penIn(canvas.styles),
      )
      ..restore()
      ..save()
      ..clipRect(full, y, width - full, 1)
      ..text(x, y, text, labelStyle.penIn(canvas.styles))
      ..restore();
  }
}

/// What a [LineGauge] lays out and paints, in the styles given, the
/// terminal's default colors where they set none: none of them the
/// theme's.
final class RenderLineGauge extends _RenderGaugeBase {
  /// Lays out and paints [ratio], with the settings a [LineGauge] has.
  RenderLineGauge({
    required double ratio,
    String? label,
    bool percentage = false,
    this._type = BorderType.single,
    this._segmented = false,
    Style style = const Style(),
    this._filledStyle = const Style(),
    this._unfilledStyle = const Style(),
  }) : super(ratio, label, percentage, style);

  bool _segmented;

  /// Whether the line is a column a cell, as [LineGauge.segmented].
  bool get segmented => _segmented;
  set segmented(bool s) {
    if (s != _segmented) {
      _segmented = s;
      markNeedsPaint();
    }
  }

  BorderType _type;

  /// The lines drawn, as [LineGauge.type].
  BorderType get type => _type;
  set type(BorderType t) {
    if (t != _type) {
      _type = t;
      markNeedsPaint();
    }
  }

  Style _filledStyle;

  /// The filled part's style, as [LineGauge.filledStyle].
  Style get filledStyle => _filledStyle;
  set filledStyle(Style s) {
    if (s != _filledStyle) {
      _filledStyle = s;
      markNeedsPaint();
    }
  }

  Style _unfilledStyle;

  /// The rest's style, as [LineGauge.unfilledStyle].
  Style get unfilledStyle => _unfilledStyle;
  set unfilledStyle(Style s) {
    if (s != _unfilledStyle) {
      _unfilledStyle = s;
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final base = const Style(fg: Color.defaultColor).merge(_style);
    final pen = base.penIn(canvas.styles);
    canvas.fill(0, 0, width, height, pen);
    if (height == 0) {
      return;
    }
    final y = height ~/ 2;
    final text = _text;
    final x = text.isEmpty ? 0 : canvas.text(0, y, text, pen) + 1;
    final cells = width - x;
    if (cells <= 0) {
      return;
    }
    final glyphs = _glyphs..use(canvas.segmenter);
    if (_segmented) {
      // a column a cell, the filled ones rounded
      final column = glyphs.acrossSteps == 8 ? 0x258D : 0x7C;
      final filled = (unitRatio(_ratio) * cells).round();
      canvas
        ..fill(
          x,
          y,
          filled,
          1,
          base.merge(_filledStyle).penIn(canvas.styles),
          column,
        )
        ..fill(
          x + filled,
          y,
          cells - filled,
          1,
          base.merge(_unfilledStyle).penIn(canvas.styles),
          column,
        );
      return;
    }
    glyphs.line(
      canvas,
      x,
      y,
      cells,
      _type,
      filledPen: base.merge(_filledStyle).penIn(canvas.styles),
      unfilledPen: base.merge(_unfilledStyle).penIn(canvas.styles),
      ratio: unitRatio(_ratio),
    );
  }
}
