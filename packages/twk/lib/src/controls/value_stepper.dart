/// One of a list of values, stepped through with arrows on either side of
/// it: [ValueStepper].
library;

import 'package:twk_core/twk_core.dart' show TextSegmenter, fitText, padCells;

import '../focus/focus.dart';
import '../foundation/helpers.dart';
import '../framework/framework.dart';
import '../semantics/semantics.dart';
import '../style/style.dart';
import '../text/hit_row.dart';
import 'choice.dart';
import 'pressable.dart';
import 'segmented_button.dart';

/// The value of one of [values] shown between arrows, `‹ dark ›`, which
/// Left and Right and a click on an arrow step to the value before and
/// after it.
///
/// Where a `Select` is too much for a few values: a theme, a size, a
/// level. Stepping stops at the first and the last value, the arrow there
/// muted, as a size or a level is expected to; with [wrap] it goes on from
/// the last to the first and the other way round, for a cycle (the days of
/// a week). A value not enabled ([Choice.enabled]) is passed by. Stepping
/// calls [onChanged] with the value stepped to; the app builds the stepper
/// with it. The label is as wide as the widest of the values, padded with
/// blanks, so that the arrows keep their places as the value changes; it
/// is cut off with `…` where the constraints are narrower. A [value] that
/// is none of the [values] shows nothing, and Right steps to the first
/// value, Left to the last.
///
/// One stop of Tab; Left and Right are hinted. Disabled with no
/// [onChanged], or fewer than two enabled values: then it takes neither
/// the focus, which Tab passes by, nor the mouse, and shows muted.
///
/// The styles, each merged over those before it: the theme's text and
/// [style]; [ThemeData.primary] for the arrows; [ThemeData.selection] for
/// the whole while it has the focus; [ThemeData.muted] while disabled. The
/// mouse over an arrow lights it as it does a `Button`: its background a
/// step from [ThemeData.surface] towards its text, where both are RGB.
///
/// A screen reader reads it as a [SemanticsRole.slider] of the label of
/// the value, `disabled` while it is.
///
/// ```dart
/// final theme = ValueNotifier('dark');
/// final stepper = ValueListenableBuilder(
///   valueListenable: theme,
///   builder: (context, value, _) => ValueStepper<String>(
///     values: const [
///       Choice('dark', 'dark'),
///       Choice('light', 'light'),
///       Choice('auto', 'auto'),
///     ],
///     value: value,
///     onChanged: (next) => theme.value = next,
///   ),
/// );
/// ```
///
/// See also:
///
///  * [SegmentedButton], the values side by side.
///  * [RadioGroup], one of several values, a row each.
final class ValueStepper<T> extends StatefulWidget {
  /// A stepper of [values] showing [value]; disabled when [onChanged] is
  /// null.
  const ValueStepper({
    required this.values,
    required this.value,
    required this.onChanged,
    super.key,
    this.focusNode,
    this.autofocus = false,
    this.style,
    this.wrap = false,
  });

  /// What can be stepped through, in the order shown: each [Choice]'s
  /// value, label and whether it is enabled.
  final List<Choice<T>> values;

  /// The value shown.
  final T value;

  /// Called with the value stepped to; null for a disabled stepper.
  // ignore: unsafe_variance
  final void Function(T value)? onChanged;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// The row, the theme's text under it.
  final Style? style;

  /// Whether stepping past the last value goes to the first and the other
  /// way round; by default it stops, the arrow at the end muted.
  final bool wrap;

  @override
  State<ValueStepper<T>> createState() => _ValueStepperState<T>();
}

final class _ValueStepperState<T> extends State<ValueStepper<T>> {
  /// The arrows as last built: target 0 is `‹`, 1 is `›`.
  final _hits = HitRow();

  List<Choice<T>> get _values => widget.values;

  bool get _enabled =>
      widget.onChanged != null && _values.where((v) => v.enabled).length > 1;

  int get _index => _values.indexWhere((v) => v.value == widget.value);

  /// The index [step] places from the value shown over the enabled ones, or
  /// -1 where there is none (at an end, not wrapping).
  int _target(int step) {
    final n = _values.length;
    final from = _index;
    // A value not in the list starts at the first or last item.
    if (widget.wrap || from < 0) {
      return nextEnabled(
        n,
        from < 0 ? (step > 0 ? -1 : n) : from,
        step,
        (i) => _values[i].enabled,
      );
    }
    final dir = step.sign;
    for (var i = from + dir; i >= 0 && i < n; i += dir) {
      if (_values[i].enabled) {
        return i;
      }
    }
    return -1;
  }

  /// Steps [step] places from the value shown, over the enabled ones.
  void _step(int step) {
    final onChanged = widget.onChanged;
    final n = _values.length;
    if (onChanged == null || n == 0) {
      return;
    }
    final from = _index;
    final i = _target(step);
    if (i >= 0 && i != from) {
      onChanged(_values[i].value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    return Semantics(
      nodes: [
        SemanticsNode(
          role: SemanticsRole.slider,
          label: _index < 0 ? '' : _values[_index].label,
          state: SemanticsState(disabled: !enabled),
        ),
      ],
      child: Pressable(
        enabled: enabled,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        bindings: {'left': () => _step(-1), 'right': () => _step(1)},
        hints: const {'left': 'previous', 'right': 'next'},
        onTap: enabled
            ? (event) {
                switch (_hits.at(event.x)) {
                  case 0:
                    _step(-1);
                  case 1:
                    _step(1);
                }
              }
            : null,
        builder: (context, focused) => LayoutBuilder(
          builder: (context, constraints) => _row(
            Theme.of(context),
            segmenterOf(context),
            constraints.maxW,
            enabled: enabled,
            focused: focused,
          ),
        ),
      ),
    );
  }

  Widget _row(
    ThemeData theme,
    TextSegmenter segmenter,
    int width, {
    required bool enabled,
    required bool focused,
  }) {
    var row = theme.text.merge(widget.style ?? const Style());
    if (!enabled) {
      row = row.merge(theme.muted);
    } else if (focused) {
      row = row.merge(focusedRow(theme));
    }
    final arrows = enabled ? row.merge(theme.primary) : row;
    final end = row.merge(theme.muted);
    final hover = enabled
        ? buttonHoverStyle(theme, theme.surface.merge(row))
        : const Style();
    final index = _index;
    final widest = [
      for (final v in _values) segmenter.width(v.label),
    ].fold(0, (a, b) => a > b ? a : b);
    // the arrows and their blanks take 4 columns; the label the rest
    final room = (width - 4).clamp(1, 1 << 30);
    final label = fitText(
      segmenter,
      index < 0 ? '' : _values[index].label,
      widest < room ? widest : room,
    );
    // a muted arrow at an end, which does nothing and is not lit
    Style arrow(int target) => !enabled || _target(target * 2 - 1) >= 0
        ? (_hits.hovered == target ? arrows.merge(hover) : arrows)
        : end;
    return _hits.row(
      [
        (span: Span(theme.glyphs.previous, arrow(0)), target: 0),
        (
          span: Span(
            ' ${padCells(segmenter, label, widest < room ? widest : room)} ',
            row,
          ),
          target: -1,
        ),
        (span: Span(theme.glyphs.next, arrow(1)), target: 1),
      ],
      segmenter,
      style: row,
      onHover: enabled && hover != const Style()
          ? (_) => setState(() {})
          : null,
      // the hidden cursor on the left arrow while it has the focus
      active: focused ? 0 : -1,
    );
  }
}
