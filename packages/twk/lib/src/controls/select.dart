/// Values chosen from a list that opens under a field and filters as one
/// types: [Select] chooses one, [MultiSelect] any number.
library;

import 'dart:async';

import 'package:twk_core/twk_core.dart'
    show
        Attr,
        CrossAxisAlignment,
        KeyCode,
        KeyEvent,
        KeyKind,
        MainAxisSize,
        Mod,
        TextOverflow,
        TextSegmenter,
        TextWrap;

import '../editing/input_decoration.dart';
import '../editing/text_editing.dart' show TextBoundaries;
import '../focus/focus.dart';
import '../foundation/change_notifier.dart';
import '../foundation/controller_host.dart';
import '../framework/framework.dart';
import '../gestures/gesture_detector.dart';
import '../layout/basic.dart';
import '../layout/box.dart';
import '../layout/flex.dart';
import '../overlay/fuzzy.dart';
import '../overlay/options.dart';
import '../overlay/panel.dart';
import '../overlay/popover.dart';
import '../style/color_mix.dart';
import '../style/style.dart';
import '../text/hit_row.dart' show segmenterOf;
import '../text/widgets.dart';
import 'choice.dart';
import 'pressable.dart';

/// Opens and closes the popup of a [Select], a [MultiSelect] or a
/// `DatePicker` from outside, given to one of them as its `controller`.
///
/// [open] and [close] do as its keys and its mouse do, and [isOpen] says
/// whether it is open. Its
/// listeners are told each time it opens and closes, by the controller or
/// by the widget. One widget at a time has it; one built with it open
/// opens as it is built, and one built in place of the widget that had it
/// goes on with it. A widget that lets go of it, given another controller
/// or none, or gone, with none built in its place, leaves it closed.
///
/// [open] gives the widget the focus too, so that its keys are the
/// popup's: a [Select]'s field, a `DatePicker`'s calendar. A disabled
/// widget, with no `onChanged`, stays closed: [open] is undone at once.
/// An inline [Select], whose list always shows, only says it is open.
///
/// A key that opens the list of a select from anywhere in the app:
///
/// ```dart
/// final popup = PopupController();
/// final app = KeyBindings(
///   {'ctrl+l': popup.open},
///   hints: const {'ctrl+l': 'language'},
///   child: Select<String>(
///     controller: popup,
///     choices: const [Choice('en', 'English'), Choice('uk', 'Ukrainian')],
///     value: 'en',
///     onChanged: (v) => print(v),
///   ),
/// );
/// ```
final class PopupController extends ChangeNotifier {
  /// A controller of a closed popup.
  PopupController();

  var _open = false;

  /// Whether the popup is open.
  bool get isOpen => _open;

  /// Opens the popup, where it is closed.
  void open() => _set(true);

  /// Closes the popup, where it is open.
  void close() => _set(false);

  void _set(bool open) {
    if (open != _open) {
      _open = open;
      notifyListeners();
    }
  }

  // the widget it is given to
  final _hosts = ControllerHost<State>();

  @override
  void dispose() {
    _hosts.dispose();
    super.dispose();
  }
}

/// The state of a widget whose popup a [PopupController] opens and closes:
/// [Select]'s, [MultiSelect]'s and `DatePicker`'s. Not exported.
mixin PopupHostState<W extends StatefulWidget> on State<W> {
  /// Serves [controller], if any, in place of the widget that did; returns
  /// whether it took it over from one.
  bool attachPopup(PopupController? controller) =>
      controller != null && controller._hosts.attach(this) != null;

  /// Lets go of [controller], if any: where no widget takes it over, it
  /// closes after the build.
  void detachPopup(PopupController? controller) =>
      controller?._hosts.detach(this, controller.close);

  /// Whether this widget is the one [controller] is given to: with none,
  /// its own, it is.
  bool servesPopup(PopupController? controller) =>
      controller == null || controller._hosts.isHost(this);

  /// Closes [popup] after the build, while this widget has it: a disabled
  /// widget keeps it closed.
  void closePopupAfterBuild(PopupController popup) =>
      popup._hosts.afterBuild(() {
        final host = popup._hosts.host;
        if (host == null || identical(host, this)) {
          popup.close();
        }
      });
}

