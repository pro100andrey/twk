/// A small label that can be on and taken away, and a row of them with a
/// cursor: [Chip] and [ChipList].
library;

import 'package:twk_core/twk_core.dart'
    show Attr, TextSegmenter, TextWrap, fitText;

import '../binding/app_binding.dart';
import '../focus/focus.dart';
import '../foundation/change_notifier.dart' show VoidCallback;
import '../foundation/helpers.dart';
import '../framework/framework.dart';
import '../layout/flex.dart';
import '../semantics/semantics.dart';
import '../style/style.dart';
import '../text/hit_row.dart';
import '../text/widgets.dart';
import 'choice.dart';
import 'pressable.dart';
import 'segmented_button.dart';
import 'status.dart';

/// What a chip shows: [label] with a blank on either side, after `✓ ` for
/// a [mark], and followed by the [close] mark and a blank where it is
/// removable (`× `).
String _chipText(
  String label, {
  required String mark,
  required String? close,
}) => ' $mark$label ${close == null ? '' : '$close '}';

/// A short [label] on a chip of its own, on one row: a tag, a filter, a
/// recipient. It only shows; [ChipList] is the control that moves between
/// chips and presses them.
///
/// The label has a blank on either side, and `× ` after it where it is
/// [removable]. The styles, each merged over those before it: the theme's
/// text and [style] on [ThemeData.surface]; [ThemeData.primary] filled
/// ([ThemeData.fill]) and bold while [selected]; [ThemeData.selection]
/// while [highlighted]; [ThemeData.muted] while not [enabled]. On plain
/// output (`TerminalInfo.plain`), which has no colors, a chip that is
/// selected shows `✓ ` before its label.
///
/// ```dart
/// const Row(
///   gap: 1,
///   children: [
///     Chip('dart'),
///     Chip('tui', selected: true),
///     Chip('beta', removable: true),
///   ],
/// )
/// ```
///
/// See also:
///
///  * [ChipList], chips that wrap, with a cursor.
///  * [Badge], a label set off by its color, with nothing to press.
final class Chip extends StatelessWidget {
  /// A chip of [label].
  const Chip(
    this.label, {
    super.key,
    this.selected = false,
    this.highlighted = false,
    this.removable = false,
    this.enabled = true,
    this.style,
  });

  /// What it shows.
  final String label;

  /// Whether it is on.
  final bool selected;

  /// Whether the cursor of a list is on it.
  final bool highlighted;

  /// Whether it shows `×`, for taking it away.
  final bool removable;

  /// Whether it can be pressed; false for it muted.
  final bool enabled;

  /// Over the theme's text, under the colors of the state.
  final Style? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plain =
        AppBinding.maybeOf(context)?.twkApp.terminal.info.plain ?? false;
    var chip = theme.surface.merge(theme.text).merge(style ?? const Style());
    if (!enabled) {
      chip = chip.merge(theme.muted);
    } else {
      if (highlighted) {
        // The cursor's row kept, the color of a selected chip over it.
        chip = chip.merge(focusedRow(theme));
        if (selected) {
          chip = chip.merge(Style(fg: theme.primary.fg, attrs: Attr.bold));
        }
      } else if (selected) {
        chip = chip
            .merge(theme.fill(theme.primary.fg))
            .merge(
              const Style(attrs: Attr.bold),
            );
      }
    }
    return Text(
      _chipText(
        label,
        mark: selected && plain ? '${theme.glyphs.check} ' : '',
        close: removable ? theme.glyphs.close : null,
      ),
      style: chip,
      wrap: TextWrap.none,
      maxLines: 1,
    );
  }
}

/// Chips of the [widths] given, laid out in rows of [width] columns at most,
/// a blank between two on a row: for each chip its row, first column and width.
List<({int line, int x, int width})> _flow(List<int> widths, int width) {
  final out = <({int line, int x, int width})>[];
  var line = 0;
  var x = 0;
  for (final w in widths) {
    if (x > 0 && x + 1 + w > width) {
      line++;
      x = 0;
    }
    if (x > 0) {
      x++;
    }
    out.add((line: line, x: x, width: w));
    x += w;
  }
  return out;
}

