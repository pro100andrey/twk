/// The mouse by hit test: a [Listener] gets the presses, releases, motion
/// and wheel over its child, a [MouseRegion] is told when the mouse comes
/// in, moves inside and goes out, and sets the pointer's shape over it;
/// the [MouseTracker] of an app routes the terminal's reports to them and
/// counts what they need reported.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        Axis,
        BoxConstraints,
        DiagnosticPropertiesBuilder,
        HitTestBehavior,
        HitTestResult,
        Mod,
        MouseEvent,
        MouseKind,
        MouseTracking,
        PaintContext,
        PointerShape,
        RenderObject,
        RenderObjectWithChildMixin;

import '../binding/terminal_status.dart';
import '../framework/framework.dart';
import '../layout/one_child.dart';
import 'ignore_pointer.dart' show RenderAbsorbPointer;

export 'package:twk_core/twk_core.dart' show PointerShape;

/// A mouse event as a [Listener] or a [MouseRegion] gets it: what the
/// terminal reported ([MouseEvent]), the cell in the coordinates of the
/// widget too.
///
/// Two events are equal when all they say is. A callback that tells a
/// click of the left button with Ctrl held:
///
/// ```dart
/// void onDown(PointerEvent event) {
///   if (event.button == 0 && event.ctrl) {
///     print('ctrl+click at ${event.x},${event.y}');
///   }
/// }
/// ```
@immutable
final class PointerEvent {
  /// An event of [kind] at the cell [x], [y] of the widget, [screenX],
  /// [screenY] of the screen.
  const PointerEvent(
    this.kind,
    this.x,
    this.y, {
    required this.screenX,
    required this.screenY,
    this.button = 0,
    this.modifiers = 0,
  });

  /// What the mouse did; for an enter or an exit, what moved it in or out
  /// (a frame that moved the region: a move, or a drag while a button is
  /// held).
  final MouseKind kind;

  /// The column of the cell from the left of the widget: outside it for
  /// an exit, and for a drag or a release that follows a press inside it.
  final int x;

  /// The row of the cell from the top of the widget, as [x].
  final int y;

  /// The column of the cell from the left of the screen.
  final int screenX;

  /// The row of the cell from the top of the screen.
  final int screenY;

  /// The button pressed, released or held: 0 left, 1 middle, 2 right, 8 to
  /// 11 the side buttons.
  final int button;

  /// [Mod]'s Shift, Alt and Ctrl, held.
  final int modifiers;

  /// Whether Shift is held.
  bool get shift => modifiers & Mod.shift != 0;

  /// Whether Alt is held.
  bool get alt => modifiers & Mod.alt != 0;

  /// Whether Ctrl is held.
  bool get ctrl => modifiers & Mod.ctrl != 0;

  /// The rows the wheel scrolls: -1 up, 1 down; 0 for any other event.
  int get scrollY => switch (kind) {
    MouseKind.wheelUp => -1,
    MouseKind.wheelDown => 1,
    _ => 0,
  };

  /// The columns the wheel scrolls: -1 left, 1 right; 0 for any other
  /// event.
  int get scrollX => switch (kind) {
    MouseKind.wheelLeft => -1,
    MouseKind.wheelRight => 1,
    _ => 0,
  };

  @override
  bool operator ==(Object other) =>
      other is PointerEvent &&
      other.kind == kind &&
      other.x == x &&
      other.y == y &&
      other.screenX == screenX &&
      other.screenY == screenY &&
      other.button == button &&
      other.modifiers == modifiers;

  @override
  int get hashCode =>
      Object.hash(kind, x, y, screenX, screenY, button, modifiers);

  @override
  String toString() =>
      'Pointer(${kind.name} $x,$y at $screenX,$screenY b$button '
      'm$modifiers)';
}

/// What a [Listener] or a [MouseRegion] calls with an event.
typedef PointerEventListener = void Function(PointerEvent event);

