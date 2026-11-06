/// Dialogs: [showDialog] puts one over the app behind a [ModalBarrier],
/// with the focus kept in it until [closeDialog]; as a route of the
/// `Navigator` above, or in an entry of the [Overlay] above without one.
/// [Dialog] is the box it is usually drawn in.
///
/// @docImport 'popover.dart';
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:twk_core/twk_core.dart'
    show
        Alignment,
        Attr,
        BoxConstraints,
        Color,
        ContainerParentDataMixin,
        ContainerRenderObjectMixin,
        CrossAxisAlignment,
        EdgeInsets,
        MainAxisSize,
        PaintContext,
        ParentData,
        RenderObject;

import '../animation/animation_controller.dart';
import '../animation/curves.dart';
import '../animation/switcher.dart' show Opacity;
import '../animation/ticker.dart';
import '../focus/focus_tree.dart';
import '../foundation/listenable_builder.dart';
import '../framework/framework.dart';
import '../layout/basic.dart';
import '../layout/box.dart';
import '../layout/child_list.dart';
import '../layout/flex.dart';
import '../layout/shadow.dart';
import '../layout/stack.dart';
import '../navigation/navigator.dart';
import '../scroll/single_child_scroll_view.dart';
import '../semantics/semantics.dart';
import '../style/style.dart';
import '../text/hit_row.dart' show segmenterOf;
import '../text/widgets.dart';
import 'barrier.dart';
import 'layer.dart';
import 'layer_escape.dart';
import 'panel.dart';

// Examples can assume:
// late BuildContext context;

/// Shows what [builder] builds placed by [alignment] over a
/// [ModalBarrier] of [barrierColor] and [barrierAlpha] (the theme's shade
/// and its alpha, `ThemeData.shade` and `ThemeData.shadeAlpha`, where
/// null); returns a future that completes with the result of
/// [closeDialog] once it is closed. The barrier and the dialog fade in
/// over [fadeIn], 160 ms by default, easing out; zero shows them at once.
///
/// With a [Navigator] above [context], the dialog is a route pushed on it
/// (the root one, the furthest above, unless [useRootNavigator] is
/// false), which is not opaque: the barrier covers the navigator, and
/// [Navigator.pop] closes the dialog too, as the navigator's back key does
/// when it is [barrierDismissible]. Without one it is shown in an entry of the
/// [Overlay] above [context], and the barrier covers the overlay; a
/// [StateError] that says where to place one if there is none.
///
/// The dialog is a [FocusScope] that takes the focus as it is shown, so a
/// node in it with `autofocus` gets it, Tab and Shift+Tab stay in it, and
/// the keys go to the node focused in it and then to those above the
/// overlay or the navigator, not to the widgets under it (those no node
/// handles go on to the app's `InputListener`s, as ever). Closed, it gives
/// the focus back to the node that had it before. When [barrierDismissible],
/// Escape (bound in a `KeyBindings` with the hint `close`, which a
/// `KeyHintsBar` lists) and a click on the barrier close it with null; on
/// a navigator, by a pop of its route as the back key pops a page
/// ([NavigatorState.maybePop]): a `PopScope` in it that cannot pop keeps
/// it open and is told so, and the navigator's observers are told it was
/// popped. [closeDialog] closes it whatever its `PopScope`s say. A
/// dialog shown over another, from either, covers it, and closed gives the
/// focus back to it.
///
/// So the [Overlay] (or the [Navigator]) goes above the app's own
/// `KeyBindings`, around them: bindings above it hear the keys the dialog
/// leaves, its `s` and `q` among them, as the app's root bindings would
/// act on them while the dialog is open. `runApp` places no overlay;
/// `App` places one under the app's theme, above the app, whose root has
/// its `KeyBindings`:
///
/// ```dart
/// App(
///   child: KeyBindings(
///     {'q': () {}},
///     child: Text('the app'),
///   ),
/// )
/// ```
///
/// A dialog on a navigator hears the keys as one in the overlay above the
/// navigator: see [Overlay], "Keys of what it shows".
///
/// It completes with null too when it leaves the tree some other way, as
/// with its overlay or navigator.
///
/// A question with two answers, its future the answer chosen, null when
/// Escape or a click outside closed it:
///
/// ```dart
/// final delete = await showDialog<bool>(
///   context: context,
///   builder: (context) => Dialog(
///     title: 'Delete the file?',
///     child: Row(
///       children: [
///         Button('Delete', onPressed: () => closeDialog(context, true)),
///         Button('Keep', onPressed: () => closeDialog(context, false)),
///       ],
///     ),
///   ),
/// );
/// ```
///
/// A box of the app's own, with no room around it and no title row (a
/// palette), at the top and with nothing dimmed: [Dialog] always has its
/// room or border, so what is shown is a [Box] or a `Panel` of the app's
/// own, the dialog being whatever [builder] builds:
///
/// ```dart
/// showDialog<void>(
///   context: context,
///   builder: (context) => SizedBox(
///     width: 40,
///     child: Box(
///       style: Theme.of(context).surface,
///       child: Text('> find a command'),
///     ),
///   ),
///   alignment: Alignment.topCenter,
///   barrierAlpha: 0,
/// );
/// ```
///
/// Placed by [alignment] alone: there is no position in cells. What is
/// at a cell or by a widget is not a dialog: a menu at a row is a
/// `ContextMenu` opened by `MenuController.open` with `at`, a panel by a
/// widget a [Popover], neither dimming what is under it.
Future<T?> showDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Alignment alignment = Alignment.center,
  Color? barrierColor,
  int? barrierAlpha,
  Duration fadeIn = const Duration(milliseconds: 160),
  bool useRootNavigator = true,
}) {
  assert(
    barrierAlpha == null || (barrierAlpha >= 0 && barrierAlpha <= 255),
    'barrierAlpha out of 0..255',
  );
  final route = _DialogRoute<T>(
    builder,
    barrierDismissible: barrierDismissible,
    alignment: alignment,
    barrierColor: barrierColor,
    barrierAlpha: barrierAlpha,
    fadeIn: fadeIn,
  );
  final navigator = Navigator.maybeOf(
    context,
    rootNavigator: useRootNavigator,
  );
  if (navigator != null) {
    return navigator.push(route);
  }
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) {
    throw StateError(
      'showDialog: no Overlay above ${context.widget.runtimeType}: place '
      'an Overlay above it, as App does around the whole app: App(child: …)',
    );
  }
  final entry = route._entry = OverlayEntry(
    builder: (_) => _DialogLayer(route),
    fadeIn: Duration.zero,
    fadeOut: Duration.zero,
  );
  overlay.insert(entry);
  return route._result.future;
}

