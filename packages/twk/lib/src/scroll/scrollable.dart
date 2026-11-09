/// Scrolling in cells: the [ScrollPosition] of a [Scrollable], the
/// [ScrollController] that reads and moves it, and the
/// [ScrollNotification]s it sends up the tree as it moves.
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        Axis,
        KeyCode,
        KeyEvent,
        KeyKind,
        RenderObject,
        RenderObjectWithChildMixin;

import '../binding/app_binding.dart';
import '../focus/focus.dart';
import '../focus/hinted_keys.dart';
import '../foundation/change_notifier.dart';
import '../framework/framework.dart';
import '../gestures/mouse.dart';
import 'scroll_behavior.dart';
import 'scroll_input.dart';

// Examples can assume:
// late String line;

/// Where a scrollable view is along its [axis]: [pixels] cells of its
/// content scrolled off its start, out of [maxScrollExtent], with
/// [viewportDimension] cells of it in its window.
///
/// What a [ScrollNotification] carries, and [ScrollPosition.metrics]
/// returns. Two are equal when all four are.
@immutable
final class ScrollMetrics {
  /// Where a view is: [pixels] of [maxScrollExtent], [viewportDimension]
  /// cells in the window, along [axis], vertical by default.
  const ScrollMetrics({
    required this.pixels,
    required this.maxScrollExtent,
    required this.viewportDimension,
    this.axis = Axis.vertical,
  });

  /// The cells of the content before the window.
  final int pixels;

  /// The largest [pixels]: the content's extent less the window's, 0 when
  /// all of it fits.
  final int maxScrollExtent;

  /// The cells of the content the window shows.
  final int viewportDimension;

  /// The axis the view scrolls along.
  final Axis axis;

  /// The cells of the content after the window; 0 at the end, and when
  /// [pixels] is past [maxScrollExtent].
  int get extentAfter =>
      maxScrollExtent - pixels < 0 ? 0 : maxScrollExtent - pixels;

  /// Whether the window shows the content's start.
  bool get atStart => pixels <= 0;

  /// Whether the window shows the content's end.
  bool get atEnd => pixels >= maxScrollExtent;

  @override
  bool operator ==(Object other) =>
      other is ScrollMetrics &&
      other.pixels == pixels &&
      other.maxScrollExtent == maxScrollExtent &&
      other.viewportDimension == viewportDimension &&
      other.axis == axis;

  @override
  int get hashCode =>
      Object.hash(pixels, maxScrollExtent, viewportDimension, axis);

  @override
  String toString() =>
      'ScrollMetrics(${axis.name} $pixels of $maxScrollExtent, '
      'window $viewportDimension)';
}

/// Where a [Scrollable] is scrolled to, in cells along its [axis]: the
/// [pixels], kept from 0 to [maxScrollExtent] once its viewport has told it its
/// extents ([applyExtents]); an offset set before that is kept until then.
/// The scrollable makes it and keeps it while it is mounted; a
/// [ScrollController] given to the scrollable reads and moves it, and
/// [Scrollable.of] finds it from below.
///
/// Its listeners are told when the offset changes, and when the extents
/// do. A move by [jumpTo], or by a key or the wheel, sends a
/// [ScrollUpdateNotification] up from the scrollable; a key or the wheel
/// that would move it past an end sends an [OverscrollNotification].
///
/// While its scrollable's controller [ScrollController.stickToEnd]s and
/// the window shows the end, it keeps showing it as the content grows,
/// [pixels] following [maxScrollExtent]; moved away from the end, it stays
/// where it is until it is moved back. In [reverse], the end it keeps is the
/// one End goes to: offset 0, at the bottom (the right).
final class ScrollPosition with ChangeNotifier {
  ScrollPosition._(this._axis, this._pixels, this._state, this._reverse)
    : _stuck = _pixels == 0;

  Axis _axis;

  /// The axis it scrolls along.
  Axis get axis => _axis;

  bool _reverse;

  /// Whether the scrollable shows the start of its content at the end of
  /// its axis, at the bottom (the right): offset 0 shows the bottom, and
  /// the offset grows as the window goes up ([Scrollable.reverse]).
  bool get reverse => _reverse;

  // whether the window showed the end stickToEnd keeps when it last
  // moved or settled; before its extents, whether it starts at the end
  bool _stuck;

  int _pixels;

