/// One child giving way to another: [AnimatedSwitcher], the
/// [SwitcherTransition]s it shows them coming and going with, and what
/// those are made of, [Opacity], [Dissolve] and [FractionalTranslation].
///
/// @docImport 'animated_builder.dart';
/// @docImport 'implicit.dart';
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        Alignment,
        Attr,
        BoxConstraints,
        Canvas,
        Color,
        PaintContext,
        Pen,
        RenderObject,
        RenderObjectWithChildMixin,
        StyleTable,
        Surface,
        kBlank,
        kCont,
        kGlyphMask,
        kWide;

import '../binding/app_binding.dart';
import '../foundation/change_notifier.dart';
import '../foundation/listenable_builder.dart';
import '../framework/framework.dart';
import '../layout/basic.dart';
import '../layout/one_child.dart';
import '../layout/stack.dart';
import 'animation_controller.dart';
import 'curves.dart';
import 'ticker.dart';

// Examples can assume:
// late AnimationController controller;
// var count = 0;

/// Shows [child], and when given one that does not update it (of another
/// type, or with another key: `Text('$n', key: ValueKey(n))`), has the new
/// one come in as the old one goes out, as [transition] shows them: the new
/// one in [duration] along [switchInCurve], the old one in
/// [reverseDuration] ([duration] when null) along [switchOutCurve], from
/// where it was when a child that had not come in all the way is replaced.
/// The children are stacked, the new one over the old ones, placed by
/// [alignment] in the room the biggest of them takes; one gone out all the
/// way is dropped. The first child shows at once; without any, the
/// switcher takes no room.
///
/// Each child comes and goes on a controller of its own, on the app's
/// clock: the switcher asks for frames while one moves, and none once they
/// are in and out.
///
/// A count whose new number slides in from below as the old one leaves at
/// the top, each with a key of its own so that the switcher tells them
/// apart:
///
/// ```dart
/// AnimatedSwitcher(
///   duration: const Duration(milliseconds: 200),
///   transition: const SwitcherTransition.slide(from: Alignment.bottomCenter),
///   child: Text('$count', key: ValueKey(count)),
/// )
/// ```
///
/// See also:
///
///  * [ImplicitlyAnimatedWidget], whose widgets run their values, not
///    their children, to new ones.
final class AnimatedSwitcher extends StatefulWidget {
  /// Shows [child], switching to a new one in [duration] with [transition],
  /// [SwitcherTransition.fade] by default.
  const AnimatedSwitcher({
    required this.duration,
    super.key,
    this.child,
    this.reverseDuration,
    this.switchInCurve = Curves.linear,
    this.switchOutCurve = Curves.linear,
    this.transition = SwitcherTransition.fade,
    this.alignment = Alignment.topLeft,
  });

  /// What it shows; another child in its place comes in as this one goes
  /// out. Null for none: the one shown goes out.
  final Widget? child;

  /// How long a new child takes to come in.
  final Duration duration;

  /// How long an old child takes to go out; [duration] when null.
  final Duration? reverseDuration;

  /// What a child coming in goes along: [Curves.linear] by default.
  final Curve switchInCurve;

  /// What a child going out goes along, from 1 back to 0:
  /// [Curves.linear] by default.
  final Curve switchOutCurve;

  /// How the children come in and go out.
  final SwitcherTransition transition;

  /// Where a child smaller than the biggest goes.
  final Alignment alignment;

  @override
  State<AnimatedSwitcher> createState() => _AnimatedSwitcherState();
}

/// How a child of an [AnimatedSwitcher] comes in and goes out: [build]
/// wraps it in what shows as much of it as `shown` says. [fade], [dissolve]
/// and [SwitcherTransition.slide]; an app's own extends it.
///
/// Two equal transitions are the same: a switcher given an equal one
/// builds its children as it did.
///
/// A transition of one's own, which has a child coming in or going out
/// fade and slide at once:
///
/// ```dart
/// final class FadeAndSlide extends SwitcherTransition {
///   const FadeAndSlide();
///
///   @override
///   Widget build(
///     Widget child,
///     ValueListenable<double> shown, {
///     required bool entering,
///   }) => ListenableBuilder(
///     listenable: shown,
///     builder: (context, child) => Opacity(
///       opacity: shown.value,
///       child: FractionalTranslation(y: 1 - shown.value, child: child),
///     ),
///     child: child,
///   );
/// }
/// ```
@immutable
abstract class SwitcherTransition {
  /// A transition; a subclass's constructor can be const.
  const SwitcherTransition();

