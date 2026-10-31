/// What is on or off: [Checkbox] and [Switch].
library;

import 'package:twk_core/twk_core.dart' show Brightness, Color;

import '../animation/curves.dart';
import '../animation/implicit.dart';
import '../animation/tween.dart';
import '../focus/focus.dart';
import '../framework/framework.dart';
import '../semantics/semantics.dart';
import '../style/color_mix.dart';
import '../style/style.dart';
import '../text/widgets.dart';
import 'pressable.dart';

/// A checkbox before [label]: `[x]` while [value] is true, `[ ]` while it
/// is false.
///
/// Clicked, or Space or Enter pressed while it has the focus (Space
/// hinted), it calls [onChanged] with the value it is to take; the app
/// builds it with that one. Disabled with no [onChanged]: then it takes
/// neither the focus, which Tab passes by, nor the mouse.
///
/// A setting held by the app:
///
/// ```dart
/// final wrap = ValueNotifier(true);
/// final box = ValueListenableBuilder(
///   valueListenable: wrap,
///   builder: (context, on, _) => Checkbox(
///     value: on,
///     label: 'Wrap long lines',
///     onChanged: (v) => wrap.value = v,
///   ),
/// );
/// ```
///
/// One row, cut off with "…" where it does not fit. The styles, each
/// merged over those before it: the theme's text and [style] for the row,
/// and [ThemeData.primary] in bold for the `x` of a checked box;
/// [bracketStyle] for the brackets, [ThemeData.muted] when null;
/// [focusedStyle] for the row while it has the focus, the theme's
/// [ThemeData.selection] when null; [disabledStyle] while it is disabled,
/// [ThemeData.muted] when null.
///
/// A plain look, the brackets as the mark and the row reversed while
/// focused: `bracketStyle: const Style()` and
/// `focusedStyle: theme.primary.merge(const Style(attrs: Attr.bold |
/// Attr.reverse))`.
///
/// A screen reader reads it as a [SemanticsRole.checkbox] of its label,
/// or of its [semanticsLabel] where it shows none, `checked` or `not
/// checked`, and `disabled` while it is.
///
/// See also:
///
///  * [Switch], the same on and off as a pill.
///  * `RadioGroup`, one of several values.
final class Checkbox extends StatelessWidget {
  /// A box checked while [value] is; disabled when [onChanged] is null.
  const Checkbox({
    required this.value,
    required this.onChanged,
    super.key,
    this.label = '',
    this.semanticsLabel,
    this.focusNode,
    this.autofocus = false,
    this.style,
    this.bracketStyle,
    this.focusedStyle,
    this.disabledStyle,
  });

  /// Whether the box is checked.
  final bool value;

  /// Called with the value the box is to take; null for a disabled box.
  final void Function(bool value)? onChanged;

  /// What is after the box; nothing when empty.
  final String label;

  /// What a screen reader calls a box that shows no [label]: `Bold`;
  /// null, or empty, for one read as checked or not alone. A [label] is
  /// read in its place, so that what is read of the box is what it shows.
  final String? semanticsLabel;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// The row, the theme's text under it.
  final Style? style;

  /// The brackets, over the row and the mark's style; [ThemeData.muted],
  /// not bold, when null.
  final Style? bracketStyle;

  /// The row while it has the focus; [ThemeData.selection] when null.
  final Style? focusedStyle;

  /// The row while it is disabled; [ThemeData.muted] when null.
  final Style? disabledStyle;

  @override
  Widget build(BuildContext context) => _Toggle(
    role: SemanticsRole.checkbox,
    marks: (theme, row, on, enabled, _) =>
        bracketed(theme, '[', on ? 'x' : ' ', ']', on, enabled, bracketStyle),
    on: value,
    toggle: switch (onChanged) {
      final onChanged? => () => onChanged(!value),
      null => null,
    },
    label: label,
    semanticsLabel: semanticsLabel,
    focusNode: focusNode,
    autofocus: autofocus,
    style: style,
    focusedStyle: focusedStyle,
    disabledStyle: disabledStyle,
  );
}

/// A switch before [label], on while [value] is true and off while it is
/// false.
///
/// It is a pill `▐ ● ▌` whose knob runs to the right end as it turns on,
/// to the left as it turns off, in 140 ms. Its track is
/// [ThemeData.primary] while on, [ThemeData.border] while off, a mix of
/// the two on the way; disabled, [ThemeData.faint] with the knob
/// [ThemeData.muted]. As a [Checkbox] is checked, with the same keys,
/// clicks and styles, the row on [ThemeData.selection] while it has the
/// focus. With [pill] false it shows `[on ]` and `[off]`, `on` in
/// [ThemeData.primary] in bold: with `focusedStyle:
/// theme.primary.merge(const Style(attrs: Attr.bold | Attr.reverse))`, a
/// plain look. A screen reader reads it as a [SemanticsRole.toggle] of its
/// label, or of its [semanticsLabel] where it shows none, `on` or `off`.
///
/// ```dart
/// final wifi = ValueNotifier(false);
/// final toggle = ValueListenableBuilder(
///   valueListenable: wifi,
///   builder: (context, on, _) => Switch(
///     value: on,
///     label: 'Wi-Fi',
///     onChanged: (v) => wifi.value = v,
///   ),
/// );
/// ```
final class Switch extends StatelessWidget {
  /// A switch on while [value] is; disabled when [onChanged] is null.
  const Switch({
    required this.value,
    required this.onChanged,
    super.key,
    this.label = '',
    this.semanticsLabel,
    this.focusNode,
    this.autofocus = false,
    this.pill = true,
    this.style,
    this.focusedStyle,
    this.disabledStyle,
  });

  /// Whether the switch is on.
  final bool value;

