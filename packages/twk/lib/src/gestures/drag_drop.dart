/// Drag and drop: a [Draggable] drags its data, a feedback widget following
/// the mouse in the overlay, and the [DragTarget] it is released over takes
/// the data if it accepts it.
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        BoxConstraints,
        DiagnosticPropertiesBuilder,
        HitTestBehavior,
        HitTestResult,
        PaintContext,
        RenderObject,
        RenderObjectWithChildMixin;

import '../foundation/foundation.dart';
import '../framework/framework.dart';
import '../layout/one_child.dart';
import '../overlay/layer.dart';
import 'gesture_detector.dart';
import 'mouse.dart';

/// A drag over a [DragTarget] as the target is told it: the data, and the
/// event the mouse was reported in, with the cell in the coordinates of the
/// target.
///
/// Two details are equal when their data and events are.
@immutable
final class DragTargetDetails<T extends Object> {
  /// The drag of [data] in [event].
  const DragTargetDetails(this.data, this.event);

  /// What the [Draggable] drags.
  final T data;

  /// A drag, or the release for a drop.
  final PointerEvent event;

  @override
  bool operator ==(Object other) =>
      other is DragTargetDetails<T> &&
      other.data == data &&
      other.event == event;

  @override
  int get hashCode => Object.hash(data, event);

  @override
  String toString() => 'DragTargetDetails($data, $event)';
}

/// What a [DragTarget] builds: with the data of the drag over it that it
/// accepts ([candidate]) or rejects ([rejected]); both null while no drag
/// is over it.
typedef DragTargetBuilder<T extends Object> = Widget Function(
  BuildContext context,
  T? candidate,
  Object? rejected,
);

/// Drags [data] from [child] with the left button, to drop it on a
/// [DragTarget].
///
/// Once the mouse moves to another cell with the button held, [feedback]
/// follows the mouse in the
/// [Overlay] above, placed where [child] was at the press and moved as the
/// mouse moved since, as big as it likes within the overlay, cut off at its
/// edges and never hit; [childWhenDragging], if any, shows in place of
/// [child] meanwhile. Released over a [DragTarget] that accepts the data,
/// the target gets it and [onDragCompleted] is told; released elsewhere,
/// [onDragCanceled] is. It is a [Listener] underneath, hit as [behavior]
/// says: by default where its child is.
///
/// A drag is a gesture of the press as a [GestureDetector]'s are: it takes
/// the press from the detectors around it, which get nothing more of it
/// (no tap at the release), unless one inside it took the press first, as
/// a drag or a long press, and then it does not start. A drag whose release
/// the terminal did not report is canceled at the next press, or at motion
/// with no button held. A Draggable that leaves the tree while dragged ends
/// the drag and is told nothing.
///
/// With [pointerShapes], the pointer shows what a drag would do, as a
/// [MouseRegion.cursor] sets it where the terminal shows it:
/// [PointerShape.grab] over the child, [PointerShape.grabbing] while it is
/// dragged, and [PointerShape.noDrop] while the drag is over [DragTarget]s
/// none of which accepts it.
///
/// While it is mounted, the terminal reports presses and releases, and
/// motion with a button held while it is pressed (see [Listener]); with
/// [pointerShapes], where the terminal shows the pointer's shape, all
/// motion (see [MouseRegion]). Without an [Overlay] above it the build
/// fails with a [StateError] that says where to place one.
///
/// A file dragged to the trash, which takes files only:
///
/// ```dart
/// Overlay(
///   child: Row(
///     children: [
///       const Draggable<String>(
///         data: 'notes.txt',
///         feedback: Text('[notes.txt]'),
///         childWhenDragging: Text('         '),
///         child: Text('notes.txt'),
///       ),
///       DragTarget<String>(
///         onAccept: (details) => print('deleted ${details.data}'),
///         builder: (context, candidate, rejected) =>
///             Text(candidate == null ? ' trash ' : '[trash]'),
///       ),
///     ],
///   ),
/// )
/// ```
///
/// See also:
///
///  * [GestureDetector], a drag that carries nothing.
final class Draggable<T extends Object> extends StatefulWidget {
  /// Drags [data] from [child], [feedback] following the mouse.
  const Draggable({
    required this.data,
    required this.feedback,
    required this.child,
    super.key,
    this.childWhenDragging,
    this.onDragStarted,
    this.onDragCompleted,
    this.onDragCanceled,
    this.behavior = HitTestBehavior.deferToChild,
    this.pointerShapes = true,
  });

  /// What it drags: what a target it is dropped on gets, as it was when the
  /// drag started.
  final T data;

  /// What follows the mouse while it is dragged.
  final Widget feedback;

  /// What is pressed to drag.
  final Widget child;

  /// What shows in place of [child] while it is dragged; [child] when null.
  final Widget? childWhenDragging;

