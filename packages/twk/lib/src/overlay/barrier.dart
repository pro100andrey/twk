/// What keeps a dialog modal: a [ModalBarrier] that dims what is under it
/// and stops the mouse from reaching it, and an [AnimatedModalBarrier]
/// whose shade fades in and out with an animation.
///
/// @docImport 'dialog.dart';
library;

import 'package:twk_core/twk_core.dart'
    show
        BoxConstraints,
        Color,
        DiagnosticPropertiesBuilder,
        PaintContext,
        RenderObject,
        describeColor,
        kCont,
        kWide;

import '../animation/animation_controller.dart' show AnimationController;
import '../animation/curves.dart';
import '../foundation/change_notifier.dart';
import '../framework/framework.dart';
import '../gestures/mouse.dart';
import '../semantics/semantics.dart';
import '../style/color_mix.dart';
import '../style/style.dart';

// Examples can assume:
// late AnimationController controller;
// void close() {}

/// Covers the room it gets and dims what is under it: each cell keeps its
/// glyph and its attributes, its background, its text color and the color
/// of its underline taken [opacity] of the way to [color], channel by
/// channel and rounded once (`a + (color - a) * opacity`; the terminal's
/// default colors where a cell has them); where they are null, the
/// theme's shade and its alpha (`ThemeData.shade`, `ThemeData.shadeAlpha`:
/// black at half on a dark theme, at 28 % on a light one), not rounded to
/// 255ths on the way. Text in the default color while the terminal has not
/// told it is drawn faint instead. What is under it dims again wherever it
/// repaints on its own.
///
/// The mouse does not reach what is under it: a click on it calls
/// [onDismiss], and what it does not take goes to the app's
/// `InputListener`s, as anything no `Listener` takes. Nor does a screen
/// reader: it is a [BlockSemantics].
///
/// A panel of one's own over the app, dimmed behind it, that a click
/// outside closes:
///
/// ```dart
/// Stack(
///   fit: StackFit.expand,
///   children: [
///     ModalBarrier(onDismiss: close),
///     Center(child: Panel(child: Text('Busy'))),
///   ],
/// )
/// ```
///
/// See also:
///
///  * [showDialog], which puts a dialog over one.
final class ModalBarrier extends StatelessWidget {
  /// A barrier of [color] at [alpha] or [opacity], the theme's shade where
  /// they are null, calling [onDismiss] when clicked; asserts that [alpha]
  /// is from 0 to 255, [opacity] from 0 to 1, and not both are given.
  const ModalBarrier({
    super.key,
    this.color,
    this.alpha,
    this.opacity,
    this.onDismiss,
  }) : assert(
         alpha == null || (alpha >= 0 && alpha <= 255),
         'alpha out of 0..255',
       ),
       assert(
         opacity == null || (opacity >= 0 && opacity <= 1),
         'opacity out of 0..1',
       ),
       assert(alpha == null || opacity == null, 'both alpha and opacity');

  /// What the cells under it are blended with; the theme's shade when
  /// null.
  final Color? color;

  /// How much of [color] they take, of 255: 0 leaves them as they are, 255
  /// paints them over in [color]; [opacity] where that is given, else the
  /// theme's shade alpha, when null.
  final int? alpha;

  /// How much of [color] they take, from 0 to 1, as [alpha] does in 255ths:
  /// what a fraction such as the theme's half comes to exactly, which no
  /// alpha of 255 is.
  final double? opacity;

  /// Called when a button pressed on the barrier is released there; null
  /// for a barrier a click does not dismiss.
  final void Function()? onDismiss;

  @override
  Widget build(BuildContext context) {
    final (color, opacity) = _resolve(context, this.color, alpha, this.opacity);
    return _blocking(_Shade(color, opacity), onDismiss);
  }
}

/// A [ModalBarrier] whose shade fades in and out with [animation]: it
/// takes the colors of the cells under it `opacity * curve(value)` of the
/// way to [color], the value held to 0..1, where [opacity] is what a
/// [ModalBarrier] of the same [color], [alpha] and [opacity] takes them; as
/// [animation] runs from 0 to 1, the shade comes in, and as it runs back,
/// the shade goes. Only the shade is painted again as it moves.
///
/// What runs it is the caller's, an [AnimationController] say, run
/// forward as the barrier comes and in reverse before it goes, as a
/// dialog's barrier fades in with the dialog. At any point the barrier
/// keeps the mouse and a screen reader from what is under it, and a click
/// on it calls [onDismiss], as a [ModalBarrier]'s does.
///
/// A barrier that comes in, easing out, as `controller` runs forward:
///
/// ```dart
/// AnimatedModalBarrier(
///   animation: controller,
///   curve: Curves.easeOut,
///   onDismiss: close,
/// )
/// ```
final class AnimatedModalBarrier extends StatelessWidget {
  /// A [ModalBarrier] whose shade comes in as [animation] runs along
  /// [curve], linear by default; asserts as a [ModalBarrier] does.
  const AnimatedModalBarrier({
    required this.animation,
    super.key,
    this.curve = Curves.linear,
    this.color,
    this.alpha,
    this.opacity,
    this.onDismiss,
  }) : assert(
         alpha == null || (alpha >= 0 && alpha <= 255),
         'alpha out of 0..255',
       ),
       assert(
         opacity == null || (opacity >= 0 && opacity <= 1),
         'opacity out of 0..1',
       ),
       assert(alpha == null || opacity == null, 'both alpha and opacity');

  /// How far the shade has come in, from 0 (none) to 1 (all of it).
  final ValueListenable<double> animation;