/// Closes the dialog [context] is in, the nearest one [showDialog] shows
/// above it, wherever it is among the routes of its navigator: its future
/// completes with [result], which has to be of the type it gives (a
/// [TypeError] if not), and it is gone from the next frame on. A
/// [StateError] when [context] is in none; nothing when it is closed
/// already.
///
/// ```dart
/// Button('OK', onPressed: () => closeDialog(context, 'ok'))
/// ```
void closeDialog(BuildContext context, [Object? result]) {
  final scope = context.getInheritedWidgetOfExactType<_DialogScope>();
  if (scope == null) {
    throw StateError(
      'closeDialog: ${context.widget.runtimeType} is in no dialog: '
      'showDialog shows one',
    );
  }
  scope.route.close(result);
}

/// [child] in a box that stands out of what is around it: a raised panel
/// ([look]) of the theme's surface and text, a cell of room around
/// [padding] and no outline, [title] in bold in the text on the first row
/// inside, over [child]; and [shadow] cast beside it. With [look]
/// [PanelLook.bordered]: a border in the theme's border color where the
/// room is, [title] on its top edge. A screen reader reads it as a
/// [SemanticsRole.dialog] of its title, then what is in it.
///
/// What an app sets: [title] and [trailing], [look] (raised or bordered),
/// [shadow], [padding] (which adds the one cell of room a raised look
/// always has), [maxWidth] and [scrollable]; and in [showDialog] the
/// alignment, the barrier (`barrierAlpha` 0 for none) and whether it
/// is dismissible. The room or border and the title row are always there:
/// a box with none (a palette) is a `Panel` or a `Box` of the app's own in
/// [showDialog] (an example there), and a dialog at a cell, not an edge,
/// is a `ContextMenu` or a [Popover] (see [showDialog]).
///
/// A bordered dialog with a shadow, as [showDialog] shows it:
///
/// ```dart
/// Dialog(
///   title: 'About',
///   look: PanelLook.bordered,
///   shadow: Panel.shadowOf(Theme.of(context)),
///   child: Text('twk, a framework for terminal apps'),
/// )
/// ```
final class Dialog extends StatelessWidget {
  /// A box around [child], titled [title], a raised panel by default.
  const Dialog({
    required this.child,
    super.key,
    this.title,
    this.trailing,
    this.scrollable = false,
    this.padding = const EdgeInsets.x(1),
    this.shadow,
    this.look = PanelLook.raised,
    this.maxWidth = 72,
  });

