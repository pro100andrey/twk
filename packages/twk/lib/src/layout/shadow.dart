/// Drop shadows: [Shadow] darkens what is under it in the cells a
/// [BoxShadow] casts beside and below its child.
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        BoxConstraints,
        Canvas,
        Color,
        DiagnosticPropertiesBuilder,
        EdgeInsets,
        PaintContext,
        RenderObject,
        RenderObjectWithChildMixin,
        StyleTable,
        describeColor,
        kCont,
        kWide;

import '../framework/framework.dart';
import '../style/color_mix.dart';
import 'one_child.dart';

/// A drop shadow: the cells of a box moved [dx] columns right and [dy]
/// rows down (left and up where negative), but those of the box, taken
/// [opacity] of the way to [color] (or [alpha] of 255 of the way, where
/// no [opacity] is given).
///
/// Two shadows are equal when their offsets, colors, alphas and
/// opacities are.
///
/// A shadow one column to the right and one row down, darker than the
/// default:
///
/// ```dart
/// const BoxShadow(dx: 1, dy: 1, opacity: 0.7)
/// ```
@immutable
final class BoxShadow {
  /// A shadow [dx] columns right and [dy] rows down, 2 and 1 by default,
  /// taken towards [color], black, by [opacity] from 0 to 1 or else by
  /// [alpha] out of 255, half way by default.
  const BoxShadow({
    this.dx = 2,
    this.dy = 1,
    this.color = const Color.rgb(0, 0, 0),
    this.alpha = 0x80,
    this.opacity,
  }) : assert(alpha >= 0 && alpha <= 255, 'alpha out of 0..255'),
       assert(
         opacity == null || (opacity >= 0 && opacity <= 1),
         'opacity out of 0..1',
       );

  /// The columns the shadow is moved to the right of the box; to the left
  /// where negative.
  final int dx;

  /// The rows the shadow is moved down from the box; up where negative.
  final int dy;

  /// What the cells under the shadow are taken towards.
  final Color color;

  /// How much of [color] they take, of 255: 0 leaves them as they are, 255
  /// paints them over in [color]. Where [opacity] is given, it is left
  /// out.
  final int alpha;

  /// How much of [color] they take, from 0 to 1, as [alpha] does in 255ths:
  /// what a fraction such as 0.55 comes to exactly, which no alpha of 255
  /// is; null for [alpha].
  final double? opacity;

  /// How far the cells under the shadow are taken towards [color], from 0
  /// to 1: [opacity], else [alpha] in 255ths.
  double get strength => opacity ?? alpha / 255;

  /// The cells the shadow takes beside a box: [dx] on its right (or left),
  /// [dy] below (or above) it.
  EdgeInsets get insets => EdgeInsets.only(
    left: dx < 0 ? -dx : 0,
    top: dy < 0 ? -dy : 0,
    right: dx > 0 ? dx : 0,
    bottom: dy > 0 ? dy : 0,
  );

  @override
  bool operator ==(Object other) =>
      other is BoxShadow &&
      other.dx == dx &&
      other.dy == dy &&
      other.color == color &&
      other.alpha == alpha &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(dx, dy, color, alpha, opacity);
}

/// [child] casting [shadow] on what is under this widget: as big as the
/// child and the cells the shadow takes beside it ([BoxShadow.insets]),
/// the child in from them. Those cells keep their glyphs and attributes,
/// their background, their text color and the color of their underline
/// each taken [BoxShadow.strength] of the way to the shadow's color,
/// channel by channel and rounded once (`a + (color - a) * strength`; the
/// terminal's default colors where a cell has them); text in the default
/// color while the terminal has not
/// told it is drawn faint instead. What is under the shadow darkens again
/// wherever it repaints on its own; a two-column glyph its edge cuts
/// through is left as it is. The mouse goes through the shadow.
///
/// A dialog that casts the default shadow, two columns to its right and a
/// row below it:
///
/// ```dart
/// const Shadow(
///   child: Box(
///     border: Border.all(),
///     padding: EdgeInsets.x(1),
///     child: Text('Delete 3 files?'),
///   ),
/// )
/// ```
final class Shadow extends SingleChildRenderObjectWidget {
  /// Paints [child] casting [shadow], the default [BoxShadow] unless
  /// given.
  const Shadow({super.key, this.shadow = const BoxShadow(), super.child});

  /// The shadow the child casts.
  final BoxShadow shadow;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderShadow(shadow);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderShadow).shadow = shadow;
}

/// What a [Shadow] lays out and paints: the child, then the shadow.
final class _RenderShadow extends RenderObject with RenderObjectWithChildMixin {
  _RenderShadow(this._shadow);

  BoxShadow _shadow;
  BoxShadow get shadow => _shadow;
  set shadow(BoxShadow s) {
    if (s == _shadow) {
      return;
    }
    final room = s.insets != _shadow.insets;
    _shadow = s;
    if (room) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  // the styles shaded since it last painted, by the style they shade
  final _shaded = <int, int>{};

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    final s = _shadow;
    properties.addMessage(
      'shadow',
      '${s.dx},${s.dy} ${describeColor(s.color)}/'
          '${(s.strength * 100).round()}%',
    );
  }

