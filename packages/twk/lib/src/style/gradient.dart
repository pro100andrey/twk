/// Gradients: [Gradient], colors that change from cell to cell along the
/// columns or the rows of a widget; [GradientBackground] fills its cells
/// with one under its child, and [GradientForeground] draws the text of
/// its child in one. A span of a `Text.rich` takes one along its graphemes
/// (`Span.gradient`).
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        Axis,
        BoxConstraints,
        Canvas,
        Color,
        DiagnosticPropertiesBuilder,
        PaintContext,
        Pen,
        RenderObject,
        RenderObjectWithChildMixin,
        StyleTable,
        describeColor,
        kCont,
        kWide;

import '../binding/app_binding.dart' show AppBinding;
import '../framework/framework.dart';
import '../layout/one_child.dart';
import 'color_mix.dart' show rgbColor;
import 'style.dart' show Span;

// Examples can assume:
// late Duration elapsed;

/// Colors that change from cell to cell along the columns of a widget,
/// left to right ([Axis.horizontal]), or along its rows, top to bottom
/// ([Axis.vertical]).
///
/// [colors] are at [stops], fractions of the way from the first cell (0)
/// to the last (1), each at least the one before; evenly spread when null.
/// The cells before the first stop take the first color, those after the
/// last stop the last, and those between two stops a mix of the two, as
/// the core blends a translucent background over another ([Pen.bgAlpha]):
/// in RGB, a palette color as the core takes it, the default color as the
/// terminal's background. A terminal of 256 colors or fewer shows the
/// nearest it has, as it does any RGB color.
///
/// With a [phase] the colors are a loop instead, the first again after the
/// last, turned [phase] of the way along it: colors that flow turn by a
/// growing phase, each cell on its way from one color to the next mixed
/// as between two stops, so that a palette color turns as smoothly as an
/// RGB one.
///
/// Red to blue across, through white a quarter of the way:
///
/// ```dart
/// const sunset = Gradient(
///   [Color.rgb(255, 0, 0), Color.rgb(255, 255, 255), Color.rgb(0, 0, 255)],
///   stops: [0, 0.25, 1],
/// );
/// ```
///
/// Blue, magenta and red flowing along, round once every four seconds, at
/// `elapsed` (a [Duration]):
///
/// ```dart
/// final flowing = Gradient(
///   const [Color.blue, Color.magenta, Color.red],
///   phase: elapsed.inMilliseconds % 4000 / 4000,
/// );
/// ```
///
/// See also:
///
///  * [GradientBackground], which fills a widget's cells with one.
///  * [GradientForeground], which colors a widget's text with one.
///  * [Span.gradient], text in one, grapheme by grapheme.
@immutable
final class Gradient {
  /// [colors] at [stops] along [direction], across by default; a loop
  /// turned [phase] of the way when that is given.
  ///
  /// [stops], when given, are as many as [colors], of which there is at
  /// least one, in order from 0 to 1, and [phase] is finite: a widget given
  /// one that is not fails an assert.
  const Gradient(
    this.colors, {
    this.stops,
    this.direction = Axis.horizontal,
    this.phase,
  });

  /// The colors, at least one: the first at the first cell, the last at the
  /// last; with a [phase], round a loop.
  final List<Color> colors;

  /// Where each of [colors] is, a fraction of the way from the first cell
  /// (0) to the last (1); null, the default, for evenly spread: from the
  /// first cell to the last, or with a [phase] round the loop, the first
  /// color again where the last would be, at 1.
  final List<double>? stops;

  /// How far the colors are turned along the axis, as a fraction of it;
  /// null, the default, for no loop.
  ///
  /// Given, the colors are a loop: after the last stop the colors go on
  /// from the last to the first, which is at its own stop plus 1, and the
  /// loop is shifted [phase] of the way towards the last cell, a color at
  /// a stop `s` showing at `s + phase`. Only its fraction counts: 1.5
  /// turns as 0.5, and -0.25 as 0.75. A phase that grows a little every
  /// frame makes the colors flow towards the last cell. Evenly spread, 0.5
  /// turns `[a, b, c, d]` into `[c, d, a, b, c]`.
  final double? phase;

  /// Whether the colors change along the columns ([Axis.horizontal], the
  /// default) or along the rows.
  final Axis direction;

  /// Whether [other] is a gradient of equal colors, stops, direction and
  /// phase.
  @override
  bool operator ==(Object other) =>
      other is Gradient &&
      other.direction == direction &&
      other.phase == phase &&
      _equal(other.colors, colors) &&
      _equal(other.stops, stops);

