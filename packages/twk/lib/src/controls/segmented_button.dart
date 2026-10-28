/// A compact choice of one or more of a few values, on one row:
/// [SegmentedButton].
library;

import 'package:twk_core/twk_core.dart' show TextSegmenter, fitText;

import '../binding/app_binding.dart';
import '../focus/focus.dart';
import '../framework/framework.dart';
import '../semantics/semantics.dart';
import '../style/style.dart';
import '../text/hit_row.dart';
import 'choice.dart';
import 'pressable.dart';

/// A row of [segments] joined into one control, of which those whose
/// values are in [selected] are on: `[ All │ Errors (3) │ Warnings │ Info ]`.
///
/// Where a `TabBar` is too big: a filter, a view, a mode. One segment is
/// on at a time, or with [multiSelectionEnabled] any number of them;
/// [emptySelectionAllowed] lets the last one on be turned off. Turning one
/// on or off calls [onSelectionChanged] with the values that are on then,
/// a new set; the app builds the control with it. A press that changes
/// nothing calls nothing.
///
/// One stop of Tab. While it has the focus one segment is highlighted, at
/// first the first one on, or the first enabled one: Left and Right move
/// the highlight to the enabled segment before and after it, from the
/// last to the first and back, Home and End to the first and the last;
/// Space and Enter press the highlighted one, and 1 to 9 the segment of
/// that number, highlighting it. A segment clicked is pressed too. A
/// press of one that is off turns it on, and in a single choice the one
/// that was on off; a press of one that is on turns it off where that
/// leaves the choice allowed (in a multiple one, or with
/// [emptySelectionAllowed]). Left and Right, Space and the digits are
/// hinted.
///
/// Disabled with no [onSelectionChanged], or no enabled segment: then it
/// takes neither the focus, which Tab passes by, nor the mouse. A segment
/// not enabled ([Choice.enabled]) is passed by and cannot be pressed.
///
/// A segment is its label with a blank on either side, after `✓ ` while
/// it is on with [showSelectedIcon]; one `│` is between two segments and
/// the row is between [caps], `[` and `]` by default (`('(', ')')` for
/// round ones). One row, as wide as its segments within its constraints;
/// where they do not fit, the labels are cut off with `…` evenly, the
/// longest first, never wrapped.
///
/// The styles, each merged over those before it: the theme's text and
/// [style] for the row; [ThemeData.border] for the caps and the lines
/// between; [ThemeData.primary] in bold for a segment that is on;
/// [ThemeData.selection] for the highlighted one while the control has
/// the focus; [ThemeData.muted] for one that cannot be pressed. The mouse
/// over an enabled segment lights it as it does a `Button`: its
/// background a step from [ThemeData.surface] towards its text, where both
/// are RGB; with a theme whose are not, there is no hover and the motion
/// of the mouse goes unreported.
///
/// On plain output (`TerminalInfo.plain`), which has no colors, a segment
/// that is on shows `✓ ` whatever [showSelectedIcon] says.
///
/// A screen reader reads each segment as a [SemanticsRole.radio] of its
/// label, or a [SemanticsRole.checkbox] in a multiple choice, `checked`
/// while it is on and `disabled` when it cannot be pressed; while the
/// control has the focus, the highlighted segment is the focused node.
///
/// Which of a log's records are shown, one kind at a time:
///
/// ```dart
/// final shown = ValueNotifier({'all'});
/// final view = ValueListenableBuilder(
///   valueListenable: shown,
///   builder: (context, values, _) => SegmentedButton<String>(
///     segments: const [
///       Choice('all', 'All'),
///       Choice('errors', 'Errors (3)'),
///       Choice('warnings', 'Warnings (12)'),
///       Choice('info', 'Info', enabled: false),
///     ],
///     selected: values,
///     onSelectionChanged: (values) => shown.value = values,
///   ),
/// );
/// ```
///
/// See also:
///
///  * [RadioGroup], one of several values, a row each.
///  * `TabBar`, tabs that switch what is shown below them.
final class SegmentedButton<T> extends StatefulWidget {
  /// A row of [segments], those whose values are in [selected] on;
  /// disabled when [onSelectionChanged] is null.
  const SegmentedButton({
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    super.key,
    this.multiSelectionEnabled = false,
    this.emptySelectionAllowed = false,
    this.showSelectedIcon = false,
    this.caps = const ('[', ']'),
    this.focusNode,
    this.autofocus = false,
    this.style,
  });

