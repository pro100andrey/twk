// What the pages share: the line under a widget that says what happened,
// lit for a moment when it changes, the Dart a Code tab writes, and what
// builds on the gallery's clock.
import 'dart:math' as math;

import 'package:twk/twk.dart';

import '../motion.dart';
import '../page.dart';
import '../paint.dart';

/// The theme colours the pages offer a choice of, in the design's order.
const pageColors = ['primary', 'accent', 'success', 'warning', 'error', 'info'];

/// The background of what is lit [k] (1 to 0, as it fades): the theme's
/// selection fading into its background, as the pages light what changed;
/// none at 0.
Style litStyle(ThemeData theme, double k) => k <= 0
    ? const Style()
    : Style(
        bg: mix(
          theme.background.bg ?? Color.defaultColor,
          theme.selection.bg!,
          k,
        ),
      );

/// What happened, as the pages say it under their widget: [spans], each
/// (text, muted): the muted ones labels (`saved: `), the others values,
/// which light up bold when [serial] changes and fade in 900 ms; in
/// [maxLines] lines at most, or on one with [wrap] none, cut with an
/// ellipsis. The fade is the gallery's own, not the Code's.
final class LitLine extends StatefulWidget {
  const LitLine(
    this.spans, {
    required this.serial,
    super.key,
    this.maxLines,
    this.wrap = TextWrap.word,
  });

  final List<(String, bool)> spans;

  /// Changes when something happened.
  final int serial;

  /// The lines it takes at most; null for as many as it needs.
  final int? maxLines;

  /// How it breaks its lines.
  final TextWrap wrap;

  @override
  State<LitLine> createState() => _LitLineState();
}

final class _LitLineState extends State<LitLine> {
  late final _motion = Motion(() {
    if (mounted) {
      setState(() {});
    }
  });
  int? _serial;
  Duration? _litAt;

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _motion.begin(context);
    final theme = Theme.of(context);
    if (_serial != null && _serial != widget.serial) {
      _litAt = _motion.now;
    }
    _serial = widget.serial;
    final at = _litAt;
    final k = at == null ? 0.0 : 1 - _motion.progress(at, 900);
    final lit = k > 0
        ? litStyle(theme, k).merge(const Style(attrs: Attr.bold))
        : const Style();
    _motion.end();
    final cut = widget.maxLines != null || widget.wrap == TextWrap.none;
    return Text.rich(
      [
        for (final (text, muted) in widget.spans)
          if (muted) Span(text, theme.muted) else Span(text, lit),
      ],
      wrap: widget.wrap,
      maxLines: widget.maxLines,
      overflow: cut ? TextOverflow.ellipsis : TextOverflow.clip,
    );
  }
}

/// The lines of the call [head]([args])[tail] at [indent], as dart format
/// writes it: on one line where it fits in 80 columns, else an argument a
/// line with a comma after each.
List<String> call(int indent, String head, List<String> args, String tail) {
  final pad = ' ' * indent;
  final one = '$pad$head(${args.join(', ')})$tail';
  if (one.length <= 78) {
    return [one];
  }
  return [
    '$pad$head(',
    for (final a in args) '$pad  $a,',
    '$pad)$tail',
  ];
}

/// The lines of a State whose timer calls [body] every [ms].
List<String> timerLines(int ms, List<String> body) => [
  'late final Timer _timer;',
  '',
  '@override',
  'void initState() {',
  '  super.initState();',
  '  _timer = Timer.periodic(',
  '    const Duration(milliseconds: $ms),',
  for (final l in body) '    $l',
  '  );',
  '}',
  '',
  '@override',
  'void dispose() {',
  '  _timer.cancel();',
  '  super.dispose();',
  '}',
];

/// [parts] as one line of the Code, a line too long for its file.
String codeLine(List<String> parts) => parts.join();

/// [v] within [low] and [high]; [low] where they cross.
int clampTo(int v, int low, int high) => math.max(low, math.min(high, v));

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

final class _TimedBuilds extends State<Timed> {
  late final _motion = Motion(() {
    if (mounted) {
      setState(() {});
    }
  });

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _motion.begin(context);
    final built = widget.builder(
      context,
      _motion.now.inMilliseconds,
      (at) => _motion.wakeAt(Duration(milliseconds: at)),
    );
    _motion.end();
    return built;
  }
}

/// A State that builds with a [Motion] begun on the gallery's clock, and
/// the page's kept state.
abstract base class TimedState<W extends StatefulWidget> extends State<W> {
  late final motion = Motion(() {
    if (mounted) {
      setState(() {});
    }
  });
  late final Map<String, Object?> kept = PageControl.of(context).state;

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

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

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