/// A row of [Chip]s of [chips] that wraps onto more rows, with a cursor
/// that keys and clicks move and press: `Enter` and `Space` or a click
/// call [onPressed], and `Delete`, `Backspace` or a click on the `×` of a
/// chip call [onRemove].
///
/// One stop of Tab. While it has the focus one chip is highlighted, at
/// first the first enabled one: Left and Right move the highlight to the
/// enabled chip before and after it, from the last to the first and back,
/// Up and Down to the nearest chip of the nearest row above and below
/// that has an enabled one, Home and End to the first and the last. Space
/// and Enter press the highlighted
/// chip; Delete and Backspace remove it. A chip clicked is highlighted and
/// pressed; the `×` of a chip, shown while there is an [onRemove],
/// removes it. The app builds the list again with the new chips and
/// [selected]: after a removal the highlight stays at the same place in
/// the list, or on the last chip. Left and Right, Space and Delete are
/// hinted, those whose callbacks there are.
///
/// Disabled with neither callback, or no enabled chip: then it takes
/// neither the focus, which Tab passes by, nor the mouse. A chip not
/// enabled ([Choice.enabled]) is passed by, muted, and cannot be pressed
/// or removed. A chip whose value is in [selected] shows as on. The chips
/// are as wide as their labels within the constraints, a label too long
/// for a row cut off with `…`; the rows are never taller than the chips
/// need.
///
/// A screen reader reads each chip as a [SemanticsRole.checkbox] of its
/// label, `checked` while it is in [selected], where there is an
/// [onPressed], else as a [SemanticsRole.listItem]; `disabled` when it
/// cannot be pressed; while the list has the focus, the highlighted chip
/// is the focused node.
///
/// Tags of a post, which can be turned off or taken away:
///
/// ```dart
/// final tags = ValueNotifier(['dart', 'tui', 'terminal']);
/// final on = ValueNotifier({'tui'});
/// final list = ListenableBuilder(
///   listenable: Listenable.merge([tags, on]),
///   builder: (context, _) => ChipList<String>(
///     chips: [for (final t in tags.value) Choice(t, t)],
///     selected: on.value,
///     onPressed: (tag) => on.value = on.value.contains(tag)
///         ? ({...on.value}..remove(tag))
///         : {...on.value, tag},
///     onRemove: (tag) => tags.value = [...tags.value]..remove(tag),
///   ),
/// );
/// ```
///
/// See also:
///
///  * [Chip], one of the chips without the control.
///  * [SegmentedButton], a choice of a few values on one row, joined.
final class ChipList<T> extends StatefulWidget {
  /// A list of [chips], those whose values are in [selected] on; disabled
  /// without an [onPressed] or an [onRemove].
  const ChipList({
    required this.chips,
    super.key,
    this.selected = const {},
    this.onPressed,
    this.onRemove,
    this.focusNode,
    this.autofocus = false,
    this.style,
  });

  /// The chips in the order shown: each [Choice]'s value, label and
  /// whether it is enabled.
  final List<Choice<T>> chips;

  /// The values of the chips that are on.
  final Set<T> selected;

  /// Called with the value of the chip pressed; null for a list whose
  /// chips cannot be pressed.
  // ignore: unsafe_variance
  final void Function(T value)? onPressed;

  /// Called with the value of the chip to remove; null for chips without
  /// `×`.
  // ignore: unsafe_variance
  final void Function(T value)? onRemove;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// Over the theme's text on each chip, as [Chip.style].
  final Style? style;

  @override
  State<ChipList<T>> createState() => _ChipListState<T>();
}

final class _ChipListState<T> extends State<ChipList<T>> {
  /// The chip highlighted while the list has the focus; -1 before one is.
  var _cursor = -1;

  /// Where each chip is, as last built.
  var _places = const <({int line, int x, int width})>[];

  List<Choice<T>> get _chips => widget.chips;

  bool get _enabled =>
      (widget.onPressed != null || widget.onRemove != null) &&
      _chips.any((c) => c.enabled);

  /// The enabled chip [step] places on from [from], round; -1 for none.
  int _step(int from, int step) =>
      nextEnabled(_chips.length, from, step, (i) => _chips[i].enabled);

  /// The chip highlighted: [_cursor] while it is in the list and enabled,
  /// the last chip when the list got shorter, else the first enabled one.
  int get _current {
    var h = _cursor;
    if (h >= _chips.length) {
      h = _chips.length - 1;
    }
    if (h >= 0 && _chips[h].enabled) {
      return h;
    }
    return _step(h >= 0 ? h : _chips.length - 1, h >= 0 ? -1 : 1);
  }

  void _move(int to) {
    if (to >= 0 && to != _cursor) {
      setState(() => _cursor = to);
    }
  }

  /// The enabled chip on the nearest row above ([rows] -1) or below (1)
  /// the current one that has one, nearest to its first column; -1 where
  /// there is none.
  int _vertical(int rows) {
    final from = _current;
    if (from < 0 || from >= _places.length) {
      return -1;
    }
    final lines = _places.last.line;
    for (var l = _places[from].line + rows; l >= 0 && l <= lines; l += rows) {
      var best = -1;
      for (var i = 0; i < _places.length && i < _chips.length; i++) {
        if (_places[i].line == l &&
            _chips[i].enabled &&
            (best < 0 ||
                (_places[i].x - _places[from].x).abs() <
                    (_places[best].x - _places[from].x).abs())) {
          best = i;
        }
      }
      if (best >= 0) {
        return best;
      }
    }
    return -1;
  }

  void _press(int i) {
    final onPressed = widget.onPressed;
    if (onPressed != null && i >= 0 && i < _chips.length && _chips[i].enabled) {
      _move(i);
      onPressed(_chips[i].value);
    }
  }

  void _remove(int i) {
    final onRemove = widget.onRemove;
    if (onRemove != null && i >= 0 && i < _chips.length && _chips[i].enabled) {
      _move(i);
      onRemove(_chips[i].value);
    }
  }