  /// Slides the new child in from the side [from] points to and the old
  /// one out to the other side, [Alignment.centerRight] (the default) in
  /// from the right and out to the left, each moved a share of its own
  /// size and cut off at its own place ([FractionalTranslation]).
  const factory SwitcherTransition.slide({Alignment from}) = _SlideTransition;

  /// Fades the new child in over the old one, and that one out over what
  /// is under it ([Opacity]).
  static const SwitcherTransition fade = _FadeTransition();

  /// Puts the cells of the new child in place of those of the old one, a
  /// scattered few each frame ([Dissolve]).
  static const SwitcherTransition dissolve = _DissolveTransition();

  /// [child] showing as much of itself as [shown] says, from 0 (none) to 1
  /// (all of it): rising while it comes in ([entering]), falling while it
  /// goes out. Built again when [entering] changes, not as [shown] does.
  Widget build(
    Widget child,
    ValueListenable<double> shown, {
    required bool entering,
  });
}

final class _FadeTransition extends SwitcherTransition {
  const _FadeTransition();

  @override
  Widget build(
    Widget child,
    ValueListenable<double> shown, {
    required bool entering,
  }) => ListenableBuilder(
    listenable: shown,
    builder: (_, faded) => Opacity(opacity: shown.value, child: faded),
    child: child,
  );
}

final class _SlideTransition extends SwitcherTransition {
  const _SlideTransition({this.from = Alignment.centerRight});

  final Alignment from;

  @override
  Widget build(
    Widget child,
    ValueListenable<double> shown, {
    required bool entering,
  }) {
    // in from that side, out to the other one
    final x = entering ? from.x : -from.x;
    final y = entering ? from.y : -from.y;
    return ListenableBuilder(
      listenable: shown,
      builder: (_, moved) {
        final away = 1 - shown.value;
        return FractionalTranslation(x: x * away, y: y * away, child: moved);
      },
      child: child,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _SlideTransition && other.from == from;

  @override
  int get hashCode => from.hashCode;
}

final class _DissolveTransition extends SwitcherTransition {
  const _DissolveTransition();

  @override
  Widget build(
    Widget child,
    ValueListenable<double> shown, {
    required bool entering,
  }) => ListenableBuilder(
    listenable: shown,
    builder: (_, cells) =>
        Dissolve(shown: shown.value, inverse: !entering, child: cells),
    child: child,
  );
}

/// Its own [TickerProvider], not [TickerProviderStateMixin]: a child's
/// ticker goes with its controller, disposed when the child has gone.
final class _AnimatedSwitcherState extends State<AnimatedSwitcher>
    implements TickerProvider {
  _Entry? _current;
  final _leaving = <_Entry>[];
  var _serial = 0;

  @override
  Ticker createTicker(TickerCallback onTick) =>
      Ticker(onTick, binding: AppBinding.maybeOf(context));

  @override
  void initState() {
    super.initState();
    final child = widget.child;
    if (child != null) {
      _current = _entry(child, 1);
    }
  }

  @override
  void didUpdateWidget(AnimatedSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final entry in [?_current, ..._leaving]) {
      entry.controller
        ..duration = widget.duration
        ..reverseDuration = widget.reverseDuration;
    }
    final child = widget.child;
    final current = _current;
    if (current != null &&
        child != null &&
        Widget.canUpdate(current.child, child)) {
      current.child = child;
      return;
    }
    _current = null;
    if (current != null) {
      _leave(current);
    }
    if (child != null) {
      _current = _entry(child, 0)..controller.forward();
    }
  }

  _Entry _entry(Widget child, double value) => _Entry(
    this,
    child,
    AnimationController(
      vsync: this,
      duration: widget.duration,
      reverseDuration: widget.reverseDuration,
      value: value,
    ),
    ValueKey(_serial++),
  );

  /// Has [entry] go out, and dropped once it has.
  void _leave(_Entry entry) {
    final controller = entry.controller;
    entry.leaving = true;
    controller.reverse();
    if (controller.status == AnimationStatus.dismissed) {
      // it had not come in at all
      controller.dispose();
      return;
    }
    _leaving.add(entry);
    controller.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        setState(() => _leaving.remove(entry));
        controller.dispose();
      }
    });
  }

  @override
  void dispose() {
    for (final entry in [?_current, ..._leaving]) {
      entry.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    if (current == null && _leaving.isEmpty) {
      return const SizedBox.shrink();
    }
    return Stack(
      alignment: widget.alignment,
      children: [
        for (final entry in _leaving) _shown(entry),
        if (current != null) _shown(current),
      ],
    );
  }

  Widget _shown(_Entry entry) => _Slot(
    key: entry.key,
    child: widget.transition.build(
      entry.child,
      entry,
      entering: !entry.leaving,
    ),
  );
}