  @override
  void performLayout(BoxConstraints c) {
    final child = this.child;
    if (child == null) {
      width = c.minW;
      height = c.minH;
      return;
    }
    final h = _across;
    final v = _down;
    child
      ..layout(
        BoxConstraints(
          _inside(c.minW, h),
          _inside(c.maxW, h),
          _inside(c.minH, v),
          _inside(c.maxH, v),
        ),
        parentUsesSize: true,
      )
      ..parentData.dx = _shadow.dx < 0 ? h : 0
      ..parentData.dy = _shadow.dy < 0 ? v : 0;
    width = c.constrainW(child.width + h);
    height = c.constrainH(child.height + v);
  }

  // the columns and the rows the shadow takes beside the child
  int get _across => _shadow.dx.abs();
  int get _down => _shadow.dy.abs();

  @override
  int computeMinIntrinsicWidth(int height) =>
      _across + (child?.getMinIntrinsicWidth(_inside(height, _down)) ?? 0);

  @override
  int computeMaxIntrinsicWidth(int height) =>
      _across + (child?.getMaxIntrinsicWidth(_inside(height, _down)) ?? 0);

  @override
  int computeMinIntrinsicHeight(int width) =>
      _down + (child?.getMinIntrinsicHeight(_inside(width, _across)) ?? 0);

  @override
  int computeMaxIntrinsicHeight(int width) =>
      _down + (child?.getMaxIntrinsicHeight(_inside(width, _across)) ?? 0);

  @override
  void paint(PaintContext ctx) {
    final child = this.child;
    if (child == null) {
      return;
    }
    paintChild(ctx, child);
    final s = _shadow;
    if (s.strength > 0 && (s.dx != 0 || s.dy != 0)) {
      // after the child, which may have broken a glyph at its edge
      _cast(ctx.canvas, child);
    }
  }

  /// Shades the cells of the shadow within the canvas's clip: the child's
  /// cells moved by the shadow's offset, but the child's own.
  void _cast(Canvas canvas, RenderObject child) {
    final styles = canvas.styles;
    final s = _shadow;
    final towards = rgbOf(styles, s.color, styles.defaultBackgroundRgb);
    final k = s.strength;
    _shaded.clear();
    // the canvas's origin is this object's place on the screen, where
    // paintChild moved it
    final (gx, gy) = globalOffset;
    final (cx0, cy0, cx1, cy1) = canvas.clipBounds;
    final x0 = gx + child.parentData.dx;
    final y0 = gy + child.parentData.dy;
    final x1 = x0 + child.width;
    final y1 = y0 + child.height;
    final sx0 = x0 + s.dx;
    final sx1 = x1 + s.dx;
    final top = _max(y0 + s.dy, cy0);
    final bottom = _min(y1 + s.dy, cy1);
    final left = _max(sx0, cx0);
    final right = _min(sx1, cx1);
    for (var y = top; y < bottom; y++) {
      if (y < y0 || y >= y1) {
        _shadeRow(canvas, styles, towards, k, y, left, right);
        continue;
      }
      // beside the child: left of it, right of it
      _shadeRow(canvas, styles, towards, k, y, left, _min(right, x0));
      _shadeRow(canvas, styles, towards, k, y, _max(left, x1), right);
    }
  }

  /// Takes the cells [a]..[b] of row [y] of the surface [k] of the way to
  /// [towards], an RGB, those of a two-column glyph cut by either end left
  /// as they are.
  void _shadeRow(
    Canvas canvas,
    StyleTable styles,
    int towards,
    double k,
    int y,
    int a,
    int b,
  ) {
    final surface = canvas.surface;
    final cells = surface.cells;
    final sty = surface.styles;
    final width = surface.width;
    final row = y * width;
    var i = row + a;
    var end = row + b;
    if (i < end && (cells[i] & kCont) != 0) {
      i++;
    }
    if (i < end && b < width && (cells[end - 1] & kWide) != 0) {
      end--;
    }
    if (i >= end) {
      return;
    }
    final from = i - row;
    final to = end - row;
    while (i < end) {
      final style = sty[i];
      final shaded = _shaded[style] ??= shadeStyle(styles, style, towards, k);
      var j = i + 1;
      while (j < end && sty[j] == style) {
        j++;
      }
      sty.fillRange(i, j, shaded);
      i = j;
    }
    surface.markDirty(y, from, to);
  }
}

/// [extent] less [cells], at least 0; an unbounded [extent] stays so.
int _inside(int extent, int cells) => extent >= BoxConstraints.unbounded
    ? extent
    : (extent - cells < 0 ? 0 : extent - cells);

int _min(int a, int b) => a < b ? a : b;

int _max(int a, int b) => a > b ? a : b;