/// Gives the mouse events over [child] to its callbacks, each with the cell
/// in the coordinates of this widget.
///
/// The callbacks are a press ([onDown]), a release ([onUp]), motion with
/// no button held ([onMove]) and with one ([onDrag]), the wheel
/// ([onScroll]). Where it is hit is up to [behavior]: by default where its
/// child is (a see-through cell of a `Box` without a background is not),
/// anywhere in its bounds when [HitTestBehavior.opaque].
///
/// A press, release, move or drag goes to each Listener hit there with a
/// callback for it, the deepest first. Once a button is pressed, drags and
/// releases go to the Listeners the press was hit in, wherever the mouse
/// goes, until the last button is released: a drag that leaves the widget
/// goes on to it. The wheel goes to one Listener alone: the deepest hit
/// there with an [onScroll] that takes the wheel's axis ([scrollAxis]),
/// else the deepest with an [onScroll] at all. Of two scrolling views one
/// inside the other along the same axis only the inner one scrolls; of a
/// view across inside a view down, the wheel down scrolls the outer one
/// and the wheel across the inner one, and the wheel down the inner one
/// where nothing above it scrolls down (a mouse without a wheel across).
/// An event that no Listener takes (has a callback for) goes to the app's
/// `InputListener`s.
///
/// While one with a callback is mounted, the terminal reports the mouse
/// as its callbacks need: all motion for [onMove] (mode 1003: a report for
/// each cell the mouse crosses), motion while a button is held for
/// [onDrag] (1002), presses, releases and the wheel for the others (1000).
/// While none is mounted, nor a [MouseRegion], the mouse is the
/// terminal's: its selection and its wheel work as without the app. In the
/// inline mode the mouse stays the terminal's. Outside an app a Listener
/// gets nothing.
///
/// A panel that counts the wheel's notches over it:
///
/// ```dart
/// var notches = 0;
/// final panel = Listener(
///   behavior: HitTestBehavior.opaque,
///   scrollAxis: Axis.vertical,
///   onScroll: (event) => notches += event.scrollY,
///   child: const SizedBox(width: 20, height: 5),
/// );
/// ```
///
/// See also:
///
///  * `GestureDetector`, taps and drags rather than the events.
///  * [MouseRegion], the mouse coming in and going out.
final class Listener extends SingleChildRenderObjectWidget {
  /// Gives the events over [child] to the callbacks given.
  const Listener({
    super.key,
    this.onDown,
    this.onUp,
    this.onMove,
    this.onDrag,
    this.onScroll,
    this.scrollAxis,
    this.behavior = HitTestBehavior.deferToChild,
    super.child,
  });

  /// A button pressed over it.
  final PointerEventListener? onDown;

  /// A button released over it, or after a press over it.
  final PointerEventListener? onUp;

  /// The mouse moved over it with no button held.
  final PointerEventListener? onMove;

  /// The mouse moved with a button held, over it or after a press over it.
  final PointerEventListener? onDrag;

  /// The wheel turned over it ([PointerEvent.scrollY],
  /// [PointerEvent.scrollX]), and over no Listener inside it that takes
  /// it ([scrollAxis]).
  final PointerEventListener? onScroll;

  /// The axis of the wheel [onScroll] is for: the wheel along the other
  /// axis goes on to the nearest Listener above that takes it, and comes
  /// back to this one where none does. Null for both: every wheel stops
  /// here.
  ///
  /// So does Flutter's `Scrollable`, which bids for a pointer's scroll
  /// signal only where the signal's delta along its own axis is not zero:
  /// the signal's resolver gives it to the first bidder, the deepest.
  final Axis? scrollAxis;

  /// Where it is hit.
  final HitTestBehavior behavior;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderListener createRenderObject(BuildContext context) {
    final listener = RenderListener(
      onDown: onDown,
      onUp: onUp,
      onMove: onMove,
      onDrag: onDrag,
      onScroll: onScroll,
      scrollAxis: scrollAxis,
      behavior: behavior,
    );
    MouseTracker.of(context)?._add(listener);
    return listener;
  }

  @override
  void updateRenderObject(BuildContext context, RenderListener renderObject) {
    renderObject
      ..onDown = onDown
      ..onUp = onUp
      ..onMove = onMove
      ..onDrag = onDrag
      ..onScroll = onScroll
      ..scrollAxis = scrollAxis
      ..behavior = behavior
      .._recount();
  }

