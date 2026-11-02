/// One of several values to choose from, and the controls that choose one
/// as it is pressed: [Choice] and [RadioGroup].
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart' show Attr;

import '../focus/focus.dart';
import '../foundation/helpers.dart';
import '../framework/framework.dart';
import '../gestures/gesture_detector.dart';
import '../layout/flex.dart';
import '../semantics/semantics.dart';
import '../style/glyphs.dart' show radioMarks;
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
/// a mark, `(●)` for the one whose value is [value], `( )` for the others
/// (`Glyphs.radioOn`, `Glyphs.radioOff` and `Glyphs.radioBrackets` of the
/// theme).
///
/// The choices go one below another, or side by side along a horizontal
/// [direction]; [mark] is what is between the parentheses of the one
/// chosen, in place of `Glyphs.radioOn`.
/// One stop of Tab: while it has the focus, Up and Left choose the
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
/// What an app sets: the glyphs of the theme, `radioOn`, `radioOff` and
/// `radioBrackets` (`Glyphs.ascii` has `(*)`; `radioOn: '◉'`,
/// `radioOff: '○'` and `radioBrackets: ('', '')` draw `◉ ○` with no
/// parentheses); [mark], the chosen one's mark above the theme; the
/// styles of the mark, the brackets, the choice that shows the focus and
/// a disabled one, and [direction].
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
    this.mark,
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

  /// What is between the brackets of the choice chosen, a character one
  /// column wide, in place of `Glyphs.radioOn`; null for the theme's. It is
  /// the app's own text, not a theme mark: the width rule of `Glyphs`
  /// fits the theme's marks, and a [mark] of another width is drawn as it
  /// is, for the app that wrote it to have meant.
  final String? mark;

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
  int _step(int from, int step) =>
      nextEnabled(choices.length, from, step, (i) => choices[i].enabled);

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
        final radio = radioMarks(context, theme.glyphs);
        final row = Flex(
          direction: direction,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          gap: vertical ? 0 : 2,
          children: [
            for (var i = 0; i < choices.length; i++)
              _choice(
                theme,
                radio,
                i,
                on: i == chosen,
                focused: focused && i == focus,
                enabled: enabled && choices[i].enabled,
              ),
          ],
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
                focused: focused && i == focus,
              ),
          ],
          child: row,
        );
      },
    );
    return pressable;
  }

  Widget _choice(
    ThemeData theme,
    ({String on, String off}) radio,
    int i, {
    required bool on,
    required bool focused,
    required bool enabled,
  }) {
    final choice = choices[i];
    return GestureDetector(
      onTap: enabled ? (_) => _choose(i) : null,
      // the hidden cursor on the choice that shows the focus
      child: ActiveItem(
        active: focused,
        child: Text.richLine(
          [
            ..._radioSpans(
              theme,
              on ? radio.on : radio.off,
              on,
              enabled,
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
        ),
      ),
    );
  }

  /// The theme's radio button as spans: the opening bracket, [glyph] (the
  /// [mark] given in its place while [on]) and the closing bracket, each
  /// left out where it is empty. The mark has its style while [on] and
  /// [enabled], the text's while it is on and not enabled, and
  /// [bracketStyle] (muted) while it is off, as the brackets are, over
  /// that.
  List<Span> _radioSpans(
    ThemeData theme,
    String glyph,
    bool on,
    bool enabled,
  ) {
    final marked = on && enabled ? markStyle(theme) : const Style();
    final brackets = marked.merge(
      bracketStyle ?? theme.muted.merge(const Style(attrsOff: Attr.bold)),
    );
    final (open, close) = theme.glyphs.radioBrackets;
    return [
      if (open.isNotEmpty) Span(open, brackets),
      Span(on ? mark ?? glyph : glyph, on ? marked : brackets),
      if (close.isNotEmpty) Span(close, brackets),
    ];
  }
}
