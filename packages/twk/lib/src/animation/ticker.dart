/// Calls once a frame: [Ticker], and the [TickerProvider] a [State] with
/// [TickerProviderStateMixin] is.
///
/// @docImport 'animation_controller.dart';
library;

import 'package:meta/meta.dart';

import '../binding/app_binding.dart';
import '../framework/framework.dart';

// Examples can assume:
// abstract class Blink extends StatefulWidget {
//   const Blink({super.key});
// }

/// What a [Ticker] calls each frame: [elapsed] is the time since its first
/// tick.
typedef TickerCallback = void Function(Duration elapsed);

/// Calls [onTick] once a frame while it is active, from [start] to [stop],
/// with the time since its first tick: zero at the first, then the time of
/// each frame on the app's clock ([AppBinding.frameTime]) less that of the
/// first.
///
/// The ticks are [binding]'s frame callbacks
/// ([AppBinding.scheduleFrameCallback]): each asks for the next frame, so
/// an active ticker has the app run frames, at most `maxFps` a second,
/// and all the tickers of an app tick in the same frames; a stopped one
/// asks for none, and starts no timer. Without a binding (a tree outside
/// any app) it never ticks.
///
/// A widget's tickers come from its state's [TickerProviderStateMixin]
/// ([TickerProvider.createTicker]), which gives them the app's binding and
/// disposes of them with the state; an [AnimationController] is the usual
/// way to use one. A ticker that counts the time a state has been shown:
///
/// ```dart
/// final class Uptime extends StatefulWidget {
///   const Uptime({super.key});
///
///   @override
///   State<Uptime> createState() => _UptimeState();
/// }
///
/// final class _UptimeState extends State<Uptime>
///     with TickerProviderStateMixin {
///   var shown = Duration.zero;
///   late final ticker = createTicker((elapsed) {
///     setState(() => shown = elapsed);
///   })..start();
///
///   @override
///   Widget build(BuildContext context) => Text('${shown.inSeconds} s');
/// }
/// ```
final class Ticker {
  /// A ticker that calls [onTick] in the frames of [binding]'s app, not
  /// started; without a binding, one that never ticks.
  Ticker(this.onTick, {this.binding});

  /// What it calls each frame while active, with the time since its first
  /// tick.
  final TickerCallback onTick;

  /// The app whose frames it ticks in.
  final AppBinding? binding;

  // the frame callback of the next tick; the time of the first tick
  int? _callback;
  Duration? _startedAt;
  var _active = false;
  var _disposed = false;

  late final FrameCallback _tickCallback = _tick;

  /// Whether it ticks: [start]ed and not stopped since.
  bool get isActive => _active;

  /// Ticks from the next frame on; a [StateError] if it is active.
  void start() {
    assert(!_disposed, '$this started after dispose()');
    if (_active) {
      throw StateError('the ticker is active already');
    }
    _active = true;
    _startedAt = null;
    _schedule();
  }

  /// Ticks no more until [start]ed again.
  void stop() {
    _active = false;
    final callback = _callback;
    if (callback != null) {
      _callback = null;
      binding?.cancelFrameCallback(callback);
    }
  }

  /// Stops it for good; one disposed already is left as it is.
  void dispose() {
    stop();
    _disposed = true;
  }

  void _schedule() {
    _callback = binding?.scheduleFrameCallback(_tickCallback);
  }

  void _tick(Duration time) {
    _callback = null;
    final startedAt = _startedAt ??= time;
    onTick(time - startedAt);
    // onTick may have stopped it, or started it again
    if (_active && _callback == null) {
      _schedule();
    }
  }
}

/// What makes the [Ticker]s of an object's animations, such as a [State]
/// with [TickerProviderStateMixin].
abstract interface class TickerProvider {
  /// A ticker that calls [onTick], not started.
  Ticker createTicker(TickerCallback onTick);
}

/// Makes a [State] a [TickerProvider]: its tickers tick in the frames of
/// the app it is in ([AppBinding.maybeOf]), and are disposed with it.
///
/// The state is the `vsync` of its controllers, which it disposes itself:
///
/// ```dart
/// final class _BlinkState extends State<Blink>
///     with TickerProviderStateMixin {
///   late final controller = AnimationController(
///     vsync: this,
///     duration: const Duration(seconds: 1),
///   )..repeat();
///
///   @override
///   void dispose() {
///     controller.dispose();
///     super.dispose();
///   }
///
///   @override
///   Widget build(BuildContext context) => AnimatedBuilder(
///     animation: controller,
///     builder: (context, _) => Text(controller.value < 0.5 ? '█' : ' '),
///   );
/// }
/// ```
mixin TickerProviderStateMixin<T extends StatefulWidget> on State<T>
    implements TickerProvider {
  List<Ticker>? _tickers;

  @override
  Ticker createTicker(TickerCallback onTick) {
    final ticker = Ticker(onTick, binding: AppBinding.maybeOf(context));
    (_tickers ??= []).add(ticker);
    return ticker;
  }

  @override
  @protected
  @mustCallSuper
  void dispose() {
    final tickers = _tickers;
    if (tickers != null) {
      for (final ticker in tickers) {
        ticker.dispose();
      }
    }
    super.dispose();
  }
}
