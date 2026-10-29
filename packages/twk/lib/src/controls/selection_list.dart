/// A list whose items are selected by their keys: [SelectionList], and the
/// [SelectionController] that holds what is selected and where its cursor
/// is.
library;

import 'dart:collection';

import 'package:twk_core/twk_core.dart' show Attr, TextWrap;

import '../focus/focus.dart';
import '../foundation/change_notifier.dart';
import '../framework/framework.dart';
import '../gestures/gesture_detector.dart';
import '../layout/box.dart';
import '../layout/flex.dart';
import '../scroll/list_view.dart';
import '../style/style.dart';
import '../text/widgets.dart';
import 'pressable.dart';

/// Holds which items of a [SelectionList] are [selected], and the one its
/// [cursor] is on, by their keys.
///
/// Held by their keys, they stay with their items as the list changes
/// around them. In a single selection, at most one is selected; with
/// [multiple], any number. Its listeners are told of each change.
///
/// A list of files, two of them selected, and a key that selects them all:
///
/// ```dart
/// final files = ['a.txt', 'b.txt', 'c.txt'];
/// final selection = SelectionController<String>(
///   multiple: true,
///   selected: ['a.txt', 'c.txt'],
/// );
/// final list = KeyBindings(
///   {'ctrl+a': () => selection.selectAll(files)},
///   child: SelectionList<String>(
///     controller: selection,
///     itemCount: files.length,
///     keyOf: (i) => files[i],
///     itemBuilder: (context, i) => Text(files[i]),
///   ),
/// );
/// ```
final class SelectionController<K> extends ChangeNotifier {
  /// A selection of [selected], the cursor on the item whose key is
  /// [cursor]; any number of them with [multiple], else one at most, which
  /// it asserts.
  SelectionController({
    this.multiple = false,
    Iterable<K> selected = const [],
    this._cursor,
  }) : _selected = LinkedHashSet.of(selected),
       assert(
         multiple || selected.length <= 1,
         'more than one selected in a single selection',
       );

  /// Whether any number of items can be selected, rather than one.
  final bool multiple;

  final LinkedHashSet<K> _selected;
  K? _cursor;

  /// The keys selected, in the order they were.
  Set<K> get selected => UnmodifiableSetView(_selected);

  /// The key of the item the cursor is on; null puts it on the item
  /// selected in a single selection, else on the first item.
  K? get cursor => _cursor;

  set cursor(K? key) {
    if (key != _cursor) {
      _cursor = key;
      notifyListeners();
    }
  }

  /// Whether [key] is selected.
  bool isSelected(K key) => _selected.contains(key);

  /// Selects [key]: in a single selection, in place of the one selected.
  void select(K key) {
    if (_selected.contains(key) && (multiple || _selected.length == 1)) {
      return;
    }
    if (!multiple) {
      _selected.clear();
    }
    _selected.add(key);
    notifyListeners();
  }

  /// Selects [keys] as well, in a multiple selection.
  void selectAll(Iterable<K> keys) {
    assert(multiple, 'selectAll in a single selection');
    final before = _selected.length;
    _selected.addAll(keys);
    if (_selected.length != before) {
      notifyListeners();
    }
  }

  /// Deselects [key].
  void deselect(K key) {
    if (_selected.remove(key)) {
      notifyListeners();
    }
  }

  /// Selects [key] if it is not, deselects it if it is.
  void toggle(K key) => isSelected(key) ? deselect(key) : select(key);

  /// Deselects all.
  void clear() {
    if (_selected.isNotEmpty) {
      _selected.clear();
      notifyListeners();
    }
  }

  @override
  String toString() => 'SelectionController($_selected, cursor $_cursor)';
}

