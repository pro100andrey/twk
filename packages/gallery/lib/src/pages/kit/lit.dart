// The line under a widget that says what happened, lit for a moment
// when it changes (README.md, "Adding a page").
import 'package:twk/twk.dart';

import '../../paint.dart';
import 'motion_state.dart';

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

/// How lit what a serial counts is, as the pages light what changed: 1
/// as it changes, fading to 0 in 900 ms, 0 before it first changed.
mixin _LightsUp<W extends StatefulWidget> on MotionState<W> {
  int? _serial;
  Duration? _litAt;

  /// How lit at this build, with [serial] as it is now: between the
  /// motion's `begin` and `end`.
  double lightness(int serial) {
    if (_serial != null && _serial != serial) {
      _litAt = motion.now;
    }
    _serial = serial;
    final at = _litAt;
    return at == null ? 0.0 : 1 - motion.progress(at, 900);
  }
}

final class _LitLineState extends State<LitLine> with MotionState, _LightsUp {
  @override
  Widget build(BuildContext context) {
    motion.begin(context);
    final theme = Theme.of(context);
    final k = lightness(widget.serial);
    final lit = k > 0
        ? litStyle(theme, k).merge(const Style(attrs: Attr.bold))
        : const Style();
    motion.end();
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

/// [text] in [style], its background lit for a moment when [serial]
/// changes, as [LitLine] lights its values (not bold), on up to
/// [maxLines] lines.
final class LitText extends StatefulWidget {
  const LitText(
    this.text, {
    required this.serial,
    super.key,
    this.style = const Style(),
    this.maxLines,
  });

  final String text;

  /// Changes when something happened.
  final int serial;

  final Style style;

  /// The lines it takes at most, cut with an ellipsis; null for as many
  /// as it needs.
  final int? maxLines;

  @override
  State<LitText> createState() => _LitTextState();
}

final class _LitTextState extends State<LitText> with MotionState, _LightsUp {
  @override
  Widget build(BuildContext context) {
    motion.begin(context);
    final k = lightness(widget.serial);
    motion.end();
    return Text(
      widget.text,
      style: widget.style.merge(litStyle(Theme.of(context), k)),
      maxLines: widget.maxLines,
      overflow: widget.maxLines == null
          ? TextOverflow.clip
          : TextOverflow.ellipsis,
    );
  }
}
