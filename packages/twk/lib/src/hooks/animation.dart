/// The hooks of animations and time: [useAnimationController], [useTicker]
/// and [useInterval], ticking in the frames of the app the widget is in.
library;

import '../../twk.dart';
import '../animation/steps.dart';

import 'hook.dart';

/// An [AnimationController] made by the first build, made anew when the
/// [keys] of a build differ from the last one's, and disposed with the
/// element or when replaced. Its ticker is the hook's own, ticking in the
/// frames of the app the widget is in, unless [vsync] gives one. That ticker
/// is muted ([Ticker.muted]) while a [TickerMode] above is off, so that the
/// controller stands still and asks for no frame, and goes on when it is on
/// again, its time having gone on meanwhile: it is where it would have
/// been. A [vsync] is muted by its own owner.
///
/// Each build sets the controller's [duration] and [reverseDuration];
/// [initialValue], the bounds and [vsync] are those of the build that made
/// it.
///
/// A bar that grows over a second from the first build:
///
/// ```dart
/// HookBuilder(
///   builder: (context) {
///     final controller = useAnimationController(
///       duration: const Duration(seconds: 1),
///     );
///     useEffect(() {
///       controller.forward();
///       return null;
///     }, const []);
///     final value = useListenable(controller).value;
///     return Text('█' * (value * 20).round());
///   },
/// )
/// ```
AnimationController useAnimationController({
  Duration? duration,
  Duration? reverseDuration,
  double? initialValue,
  double lowerBound = 0,
  double upperBound = 1,
  TickerProvider? vsync,
  List<Object?>? keys,
}) => use(
  _AnimationControllerHook(
    duration: duration,
    reverseDuration: reverseDuration,
    initialValue: initialValue,
    lowerBound: lowerBound,
    upperBound: upperBound,
    vsync: vsync,
    keys: keys,
  ),
);

final class _AnimationControllerHook extends Hook<AnimationController> {
  const _AnimationControllerHook({
    required this.duration,
    required this.reverseDuration,
    required this.initialValue,
    required this.lowerBound,
    required this.upperBound,
    required this.vsync,
    required super.keys,
  });

  final Duration? duration;
  final Duration? reverseDuration;
  final double? initialValue;
  final double lowerBound;
  final double upperBound;
  final TickerProvider? vsync;

  @override
  String get debugLabel => 'useAnimationController';

  @override
  _AnimationControllerHookState createState() =>
      _AnimationControllerHookState();
}

final class _AnimationControllerHookState
    extends HookState<AnimationController, _AnimationControllerHook>
    implements TickerProvider {
  late final AnimationController _controller;
  Ticker? _ticker;

  @override
  void initHook() {
    super.initHook();
    _controller = AnimationController(
      vsync: hook.vsync ?? this,
      value: hook.initialValue,
      duration: hook.duration,
      reverseDuration: hook.reverseDuration,
      lowerBound: hook.lowerBound,
      upperBound: hook.upperBound,
    );
  }

  @override
  Ticker createTicker(TickerCallback onTick) =>
      _ticker = Ticker(onTick, binding: AppBinding.maybeOf(context))
        ..muted = !TickerMode.of(context);

  @override
  void didUpdateHook(_AnimationControllerHook oldHook) {
    super.didUpdateHook(oldHook);
    _controller
      ..duration = hook.duration
      ..reverseDuration = hook.reverseDuration;
  }

  @override
  AnimationController build(BuildContext context) {
    // The dependency on TickerMode is what has the element build again, and
    // so this, when it changes. A hook state has no didChangeDependencies.
    final ticker = _ticker;
    if (ticker != null) {
      ticker.muted = !TickerMode.of(context);
    }
    return _controller;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(hook.debugLabel, _controller.value);
  }
}

/// A [Ticker] made by the first build, not started, that calls the
/// [onTick] of the latest build once a frame while it is active, in the
/// frames of the app the widget is in; disposed with the element. It is
/// muted ([Ticker.muted]) while a [TickerMode] above is off, its time going
/// on.
///
/// A clock of the time since its ticker started:
///
/// ```dart
/// HookBuilder(
///   builder: (context) {
///     final elapsed = useState(Duration.zero);
///     final ticker = useTicker((time) => elapsed.value = time);
///     useEffect(() {
///       ticker.start();
///       return null;
///     }, const []);
///     return Text('${elapsed.value.inSeconds} s');
///   },
/// )
/// ```
Ticker useTicker(TickerCallback onTick) => use(_TickerHook(onTick));

final class _TickerHook extends Hook<Ticker> {
  const _TickerHook(this.onTick);

  final TickerCallback onTick;

  @override
  String get debugLabel => 'useTicker';

  @override
  _TickerHookState createState() => _TickerHookState();
}

final class _TickerHookState extends HookState<Ticker, _TickerHook> {
  late final Ticker _ticker;

  @override
  void initHook() {
    super.initHook();
    _ticker = Ticker(_tick, binding: AppBinding.maybeOf(context));
  }

  void _tick(Duration elapsed) => hook.onTick(elapsed);

  @override
  // The dependency on TickerMode has the element build again when it
  // changes, as in _AnimationControllerHookState.build.
  Ticker build(BuildContext context) =>
      _ticker..muted = !TickerMode.of(context);

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

/// Calls [onTick] of the latest build once every [period], from the first
/// build on, on the clock of the app the widget is in, until the element is
/// disposed. The ticks are [Steps] of the app's clock: they fall in the
/// frames at the multiples of [period] since the app started, so the first
/// comes within one [period] of the build, not after a whole one, and all
/// that step by the same period tick in the same frame. A tick is called in
/// a frame, where a `setState` is as usual.
///
/// Muted while a [TickerMode] above is off, as [useTicker] is: no tick and
/// no frame asked for, and none made up for when it is on again. A changed
/// [period] restarts it at the next multiple of the new one; a [period] not
/// longer than zero is an [ArgumentError]. Outside an app it never ticks.
///
/// A clock of the seconds, redrawn once each:
///
/// ```dart
/// HookBuilder(
///   builder: (context) {
///     final seconds = useState(0);
///     useInterval(
///       const Duration(seconds: 1),
///       () => seconds.value++,
///     );
///     return Text('${seconds.value} s');
///   },
/// )
/// ```
void useInterval(Duration period, void Function() onTick) =>
    use(_IntervalHook(period, onTick));

final class _IntervalHook extends Hook<void> {
  const _IntervalHook(this.period, this.onTick);

  final Duration period;
  final void Function() onTick;

  @override
  String get debugLabel => 'useInterval';

  @override
  _IntervalHookState createState() => _IntervalHookState();
}

final class _IntervalHookState extends HookState<void, _IntervalHook> {
  late final Steps _steps;

  @override
  void initHook() {
    super.initHook();
    _steps = Steps(
      hook.period,
      _tick,
      binding: AppBinding.maybeOf(context),
    )..start();
  }

  void _tick() => hook.onTick();

  @override
  void didUpdateHook(_IntervalHook oldHook) {
    super.didUpdateHook(oldHook);
    _steps.interval = hook.period;
  }

  @override
  // The dependency on TickerMode has the element build again when it
  // changes, as in _AnimationControllerHookState.build.
  void build(BuildContext context) {
    _steps.muted = !TickerMode.of(context);
  }

  @override
  void dispose() {
    _steps.stop();
    super.dispose();
  }
}