/// A drop-down: a field that shows the label of the choice whose value is
/// [value], and opens a list of the [choices] to choose another from.
///
/// The field shows [hint] while no choice is chosen. The list is in a
/// [Popover] under the field, or, [inline], always below it. A choice of
/// a color, held by the app:
///
/// ```dart
/// final color = ValueNotifier<String?>(null);
/// final select = ValueListenableBuilder(
///   valueListenable: color,
///   builder: (context, value, _) => Select<String>(
///     hint: 'color',
///     choices: const [
///       Choice('r', 'Red'),
///       Choice('g', 'Green'),
///       Choice('b', 'Blue'),
///     ],
///     value: value,
///     onChanged: (v) => color.value = v,
///   ),
/// );
/// ```
///
/// The field takes the focus, unless it is disabled, with no [onChanged]:
/// then Tab passes it by and the mouse does nothing to it. Enter, Space,
/// Up or Down while it has the focus opens the list, as does a click on
/// the field, which a second one closes. The list shows the enabled
/// choices; typing, which opens it too, filters them, the query shown in
/// the field in place of the label: those whose labels have its
/// characters in order ([fuzzyMatch]), best first, the characters
/// standing out, or `no match`; Backspace takes the last character off,
/// and Space is typed while the list is open. Up and Down highlight the
/// choice before and after, from the last to the first and back, PageUp
/// and PageDown a window before and after; Enter chooses the one
/// highlighted, as does a click on it, which calls [onChanged] with its
/// value and closes the list. Escape closes it, as does the focus leaving
/// the field and a press outside it; inline, Escape clears the query.
/// Enter is hinted, to open and to choose.
///
/// At most [rows] choices show at once, in the theme's surface and text,
/// the highlighted one in its selection, the popup as [popupLook] says: a
/// panel of the surface, its rows all it has ([PanelLook.raised]), or a
/// [Panel] in a border ([PanelLook.bordered]); opened, the choice chosen
/// is highlighted. The field is one row, a blank, its text and
/// `▾`, as wide as the widest label: a chip of the theme's text over
/// [style], [ThemeData.surface] when null; [focusedStyle] while it has the
/// focus, filled with [ThemeData.primary], its text bold in
/// [ThemeData.onPrimary], when null; [disabledStyle] while disabled,
/// [ThemeData.muted] when null. The hint is in [ThemeData.muted], or a
/// step from [ThemeData.onPrimary] towards the primary color on the
/// primary fill; `▾` is in [arrowStyle] while the field has not the
/// focus, [ThemeData.muted] when null, and stays when the text is cut off
/// with "…". `style: const Style()`, `focusedStyle:
/// theme.primary.merge(const Style(attrs: Attr.bold | Attr.reverse))`,
/// `arrowStyle: const Style()` and `popupLook: PanelLook.bordered` give
/// a plain look: the field without a chip, reversed while focused, the
/// popup in a border.
///
/// With a [decoration] the field is drawn in an [InputDecorator], as
/// Flutter's DropdownButtonFormField is: its label, icon, border and
/// helper around it, the field as wide as the decoration leaves it, with
/// no chip of its own (only [style], where given), its text in the
/// theme's, `▾` at its right edge, [ThemeData.primary] while it has the
/// focus, which the decoration's border shows rather than a primary fill
/// (only [focusedStyle], where given); the list opens right under its
/// border (the line under an [UnderlineInputBorder]), from its left edge
/// and as wide as it, over the helper, or, [inline], in the border. A
/// choice of a language in a box, its label on the box:
///
/// ```dart
/// Select<String>(
///   choices: const [Choice('en', 'English'), Choice('uk', 'Ukrainian')],
///   value: 'en',
///   onChanged: (v) => print(v),
///   decoration: const InputDecoration(
///     labelText: 'Language',
///     border: OutlineInputBorder(),
///   ),
/// )
/// ```
///
/// The popup needs an `Overlay` above, as a [Popover] does. With a
/// [controller], the app opens and closes the list and hears it open and
/// close.
///
/// See also:
///
///  * [MultiSelect], which chooses any number of the choices.
///  * `RadioGroup`, the choices all shown, for a few of them.
final class Select<T> extends StatelessWidget {
  /// A field of the choice of [value] among [choices]; disabled when
  /// [onChanged] is null.
  ///
  /// [rows] is above 0, which it asserts.
  const Select({
    required this.choices,
    required this.value,
    required this.onChanged,
    super.key,
    this.controller,
    this.hint = '',
    this.inline = false,
    this.rows = 8,
    this.focusNode,
    this.autofocus = false,
    this.style,
    this.focusedStyle,
    this.disabledStyle,
    this.arrowStyle,
    this.popupLook = PanelLook.raised,
    this.popupFadeIn = const Duration(milliseconds: 120),
    this.decoration,
  }) : assert(rows > 0, 'rows below 1');

