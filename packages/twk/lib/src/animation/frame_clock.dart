/// What [Ticker] and [Steps] ask for frames of: a [FrameClock].
///
/// @docImport 'steps.dart';
/// @docImport 'ticker.dart';
library;

import 'package:meta/meta.dart';

import '../binding/app_binding.dart';

/// The app's clock as the animations use it: the time of the frame, and
/// frame callbacks for the next frame or for a time. [AppBinding] is the
/// one in an app; a test without an app gives a fake.
@internal
abstract interface class FrameClock {
  /// The time of the frame running, or of the last one between frames.
  Duration get frameTime;

  /// Calls [callback] once at the start of a frame, the next one or, with
  /// [at], the first at or after that time; returns the id
  /// [cancelFrameCallback] takes.
  int scheduleFrameCallback(FrameCallback callback, {Duration? at});

  /// Calls the callback [id] names at no frame.
  void cancelFrameCallback(int id);
}