  /// What is in the dialog.
  final Widget child;

  /// What the dialog is titled; null for nothing.
  final String? title;

  /// What is at the right end of the title row, after [title]: a counter
  /// such as `2/5 ←→`, a close hint. In the raised look the row is the
  /// first inside, [title] to the left of it (nothing to the left when
  /// [title] is null); in the bordered look it is on the top border at the
  /// right, as [title] is at the left, the box no taller for it. Null for
  /// none.
  final Widget? trailing;

  /// Whether [child] is shown in a `SingleChildScrollView` that is bounded
  /// by the room the dialog gets (the screen's height less the room, the
  /// border and the title row), so a [child] taller than that scrolls,
  /// by the keys once it has the focus and by the wheel, instead of being
  /// cut off. False by default: [child] is laid out as before, as tall as
  /// it likes.
  final bool scrollable;

  /// The cells between the room (or the border) and [child].
  final EdgeInsets padding;

  /// The shadow the box casts on what is under it, in cells of the dialog
  /// beside the box ([Shadow]); null for none.
  final BoxShadow? shadow;

  /// A raised panel, or a bordered box.
  final PanelLook look;

  /// The most columns the box takes, its room or border among them, 72 by
  /// default, and fewer where the screen is narrower; null for as many as
  /// the screen gives it. A child that takes the width it is given (a
  /// `DescriptionList`, a [Row] with an [Expanded]) makes the dialog that
  /// wide.
  final int? maxWidth;

  /// The bordered look: [title] and [trailing] both on the top edge, as a
  /// `Callout` has its close mark, the box as tall as it is without them.
  /// [trailing] is in a blank cell on either side, one `─` from the
  /// corner, built once: [_EdgeFit] keeps the box from being narrower than
  /// the title and it together.
  Widget _bordered(
    BuildContext context,
    ThemeData theme,
    String? title,
    Widget? trailing,
    Widget content,
  ) {
    final segmenter = segmenterOf(context);
    final box = Box(
      style: theme.surface.merge(theme.text),
      border: Border.all(style: theme.border),
      titles: [
        if (title != null) BorderTitle(' $title ', style: theme.text),
      ],
      padding: padding,
      child: scrollable
          ? IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [content],
              ),
            )
          : child,
    );
    if (trailing == null) {
      return box;
    }
    return _EdgeFit(
      // the edge: corner, title, `─`, blank, trailing, blank, `─`, corner
      before:
          2 +
          padding.horizontal +
          math.max(
            0,
            (title == null ? 0 : segmenter.width(' $title ')) +
                2 -
                padding.horizontal,
          ),
      children: [
        box,
        // blank cells either side, which cover the edge's line
        Box(
          style: theme.surface.merge(theme.text),
          padding: const EdgeInsets.x(1),
          child: trailing,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = this.title;
    final shadow = this.shadow;
    final p = padding;
    final trailing = this.trailing;
    final content = scrollable
        ? Flexible(child: SingleChildScrollView(child: child))
        : child;
    final plain = title == null && trailing == null && !scrollable;
    final box = switch (look) {
      PanelLook.raised => Box(
        style: theme.surface.merge(theme.text),
        padding: EdgeInsets.only(
          left: p.left + 1,
          top: p.top + 1,
          right: p.right + 1,
          bottom: p.bottom + 1,
        ),
        child: plain
            ? child
            : trailing == null && !scrollable
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // read as the dialog's label already
                  Semantics(
                    nodes: const [],
                    child: Text(
                      title!,
                      style: theme.text.merge(const Style(attrs: Attr.bold)),
                      maxLines: 1,
                    ),
                  ),
                  child,
                ],
              )
            : IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null || trailing != null)
                      SizedBox(
                        height: 1,
                        child: Row(
                          spacing: 1,
                          children: [
                            Expanded(
                              child: title == null
                                  ? const SizedBox()
                                  // read as the dialog's label already
                                  : Semantics(
                                      nodes: const [],
                                      child: Text(
                                        title,
                                        style: theme.text.merge(
                                          const Style(attrs: Attr.bold),
                                        ),
                                        maxLines: 1,
                                      ),
                                    ),
                            ),
                            ?trailing,
                          ],
                        ),
                      ),
                    content,
                  ],
                ),
              ),
      ),
      PanelLook.bordered => _bordered(context, theme, title, trailing, content),
    };
    final maxWidth = this.maxWidth;
    final sized = maxWidth == null
        ? box
        : ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: box,
          );
    return Semantics(
      role: SemanticsRole.dialog,
      label: title,
      child: shadow == null ? sized : Shadow(shadow: shadow, child: sized),
    );
  }
}

