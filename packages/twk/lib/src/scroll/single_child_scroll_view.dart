/// [SingleChildScrollView]: one child, as long as it likes, scrolled in a
/// window.
library;

import 'package:twk_core/twk_core.dart'
    show Axis, Color, RenderObject, RenderViewport;

import '../focus/focus.dart';
import '../framework/framework.dart';
import '../style/style.dart';
import 'scrollable.dart';

/// Shows [child] in a window that scrolls along [scrollDirection] (a
/// [Scrollable]: keys, the wheel, [controller]). The child is laid out as
/// long as it likes along the axis and within the constraints across it,
/// the window as big as the child within the constraints: a `Column` in it
/// is as tall as its children, whatever its `mainAxisSize`.
///
/// It fills the window with [style] over the theme's background and text,
/// under the child: a window inside a `Box` with a background of its own
/// takes it as its [style] too. Scrolled along a vertical axis while all
/// of it is on the screen, it has the terminal move the rows that stay in
/// view (a hardware scroll) and paints only those the scroll brought in.
///
/// A form taller than the terminal, scrolled by the keys once it has the
/// focus:
///
/// ```dart
/// SingleChildScrollView(
///   autofocus: true,
///   child: Column(
///     children: [for (var i = 1; i <= 40; i++) Text('field $i')],
///   ),
/// )
/// ```
///
/// See also:
///
///  * `ListView`, which builds only the rows in view, for content too long
///    to build whole.
///  * [Scrollable], what it scrolls with, for a viewport of one's own.
final class SingleChildScrollView extends StatelessWidget {
  /// Shows [child] in a window that scrolls along [scrollDirection],
  /// vertically by default.
  const SingleChildScrollView({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.controller,
    this.style,
    this.focusNode,
    this.autofocus = false,
    this.canRequestFocus,
    this.wheelAcceleration = WheelAcceleration.none,
    this.keyHints = true,
    this.child,
  });

  /// The axis it scrolls along.
  final Axis scrollDirection;

  /// See [Scrollable.controller].
  final ScrollController? controller;

  /// What fills the window under the child, over [ThemeData.background]
  /// and [ThemeData.text].
  final Style? style;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// See [FocusNode.canRequestFocus].
  final bool? canRequestFocus;

  /// See [Scrollable.wheelAcceleration].
  final WheelAcceleration wheelAcceleration;

  /// Whether the keys that would scroll it carry their hints, for a
  /// `KeyHintsBar`, true by default: none while all of it is in the window
  /// ([Scrollable.keyHints]).
  final bool keyHints;

  /// What it scrolls; null shows nothing.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = const Style(
      fg: Color.defaultColor,
      bg: Color.defaultColor,
    ).merge(theme.background).merge(theme.text).merge(style ?? const Style());
    return Scrollable(
      scrollDirection: scrollDirection,
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      canRequestFocus: canRequestFocus,
      wheelAcceleration: wheelAcceleration,
      keyHints: keyHints,
      viewportBuilder: (context, position) => _Viewport(
        position: position,
        background: background,
        child: child,
      ),
    );
  }
}

/// The window of a [SingleChildScrollView]: a [RenderViewport] at
/// [position]'s offset, moved as the position moves without a build, that
/// tells the position its extents.
final class _Viewport extends SingleChildRenderObjectWidget {
  const _Viewport({
    required this.position,
    required this.background,
    super.child,
  });

  final ScrollPosition position;
  final Style background;

  @override
  _ViewportElement createElement() => _ViewportElement(this);

  @override
  RenderViewport createRenderObject(BuildContext context) => RenderViewport(
    axis: position.axis,
    scrollOffset: position.offset,
    background: background.pen,
    onExtents: position.applyExtents,
  );

  @override
  void updateRenderObject(BuildContext context, RenderViewport renderObject) {
    renderObject
      ..axis = position.axis
      ..background = background.pen
      ..onExtents = position.applyExtents
      ..scrollOffset = position.offset;
  }
}

/// The element of a [_Viewport]: it moves the render object to the
/// position's offset each time the position moves.
final class _ViewportElement extends SingleChildRenderObjectElement {
  _ViewportElement(_Viewport super.widget);

  ScrollPosition? _position;

  @override
  _Viewport get widget => super.widget as _Viewport;

  @override
  RenderViewport get renderObject => super.renderObject as RenderViewport;

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    _follow(widget.position);
  }

  @override
  void update(covariant _Viewport newWidget) {
    super.update(newWidget);
    _follow(newWidget.position);
  }

  @override
  void unmount() {
    _position?.removeListener(_moved);
    _position = null;
    super.unmount();
  }

  void _follow(ScrollPosition position) {
    if (!identical(position, _position)) {
      _position?.removeListener(_moved);
      _position = position..addListener(_moved);
    }
  }

  void _moved() => renderObject.scrollOffset = _position!.offset;

  @override
  void insertRenderObjectChild(RenderObject child, Object? slot) =>
      renderObject.child = child;

  @override
  void moveRenderObjectChild(
    RenderObject child,
    Object? oldSlot,
    Object? newSlot,
  ) => throw UnsupportedError('one child does not move: $this');

  @override
  void removeRenderObjectChild(RenderObject child, Object? slot) {
    assert(identical(renderObject.child, child), '$child is not the child');
    renderObject.child = null;
  }
}