  @override
  void didUnmountRenderObject(RenderListener renderObject) =>
      renderObject._tracker?._remove(renderObject);
}

/// Tells when the mouse comes in over [child] ([onEnter]), moves over it
/// with no button held ([onHover]) and goes out ([onExit]), and sets the
/// pointer's shape over it ([cursor]).
///
/// Each callback gets the cell in the coordinates of this widget. The
/// mouse is in where it is
/// hit, which [behavior] says: by default anywhere in its bounds, so that
/// what it covers is not hit there (a region under it in a `Stack` is
/// left); with [HitTestBehavior.translucent] what it covers is hit too.
/// A region inside another is in it: the mouse coming from the outer one
/// into the inner one enters the inner one alone.
///
/// The regions the mouse is in are kept between events: the mouse
/// reported elsewhere, the regions it left are told first, the deepest
/// first, then those it came into, the outermost first, then the hover. A
/// frame that moves a region under the mouse or away from it tells it as
/// well, as after a scroll under a mouse that stays put. A region that
/// leaves the tree is not told.
///
/// While the mouse is in it, the pointer has the shape of its [cursor]
/// (OSC 22), or that of the nearest region around it with one: the
/// terminal's own outside them all. The shape is written as it changes,
/// with the mouse or with a frame that moved a region, and only where the
/// terminal is known to show it (`TerminalInfo.pointerShapes`); the
/// terminal's own is put back when the app ends ([TerminalStatus]).
///
/// While one with a callback is mounted, or with a [cursor] the terminal
/// shows, the terminal reports all motion of the mouse (mode 1003; see
/// [Listener]). Outside an app a MouseRegion is told nothing.
///
/// A row lit while the mouse is over it, the pointer a hand there:
///
/// ```dart
/// final hovered = ValueNotifier(false);
/// final row = MouseRegion(
///   cursor: PointerShape.pointer,
///   onEnter: (_) => hovered.value = true,
///   onExit: (_) => hovered.value = false,
///   child: ValueListenableBuilder(
///     valueListenable: hovered,
///     builder: (context, lit, _) => Text(
///       'Open',
///       style: Style(attrs: lit ? Attr.bold : 0),
///     ),
///   ),
/// );
/// ```
final class MouseRegion extends SingleChildRenderObjectWidget {
  /// Tells the callbacks given of the mouse over [child].
  const MouseRegion({
    super.key,
    this.onEnter,
    this.onExit,
    this.onHover,
    this.cursor,
    this.behavior = HitTestBehavior.opaque,
    super.child,
  });

  /// The mouse came in.
  final PointerEventListener? onEnter;

  /// The mouse went out.
  final PointerEventListener? onExit;

  /// The mouse moved inside with no button held.
  final PointerEventListener? onHover;

  /// The pointer's shape while the mouse is in it; null for that of the
  /// region around it.
  final PointerShape? cursor;

  /// Where the mouse is in it.
  final HitTestBehavior behavior;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderMouseRegion createRenderObject(BuildContext context) {
    final status = TerminalStatus.of(context);
    final region = RenderMouseRegion(
      onEnter: onEnter,
      onExit: onExit,
      onHover: onHover,
      cursor: cursor,
      behavior: behavior,
    ).._shapesShown = status?.showsPointerShape ?? false;
    final tracker = MouseTracker.of(context);
    if (tracker != null) {
      tracker
        .._status ??= status
        .._add(region);
    }
    return region;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMouseRegion renderObject,
  ) {
    renderObject
      ..onEnter = onEnter
      ..onExit = onExit
      ..onHover = onHover
      ..cursor = cursor
      ..behavior = behavior
      .._recount();
  }

  @override
  void didUnmountRenderObject(RenderMouseRegion renderObject) =>
      renderObject._tracker?._remove(renderObject);
}

