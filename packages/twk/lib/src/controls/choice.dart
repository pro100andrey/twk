/// One of several values to choose from, and the controls that choose one
/// as it is pressed: [Choice] and [RadioGroup].
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show Axis, CrossAxisAlignment, MainAxisSize, TextOverflow, TextWrap;

import '../focus/focus.dart';
import '../framework/framework.dart';
import '../gestures/gesture_detector.dart';
import '../layout/flex.dart';
import '../semantics/semantics.dart';
import '../style/style.dart';
import '../text/widgets.dart';
import 'pressable.dart';

/// One of the values a [RadioGroup], a `Select` or a `MultiSelect` offers:
/// [value], shown as [label].
///
/// One not [enabled] cannot be chosen: a [RadioGroup] shows it muted, a
/// `Select` leaves it out of its list. Two choices are equal when their
/// values, labels and [enabled] are.
///
/// ```dart
/// const sizes = [
///   Choice('s', 'Small'),
///   Choice('m', 'Medium'),
///   Choice('l', 'Large', enabled: false),
/// ];
/// ```
@immutable
final class Choice<T> {
  /// A choice of [value] shown as [label], enabled unless [enabled] is
  /// false.
  const Choice(this.value, this.label, {this.enabled = true});

  /// What choosing it gives.
  final T value;

  /// What it shows.
  final String label;

  /// Whether it can be chosen; true by default.
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is Choice<T> &&
      other.value == value &&
      other.label == label &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(value, label, enabled);

  @override
  String toString() => 'Choice($value, $label)';
}

/// Radio buttons: [choices], one of which is chosen, each its label after
/// a mark, `(●)` for the one whose value is [value], `( )` for the others.
///
/// The choices go one below another, or side by side along a horizontal
/// [direction]; [mark] is what is between the parentheses of the one
/// chosen. One stop of Tab: while it has the focus, Up and Left choose the
/// enabled choice before the one chosen, Down and Right the one after,
/// from the last to the first and back, Home and End the first and the
/// last; Space and Enter choose the one that shows the focus, the first
/// enabled one while none is chosen. A choice clicked is chosen. Choosing
/// calls [onChanged] with the value; the app builds the group with it.
///
/// Three sizes, the medium one chosen until the user picks another:
///
/// ```dart
/// final size = ValueNotifier('m');
/// final group = ValueListenableBuilder(
///   valueListenable: size,
///   builder: (context, value, _) => RadioGroup<String>(
///     choices: const [
///       Choice('s', 'Small'),
///       Choice('m', 'Medium'),
///       Choice('l', 'Large'),
///     ],
///     value: value,
///     onChanged: (value) => size.value = value,
///   ),
/// );
/// ```
///
/// Disabled with no [onChanged], or no enabled choice: then it takes
/// neither the focus, which Tab passes by, nor the mouse. A choice not
/// enabled is passed by and cannot be clicked.
///
/// The styles, each merged over those before it: the theme's text and
/// [style] for a choice, and [ThemeData.primary] in bold for the mark of
/// the one chosen; [bracketStyle] for the parentheses, [ThemeData.muted]
/// when null; [focusedStyle] for the one chosen while the group has the
/// focus, or the first enabled one while none is, [ThemeData.selection]
/// when null; [disabledStyle] for one that cannot be chosen,
/// [ThemeData.muted] when null.
///
/// A plain look, `(*)` all in the mark's style and the focused choice
/// reversed: `mark: '*'`, `bracketStyle: const Style()` and
/// `focusedStyle: theme.primary.merge(const Style(attrs: Attr.bold |
/// Attr.reverse))`.
///
/// A screen reader reads each choice as a [SemanticsRole.radio] of its
/// label, `checked` or `not checked`, and `disabled` when it cannot be
/// chosen; while the group has the focus, the choice that shows it is the
/// focused node.
///
/// See also:
///
///  * `Select`, one of many values in a popup.
///  * `Checkbox`, a value on or off.
final class RadioGroup<T> extends StatelessWidget {
  /// Radio buttons of [choices], the one of [value] chosen; disabled when
  /// [onChanged] is null.
  const RadioGroup({
    required this.choices,
    required this.value,
    required this.onChanged,
    super.key,
    this.direction = Axis.vertical,
    this.focusNode,
    this.autofocus = false,
    this.mark = '●',
    this.style,
    this.bracketStyle,
    this.focusedStyle,
    this.disabledStyle,
  });