  /// The cells of the content scrolled off the start.
  int get pixels => _pixels;

  var _maxScrollExtent = 0;
  var _viewportDimension = 0;
  var _hasExtents = false;

  // the scrollable it is the position of, while mounted
  _ScrollableState? _state;

  /// The largest [pixels]: the content's extent less the window's; 0 until
  /// the viewport is laid out.
  int get maxScrollExtent => _maxScrollExtent;

  /// The cells of the content the window shows; 0 until the viewport is
  /// laid out.
  int get viewportDimension => _viewportDimension;

  /// Whether the viewport has told it its extents.
  bool get hasExtents => _hasExtents;

  /// Its offset and extents, as a notification carries them.
  ScrollMetrics get metrics => ScrollMetrics(
    pixels: _pixels,
    maxScrollExtent: _maxScrollExtent,
    viewportDimension: _viewportDimension,
    axis: _axis,
  );

  /// Scrolls to [offset], kept within 0 and [maxScrollExtent]; a move sends a
  /// [ScrollUpdateNotification] up from the scrollable.
  void jumpTo(int offset) {
    final to = _clamp(offset);
    final delta = to - _pixels;
    if (delta == 0) {
      return;
    }
    _pixels = to;
    _stuck = _reverse ? to <= 0 : _hasExtents && to >= _maxScrollExtent;
    notifyListeners();
    final state = _state;
    if (state != null && state.mounted) {
      ScrollUpdateNotification(
        metrics: metrics,
        context: state.context,
        scrollDelta: delta,
      ).dispatch(state.context);
    }
  }

  /// Whether [target] is inside the scrollable's viewport, as it was laid
  /// out last.
  bool _holds(RenderObject target) {
    final viewport = _state?._viewport;
    if (viewport == null || identical(target, viewport)) {
      return false;
    }
    for (RenderObject? o = target; o != null; o = o.parent) {
      if (identical(o, viewport)) {
        return true;
      }
    }
    return false;
  }

  /// Scrolls the least that shows [target], a render object inside the
  /// scrollable's viewport, as it was laid out last: its start (its end,
  /// in [reverse]) when it is longer than the window. An [ArgumentError]
  /// when it is not inside.
  void ensureVisible(RenderObject target) {
    final viewport = _state?._viewport;
    if (viewport == null) {
      return;
    }
    final vertical = _axis == Axis.vertical;
    var at = 0;
    RenderObject? o = target;
    for (; o != null && !identical(o, viewport); o = o.parent) {
      at += vertical ? o.parentData.dy : o.parentData.dx;
    }
    if (o == null || identical(target, viewport)) {
      throw ArgumentError.value(target, 'target', 'not inside the viewport');
    }
    // along the axis on screen: in reverse, the cells of the content
    // above the window are those after it
    final shown = _reverse ? _maxScrollExtent - _pixels : _pixels;
    final start = at + shown;
    final end = start + (vertical ? target.height : target.width);
    final top = end - _viewportDimension;
    int? to;
    if (_reverse) {
      if (end > shown + _viewportDimension) {
        to = top;
      } else if (start < shown) {
        to = top > start ? top : start;
      }
    } else if (start < shown) {
      to = start;
    } else if (end > shown + _viewportDimension) {
      to = top < start ? top : start;
    }
    if (to != null) {
      jumpTo(_reverse ? _maxScrollExtent - to : to);
    }
  }

  /// Takes the extents of the viewport, laid out: [viewport] cells of the
  /// content's [content] in the window. What the viewport's layout calls;
  /// the offset is kept within the new [maxScrollExtent]. A viewport that
  /// settles its offset itself as it lays out (a list view's, whose content is
  /// partly estimated) gives the [offset] it settled at, which the position
  /// takes without a [ScrollUpdateNotification], and which keeps to the end
  /// itself: one that does not, while it sticks to the end and showed it,
  /// goes to the new end instead (offset 0 in [reverse]). With [moved], the
  /// settling is the end of a move the scrollable was asked for (to an
  /// item): when it leaves the offset other than it was, that is a move,
  /// and sends a [ScrollUpdateNotification] up.
  void applyExtents(
    int viewport,
    int content, {
    int? offset,
    bool moved = false,
  }) {
    final before = _pixels;
    final max = content - viewport > 0 ? content - viewport : 0;
    final changed =
        !_hasExtents ||
        viewport != _viewportDimension ||
        max != _maxScrollExtent;
    final stick = offset == null && _stuck && _sticks;
    _hasExtents = true;
    _viewportDimension = viewport;
    _maxScrollExtent = max;
    final to = stick ? (_reverse ? 0 : max) : _clamp(offset ?? _pixels);
    _stuck = _reverse ? to <= 0 : to >= max;
    if (changed || to != _pixels) {
      _pixels = to;
      notifyListeners();
    }
    final state = _state;
    if (moved && _pixels != before && state != null && state.mounted) {
      ScrollUpdateNotification(
        metrics: metrics,
        context: state.context,
        scrollDelta: _pixels - before,
      ).dispatch(state.context);
    }
  }