/// What a [Listener] or a [MouseRegion] puts in the render tree: its
/// child, as big as the child is, hit as [behavior] says; counted by the
/// app's [MouseTracker] while mounted.
abstract base class _RenderMouseTarget extends RenderObject
    with RenderObjectWithChildMixin {
  _RenderMouseTarget(this.behavior);

  /// Where it is hit.
  HitTestBehavior behavior;

  @override
  HitTestBehavior get hitTestBehavior => behavior;

  // the tracker that counts it, and as what
  MouseTracker? _tracker;
  MouseTracking _counted = MouseTracking.off;

  /// What its callbacks need the terminal to report.
  MouseTracking get _needs;

  /// Counts it again after its callbacks changed.
  void _recount() => _tracker?._recount(this);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add('behavior', behavior.name);
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

/// What a [Listener] puts in the render tree.
final class RenderListener extends _RenderMouseTarget {
  /// The render object of a [Listener] of the callbacks given.
  RenderListener({
    this.onDown,
    this.onUp,
    this.onMove,
    this.onDrag,
    this.onScroll,
    this.scrollAxis,
    HitTestBehavior behavior = HitTestBehavior.deferToChild,
  }) : super(behavior);

  /// See [Listener.onDown].
  PointerEventListener? onDown;

  /// See [Listener.onUp].
  PointerEventListener? onUp;

  /// See [Listener.onMove].
  PointerEventListener? onMove;

  /// See [Listener.onDrag].
  PointerEventListener? onDrag;

  /// See [Listener.onScroll].
  PointerEventListener? onScroll;

  /// See [Listener.scrollAxis].
  Axis? scrollAxis;

  // the render object it takes the events over while it is not in the
  // tree itself ([listenOver])
  RenderObject? _over;

  @override
  MouseTracking get _needs {
    if (onMove != null) {
      return MouseTracking.motion;
    }
    if (onDrag != null) {
      return MouseTracking.drags;
    }
    return onDown != null || onUp != null || onScroll != null
        ? MouseTracking.buttons
        : MouseTracking.off;
  }

  /// Its callback for [kind].
  PointerEventListener? _callbackFor(MouseKind kind) => switch (kind) {
    MouseKind.down => onDown,
    MouseKind.up => onUp,
    MouseKind.move => onMove,
    MouseKind.drag => onDrag,
    _ => onScroll,
  };

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    final callbacks = [
      if (onDown != null) 'down',
      if (onUp != null) 'up',
      if (onMove != null) 'move',
      if (onDrag != null) 'drag',
      if (onScroll != null) 'scroll',
    ];
    properties.add(
      'listens',
      callbacks.isEmpty ? 'none' : callbacks.join(', '),
    );
    final scrollAxis = this.scrollAxis;
    if (onScroll != null && scrollAxis != null) {
      properties.add('scrollAxis', scrollAxis.name);
    }
  }
}

/// What a [MouseRegion] puts in the render tree.
final class RenderMouseRegion extends _RenderMouseTarget {
  /// The render object of a [MouseRegion] of the callbacks given.
  RenderMouseRegion({
    this.onEnter,
    this.onExit,
    this.onHover,
    this.cursor,
    HitTestBehavior behavior = HitTestBehavior.opaque,
  }) : super(behavior);

  /// See [MouseRegion.onEnter].
  PointerEventListener? onEnter;

  /// See [MouseRegion.onExit].
  PointerEventListener? onExit;

  /// See [MouseRegion.onHover].
  PointerEventListener? onHover;

  /// See [MouseRegion.cursor].
  PointerShape? cursor;

  // the terminal of its app shows the pointer's shape
  var _shapesShown = false;

  @override
  MouseTracking get _needs =>
      onEnter != null ||
          onExit != null ||
          onHover != null ||
          (cursor != null && _shapesShown)
      ? MouseTracking.motion
      : MouseTracking.off;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    final cursor = this.cursor;
    if (cursor != null) {
      properties.add('cursor', cursor.css);
    }
  }
}

/// Routes the mouse events of an app to its [Listener]s and
/// [MouseRegion]s by a hit test of its render tree, and counts what those
/// mounted under [scope] need the terminal to report ([tracking]). The
/// binding has one, and switches the terminal's reports to [tracking].
final class MouseTracker {
  /// Hit tests with [_hitTest] (`PipelineOwner.hitTest`); what a callback
  /// throws goes to [_failed] with the render object whose callback it is.
  MouseTracker(this._hitTest, this._failed);

  final void Function(HitTestResult result, int x, int y) _hitTest;
  final Never Function(RenderObject target, Object error, StackTrace stack)
  _failed;