/// A list of [itemCount] items to select one of, or any number with a
/// multiple [controller], by the keys and the mouse.
///
/// The items are built as a [ListView.builder] builds them, and selected
/// by their keys ([keyOf]) in [controller]: what is selected and the
/// cursor stay with the items they are on as items are added, removed and
/// moved. The cursor's item gone, the cursor goes to
/// the item at its place, the last one when the list got shorter.
///
/// While it has the focus, Up and Down move the cursor to the enabled item
/// before and after it, PageUp and PageDown a window of rows, Home and End
/// to the first and the last; the list scrolls to show it. In a single
/// selection the item the cursor moves to is selected; in a multiple one,
/// Space selects or deselects the item the cursor is on, Space hinted.
/// Enter calls [onSubmitted] with its key. An item clicked takes the
/// cursor, and is selected, or selected or deselected in a multiple
/// selection; the wheel scrolls the list.
///
/// Each item is what [itemBuilder] builds after a column for a bar `▎`
/// (none without [bar]), in a
/// multiple selection after a mark too, `[x]` for one selected and `[ ]`
/// for the others, as a `Checkbox` draws it: the brackets in
/// [bracketStyle], [ThemeData.muted] when null, the `x` in the theme's
/// primary color in bold. The bar shows on the cursor's row while the list
/// has the focus, in [ThemeData.primary], and on the item selected in a
/// single selection while it has not, in [ThemeData.muted]. An item for
/// which [itemEnabled] is false is passed by and cannot be clicked;
/// disabled, the list takes neither the focus, which Tab passes by, nor
/// the mouse. Without a [controller], the list has a single selection of
/// its own. It takes all the room it is given, which must be bounded.
///
/// The styles, each merged over those before it and the theme's text,
/// under the items' own: [style] for an item; [selectedStyle] for one
/// selected, bold in a single selection when null; [cursorStyle] for the
/// cursor's while the list has the focus, [ThemeData.selection] when
/// null; [idleStyle] for the one selected in a single selection while the
/// list has not the focus, [ThemeData.selectionIdle] when null;
/// [disabledStyle] for one that cannot be selected, [ThemeData.muted] when
/// null. `bar: false`, `selectedStyle: theme.primary`, `idleStyle: const
/// Style()` and `bracketStyle: const Style()` give a plain look: no bar,
/// the item selected in the primary color, marks all in one color.
///
/// A list of servers to connect to, the one picked submitted by Enter:
///
/// ```dart
/// const servers = ['alpha', 'beta', 'gamma'];
/// final list = SelectionList<String>(
///   autofocus: true,
///   itemCount: servers.length,
///   keyOf: (i) => servers[i],
///   itemBuilder: (context, i) => Text(servers[i]),
///   onSubmitted: (server) => print('connecting to $server'),
/// );
/// ```
///
/// See also:
///
///  * [SelectionController], what is selected and where the cursor is.
///  * [ListView], a list without a selection.
final class SelectionList<K> extends StatefulWidget {
  /// A list of [itemCount] items, at least 0, which it asserts.
  const SelectionList({
    required this.itemCount,
    required this.keyOf,
    required this.itemBuilder,
    super.key,
    this.controller,
    this.onSubmitted,
    this.itemEnabled,
    this.enabled = true,
    this.itemExtent,
    this.focusNode,
    this.autofocus = false,
    this.style,
    this.selectedStyle,
    this.cursorStyle,
    this.idleStyle,
    this.disabledStyle,
    this.bracketStyle,
    this.bar = true,
  }) : assert(itemCount >= 0, 'a count of 0 items or more');

  /// How many items the list has.
  final int itemCount;

  /// The key of an item, by its index: one no other item has.
  final K Function(int index) keyOf;

  /// Builds an item, by its index, as it comes into view.
  final IndexedWidgetBuilder itemBuilder;

  /// What is selected and where the cursor is; a single selection of its
  /// own when null.
  final SelectionController<K>? controller;

  /// Called with the key of the cursor's item on Enter; null leaves Enter
  /// to the nodes above.
  // ignore: unsafe_variance
  final void Function(K key)? onSubmitted;

  /// Whether an item, by its index, can be selected; null for all.
  final bool Function(int index)? itemEnabled;

  /// Whether the list takes the focus and the mouse.
  final bool enabled;

