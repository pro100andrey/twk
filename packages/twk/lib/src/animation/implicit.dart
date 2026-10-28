/// Widgets that animate to the values they are given:
/// [ImplicitlyAnimatedWidget] and its state, which run each value from the
/// one shown to the new one; [AnimatedPadding], [AnimatedAlign],
/// [AnimatedPositioned], [AnimatedOpacity], [AnimatedDefaultTextStyle],
/// [AnimatedBox] and [TweenAnimationBuilder] of that kind; [AnimatedSize],
/// which follows the size of its child; and the tweens of what they
/// animate, [EdgeInsetsTween] and [StyleTween].
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        Alignment,
        BoxConstraints,
        Color,
        EdgeInsets,
        PaintContext,
        RenderObject,
        RenderObjectWithChildMixin;

import '../foundation/listenable_builder.dart';
import '../framework/framework.dart';
import '../layout/basic.dart';
import '../layout/box.dart';
import '../layout/one_child.dart';
import '../layout/stack.dart';
import '../style/style.dart';
import '../text/widgets.dart';
import 'animation_controller.dart';
import 'curves.dart';
import 'switcher.dart';
import 'ticker.dart';
import 'tween.dart';

// Examples can assume:
// var selected = false;
// var atEnd = false;
// var open = false;
// var read = false;
// var failed = false;
// var focused = false;
// var total = 0;
// var shown = <String>[];
// var over = false;
// late BuildContext context;

/// Makes a tween from [begin] to [end]: `Tween<double>.new`,
/// `IntTween.new`, `ColorTween.new`, `EdgeInsetsTween.new`.
typedef TweenConstructor<T> = Tween<T> Function({
  required T begin,
  required T end,
});

/// What [ImplicitlyAnimatedWidgetState.forEachTween] calls for each value
/// the widget animates: with the [tween] the state keeps for it (null at
/// first), the value the widget has now ([target]; null for none) and
/// [make], which makes a tween between two such values; returns the tween
/// the state keeps from then on, null for none.
typedef TweenVisitor = Tween<T>? Function<T extends Object>(
  Tween<T>? tween,
  T? target,
  TweenConstructor<T> make,
);

/// A widget that animates to the values it is given: whenever its parent
/// gives it one that differs, the value it shows runs from where it is to
/// the new one in [duration] along [curve]; at first it shows them as they
/// are. [onEnd] is called when a run ends.
///
/// Its state extends [ImplicitlyAnimatedWidgetState], which says what it
/// animates ([ImplicitlyAnimatedWidgetState.forEachTween]).
///
/// A bar whose width runs to each new one it is given:
///
/// ```dart
/// final class AnimatedBar extends ImplicitlyAnimatedWidget {
///   const AnimatedBar({required this.width, required super.duration});
///
///   final int width;
///
///   @override
///   State<AnimatedBar> createState() => _AnimatedBarState();
/// }
///
/// final class _AnimatedBarState
///     extends ImplicitlyAnimatedWidgetState<AnimatedBar> {
///   Tween<int>? _width;
///
///   @override
///   void forEachTween(TweenVisitor visit) =>
///       _width = visit(_width, widget.width, IntTween.new);
///
///   @override
///   Widget build(BuildContext context) => SizedBox(
///     width: _width!.transform(progress),
///     height: 1,
///     child: const ColoredBox(color: Color.blue),
///   );
/// }
/// ```
///
/// A [Color] runs as a [ColorTween] has it (`visit(_color, widget.color,
/// ColorTween.new)`), the colors of a [Style] as a [StyleTween] has them.
///
/// See also:
///
///  * [TweenAnimationBuilder], the same for a value without a widget of
///    its own.
///  * [AnimatedSwitcher], which runs from one child to another.
abstract class ImplicitlyAnimatedWidget extends StatefulWidget {
  /// A widget whose values run to new ones in [duration] along [curve],
  /// linear by default, calling [onEnd] when a run ends.
  const ImplicitlyAnimatedWidget({
    required this.duration,
    super.key,
    this.curve = Curves.linear,
    this.onEnd,
  });

