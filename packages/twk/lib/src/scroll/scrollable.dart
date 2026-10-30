/// Scrolling in cells: the [ScrollPosition] of a [Scrollable], the
/// [ScrollController] that reads and moves it, and the
/// [ScrollNotification]s it sends up the tree as it moves.
library;

import 'dart:math' as math;

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

// Examples can assume:
// late String line;

/// Where a scrollable view is along its [axis]: [offset] cells of its
/// content scrolled off its start, out of [maxOffset], with
/// [viewportExtent] cells of it in its window.
///
/// What a [ScrollNotification] carries, and [ScrollPosition.metrics]
/// returns. Two are equal when all four are.
@immutable
final class ScrollMetrics {
  /// Where a view is: [offset] of [maxOffset], [viewportExtent] cells in
  /// the window, along [axis], vertical by default.
  const ScrollMetrics({
    required this.offset,
    required this.maxOffset,
    required this.viewportExtent,
    this.axis = Axis.vertical,
  });

  /// The cells of the content before the window.
  final int offset;

  /// The largest [offset]: the content's extent less the window's, 0 when
  /// all of it fits.
  final int maxOffset;

  /// The cells of the content the window shows.
  final int viewportExtent;

  /// The axis the view scrolls along.
  final Axis axis;

  /// The cells of the content after the window; 0 at the end, and when
  /// [offset] is past [maxOffset].
  int get extentAfter => maxOffset - offset < 0 ? 0 : maxOffset - offset;

  /// Whether the window shows the content's start.
  bool get atStart => offset <= 0;

  /// Whether the window shows the content's end.
  bool get atEnd => offset >= maxOffset;

  @override
  bool operator ==(Object other) =>
      other is ScrollMetrics &&
      other.offset == offset &&
      other.maxOffset == maxOffset &&
      other.viewportExtent == viewportExtent &&
      other.axis == axis;

  @override
  int get hashCode => Object.hash(offset, maxOffset, viewportExtent, axis);

  @override
  String toString() =>
      'ScrollMetrics(${axis.name} $offset of $maxOffset, '
      'window $viewportExtent)';
}

/// Where a [Scrollable] is scrolled to, in cells along its [axis]: the
/// [offset], kept from 0 to [maxOffset] once its viewport has told it its
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
/// [offset] following [maxOffset]; moved away from the end, it stays where
/// it is until it is moved back. In [reverse], the end it keeps is the one
/// End goes to: offset 0, at the bottom (the right).
final class ScrollPosition with ChangeNotifier {
  ScrollPosition._(this._axis, this._offset, this._state, this._reverse)
    : _stuck = _offset == 0;

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

  int _offset;

  /// The cells of the content scrolled off the start.
  int get offset => _offset;

  var _maxOffset = 0;
  var _viewportExtent = 0;
  var _hasExtents = false;

  // the scrollable it is the position of, while mounted
  _ScrollableState? _state;

  /// The largest [offset]: the content's extent less the window's; 0 until
  /// the viewport is laid out.
  int get maxOffset => _maxOffset;

  /// The cells of the content the window shows; 0 until the viewport is
  /// laid out.
  int get viewportExtent => _viewportExtent;

  /// Whether the viewport has told it its extents.
  bool get hasExtents => _hasExtents;

  /// Its offset and extents, as a notification carries them.
  ScrollMetrics get metrics => ScrollMetrics(
    offset: _offset,
    maxOffset: _maxOffset,
    viewportExtent: _viewportExtent,
    axis: _axis,
  );

