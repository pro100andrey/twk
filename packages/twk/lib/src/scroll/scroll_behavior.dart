/// How the wheel scrolls: [ScrollBehavior], and [ScrollConfiguration],
/// which gives it to the scrollables below.
library;

import 'package:meta/meta.dart';

import '../framework/framework.dart';

/// How a wheel event becomes cells scrolled, the same for every scrollable
/// under a [ScrollConfiguration]: the input's policy, as `ScrollPhysics` is
/// the bounds'.
///
/// A terminal reports a wheel and a trackpad alike, one event for each
/// unit it counted, and the units differ by terminal and device: a notch
/// of a mouse wheel is 1 event in one terminal and 9 in another, a
/// trackpad is a burst of events a display refresh. So a scrollable
/// moving a fixed step an event moves a different distance on each. The
/// behaviour tells the two kinds of input apart by the input's own
/// timing, never by the terminal's name:
///
///  * **Dense** input is events of one stream (one axis, one way) less
///    than [denseGap] apart: no hand makes two separate motions that
///    close. Twice in a stream, and it is dense for the session. It moves
///    [denseStep] cells an event, the `n`-th of a stream
///    `1 + n / accelEvents` times that, up to [accelMax].
///  * **Sparse** input, until then and always where events come one at a
///    time, moves [step] cells an event.
///
/// So a mouse wheel is dense too where a terminal sends a notch as a burst,
/// and a notch then moves as many cells as it has events, where a fixed
/// step would move several times that. Timing is no sure way to tell a
/// wheel from a trackpad: [ScrollBehavior.fixed] is a plain step an event,
/// for a terminal it tells wrongly.
///
/// A stream ends after [streamGap] without an event, or at a turn, which
/// moves at once. What is under a whole cell carries on to the next
/// stream the same way only. The events of a frame are one move, applied
/// at the frame (`ScrollInput`). With [axisLock] a gesture that goes along
/// one axis leaves out the sideways events a trackpad adds to it.
///
/// [ScrollBehavior.new] is the default; [ScrollConfiguration] or
/// `App.scrollBehavior` gives another:
///
/// ```dart
/// const App(
///   scrollBehavior: ScrollBehavior(step: 2),
///   child: Text('home'),
/// )
/// ```
@immutable
final class ScrollBehavior {
  /// The default: [step] 3, [denseStep] 1, the acceleration of 30 events
  /// up to 3, dense under 2 ms, a stream ending after 80 ms, the axis
  /// locked.
  const ScrollBehavior({
    this.step = 3,
    this.denseStep = 1,
    this.accelEvents = 30,
    this.accelMax = 3,
    this.denseGap = const Duration(milliseconds: 2),
    this.streamGap = const Duration(milliseconds: 80),
    this.axisLock = true,
  }) : assert(step >= 0, 'a step of 0 or more'),
       assert(denseStep >= 0, 'a step of 0 or more'),
       assert(accelEvents > 0, 'an acceleration of 1 event or more'),
       assert(accelMax >= 1, 'a factor of 1 or more');

  /// Every event moves [step] cells, however dense the input: what a
  /// scrollable did before the behaviour measured it.
  const ScrollBehavior.fixed(int step)
    : this(step: step, denseStep: step + 0.0, accelMax: 1);

  /// The cells an event of sparse input moves.
  final int step;

  /// The cells an event of dense input moves before the acceleration.
  final double denseStep;

  /// The events of a dense stream after which an event moves twice
  /// [denseStep]: its `n`-th moves `1 + n / accelEvents` times.
  final int accelEvents;

  /// The most times [denseStep] an event of a dense stream moves; 1 is no
  /// acceleration.
  final double accelMax;

  /// Events of a stream closer than this are dense.
  final Duration denseGap;

  /// A stream, and a gesture, end after this long without an event.
  final Duration streamGap;

  /// Whether the sideways events of a gesture along one axis are left
  /// out.
  final bool axisLock;

  /// This with the fields given changed.
  ScrollBehavior copyWith({
    int? step,
    double? denseStep,
    int? accelEvents,
    double? accelMax,
    Duration? denseGap,
    Duration? streamGap,
    bool? axisLock,
  }) => ScrollBehavior(
    step: step ?? this.step,
    denseStep: denseStep ?? this.denseStep,
    accelEvents: accelEvents ?? this.accelEvents,
    accelMax: accelMax ?? this.accelMax,
    denseGap: denseGap ?? this.denseGap,
    streamGap: streamGap ?? this.streamGap,
    axisLock: axisLock ?? this.axisLock,
  );

  @override
  bool operator ==(Object other) =>
      other is ScrollBehavior &&
      other.step == step &&
      other.denseStep == denseStep &&
      other.accelEvents == accelEvents &&
      other.accelMax == accelMax &&
      other.denseGap == denseGap &&
      other.streamGap == streamGap &&
      other.axisLock == axisLock;

  @override
  int get hashCode => Object.hash(
    step,
    denseStep,
    accelEvents,
    accelMax,
    denseGap,
    streamGap,
    axisLock,
  );

  @override
  String toString() =>
      'ScrollBehavior(step $step, denseStep $denseStep, accel '
      '$accelEvents events up to $accelMax, dense under '
      '${denseGap.inMicroseconds / 1000} ms, stream ends after '
      '${streamGap.inMilliseconds} ms, axisLock $axisLock)';
}

/// Gives the [ScrollBehavior] of the scrollables below it, as Flutter's
/// `ScrollConfiguration` does: what a subtree scrolls like is its own,
/// the app's `App.scrollBehavior` above it.
///
/// ```dart
/// ScrollConfiguration(
///   behavior: const ScrollBehavior.fixed(1),
///   child: ListView(children: const [Text('a'), Text('b')]),
/// )
/// ```
final class ScrollConfiguration extends InheritedWidget {
  /// [behavior] for what is below [child].
  const ScrollConfiguration({
    required this.behavior,
    required super.child,
    super.key,
  });

  /// What the scrollables below scroll like.
  final ScrollBehavior behavior;

  /// The behaviour of the nearest [ScrollConfiguration] above [context],
  /// the default [ScrollBehavior] where there is none; [context] depends
  /// on it.
  static ScrollBehavior of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ScrollConfiguration>()
          ?.behavior ??
      const ScrollBehavior();

  @override
  bool updateShouldNotify(ScrollConfiguration oldWidget) =>
      behavior != oldWidget.behavior;
}
