/// Gestures in the presses of the mouse: a [GestureDetector] tells taps,
/// double taps, long presses and drags, the deepest of those hit by a
/// press that recognises a gesture getting it.
library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart' show HitTestBehavior, PointerShape;

import '../binding/app_binding.dart' show AppBinding;
import '../framework/framework.dart';
import '../style/theme.dart' show ThemeData;
import 'hand.dart';
import 'mouse.dart';

/// A drag as a [GestureDetector] tells it: the event the mouse was
/// reported in, and the cells it moved since the drag was told last.
///
/// Two details are equal when their events and moves are. See
/// [GestureDetector] for one in use.
@immutable
final class DragDetails {
  /// A drag in [event] that moved [dx] columns and [dy] rows.
  const DragDetails(this.event, {this.dx = 0, this.dy = 0});

  /// The press for the start, a drag for an update, the release for the
  /// end; the cell in the coordinates of the detector.
  final PointerEvent event;

  /// The columns the mouse moved since the drag was told last: 0 at the
  /// start.
  final int dx;

  /// The rows the mouse moved since the drag was told last: 0 at the
  /// start.
  final int dy;

  /// The column of the cell from the left of the detector.
  int get x => event.x;

  /// The row of the cell from the top of the detector.
  int get y => event.y;

  @override
  bool operator ==(Object other) =>
      other is DragDetails &&
      other.event == event &&
      other.dx == dx &&
      other.dy == dy;

  @override
  int get hashCode => Object.hash(event, dx, dy);

  @override
  String toString() => 'Drag($event, $dx,$dy)';
}

/// What a [GestureDetector] tells a drag with.
typedef DragListener = void Function(DragDetails details);

/// Tells the gestures of the presses over [child]: taps, double taps, long
/// presses and drags.
///
/// It takes the presses of [buttons] (the left one by default), and tells
/// each gesture with the cell in the coordinates of this widget and the
/// button: a tap ([onTap]), a double tap ([onDoubleTap]), a long press
/// ([onLongPress], [onLongPressEnd]) and a drag ([onDragStart],
/// [onDragUpdate], [onDragEnd]). It is a [Listener] underneath, hit as
/// [behavior] says: by default where its child is.
///
/// A press is a drag once the mouse moves to another cell with the button
/// held; a long press once it is held for [longPressDuration] with the
/// mouse over this widget; a tap when it is released over this widget, if
/// neither, wherever the mouse went in between. With an [onDoubleTap], a
/// tap waits [doubleTapInterval] for the next press: a tap of the same
/// button there is a double tap, else [onTap] is told of the first one,
/// before any gesture that follows it.
///
/// Detectors hit by one press, one inside another, compete for it: each
/// gesture goes to the deepest of them that recognises it (has a callback
/// for it and, for a tap or a long press, the mouse over it), and a press
/// is one gesture: once it is a drag, a long press or a tap, the others
/// get nothing of it. A press of a button one does not take goes to those
/// around it that do. A `Draggable` hit by the press competes as a
/// detector that drags. A drag or a long press whose release the terminal
/// did not report ends where the mouse was last when the next press over
/// a detector comes.
///
/// A press is declared here once, and the pointer follows from it. Where a
/// tap of the left button is told ([onTap], [onTapDown]), the pointer is the
/// hand, by [ThemeData.pointerMode], and there is no hand to remember. A
/// double tap alone, or a press of another button alone, shows none.
/// [cursor] puts a shape of its own in the hand's place, and over all of it
/// where no tap is told, so that a drag has a pointer too. [tapAt] is for
/// targets inside one row: it says which cells a tap is on, for the hand
/// and for the tap at once.
///
/// [onTapDown] is told as the left button goes down, for what answers at
/// once (a tab, a menu's title). It is told apart from the competition: a
/// tap, drag or long press of that press goes on as without it, here and
/// in the detectors inside and around it.
///
/// The intervals are timers of the app's zone, which a test's fake clock
/// moves. While it has a callback, the terminal reports presses and
/// releases, and motion with a button held for a long press or a drag (see
/// [Listener]); like a Listener, it takes the presses of every button
/// over it from the app's `InputListener`s.
///
/// A card opened by a double click and moved by a drag:
///
/// ```dart
/// var left = 0;
/// var top = 0;
/// final card = GestureDetector(
///   onDoubleTap: (_) => print('open'),
///   onDragUpdate: (drag) {
///     left += drag.dx;
///     top += drag.dy;
///   },
///   child: const Box(
///     border: Border.all(type: BorderType.rounded),
///     child: Text('card'),
///   ),
/// );
/// ```
///
/// Steps in one row, a click on those that can be reached, the hand over
/// the same cells:
///
/// ```dart
/// late int Function(int x) stepAt;
/// final steps = GestureDetector(
///   tapAt: (x, y) => stepAt(x) >= 0,
///   onTap: (event) => print('step ${stepAt(event.x)}'),
///   child: const Text('one  two  three'),
/// );
/// ```
///
/// See also:
///
///  * [Listener], the events of the mouse themselves.
///  * `Draggable` and `DragTarget`, a drag that carries data.
final class GestureDetector extends StatefulWidget {
  /// Tells the callbacks given of the gestures over [child].
  const GestureDetector({
    super.key,
    this.onTap,
    this.onTapDown,
    this.tapAt,
    this.cursor,
    this.onDoubleTap,
    this.onLongPress,
    this.onLongPressEnd,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.buttons = const {0},
    this.doubleTapInterval = const Duration(milliseconds: 300),
    this.longPressDuration = const Duration(milliseconds: 500),
    this.behavior = HitTestBehavior.deferToChild,
    this.child,
  });