  /// Maps [animation]'s value to how far the shade has come in.
  final Curve curve;

  /// See [ModalBarrier.color].
  final Color? color;

  /// See [ModalBarrier.alpha].
  final int? alpha;

  /// See [ModalBarrier.opacity].
  final double? opacity;

  /// See [ModalBarrier.onDismiss].
  final void Function()? onDismiss;

  @override
  Widget build(BuildContext context) {
    final (color, opacity) = _resolve(context, this.color, alpha, this.opacity);
    return _blocking(
      _AnimatedShade(color, opacity, animation, curve),
      onDismiss,
    );
  }
}

/// The color and the opacity of a barrier given [color], [alpha] and
/// [opacity], the theme's where they are null.
(Color, double) _resolve(
  BuildContext context,
  Color? color,
  int? alpha,
  double? opacity,
) {
  final k = opacity ?? (alpha == null ? null : alpha / 255);
  final theme = color == null || k == null ? Theme.of(context) : null;
  return (
    color ?? theme!.shade.bg ?? const Color.rgb(0, 0, 0),
    k ?? theme!.shadeAlpha,
  );
}

/// [shade] keeping the mouse and a screen reader from what is under it, a
/// click on it calling [onDismiss].
Widget _blocking(Widget shade, void Function()? onDismiss) => BlockSemantics(
  child: onDismiss == null
      ? shade
      : Listener(onDown: _ignore, onUp: (_) => onDismiss(), child: shade),
);

void _ignore(PointerEvent event) {}

/// What an [AnimatedModalBarrier] paints: a [_Shade] whose opacity follows
/// [animation], set on the render object as it moves, nothing built.
final class _AnimatedShade extends StatefulWidget {
  const _AnimatedShade(this.color, this.opacity, this.animation, this.curve);

  final Color color;
  final double opacity;
  final ValueListenable<double> animation;
  final Curve curve;

  @override
  State<_AnimatedShade> createState() => _AnimatedShadeState();
}

final class _AnimatedShadeState extends State<_AnimatedShade> {
  @override
  void initState() {
    super.initState();
    widget.animation.addListener(_moved);
  }

  @override
  void didUpdateWidget(_AnimatedShade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.animation, widget.animation)) {
      oldWidget.animation.removeListener(_moved);
      widget.animation.addListener(_moved);
    }
  }

  @override
  void dispose() {
    widget.animation.removeListener(_moved);
    super.dispose();
  }

  double get _opacity {
    final t = widget.animation.value.clamp(0.0, 1.0);
    return widget.opacity * widget.curve.transform(t);
  }

  void _moved() {
    final shade = context.findRenderObject();
    if (shade is _RenderShade) {
      shade.opacity = _opacity;
    }
  }

  @override
  Widget build(BuildContext context) => _Shade(widget.color, _opacity);
}

/// What a [ModalBarrier] paints.
final class _Shade extends LeafRenderObjectWidget {
  const _Shade(this.color, this.opacity);

  final Color color;
  final double opacity;

  @override
  _RenderShade createRenderObject(BuildContext context) =>
      _RenderShade(color, opacity);

  @override
  void updateRenderObject(BuildContext context, _RenderShade renderObject) {
    renderObject
      ..color = color
      ..opacity = opacity;
  }
}

/// Takes the colors of the cells under it [opacity] of the way to a color:
/// those it paints over, the whole of it as its parent paints it, the
/// cells of a repaint boundary under it as that repaints on its own
/// ([RenderObject.paintOver]). Not a repaint boundary: it would blend with
/// itself.
final class _RenderShade extends RenderObject {
  _RenderShade(this._color, this._opacity);

  Color _color;
  Color get color => _color;
  set color(Color c) {
    if (c != _color) {
      _color = c;
      markNeedsPaint();
    }
  }

  double _opacity;
  double get opacity => _opacity;
  set opacity(double k) {
    if (k != _opacity) {
      _opacity = k;
      markNeedsPaint();
    }
  }

  @override
  bool get sizedByParent => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW < BoxConstraints.unbounded ? c.maxW : c.minW;
    height = c.maxH < BoxConstraints.unbounded ? c.maxH : c.minH;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.addMessage(
      'color',
      '${describeColor(_color)}/${(_opacity * 100).round()}%',
    );
  }

  /// Restyles the cells within the canvas's clip, which its parent cut to
  /// this object, a two-column glyph cut by the clip whole.
  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final styles = canvas.styles;
    final surface = canvas.surface;
    final (x0, y0, x1, y1) = canvas.clipBounds;
    final k = _opacity;
    if (x0 >= x1 || y0 >= y1 || k <= 0) {
      return;
    }
    final to = rgbOf(styles, _color, styles.defaultBackgroundRgb);
    // the style shaded last: a run of it often goes on on the next row
    var from = -1;
    var shaded = 0;
    final cells = surface.cells;
    final sty = surface.styles;
    final width = surface.width;
    for (var y = y0; y < y1; y++) {
      final row = y * width;
      var a = x0;
      var b = x1;
      if (a > 0 && (cells[row + a] & kCont) != 0) {
        a--;
      }
      if (b < width && (cells[row + b - 1] & kWide) != 0) {
        b++;
      }
      var i = row + a;
      final end = row + b;
      while (i < end) {
        final s = sty[i];
        if (s != from) {
          from = s;
          shaded = shadeStyle(styles, s, to, k);
        }
        var j = i + 1;
        while (j < end && sty[j] == s) {
          j++;
        }
        sty.fillRange(i, j, shaded);
        i = j;
      }
      surface.markDirty(y, a, b);
    }
  }
}