  /// See [ListView.itemExtent].
  final int? itemExtent;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// An item, over the theme's text.
  final Style? style;

  /// An item selected; bold in a single selection when null.
  final Style? selectedStyle;

  /// The cursor's item while the list has the focus;
  /// [ThemeData.selection] when null.
  final Style? cursorStyle;

  /// The item selected in a single selection while the list has not the
  /// focus; [ThemeData.selectionIdle] when null.
  final Style? idleStyle;

  /// An item that cannot be selected; [ThemeData.muted] when null.
  final Style? disabledStyle;

  /// The brackets of the marks of a multiple selection; [ThemeData.muted]
  /// when null.
  final Style? bracketStyle;

  /// Whether a column before the items shows a bar `▎` on the cursor's
  /// row.
  final bool bar;

  @override
  State<SelectionList<K>> createState() => _SelectionListState<K>();
}

final class _SelectionListState<K> extends State<SelectionList<K>> {
  SelectionController<K>? _own;
  final _list = ListController();

  // where the cursor's key was found last, which it is looked for from
  var _hint = 0;

  // the cursor's item and whether the list has the focus, as built last
  var _cursorAt = -1;
  var _focused = false;

  SelectionController<K> get _controller =>
      widget.controller ?? (_own ??= SelectionController<K>());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(SelectionList<K> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      (oldWidget.controller ?? _own)?.removeListener(_changed);
      _controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _own?.dispose();
    _list.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  bool _enabled(int index) => widget.itemEnabled?.call(index) ?? true;

  /// The index of [key], looked for from where it was last; -1 if no item
  /// has it.
  int _find(K key) {
    final n = widget.itemCount;
    final keyOf = widget.keyOf;
    final from = _hint < n ? _hint : n - 1;
    for (var d = 0; from - d >= 0 || from + d < n; d++) {
      if (from + d < n && keyOf(from + d) == key) {
        return from + d;
      }
      if (d > 0 && from - d >= 0 && keyOf(from - d) == key) {
        return from - d;
      }
    }
    return -1;
  }

  /// The enabled item nearest [index] going by [step], or the other way
  /// when there is none; -1 for none.
  int _enabledFrom(int index, int step) {
    final n = widget.itemCount;
    for (var i = index; i >= 0 && i < n; i += step) {
      if (_enabled(i)) {
        return i;
      }
    }
    for (var i = index - step; i >= 0 && i < n; i -= step) {
      if (_enabled(i)) {
        return i;
      }
    }
    return -1;
  }

  /// The item the cursor is on; -1 in an empty list.
  int _cursor() {
    final n = widget.itemCount;
    if (n == 0) {
      return -1;
    }
    final c = _controller;
    final key = c.cursor ?? (c.multiple ? null : c.selected.firstOrNull);
    if (key != null) {
      final at = _find(key);
      if (at >= 0) {
        return _hint = at;
      }
      if (c.cursor != null) {
        // its item is gone: the one at its place
        return _enabledFrom(_hint < n ? _hint : n - 1, 1);
      }
    }
    return _enabledFrom(0, 1);
  }

  /// Puts the cursor on [index], which in a single selection selects it,
  /// and scrolls the list to show it.
  void _moveTo(int index) {
    if (index < 0) {
      return;
    }
    final key = widget.keyOf(index);
    final c = _controller;
    _hint = index;
    c.cursor = key;
    if (!c.multiple) {
      c.select(key);
    }
    _list.ensureIndexVisible(index);
  }

  void _by(int rows) {
    final from = _cursor();
    if (from < 0) {
      return;
    }
    final n = widget.itemCount;
    final step = rows < 0 ? -1 : 1;
    var to = from + rows;
    to = to < 0 ? 0 : (to >= n ? n - 1 : to);
    // the first enabled one from [to] on, else the last before it
    for (var i = to; i >= 0 && i < n; i += step) {
      if (_enabled(i)) {
        _moveTo(i);
        return;
      }
    }
    for (var i = to - step; (i - from) * step > 0; i -= step) {
      if (_enabled(i)) {
        _moveTo(i);
        return;
      }
    }
  }

  void _up() => _by(-1);

  void _down() => _by(1);

  int get _page {
    final rows = _list.hasClients ? _list.position.viewportExtent : 1;
    final per = rows ~/ (widget.itemExtent ?? 1);
    return per > 1 ? per : 1;
  }

  void _pageUp() => _by(-_page);

  void _pageDown() => _by(_page);

  void _home() => _moveTo(_enabledFrom(0, 1));

  void _end() => _moveTo(_enabledFrom(widget.itemCount - 1, -1));

  void _toggle() {
    final at = _cursor();
    if (at >= 0) {
      final key = widget.keyOf(at);
      _controller
        ..cursor = key
        ..toggle(key);
    }
  }

  void _submit() {
    final at = _cursor();
    if (at >= 0) {
      widget.onSubmitted?.call(widget.keyOf(at));
    }
  }

  void _tap(int index) {
    final key = widget.keyOf(index);
    final c = _controller;
    _hint = index;
    c.cursor = key;
    if (c.multiple) {
      c.toggle(key);
    } else {
      c.select(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final multiple = _controller.multiple;
    return Pressable(
      enabled: widget.enabled,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      bindings: {
        'up': _up,
        'down': _down,
        'pageup': _pageUp,
        'pagedown': _pageDown,
        'home': _home,
        'end': _end,
        if (multiple) 'space': _toggle,
        if (widget.onSubmitted != null) 'enter': _submit,
      },
      hints: multiple ? const {'space': 'toggle'} : const {},
      builder: (context, focused) {
        _focused = focused;
        _cursorAt = _cursor();
        return ListView.builder(
          itemCount: widget.itemCount,
          itemBuilder: _item,
          itemExtent: widget.itemExtent,
          controller: _list,
          canRequestFocus: false,
        );
      },
    );
  }

  Widget _item(BuildContext context, int index) {
    final theme = Theme.of(context);
    final key = widget.keyOf(index);
    final c = _controller;
    final multiple = c.multiple;
    final selected = c.isSelected(key);
    final enabled = widget.enabled && _enabled(index);
    var s = theme.text.merge(widget.style ?? const Style());
    // the bar's color on this row; null for none
    Style? bar;
    if (!enabled) {
      s = s.merge(widget.disabledStyle ?? theme.muted);
    } else {
      if (selected) {
        s = s.merge(widget.selectedStyle ?? (multiple ? _plain : _bold));
      }
      if (_focused && index == _cursorAt) {
        s = s.merge(widget.cursorStyle ?? theme.selection);
        bar = theme.primary;
      } else if (!_focused && !multiple && selected) {
        s = s.merge(widget.idleStyle ?? theme.selectionIdle);
        bar = theme.muted;
      }
    }
    final item = widget.itemBuilder(context, index);
    final column = widget.bar;
    final Widget row;
    if (!column && !multiple) {
      row = item;
    } else {
      final brackets = enabled
          ? widget.bracketStyle ?? theme.muted
          : const Style();
      row = Row(
        children: [
          if (column)
            Text(
              bar == null ? ' ' : '▎',
              style: bar?.merge(_unbold) ?? _plain,
              wrap: TextWrap.none,
            ),
          if (multiple)
            Text.rich(
              [
                Span('[', brackets),
                Span(selected ? 'x' : ' ', enabled ? markStyle(theme) : _plain),
                Span(']', brackets),
                const Span(' '),
              ],
              wrap: TextWrap.none,
            ),
          Expanded(child: item),
        ],
      );
    }
    return GestureDetector(
      key: ValueKey<K>(key),
      onTap: enabled ? (_) => _tap(index) : null,
      // the hidden cursor on the cursor's row
      child: ActiveItem(
        active: index == _cursorAt,
        child: Box(
          style: s,
          child: DefaultTextStyle(style: s, child: row),
        ),
      ),
    );
  }
}

const _plain = Style();
const _bold = Style(attrs: Attr.bold);
const _unbold = Style(attrsOff: Attr.bold);