/// A child of an [AnimatedSwitcher], coming in or going out: how much of
/// it shows, its controller's value along the switcher's curve in, or its
/// curve out once [leaving].
final class _Entry extends ValueListenable<double> {
  _Entry(this._state, this.child, this.controller, this.key);

  final _AnimatedSwitcherState _state;
  Widget child;
  final AnimationController controller;

  /// What keeps its element as the children around it come and go.
  final Key key;

  var leaving = false;

  @override
  double get value {
    final switcher = _state.widget;
    return (leaving ? switcher.switchOutCurve : switcher.switchInCurve)
        .transform(controller.value);
  }

  @override
  void addListener(VoidCallback listener) => controller.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      controller.removeListener(listener);
}

/// [child] under a key of its own.
final class _Slot extends StatelessWidget {
  const _Slot({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Shows [child] at [opacity], from 0 (not at all: what is under it shows)
/// to 1 (as it paints), mixed with what is under it cell by cell: the
/// child's background over the one under it as by alpha ([Pen.bgAlpha]),
/// then the child's text, its color mixed with that background as the
/// alpha says, or where the child has none, or both have text and the
/// opacity is below half, the text under it, its color mixed with the
/// child's background. A text color the terminal has not told is made
/// faint instead. As big as the child.
///
/// Below 1 it keeps what was under it, so that what a repaint boundary in
/// the child repaints on its own is mixed with that again; at 0 the child
/// is not painted.
///
/// Without a child it is as small as the constraints allow.
///
/// A line shown at half strength over the background:
///
/// ```dart
/// Opacity(opacity: 0.5, child: Text('archived'))
/// ```
///
/// See also:
///
///  * [AnimatedOpacity], which runs to each new opacity.
///  * [Dissolve], which shows a share of the cells instead.
final class Opacity extends SingleChildRenderObjectWidget {
  /// Shows [child] at [opacity].
  const Opacity({required this.opacity, super.key, super.child});

  /// How much of the child shows, from 0 (none) to 1 (all of it); a value
  /// beyond them counts as the nearest.
  final double opacity;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderOpacity(_alphaOf(opacity));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderOpacity).alpha = _alphaOf(opacity);
}

/// Shows [shown] of the cells of [child], from 0 (none: what is under it
/// shows) to 1 (all), taken in a scattered order of the screen's cells,
/// the same for every Dissolve: one with [inverse] takes them from the end
/// of that order, so that at `1 - t` it shows just the cells one without
/// leaves out at t. As big as the child.
///
/// Below 1 it keeps what was under it, so that what a repaint boundary in
/// the child repaints on its own shows only in its cells; at 0 the child is
/// not painted.
///
/// Without a child it is as small as the constraints allow.
///
/// A banner whose cells show one by one as `controller` runs:
///
/// ```dart
/// AnimatedBuilder(
///   animation: controller,
///   builder: (context, child) =>
///       Dissolve(shown: controller.value, child: child),
///   child: Text('Welcome'),
/// )
/// ```
final class Dissolve extends SingleChildRenderObjectWidget {
  /// Shows [shown] of the cells of [child], from the start of their order
  /// or with [inverse] from its end.
  const Dissolve({
    required this.shown,
    super.key,
    this.inverse = false,
    super.child,
  });

  /// How many of the child's cells show, from 0 (none) to 1 (all of them);
  /// a value beyond them counts as the nearest.
  final double shown;

  /// Whether it takes the cells from the end of their order: false by
  /// default.
  final bool inverse;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDissolve(_ranksOf(shown), inverse: inverse);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderDissolve)
        ..shown = _ranksOf(shown)
        ..inverse = inverse;
}

/// Shows [child] moved [x] times its width to the right and [y] times its
/// height down (left and up where negative), to the nearest cell, and cut
/// off at the edges of its own place: as big as the child, which takes the
/// mouse where it shows.
///
/// Without a child it is as small as the constraints allow.
///
/// A line half out of its place on the right, the other half cut off:
///
/// ```dart
/// FractionalTranslation(x: 0.5, child: Text('moving out'))
/// ```
final class FractionalTranslation extends SingleChildRenderObjectWidget {
  /// Shows [child] moved by [x] times its width and [y] times its height.
  const FractionalTranslation({super.key, this.x = 0, this.y = 0, super.child});