/// A dialog [showDialog] shows: a route of a navigator, or in an entry
/// of an overlay, with the future [close] completes then.
final class _DialogRoute<T> extends Route<T> {
  _DialogRoute(
    this.builder, {
    required this.barrierDismissible,
    required this.alignment,
    required this.barrierColor,
    required this.barrierAlpha,
    required this.fadeIn,
  });

  final WidgetBuilder builder;
  final bool barrierDismissible;
  final Alignment alignment;
  final Color? barrierColor;
  final int? barrierAlpha;
  final Duration fadeIn;

  // where it is shown when no navigator is above, and what it completes
  // then
  OverlayEntry? _entry;
  final _result = Completer<T?>();

  @override
  bool get opaque => false;

  @override
  bool get popsOnBack => barrierDismissible;

  @override
  Widget build(BuildContext context) => _DialogLayer(this);

  /// What Escape and a click on the barrier do: on a navigator, a pop of
  /// the route as its back key does ([NavigatorState.maybePop]), which a
  /// `PopScope` in it that cannot pop refuses and is told of; under a
  /// route shown over it, the same asked of it alone, the route removed;
  /// in an overlay, [close] with null.
  void dismiss() {
    final navigator = this.navigator;
    if (_entry != null || navigator == null) {
      close(null);
    } else if (isCurrent) {
      navigator.maybePop();
    } else if (popDisposition == RoutePopDisposition.doNotPop) {
      onPopInvokedWithResult(false, null);
    } else {
      navigator.removeRoute(this);
    }
  }

  /// Takes the dialog away and completes its future with [value], once.
  void close(Object? value) {
    final entry = _entry;
    if (entry == null) {
      if (isActive) {
        navigator!.removeRoute(this, value);
      }
      return;
    }
    if (_result.isCompleted) {
      return;
    }
    final result = value as T?;
    entry.remove();
    _result.complete(result);
  }
}

/// The barrier and the dialog over it, in a scope that takes the focus.
final class _DialogLayer extends StatefulWidget {
  const _DialogLayer(this.route);

  final _DialogRoute<Object?> route;

  @override
  State<_DialogLayer> createState() => _DialogLayerState();
}

