// What builds on the gallery's clock, so that a route's `t=` stills it:
// a builder, a State, and where a cycle stands.
import 'package:twk/twk.dart';

import '../../motion.dart';
import 'kept.dart';
import 'lit.dart';
import 'motion_state.dart';

/// Builds [builder] with the gallery's time in milliseconds, again at each
/// time it asks for with `wake`: what the Code's timers move, on the
/// gallery's clock, so that a route's `t=` stills it.
final class Timed extends StatefulWidget {
  const Timed(this.builder);

  final Widget Function(BuildContext context, int ms, void Function(int) wake)
  builder;

  @override
  State<Timed> createState() => _TimedBuilds();
}

final class _TimedBuilds extends State<Timed> with MotionState {
  @override
  Widget build(BuildContext context) {
    motion.begin(context);
    final built = widget.builder(
      context,
      motion.now.inMilliseconds,
      (at) => motion.wakeAt(Duration(milliseconds: at)),
    );
    motion.end();
    return built;
  }
}

/// A State that builds with a [Motion] begun on the gallery's clock, and
/// the page's kept state.
abstract base class TimedState<W extends StatefulWidget> extends State<W>
    with KeptState<W>, MotionState<W> {
  /// The time of this build, in ms.
  int get now => motion.now.inMilliseconds;

  /// The time on the gallery's clock, in ms, outside a build.
  int get clockNow => Clock.of(context).now(context).inMilliseconds;

  /// A build at [at] ms on the gallery's clock.
  void wake(int at) => motion.wakeAt(Duration(milliseconds: at));

  /// How lit something lit at [at] ms is, fading over [ms]: 1 at once, 0
  /// after and while time is frozen.
  double litAt(int? at, [int ms = 900]) =>
      at == null ? 0 : 1 - motion.progress(Duration(milliseconds: at), ms);

  /// The background of something lit [k] ([litStyle]).
  Style lit(double k) => litStyle(Theme.of(context), k);

  Widget buildTimed(BuildContext context);

  @override
  Widget build(BuildContext context) {
    motion.begin(context);
    final built = buildTimed(context);
    motion.end();
    return built;
  }
}

/// Where a cycle stands: on or off, since when, from which value, and
/// the value the option last had.
final class Drive {
  Drive({required this.on, required this.since, required this.from})
    : last = from;

  bool on;
  Duration since;
  int from;
  int last;
}