  /// How far to the right the child is moved, in its widths; negative to
  /// the left. 0 by default.
  final double x;

  /// How far down the child is moved, in its heights; negative up. 0 by
  /// default.
  final double y;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTranslation(x, y);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderTranslation).moveTo(x, y);
}

int _alphaOf(double opacity) =>
    opacity >= 1 ? 255 : (opacity > 0 ? (opacity * 255).round() : 0);

/// The ranks of the cells a [Dissolve] shows: those below this many of
/// [_ranks].
int _ranksOf(double shown) =>
    shown >= 1 ? _ranks : (shown > 0 ? (shown * _ranks).round() : 0);

const int _ranks = 1 << 16;

/// Where the cell at [x], [y] of the screen is in the order a [Dissolve]
/// shows cells in: from 0 to [_ranks], scattered.
int _rank(int x, int y) {
  var h = (x * 0x45D9F3B + y * 0x119DE1F3) & 0xFFFFFFFF;
  h = ((h ^ (h >> 16)) * 0x45D9F3B) & 0xFFFFFFFF;
  h = ((h ^ (h >> 16)) * 0x45D9F3B) & 0xFFFFFFFF;
  return (h ^ (h >> 16)) & (_ranks - 1);
}

/// As big as its child, which it paints over what is under it and then
/// mixes with that cell by cell ([_mix]) in the cells the canvas lets it
/// paint, keeping what was under them: what a repaint boundary inside the
/// child repaints on its own is mixed with that again ([paintOver]). A
/// two-column glyph is kept whole, or blanked where only half of it is
/// left.
abstract base class _RenderMixed extends RenderObject
    with RenderObjectWithChildMixin {
  /// Whether the child shows as it paints: nothing to mix.
  bool get _whole;

  /// Whether none of the child shows: it is not painted.
  bool get _none;

  /// Mixes the cell at [x], [y] of the surface, where the child painted
  /// the glyph word [c] in style [s] over [u] in [us]: sets [_glyph] and
  /// [_style].
  void _mix(StyleTable styles, int x, int y, int c, int s, int u, int us);

  var _glyph = 0;
  var _style = 0;

  // what was under the cells _x0.._x1, _y0.._y1 of _surface when it last
  // painted, row by row
  Surface? _surface;
  var _x0 = 0;
  var _y0 = 0;
  var _x1 = 0;
  var _y1 = 0;
  var _cells = Uint32List(0);
  var _styles = Uint32List(0);

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

  @override
  void detach() {
    _surface = null;
    super.detach();
  }

  /// What it kept of the cells under it may not be under it any more (a
  /// view scrolled it, keeping the rows): it keeps them again when it
  /// paints.
  @override
  void invalidatePaintCache() => _surface = null;

  @override
  void paint(PaintContext ctx) {
    _surface = null;
    final child = this.child;
    if (child == null) {
      return;
    }
    if (_whole) {
      paintChild(ctx, child);
      return;
    }
    final canvas = ctx.canvas;
    _keep(canvas);
    if (!_none) {
      paintChild(ctx, child);
      _mixCells(canvas, _x0, _y0, _x1, _y1);
    }
  }

  @override
  bool paintsOver(RenderObject child, int x, int y, int w, int h) => !_whole;

  /// Mixes the cells the canvas is clipped to, which a repaint boundary in
  /// the child has just repainted, with what was under them.
  @override
  void paintOver(
    PaintContext ctx,
    RenderObject child,
    int x,
    int y,
    int w,
    int h,
  ) {
    final canvas = ctx.canvas;
    final (cx0, cy0, cx1, cy1) = canvas.clipBounds;
    if (!identical(canvas.surface, _surface)) {
      if (cx0 < cx1) {
        // it has nothing to mix with: on the next frame, all of it
        markNeedsPaint();
      }
      return;
    }
    _mixCells(
      canvas,
      cx0 > _x0 ? cx0 : _x0,
      cy0 > _y0 ? cy0 : _y0,
      cx1 < _x1 ? cx1 : _x1,
      cy1 < _y1 ? cy1 : _y1,
    );
  }

  /// Keeps what is in the cells the canvas is clipped to.
  void _keep(Canvas canvas) {
    final surface = canvas.surface;
    final (x0, y0, x1, y1) = canvas.clipBounds;
    final w = x1 - x0;
    final n = w > 0 && y1 > y0 ? w * (y1 - y0) : 0;
    if (_cells.length < n) {
      _cells = Uint32List(n);
      _styles = Uint32List(n);
    }
    for (var y = y0; y < y1 && w > 0; y++) {
      final from = y * surface.width + x0;
      final to = (y - y0) * w;
      _cells.setRange(to, to + w, surface.cells, from);
      _styles.setRange(to, to + w, surface.styles, from);
    }
    _surface = surface;
    _x0 = x0;
    _y0 = y0;
    _x1 = x1;
    _y1 = y1;
  }

  /// Mixes the cells [x0]..[x1], [y0]..[y1] of the surface, kept under.
  void _mixCells(Canvas canvas, int x0, int y0, int x1, int y1) {
    final surface = canvas.surface;
    final styles = canvas.styles;
    final cells = surface.cells;
    final sty = surface.styles;
    final width = surface.width;
    final kept = _x1 - _x0;
    for (var y = y0; y < y1 && x0 < x1; y++) {
      final row = y * width;
      final under = (y - _y0) * kept - _x0;
      // the cell before is the first half of a two-column glyph
      var wide = x0 > 0 && (cells[row + x0 - 1] & kWide) != 0;
      for (var x = x0; x < x1; x++) {
        final i = row + x;
        final c = cells[i];
        final u = _cells[under + x];
        if (wide) {
          wide = false;
          if (((c | u) & kCont) != 0) {
            // its second half
            cells[i] = kCont;
            sty[i] = sty[i - 1];
            continue;
          }
          if (x > x0) {
            cells[i - 1] = kBlank;
          }
        }
        _mix(styles, x, y, c, sty[i], u, _styles[under + x]);
        var glyph = _glyph;
        if ((glyph & kCont) != 0) {
          // the second half of a glyph whose first half is not here
          glyph = kBlank;
        }
        cells[i] = glyph;
        sty[i] = _style;
        wide = (glyph & kWide) != 0;
      }
      if (wide && (x1 >= width || (cells[row + x1] & kCont) == 0)) {
        cells[row + x1 - 1] = kBlank;
      }
      surface.markDirty(y, x0, x1);
    }
  }
}