  // what shows the pointer's shape, from the first region mounted
  TerminalStatus? _status;

  /// [child] under this tracker: the [Listener]s and [MouseRegion]s in it
  /// are counted and get its events.
  Widget scope(Widget child) => _MouseScope(this, child: child);

  /// The tracker of the app [context] is in; null outside an app.
  static MouseTracker? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_MouseScope>()?.tracker;

  // the targets mounted, by what they need reported
  final _counts = List<int>.filled(MouseTracking.values.length, 0);

  /// The most any [Listener] or [MouseRegion] mounted needs reported:
  /// [MouseTracking.off] while none with a callback is.
  MouseTracking get tracking {
    for (var i = _counts.length - 1; i > 0; i--) {
      if (_counts[i] > 0) {
        return MouseTracking.values[i];
      }
    }
    return MouseTracking.off;
  }

  void _add(_RenderMouseTarget target) {
    final needs = target._needs;
    target
      .._tracker = this
      .._counted = needs;
    _counts[needs.index]++;
  }

  void _remove(_RenderMouseTarget target) {
    _counts[target._counted.index]--;
    target._tracker = null;
  }

  // how many listeners take the events over a render object of their own
  // ([listenOver])
  var _overs = 0;

  void _recount(_RenderMouseTarget target) {
    final needs = target._needs;
    if (needs != target._counted) {
      _counts[target._counted.index]--;
      _counts[needs.index]++;
      target._counted = needs;
    }
  }

  final _result = HitTestResult();

  // the listeners the last hit test found, the deepest first, and where
  // each was hit in its own coordinates
  final _hit = _Hits<RenderListener>();

  // the listeners a press was hit in, the deepest first, while a button
  // is held; and the buttons held, a bit each
  final _captured = <RenderListener>[];
  var _held = 0;

  // whether the press under way was made over an AbsorbPointer
  var _pressAbsorbed = false;

  /// How many presses began with no button held, or with one held again
  /// (its release lost): the number of the press under way, which tells a
  /// `GestureDetector` the presses apart.
  int get presses => _presses;
  var _presses = 0;

  // the regions the mouse is in, the deepest first; and those the last hit
  // test found, with where each was hit in its own coordinates
  var _hovered = _Hits<RenderMouseRegion>();
  var _hovering = _Hits<RenderMouseRegion>();

  // where the mouse was reported last; null when not known
  int? _x;
  int? _y;

  /// Gives [event] to the [Listener]s and [MouseRegion]s it is for (see
  /// both); returns whether a Listener took it, or an `AbsorbPointer`
  /// did: one hit there, or for a drag or a release while a button is
  /// held, where the press was.
  bool dispatch(MouseEvent event) {
    final MouseEvent(:kind, :x, :y, :button) = event;
    _x = x;
    _y = y;
    _hitTest(_result, x, y);
    _moveTo(kind, x, y, button, event.modifiers, hover: true);
    final bit = 1 << button;
    switch (kind) {
      case MouseKind.down:
        // a button held again: its release was lost
        if (_held == 0 || _held & bit != 0) {
          _released();
          _presses++;
          _captured.clear();
          final hit = _listenersHit();
          for (var i = 0; i < hit.length; i++) {
            _captured.add(hit[i]);
          }
          _held = 0;
          _pressAbsorbed = _absorbed();
        }
        _held |= bit;
        return _deliver(_captured, event) || _pressAbsorbed;
      case MouseKind.up:
        final taken = _held == 0
            ? _deliverHit(event) || _absorbed()
            : _deliver(_captured, event) || _pressAbsorbed;
        _held &= ~bit;
        if (_held == 0) {
          _captured.clear();
          _released();
        }
        return taken;
      case MouseKind.drag:
        return _held == 0
            ? _deliverHit(event) || _absorbed()
            : _deliver(_captured, event) || _pressAbsorbed;
      case MouseKind.move:
        // no button is held: a release was lost
        _captured.clear();
        _held = 0;
        _released();
        return _deliverHit(event) || _absorbed();
      case MouseKind.wheelUp ||
          MouseKind.wheelDown ||
          MouseKind.wheelLeft ||
          MouseKind.wheelRight:
        final axis = kind == MouseKind.wheelUp || kind == MouseKind.wheelDown
            ? Axis.vertical
            : Axis.horizontal;
        // the deepest that takes the axis, else the deepest that scrolls
        final hit = _listenersHit();
        var to = -1;
        for (var i = 0; i < hit.length; i++) {
          final listener = hit[i];
          if (listener.onScroll != null) {
            final along = listener.scrollAxis;
            if (along == null || along == axis) {
              to = i;
              break;
            }
            if (to < 0) {
              to = i;
            }
          }
        }
        if (to < 0) {
          return _absorbed();
        }
        final listener = hit[to];
        final at = PointerEvent(
          kind,
          hit.xAt(to),
          hit.yAt(to),
          screenX: x,
          screenY: y,
          modifiers: event.modifiers,
        );
        _call(listener, listener.onScroll!, at);
        return true;
    }
  }