  /// What can be chosen, in the order the list shows them.
  final List<Choice<T>> choices;

  /// The value of the choice chosen; none is when no choice has it.
  final T? value;

  /// Called with the value of the choice chosen; null for a disabled
  /// select.
  // ignore: unsafe_variance
  final void Function(T value)? onChanged;

  /// Opens and closes the list, and says whether it is open; null for
  /// one of its own.
  final PopupController? controller;

  /// What the field shows while no choice is chosen.
  final String hint;

  /// Whether the list is always below the field, rather than in a popup
  /// while open.
  final bool inline;

  /// The most choices shown at once; 8 by default.
  final int rows;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// The field's chip, over the theme's text; [ThemeData.surface] when
  /// null.
  final Style? style;

  /// The field while it has the focus; a fill of [ThemeData.primary] with
  /// the text bold in [ThemeData.onPrimary] when null.
  final Style? focusedStyle;

  /// The field while it is disabled; [ThemeData.muted] when null.
  final Style? disabledStyle;

  /// `▾` while the field has not the focus; [ThemeData.muted] when null.
  final Style? arrowStyle;

  /// How the popup stands out of what is under it: a raised panel by
  /// default.
  final PanelLook popupLook;

  /// How long the popup takes to fade in from what is under it as it
  /// opens, easing out; 120 ms by default, zero for at once.
  final Duration popupFadeIn;

  /// What is drawn around the field ([InputDecorator]), which then has no
  /// chip; null for the chip alone.
  final InputDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    final value = this.value;
    return _Picker<T>(
      choices: choices,
      chosen: {
        for (final c in choices)
          if (c.value == value && value != null) c.value,
      },
      multiple: false,
      onChanged: onChanged == null
          ? null
          : (chosen) => onChanged(chosen.single),
      controller: controller,
      hint: hint,
      inline: inline,
      rows: rows,
      focusNode: focusNode,
      autofocus: autofocus,
      style: style,
      focusedStyle: focusedStyle,
      disabledStyle: disabledStyle,
      arrowStyle: arrowStyle,
      popupLook: popupLook,
      popupFadeIn: popupFadeIn,
      decoration: decoration,
    );
  }
}

/// A [Select] of any number of the [choices]: those whose values are in
/// [values] are selected.
///
/// In the list, each selected choice has `[x]` before its label, the
/// others `[ ]`. Space or a click on one selects or deselects it, calling
/// [onChanged] with the values selected then, and the list stays open;
/// Enter closes it; Space and Enter hinted. The field shows the labels of
/// those selected, apart by commas, or [hint] while none is; typing filters
/// as in a [Select], a blank not among what it types. Everything else is
/// as a [Select]'s.
///
/// ```dart
/// final days = ValueNotifier(<int>{1, 3});
/// final select = ValueListenableBuilder(
///   valueListenable: days,
///   builder: (context, values, _) => MultiSelect<int>(
///     hint: 'days',
///     choices: const [Choice(1, 'Mo'), Choice(2, 'Tu'), Choice(3, 'We')],
///     values: values,
///     onChanged: (v) => days.value = v,
///   ),
/// );
/// ```
final class MultiSelect<T> extends StatelessWidget {
  /// A field of the choices of [values] among [choices]; disabled when
  /// [onChanged] is null.
  ///
  /// [rows] is above 0, which it asserts.
  const MultiSelect({
    required this.choices,
    required this.values,
    required this.onChanged,
    super.key,
    this.controller,
    this.hint = '',
    this.inline = false,
    this.rows = 8,
    this.focusNode,
    this.autofocus = false,
    this.style,
    this.focusedStyle,
    this.disabledStyle,
    this.arrowStyle,
    this.popupLook = PanelLook.raised,
    this.popupFadeIn = const Duration(milliseconds: 120),
    this.decoration,
  }) : assert(rows > 0, 'rows below 1');

