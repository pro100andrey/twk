// FrameClock is twk's own, internal, and no more public than this fake of it
// is meant to be: the one place a test package implements it.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'package:twk/src/animation/frame_clock.dart';
import 'package:twk/src/binding/app_binding.dart' show FrameCallback;

/// A [FrameClock] without an app, for what steps by frames alone: [advance]
/// moves its time and calls the frame callbacks due, as the app's frame
/// does.
final class FakeFrameClock implements FrameClock {
  Duration _time = Duration.zero;
  var _last = 0;
  final _waiting = <int, (FrameCallback, Duration?)>{};

  @override
  Duration get frameTime => _time;

  /// How many callbacks wait.
  int get pending => _waiting.length;

  @override
  int scheduleFrameCallback(FrameCallback callback, {Duration? at}) {
    _waiting[++_last] = (callback, at);
    return _last;
  }

  @override
  void cancelFrameCallback(int id) => _waiting.remove(id);

  /// Moves the time to [to] (one frame) and calls the callbacks due at it
  /// that were waiting before; those they schedule wait for the next.
  void advance(Duration to) {
    _time = to;
    final due = [
      for (final e in _waiting.entries)
        if (e.value.$2 == null || e.value.$2! <= to) e.key,
    ];
    for (final id in due) {
      _waiting.remove(id)?.$1(to);
    }
  }
}