  /// Calls [callback] once, when the press under way ends: after the
  /// listeners got the release of its last button, or, its release lost,
  /// before they get the press or the motion with no button held that
  /// comes instead.
  void whenReleased(void Function() callback) => _whenReleased.add(callback);

  final _whenReleased = <void Function()>[];

  void _released() {
    if (_whenReleased.isEmpty) {
      return;
    }
    final callbacks = List.of(_whenReleased);
    _whenReleased.clear();
    for (final callback in callbacks) {
      callback();
    }
  }

  /// Adds what the app's render tree has at [x], [y] of the screen to
  /// [result] ([HitTestResult]), the deepest object first, as laid out
  /// last.
  void hitTest(HitTestResult result, int x, int y) => _hitTest(result, x, y);

  /// Tells the regions a frame moved under the mouse or away from it, as
  /// a move to where it is would (no hover). The mouse is forgotten while
  /// the terminal does not report all of its motion: it may be anywhere.
  void afterFrame() {
    final x = _x;
    final y = _y;
    if (tracking != MouseTracking.motion) {
      _x = _y = null;
      _hovered.reset();
      _showCursor();
      return;
    }
    if (x == null || y == null) {
      return;
    }
    _hitTest(_result, x, y);
    final kind = _held == 0 ? MouseKind.move : MouseKind.drag;
    var button = 0;
    while (_held != 0 && _held & (1 << button) == 0) {
      button++;
    }
    _moveTo(kind, x, y, button, 0, hover: false);
  }

  /// Whether [_result] holds an `AbsorbPointer` that takes the event.
  bool _absorbed() {
    final result = _result;
    for (var i = 0; i < result.length; i++) {
      if (result[i] case RenderAbsorbPointer(absorbing: true)) {
        return true;
      }
    }
    return false;
  }

  /// The listeners [_result] holds, the deepest first, with where each
  /// was hit.
  _Hits<RenderListener> _listenersHit() {
    final hit = _hit..reset();
    final result = _result;
    for (var i = 0; i < result.length; i++) {
      final o = result[i];
      if (o case final RenderListener listener) {
        hit.add(listener, result.xAt(i), result.yAt(i));
      } else if (_overs > 0) {
        if (_listenersOver[o] case final listener?
            when identical(listener._tracker, this)) {
          hit.add(listener, result.xAt(i), result.yAt(i));
        }
      }
    }
    return hit;
  }

  /// The mouse is at [x], [y], where [_result] was hit tested: the regions
  /// it left and those it came into are told, then with [hover] those it
  /// is in, for a move.
  void _moveTo(
    MouseKind kind,
    int x,
    int y,
    int button,
    int modifiers, {
    required bool hover,
  }) {
    final now = _hovering..reset();
    final result = _result;
    for (var i = 0; i < result.length; i++) {
      if (result[i] case final RenderMouseRegion region) {
        now.add(region, result.xAt(i), result.yAt(i));
      }
    }
    final before = _hovered;
    _hovered = now;
    _hovering = before;
    for (var i = 0; i < before.length; i++) {
      final region = before[i];
      final onExit = region.onExit;
      if (onExit != null && !now.contains(region)) {
        // where it is now, not where it was hit
        final at = _pointerAt(region, kind, x, y, button, modifiers);
        if (at != null) {
          _call(region, onExit, at);
        }
      }
    }
    // the outermost first
    for (var i = now.length - 1; i >= 0; i--) {
      final region = now[i];
      final onEnter = region.onEnter;
      if (onEnter != null && !before.contains(region)) {
        _call(
          region,
          onEnter,
          _local(kind, now.xAt(i), now.yAt(i), x, y, button, modifiers),
        );
      }
    }
    if (hover && kind == MouseKind.move) {
      for (var i = 0; i < now.length; i++) {
        final region = now[i];
        final onHover = region.onHover;
        if (onHover != null) {
          _call(
            region,
            onHover,
            _local(kind, now.xAt(i), now.yAt(i), x, y, button, modifiers),
          );
        }
      }
    }
    _showCursor();
  }

