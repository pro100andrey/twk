/// Calls once a frame: [Ticker], and the [TickerProvider] a [State] with
/// [TickerProviderStateMixin] is.
///
/// @docImport 'animation_controller.dart';
library;

import 'package:meta/meta.dart';

import '../binding/app_binding.dart';
import '../framework/framework.dart';
import 'frame_clock.dart';
import 'mute.dart';

// Examples can assume:
// import 'dart:async';
// abstract class Poll extends StatefulWidget {
//   const Poll({super.key});
// }
// void refresh() {}
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
final class Ticker implements Muteable {
  /// A ticker that calls [onTick] in the frames of [binding]'s app, not
  /// started; without a binding, one that never ticks. `onDispose` is
  /// called with it once, when it is disposed.
  Ticker(this.onTick, {this.binding, this._onDispose});

  /// What it calls each frame while active, with the time since its first
  /// tick.
  final TickerCallback onTick;

  /// The clock whose frames it ticks in: an app's [AppBinding].
  final FrameClock? binding;

  final void Function(Ticker)? _onDispose;

  // the frame callback of the next tick; the time of the first tick
  int? _callback;
  Duration? _startedAt;
  var _active = false;
  var _disposed = false;
  var _muted = false;

  late final FrameCallback _tickCallback = _tick;

  /// Whether it ticks: [start]ed and not stopped since.
  bool get isActive => _active;

  /// Whether it is kept from ticking while active: it asks for no frame
  /// and calls nothing, its time going on; unmuted, it ticks from the next
  /// frame. A [TickerProviderStateMixin] sets it from [TickerMode].
  @override
  bool get muted => _muted;
  @override
  set muted(bool on) {
    if (on == _muted) {
      return;
    }
    _muted = on;
    if (on) {
      final callback = _callback;
      if (callback != null) {
        _callback = null;
        binding?.cancelFrameCallback(callback);
      }
    } else if (_active && !_disposed && _callback == null) {
      _schedule();
    }
  }

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
    if (!_disposed) {
      _disposed = true;
      _onDispose?.call(this);
    }
  }

  void _schedule() {
    if (_muted) {
      return;
    }
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

/// Whether the [Ticker]s below tick: `Offstage` and `Visibility` turn them
/// off for what they hide, so that what is not shown asks for no frames.
///
/// A [TickerProviderStateMixin] mutes its tickers ([Ticker.muted]) while
/// the mode is off, and unmutes them when it is on again; their time goes
/// on meanwhile. A state's own timer asks the same through [of]:
///
/// ```dart
/// final class _PollState extends State<Poll> {
///   Timer? timer;
///
///   @override
///   Widget build(BuildContext context) => const Text('polling');
///
///   @override
///   void didChangeDependencies() {
///     super.didChangeDependencies();
///     timer?.cancel();
///     timer = TickerMode.of(context)
///         ? Timer.periodic(const Duration(seconds: 1), (_) => refresh())
///         : null;
///   }
/// }
/// ```
final class TickerMode extends InheritedWidget {
  /// Turns the tickers below on or off with [enabled].
  const TickerMode({required this.enabled, required super.child, super.key});

  /// Whether the tickers below tick.
  final bool enabled;

  /// Whether the tickers at [context] tick: the mode of the nearest
  /// [TickerMode] above it, true where there is none. The caller is told
  /// ([State.didChangeDependencies]) when it changes.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TickerMode>()?.enabled ?? true;

  @override
  bool updateShouldNotify(TickerMode oldWidget) => enabled != oldWidget.enabled;
}

/// What makes the [Ticker]s of an object's animations, such as a [State]
/// with [TickerProviderStateMixin].
abstract interface class TickerProvider {
  /// A ticker that calls [onTick], not started.
  Ticker createTicker(TickerCallback onTick);
}

/// A ticker of the state at [context], added to [tickers].
Ticker _newTicker(
  MuteGroup<Ticker> tickers,
  BuildContext context,
  TickerCallback onTick,
) {
  // read without a dependency: a state may create a ticker in initState, and
  // didChangeDependencies, called after it, depends and is told
  final mode = context.getInheritedWidgetOfExactType<TickerMode>();
  return tickers.add(
    Ticker(
      onTick,
      binding: AppBinding.maybeOf(context),
      onDispose: tickers.remove,
    )..muted = !(mode?.enabled ?? true),
  );
}

/// Disposes every ticker of [tickers], which each takes out of it.
void _disposeTickers(MuteGroup<Ticker> tickers) {
  for (final ticker in [...tickers.items]) {
    ticker.dispose();
  }
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
  final _tickers = MuteGroup<Ticker>();

  @override
  Ticker createTicker(TickerCallback onTick) =>
      _newTicker(_tickers, context, onTick);

  @override
  @protected
  @mustCallSuper
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickers.sync(context);
  }

  @override
  @protected
  @mustCallSuper
  void dispose() {
    _disposeTickers(_tickers);
    super.dispose();
  }
}

/// A [TickerProviderStateMixin] for a state with one ticker, which is what
/// one [AnimationController] needs: [createTicker] a second time, while the
/// first is not disposed, is an assertion failure; once it is disposed, a
/// new one may be made.
///
/// ```dart
/// final class _OnceState extends State<Blink>
///     with SingleTickerProviderStateMixin {
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
///   Widget build(BuildContext context) =>
///       Text(controller.value < 0.5 ? '█' : ' ');
/// }
/// ```
mixin SingleTickerProviderStateMixin<T extends StatefulWidget> on State<T>
    implements TickerProvider {
  final _tickers = MuteGroup<Ticker>();

  @override
  Ticker createTicker(TickerCallback onTick) {
    assert(
      _tickers.items.isEmpty,
      '$runtimeType is a SingleTickerProviderStateMixin but creates more '
      'than one Ticker: use TickerProviderStateMixin.',
    );
    return _newTicker(_tickers, context, onTick);
  }

  @override
  @protected
  @mustCallSuper
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickers.sync(context);
  }

  @override
  @protected
  @mustCallSuper
  void dispose() {
    _disposeTickers(_tickers);
    super.dispose();
  }
}