  /// What can be chosen, in the order shown.
  final List<Choice<T>> choices;

  /// The value of the choice chosen; none is when no choice has it.
  final T? value;

  /// Called with the value of the choice chosen; null for a disabled
  /// group.
  // ignore: unsafe_variance
  final void Function(T value)? onChanged;

  /// Along which the choices go: down, or across with two blanks between.
  final Axis direction;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// What is between the parentheses of the choice chosen: a character
  /// one column wide.
  final String mark;

  /// A choice, the theme's text under it.
  final Style? style;

  /// The parentheses, over the choice and the mark's style;
  /// [ThemeData.muted], not bold, when null.
  final Style? bracketStyle;

  /// The choice that shows the focus; [ThemeData.selection] when null.
  final Style? focusedStyle;

  /// A choice that cannot be chosen; [ThemeData.muted] when null.
  final Style? disabledStyle;

  /// The choice chosen; -1 for none.
  int get _chosen {
    for (var i = 0; i < choices.length; i++) {
      if (choices[i].value == value && choices[i].enabled) {
        return i;
      }
    }
    return -1;
  }

  /// The enabled choice [step] places on from [from], round; -1 for none.
  int _step(int from, int step) {
    final n = choices.length;
    for (var k = 1; k <= n; k++) {
      final i = ((from + step * k) % n + n) % n;
      if (choices[i].enabled) {
        return i;
      }
    }
    return -1;
  }

  void _choose(int i) {
    if (i >= 0) {
      onChanged?.call(choices[i].value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _chosen;
    final first = _step(-1, 1);
    final enabled = onChanged != null && first >= 0;
    final focus = chosen >= 0 ? chosen : first;
    void before() => _choose(_step(chosen >= 0 ? chosen : choices.length, -1));
    void after() => _choose(_step(chosen, 1));
    void here() => _choose(focus);
    final vertical = direction == Axis.vertical;
    final pressable = Pressable(
      enabled: enabled,
      focusNode: focusNode,
      autofocus: autofocus,
      bindings: {
        'up': before,
        'left': before,
        'down': after,
        'right': after,
        'home': () => _choose(first),
        'end': () => _choose(_step(choices.length, -1)),
        'space': here,
        'enter': here,
      },
      hints: vertical
          ? const {'up': 'previous', 'down': 'next'}
          : const {'left': 'previous', 'right': 'next'},
      builder: (context, focused) {
        final theme = Theme.of(context);
        return Flex(
          direction: direction,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          gap: vertical ? 0 : 2,
          children: [
            for (var i = 0; i < choices.length; i++)
              _choice(
                theme,
                i,
                on: i == chosen,
                focused: focused && i == focus,
                enabled: enabled && choices[i].enabled,
              ),
          ],
        );
      },
    );
    return Semantics(
      nodes: [
        for (var i = 0; i < choices.length; i++)
          SemanticsNode(
            role: SemanticsRole.radio,
            label: choices[i].label,
            state: SemanticsState(
              checked: i == chosen,
              disabled: !enabled || !choices[i].enabled,
            ),
            focused: i == focus,
          ),
      ],
      child: pressable,
    );
  }

  Widget _choice(
    ThemeData theme,
    int i, {
    required bool on,
    required bool focused,
    required bool enabled,
  }) {
    final choice = choices[i];
    return GestureDetector(
      onTap: enabled ? (_) => _choose(i) : null,
      child: Text.rich(
        [
          ...bracketed(
            theme,
            '(',
            on ? mark : ' ',
            ')',
            on,
            enabled,
            bracketStyle,
          ),
          Span(' ${choice.label}'),
        ],
        style: rowStyle(
          theme,
          style: style,
          focused: focused,
          focusedStyle: focusedStyle ?? focusedRow(theme),
          enabled: enabled,
          disabledStyle: disabledStyle,
        ),
        wrap: TextWrap.none,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }
}