  static PointerEvent _local(
    MouseKind kind,
    int localX,
    int localY,
    int x,
    int y,
    int button,
    int modifiers,
  ) => PointerEvent(
    kind,
    localX,
    localY,
    screenX: x,
    screenY: y,
    button: button,
    modifiers: modifiers,
  );

  /// Shows the pointer's shape of the deepest region the mouse is in that
  /// has a cursor, the terminal's own when none has.
  void _showCursor() {
    final status = _status;
    if (status == null) {
      return;
    }
    PointerShape? shape;
    final hovered = _hovered;
    for (var i = 0; i < hovered.length; i++) {
      shape = hovered[i].cursor;
      if (shape != null) {
        break;
      }
    }
    status.pointerShape = shape;
  }

  /// Gives [event] to each of [targets], those a press captured, with a
  /// callback for it, in order; returns whether one had. They may have
  /// moved since the press, or left the tree.
  bool _deliver(List<RenderListener> targets, MouseEvent event) {
    final MouseEvent(:kind, :x, :y, :button, :modifiers) = event;
    var taken = false;
    for (final target in targets) {
      final callback = target._callbackFor(kind);
      // one that left the tree since the press gets nothing
      final at = callback == null
          ? null
          : _pointerAt(target._over ?? target, kind, x, y, button, modifiers);
      if (at != null) {
        taken = true;
        _call(target, callback!, at);
      }
    }
    return taken;
  }

  /// Gives [event] to each listener [_result] holds with a callback for
  /// it, the deepest first, in the cell it was hit at; returns whether one
  /// had.
  bool _deliverHit(MouseEvent event) {
    final MouseEvent(:kind, :x, :y, :button, :modifiers) = event;
    final hit = _listenersHit();
    var taken = false;
    for (var i = 0; i < hit.length; i++) {
      final target = hit[i];
      final callback = target._callbackFor(kind);
      if (callback != null) {
        taken = true;
        _call(
          target,
          callback,
          _local(kind, hit.xAt(i), hit.yAt(i), x, y, button, modifiers),
        );
      }
    }
    return taken;
  }

  /// The event of [kind] at [x], [y] of the screen as [target] gets it;
  /// null when it is not in the tree.
  static PointerEvent? _pointerAt(
    RenderObject target,
    MouseKind kind,
    int x,
    int y,
    int button,
    int modifiers,
  ) {
    if (target.owner == null) {
      return null;
    }
    var left = 0;
    var top = 0;
    for (var o = target; o.parent != null; o = o.parent!) {
      left += o.parentData.dx;
      top += o.parentData.dy;
    }
    return PointerEvent(
      kind,
      x - left,
      y - top,
      screenX: x,
      screenY: y,
      button: button,
      modifiers: modifiers,
    );
  }

  /// [guard] without a closure per call.
  void _call(
    RenderObject target,
    PointerEventListener callback,
    PointerEvent event,
  ) {
    try {
      callback(event);
    } on Object catch (error, stack) {
      _caught(
        target is RenderListener ? target._over ?? target : target,
        error,
        stack,
      );
    }
  }

  // what a guard threw last, which one around it passes on as it is
  Object? _thrown;

  /// Calls [callback], one of [target]'s: what it throws ends the app as
  /// what a [Listener]'s callback throws does, in the widget of [target],
  /// also when called from a timer or from another's callback (a
  /// `GestureDetector`'s).
  void guard(RenderObject target, void Function() callback) {
    try {
      callback();
    } on Object catch (error, stack) {
      _caught(target, error, stack);
    }
  }