  /// Moves by [delta] as a key or the wheel does: within the ends, telling
  /// what would go past one in an [OverscrollNotification]. Returns
  /// whether it moved.
  bool _scrollBy(int delta) {
    final from = _pixels;
    jumpTo(from + delta);
    final over = from + delta - _pixels;
    final state = _state;
    if (over != 0 && _hasExtents && state != null && state.mounted) {
      OverscrollNotification(
        metrics: metrics,
        context: state.context,
        overscroll: over,
      ).dispatch(state.context);
    }
    return _pixels != from;
  }

  /// Whether its scrollable's controller sticks to the end.
  bool get _sticks => _state?.widget.controller?.stickToEnd ?? false;

  int _clamp(int offset) {
    if (offset < 0) {
      return 0;
    }
    return _hasExtents && offset > _maxScrollExtent ? _maxScrollExtent : offset;
  }

  @override
  String toString() =>
      'ScrollPosition(${axis.name} $_pixels of $_maxScrollExtent)';
}

/// Reads and moves the position of the [Scrollable] it is given to:
/// [offset], [jumpTo], [ensureVisible]. The scrollable starts at
/// [initialScrollOffset]. Its listeners are told whenever the position's are
/// ([ScrollPosition]).
///
/// With [stickToEnd], a scrollable it is given to keeps showing the end of
/// its content as the content grows, while the window shows the end, as a
/// log or a chat does; scrolled away from the end, it stays where it is
/// until it is scrolled back to the end (End, the wheel, [jumpTo]). Such a
/// scrollable starts at the end, unless [initialScrollOffset] says otherwise.
///
/// Given to two scrollables at once, it moves both, and [ensureVisible]
/// the one the widget is in; [position] and [offset] then fail.
///
/// A view of a hundred rows, taken back to its top:
///
/// ```dart
/// final controller = ScrollController();
/// final view = SingleChildScrollView(
///   controller: controller,
///   child: Column(children: [for (var i = 0; i < 100; i++) Text('row $i')]),
/// );
/// // ... once it is shown and scrolled:
/// controller.jumpTo(0);
/// ```
///
/// See also:
///
///  * `ListController`, a list view's, which moves it to an item too.
///  * `LogController`, which holds a log view's lines and follows its end.
class ScrollController with ChangeNotifier {
  /// Reads and moves a scrollable that starts at [initialScrollOffset] (0, the
  /// default, its start), and with [stickToEnd] (false by default) keeps
  /// to its end; an [initialScrollOffset] below 0 asserts.
  ScrollController({this.initialScrollOffset = 0, this.stickToEnd = false})
    : assert(initialScrollOffset >= 0, 'an offset of 0 cells or more') {
    assert(
      DisposalTracker.created(this),
      'tracks the object',
    );
  }

  /// Where a scrollable it is given to starts.
  final int initialScrollOffset;

  /// Whether a scrollable it is given to keeps showing the end as its
  /// content grows, while it shows the end. The end is the one End scrolls
  /// to: that of a [Scrollable.reverse] one is offset 0, at its bottom,
  /// where a reverse list has item 0, a chat its newest message.
  final bool stickToEnd;

  final _positions = <ScrollPosition>[];

  /// Whether it is given to a mounted scrollable.
  bool get hasClients => _positions.isNotEmpty;

  /// The position of the one scrollable it is given to; a [StateError]
  /// with none or more.
  ScrollPosition get position => switch (_positions) {
    [final position] => position,
    [] => throw StateError('the controller is not given to a scrollable'),
    _ => throw StateError('the controller is given to several scrollables'),
  };

  /// The [position]'s offset.
  int get offset => position.pixels;