  /// A tap: the release.
  final PointerEventListener? onTap;

  /// The left button pressed, on a cell of a tap (see [GestureDetector]).
  final PointerEventListener? onTapDown;

  /// Whether the cell at `x`, `y` of it is a tap's: where false, the hand
  /// does not show, and a press there is told neither [onTap] nor
  /// [onTapDown], a detector around it getting it. A tap is pressed and
  /// released on such cells, so [onTap] may rely on it for the cell it is
  /// told. Null for all of it.
  final bool Function(int x, int y)? tapAt;

  /// The pointer's shape in place of the hand, whatever
  /// [ThemeData.pointerMode] says, over the cells of a tap, or over all of
  /// it with neither [onTap] nor [onTapDown]; null for the hand.
  /// `PointerShape.arrow`, for a click that presses nothing (the ground
  /// around a dialog), has the terminal report no motion for it; another
  /// shape does, as [MouseRegion.cursor].
  final PointerShape? cursor;

  /// A second tap within [doubleTapInterval] of a tap: its release.
  final PointerEventListener? onDoubleTap;

  /// A press held for [longPressDuration]: the event the mouse was
  /// reported in last, the press or a drag after it.
  final PointerEventListener? onLongPress;

  /// The release of a long press, wherever the mouse is.
  final PointerEventListener? onLongPressEnd;

  /// The start of a drag: the press, where the drag starts from.
  final DragListener? onDragStart;

  /// The mouse moved to another cell in a drag, wherever it is.
  final DragListener? onDragUpdate;

  /// The release that ends a drag, wherever the mouse is.
  final DragListener? onDragEnd;

  /// The buttons whose presses it takes: 0 left, 1 middle, 2 right, 8 to
  /// 11 the side buttons.
  final Set<int> buttons;

  /// How long after a tap's release the next press makes a double tap. It
  /// is a timer of the app: the detector needs one above it (`runApp`, or a
  /// `Cli`), see [AppBinding.startTimer].
  final Duration doubleTapInterval;

  /// How long a press is held to be a long press. It is a timer of the
  /// app: the detector needs one above it (`runApp`, or a `Cli`), see
  /// [AppBinding.startTimer].
  final Duration longPressDuration;

  /// Where it is hit.
  final HitTestBehavior behavior;

  /// What the presses are over.
  final Widget? child;

  @override
  State<GestureDetector> createState() => _GestureDetectorState();
}

final class _GestureDetectorState extends State<GestureDetector> {
  // the arena of the app it got a press in
  _Arena? _arena;

  // the press under way as it got it, while it competes for it: where it
  // was pressed and where the mouse was reported last
  PointerEvent? _pressed;
  PointerEvent? _last;

  // when the press is held long enough
  Timer? _longPress;

  bool get _taps => widget.onTap != null || widget.onDoubleTap != null;

  // whether the press under way is on a cell of a tap
  var _tapHere = true;

  /// Whether [event], a release, ends a tap: over this widget, pressed and
  /// released on cells of [GestureDetector.tapAt].
  bool _tapsAt(PointerEvent event) =>
      _taps &&
      _tapHere &&
      _contains(event) &&
      (widget.tapAt?.call(event.x, event.y) ?? true);