  /// What can be selected, in the order the list shows them.
  final List<Choice<T>> choices;

  /// The values of the choices selected.
  final Set<T> values;

  /// Called with the values selected once one is selected or deselected;
  /// null for a disabled select.
  // ignore: unsafe_variance
  final void Function(Set<T> values)? onChanged;

  /// See [Select.controller].
  final PopupController? controller;

  /// What the field shows while none is selected.
  final String hint;

  /// See [Select.inline].
  final bool inline;

  /// See [Select.rows].
  final int rows;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// See [Select.style].
  final Style? style;

  /// See [Select.focusedStyle].
  final Style? focusedStyle;

  /// See [Select.disabledStyle].
  final Style? disabledStyle;

  /// See [Select.arrowStyle].
  final Style? arrowStyle;

  /// See [Select.popupLook].
  final PanelLook popupLook;

  /// See [Select.popupFadeIn].
  final Duration popupFadeIn;

  /// See [Select.decoration].
  final InputDecoration? decoration;

  @override
  Widget build(BuildContext context) => _Picker<T>(
    choices: choices,
    chosen: values,
    multiple: true,
    onChanged: onChanged,
    controller: controller,
    hint: hint,
    inline: inline,
    rows: rows,
    focusNode: focusNode,
    autofocus: autofocus,
    style: style,
    focusedStyle: focusedStyle,
    disabledStyle: disabledStyle,
    arrowStyle: arrowStyle,
    popupLook: popupLook,
    popupFadeIn: popupFadeIn,
    decoration: decoration,
  );
}

/// What a [Select] and a [MultiSelect] are: a field and the list of the
/// choices, [chosen] those of them chosen.
final class _Picker<T> extends StatefulWidget {
  const _Picker({
    required this.choices,
    required this.chosen,
    required this.multiple,
    required this.onChanged,
    required this.controller,
    required this.hint,
    required this.inline,
    required this.rows,
    required this.focusNode,
    required this.autofocus,
    required this.style,
    required this.focusedStyle,
    required this.disabledStyle,
    required this.arrowStyle,
    required this.popupLook,
    required this.popupFadeIn,
    required this.decoration,
  });

  final List<Choice<T>> choices;
  final Set<T> chosen;
  final bool multiple;

  /// Called with what is chosen once it changes.
  // ignore: unsafe_variance
  final void Function(Set<T> chosen)? onChanged;

  final PopupController? controller;
  final String hint;
  final bool inline;
  final int rows;
  final FocusNode? focusNode;
  final bool autofocus;
  final Style? style;
  final Style? focusedStyle;
  final Style? disabledStyle;
  final Style? arrowStyle;
  final PanelLook popupLook;
  final Duration popupFadeIn;
  final InputDecoration? decoration;

  @override
  State<_Picker<T>> createState() => _PickerState<T>();
}

/// A choice the query matches: its index in the choices, and where its
/// characters are in the label.
typedef _Match = ({int index, List<int> marks});