final class _DialogLayerState extends State<_DialogLayer>
    with TickerProviderStateMixin<_DialogLayer> {
  // how far the barrier and the dialog have faded in
  late final _fade = AnimationController(
    vsync: this,
    duration: widget.route.fadeIn,
  );

  final _scope = FocusScopeNode(debugLabel: 'dialog')..modal = true;

  @override
  void initState() {
    super.initState();
    // on a navigator the route gives the focus back
    if (widget.route._entry != null) {
      _scope.returnTo = FocusNode.primaryAt(context);
    }
    if (widget.route.fadeIn > Duration.zero) {
      _fade.forward();
    } else {
      _fade.value = 1;
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    _scope.dispose();
    // a route's navigator completes it as it takes it off
    if (widget.route._entry != null) {
      widget.route.close(null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final theme = Theme.of(context);
    final color =
        route.barrierColor ?? theme.shade.bg ?? const Color.rgb(0, 0, 0);
    // as a fraction: the theme's is not a whole number of 255ths, nor is
    // a share of it as the dialog fades in
    final alpha = route.barrierAlpha;
    final opacity = alpha == null ? theme.shadeAlpha : alpha / 255;
    _scope.keysSkip = Overlay.maybeOf(context)?.keysSkip;
    return _DialogScope(
      route,
      child: ListenableBuilder(
        listenable: _fade,
        builder: (context, child) {
          final k = Curves.easeOut.transform(_fade.value);
          return Stack(
            fit: StackFit.expand,
            children: [
              ModalBarrier(
                color: color,
                opacity: opacity * k,
                onDismiss: route.barrierDismissible ? route.dismiss : null,
              ),
              Opacity(opacity: k, child: child),
            ],
          );
        },
        child: LayerEscape(
          onEscape: route.barrierDismissible ? route.dismiss : null,
          debugLabel: 'dialog',
          child: FocusScope(
            node: _scope,
            child: _TakeFocus(
              child: Align(
                alignment: route.alignment,
                child: _Built(route.builder),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Gives the scope it is in the focus as it is mounted.
final class _TakeFocus extends StatefulWidget {
  const _TakeFocus({required this.child});

  final Widget child;

  @override
  State<_TakeFocus> createState() => _TakeFocusState();
}

final class _TakeFocusState extends State<_TakeFocus> {
  var _taken = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = FocusScope.of(context);
    if (!_taken) {
      _taken = true;
      scope.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// What [builder] builds.
final class _Built extends StatelessWidget {
  const _Built(this.builder);

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => builder(context);
}

/// What finds the dialog from below.
final class _DialogScope extends InheritedWidget {
  const _DialogScope(this.route, {required super.child});

  final _DialogRoute<Object?> route;

  @override
  bool updateShouldNotify(_DialogScope oldWidget) =>
      !identical(route, oldWidget.route);
}

/// A bordered [Dialog]'s box and, over its top edge, the widget at the
/// edge's right end: the box at least as wide as `before` cells and that
/// widget are, the widget two cells from the right corner.
final class _EdgeFit extends MultiChildRenderObjectWidget {
  const _EdgeFit({required this.before, super.children});

  /// The columns the edge takes before the widget: the corner, the border
  /// and room, the title and its `─`.
  final int before;

  @override
  MultiChildRenderObjectElement createElement() => ChildListElement(this);

  @override
  _RenderEdgeFit createRenderObject(BuildContext context) =>
      _RenderEdgeFit(before);

  @override
  void updateRenderObject(BuildContext context, _RenderEdgeFit renderObject) =>
      renderObject.before = before;
}

final class _EdgeData extends ParentData with ContainerParentDataMixin {}

final class _RenderEdgeFit extends RenderObject
    with ContainerRenderObjectMixin<_EdgeData> {
  _RenderEdgeFit(this._before);

  int _before;
  int get before => _before;
  set before(int b) {
    if (b != _before) {
      _before = b;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _EdgeData) {
      child.parentData = _EdgeData();
    }
  }

  RenderObject? get _box => firstChild;
  RenderObject? get _edge => _box == null ? null : childAfter(_box!);

  int get _edgeWidth => _before + (_edge?.getMaxIntrinsicWidth(1) ?? 0);

  @override
  int computeMinIntrinsicWidth(int height) => math.max(
    _box?.getMinIntrinsicWidth(height) ?? 0,
    _edgeWidth,
  );

  @override
  int computeMaxIntrinsicWidth(int height) => math.max(
    _box?.getMaxIntrinsicWidth(height) ?? 0,
    _edgeWidth,
  );

  @override
  int computeMinIntrinsicHeight(int width) =>
      _box?.getMinIntrinsicHeight(width) ?? 0;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      _box?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void performLayout(BoxConstraints c) {
    final box = _box;
    final edge = _edge;
    if (box == null) {
      width = c.constrainWidth(0);
      height = c.constrainHeight(0);
      return;
    }
    box.layout(
      BoxConstraints(
        minWidth: math.min(math.max(c.minWidth, _edgeWidth), c.maxWidth),
        maxWidth: c.maxWidth,
        minHeight: c.minHeight,
        maxHeight: c.maxHeight,
      ),
      parentUsesSize: true,
    );
    box.parentData
      ..dx = 0
      ..dy = 0;
    width = box.width;
    height = box.height;
    if (edge != null) {
      edge.layout(
        BoxConstraints(maxWidth: math.max(0, width - 4), maxHeight: height),
        parentUsesSize: true,
      );
      edge.parentData
        ..dx = math.max(0, width - 2 - edge.width)
        ..dy = 0;
    }
  }

  @override
  void paint(PaintContext ctx) {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      paintChild(ctx, child);
    }
  }
}