/// What an [Opacity] lays out and paints: its child at [alpha] of 255.
final class _RenderOpacity extends _RenderMixed {
  _RenderOpacity(this._alpha);

  int _alpha;
  int get alpha => _alpha;
  set alpha(int a) {
    if (a != _alpha) {
      _alpha = a;
      markNeedsPaint();
    }
  }

  // the styles mixed since it last painted: by the child's style, the
  // style under it and whose text shows
  final _mixed = <int, int>{};

  @override
  bool get _whole => _alpha >= 255;

  @override
  bool get _none => _alpha <= 0;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.addMessage('opacity', '${(_alpha * 100 / 255).round()}%');
  }

  @override
  void paint(PaintContext ctx) {
    _mixed.clear();
    super.paint(ctx);
  }

  @override
  void _mix(StyleTable styles, int x, int y, int c, int s, int u, int us) {
    if (_alpha <= 0) {
      _glyph = u;
      _style = us;
      return;
    }
    if (c == u && s == us) {
      _glyph = c;
      _style = s;
      return;
    }
    final child =
        !_blank(styles, c, s) && (_alpha >= 0x80 || _blank(styles, u, us));
    _glyph = child ? c : u;
    _style = _mixed[s << 32 | us << 1 | (child ? 1 : 0)] ??= _mixStyle(
      styles,
      s,
      us,
      childText: child,
    );
  }

  /// The style of a cell where the child painted [s] over [us]: the
  /// background the child's over the one under it, and the text of the
  /// child as translucent as it ([childText]), or else the text under it
  /// seen through the child's background.
  int _mixStyle(
    StyleTable styles,
    int s,
    int us, {
    required bool childText,
  }) {
    final a = _alpha;
    final bg = _over(styles, styles.bgOf(s), a, styles.bgOf(us));
    final from = childText ? s : us;
    final text = _known(styles, styles.fgOf(from));
    var fg = styles.fgOf(from);
    var attrs = styles.attrsOf(from);
    if (text == null) {
      attrs |= Attr.dim;
    } else {
      fg = childText
          ? _over(styles, text, a, bg)
          : _over(styles, styles.bgOf(s), a, text);
    }
    return styles.style(
      fg: fg,
      bg: bg,
      attrs: attrs,
      underlineColor: styles.underlineColorOf(from),
      link: styles.linkOf(from),
    );
  }

  /// Whether the cell [c] in style [s] shows nothing but its background.
  static bool _blank(StyleTable styles, int c, int s) =>
      (c & (kGlyphMask | kWide | kCont)) == kBlank &&
      (styles.attrsOf(s) & Attr.visibleOnBlank) == 0;

  /// [color] as RGB where it is the terminal's default text color and the
  /// terminal told it; null where it did not.
  static Color? _known(StyleTable styles, Color color) {
    if (!color.isDefault) {
      return color;
    }
    final rgb = styles.defaultForegroundRgb;
    return rgb == null
        ? null
        : Color.rgb(rgb >> 16 & 0xFF, rgb >> 8 & 0xFF, rgb & 0xFF);
  }

  /// [src] at [alpha] over [dst], each as a background would be.
  static Color _over(StyleTable styles, Color src, int alpha, Color dst) =>
      src == dst
      ? src
      : styles.bgOf(
          styles.compose(
            styles.style(bg: dst),
            styles.pen(Pen(bg: src, bgAlpha: alpha)),
          ),
        );
}