  /// Scrolls each of its scrollables to [offset] ([ScrollPosition.jumpTo]).
  void jumpTo(int offset) {
    for (final p in List.of(_positions)) {
      p.jumpTo(offset);
    }
  }

  /// Scrolls the least that shows the widget at [context] in the
  /// scrollable it is inside ([ScrollPosition.ensureVisible]); of several,
  /// in each it is inside. A [StateError] when the controller is given to
  /// none, an [ArgumentError] when the widget is inside none of them.
  void ensureVisible(BuildContext context) {
    final target = context.findRenderObject();
    if (target == null) {
      return;
    }
    if (_positions.isEmpty) {
      throw StateError('the controller is not given to a scrollable');
    }
    var shown = false;
    for (final p in List.of(_positions)) {
      if (p._holds(target)) {
        p.ensureVisible(target);
        shown = true;
      }
    }
    if (!shown) {
      throw ArgumentError.value(
        context,
        'context',
        'not inside a scrollable of the controller',
      );
    }
  }

  /// Takes [position], the scrollable's, which it reads and moves from now
  /// on; what a [Scrollable] does with its controller.
  void attach(ScrollPosition position) {
    _positions.add(position);
    position.addListener(notifyListeners);
  }

  /// Lets go of [position].
  void detach(ScrollPosition position) {
    position.removeListener(notifyListeners);
    _positions.remove(position);
  }

  @override
  void dispose() {
    for (final p in _positions) {
      p.removeListener(notifyListeners);
    }
    _positions.clear();
    super.dispose();
  }

  @override
  String toString() => switch (_positions) {
    [final position] => 'ScrollController(offset ${position.pixels})',
    _ => 'ScrollController(${_positions.length} clients)',
  };
}

/// Something a [Scrollable] did, sent up from it to the
/// [NotificationListener]s above it.
abstract class ScrollNotification extends Notification {
  /// What the scrollable at [context] did, which left it at [metrics].
  ScrollNotification({required this.metrics, required this.context});

  /// Where the scrollable is, after what it did.
  final ScrollMetrics metrics;

  /// The scrollable's.
  final BuildContext context;

  var _depth = 0;

  /// How many other scrollables it went past on its way up to the
  /// listener: 0 from the nearest scrollable below the listener.
  int get depth => _depth;

  @override
  bool visitAncestor(Element element) {
    if (element.widget is Scrollable) {
      _depth++;
    }
    return super.visitAncestor(element);
  }

  @override
  String toString() => '$runtimeType(depth $_depth, $metrics)';
}

/// A [Scrollable] moved [scrollDelta] cells: on to the end when positive.
final class ScrollUpdateNotification extends ScrollNotification {
  /// The scrollable at [context] moved [scrollDelta] cells, to [metrics].
  ScrollUpdateNotification({
    required super.metrics,
    required super.context,
    required this.scrollDelta,
  });

  /// The cells it moved: towards the end of the content when positive,
  /// towards its start when negative; never 0.
  final int scrollDelta;

  @override
  String toString() =>
      'ScrollUpdateNotification(depth $depth, delta $scrollDelta, $metrics)';
}

/// A key or the wheel would have moved a [Scrollable] [overscroll] cells
/// past an end: past the end when positive, before the start when negative.
final class OverscrollNotification extends ScrollNotification {
  /// A key or the wheel would have moved the scrollable at [context]
  /// [overscroll] cells past an end it is at, [metrics].
  OverscrollNotification({
    required super.metrics,
    required super.context,
    required this.overscroll,
  });

  /// The cells past the end when positive, before the start when
  /// negative; never 0.
  final int overscroll;

  @override
  String toString() =>
      'OverscrollNotification(depth $depth, overscroll $overscroll, '
      '$metrics)';
}

/// Whether a scrollable takes what the user does to it: the wheel and the
/// keys. [Scrollable.physics] and `ListView.physics` take one; none given
/// is [ScrollPhysics] itself, which takes all of it.
///
/// A view that does not take the wheel leaves it to the scrollable around
/// it, as Flutter's `NeverScrollableScrollPhysics` does:
///
/// ```dart
/// ListView(
///   physics: const NeverScrollableScrollPhysics(),
///   children: const [Text('one'), Text('two')],
/// )
/// ```
///
/// `Scrollable`, `SingleChildScrollView`, `ListView` and `TreeView` take
/// physics (a `TreeView` passes them to its `ListView`: with
/// `NeverScrollableScrollPhysics` the wheel goes to the list around, its
/// own keys and Tab stop stay). The views built on a `ListView` of their
/// own (`SelectionList`, `Table`, `LogView`, `FilePicker`) take none: they
/// are the focused widget of their screen and scroll with the wheel and the
/// keys, and a view that is to leave the wheel to the one around is a
/// `ListView` or a `SingleChildScrollView` with these physics.
@immutable
class ScrollPhysics {
  /// Physics that accept the user's scrolling.
  const ScrollPhysics();