  /// Scrolls to [offset], kept within 0 and [maxOffset]; a move sends a
  /// [ScrollUpdateNotification] up from the scrollable.
  void jumpTo(int offset) {
    final to = _clamp(offset);
    final delta = to - _offset;
    if (delta == 0) {
      return;
    }
    _offset = to;
    _stuck = _reverse ? to <= 0 : _hasExtents && to >= _maxOffset;
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
    final shown = _reverse ? _maxOffset - _offset : _offset;
    final start = at + shown;
    final end = start + (vertical ? target.height : target.width);
    final top = end - _viewportExtent;
    int? to;
    if (_reverse) {
      if (end > shown + _viewportExtent) {
        to = top;
      } else if (start < shown) {
        to = top > start ? top : start;
      }
    } else if (start < shown) {
      to = start;
    } else if (end > shown + _viewportExtent) {
      to = top < start ? top : start;
    }
    if (to != null) {
      jumpTo(_reverse ? _maxOffset - to : to);
    }
  }

  /// Takes the extents of the viewport, laid out: [viewport] cells of the
  /// content's [content] in the window. What the viewport's layout calls;
  /// the offset is kept within the new [maxOffset]. A viewport that settles
  /// its offset itself as it lays out (a list view's, whose content is
  /// partly estimated) gives the [offset] it settled at, which the position
  /// takes without a [ScrollUpdateNotification], and which keeps to the end
  /// itself: one that does not, while it sticks to the end and showed it,
  /// goes to the new end instead (offset 0 in [reverse]).
  void applyExtents(int viewport, int content, {int? offset}) {
    final max = content - viewport > 0 ? content - viewport : 0;
    final changed =
        !_hasExtents || viewport != _viewportExtent || max != _maxOffset;
    final stick = offset == null && _stuck && _sticks;
    _hasExtents = true;
    _viewportExtent = viewport;
    _maxOffset = max;
    final to = stick ? (_reverse ? 0 : max) : _clamp(offset ?? _offset);
    _stuck = _reverse ? to <= 0 : to >= max;
    if (changed || to != _offset) {
      _offset = to;
      notifyListeners();
    }
  }

  /// Moves by [delta] as a key or the wheel does: within the ends, telling
  /// what would go past one in an [OverscrollNotification]. Returns
  /// whether it moved.
  bool _scrollBy(int delta) {
    final from = _offset;
    jumpTo(from + delta);
    final over = from + delta - _offset;
    final state = _state;
    if (over != 0 && _hasExtents && state != null && state.mounted) {
      OverscrollNotification(
        metrics: metrics,
        context: state.context,
        overscroll: over,
      ).dispatch(state.context);
    }
    return _offset != from;
  }

  /// Whether its scrollable's controller sticks to the end.
  bool get _sticks => _state?.widget.controller?.stickToEnd ?? false;

  int _clamp(int offset) {
    if (offset < 0) {
      return 0;
    }
    return _hasExtents && offset > _maxOffset ? _maxOffset : offset;
  }

  @override
  String toString() => 'ScrollPosition(${axis.name} $_offset of $_maxOffset)';
}

/// Reads and moves the position of the [Scrollable] it is given to:
/// [offset], [jumpTo], [ensureVisible]. The scrollable starts at
/// [initialOffset]. Its listeners are told whenever the position's are
/// ([ScrollPosition]).
///
/// With [stickToEnd], a scrollable it is given to keeps showing the end of
/// its content as the content grows, while the window shows the end, as a
/// log or a chat does; scrolled away from the end, it stays where it is
/// until it is scrolled back to the end (End, the wheel, [jumpTo]). Such a
/// scrollable starts at the end, unless [initialOffset] says otherwise.
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
  /// Reads and moves a scrollable that starts at [initialOffset] (0, the
  /// default, its start), and with [stickToEnd] (false by default) keeps
  /// to its end; an [initialOffset] below 0 asserts.
  ScrollController({this.initialOffset = 0, this.stickToEnd = false})
    : assert(initialOffset >= 0, 'an offset of 0 cells or more');

  /// Where a scrollable it is given to starts.
  final int initialOffset;

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
  int get offset => position.offset;

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
    [final position] => 'ScrollController(offset ${position.offset})',
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