/// What a [Dissolve] lays out and paints: the cells of its child whose
/// rank ([_rank]) is below [shown], or with [inverse] at least [_ranks]
/// less [shown].
final class _RenderDissolve extends _RenderMixed {
  _RenderDissolve(this._shown, {required this._inverse});

  int _shown;
  int get shown => _shown;
  set shown(int s) {
    if (s != _shown) {
      _shown = s;
      markNeedsPaint();
    }
  }

  bool _inverse;
  bool get inverse => _inverse;
  set inverse(bool i) {
    if (i != _inverse) {
      _inverse = i;
      markNeedsPaint();
    }
  }

  @override
  bool get _whole => _shown >= _ranks;

  @override
  bool get _none => _shown <= 0;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..addMessage('shown', '${(_shown * 100 / _ranks).round()}%')
      ..add('inverse', _inverse, defaultValue: false);
  }

  @override
  void _mix(StyleTable styles, int x, int y, int c, int s, int u, int us) {
    final rank = _rank(x, y);
    final shows = _inverse ? rank >= _ranks - _shown : rank < _shown;
    _glyph = shows ? c : u;
    _style = shows ? s : us;
  }
}

/// What a [FractionalTranslation] lays out and paints: its child moved by
/// [_x] times its width and [_y] times its height.
final class _RenderTranslation extends RenderObject
    with RenderObjectWithChildMixin {
  _RenderTranslation(this._x, this._y);

  double _x;
  double _y;

  /// Moves the child by [x] times its width and [y] times its height.
  void moveTo(double x, double y) {
    if (x != _x || y != _y) {
      _x = x;
      _y = y;
      _place();
      markNeedsPaint();
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add('x', _x, defaultValue: 0.0)
      ..add('y', _y, defaultValue: 0.0);
  }

  @override
  void performLayout(BoxConstraints c) {
    final child = this.child;
    if (child == null) {
      width = c.minW;
      height = c.minH;
      return;
    }
    child.layout(c, parentUsesSize: true);
    width = child.width;
    height = child.height;
    _place();
  }

  void _place() {
    final child = this.child;
    if (child != null) {
      child.parentData
        ..dx = (_x * child.width).round()
        ..dy = (_y * child.height).round();
    }
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

  @override
  void paint(PaintContext ctx) {
    final child = this.child;
    if (child != null) {
      paintChild(ctx, child);
    }
  }
}