  /// Called with the value the switch is to take; null for a disabled
  /// switch.
  final void Function(bool value)? onChanged;

  /// What is after the switch; nothing when empty.
  final String label;

  /// What a screen reader calls a switch that shows no [label]: `Wi-Fi`;
  /// null, or empty, for one read as on or off alone. A [label] is read
  /// in its place, as of a [Checkbox].
  final String? semanticsLabel;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// Whether it is the pill `▐ ● ▌`; false for `[on ]` and `[off]`.
  final bool pill;

  /// The row, the theme's text under it.
  final Style? style;

  /// The row while it has the focus; [ThemeData.selection] when null.
  final Style? focusedStyle;

  /// The row while it is disabled; [ThemeData.muted] when null.
  final Style? disabledStyle;

  @override
  Widget build(BuildContext context) => _Toggle(
    role: SemanticsRole.toggle,
    marks: pill
        ? _pill
        : (theme, row, on, enabled, _) => [
            Span(
              on ? '[on ]' : '[off]',
              on && enabled ? markStyle(theme) : const Style(),
            ),
          ],
    animated: pill,
    on: value,
    toggle: switch (onChanged) {
      final onChanged? => () => onChanged(!value),
      null => null,
    },
    label: label,
    semanticsLabel: semanticsLabel,
    focusNode: focusNode,
    autofocus: autofocus,
    style: style,
    focusedStyle: focusedStyle,
    disabledStyle: disabledStyle,
  );

  /// The spans of the pill a [Switch] draws in [theme], five cells, its
  /// knob [at] of the way to the right end (0 off, 1 on, between them as
  /// it moves), muted unless [enabled]: for a painter of one's own that
  /// shows a switch as the widget does, the gallery's options among them.
  /// The ends set no background, over what is under them.
  static List<Span> pillSpans(
    ThemeData theme, {
    required double at,
    bool enabled = true,
  }) => _pill(theme, const Style(), at >= 0.5, enabled, at);

  /// The pill with its knob [at] of the way to the right end, as the
  /// design draws it: the ends half blocks in the track's color, the knob
  /// `●` on it in one of the three cells between them.
  static List<Span> _pill(
    ThemeData theme,
    Style row,
    bool on,
    bool enabled,
    double at,
  ) {
    final dark = theme.brightness == Brightness.dark;
    final Color? off;
    final Color? lit;
    if (!enabled) {
      off = lit = theme.faint.fg;
    } else {
      off = dark
          ? mixRgb(theme.border.fg, theme.background.bg, 0.15) ??
                theme.border.fg
          : theme.border.fg;
      lit = theme.primary.fg;
    }
    final track = mixRgb(off, lit, at) ?? (at < 0.5 ? off : lit);
    const white = Color.rgb(0xff, 0xff, 0xff);
    final knob = !enabled
        ? theme.muted.fg
        : dark
        // the colors not RGB: white on the primary color, as on its fill
        ? mixRgb(theme.text.fg, white, at) ??
              (at < 0.5 ? theme.text.fg : theme.fill(lit).fg)
        : white;
    final k = (at * 2).round();
    final end = Style(fg: track);
    return [
      Span('▐', end),
      Span(
        '${' ' * k}●${' ' * (2 - k)}',
        Style(fg: knob, bg: track),
      ),
      Span('▌', end),
    ];
  }
}

/// What a [Checkbox] and a [Switch] share: what [marks] gives before
/// [label], which [toggle] flips, read as a node of [role] called [label],
/// or [semanticsLabel] while that is empty. [marks] gets how far it is on,
/// from 0 to 1, running between them in 140 ms where [animated].
final class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.role,
    required this.marks,
    required this.on,
    required this.toggle,
    required this.label,
    required this.semanticsLabel,
    required this.focusNode,
    required this.autofocus,
    required this.style,
    required this.focusedStyle,
    required this.disabledStyle,
    this.animated = false,
  });

  final SemanticsRole role;
  final List<Span> Function(
    ThemeData theme,
    Style row,
    bool on,
    bool enabled,
    double at,
  )
  marks;
  final bool on;
  final void Function()? toggle;
  final String label;
  final String? semanticsLabel;
  final FocusNode? focusNode;
  final bool autofocus;
  final Style? style;
  final Style? focusedStyle;
  final Style? disabledStyle;
  final bool animated;

  @override
  Widget build(BuildContext context) {
    final toggle = this.toggle;
    final enabled = toggle != null;
    final pressable = Pressable(
      enabled: enabled,
      focusNode: focusNode,
      autofocus: autofocus,
      bindings: {'space': toggle, 'enter': toggle},
      hints: const {'space': 'toggle'},
      onTap: enabled ? (_) => toggle() : null,
      builder: (context, focused) {
        final theme = Theme.of(context);
        final row = rowStyle(
          theme,
          style: style,
          focused: focused,
          focusedStyle: focusedStyle ?? focusedRow(theme),
          enabled: enabled,
          disabledStyle: disabledStyle,
        );
        Widget text(double at) => Text.richLine(
          [
            ...marks(theme, row, on, enabled, at),
            if (label.isNotEmpty) Span(' $label'),
          ],
          style: row,
        );
        final at = on ? 1.0 : 0.0;
        if (!animated) {
          return text(at);
        }
        return TweenAnimationBuilder<double>(
          value: at,
          tween: Tween<double>.new,
          duration: const Duration(milliseconds: 140),
          // the design's ease out, a cubic
          curve: const Cubic(0.33, 1, 0.68, 1),
          builder: (context, at, _) => text(at),
        );
      },
    );
    return Semantics(
      role: role,
      // never null, for the mark not to be read
      label: label.isNotEmpty ? label : semanticsLabel ?? '',
      state: SemanticsState(checked: on, disabled: !enabled),
      child: pressable,
    );
  }
}