  /// How long a run to new values takes.
  final Duration duration;

  /// What a run goes along: [Curves.linear] by default.
  final Curve curve;

  /// Called when a run ends at the new values; null for nothing.
  final void Function()? onEnd;
}

/// The state of an [ImplicitlyAnimatedWidget]: a tween for each value the
/// widget animates ([forEachTween]), from the value shown when the widget
/// last changed to the one it has, which [build] reads at [progress].
///
/// When a new widget has another value for any of them, every tween starts
/// again from the value it shows, and the [controller] runs from 0 to 1 in
/// the widget's duration: the state is built again each frame of the run,
/// on the app's clock, and asks for no frame once it has ended. A value
/// that goes from or to none (null) does so at once.
abstract class ImplicitlyAnimatedWidgetState<W extends ImplicitlyAnimatedWidget>
    extends State<W>
    with TickerProviderStateMixin<W> {
  /// What runs the tweens, from 0 to 1.
  @protected
  late final controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  /// How far the run is along the widget's curve: 0 where it starts, 1
  /// where it ends (and beyond them where the curve overshoots).
  @protected
  double get progress => widget.curve.transform(controller.value);

  /// Calls [visit] for each value the widget animates and keeps the tween
  /// it returns: `_padding = visit(_padding, widget.padding,
  /// EdgeInsetsTween.new)`.
  @protected
  void forEachTween(TweenVisitor visit);

  // the controller is set going in didUpdateWidget, which builds anyway
  var _quiet = false;

  // what the passes of didUpdateWidget found: a value changed; a tween
  // runs between two values
  var _changed = false;
  var _runs = false;
  var _at = 0.0;

  @override
  void initState() {
    super.initState();
    controller
      ..addListener(_moved)
      ..addStatusListener(_statusChanged);
    forEachTween(_settle);
  }

  @override
  void didUpdateWidget(W oldWidget) {
    super.didUpdateWidget(oldWidget);
    controller.duration = widget.duration;
    _changed = false;
    forEachTween(_check);
    if (!_changed) {
      return;
    }
    _at = progress;
    _runs = false;
    forEachTween(_restart);
    if (_runs) {
      _quiet = true;
      try {
        controller.forward(from: 0);
      } finally {
        _quiet = false;
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _moved() {
    if (!_quiet) {
      setState(() {});
    }
  }

  void _statusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      widget.onEnd?.call();
    }
  }

  Tween<T>? _settle<T extends Object>(
    Tween<T>? tween,
    T? target,
    TweenConstructor<T> make,
  ) => target == null ? null : make(begin: target, end: target);

  Tween<T>? _check<T extends Object>(
    Tween<T>? tween,
    T? target,
    TweenConstructor<T> make,
  ) {
    if (target != tween?.end) {
      _changed = true;
    }
    return tween;
  }

  Tween<T>? _restart<T extends Object>(
    Tween<T>? tween,
    T? target,
    TweenConstructor<T> make,
  ) {
    if (target == null) {
      return null;
    }
    final from = tween == null ? target : tween.transform(_at);
    if (from != target) {
      _runs = true;
    }
    return make(begin: from, end: target);
  }
}

/// Insets [child] by [padding] ([Padding]), each side running to its new
/// width.
///
/// Text that moves in by four cells while it is selected:
///
/// ```dart
/// AnimatedPadding(
///   padding: EdgeInsets.only(left: selected ? 4 : 0),
///   duration: const Duration(milliseconds: 150),
///   child: Text('Settings'),
/// )
/// ```
final class AnimatedPadding extends ImplicitlyAnimatedWidget {
  /// Insets [child] by [padding], running to a new one in [duration].
  const AnimatedPadding({
    required this.padding,
    required super.duration,
    super.key,
    super.curve,
    super.onEnd,
    this.child,
  });

  /// The empty cells on each side of the child that it runs to.
  final EdgeInsets padding;

  /// What is inset; null for the padding alone.
  final Widget? child;

  @override
  State<AnimatedPadding> createState() => _AnimatedPaddingState();
}

final class _AnimatedPaddingState
    extends ImplicitlyAnimatedWidgetState<AnimatedPadding> {
  Tween<EdgeInsets>? _padding;

  @override
  void forEachTween(TweenVisitor visit) =>
      _padding = visit(_padding, widget.padding, EdgeInsetsTween.new);

  @override
  Widget build(BuildContext context) =>
      Padding(padding: _padding!.transform(progress), child: widget.child);
}

/// Places [child] inside itself as [alignment] says, as [Align] does
/// without factors, the child running across to its new place a cell at a
/// time.
///
/// As big as the constraints allow; the child is laid out as loosely.
///
/// A marker that slides from one end of a row to the other:
///
/// ```dart
/// SizedBox(
///   height: 1,
///   child: AnimatedAlign(
///     alignment: atEnd ? Alignment.centerRight : Alignment.centerLeft,
///     duration: const Duration(milliseconds: 300),
///     curve: Curves.easeInOut,
///     child: Text('●'),
///   ),
/// )
/// ```
final class AnimatedAlign extends ImplicitlyAnimatedWidget {
  /// Places [child] by [alignment], running to a new one in [duration].
  const AnimatedAlign({
    required this.alignment,
    required super.duration,
    super.key,
    super.curve,
    super.onEnd,
    this.child,
  });

  /// Where the child is placed that it runs to.
  final Alignment alignment;

  /// What is placed; null for an empty box as big as the constraints
  /// allow.
  final Widget? child;

  @override
  State<AnimatedAlign> createState() => _AnimatedAlignState();
}

final class _AnimatedAlignState
    extends ImplicitlyAnimatedWidgetState<AnimatedAlign> {
  Tween<double>? _x;
  Tween<double>? _y;

  @override
  void forEachTween(TweenVisitor visit) {
    _x = visit(_x, widget.alignment.x.toDouble(), Tween<double>.new);
    _y = visit(_y, widget.alignment.y.toDouble(), Tween<double>.new);
  }

  @override
  Widget build(BuildContext context) {
    final t = progress;
    return _AlignAt(
      x: _x!.transform(t),
      y: _y!.transform(t),
      child: widget.child,
    );
  }
}

/// [child] placed as an alignment of [x], [y] (-1 to 1) would.
final class _AlignAt extends SingleChildRenderObjectWidget {
  const _AlignAt({required this.x, required this.y, super.child});

  final double x;
  final double y;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  _RenderAlignAt createRenderObject(BuildContext context) =>
      _RenderAlignAt(x, y);

  @override
  void updateRenderObject(BuildContext context, _RenderAlignAt renderObject) =>
      renderObject.alignTo(x, y);
}

/// As big as the constraints allow, its child placed as an alignment of
/// [_x], [_y] would: a share of the room left over left of it and above it,
/// half of it at 0.
final class _RenderAlignAt extends RenderObject
    with RenderObjectWithChildMixin {
  _RenderAlignAt(this._x, this._y);

  double _x;
  double _y;

  void alignTo(double x, double y) {
    if (x != _x || y != _y) {
      _x = x;
      _y = y;
      markNeedsLayout();
    }
  }

  @override
  bool get sizedByParent => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
    final child = this.child;
    if (child == null) {
      return;
    }
    child
      ..layout(BoxConstraints(0, c.maxW, 0, c.maxH), parentUsesSize: true)
      ..parentData.dx = _share(width - child.width, _x)
      ..parentData.dy = _share(height - child.height, _y);
  }

  /// The cells left of or above the child of the [free] ones around it at
  /// [a]: to the nearest cell, a half towards 0, as [Alignment.dx] has it.
  static int _share(int free, double a) {
    final v = free * (a + 1) / 2;
    return v >= 0 ? (v - 0.5).ceil() : -(-v - 0.5).ceil();
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

/// Pins [child] to the edges of the [Stack] it is in as [Positioned] does,
/// each edge and length running to its new place a cell at a time; one
/// given where there was none, or taken away, at once. It goes inside a
/// [Stack] with no render object widget in between.
///
/// At most two of [left], [right] and [width] are given, and of [top],
/// [bottom] and [height]: it asserts so. A length below 0 on the way counts
/// as 0.
///
/// A panel that slides in from the right edge when it is open:
///
/// ```dart
/// Stack(
///   children: [
///     Text('main view'),
///     AnimatedPositioned(
///       top: 0,
///       bottom: 0,
///       right: open ? 0 : -30,
///       width: 30,
///       duration: const Duration(milliseconds: 200),
///       child: Box(border: const Border.all(), child: Text('details')),
///     ),
///   ],
/// )
/// ```
final class AnimatedPositioned extends ImplicitlyAnimatedWidget {
  /// Pins [child] by the edges and lengths given, running to new ones in
  /// [duration].
  const AnimatedPositioned({
    required this.child,
    required super.duration,
    super.key,
    super.curve,
    super.onEnd,
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.width,
    this.height,
  }) : assert(
         left == null || right == null || width == null,
         'at most two of left, right and width',
       ),
       assert(
         top == null || bottom == null || height == null,
         'at most two of top, bottom and height',
       );

  /// What is pinned.
  final Widget child;

  /// The cells between the stack's left edge and the child's; null for
  /// none given.
  final int? left;

  /// The cells between the stack's top edge and the child's; null for
  /// none given.
  final int? top;

  /// The cells between the child's right edge and the stack's; null for
  /// none given.
  final int? right;

  /// The cells between the child's bottom edge and the stack's; null for
  /// none given.
  final int? bottom;

  /// The child's width; null for none given.
  final int? width;

  /// The child's height; null for none given.
  final int? height;

  @override
  State<AnimatedPositioned> createState() => _AnimatedPositionedState();
}

final class _AnimatedPositionedState
    extends ImplicitlyAnimatedWidgetState<AnimatedPositioned> {
  Tween<int>? _left;
  Tween<int>? _top;
  Tween<int>? _right;
  Tween<int>? _bottom;
  Tween<int>? _width;
  Tween<int>? _height;

  @override
  void forEachTween(TweenVisitor visit) {
    _left = visit(_left, widget.left, IntTween.new);
    _top = visit(_top, widget.top, IntTween.new);
    _right = visit(_right, widget.right, IntTween.new);
    _bottom = visit(_bottom, widget.bottom, IntTween.new);
    _width = visit(_width, widget.width, IntTween.new);
    _height = visit(_height, widget.height, IntTween.new);
  }

  @override
  Widget build(BuildContext context) {
    final t = progress;
    return Positioned(
      left: _left?.transform(t),
      top: _top?.transform(t),
      right: _right?.transform(t),
      bottom: _bottom?.transform(t),
      width: _cells(_width?.transform(t)),
      height: _cells(_height?.transform(t)),
      child: widget.child,
    );
  }
}

/// Shows [child] at [opacity] ([Opacity]), running to the new one.
///
/// A hint that fades out once it has been read:
///
/// ```dart
/// AnimatedOpacity(
///   opacity: read ? 0 : 1,
///   duration: const Duration(milliseconds: 400),
///   child: Text('Press ? for help'),
/// )
/// ```
final class AnimatedOpacity extends ImplicitlyAnimatedWidget {
  /// Shows [child] at [opacity], running to a new one in [duration].
  const AnimatedOpacity({
    required this.opacity,
    required super.duration,
    super.key,
    super.curve,
    super.onEnd,
    this.child,
  });

  /// How much of the child shows that it runs to, from 0 (none) to 1 (all
  /// of it).
  final double opacity;

  /// What is shown; null for nothing.
  final Widget? child;

  @override
  State<AnimatedOpacity> createState() => _AnimatedOpacityState();
}

final class _AnimatedOpacityState
    extends ImplicitlyAnimatedWidgetState<AnimatedOpacity> {
  Tween<double>? _opacity;

  @override
  void forEachTween(TweenVisitor visit) =>
      _opacity = visit(_opacity, widget.opacity, Tween<double>.new);

  @override
  Widget build(BuildContext context) =>
      Opacity(opacity: _opacity!.transform(progress), child: widget.child);
}

/// The style the [Text]s below it are drawn in ([DefaultTextStyle]), its
/// colors running to the new ones ([StyleTween]).
///
/// A status line that turns red on an error:
///
/// ```dart
/// AnimatedDefaultTextStyle(
///   style: Style(fg: failed ? Color.red : Color.green),
///   duration: const Duration(milliseconds: 250),
///   child: Text(failed ? 'failed' : 'ok'),
/// )
/// ```
final class AnimatedDefaultTextStyle extends ImplicitlyAnimatedWidget {
  /// Draws the texts of [child] in [style], running to a new one in
  /// [duration].
  const AnimatedDefaultTextStyle({
    required this.style,
    required this.child,
    required super.duration,
    super.key,
    super.curve,
    super.onEnd,
  });

  /// The style the texts below it are drawn in that it runs to.
  final Style style;

  /// What is below it.
  final Widget child;

  @override
  State<AnimatedDefaultTextStyle> createState() =>
      _AnimatedDefaultTextStyleState();
}

final class _AnimatedDefaultTextStyleState
    extends ImplicitlyAnimatedWidgetState<AnimatedDefaultTextStyle> {
  Tween<Style>? _style;

  @override
  void forEachTween(TweenVisitor visit) =>
      _style = visit(_style, widget.style, StyleTween.new);

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    style: _style!.transform(progress),
    child: widget.child,
  );
}

/// A [Box] around [child] made [width] wide and [height] tall where they
/// are given ([SizedBox]), its [style], the styles of its [border],
/// [padding] and size running to the new ones: colors as [StyleTween] has
/// them, lengths a cell at a time. A border of another type switches
/// halfway, as does a value given where there was none, or taken away;
/// [titles] change at once.
///
/// A panel whose border lights up while it has the focus:
///
/// ```dart
/// AnimatedBox(
///   border: Border.all(
///     style: Style(fg: focused ? Color.cyan : Color.brightBlack),
///   ),
///   titles: const [BorderTitle(' Files ')],
///   duration: const Duration(milliseconds: 200),
///   child: Text('README.md'),
/// )
/// ```
final class AnimatedBox extends ImplicitlyAnimatedWidget {
  /// A box around [child] that runs to new values in [duration].
  const AnimatedBox({
    required super.duration,
    super.key,
    super.curve,
    super.onEnd,
    this.style,
    this.border,
    this.titles = const [],
    this.padding = EdgeInsets.zero,
    this.width,
    this.height,
    this.child,
  });

  /// What the box is filled with, as [Box.style]; null leaves what is
  /// under it.
  final Style? style;

  /// The lines around the box, as [Box.border]; null for none.
  final Border? border;

  /// The titles on the border's edges, as [Box.titles]: none by default.
  final List<BorderTitle> titles;

  /// The cells between the border and the child: none by default.
  final EdgeInsets padding;

  /// The width of the box; null for the width its child and the
  /// constraints give it.
  final int? width;

  /// The height of the box; null for the height its child and the
  /// constraints give it.
  final int? height;

  /// What is in the box; null for an empty one.
  final Widget? child;

  @override
  State<AnimatedBox> createState() => _AnimatedBoxState();
}

final class _AnimatedBoxState
    extends ImplicitlyAnimatedWidgetState<AnimatedBox> {
  Tween<Style>? _style;
  Tween<Border>? _border;
  Tween<EdgeInsets>? _padding;
  Tween<int>? _width;
  Tween<int>? _height;

  @override
  void forEachTween(TweenVisitor visit) {
    _style = visit(_style, widget.style, StyleTween.new);
    _border = visit(_border, widget.border, _BorderTween.new);
    _padding = visit(_padding, widget.padding, EdgeInsetsTween.new);
    _width = visit(_width, widget.width, IntTween.new);
    _height = visit(_height, widget.height, IntTween.new);
  }

  @override
  Widget build(BuildContext context) {
    final t = progress;
    return SizedBox(
      width: _cells(_width?.transform(t)),
      height: _cells(_height?.transform(t)),
      child: Box(
        style: _style?.transform(t),
        border: _border?.transform(t),
        titles: widget.titles,
        padding: _padding!.transform(t),
        child: widget.child,
      ),
    );
  }
}

/// Builds [builder] with a value that runs to [value] whenever it changes,
/// from the one shown then, in [duration] along [curve], through the
/// tweens [tween] makes between two values (`Tween<double>.new`,
/// `ColorTween.new`, `StyleTween.new`); at first it shows [value], or
/// runs to it from [from] when that is given. [child] is handed to
/// [builder] as a [ListenableBuilder]'s.
///
/// A count that runs up to each new total:
///
/// ```dart
/// TweenAnimationBuilder<int>(
///   value: total,
///   tween: IntTween.new,
///   duration: const Duration(milliseconds: 500),
///   builder: (context, value, child) => Text('$value files'),
/// )
/// ```
final class TweenAnimationBuilder<T extends Object>
    extends ImplicitlyAnimatedWidget {
  /// Builds [builder] with a value that runs to [value] in [duration],
  /// from [from] at first when given.
  const TweenAnimationBuilder({
    required this.value,
    required this.tween,
    required this.builder,
    required super.duration,
    super.key,
    super.curve,
    super.onEnd,
    this.from,
    this.child,
  });

  /// What the value runs to.
  final T value;

  /// Where the value starts at first; null to start at [value].
  final T? from;

  /// Makes the tween between two values: `Tween<double>.new`,
  /// `IntTween.new`, `ColorTween.new`, `StyleTween.new`.
  // called by the state, whose T is the widget's own
  // ignore: unsafe_variance
  final TweenConstructor<T> tween;

  /// Builds the widget for the value shown, each frame of a run.
  // called by the state, whose T is the widget's own
  // ignore: unsafe_variance
  final ValueWidgetBuilder<T> builder;

  /// What [builder] is handed as its child, built once by the parent; null
  /// for none.
  final Widget? child;

  @override
  State<TweenAnimationBuilder<T>> createState() =>
      _TweenAnimationBuilderState<T>();
}

final class _TweenAnimationBuilderState<T extends Object>
    extends ImplicitlyAnimatedWidgetState<TweenAnimationBuilder<T>> {
  Tween<T>? _value;

  @override
  void initState() {
    super.initState();
    final from = widget.from;
    if (from != null && from != widget.value) {
      _value = widget.tween(begin: from, end: widget.value);
      controller.forward();
    }
  }

  @override
  void forEachTween(TweenVisitor visit) =>
      _value = visit(_value, widget.value, widget.tween);

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _value!.transform(progress), widget.child);
}

