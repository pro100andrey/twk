/// [ScrollInput]: the wheel's events gathered into whole cells a frame.
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart' show Axis;

import 'scroll_behavior.dart';

/// Whole cells scrolled, taken from a [ScrollInput]: [rows] down and
/// [columns] right when positive.
@immutable
final class ScrollDelta {
  /// [rows] along the vertical axis and [columns] along the horizontal.
  const ScrollDelta(this.rows, this.columns);

  /// The cells along the vertical axis, positive down.
  final int rows;

  /// The cells along the horizontal axis, positive right.
  final int columns;

  @override
  bool operator ==(Object other) =>
      other is ScrollDelta && other.rows == rows && other.columns == columns;

  @override
  int get hashCode => Object.hash(rows, columns);

  @override
  String toString() => 'ScrollDelta($rows rows, $columns columns)';
}

/// The policy of a [ScrollBehavior] as a state machine with no clock and no
/// I/O: [event] takes each wheel event with its time, [take] gives the
/// whole rows and columns they come to, once a frame. Each `Scrollable`
/// owns one.
///
/// Nothing moves by itself and nothing is eased: what an event asks for
/// waits for the next [take] whole, and what is under a cell carries on
/// the same way only.
final class ScrollInput {
  /// An input that moves as [behavior] says.
  ScrollInput(this.behavior);

  /// The behaviour, which may change between events.
  ScrollBehavior behavior;

  var _dense = false;

  /// Whether the input has shown itself dense: two pairs of events of one
  /// stream less than [ScrollBehavior.denseGap] apart. For the session.
  bool get isDense => _dense;

  // [vertical, horizontal]
  final _streams = [_Stream(), _Stream()];
  final _pending = [0, 0];
  final _held = [0, 0];

  // the gesture: the time of its last event, events of each axis in it,
  // the axis it is locked to
  Duration? _gestureAt;
  final _counts = [0, 0];
  int? _lock;

  /// Whether whole cells wait for [take].
  bool get hasPending => _pending[0] != 0 || _pending[1] != 0;

  /// Takes a wheel event at [now], [way] -1 (up, left) or 1 (down, right)
  /// along [axis].
  void event(Duration now, Axis axis, int way) {
    assert(way == 1 || way == -1, 'a wheel step is -1 or 1');
    final a = axis == Axis.vertical ? 0 : 1;
    final b = behavior;
    final gestureAt = _gestureAt;
    if (gestureAt == null || now - gestureAt > b.streamGap) {
      _counts[0] = _counts[1] = 0;
      _held[0] = _held[1] = 0;
      _lock = null;
    }
    _gestureAt = now;
    _counts[a]++;

    final s = _streams[a];
    final last = s.at;
    if (last == null || s.way != way || now - last > b.streamGap) {
      // a turn drops what carried; a pause keeps it
      final carry = last != null && s.way == way ? s.carry : 0.0;
      s
        ..n = 0
        ..pairs = 0
        ..carry = carry;
    } else if (now - last < b.denseGap) {
      if (++s.pairs >= 2) {
        _dense = true;
      }
    }
    s
      ..at = now
      ..way = way
      ..n += 1;

    final int whole;
    if (_dense) {
      final factor = math.min(
        b.accelMax,
        math.max(1, 1 + s.n / b.accelEvents),
      );
      final cells = s.carry + b.denseStep * factor;
      whole = cells.floor();
      s.carry = cells - whole;
    } else {
      whole = b.step;
      s.carry = 0;
    }
    final moved = way * whole;

    _lockAfter(a);
    final locked = _lock;
    if (b.axisLock && locked != null && locked != a) {
      _held[a] += moved;
    } else {
      _pending[a] += moved;
    }
  }

  // moves the lock to the axis that leads the gesture by two events; what
  // the axis held, if it overtakes the one locked, is given
  void _lockAfter(int a) {
    if (!behavior.axisLock) {
      return;
    }
    final lead = _counts[a] - _counts[1 - a];
    final locked = _lock;
    if (lead >= 2 && locked != a) {
      _lock = a;
      if (locked != null) {
        _pending[a] += _held[a];
      }
      _held[0] = _held[1] = 0;
    }
  }

  /// The whole cells the events since the last call come to, null for
  /// none.
  ScrollDelta? take() {
    if (!hasPending) {
      return null;
    }
    final delta = ScrollDelta(_pending[0], _pending[1]);
    _pending[0] = _pending[1] = 0;
    return delta;
  }

  /// Drops what waits for [take], the fraction carried and the streams:
  /// something else moved the view, a key, a jump.
  void cancel() {
    _pending[0] = _pending[1] = 0;
    _held[0] = _held[1] = 0;
    for (final s in _streams) {
      s
        ..at = null
        ..carry = 0
        ..n = 0
        ..pairs = 0;
    }
    _gestureAt = null;
    _lock = null;
    _counts[0] = _counts[1] = 0;
  }
}

final class _Stream {
  Duration? at;
  var way = 0;
  var n = 0;
  var pairs = 0;
  var carry = 0.0;
}