final class _PickerState<T> extends State<_Picker<T>>
    with PopupHostState<_Picker<T>> {
  // whether the list is open, as the controller said last
  var _open = false;
  var _query = '';

  PopupController? _ownPopup;
  FocusNode? _ownNode;

  PopupController get _popup =>
      widget.controller ?? (_ownPopup ??= PopupController());

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  // the value of the choice highlighted, which it stays on as the choices
  // change, and the first match shown
  Object? _highlighted = _none;
  var _top = 0;

  static const _none = Object();

  // the choices the query matches, as built last
  var _matches = const <_Match>[];

  bool get _enabled => widget.onChanged != null;

  bool get _shown => _open || widget.inline;

  /// The enabled choices the query matches, best first, the others in
  /// their order.
  List<_Match> _match() {
    final scored = <(int, FuzzyMatch)>[];
    final choices = widget.choices;
    for (var i = 0; i < choices.length; i++) {
      if (choices[i].enabled) {
        if (fuzzyMatch(_query, choices[i].label) case final m?) {
          scored.add((i, m));
        }
      }
    }
    scored.sort(
      (a, b) =>
          a.$2.score != b.$2.score ? b.$2.score - a.$2.score : a.$1 - b.$1,
    );
    return [for (final (i, m) in scored) (index: i, marks: m.positions)];
  }

  /// The match of the choice highlighted; -1 for none.
  int get _at {
    for (var k = 0; k < _matches.length; k++) {
      if (widget.choices[_matches[k].index].value == _highlighted) {
        return k;
      }
    }
    return -1;
  }

  @override
  void initState() {
    super.initState();
    _popup.addListener(_popupChanged);
    final tookOver = attachPopup(widget.controller);
    _open = _popup.isOpen && _enabled;
    _settle(tookOver: tookOver);
  }

  @override
  void didUpdateWidget(_Picker<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      (oldWidget.controller ?? _ownPopup)?.removeListener(_popupChanged);
      detachPopup(oldWidget.controller);
      _popup.addListener(_popupChanged);
      final tookOver = attachPopup(widget.controller);
      // as the new one says, built now
      _open = _popup.isOpen && _enabled;
      if (!_open) {
        _query = '';
      }
      _settle(tookOver: tookOver);
    } else if (_open && !_enabled) {
      _open = false;
      _query = '';
      _settle();
    }
  }

  /// After the build: the controller closed while this widget is disabled;
  /// the field focused when this widget [tookOver] the list open from the
  /// one built before it, so that its keys are the list's.
  void _settle({bool tookOver = false}) {
    if (_popup.isOpen && !_enabled) {
      closePopupAfterBuild(_popup);
    } else if (tookOver && _open) {
      scheduleMicrotask(() {
        if (mounted && _open) {
          _node.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _popup.removeListener(_popupChanged);
    detachPopup(widget.controller);
    _ownPopup?.dispose();
    _ownNode?.dispose();
    super.dispose();
  }

  /// Opens or closes the list as the controller says: a disabled one stays
  /// closed. Nothing while another widget has the controller.
  void _popupChanged() {
    if (!servesPopup(widget.controller)) {
      return;
    }
    final open = _popup.isOpen;
    if (open && !_enabled) {
      _popup.close();
      return;
    }
    if (open == _open) {
      return;
    }
    setState(() {
      _open = open;
      _query = '';
      if (open) {
        _highlighted = _none;
        _top = 0;
      }
    });
    if (open) {
      _node.requestFocus();
    }
  }

  void _openList() => _popup.open();

  void _close() {
    if (!servesPopup(widget.controller)) {
      return;
    }
    if (_popup.isOpen) {
      _popup.close();
    } else if (_query.isNotEmpty) {
      setState(() => _query = '');
    }
  }

  void _toggleOpen() => _open ? _close() : _openList();

  /// Highlights the match [steps] on from the highlighted one: round for a
  /// step of one, else stopping at the ends.
  void _step(int steps) {
    final n = _matches.length;
    if (n == 0) {
      return;
    }
    final at = _at;
    var to = at < 0 ? (steps > 0 ? 0 : n - 1) : at + steps;
    if (steps.abs() == 1) {
      to %= n;
    } else {
      to = to < 0 ? 0 : (to >= n ? n - 1 : to);
    }
    setState(() => _highlighted = widget.choices[_matches[to].index].value);
  }

  void _up() => _step(-1);

  void _down() => _step(1);

  void _pageUp() => _step(-widget.rows);

  void _pageDown() => _step(widget.rows);

  /// Chooses the choice at [index]: in a [MultiSelect], selects or
  /// deselects it.
  void _choose(int index) {
    final onChanged = widget.onChanged;
    if (onChanged == null || index < 0) {
      return;
    }
    final value = widget.choices[index].value;
    if (!widget.multiple) {
      _close();
      onChanged({value});
      return;
    }
    setState(() => _highlighted = value);
    final chosen = Set.of(widget.chosen);
    if (!chosen.remove(value)) {
      chosen.add(value);
    }
    onChanged(chosen);
  }

  void _enter() => widget.multiple ? _close() : _choose(_highlightedIndex);

  void _space() => _choose(_highlightedIndex);

  /// The index in the choices of the one highlighted; -1 for none.
  int get _highlightedIndex {
    final at = _at;
    return at < 0 ? -1 : _matches[at].index;
  }

  void _backspace() => _type(_query.substring(0, _lastStart(_query)));

  void _clear() => _type('');

  void _type(String query) {
    if (!_open && !widget.inline) {
      _openList();
    }
    setState(() {
      _query = query;
      _highlighted = _none;
      _top = 0;
    });
  }

  /// Where the last character of [text] starts.
  static int _lastStart(String text) =>
      text.characterOffset(text.characterIndexAt(text.length) - 1);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event.kind == KeyKind.release ||
        event.code != KeyCode.char ||
        (event.modifiers & ~Mod.shift) != 0 ||
        (event.char == ' ' && (widget.multiple || !_shown))) {
      return KeyEventResult.ignored;
    }
    _type(_query + event.char);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    _matches = shown ? _match() : const [];
    if (shown && _at < 0) {
      _highlighted = _firstHighlighted();
    }
    final multiple = widget.multiple;
    final bindings = <String, void Function()?>{
      if (!shown) ...{
        'enter': _openList,
        'space': _openList,
        'up': _openList,
        'down': _openList,
      } else ...{
        'up': _up,
        'down': _down,
        'pageup': _pageUp,
        'pagedown': _pageDown,
        if (multiple) 'space': _space,
        'enter': _enter,
        if (_query.isNotEmpty) 'backspace': _backspace,
        if (_query.isNotEmpty && widget.inline) 'escape': _clear,
      },
    };
    final hints = !shown
        ? const {'enter': 'open'}
        : multiple
        ? const {'space': 'toggle', 'enter': 'done'}
        : const {'enter': 'choose'};
    final field = Pressable(
      enabled: _enabled,
      focusNode: _node,
      autofocus: widget.autofocus,
      bindings: bindings,
      hints: hints,
      onKeyEvent: _onKey,
      onTap: widget.inline || !_enabled ? null : (_) => _toggleOpen(),
      builder: !widget.inline
          ? _field
          : (context, focused) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _field(context, focused),
                _list(context, highlight: focused),
              ],
            ),
    );
    final decoration = widget.decoration;
    if (widget.inline) {
      return decoration == null
          ? field
          : decoratedField(decoration, enabled: _enabled, child: field);
    }
    final theme = Theme.of(context);
    Widget popover(Widget child) => Popover(
      open: _open,
      onDismiss: _close,
      fadeIn: widget.popupFadeIn,
      // in a decoration, as wide as its border
      matchAnchorWidth: decoration != null,
      popover: switch (widget.popupLook) {
        PanelLook.raised => Box(
          style: theme.surface.merge(theme.text),
          child: _list(context),
        ),
        PanelLook.bordered => Panel(
          look: PanelLook.bordered,
          shadow: false,
          child: _list(context),
        ),
      },
      child: child,
    );
    if (decoration == null) {
      return popover(field);
    }
    // under the decoration's border, from its left edge
    return decoratedField(
      decoration,
      enabled: _enabled,
      child: field,
      aroundBox: popover,
    );
  }

  /// The choice highlighted as the list opens or the query changes: the
  /// first chosen one among the matches without a query, else the best
  /// match; [_none] for none.
  Object? _firstHighlighted() {
    if (_matches.isEmpty) {
      return _none;
    }
    final choices = widget.choices;
    if (_query.isEmpty) {
      for (final m in _matches) {
        if (widget.chosen.contains(choices[m.index].value)) {
          return choices[m.index].value;
        }
      }
    }
    return choices[_matches.first.index].value;
  }

  /// The columns of the widest label as [segmenter] measures them, and of
  /// its mark in a [MultiSelect].
  int _labelWidth(TextSegmenter segmenter) {
    var w = segmenter.width(widget.hint);
    for (final c in widget.choices) {
      final cw = segmenter.width(c.label);
      if (cw > w) {
        w = cw;
      }
    }
    return w + (widget.multiple ? 4 : 0);
  }

  Widget _field(BuildContext context, bool focused) {
    final theme = Theme.of(context);
    final enabled = _enabled;
    final given = widget.focusedStyle;
    // in a decoration: no chip, the focus the border's
    final decorated = widget.decoration != null;
    final filled = enabled && focused && given == null && !decorated;
    var row = theme.text.merge(
      widget.style ?? (decorated ? _plain : theme.surface),
    );
    if (!enabled) {
      row = row.merge(widget.disabledStyle ?? theme.muted);
    } else if (focused && (given != null || !decorated)) {
      row = row.merge(
        given ??
            Style(
              fg: theme.onPrimary.fg,
              bg: theme.primary.fg,
              attrs: Attr.bold,
            ),
      );
    }
    final chosen = [
      for (final c in widget.choices)
        if (widget.chosen.contains(c.value)) c.label,
    ];
    final String text;
    var muted = false;
    if (_query.isNotEmpty) {
      text = _query;
    } else if (chosen.isNotEmpty) {
      text = chosen.join(', ');
    } else {
      text = widget.hint;
      muted = enabled;
    }
    final segmenter = segmenterOf(context);
    final pad = _labelWidth(segmenter) - segmenter.width(text);
    final Style shown;
    if (!muted) {
      shown = _plain;
    } else if (filled) {
      // the hint on the primary fill, a step towards it; dim where the
      // colors cannot be mixed
      final fg = mixRgb(theme.onPrimary.fg, theme.primary.fg, 0.3);
      shown = fg != null
          ? Style(fg: fg, attrsOff: Attr.bold)
          : const Style(attrs: Attr.dim, attrsOff: Attr.bold);
    } else {
      shown = theme.muted;
    }
    final arrow = filled
        ? const Style(attrsOff: Attr.bold)
        : enabled && !focused
        ? widget.arrowStyle ?? theme.muted
        : enabled && decorated
        ? theme.primary
        : _plain;
    if (decorated) {
      // as wide as the decoration leaves it, ▾ at the right edge
      return Box(
        style: row,
        child: DefaultTextStyle(
          style: row,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: shown,
                  wrap: TextWrap.none,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              Text(' ▾', style: arrow, wrap: TextWrap.none),
            ],
          ),
        ),
      );
    }
    return Box(
      style: row,
      child: DefaultTextStyle(
        style: row,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                ' $text${pad > 0 ? ' ' * pad : ''}',
                style: shown,
                wrap: TextWrap.none,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            Text(' ▾', style: arrow, wrap: TextWrap.none),
          ],
        ),
      ),
    );
  }

  /// The list of the matches, the highlighted one shown so while
  /// [highlight]; as wide as the widest label, wider where its popover
  /// asks it to be.
  Widget _list(BuildContext context, {bool highlight = true}) {
    final matches = _matches;
    final width = _labelWidth(segmenterOf(context)) + 2;
    if (matches.isEmpty) {
      final theme = Theme.of(context);
      return SizedBox(
        width: width,
        child: Text(
          ' no match',
          style: theme.surface.merge(theme.muted),
          wrap: TextWrap.none,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    final rows = widget.rows;
    final at = _at < 0 ? 0 : _at;
    if (at < _top) {
      _top = at;
    } else if (at >= _top + rows) {
      _top = at - rows + 1;
    }
    final most = matches.length - rows;
    if (_top > most) {
      _top = most > 0 ? most : 0;
    }
    final end = _top + rows < matches.length ? _top + rows : matches.length;
    final choices = widget.choices;
    final top = _top;
    return GestureDetector(
      onTap: (event) {
        final k = top + event.y;
        if (k >= 0 && k < matches.length) {
          _choose(matches[k].index);
        }
      },
      child: SizedBox(
        width: width,
        child: OptionList(
          options: [
            for (var k = top; k < end; k++)
              _option(choices[matches[k].index], matches[k].marks),
          ],
          highlighted: highlight ? at - top : -1,
          rows: rows,
        ),
      ),
    );
  }

  Option _option(Choice<T> choice, List<int> marks) {
    if (!widget.multiple) {
      return Option(choice.label, marks: marks);
    }
    final on = widget.chosen.contains(choice.value);
    return Option(
      '${on ? '[x]' : '[ ]'} ${choice.label}',
      marks: [for (final m in marks) m + 4],
    );
  }
}

const _plain = Style();