/// As big as [child], and when the child's size changes, running to the
/// new size from the one it shows in [duration] along [curve], a cell at a
/// time: the child laid out at its new size, placed by [alignment] and cut
/// off where it is bigger than this. Its first size it takes at once, and
/// outside an app every size.
///
/// Without a child it is as small as the constraints allow. A run cut
/// short when it leaves the tree ends at the child's size.
///
/// A panel that grows and shrinks with its lines, as more are shown:
///
/// ```dart
/// AnimatedSize(
///   duration: const Duration(milliseconds: 200),
///   child: Column(
///     children: [
///       for (final line in shown) Text(line),
///     ],
///   ),
/// )
/// ```
final class AnimatedSize extends StatefulWidget {
  /// Follows the size of [child], running to a new one in [duration].
  const AnimatedSize({
    required this.duration,
    super.key,
    this.curve = Curves.linear,
    this.alignment = Alignment.topLeft,
    this.child,
  });

  /// How long a run to the child's new size takes; zero or less for none,
  /// the size taken at once.
  final Duration duration;

  /// What a run goes along: [Curves.linear] by default.
  final Curve curve;

  /// Where the child is placed in the size shown while it runs:
  /// [Alignment.topLeft] by default.
  final Alignment alignment;

  /// What it follows the size of; null for none.
  final Widget? child;

