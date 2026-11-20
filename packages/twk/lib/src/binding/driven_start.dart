/// `TWK_DRIVEN`: a process that a driver (`twk_driver`) starts and moves the
/// time of.
library;

import 'dart:async';
import 'dart:developer' as developer;

import '../foundation/constants.dart' show kReleaseMode;
import '../platform/platform.dart' as platform;
import 'driven_clock.dart';

/// The name of the variable the driver starts the app with.
const drivenVariable = 'TWK_DRIVEN';

/// What a process that is driven runs on: the [clock] that only the driver
/// moves, the [startTime] it gave (or the real time at start), and the
/// [zone] the binding and the app run in, whose timers go to [clock].
///
/// Made by [DrivenStart.of], which `runApp` and the `Cli`'s system terminal
/// call when they are given no clock. The binding never reads the
/// variable, and nothing carries the clock in a zone value: whoever made
/// the start passes [clock] on.
final class DrivenStart {
  DrivenStart._(this.clock, this.startTime, this.outer)
    : zone = outer.fork(
        specification: ZoneSpecification(
          createTimer: (self, parent, zone, after, callback) =>
              clock.timer(after, zone.bindCallbackGuarded(callback)),
          createPeriodicTimer: (self, parent, zone, every, callback) =>
              clock.periodic(every, zone.bindUnaryCallbackGuarded(callback)),
        ),
      );

  /// The clock, a [DrivenClock] that wakes itself for what is due now.
  final DrivenClock clock;

  /// What `AppBinding.now` reads when the clock reads zero.
  final DateTime startTime;

  /// The zone the start was made in, before [zone]: real time, where the
  /// terminal opens and what is I/O runs.
  final Zone outer;

  /// A zone forked from [outer] whose `createTimer` and
  /// `createPeriodicTimer` go to [clock]: a raw `Timer` or `Future.delayed`
  /// in the app's own code is driven too. The callbacks run in the zone that
  /// made the timer, an error of one going to that zone's handler.
  final Zone zone;

  /// The start the variable [drivenVariable] of [environment] (the
  /// process's by default) asks for, or null where it asks for none: it is
  /// not set, the process runs in [product] mode (which ignores it), or
  /// the parent of the process is not the driver it names.
  ///
  /// The value is `<pid>` or `<pid>@<ISO-8601 instant>`: `<pid>` is the
  /// driving process, taken only when it is [parentPid], the id of the
  /// parent of this process (`getppid`), so that what the app starts (a
  /// nested twk app, `twk run`, a shell in a `TerminalView`), which
  /// inherits the variable, runs on real time and does not wait for a
  /// driver that is not its parent. The instant is [startTime]; without
  /// one, it is the real time now. A value that names the parent and is not
  /// of that form is a [FormatException].
  static DrivenStart? of({
    Map<String, String>? environment,
    int? parentPid,
    bool product = kReleaseMode,
  }) {
    if (product) {
      return null;
    }
    final value = (environment ?? platform.environment)[drivenVariable];
    if (value == null || value.isEmpty) {
      return null;
    }
    final at = value.indexOf('@');
    final named = int.tryParse(at < 0 ? value : value.substring(0, at));
    if (named == null) {
      throw FormatException(
        '$drivenVariable is <pid> or <pid>@<ISO-8601 instant>',
        value,
      );
    }
    if (named != (parentPid ?? platform.parentProcessId)) {
      return null;
    }
    final DateTime start;
    if (at < 0) {
      start = DateTime.now();
    } else {
      final instant = DateTime.tryParse(value.substring(at + 1));
      if (instant == null) {
        throw FormatException(
          '$drivenVariable is <pid> or <pid>@<ISO-8601 instant>',
          value,
        );
      }
      start = instant;
    }
    return DrivenStart._(DrivenClock(recordStacks: true), start, Zone.current);
  }

  /// Completes where a VM service runs and throws a [StateError] where
  /// none does: nothing could move the clock of a driven app, which would
  /// wait for ever.
  static Future<void> requireService() async {
    if ((await developer.Service.getInfo()).serverUri == null) {
      throw StateError(
        '$drivenVariable asks for a driven app, which only a driver '
        'through the VM service can move: run it with the VM service on '
        '(`dart run` does, `dart compile exe` has none)',
      );
    }
  }
}