  @override
  int get hashCode => Object.hash(
    direction,
    phase,
    Object.hashAll(colors),
    stops == null ? null : Object.hashAll(stops!),
  );

  static bool _equal<T>(List<T>? a, List<T>? b) {
    if (identical(a, b)) {
      return true;
    }
    if (a == null || b == null || a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  /// Whether the gradient has colors, its stops are as many, in order and
  /// from 0 to 1, and its phase is finite.
  bool get _valid {
    final stops = this.stops;
    if (colors.isEmpty || !(phase?.isFinite ?? true)) {
      return false;
    }
    if (stops == null) {
      return true;
    }
    if (stops.length != colors.length) {
      return false;
    }
    var last = 0.0;
    for (final stop in stops) {
      if (stop < last || stop > 1) {
        return false;
      }
      last = stop;
    }
    return true;
  }

  String get _description =>
      '${direction.name} ${colors.map(describeColor).join(' ')}'
      '${stops == null ? '' : ' at ${stops!.join(' ')}'}'
      '${phase == null ? '' : ' turned $phase'}';

  /// The colors of [n] cells along the gradient, the first at 0 and the
  /// last at 1, mixed in [styles].
  List<Color> _along(StyleTable styles, int n) {
    final out = List<Color>.filled(n, colors[0]);
    _walk(
      n,
      (i, from, to, alpha) => out[i] = alpha == 0
          ? _pure(styles, colors, colors[from])
          : alpha >= 255
          ? _pure(styles, colors, colors[to])
          : _over(styles, colors[to], alpha, colors[from]),
    );
    return out;
  }

  /// Calls [at] for each of [n] places along the gradient, the first at 0
  /// and the last at 1, with the stop at or before it, the next stop, and
  /// the opacity of the color of the next over that of the one before
  /// there.
  void _walk(int n, void Function(int i, int from, int to, int alpha) at) {
    final phase = this.phase;
    if (phase != null) {
      _walkLoop(n, phase - phase.floorToDouble(), at);
      return;
    }
    final last = colors.length - 1;
    final stops = this.stops;
    double stop(int k) => stops?[k] ?? (last == 0 ? 0 : k / last);
    var k = 0;
    for (var i = 0; i < n; i++) {
      final t = n == 1 ? 0.0 : i / (n - 1);
      while (k < last && stop(k + 1) <= t) {
        k++;
      }
      final from = stop(k);
      at(
        i,
        k,
        k == last ? k : k + 1,
        k == last || t <= from
            ? 0
            : ((t - from) / (stop(k + 1) - from) * 255).round(),
      );
    }
  }

  /// [_walk] round the loop of the colors, turned [phase] (0 to 1) of the
  /// way: the place `t` shows what is at `t - phase` round it.
  void _walkLoop(
    int n,
    double phase,
    void Function(int i, int from, int to, int alpha) at,
  ) {
    final count = colors.length;
    final last = count - 1;
    final stops = this.stops;
    double stop(int k) => stops?[k] ?? k / count;
    for (var i = 0; i < n; i++) {
      final t = n == 1 ? 0.0 : i / (n - 1);
      var u = t - phase;
      if (u < 0) {
        u += 1;
      }
      // the stop at or before u and where it is; before the first stop,
      // the last a turn back
      var k = last;
      var from = stop(last);
      if (u < stop(0)) {
        from -= 1;
      } else {
        k = 0;
        while (k < last && stop(k + 1) <= u) {
          k++;
        }
        from = stop(k);
      }
      final next = k == last ? 0 : k + 1;
      final to = k == last ? stop(0) + 1 : stop(next);
      at(
        i,
        k,
        next,
        to <= from || u <= from ? 0 : ((u - from) / (to - from) * 255).round(),
      );
    }
  }
}

/// The text colors of [n] graphemes along [gradient], the first at 0 and
/// the last at 1, each with its opacity, for text built at [context].
/// They are worked out as the text is built, before it is painted: two
/// colors mix in the table of the app [context] is in, a palette color as
/// the terminal shows it where it told (OSC 4), xterm's outside an app;
/// and a mix with the default color is the other color at its share of
/// the mix, over the background the text is on. A palette the terminal
/// tells after the text is built is taken when it is built again.
List<(Color, int)> textColorsAlong(
  Gradient gradient,
  int n,
  BuildContext context,
) {
  assert(gradient._valid, _invalid);
  final mixing =
      AppBinding.maybeOf(context)?.twkApp.screen.styles ?? _outsideApps;
  final colors = gradient.colors;
  final out = List<(Color, int)>.filled(n, (colors[0], 255));
  gradient._walk(n, (i, k, next, alpha) {
    if (alpha == 0) {
      out[i] = (_pure(mixing, colors, colors[k]), 255);
      return;
    }
    final from = colors[k];
    final to = colors[next];
    out[i] = alpha >= 255 || from == to
        ? (_pure(mixing, colors, to), 255)
        : from.isDefault
        ? (to, alpha)
        : to.isDefault
        ? (from, 255 - alpha)
        : (_over(mixing, to, alpha, from), 255);
  });
  return out;
}

// mixes the colors of text built outside an app, as xterm shows them
final _outsideApps = StyleTable();

const _invalid =
    'a gradient needs a color, and its stops as many, in order, from 0 to 1';

/// [color] where a gradient of [colors] shows it unmixed: a palette color
/// as the RGB [styles] mixes it with ([StyleTable.paletteRgb]), so that
/// it is the color of the mixes beside it; as it is in a gradient of that
/// color alone, or where it is RGB or the default. The terminal's own
/// entry would not be where its palette is not what [styles] has (one
/// that told none, taken for xterm's), and a flowing gradient's cells
/// would flicker between the two as they land on a stop and leave it.
Color _pure(StyleTable styles, List<Color> colors, Color color) {
  if (color.isRgb || color.isDefault || colors.every((c) => c == color)) {
    return color;
  }
  return rgbColor(styles.paletteRgb(color.index));
}

/// [src] at [alpha] over [dst], each as a background would be.
Color _over(StyleTable styles, Color src, int alpha, Color dst) {
  if (alpha <= 0) {
    return dst;
  }
  if (alpha >= 255) {
    return src;
  }
  return styles.bgOf(
    styles.compose(
      styles.style(bg: dst),
      styles.pen(Pen(bg: src, bgAlpha: alpha)),
    ),
  );
}

/// [child] over [gradient]: each cell of this widget a blank on the
/// gradient's color there, its text color kept, which shows where the
/// child leaves the background as it is (a `Box` without a background:
/// `GradientBackground(gradient: …, child: Box(border: …))`). As big as
/// the child; without one, as big as the constraints allow.
///
/// A header on a background from dark blue to black:
///
/// ```dart
/// GradientBackground(
///   gradient: const Gradient([Color.rgb(0, 0, 96), Color.rgb(0, 0, 0)]),
///   child: const Text(' Inbox '),
/// )
/// ```
///
/// See also:
///
///  * [GradientForeground], the colors on the text instead.
final class GradientBackground extends SingleChildRenderObjectWidget {
  /// Shows [child] over [gradient].
  const GradientBackground({required this.gradient, super.key, super.child});

  /// The colors of the background, cell by cell.
  final Gradient gradient;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGradientBackground(gradient);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderGradientBackground).gradient = gradient;
}

/// [child] with its text in the colors of [gradient], each glyph in that
/// of its column (or row), a two-column glyph in that of its first: what
/// the child paints keeps its background and attributes, its text color
/// replaced; a two-column glyph cut by an edge of this widget is left as
/// it is. Its text takes the gradient again wherever it repaints on its
/// own. As big as the child.
///
/// A banner whose letters go from cyan to magenta:
///
/// ```dart
/// GradientForeground(
///   gradient: const Gradient([Color.cyan, Color.magenta]),
///   child: const Text('twk'),
/// )
/// ```
///
/// See also:
///
///  * [Span.gradient], for a gradient along a span of text, wherever its
///    graphemes are.
final class GradientForeground extends SingleChildRenderObjectWidget {
  /// Shows [child] with its text in the colors of [gradient].
  const GradientForeground({required this.gradient, super.key, super.child});