  @override
  State<AnimatedSize> createState() => _AnimatedSizeState();
}

final class _AnimatedSizeState extends State<AnimatedSize>
    with TickerProviderStateMixin {
  @override
  Widget build(BuildContext context) => _SizeTo(
    vsync: this,
    duration: widget.duration,
    curve: widget.curve,
    alignment: widget.alignment,
    child: widget.child,
  );
}

final class _SizeTo extends SingleChildRenderObjectWidget {
  const _SizeTo({
    required this.vsync,
    required this.duration,
    required this.curve,
    required this.alignment,
    super.child,
  });

  final TickerProvider vsync;
  final Duration duration;
  final Curve curve;
  final Alignment alignment;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  _RenderSizeTo createRenderObject(BuildContext context) => _RenderSizeTo(
    vsync: vsync,
    duration: duration,
    curve: curve,
    alignment: alignment,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderSizeTo renderObject) {
    renderObject
      ..duration = duration
      ..curve = curve
      ..alignment = alignment;
  }
}

/// What an [AnimatedSize] lays out and paints: a run from the size it
/// showed when its child's last changed to the child's, on a ticker of
/// its own.
final class _RenderSizeTo extends RenderObject with RenderObjectWithChildMixin {
  _RenderSizeTo({
    required TickerProvider vsync,
    required this.duration,
    required this.curve,
    required this._alignment,
  }) {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;
  Duration duration;
  Curve curve;

  Alignment _alignment;
  Alignment get alignment => _alignment;
  set alignment(Alignment a) {
    if (a != _alignment) {
      _alignment = a;
      markNeedsLayout();
    }
  }

  // the run: from the size shown to the child's, _t of the way; no size
  // before the first layout with a child
  var _fromW = 0;
  var _fromH = 0;
  int? _toW;
  var _toH = 0;
  var _t = 1.0;

  void _tick(Duration elapsed) {
    final d = duration.inMicroseconds;
    _t = d <= 0 ? 1 : elapsed.inMicroseconds / d;
    if (_t >= 1) {
      _t = 1;
      _ticker.stop();
    }
    markNeedsLayout();
  }

  @override
  void detach() {
    // a run cut short ends where it was going
    _ticker.stop();
    _t = 1;
    super.detach();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    if (_t < 1) {
      properties.addMessage('running to', '$_toW×$_toH');
    }
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
    final w = child.width;
    final h = child.height;
    if (_toW == null || _ticker.binding == null || duration <= Duration.zero) {
      _t = 1;
    } else if (w != _toW || h != _toH) {
      _fromW = width;
      _fromH = height;
      _t = 0;
      _ticker
        ..stop()
        ..start();
    }
    _toW = w;
    _toH = h;
    final e = curve.transform(_t);
    width = c.constrainW((_fromW + (w - _fromW) * e).round());
    height = c.constrainH((_fromH + (h - _fromH) * e).round());
    child.parentData
      ..dx = _alignment.dx(width - w)
      ..dy = _alignment.dy(height - h);
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

/// Between two insets, each side the whole number of cells nearest to as
/// far from [begin]'s to [end]'s as t says, none fewer than 0.
///
/// ```dart
/// final inset = const EdgeInsetsTween(
///   begin: EdgeInsets.zero,
///   end: EdgeInsets.all(4),
/// ).transform(0.5); // 2 cells on each side
/// ```
class EdgeInsetsTween extends Tween<EdgeInsets> {
  /// A tween of insets from [begin] to [end].
  const EdgeInsetsTween({required super.begin, required super.end});

  @override
  EdgeInsets lerp(double t) {
    int side(int a, int b) {
      final v = (a + (b - a) * t).round();
      return v < 0 ? 0 : v;
    }

    return EdgeInsets.only(
      left: side(begin.left, end.left),
      top: side(begin.top, end.top),
      right: side(begin.right, end.right),
      bottom: side(begin.bottom, end.bottom),
    );
  }
}

/// Between two styles: each color as a [ColorTween] has it, with its
/// alpha as far from [begin]'s to [end]'s as t says; a color one of them
/// leaves unset fading in or out through its alpha, from or to 0. The
/// attributes, underline kind and link switch halfway, as does an
/// underline color one of them leaves unset.
///
/// A count whose color runs from the theme's text to its error color as
/// it goes past a limit:
///
/// ```dart
/// TweenAnimationBuilder<Style>(
///   value: over ? Theme.of(context).error : Theme.of(context).text,
///   tween: StyleTween.new,
///   duration: const Duration(milliseconds: 300),
///   builder: (context, style, child) => Text('$total', style: style),
/// )
/// ```
class StyleTween extends Tween<Style> {
  /// A tween of styles from [begin] to [end].
  const StyleTween({required super.begin, required super.end});

  @override
  Style lerp(double t) {
    final a = begin;
    final b = end;
    final (fg, fgAlpha) = _color(a.fg, a.fgAlpha, b.fg, b.fgAlpha, t);
    final (bg, bgAlpha) = _color(a.bg, a.bgAlpha, b.bg, b.bgAlpha, t);
    final half = t < 0.5 ? a : b;
    final au = a.underlineColor;
    final bu = b.underlineColor;
    return Style(
      fg: fg,
      bg: bg,
      fgAlpha: fgAlpha,
      bgAlpha: bgAlpha,
      underlineColor: au != null && bu != null
          ? ColorTween(begin: au, end: bu).transform(t)
          : half.underlineColor,
      attrs: half.attrs,
      attrsOff: half.attrsOff,
      link: half.link,
    );
  }

  static (Color?, int) _color(Color? a, int aa, Color? b, int ba, double t) {
    int alpha(int from, int to) =>
        (from + (to - from) * t).round().clamp(0, 255);
    if (a == null) {
      return b == null ? (null, 255) : (b, alpha(0, ba));
    }
    if (b == null) {
      return (a, alpha(aa, 0));
    }
    return (ColorTween(begin: a, end: b).transform(t), alpha(aa, ba));
  }
}

/// Between two borders: the style of a side both have as a [StyleTween]
/// has it; the type, whether it merges, and a side one of them has not,
/// switching halfway.
final class _BorderTween extends Tween<Border> {
  const _BorderTween({required super.begin, required super.end});

  @override
  Border lerp(double t) {
    final half = t < 0.5 ? begin : end;
    Style? side(Style? a, Style? b, Style? halfway) => a != null && b != null
        ? StyleTween(begin: a, end: b).transform(t)
        : halfway;
    return Border(
      type: half.type,
      top: side(begin.top, end.top, half.top),
      right: side(begin.right, end.right, half.right),
      bottom: side(begin.bottom, end.bottom, half.bottom),
      left: side(begin.left, end.left, half.left),
      merge: half.merge,
    );
  }
}

/// [cells], none fewer than 0.
int? _cells(int? cells) => cells == null || cells >= 0 ? cells : 0;