  /// What can be chosen, in the order shown: each [Choice]'s value, label
  /// and whether it is enabled.
  final List<Choice<T>> segments;

  /// The values of the segments that are on.
  final Set<T> selected;

  /// Called with the values that are on after a press that changed them;
  /// null for a disabled control.
  // ignore: unsafe_variance
  final void Function(Set<T> selected)? onSelectionChanged;

  /// Whether any number of segments can be on, not one alone.
  final bool multiSelectionEnabled;

  /// Whether the last segment on can be turned off, leaving none.
  final bool emptySelectionAllowed;

  /// Whether a segment that is on shows `✓ ` before its label.
  final bool showSelectedIcon;

  /// What the row is between, at its left and its right, each one column
  /// wide.
  final (String, String) caps;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// The row, the theme's text under it.
  final Style? style;

  @override
  State<SegmentedButton<T>> createState() => _SegmentedButtonState<T>();
}

final class _SegmentedButtonState<T> extends State<SegmentedButton<T>> {
  /// The segment highlighted while the control has the focus; -1 before
  /// one is.
  var _highlight = -1;

  /// Where each segment is along the row, as last built, and the one the
  /// mouse is over.
  final _hits = HitRow();

  List<Choice<T>> get _segments => widget.segments;

  bool get _enabled =>
      widget.onSelectionChanged != null && _segments.any((s) => s.enabled);

  bool _on(int i) => widget.selected.contains(_segments[i].value);

  /// The enabled segment [step] places on from [from], round; -1 for none.
  int _step(int from, int step) {
    final n = _segments.length;
    for (var k = 1; k <= n; k++) {
      final i = ((from + step * k) % n + n) % n;
      if (_segments[i].enabled) {
        return i;
      }
    }
    return -1;
  }

  /// The segment highlighted: [_highlight] while it can be, else the first
  /// enabled one on, else the first enabled one.
  int get _current {
    final h = _highlight;
    if (h >= 0 && h < _segments.length && _segments[h].enabled) {
      return h;
    }
    for (var i = 0; i < _segments.length; i++) {
      if (_segments[i].enabled && _on(i)) {
        return i;
      }
    }
    return _step(-1, 1);
  }

  void _move(int to) {
    if (to >= 0 && to != _highlight) {
      setState(() => _highlight = to);
    }
  }

  void _press(int i) {
    final onSelectionChanged = widget.onSelectionChanged;
    if (onSelectionChanged == null ||
        i < 0 ||
        i >= _segments.length ||
        !_segments[i].enabled) {
      return;
    }
    _move(i);
    final value = _segments[i].value;
    final on = widget.selected.contains(value);
    final Set<T> next;
    if (widget.multiSelectionEnabled) {
      next = {...widget.selected};
      if (on) {
        next.remove(value);
      } else {
        next.add(value);
      }
    } else {
      next = on ? <T>{} : {value};
    }
    if (next.isEmpty && !widget.emptySelectionAllowed) {
      return;
    }
    onSelectionChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    final current = _current;
    final digits = _segments.length < 9 ? _segments.length : 9;
    final plain =
        AppBinding.maybeOf(context)?.twkApp.terminal.info.plain ?? false;
    final pressable = Pressable(
      enabled: enabled,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      bindings: {
        'left': () => _move(_step(current, -1)),
        'right': () => _move(_step(current, 1)),
        'home': () => _move(_step(-1, 1)),
        'end': () => _move(_step(_segments.length, -1)),
        'space': () => _press(current),
        'enter': () => _press(current),
        for (var i = 0; i < digits; i++) '${i + 1}': () => _press(i),
      },
      hints: {
        'left': 'previous',
        'right': 'next',
        'space': widget.multiSelectionEnabled ? 'toggle' : 'select',
        if (digits > 1) '1': '…$digits select',
      },
      onTap: enabled ? (event) => _press(_hits.at(event.x)) : null,
      builder: (context, focused) => LayoutBuilder(
        builder: (context, constraints) => _row(
          Theme.of(context),
          segmenterOf(context),
          constraints.maxW,
          enabled: enabled,
          highlight: focused ? current : -1,
          plain: plain,
        ),
      ),
    );
    return Semantics(
      nodes: [
        for (var i = 0; i < _segments.length; i++)
          SemanticsNode(
            role: widget.multiSelectionEnabled
                ? SemanticsRole.checkbox
                : SemanticsRole.radio,
            label: _segments[i].label,
            state: SemanticsState(
              checked: _on(i),
              disabled: !enabled || !_segments[i].enabled,
            ),
            focused: i == current,
          ),
      ],
      child: pressable,
    );
  }