  /// The colors of the text, cell by cell.
  final Gradient gradient;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGradientForeground(gradient);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderGradientForeground).gradient = gradient;
}

/// What the gradient widgets share: the gradient, and laying out as the
/// child does.
abstract base class _RenderGradient extends RenderObject
    with RenderObjectWithChildMixin {
  _RenderGradient(Gradient gradient)
    : assert(gradient._valid, _invalid),
      _gradient = gradient;

  Gradient _gradient;
  Gradient get gradient => _gradient;
  set gradient(Gradient g) {
    assert(g._valid, _invalid);
    if (g != _gradient) {
      _gradient = g;
      markNeedsPaint();
    }
  }

  /// The colors of the cells along the gradient's direction.
  List<Color> _colors(StyleTable styles) => _gradient._along(
    styles,
    _gradient.direction == Axis.horizontal ? width : height,
  );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.addMessage('gradient', _gradient._description);
  }

  @override
  void performLayout(BoxConstraints c) {
    final child = this.child;
    if (child == null) {
      width = c.minW;
      height = c.minH;
      return;
    }
    child
      ..layout(c, parentUsesSize: true)
      ..parentData.dx = 0
      ..parentData.dy = 0;
    width = child.width;
    height = child.height;
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMinIntrinsicHeight(int width) =>
      child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      child?.getMaxIntrinsicHeight(width) ?? 0;
}

