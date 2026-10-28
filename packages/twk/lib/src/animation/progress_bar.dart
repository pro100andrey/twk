/// How far along work is, or that it goes on: [ProgressBar] and its
/// [RenderProgressBar].
///
/// @docImport '../data/gauge.dart';
/// @docImport 'spinner.dart';
library;

import 'package:twk_core/twk_core.dart'
    show BoxConstraints, PaintContext, RenderObject;

import '../binding/app_binding.dart';
import '../data/chart_glyphs.dart';
import '../foundation/format.dart';
import '../framework/framework.dart';
import '../semantics/semantics.dart';
import '../style/style.dart';
import 'steps.dart';

/// A bar filled from the left as far as [value] says, in eighths of a
/// cell; while the value is not known (null), a block a quarter of its
/// width (a cell at least) going from one end to the other and back, a
/// cell each [step] of the app's clock, so that such bars move together.
/// Braille stands in for the block elements where the canvas draws those
/// two columns wide (they are East Asian ambiguous).
///
/// As wide as it may be and a row tall, taller where the constraints ask
/// for more rows; a repaint boundary, so a new value or a step repaints
/// nothing else.
///
/// A screen reader reads it as a [SemanticsRole.progressBar] of its
/// [semanticsLabel] and how much is done in percent
/// (`progressbar Upload: 40%`, `progressbar 40%` without a label), without
/// a value while it is not known (`progressbar Upload`).
///
/// An upload 40 % done, with what it is beside it:
///
/// ```dart
/// Row(
///   children: [
///     Text('Upload '),
///     Expanded(child: ProgressBar(value: 0.4, semanticsLabel: 'Upload')),
///   ],
/// )
/// ```
///
/// See also:
///
///  * [Spinner], which shows only that something goes on.
///  * [Gauge], a bar with its value written on it.
final class ProgressBar extends StatelessWidget {
  /// A bar [value] done, or moving while the value is null.
  const ProgressBar({super.key, this.value, this.style, this.semanticsLabel});

  /// How much is done, from 0 to 1, a value beyond them counting as the
  /// nearest and one that is not a number as 0; null while not known.
  final double? value;

  /// The bar's color ([Style.fg]) and the background ([Style.bg]); null
  /// for the theme's [ThemeData.primary].
  final Style? style;

  /// What a screen reader calls the bar, what it shows the progress of:
  /// `Upload`; null, or empty, for a bar read as how much is done alone.
  final String? semanticsLabel;

  /// How long the block of a bar whose value is not known stays in a cell.
  static const step = Duration(milliseconds: 50);

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    return Semantics(
      role: SemanticsRole.progressBar,
      label: semanticsLabel,
      value: value == null ? null : formatPercent(value),
      child: _Bar(value, style),
    );
  }
}

/// What draws a [ProgressBar].
final class _Bar extends LeafRenderObjectWidget {
  const _Bar(this.value, this.style);

  final double? value;
  final Style? style;

  @override
  RenderProgressBar createRenderObject(BuildContext context) =>
      RenderProgressBar(
        value: value,
        style: style ?? Theme.of(context).primary,
        binding: AppBinding.maybeOf(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderProgressBar renderObject,
  ) {
    renderObject
      ..value = value
      ..style = style ?? Theme.of(context).primary;
  }
}

/// What a [ProgressBar] lays out and paints: without a value, its block
/// moves on [binding]'s clock from its first paint until it is detached
/// or given a value.
final class RenderProgressBar extends RenderObject {
  /// A bar [value] done in [style], whose block moves on [binding]'s clock
  /// while the value is null.
  RenderProgressBar({this._value, this._style = const Style(), this.binding});

  /// The app whose clock the block moves by.
  final AppBinding? binding;

  late final _steps = Steps(
    ProgressBar.step,
    markNeedsPaint,
    binding: binding,
  );

  double? _value;

  /// How much is done, from 0 to 1; null while not known. Set to a value,
  /// the block stops moving.
  double? get value => _value;
  set value(double? v) {
    final old = _value;
    // not a number is not equal to itself
    if (v == old || (v != null && old != null && v.isNaN && old.isNaN)) {
      return;
    }
    if (v != null) {
      _steps.stop();
    }
    _value = v;
    markNeedsPaint();
  }

  Style _style;

  /// The bar's color ([Style.fg]) and its background ([Style.bg]).
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
  bool get sizedByParent => true;

  @override
  int computeMinIntrinsicHeight(int width) => 1;

  @override
  int computeMaxIntrinsicHeight(int width) => 1;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW < BoxConstraints.unbounded ? c.maxW : c.minW;
    height = c.constrainH(1);
  }

  @override
  void detach() {
    _steps.stop();
    super.detach();
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final pen = opaque(_style).penIn(canvas.styles);
    canvas.fill(0, 0, width, height, pen);
    final value = _value;
    if (value == null) {
      _steps.start();
    }
    (_glyphs..use(canvas.segmenter)).blocks(
      canvas,
      0,
      0,
      width,
      height,
      value ?? 0,
      pen,
      run: value == null ? ChartGlyphs.sweep(width, _steps.current) : null,
    );
  }
}