  /// The drag started: the mouse moved to another cell with the left
  /// button held.
  final VoidCallback? onDragStarted;

  /// It was dropped on a target that accepted it, after the target got the
  /// data.
  final VoidCallback? onDragCompleted;

  /// The drag ended with no target accepting it.
  final VoidCallback? onDragCanceled;

  /// Where it is hit.
  final HitTestBehavior behavior;

  /// Whether it sets the pointer's shape: grab over the child, grabbing
  /// while it is dragged, no-drop over targets that refuse it. False
  /// leaves the pointer to the regions around it.
  final bool pointerShapes;

  @override
  State<Draggable<T>> createState() => _DraggableState<T>();
}

final class _DraggableState<T extends Object> extends State<Draggable<T>> {
  // the left button pressed over it, held, until it is a drag
  PointerEvent? _pressed;

  // the drag under way: its data, the overlay and the entry the feedback
  // is in, the cell of the child pressed and where the feedback is in the
  // overlay
  T? _data;
  OverlayState? _overlay;
  OverlayEntry? _feedback;
  var _pressX = 0;
  var _pressY = 0;
  var _left = 0;
  var _top = 0;

  // the targets the drag is over that were asked, the deepest first, and
  // the one of them that accepts it, with the drag in its coordinates
  final _entered = <_DragTargetState<Object>>[];
  _DragTargetState<Object>? _accepting;
  PointerEvent? _acceptingAt;

  /// Whether the drag is over targets and none of them accepts it.
  bool get _refused => _entered.isNotEmpty && _accepting == null;

  // what is under the mouse, found anew at each report of a drag
  static final _hit = HitTestResult();

  bool get _dragging => _feedback != null;

  RenderListener get _listener => context.findRenderObject()! as RenderListener;

  void _down(PointerEvent event) {
    final tracker = MouseTracker.of(context);
    if (tracker == null || event.button != 0 || _pressed != null) {
      return;
    }
    _pressed = event;
    tracker.whenReleased(_lost);
    // the drags may come before the next frame builds the listener anew
    setOnDrag(_listener, _drag);
    setState(() {});
  }

  void _drag(PointerEvent event) {
    if (_dragging) {
      _place(event);
      _feedback!.markNeedsBuild();
      _over(event, move: true);
      return;
    }
    final pressed = _pressed;
    if (pressed == null ||
        event.screenX == pressed.screenX && event.screenY == pressed.screenY) {
      return;
    }
    _pressed = null;
    if (takeDrag(MouseTracker.of(context)!, pressed.button)) {
      _start(pressed, event);
    }
    setState(() {});
  }

  void _up(PointerEvent event) {
    if (event.button != 0) {
      return;
    }
    if (_pressed != null) {
      _pressed = null;
      setState(() {});
    }
    if (!_dragging) {
      return;
    }
    _over(event, move: false);
    final accepting = _accepting;
    final at = _acceptingAt;
    final data = _data!;
    if (accepting != null) {
      _entered.remove(accepting);
      accepting._drop(data, at!);
    }
    _end();
    if (accepting != null) {
      widget.onDragCompleted?.call();
    } else {
      widget.onDragCanceled?.call();
    }
  }

  /// The press ended, its release lost if it is still pressed or dragged.
  void _lost() {
    if (!mounted) {
      return;
    }
    if (_pressed != null) {
      _pressed = null;
      setState(() {});
    }
    if (_dragging) {
      MouseTracker.of(context)!.guard(_listener, () {
        _end();
        widget.onDragCanceled?.call();
      });
    }
  }

  void _start(PointerEvent pressed, PointerEvent event) {
    final overlay = _overlay = Overlay.of(context);
    _data = widget.data;
    _pressX = pressed.x;
    _pressY = pressed.y;
    _place(event);
    overlay.insert(
      _feedback = OverlayEntry(
        // over the whole overlay, so that the shape shows wherever the
        // mouse goes; what is under it is hit as well
        builder: (_) => MouseRegion(
          cursor: !widget.pointerShapes
              ? null
              : (_refused ? PointerShape.noDrop : PointerShape.grabbing),
          behavior: HitTestBehavior.translucent,
          child: _Feedback(left: _left, top: _top, child: widget.feedback),
        ),
        // it follows the mouse from the first move to the drop
        fadeIn: Duration.zero,
        fadeOut: Duration.zero,
      ),
    );
    widget.onDragStarted?.call();
    _over(event, move: true);
  }

  /// Places the feedback for the mouse at [event].
  void _place(PointerEvent event) {
    var x = event.screenX - _pressX;
    var y = event.screenY - _pressY;
    for (
      var o = _overlay!.context.findRenderObject()!;
      o.parent != null;
      o = o.parent!
    ) {
      x -= o.parentData.dx;
      y -= o.parentData.dy;
    }
    _left = x;
    _top = y;
  }