  void _tap(int x, int y) {
    for (var i = 0; i < _places.length && i < _chips.length; i++) {
      final p = _places[i];
      if (p.line == y && x >= p.x && x < p.x + p.width) {
        if (!_chips[i].enabled) {
          return;
        }
        // the close mark and the blank after it
        final closeWidth = segmenterOf(context).width(
          Theme.of(context).glyphs.close,
        );
        if (widget.onRemove != null && x >= p.x + p.width - closeWidth - 1) {
          _remove(i);
        } else if (widget.onPressed != null) {
          _press(i);
        } else {
          _move(i);
        }
        return;
      }
    }
  }

  // The keys and their hints, kept while the same callbacks are there: a
  // map built anew each time would be parsed anew by the layer.
  late Map<String, VoidCallback?> _bindings;
  late Map<String, String> _hints;
  var _keysMade = -1; // 1 for pressable, 2 for removable; -1 before any

  void _keysFor({required bool pressable, required bool removable}) {
    final made = (pressable ? 1 : 0) | (removable ? 2 : 0);
    if (_keysMade == made) {
      return;
    }
    _keysMade = made;
    _bindings = {
      'left': () => _move(_step(_current, -1)),
      'right': () => _move(_step(_current, 1)),
      'up': () => _move(_vertical(-1)),
      'down': () => _move(_vertical(1)),
      'home': () => _move(_step(-1, 1)),
      'end': () => _move(_step(_chips.length, -1)),
      if (pressable) 'space': () => _press(_current),
      if (pressable) 'enter': () => _press(_current),
      if (removable) 'delete': () => _remove(_current),
      if (removable) 'backspace': () => _remove(_current),
    };
    _hints = {
      'left': 'previous',
      'right': 'next',
      if (pressable) 'space': 'toggle',
      if (removable) 'delete': 'remove',
    };
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    final current = _current;
    final onPressed = widget.onPressed;
    final onRemove = widget.onRemove;
    final selected = widget.selected;
    _keysFor(pressable: onPressed != null, removable: onRemove != null);
    return Pressable(
      enabled: enabled,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      bindings: _bindings,
      hints: _hints,
      onTap: enabled ? (event) => _tap(event.x, event.y) : null,
      builder: (context, focused) => Semantics(
        nodes: [
          for (var i = 0; i < _chips.length; i++)
            SemanticsNode(
              role: onPressed != null
                  ? SemanticsRole.checkbox
                  : SemanticsRole.listItem,
              label: _chips[i].label,
              state: SemanticsState(
                checked: onPressed != null
                    ? selected.contains(_chips[i].value)
                    : null,
                disabled: !enabled || !_chips[i].enabled,
              ),
              focused: focused && i == current,
            ),
        ],
        child: LayoutBuilder(
          builder: (context, constraints) => _rows(
            segmenterOf(context),
            constraints.maxW,
            enabled: enabled,
            highlight: focused ? current : -1,
            plain:
                AppBinding.maybeOf(context)?.twkApp.terminal.info.plain ??
                false,
          ),
        ),
      ),
    );
  }

  Widget _rows(
    TextSegmenter segmenter,
    int width, {
    required bool enabled,
    required int highlight,
    required bool plain,
  }) {
    final glyphs = Theme.of(context).glyphs;
    final close = widget.onRemove == null ? null : glyphs.close;
    final on = [for (final c in _chips) widget.selected.contains(c.value)];
    final checkMark = '${glyphs.check} ';
    // the blanks, the mark and the × take the room, the label the rest:
    // the same for every chip with a mark, and for every one without
    final aroundMarked = plain
        ? segmenter.width(_chipText('', mark: checkMark, close: close))
        : 0;
    final aroundBare = segmenter.width(_chipText('', mark: '', close: close));
    final labels = <String>[];
    final widths = <int>[];
    for (var i = 0; i < _chips.length; i++) {
      final mark = on[i] && plain ? checkMark : '';
      final around = mark.isEmpty ? aroundBare : aroundMarked;
      final label = fitText(
        segmenter,
        _chips[i].label,
        (width - around).clamp(1, 1 << 30),
        ellipsis: glyphs.ellipsis,
      );
      labels.add(label);
      widths.add(
        segmenter.width(_chipText(label, mark: mark, close: close)),
      );
    }
    _places = _flow(widths, width);
    final lines = <List<Widget>>[];
    for (var i = 0; i < _chips.length; i++) {
      if (_places[i].line == lines.length) {
        lines.add([]);
      }
      lines.last.add(
        // the hidden cursor on the highlighted chip
        ActiveItem(
          active: i == highlight,
          child: Chip(
            labels[i],
            selected: on[i],
            highlighted: i == highlight,
            removable: close != null,
            enabled: enabled && _chips[i].enabled,
            style: widget.style,
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Row(mainAxisSize: MainAxisSize.min, gap: 1, children: line),
      ],
    );
  }
}