  /// Whether the wheel and the keys of the user move a view that is at
  /// [metrics]. The position still moves by a [ScrollController], by
  /// [ScrollPosition.jumpTo] and by a scrollbar.
  bool shouldAcceptUserOffset(ScrollMetrics metrics) => true;
}

/// A view that the user cannot scroll with the wheel or the keys: the
/// wheel over it goes to the scrollable around it, if there is one.
final class NeverScrollableScrollPhysics extends ScrollPhysics {
  /// Physics that never accept the user's scrolling.
  const NeverScrollableScrollPhysics();

  @override
  bool shouldAcceptUserOffset(ScrollMetrics metrics) => false;
}

/// What a [Scrollable] shows its content in: a widget whose render object
/// shows the content from [position]'s offset on, along the scrollable's
/// axis, follows the position as it moves, and tells it the extents
/// ([ScrollPosition.applyExtents]).
typedef ViewportBuilder = Widget Function(
  BuildContext context,
  ScrollPosition position,
);

/// Scrolls the viewport [viewportBuilder] builds along [scrollDirection]:
/// the keys while it has the focus, the wheel over it, [controller] and
/// [ensureVisible]. Its [ScrollPosition] is its own, read and moved through
/// [controller], and found from below with [of].
///
/// Up and Down (Left and Right along a horizontal axis) scroll a cell,
/// PageUp and PageDown a window, Home and End to the ends; a key that
/// would not move it, at an end, goes on to the focus nodes above. In
/// [reverse], the content's start shown at the bottom (the right), the
/// keys and the wheel go the way they go on the screen: Up, PageUp and
/// the wheel up scroll on to the end of the content, Home to its end, End
/// to its start. The wheel over it
/// scrolls as the `ScrollBehavior` of the `ScrollConfiguration` above it
/// says, the events of a frame moving it once at the start of the frame:
/// along a horizontal axis the horizontal wheel's, or the vertical one's
/// for a mouse without one.
/// The wheel goes to one scrollable alone: the innermost under the mouse
/// along its axis, so that the wheel across over a list inside a view
/// across scrolls the view, and the wheel down over a view across inside
/// a list scrolls the list; the vertical wheel goes to a horizontal one
/// where no scrollable around it is vertical ([Listener.scrollAxis]).
/// While one is mounted the terminal reports the mouse (see [Listener]).
///
/// It is a stop of Tab ([Focus]) unless [canRequestFocus] is false or its
/// [physics] do not take the user's keys; its
/// keys reach it from a focused widget inside it too, which takes first
/// those it uses. While the focus is in it, the keys that would move it
/// are among those a `KeyHintsBar` shows ([FocusManagerKeys.activeKeys]),
/// unless [keyHints] is false: `scroll` for Up and Down (Left and Right
/// along a horizontal axis), `a window` for PageUp and PageDown, `the
/// ends` for Home and End; at the start the keys back are left out, at the
/// end those on, and all of them with nothing to scroll.
///
/// A `SingleChildScrollView` or a `ListView` is a scrollable with a
/// viewport built in, and what most apps use. A viewport of one's own
/// shows the content from the position's offset on and tells the position
/// its extents; here a `line` longer than the window, scrolled across:
///
/// ```dart
/// Scrollable(
///   scrollDirection: Axis.horizontal,
///   viewportBuilder: (context, position) => LayoutBuilder(
///     builder: (context, constraints) {
///       position.applyExtents(constraints.maxWidth, line.length);
///       return ListenableBuilder(
///         listenable: position,
///         builder: (context, child) =>
///             Text(line.substring(position.pixels), maxLines: 1),
///       );
///     },
///   ),
/// )
/// ```
///
/// See also:
///
///  * `SingleChildScrollView`, one child scrolled in a window.
///  * `ListView`, a list that builds only the items in view.
///  * `Scrollbar`, which shows where the scrollable below it is.
final class Scrollable extends StatefulWidget {
  /// Scrolls what [viewportBuilder] builds along [scrollDirection],
  /// vertically by default.
  const Scrollable({
    required this.viewportBuilder,
    this.scrollDirection = Axis.vertical,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.canRequestFocus,
    this.physics,
    this.keyHints = true,
    this.reverse = false,
    super.key,
  });

