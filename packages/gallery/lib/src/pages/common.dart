// What the pages share: the line under a widget that says what happened,
// lit for a moment when it changes, and the Dart a Code tab writes.
import 'package:twk/twk.dart';

import '../motion.dart';
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