  /// Whether a tap of the left button is told.
  bool get _showsTap =>
      (widget.onTap != null || widget.onTapDown != null) &&
      widget.buttons.contains(0);

  bool get _longPresses =>
      widget.onLongPress != null || widget.onLongPressEnd != null;

  bool get _drags =>
      widget.onDragStart != null ||
      widget.onDragUpdate != null ||
      widget.onDragEnd != null;

  /// Whether [event] is over this widget.
  bool _contains(PointerEvent event) {
    final box = context.findRenderObject()!;
    return event.x >= 0 &&
        event.y >= 0 &&
        event.x < box.width &&
        event.y < box.height;
  }

  /// Calls [callback] with [argument], unless it is null, as a callback of
  /// this widget's.
  void _tell<T>(void Function(T)? callback, T argument) {
    if (callback != null) {
      _arena!.tracker.guard(
        context.findRenderObject()!,
        () => callback(argument),
      );
    }
  }

  void _down(PointerEvent event) {
    _tapHere = widget.tapAt?.call(event.x, event.y) ?? true;
    if (MouseTracker.of(context) case final tracker?) {
      (_arena = _Arena.of(tracker)).down(this, event);
      if (_tapHere && event.button == 0 && widget.buttons.contains(0)) {
        _tell(widget.onTapDown, event);
      }
    }
  }

  void _drag(PointerEvent event) => _arena?.drag(this, event);

  void _up(PointerEvent event) => _arena?.up(this, event);

  @override
  void dispose() {
    _arena?.leave(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listens = _taps || widget.onTapDown != null || _longPresses || _drags;
    final taps = _showsTap;
    return HandOver(
      active: taps || widget.cursor != null,
      where: taps ? widget.tapAt : null,
      shape: widget.cursor,
      behavior: widget.behavior,
      child: Listener(
        onDown: listens ? _down : null,
        onUp: listens ? _up : null,
        onDrag: _longPresses || _drags ? _drag : null,
        behavior: widget.behavior,
        child: widget.child,
      ),
    );
  }
}

/// Takes the press of [button] under way in [tracker]'s app as a drag of
/// a widget that is not a [GestureDetector] (a `Draggable`), unless a
/// detector hit by it took it already: the detectors get nothing more of
/// it, after the tap that waits for a second one is told. Returns whether
/// it took it. Hidden from the library's exports.
bool takeDrag(MouseTracker tracker, int button) =>
    _Arena.of(tracker).takeDrag(button);

/// What a press is once a detector took it.
enum _Gesture { tap, longPress, drag }

/// The presses of an app's mouse as its [GestureDetector]s compete for
/// them, and the tap that waits for a second one.
final class _Arena {
  /// The arena of [tracker]'s app.
  factory _Arena.of(MouseTracker tracker) =>
      _arenas[tracker] ??= _Arena._(tracker);

  _Arena._(this.tracker);

  static final _arenas = Expando<_Arena>();

  final MouseTracker tracker;

  // the press under way: its number (MouseTracker.presses) and button, the
  // detectors it was hit in that take the button, the deepest first, and
  // which took it as what
  var _press = 0;
  var _button = 0;
  final _members = <_GestureDetectorState>[];
  _Gesture? _gesture;
  _GestureDetectorState? _owner;

  // a tap that waits for a second one: whose, its release, and the number
  // of the press that came within the interval, if one did
  _GestureDetectorState? _first;
  PointerEvent? _firstUp;
  Timer? _interval;
  int? _again;

  void down(_GestureDetectorState detector, PointerEvent event) {
    if (tracker.presses != _press) {
      _begin(event.button);
    } else if (event.button != _button) {
      // another button while the press's is held
      return;
    }
    if (!detector.widget.buttons.contains(event.button)) {
      return;
    }
    _members.add(detector);
    detector
      .._pressed = event
      .._last = event;
    if (identical(_first, detector) && _firstUp!.button == event.button) {
      _interval!.cancel();
      _again = _press;
    }
    if (detector._longPresses) {
      detector._longPress = AppBinding.of(detector.context).startTimer(
        detector.widget.longPressDuration,
        () => _heldLong(detector),
      );
    }
  }

