// Animation controllers on the fake clock: a value each frame from where
// they are to a bound or a target, along a curve, round and round, the
// status as they go; and an app whose controllers stand still asks for no
// frame and starts no timer.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ms = Duration(milliseconds: 1);

/// A controller of [duration], shown as its value.
final class Animated extends StatefulWidget {
  const Animated({
    super.key,
    this.duration = const Duration(milliseconds: 100),
    this.reverseDuration,
  });

  final Duration? duration;
  final Duration? reverseDuration;

  @override
  State<Animated> createState() => AnimatedState();
}

final class AnimatedState extends State<Animated>
    with TickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    reverseDuration: widget.reverseDuration,
  );

  /// Each value and status the listeners got.
  final values = <double>[];
  final statuses = <AnimationStatus>[];

  /// The values as hundredths.
  List<int> get hundredths => [for (final v in values) (v * 100).round()];

  @override
  void initState() {
    super.initState();
    controller
      ..addListener(() => values.add(controller.value))
      ..addStatusListener(statuses.add);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (_, _) => Text(controller.value.toStringAsFixed(2)),
  );
}

/// Starts [Animated] at 100 frames a second: a frame each 10 ms.
Future<AnimatedState> start(
  TwkTester t, {
  Duration duration = const Duration(milliseconds: 100),
  Duration? reverseDuration,
}) async {
  final key = GlobalKey<AnimatedState>();
  await t.pumpWidget(
    Animated(
      key: key,
      duration: duration,
      reverseDuration: reverseDuration,
    ),
    size: (6, 1),
    maxFps: 100,
  );
  return key.currentState!;
}