  /// The drag is at [event]: the targets there are asked, the deepest
  /// first, as it comes over them, until one accepts it; those it left
  /// are told, and with [move] those it is over that it moved.
  void _over(PointerEvent event, {required bool move}) {
    final hit = _hit;
    MouseTracker.of(context)!.hitTest(hit, event.screenX, event.screenY);
    final found = <(_DragTargetState<Object>, PointerEvent)>[];
    for (var i = 0; i < hit.length; i++) {
      if (hit[i] case _RenderTarget(:final target)) {
        found.add((
          target,
          PointerEvent(
            event.kind,
            hit.xAt(i),
            hit.yAt(i),
            screenX: event.screenX,
            screenY: event.screenY,
            button: event.button,
            modifiers: event.modifiers,
          ),
        ));
      }
    }
    hit.reset();
    final data = _data!;
    final now = <_DragTargetState<Object>>[];
    _accepting = _acceptingAt = null;
    for (final (target, at) in found) {
      now.add(target);
      if (_entered.contains(target)
          ? target._accepts
          : target._enter(data, at)) {
        _accepting = target;
        _acceptingAt = at;
        break;
      }
    }
    for (final target in _entered) {
      if (!now.contains(target)) {
        target._leave(data);
      }
    }
    _entered
      ..clear()
      ..addAll(now);
    if (move) {
      for (final (target, at) in found.take(now.length)) {
        target._move(data, at);
      }
    }
  }