  /// The row in [theme], [width] columns at most as [segmenter] measures
  /// them: the spans of its text, each segment a target of [_hits].
  Widget _row(
    ThemeData theme,
    TextSegmenter segmenter,
    int width, {
    required bool enabled,
    required int highlight,
    required bool plain,
  }) {
    final n = _segments.length;
    final (open, close) = widget.caps;
    final marks = [
      for (var i = 0; i < n; i++)
        if ((widget.showSelectedIcon || plain) && _on(i)) '✓ ' else '',
    ];
    final labels = _fit(
      segmenter,
      [for (final s in _segments) s.label],
      // the caps, the lines between, and the blanks and marks of each
      width -
          segmenter.width(open) -
          segmenter.width(close) -
          (n - 1) * segmenter.width('│') -
          [for (final m in marks) 2 + segmenter.width(m)].sum,
    );
    final row = theme.text.merge(widget.style ?? const Style());
    final lines = row.merge(theme.border);
    final hover = enabled
        ? buttonHoverStyle(theme, theme.surface.merge(row))
        : const Style();
    final spans = <HitSpan>[(span: Span(open, lines), target: -1)];
    for (var i = 0; i < n; i++) {
      if (i > 0) {
        spans.add((span: Span('│', lines), target: -1));
      }
      final on = enabled && _segments[i].enabled;
      var style = row;
      if (_on(i) && enabled) {
        style = style.merge(markStyle(theme));
      }
      if (!on) {
        style = style.merge(theme.muted);
      } else if (i == highlight) {
        style = style.merge(focusedRow(theme));
      } else if (i == _hits.hovered) {
        style = style.merge(hover);
      }
      spans.add((span: Span(' ${marks[i]}${labels[i]} ', style), target: i));
    }
    spans.add((span: Span(close, lines), target: -1));
    return _hits.row(
      spans,
      segmenter,
      style: row,
      onHover: enabled && hover != const Style()
          ? (_) => setState(() {})
          : null,
    );
  }
}

/// [labels] cut off with `…` to fit [room] columns between them as
/// [segmenter] measures them, evenly: those narrower than an even share as
/// they are, what they leave shared by the others, each one column at
/// least.
List<String> _fit(TextSegmenter segmenter, List<String> labels, int room) {
  final widths = [for (final l in labels) segmenter.width(l)];
  if (widths.sum <= room) {
    return labels;
  }
  // the widest are cut to the same width, the share of what is left
  final order = [for (var i = 0; i < labels.length; i++) i]
    ..sort((a, b) => widths[a].compareTo(widths[b]));
  final cut = List.of(widths);
  var left = room;
  for (var k = 0; k < order.length; k++) {
    final i = order[k];
    final share = left ~/ (order.length - k);
    if (widths[i] > share) {
      // this and every one after it are as wide as the share, or one
      // column more where it does not divide evenly, the first ones
      final rest = order.length - k;
      final extra = left - share * rest;
      for (var m = k; m < order.length; m++) {
        final w = share + (m - k < extra ? 1 : 0);
        cut[order[m]] = w < 1 ? 1 : w;
      }
      break;
    }
    left -= widths[i];
  }
  return [
    for (var i = 0; i < labels.length; i++)
      fitText(segmenter, labels[i], cut[i]),
  ];
}

extension on List<int> {
  int get sum => fold(0, (a, b) => a + b);
}