/// How far a notch of the wheel scrolls a [Scrollable] as the notches come
/// faster: [Scrollable.wheelStep] cells times a factor, what it scrolls
/// past a whole cell carried on to the next notch. A notch on its own has
/// a factor of 1, as has the first of a streak; one that comes the same
/// way within [streak] of the one before it on the app's clock goes on the
/// streak, with a factor of `1 + 0.8 (e^(r / 3) - 1)` up to [max], r being
/// 100 ms over the average time between the last four notches of the
/// streak: the faster they come, the further each goes, as on macOS. A
/// notch less than 6 ms after the one before, as a terminal may send for
/// one turn, goes as far as that one.
///
/// [none], what a scrollable takes by default, keeps every factor at 1.
@immutable
final class WheelAcceleration {
  /// Notches less than [streak] apart (150 ms by default) go on a streak,
  /// their factor up to [max] (6 by default); a [max] below 1 asserts.
  const WheelAcceleration({
    this.streak = const Duration(milliseconds: 150),
    this.max = 6,
  }) : assert(max >= 1, 'a factor of 1 or more');

  /// Every notch scrolls [Scrollable.wheelStep] cells.
  static const none = WheelAcceleration(max: 1);

  /// The longest time between two notches of a streak.
  final Duration streak;

  /// The largest factor.
  final double max;

  /// The factor of a notch of a streak whose notches came [gap] apart on
  /// average.
  double factor(Duration gap) {
    final us = gap.inMicroseconds;
    final f = us <= 0 ? max : 1 + 0.8 * (math.exp(100000 / us / 3) - 1);
    return f < max ? f : max;
  }

  @override
  bool operator ==(Object other) =>
      other is WheelAcceleration && other.streak == streak && other.max == max;

  @override
  int get hashCode => Object.hash(streak, max);