  /// What [guard] does with what a callback of [target] threw.
  Never _caught(RenderObject target, Object error, StackTrace stack) {
    if (identical(error, _thrown)) {
      Error.throwWithStackTrace(error, stack);
    }
    try {
      _failed(target, error, stack);
    } on Object catch (thrown) {
      _thrown = thrown;
      rethrow;
    }
  }
}

// What a Draggable needs of its Listener; hidden from the library's
// exports.

/// Gives [listener] [onDrag] at once, as its [Listener] built again with
/// it would, and counts what it needs again: a press that needs the drags
/// after it gets those the terminal reports before the next frame.
void setOnDrag(RenderListener listener, PointerEventListener? onDrag) {
  listener
    ..onDrag = onDrag
    .._recount();
}

// What a Text that tells its links' taps needs; hidden from the library's
// exports.

// the listener that takes the events over each render object, by it
final _listenersOver = Expando<RenderListener>('listener over');

/// Gives the events over [target], a render object whose widget cannot put
/// a [Listener] around it (a leaf's), to [listener], a render object of
/// its own out of the tree, as a Listener around [target] would get them,
/// in [target]'s coordinates; counts what it needs in the tracker of the
/// app [context] is in, which does nothing outside an app. In place of
/// the one [target] had; [stopListeningOver] lets it go.
void listenOver(
  BuildContext context,
  RenderObject target,
  RenderListener listener,
) {
  final was = _listenersOver[target];
  if (identical(was, listener)) {
    listener._recount();
    return;
  }
  if (was != null) {
    stopListeningOver(target);
  }
  final tracker = MouseTracker.of(context);
  if (tracker == null) {
    return;
  }
  _listenersOver[target] = listener;
  listener._over = target;
  tracker
    .._add(listener)
    .._overs += 1;
}

/// Lets go of the listener [listenOver] gave [target], if it has one: it
/// gets no more events, those of a press under way included.
void stopListeningOver(RenderObject target) {
  final listener = _listenersOver[target];
  if (listener == null) {
    return;
  }
  _listenersOver[target] = null;
  listener._over = null;
  if (listener._tracker case final tracker?) {
    tracker
      .._remove(listener)
      .._overs -= 1;
  }
}

/// What finds the [MouseTracker] from below.
final class _MouseScope extends InheritedWidget {
  const _MouseScope(this.tracker, {required super.child});

  final MouseTracker tracker;

  @override
  bool updateShouldNotify(_MouseScope oldWidget) =>
      !identical(tracker, oldWidget.tracker);
}

/// Render objects a hit test found, each with the cell it was hit at in
/// its own coordinates, the deepest first: storage that [reset] keeps (a
/// growable list's `clear` lets go of its own, and the next `add`
/// allocates again).
final class _Hits<T extends RenderObject> {
  var _targets = List<T?>.filled(8, null);
  var _xs = Int32List(8);
  var _ys = Int32List(8);

  /// The objects held.
  int get length => _length;
  var _length = 0;

  T operator [](int i) => _targets[i]!;

  /// The column of the cell [this[i]] was hit at.
  int xAt(int i) => _xs[i];

  /// The row of the cell [this[i]] was hit at.
  int yAt(int i) => _ys[i];

  bool contains(T target) {
    for (var i = 0; i < _length; i++) {
      if (identical(_targets[i], target)) {
        return true;
      }
    }
    return false;
  }

  /// Empties it, letting go of the objects.
  void reset() {
    for (var i = 0; i < _length; i++) {
      _targets[i] = null;
    }
    _length = 0;
  }

  void add(T target, int x, int y) {
    final n = _length;
    if (n == _targets.length) {
      _targets = List<T?>.filled(2 * n, null)..setRange(0, n, _targets);
      _xs = Int32List(2 * n)..setRange(0, n, _xs);
      _ys = Int32List(2 * n)..setRange(0, n, _ys);
    }
    _targets[n] = target;
    _xs[n] = x;
    _ys[n] = y;
    _length = n + 1;
  }
}