  /// Ends the drag: the feedback goes, the targets asked are told it left.
  void _end() {
    final data = _data!;
    _feedback!.remove();
    _feedback = null;
    _overlay = null;
    _data = null;
    _accepting = _acceptingAt = null;
    final left = List.of(_entered);
    _entered.clear();
    for (final target in left) {
      target._leave(data);
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    if (_dragging) {
      _end();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // fails here rather than at a drag
    Overlay.of(context);
    final w = widget;
    return Listener(
      onDown: _down,
      onUp: _up,
      onDrag: _pressed != null || _dragging ? _drag : null,
      behavior: w.behavior,
      // hit where the listener is
      child: MouseRegion(
        cursor: w.pointerShapes ? PointerShape.grab : null,
        behavior: w.behavior,
        child: _dragging ? w.childWhenDragging ?? w.child : w.child,
      ),
    );
  }
}

/// Takes the data of a [Draggable] dropped on it: shows what [builder]
/// builds, again as a drag comes over it and leaves.
///
/// A drag is over a target where it is hit, which [behavior] says: by
/// default anywhere in its bounds, what it covers hit too. At each cell
/// the mouse drags to, the targets there are asked, the deepest first, as
/// the drag comes over them, until one accepts it: its data is a [T] and
/// [onWillAccept] says yes, or there is none. That one gets the drop;
/// those asked before it reject it, those around it are not asked. A
/// target asked is not asked again until the drag leaves it ([onLeave]),
/// and is told each cell the drag goes to over it ([onMove]). At the
/// release, the target that accepts the drag gets the data ([onAccept]),
/// and the others asked are told it left.
///
/// What its callbacks throw ends the app, in this widget.
///
/// A bin that takes the numbers dragged to it, but not 13, and lights up
/// while one it takes is over it:
///
/// ```dart
/// DragTarget<int>(
///   onWillAccept: (details) => details.data != 13,
///   onAccept: (details) => print('got ${details.data}'),
///   builder: (context, candidate, rejected) => Text(
///     candidate != null ? '[bin]' : (rejected != null ? ' no! ' : ' bin '),
///   ),
/// )
/// ```
///
/// See [Draggable] for what drags the data.
final class DragTarget<T extends Object> extends StatefulWidget {
  /// A target of the data of type [T] that shows what [builder] builds.
  const DragTarget({
    required this.builder,
    super.key,
    this.onWillAccept,
    this.onAccept,
    this.onLeave,
    this.onMove,
    this.behavior = HitTestBehavior.translucent,
  });

  // the builder and the callbacks are called by the state, whose T is the
  // widget's own

  /// Builds what it shows.
  // ignore: unsafe_variance
  final DragTargetBuilder<T> builder;

  /// Whether it accepts the data of a drag that came over it.
  // ignore: unsafe_variance
  final bool Function(DragTargetDetails<T> details)? onWillAccept;

  /// The data was dropped on it: the release.
  // ignore: unsafe_variance
  final void Function(DragTargetDetails<T> details)? onAccept;

  /// The drag of data of its type left it, was dropped on another target,
  /// or ended.
  // ignore: unsafe_variance
  final void Function(T data)? onLeave;

  /// The drag of data of its type is at a cell over it: the one it came
  /// over it at, and each it went to since.
  // ignore: unsafe_variance
  final void Function(DragTargetDetails<T> details)? onMove;

  /// Where it is hit.
  final HitTestBehavior behavior;

  @override
  State<DragTarget<T>> createState() => _DragTargetState<T>();
}

final class _DragTargetState<T extends Object> extends State<DragTarget<T>> {
  // the data of the drag over it, as it accepts it or not
  T? _candidate;
  Object? _rejected;

  bool get _accepts => _candidate != null;

  /// Calls [callback], one of this widget's.
  void _call(void Function() callback) {
    final tracker = MouseTracker.of(context);
    if (tracker == null) {
      callback();
    } else {
      tracker.guard(context.findRenderObject()!, callback);
    }
  }

  /// The drag of [data] came over it, at [event]: whether it accepts it.
  bool _enter(Object data, PointerEvent event) {
    var accepts = data is T;
    final onWillAccept = widget.onWillAccept;
    if (data is T && onWillAccept != null) {
      _call(() => accepts = onWillAccept(DragTargetDetails(data, event)));
    }
    setState(() {
      if (accepts) {
        _candidate = data as T;
      } else {
        _rejected = data;
      }
    });
    return accepts;
  }

  void _move(Object data, PointerEvent event) {
    final onMove = widget.onMove;
    if (mounted && data is T && onMove != null) {
      _call(() => onMove(DragTargetDetails(data, event)));
    }
  }

  void _leave(Object data) {
    if (!mounted) {
      return;
    }
    setState(() => _candidate = _rejected = null);
    final onLeave = widget.onLeave;
    if (data is T && onLeave != null) {
      _call(() => onLeave(data));
    }
  }

  void _drop(Object data, PointerEvent event) {
    setState(() => _candidate = _rejected = null);
    final onAccept = widget.onAccept;
    if (onAccept != null) {
      _call(() => onAccept(DragTargetDetails(data as T, event)));
    }
  }

  @override
  Widget build(BuildContext context) => _Target(
    this,
    behavior: widget.behavior,
    child: widget.builder(context, _candidate, _rejected),
  );
}

/// What a [DragTarget] puts in the render tree; see [_RenderTarget].
final class _Target extends SingleChildRenderObjectWidget {
  const _Target(this.target, {required this.behavior, super.child});

  final _DragTargetState<Object> target;

  final HitTestBehavior behavior;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  _RenderTarget createRenderObject(BuildContext context) =>
      _RenderTarget(target, behavior);

  @override
  void updateRenderObject(BuildContext context, _RenderTarget renderObject) {
    renderObject
      ..target = target
      ..behavior = behavior;
  }
}

/// Its child, as big as the child is, hit as [behavior] says: where a drag
/// finds [target].
final class _RenderTarget extends _RenderProxy {
  _RenderTarget(this.target, this.behavior);

  _DragTargetState<Object> target;

  HitTestBehavior behavior;

  @override
  HitTestBehavior get hitTestBehavior => behavior;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add('behavior', behavior.name);
  }
}

/// Shows [child] at [left], [top] of the overlay; see [_RenderFeedback].
final class _Feedback extends SingleChildRenderObjectWidget {
  const _Feedback({required this.left, required this.top, super.child});

  final int left;
  final int top;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  _RenderFeedback createRenderObject(BuildContext context) =>
      _RenderFeedback(left, top);

  @override
  void updateRenderObject(BuildContext context, _RenderFeedback renderObject) {
    renderObject.at(left, top);
  }
}

/// As big as it may be, in the stack of an overlay: lays its child out as
/// big as it likes within it and places it at [_left], [_top], outside it
/// in part when that is; never hit, so that a drag finds what is under it.
final class _RenderFeedback extends RenderObject
    with RenderObjectWithChildMixin {
  _RenderFeedback(this._left, this._top);

  int _left;
  int _top;

  void at(int left, int top) {
    if (left != _left || top != _top) {
      _left = left;
      _top = top;
      markNeedsLayout();
    }
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW < BoxConstraints.unbounded ? c.maxW : c.minW;
    height = c.maxH < BoxConstraints.unbounded ? c.maxH : c.minH;
    final child = this.child;
    if (child != null) {
      child.layout(BoxConstraints(0, width, 0, height), parentUsesSize: true);
      child.parentData
        ..dx = _left
        ..dy = _top;
    }
  }

  @override
  bool hitTest(HitTestResult result, int x, int y) => false;

  @override
  void paint(PaintContext ctx) {
    final child = this.child;
    if (child != null) {
      paintChild(ctx, child);
    }
  }
}

/// A render object as big as its child, which it lays out, measures and
/// paints as if it were not there.
abstract base class _RenderProxy extends RenderObject
    with RenderObjectWithChildMixin {
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
