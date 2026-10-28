/// The hooks of animations: [useAnimationController] and [useTicker],
/// ticking in the frames of the app the widget is in.
library;

import '../../twk.dart';

import 'hook.dart';

/// An [AnimationController] made by the first build, made anew when the
/// [keys] of a build differ from the last one's, and disposed with the
/// element or when replaced. Its ticker is the hook's own, ticking in the
/// frames of the app the widget is in, unless [vsync] gives one.
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
      Ticker(onTick, binding: AppBinding.maybeOf(context));

  @override
  void didUpdateHook(_AnimationControllerHook oldHook) {
    super.didUpdateHook(oldHook);
    _controller
      ..duration = hook.duration
      ..reverseDuration = hook.reverseDuration;
  }

  @override
  AnimationController build(BuildContext context) => _controller;

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
/// frames of the app the widget is in; disposed with the element.
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
  Ticker build(BuildContext context) => _ticker;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
