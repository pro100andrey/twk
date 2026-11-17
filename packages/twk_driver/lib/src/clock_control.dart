/// [ClockControl], the driver's hold on a driven app's time
/// (`ext.twk.clock`), and what it answers: [ClockStatus].
library;

import 'app_client.dart' show Json;

/// Where an app's clock stands, as `ext.twk.clock` answers: what
/// `ext.twk.status` carries (the same fields, `twk.frame`'s) and the
/// clock.
final class ClockStatus {
  /// A status from the app's JSON [json].
  ClockStatus(this.json);

  /// What the app answered.
  final Json json;

  /// Whether the app's time is the driver's: false for an app that runs on
  /// real time.
  bool get driven => json['driven']! as bool;

  /// The app's clock in microseconds.
  int get time => json['time']! as int;

  /// How many timers wait, periodic ones included; null where the app is
  /// not driven.
  int? get timers => json['timers'] as int?;

  /// When the next timer is due, in microseconds of the app's clock; null
  /// where none waits, or the app is not driven.
  int? get nextDue => json['nextDue'] as int?;

  /// When the frame that is asked for is due; null where none is.
  int? get frameDue => json['frameDue'] as int?;

  /// Whether a frame is asked for.
  bool get scheduled => json['scheduled']! as bool;

  /// Whether nothing waits for time: no timer, no frame asked for or
  /// running, nothing held in the input parser. Null where the app is not
  /// driven.
  bool? get quiet => json['quiet'] as bool?;

  /// How many frames the app has run.
  int get frame => json['frame']! as int;

  /// The bytes of input the app has taken in.
  int get inputRead => json['inputRead']! as int;

  /// Whether the app's parser holds input back.
  bool get inputPending => json['inputPending']! as bool;

  /// The timers that wait, the next due first, as asked for with
  /// `describe`; empty without it.
  List<TimerInfo> get describe => [
    for (final t in (json['describe'] as List<Object?>? ?? const []))
      TimerInfo(
        due: (t! as Json)['due']! as int,
        periodic: (t as Json)['periodic']! as bool,
        created: t['created'] as String?,
      ),
  ];

  /// The timers that wait, a line each: when it is due, whether it is
  /// periodic and where it was started.
  String describeTimers(int now) => describe.isEmpty
      ? 'no timer waits'
      : describe
            .map(
              (t) =>
                  '${t.periodic ? 'a periodic timer' : 'a timer'} due in '
                  '${((t.due - now) / 1e6).toStringAsFixed(3)} s'
                  '${t.created == null ? '' : ', started at ${t.created}'}',
            )
            .join('\n');
}

/// A timer of an app's clock: [due] in microseconds of that clock, whether
/// it is [periodic], and the line of the code that [created] it, if known.
final class TimerInfo {
  /// A timer.
  const TimerInfo({
    required this.due,
    required this.periodic,
    required this.created,
  });

  /// When it is due.
  final int due;

  /// Whether it repeats.
  final bool periodic;

  /// Where it was started, null where that is not known.
  final String? created;
}

/// The hold a driver has on a driven app's time: [status], and the three
/// moves of `ext.twk.clock`, [advance], [advanceTo] and [next]. Each answers
/// the status the app has once the move is done, that is, once the timers
/// fired have run to their end and the frame that ran, if one did, was
/// written.
final class ClockControl {
  /// A hold that calls the app through `call`: `ext.twk.clock` of the
  /// app, as a session guards it.
  ClockControl(this._call);

  final Future<Json> Function(Map<String, String> params) _call;

  /// Where the app's clock stands; with [describe], the timers that wait.
  Future<ClockStatus> status({bool describe = false}) => _run({
    'op': 'status',
    if (describe) 'describe': 'true',
  });

  /// Moves the clock on by [by], firing each timer as it reaches the time
  /// the timer is due.
  Future<ClockStatus> advance(Duration by) =>
      _run({'op': 'advance', 'by': '${by.inMicroseconds}'});

  /// Moves the clock to [time], in microseconds of the app's clock, firing
  /// each timer as it reaches its time.
  Future<ClockStatus> advanceTo(int time) =>
      _run({'op': 'advanceTo', 'to': '$time'});

  /// Moves the clock to when the next timer is due, firing the timers due
  /// then; stays where it is when none waits.
  Future<ClockStatus> next() => _run({'op': 'next'});

  Future<ClockStatus> _run(Map<String, String> params) async =>
      ClockStatus(await _call(params));
}