  /// Builds the viewport, on the scrollable's [ScrollPosition]; built
  /// again with the scrollable, not as the position moves.
  final ViewportBuilder viewportBuilder;

  /// The axis it scrolls along.
  final Axis scrollDirection;

  /// Whether its viewport shows the start of the content at the end of
  /// the axis, at the bottom (the right), the offset growing as the window
  /// goes up (left): the viewport's to show so ([ScrollPosition.reverse]);
  /// the keys, the wheel and a scrollbar go the way they go on the screen.
  final bool reverse;

  /// Reads and moves its position; none when null.
  final ScrollController? controller;

  /// Whether it takes the wheel and the keys; null takes both. Not taking
  /// the wheel, it goes to the scrollable around; not taking the keys, it
  /// is no stop of Tab ([canRequestFocus] is false) and has no key hints.
  final ScrollPhysics? physics;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// See [FocusNode.canRequestFocus].
  final bool? canRequestFocus;

  /// Whether the keys that would move it carry their hints, for a
  /// `KeyHintsBar`, true by default; false leaves them out, the keys
  /// moving it still.
  final bool keyHints;

  /// The position of the nearest scrollable above [context]; [context]
  /// depends on it. A [StateError] if there is none.
  static ScrollPosition of(BuildContext context) =>
      maybeOf(context) ??
      (throw StateError(
        'no Scrollable above ${context.widget.runtimeType}',
      ));

  /// The position [of] finds, if there is one.
  static ScrollPosition? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ScrollableScope>()?.position;

  /// Scrolls each scrollable above [context], the nearest first, the least
  /// that shows the widget at [context] ([ScrollPosition.ensureVisible]).
  static void ensureVisible(BuildContext context) {
    final target = context.findRenderObject();
    if (target == null) {
      return;
    }
    for (
      var scope = context.getInheritedWidgetOfExactType<_ScrollableScope>();
      scope != null;
      scope = scope.position._state?.context
          .getInheritedWidgetOfExactType<_ScrollableScope>()
    ) {
      scope.position.ensureVisible(target);
    }
  }

  @override
  State<Scrollable> createState() => _ScrollableState();
}

final class _ScrollableState extends State<Scrollable> {
  late final _position = ScrollPosition._(
    widget.scrollDirection,
    widget.controller?.initialScrollOffset ?? 0,
    this,
    widget.reverse,
  );

  @override
  void initState() {
    super.initState();
    widget.controller?.attach(_position);
  }

