/// The arithmetic of [Steps]: which step a time is in, less those muted for.
///
/// @docImport 'steps.dart';
library;

import 'package:meta/meta.dart';

/// Which step of an interval a time is in, counted from zero, less the
/// steps a mute took: muted, it stays at the step it was in; unmuted, it
/// goes on from that step. Pure: the time is given, never read.
@internal
final class StepCount {
  /// Steps of [interval]; one not longer than zero is an [ArgumentError].
  StepCount(Duration interval) : _interval = interval {
    _check(interval);
  }

  static void _check(Duration interval) {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval', 'a step takes no time');
    }
  }

  Duration _interval;
  var _muted = false;
  var _frozen = 0;
  var _shifted = false;
  var _skipped = 0;
  var _resume = false;

  /// How long a step is.
  Duration get interval => _interval;

  /// Whether it is muted.
  bool get muted => _muted;

  /// The step [now] is in, muted for nothing.
  int live(Duration now) => now.inMicroseconds ~/ _interval.inMicroseconds;

  /// The time the step after the one [now] is in starts at.
  Duration nextAt(Duration now) => _interval * (live(now) + 1);

  /// The step [now] is in: the one it stood at while muted.
  int current(Duration now) {
    if (_muted) {
      return _frozen;
    }
    if (_resume) {
      _resume = false;
      // the steps skipped, as many as the clock has gone on past the step
      // it stood at: counted anew, not added to those of the mutes before
      _skipped = live(now) - _frozen;
    }
    return live(now) - _skipped;
  }

  /// Mutes it at the step [now] is in.
  void mute(Duration now) {
    if (_muted) {
      return;
    }
    _frozen = current(now);
    _shifted = true;
    _resume = false;
    _muted = true;
  }

  /// Unmutes it; the time it was muted for is taken off when [current] is
  /// next read, at the time that counts.
  void unmute() {
    if (!_muted) {
      return;
    }
    _resume = true;
    _muted = false;
  }

  /// Sets the interval, keeping the step [now] is in the one it is in;
  /// returns whether it changed. One not longer than zero is an
  /// [ArgumentError].
  bool setInterval(Duration i, Duration now) {
    _check(i);
    if (i == _interval) {
      return false;
    }
    // the steps muted for are counted in the old interval: counted anew in
    // the new one
    final keep = !_muted && _shifted ? current(now) : null;
    _interval = i;
    if (keep != null) {
      _skipped = live(now) - keep;
    }
    return true;
  }
}