  void drag(_GestureDetectorState detector, PointerEvent event) {
    final pressed = detector._pressed;
    if (pressed == null) {
      return;
    }
    final last = detector._last!;
    detector._last = event;
    switch (_gesture) {
      case null
          when detector._drags &&
              (event.x != pressed.x || event.y != pressed.y):
        _take(detector, _Gesture.drag);
        detector
          .._tell(detector.widget.onDragStart, DragDetails(pressed))
          .._tell(
            detector.widget.onDragUpdate,
            DragDetails(
              event,
              dx: event.x - pressed.x,
              dy: event.y - pressed.y,
            ),
          );
      case _Gesture.drag
          when identical(_owner, detector) &&
              (event.x != last.x || event.y != last.y):
        detector._tell(
          detector.widget.onDragUpdate,
          DragDetails(event, dx: event.x - last.x, dy: event.y - last.y),
        );
      case _:
    }
  }

  /// See [takeDrag].
  bool takeDrag(int button) {
    if (tracker.presses != _press) {
      _begin(button);
    } else if (_gesture != null || button != _button) {
      return false;
    }
    _take(null, _Gesture.drag);
    return true;
  }

  void up(_GestureDetectorState detector, PointerEvent event) {
    final last = detector._last;
    if (last == null || event.button != _button) {
      return;
    }
    _leavePress(detector);
    switch (_gesture) {
      case null when detector._tapsAt(event):
        _gesture = _Gesture.tap;
        _owner = detector;
        if (identical(_first, detector) && _again == _press) {
          _first = _firstUp = _again = null;
          detector._tell(detector.widget.onDoubleTap, event);
        } else {
          _flush();
          if (detector.widget.onDoubleTap == null) {
            detector._tell(detector.widget.onTap, event);
          } else {
            _first = detector;
            _firstUp = event;
            _interval = AppBinding.of(
              detector.context,
            ).startTimer(detector.widget.doubleTapInterval, _flush);
          }
        }
      case _Gesture.drag when identical(_owner, detector):
        detector._tell(
          detector.widget.onDragEnd,
          DragDetails(event, dx: event.x - last.x, dy: event.y - last.y),
        );
      case _Gesture.longPress when identical(_owner, detector):
        detector._tell(detector.widget.onLongPressEnd, event);
      case _:
    }
    if (identical(_first, detector) && _again == _press) {
      // pressed again, and no double tap
      _flush();
    }
  }

  /// The press of [detector] held long enough.
  void _heldLong(_GestureDetectorState detector) {
    detector._longPress = null;
    final last = detector._last;
    if (_gesture != null || last == null || !detector._contains(last)) {
      return;
    }
    _take(detector, _Gesture.longPress);
    detector._tell(detector.widget.onLongPress, last);
  }

  /// [detector] takes the press as [gesture], or a widget that is not a
  /// detector when null: the others get nothing more of it, after the tap
  /// that waits for a second one is told.
  void _take(_GestureDetectorState? detector, _Gesture gesture) {
    _gesture = gesture;
    _owner = detector;
    for (final member in _members) {
      member._longPress?.cancel();
      member._longPress = null;
    }
    _flush();
  }

  /// Tells the tap that waits for a second one, if one does.
  void _flush() {
    final first = _first;
    final up = _firstUp;
    _first = _firstUp = _again = null;
    _interval?.cancel();
    _interval = null;
    if (first != null) {
      first._tell(first.widget.onTap, up!);
    }
  }

  /// Starts a new press of [button]; the one before ends, its drag or long
  /// press told of the end where the mouse was last, as its release was not
  /// reported.
  void _begin(int button) {
    final owner = _owner;
    final last = owner?._last;
    if (owner != null && last != null) {
      switch (_gesture) {
        case _Gesture.drag:
          owner._tell(owner.widget.onDragEnd, DragDetails(last));
        case _Gesture.longPress:
          owner._tell(owner.widget.onLongPressEnd, last);
        case _:
      }
    }
    for (final member in _members) {
      _leavePress(member);
    }
    if (_again != null) {
      _flush();
    }
    _members.clear();
    _gesture = null;
    _owner = null;
    _press = tracker.presses;
    _button = button;
  }

  /// [detector] is done with the press under way.
  void _leavePress(_GestureDetectorState detector) {
    detector
      .._pressed = null
      .._last = null
      .._longPress?.cancel()
      .._longPress = null;
  }

  /// [detector] leaves the tree: it competes no more, and its tap that
  /// waits for a second one is not told.
  void leave(_GestureDetectorState detector) {
    _leavePress(detector);
    _members.remove(detector);
    if (identical(_owner, detector)) {
      _owner = null;
    }
    if (identical(_first, detector)) {
      _first = _firstUp = _again = null;
      _interval?.cancel();
      _interval = null;
    }
  }
}