  @override
  void didUpdateWidget(Scrollable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // a scrollbar that takes any axis follows the axis, so it is told
    if (_position._axis != widget.scrollDirection) {
      _unclaim();
    }
    _position
      .._axis = widget.scrollDirection
      .._reverse = widget.reverse;
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller?.detach(_position);
      widget.controller?.attach(_position);
    }
  }

  @override
  void deactivate() {
    _dropWheelFrame();
    _input.cancel();
    _unclaim();
    super.deactivate();
  }

  @override
  void dispose() {
    _unclaim();
    widget.controller?.detach(_position);
    _position
      .._state = null
      ..dispose();
    _ownNode?.dispose();
    super.dispose();
  }

  FocusNode? _ownNode;

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  // the slot of the scrollbar above that shows this scrollable, if any
  ValueNotifier<ScrollPosition?>? _bar;

  /// Puts the position in [bar], the slot of a scrollbar above, letting go
  /// of the one it was in.
  void _claim(ValueNotifier<ScrollPosition?>? bar) {
    if (!identical(bar, _bar)) {
      _unclaim();
      _bar = bar;
    }
    bar?.value = _position;
  }

  void _unclaim() {
    final bar = _bar;
    if (bar != null && identical(bar.value, _position)) {
      bar.value = null;
    }
    _bar = null;
  }

  /// The viewport's render object: the child of the [Listener]'s.
  RenderObject? get _viewport => switch (context.findRenderObject()) {
    final RenderObjectWithChildMixin listener => listener.child,
    _ => null,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event.kind == KeyKind.release ||
        event.modifiers != 0 ||
        !node.hasFocus ||
        !_userScrolls) {
      return KeyEventResult.ignored;
    }
    final delta = _deltaOf(event.code);
    if (delta != null && delta != 0 && _position._scrollBy(delta)) {
      // the view moved by a key: what the wheel gathered is stale
      _input.cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// What [code], pressed alone, scrolls by now; null for a key that does
  /// not scroll.
  int? _deltaOf(KeyCode code) {
    final p = _position;
    final vertical = p.axis == Axis.vertical;
    final page = p.viewportDimension > 1 ? p.viewportDimension : 1;
    // the way up (left) on the screen
    final back = p._reverse ? 1 : -1;
    final toStart = -p.pixels;
    final toEnd = p.maxScrollExtent - p.pixels;
    return switch (code) {
      KeyCode.up when vertical => back,
      KeyCode.down when vertical => -back,
      KeyCode.left when !vertical => back,
      KeyCode.right when !vertical => -back,
      KeyCode.pageUp => back * page,
      KeyCode.pageDown => -back * page,
      KeyCode.home => p._reverse ? toEnd : toStart,
      KeyCode.end => p._reverse ? toStart : toEnd,
      _ => null,
    };
  }

  /// Whether the key of [_verticalHints] or [_horizontalHints] named [key]
  /// moves it now, as [_onKey] takes it.
  bool _takes(String key) {
    final delta = _deltaOf(_codes[key]!);
    final p = _position;
    return _userScrolls &&
        delta != null &&
        delta != 0 &&
        p._clamp(p._pixels + delta) != p._pixels;
  }

  static const Map<String, KeyCode> _codes = {
    'up': KeyCode.up,
    'down': KeyCode.down,
    'left': KeyCode.left,
    'right': KeyCode.right,
    'pageup': KeyCode.pageUp,
    'pagedown': KeyCode.pageDown,
    'home': KeyCode.home,
    'end': KeyCode.end,
  };

  static const _verticalHints = {
    'up': 'scroll',
    'down': 'scroll',
    'pageup': 'a window',
    'pagedown': 'a window',
    'home': 'the ends',
    'end': 'the ends',
  };

  static const _horizontalHints = {
    'left': 'scroll',
    'right': 'scroll',
    'pageup': 'a window',
    'pagedown': 'a window',
    'home': 'the ends',
    'end': 'the ends',
  };

  bool get _userScrolls =>
      widget.physics?.shouldAcceptUserOffset(_position.metrics) ?? true;

  void _onWheel(PointerEvent event) {
    final way = _position.axis == Axis.vertical || event.scrollX == 0
        ? event.scrollY
        : event.scrollX;
    if (way == 0) {
      return;
    }
    final binding = AppBinding.maybeOf(context);
    final input = _input;
    if (binding == null) {
      input.event(Duration.zero, _position.axis, way);
      _applyWheel(Duration.zero);
      return;
    }
    input.event(
      Duration(microseconds: binding.twkApp.clock.elapsedMicroseconds),
      _position.axis,
      way,
    );
    // the events of a frame move it once, at the start of the frame
    if (_wheelFrame == null && input.hasPending) {
      _wheelFrame = binding.scheduleFrameCallback(_applyWheel);
    }
  }

  // what gathers the wheel's events of this scrollable, applied at a frame
  late final _input = ScrollInput(const ScrollBehavior());
  int? _wheelFrame;

  void _applyWheel(Duration _) {
    _wheelFrame = null;
    final delta = _input.take();
    if (delta == null || !mounted) {
      return;
    }
    final cells = _position.axis == Axis.vertical ? delta.rows : delta.columns;
    if (cells != 0) {
      _position._scrollBy(_position._reverse ? -cells : cells);
    }
  }

  void _dropWheelFrame() {
    final id = _wheelFrame;
    if (id != null) {
      _wheelFrame = null;
      AppBinding.maybeOf(context)?.cancelFrameCallback(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bars = context.dependOnInheritedWidgetOfExactType<ScrollbarScope>();
    final bar = bars?.claimFor(_position.axis);
    _claim(bar);
    _input.behavior = ScrollConfiguration.of(context);
    final viewport = Listener(
      onScroll: _userScrolls ? _onWheel : null,
      scrollAxis: _position.axis,
      child: widget.viewportBuilder(context, _position),
    );
    final node = _node;
    return _ScrollableScope(
      position: _position,
      child: HintedKeys(
        node: node,
        hints: !widget.keyHints
            ? const {}
            : _position.axis == Axis.vertical
            ? _verticalHints
            : _horizontalHints,
        takes: _takes,
        changes: _position,
        child: Focus(
          focusNode: node,
          autofocus: widget.autofocus,
          canRequestFocus: _userScrolls ? widget.canRequestFocus : false,
          onKeyEvent: _onKey,
          child: bar == null
              ? viewport
              : bars!._without(_position.axis, viewport),
        ),
      ),
    );
  }
}

/// What [Scrollable.of] finds.
final class _ScrollableScope extends InheritedWidget {
  const _ScrollableScope({required this.position, required super.child});

  final ScrollPosition position;

  @override
  bool updateShouldNotify(_ScrollableScope oldWidget) =>
      !identical(position, oldWidget.position);
}

// What a Scrollbar needs of the Scrollables below it; hidden from the
// library's exports.

/// Where the outermost [Scrollable] below it puts its position, for a
/// scrollbar above: [vertical]'s value or [horizontal]'s is the position of
/// the one along that axis while it is in the tree, [either]'s the one of
/// any axis. What a scrollbar puts above its child; a scrollable it takes
/// puts one without [either] and the slot of its axis above its viewport,
/// so that those inside it are not taken. Of two side by side, the last one
/// built is taken.
final class ScrollbarScope extends InheritedWidget {
  /// The slots [vertical], [horizontal] and [either] above [child]; a null
  /// one takes no scrollable. A scrollable takes the slot of its axis, or
  /// [either] where there is none; [eitherFirst] makes it [either] first,
  /// as the nearest scrollbar takes any axis.
  const ScrollbarScope({
    required super.child,
    this.vertical,
    this.horizontal,
    this.either,
    this.eitherFirst = false,
  });

  /// [child] with the scrollbar of [slot] above it, along [axis], or along
  /// the axis of the outermost scrollable in it where [axis] is null, and
  /// the slots [outer] has but for the one it replaces.
  factory ScrollbarScope.over(
    ScrollbarScope? outer,
    Axis? axis,
    ValueNotifier<ScrollPosition?> slot,
    Widget child,
  ) => ScrollbarScope(
    vertical: axis == Axis.vertical ? slot : outer?.vertical,
    horizontal: axis == Axis.horizontal ? slot : outer?.horizontal,
    either: axis == null ? slot : outer?.either,
    eitherFirst: axis == null,
    child: child,
  );

  /// The slot of the vertical scrollable.
  final ValueNotifier<ScrollPosition?>? vertical;

  /// The slot of the horizontal scrollable.
  final ValueNotifier<ScrollPosition?>? horizontal;

  /// The slot of the scrollable of either axis.
  final ValueNotifier<ScrollPosition?>? either;

  /// Whether [either] is taken before the slot of the scrollable's axis.
  final bool eitherFirst;

  /// The slot along [axis].
  ValueNotifier<ScrollPosition?>? slotOf(Axis axis) =>
      axis == Axis.vertical ? vertical : horizontal;

  /// The slot a scrollable along [axis] puts its position in.
  ValueNotifier<ScrollPosition?>? claimFor(Axis axis) =>
      eitherFirst ? either ?? slotOf(axis) : slotOf(axis) ?? either;

  /// This scope around [child] without the slot along [axis] and [either].
  ScrollbarScope _without(Axis axis, Widget child) => ScrollbarScope(
    vertical: axis == Axis.vertical ? null : vertical,
    horizontal: axis == Axis.vertical ? horizontal : null,
    child: child,
  );

  @override
  bool updateShouldNotify(ScrollbarScope oldWidget) =>
      !identical(vertical, oldWidget.vertical) ||
      !identical(horizontal, oldWidget.horizontal) ||
      !identical(either, oldWidget.either) ||
      eitherFirst != oldWidget.eitherFirst;
}

/// Scrolls the scrollable [position] is of as the wheel's [event] over it
/// does, acceleration and all: the wheel over its scrollbar.
void scrollByWheel(ScrollPosition position, PointerEvent event) {
  final state = position._state;
  if (state != null && state.mounted) {
    state._onWheel(event);
  }
}