  @override
  String toString() =>
      'WheelAcceleration(streak ${streak.inMilliseconds} ms, max $max)';
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
/// to its start. A notch
/// of the wheel over it scrolls [wheelStep] cells, further as the notches
/// come faster when [wheelAcceleration] says so: along a horizontal axis
/// the horizontal wheel's, or the vertical one's for a mouse without one.
/// The wheel goes to one scrollable alone: the innermost under the mouse
/// along its axis, so that the wheel across over a list inside a view
/// across scrolls the view, and the wheel down over a view across inside
/// a list scrolls the list; the vertical wheel goes to a horizontal one
/// where no scrollable around it is vertical ([Listener.scrollAxis]).
/// While one is mounted the terminal reports the mouse (see [Listener]).
///
/// It is a stop of Tab ([Focus]) unless [canRequestFocus] is false; its
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
///       position.applyExtents(constraints.maxW, line.length);
///       return ListenableBuilder(
///         listenable: position,
///         builder: (context, child) =>
///             Text(line.substring(position.offset), maxLines: 1),
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
    this.wheelAcceleration = WheelAcceleration.none,
    this.keyHints = true,
    this.reverse = false,
    super.key,
  });

  /// What a notch of the wheel scrolls, in cells.
  static const wheelStep = 3;

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

  /// How much further the notches of the wheel scroll as they come faster.
  final WheelAcceleration wheelAcceleration;

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
    widget.controller?.initialOffset ?? 0,
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
        !node.hasFocus) {
      return KeyEventResult.ignored;
    }
    final delta = _deltaOf(event.code);
    return delta != null && delta != 0 && _position._scrollBy(delta)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  /// What [code], pressed alone, scrolls by now; null for a key that does
  /// not scroll.
  int? _deltaOf(KeyCode code) {
    final p = _position;
    final vertical = p.axis == Axis.vertical;
    final page = p.viewportExtent > 1 ? p.viewportExtent : 1;
    // the way up (left) on the screen
    final back = p._reverse ? 1 : -1;
    final toStart = -p.offset;
    final toEnd = p.maxOffset - p.offset;
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
    return delta != null &&
        delta != 0 &&
        p._clamp(p._offset + delta) != p._offset;
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

  void _onWheel(PointerEvent event) {
    final way = _position.axis == Axis.vertical || event.scrollX == 0
        ? event.scrollY
        : event.scrollX;
    if (way != 0) {
      final cells = way * _notchCells(way);
      _position._scrollBy(_position._reverse ? -cells : cells);
    }
  }

  // the streak of the wheel: the time of its last notch but those of a
  // burst, in microseconds on the app's clock, which way it went, the
  // times between its last notches, its factor and the part of a cell it
  // scrolled past whole cells
  int? _notchAt;
  var _notchWay = 0;
  final _gaps = <int>[];
  var _factor = 1.0;
  var _carry = 0.0;

  /// What a notch of the wheel [way] (-1 or 1) scrolls now, in cells.
  int _notchCells(int way) {
    final acceleration = widget.wheelAcceleration;
    if (acceleration.max <= 1) {
      return Scrollable.wheelStep;
    }
    final now = AppBinding.maybeOf(context)?.twkApp.clock.elapsedMicroseconds;
    final last = _notchAt;
    if (now == null ||
        last == null ||
        way != _notchWay ||
        now - last > acceleration.streak.inMicroseconds) {
      _notchAt = now;
      _notchWay = way;
      _gaps.clear();
      _factor = 1;
      _carry = 0;
    } else if (now - last >= _burst) {
      _notchAt = now;
      if (_gaps.length == _averaged) {
        _gaps.removeAt(0);
      }
      _gaps.add(now - last);
      final sum = _gaps.reduce((a, b) => a + b);
      _factor = acceleration.factor(
        Duration(microseconds: sum ~/ _gaps.length),
      );
    }
    final cells = Scrollable.wheelStep * _factor + _carry;
    final whole = cells.floor();
    _carry = cells - whole;
    return whole;
  }

  // a notch this soon after the one before, in microseconds, is of the
  // same burst
  static const _burst = 6000;

  // the times between notches the factor of a streak averages
  static const _averaged = 3;

  @override
  Widget build(BuildContext context) {
    final bars = context.dependOnInheritedWidgetOfExactType<ScrollbarScope>();
    final bar = bars?.slotOf(_position.axis);
    _claim(bar);
    final viewport = Listener(
      onScroll: _onWheel,
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
          canRequestFocus: widget.canRequestFocus,
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

/// Where the outermost [Scrollable] below it along each axis puts its
/// position, for a scrollbar above: [vertical]'s value or [horizontal]'s
/// is the position of the one along that axis while it is in the tree.
/// What a scrollbar puts above its child; a scrollable it takes puts one
/// without the slot of its axis above its viewport, so that those inside
/// it are not taken. Of two side by side, the last one built is taken.
final class ScrollbarScope extends InheritedWidget {
  /// The slots [vertical] and [horizontal] above [child]; a null one takes
  /// no scrollable along its axis.
  const ScrollbarScope({required super.child, this.vertical, this.horizontal});

  /// The slot of the vertical scrollable.
  final ValueNotifier<ScrollPosition?>? vertical;

  /// The slot of the horizontal scrollable.
  final ValueNotifier<ScrollPosition?>? horizontal;

  /// The slot along [axis].
  ValueNotifier<ScrollPosition?>? slotOf(Axis axis) =>
      axis == Axis.vertical ? vertical : horizontal;

  /// This scope around [child] without the slot along [axis].
  ScrollbarScope _without(Axis axis, Widget child) => ScrollbarScope(
    vertical: axis == Axis.vertical ? null : vertical,
    horizontal: axis == Axis.vertical ? horizontal : null,
    child: child,
  );

  @override
  bool updateShouldNotify(ScrollbarScope oldWidget) =>
      !identical(vertical, oldWidget.vertical) ||
      !identical(horizontal, oldWidget.horizontal);
}

/// Scrolls the scrollable [position] is of as the wheel's [event] over it
/// does, acceleration and all: the wheel over its scrollbar.
void scrollByWheel(ScrollPosition position, PointerEvent event) {
  final state = position._state;
  if (state != null && state.mounted) {
    state._onWheel(event);
  }
}