/// What a [GradientBackground] lays out and paints: the gradient, a run
/// of cells of one color at a time, then the child.
final class _RenderGradientBackground extends _RenderGradient {
  _RenderGradientBackground(super.gradient);

  @override
  void performLayout(BoxConstraints c) {
    if (child != null) {
      super.performLayout(c);
      return;
    }
    width = c.maxW < BoxConstraints.unbounded ? c.maxW : c.minW;
    height = c.maxH < BoxConstraints.unbounded ? c.maxH : c.minH;
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final styles = canvas.styles;
    final colors = _colors(styles);
    final across = _gradient.direction == Axis.horizontal;
    for (var i = 0; i < colors.length;) {
      final color = colors[i];
      var j = i + 1;
      while (j < colors.length && colors[j] == color) {
        j++;
      }
      final pen = styles.pen(Pen(bg: color));
      if (across) {
        canvas.fill(i, 0, j - i, height, pen);
      } else {
        canvas.fill(0, i, width, j - i, pen);
      }
      i = j;
    }
    final child = this.child;
    if (child != null) {
      paintChild(ctx, child);
    }
  }
}

/// What a [GradientForeground] lays out and paints: the child, then the
/// text color of each cell, also of the cells of a repaint boundary in the
/// child as that repaints on its own ([RenderObject.paintOver]).
final class _RenderGradientForeground extends _RenderGradient {
  _RenderGradientForeground(super.gradient);

  // the styles given a color since it last painted, by the style and the
  // color's place along the gradient
  final _colored = <int, int>{};

  @override
  void paint(PaintContext ctx) {
    final child = this.child;
    if (child != null) {
      paintChild(ctx, child);
      _color(ctx.canvas);
    }
  }

  @override
  bool paintsOver(RenderObject child, int x, int y, int w, int h) => true;

  @override
  void paintOver(
    PaintContext ctx,
    RenderObject child,
    int x,
    int y,
    int w,
    int h,
  ) => _color(ctx.canvas);

  /// Gives the cells of this object within the canvas's clip the colors
  /// of the gradient.
  void _color(Canvas canvas) {
    final styles = canvas.styles;
    final colors = _colors(styles);
    final across = _gradient.direction == Axis.horizontal;
    _colored.clear();
    final surface = canvas.surface;
    final cells = surface.cells;
    final sty = surface.styles;
    final screenWidth = surface.width;
    // the canvas's origin is this object's place on the screen, where
    // paintChild moved it
    final (gx, gy) = globalOffset;
    final (cx0, cy0, cx1, cy1) = canvas.clipBounds;
    final x0 = gx > cx0 ? gx : cx0;
    final x1 = gx + width < cx1 ? gx + width : cx1;
    final y0 = gy > cy0 ? gy : cy0;
    final y1 = gy + height < cy1 ? gy + height : cy1;
    for (var y = y0; y < y1 && x0 < x1; y++) {
      final row = y * screenWidth;
      var a = x0;
      var b = x1;
      if ((cells[row + a] & kCont) != 0) {
        a++;
      }
      if (a < b && b < screenWidth && (cells[row + b - 1] & kWide) != 0) {
        b--;
      }
      for (var x = a; x < b; x++) {
        final i = row + x;
        if (x > a && (cells[i] & kCont) != 0) {
          // the second half of a glyph: as its first
          sty[i] = sty[i - 1];
          continue;
        }
        final k = across ? x - gx : y - gy;
        final s = sty[i];
        sty[i] = _colored[s << 16 | k] ??= styles.style(
          fg: colors[k],
          bg: styles.bgOf(s),
          attrs: styles.attrsOf(s),
          underlineColor: styles.underlineColorOf(s),
          link: styles.linkOf(s),
        );
      }
      if (a < b) {
        surface.markDirty(y, a, b);
      }
    }
  }
}