void main() {
  testTwk('forward runs from the lower bound to the upper one in its '
      'duration, a value each frame, then the app asks for no frame', (
    t,
  ) async {
    final state = await start(t);
    final controller = state.controller;
    expect(
      (controller.value, controller.status),
      (0.0, AnimationStatus.dismissed),
    );
    final written = t.frames.length;
    controller.forward();
    expect(controller.isAnimating, isTrue);
    await t.pump(ms * 95);
    expect(state.hundredths, [10, 20, 30, 40, 50, 60, 70, 80, 90]);
    expect(t.lines, ['0.90']);
    expect(controller.status, AnimationStatus.forward);
    await t.pump(ms * 10);
    expect(state.hundredths.last, 100);
    expect(controller.value, 1);
    expect(state.statuses, [
      AnimationStatus.forward,
      AnimationStatus.completed,
    ]);
    expect(controller.isAnimating, isFalse);
    expect(t.lines, ['1.00']);
    expect(t.frames, hasLength(written + 10));
    expect(t.clock.pendingTimers, 0);
    await t.pumpUntilIdle();
  });

  testTwk('an idle app whose controller was stopped schedules no timer', (
    t,
  ) async {
    final state = await start(t);
    final controller = state.controller..repeat();
    await t.pump(ms * 250);
    expect(t.clock.pendingTimers, 1, reason: 'the next frame');
    controller.stop();
    expect(controller.isAnimating, isFalse);
    await t.pump();
    expect(t.clock.pendingTimers, 0);
    final (written, values) = (t.frames.length, state.values.length);
    await t.pump(const Duration(seconds: 10));
    expect(t.frames, hasLength(written));
    expect(state.values, hasLength(values));
    expect(t.clock.pendingTimers, 0);
  });

  testTwk('reverse runs back in the reverse duration; part of the way '
      'takes that share of it', (t) async {
    final state = await start(
      t,
      reverseDuration: const Duration(milliseconds: 50),
    );
    final controller = state.controller..value = 1;
    expect(controller.status, AnimationStatus.completed);
    controller.reverse();
    await t.pump(ms * 55);
    expect(state.hundredths, [100, 80, 60, 40, 20, 0]);
    expect(state.statuses, [
      AnimationStatus.completed,
      AnimationStatus.reverse,
      AnimationStatus.dismissed,
    ]);
    state.values.clear();
    controller.forward(from: 0.5);
    await t.pump(ms * 55);
    expect(state.hundredths, [50, 60, 70, 80, 90, 100]);
    expect(controller.status, AnimationStatus.completed);
  });

  testTwk('animateTo runs to the target along the curve', (t) async {
    final state = await start(t);
    state.controller.animateTo(
      0.5,
      duration: ms * 40,
      curve: Curves.easeIn,
    );
    await t.pump(ms * 45);
    expect(state.values, [
      for (var i = 1; i <= 4; i++) 0.5 * Curves.easeIn.transform(i / 4),
    ]);
    expect(state.values.last, 0.5);
    expect(state.statuses, [
      AnimationStatus.forward,
      AnimationStatus.completed,
    ]);
  });

  testTwk('repeat starts again from the lower bound each period, or goes '
      'back and forth with reverse, until stopped', (t) async {
    final state = await start(t);
    final controller = state.controller..repeat(period: ms * 40);
    await t.pump(ms * 85);
    expect(state.hundredths, [25, 50, 75, 0, 25, 50, 75, 0]);
    controller.stop();
    expect(controller.status, AnimationStatus.forward);
    state.values.clear();
    controller.repeat(reverse: true, period: ms * 40);
    await t.pump(ms * 105);
    expect(state.hundredths, [25, 50, 75, 100, 75, 50, 25, 0, 25, 50]);
    expect(state.statuses.sublist(1), [
      AnimationStatus.reverse,
      AnimationStatus.forward,
    ]);
    expect(controller.isAnimating, isTrue);
  });

  testTwk('setting the value stops the run there, clamped to the bounds; '
      'a run with no duration is a StateError', (t) async {
    final state = await start(t);
    final controller = state.controller..forward();
    await t.pump(ms * 35);
    controller.value = 0.25;
    expect(controller.isAnimating, isFalse);
    expect(controller.status, AnimationStatus.forward);
    await t.pump(ms * 50);
    expect(controller.value, 0.25);
    expect(t.lines, ['0.25']);
    controller.value = 7;
    expect(
      (controller.value, controller.status),
      (1.0, AnimationStatus.completed),
    );
    controller.value = -3;
    expect(
      (controller.value, controller.status),
      (0.0, AnimationStatus.dismissed),
    );
    controller
      ..value = 0.5
      ..reset();
    expect(
      (controller.value, controller.status),
      (0.0, AnimationStatus.dismissed),
    );
    controller.duration = null;
    expect(controller.forward, throwsStateError);
    expect(controller.repeat, throwsStateError);
  });

  testTwk('a controller disposed with its state mid-run asks for no frame', (
    t,
  ) async {
    final state = await start(t);
    state.controller.forward();
    await t.pump(ms * 30);
    await t.pumpWidget(const Text('gone'));
    await t.pump();
    expect(t.clock.pendingTimers, 0);
  });

  testTwk('reverse from a value runs back from there in the share of the '
      'duration the way is', (t) async {
    final state = await start(t);
    state.controller.reverse(from: 0.5);
    expect(state.statuses, [AnimationStatus.forward, AnimationStatus.reverse]);
    await t.pump(ms * 55);
    expect(state.hundredths, [50, 40, 30, 20, 10, 0]);
    expect(state.statuses.last, AnimationStatus.dismissed);
  });

  testTwk('animateTo without a duration takes the share of the '
      "controller's the way is of the bounds'", (t) async {
    final state = await start(t);
    state.controller.animateTo(0.3);
    await t.pump(ms * 35);
    expect(state.hundredths, [10, 20, 30]);
    expect(state.controller.status, AnimationStatus.completed);
  });

  testTwk('a run to where the controller is ends at once, in the status of '
      'its end, and asks for no frame', (t) async {
    final state = await start(t);
    final controller = state.controller..value = 1;
    state.statuses.clear();
    final written = t.frames.length;
    controller.forward();
    expect(controller.isAnimating, isFalse);
    expect(state.statuses, isEmpty, reason: 'completed already');
    controller.animateTo(0.5, duration: Duration.zero);
    expect(controller.isAnimating, isFalse);
    expect(controller.value, 0.5);
    expect(
      controller.status,
      AnimationStatus.completed,
      reason: 'as a run forward ends',
    );
    await t.pump(ms * 50);
    expect(t.frames, hasLength(written + 1), reason: 'the value it is at');
    expect(t.lines, ['0.50']);
  });

  testTwk('a status listener removed is called no more', (t) async {
    final state = await start(t);
    final controller = state.controller;
    final heard = <AnimationStatus>[];
    void listener(AnimationStatus status) => heard.add(status);
    controller
      ..addStatusListener(listener)
      ..value = 1
      ..removeStatusListener(listener)
      ..value = 0;
    expect(heard, [AnimationStatus.completed]);
    expect(state.statuses, [
      AnimationStatus.completed,
      AnimationStatus.dismissed,
    ]);
  });

  test('a NaN, set or a target, is an ArgumentError', () {
    final controller = AnimationController(vsync: _NoTicks());
    expect(() => controller.value = double.nan, throwsArgumentError);
    expect(() => controller.animateTo(double.nan), throwsArgumentError);
    expect(controller.value, 0);
  });

  test('a status listener that throws is reported to the zone, and the '
      'others are called all the same', () {
    final errors = <Object>[];
    final heard = <AnimationStatus>[];
    runZonedGuarded(() {
      AnimationController(vsync: _NoTicks())
        ..addStatusListener((_) => throw StateError('listener'))
        ..addStatusListener(heard.add)
        ..value = 1;
    }, (error, _) => errors.add(error));
    expect(errors, [isStateError]);
    expect(heard, [AnimationStatus.completed]);
  });
}

/// Makes tickers outside any app, which never tick.
final class _NoTicks implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}
