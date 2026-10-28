/// A number typed in a field or stepped: [NumberInput]; and what it shares
/// with a `DatePicker`, a value typed in a field ([TypedInputState]).
library;

import 'package:twk_core/twk_core.dart' show KeyCode, KeyEvent, KeyKind;

import '../editing/text_editing.dart';
import '../editing/text_field.dart';
import '../focus/focus.dart';
import '../foundation/change_notifier.dart';
import '../framework/framework.dart';
import '../gestures/mouse.dart';
import '../layout/flex.dart';
import '../style/style.dart';
import '../text/widgets.dart';
import 'field_styles.dart';

/// A field for a number from [min] to [max], typed, or stepped by [step]
/// with the keys, the wheel and the arrows `▴▾` after it.
///
/// It shows [value] with [decimals] digits after the point. A quantity
/// from 1 to 99, held by the app:
///
/// ```dart
/// final quantity = ValueNotifier(1.0);
/// final input = ValueListenableBuilder(
///   valueListenable: quantity,
///   builder: (context, value, _) => NumberInput(
///     value: value,
///     min: 1,
///     max: 99,
///     onChanged: (v) => quantity.value = v,
///   ),
/// );
/// ```
///
/// The text typed is taken as Enter is pressed, which goes on to the nodes
/// above (a `Form` moves to the next field), and as the focus leaves the
/// field: a number, rounded to [decimals] digits, within the bounds as it
/// is and beyond them as the nearest bound; text that is no number gives
/// way to the value. Meanwhile the field shows such text in [errorStyle],
/// [ThemeData.error] when null, and Escape puts the value back. Taken out
/// of the tree, the field takes nothing.
///
/// While it has the focus, Up takes the value a step up and Down a step
/// down, Page Up and Page Down ten steps, from the number typed, if one
/// is; they stop at [min] and [max]. The wheel steps as Up and Down while
/// it has the focus, and goes to the views around it while it has not. Up
/// and Down are hinted. A press of the left button on the field focuses
/// it; on `▴` and `▾` it steps the value up and down too.
///
/// Each calls [onChanged] with the value it is to take, once that is
/// another; the app builds it with that one, and the field shows it. Keys
/// that come before the app builds it again step from the value the last
/// one gave. Disabled with no [onChanged]: then it is muted, and takes
/// neither the focus, which Tab passes by, nor the mouse.
///
/// A row as wide as it may be, the field a `TextField` (the keys that edit
/// it are its), in [style] over the theme's surface and text; where its
/// width is not bounded, as wide as its text. While it has the focus the
/// field is in [focusedStyle], [ThemeData.selection] when null, and then
/// shows its selection a step towards [ThemeData.primary]. `▴▾` are in
/// [ThemeData.primary] while the field has the focus, in [arrowStyle]
/// while it has not ([ThemeData.muted] when null), and [ThemeData.muted]
/// while it is disabled. `focusedStyle: const Style()` and `arrowStyle:
/// theme.primary` give a plain look, a field that shows the focus by the
/// caret alone.
///
/// See also:
///
///  * `Slider`, a number picked along a track.
///  * `DatePicker`, a date typed or stepped the same way.
final class NumberInput extends StatefulWidget {
  /// A field for [value], which [onChanged] changes; disabled when that is
  /// null.
  ///
  /// It asserts that [min] is not above [max], that [step] is above 0 and
  /// that [decimals] is from 0 to 20.
  const NumberInput({
    required this.value,
    required this.onChanged,
    super.key,
    this.min,
    this.max,
    this.step = 1,
    this.decimals = 0,
    this.focusNode,
    this.autofocus = false,
    this.style,
    this.focusedStyle,
    this.arrowStyle,
    this.errorStyle,
  }) : assert(min == null || max == null || min <= max, 'min above max'),
       assert(step > 0, 'step not above 0'),
       assert(decimals >= 0 && decimals <= 20, 'decimals not from 0 to 20');

  /// The number shown.
  final double value;

  /// Called with the number the field is to take; null for a disabled
  /// field.
  final void Function(double value)? onChanged;

  /// The least number it takes; null for no bound.
  final double? min;

  /// The greatest number it takes; null for no bound.
  final double? max;

  /// What Up and Down add and take away.
  final double step;

  /// The digits after the point it shows and rounds to.
  final int decimals;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// The field, the theme's surface and text under it.
  final Style? style;

  /// The field while it has the focus, over [style];
  /// [ThemeData.selection] when null.
  final Style? focusedStyle;

  /// `▴▾` while the field has not the focus; [ThemeData.muted] when null.
  final Style? arrowStyle;

  /// The field while its text is no number, or one beyond the bounds;
  /// [ThemeData.error] when null.
  final Style? errorStyle;

  @override
  State<NumberInput> createState() => _NumberInputState();
}

final class _NumberInputState extends State<NumberInput>
    with TypedInputState<NumberInput, double> {
  @override
  double get widgetValue => widget.value;

  @override
  void Function(double value)? get onChanged => widget.onChanged;

  @override
  FocusNode? get focusNode => widget.focusNode;

  double _round(double value) =>
      double.parse(value.toStringAsFixed(widget.decimals));

  @override
  String format(double value) {
    final v = _round(value);
    // without the sign of a zero
    return (v == 0 ? 0.0 : v).toStringAsFixed(widget.decimals);
  }

  @override
  ({double value})? parse(String text) {
    final v = double.tryParse(text.trim());
    return v == null || !v.isFinite ? null : (value: _round(v));
  }

  @override
  bool fits(double value) {
    final NumberInput(:min, :max) = widget;
    return (min == null || value >= min) && (max == null || value <= max);
  }

  @override
  double clamp(double value) {
    final NumberInput(:min, :max) = widget;
    if (min != null && value < min) {
      return min;
    }
    return max != null && value > max ? max : value;
  }

  @override
  double stepped(double from, int count) => _round(from + count * widget.step);

  void _arrow(PointerEvent event) {
    if (event.button == 0) {
      node.requestFocus();
      stepBy(event.x == 0 ? 1 : -1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return buildField(
      context,
      keys: {
        'up': () => stepBy(1),
        'down': () => stepBy(-1),
        'pageup': () => stepBy(10),
        'pagedown': () => stepBy(-10),
      },
      hints: const {'up': 'increase', 'down': 'decrease'},
      onWheel: (event) => stepBy(event.scrollX - event.scrollY),
      autofocus: widget.autofocus,
      style: widget.style,
      focusedStyle: widget.focusedStyle,
      errorStyle: widget.errorStyle,
      trailing: Listener(
        onDown: enabled ? _arrow : null,
        child: Text(
          '▴▾',
          style: theme.text.merge(
            !enabled
                ? theme.muted
                : node.hasFocus
                ? theme.primary
                : widget.arrowStyle ?? theme.muted,
          ),
        ),
      ),
    );
  }
}

/// What a [NumberInput] and a `DatePicker` share: a value of [T] typed in
/// a [TextField], whose text [controller] holds and whose focus [node]
/// has. The text typed is taken as Enter is pressed and as the focus
/// leaves the field while it is in the tree ([commit]); the keys and the
/// wheel step the value
/// ([stepBy]); Escape puts the value back in place of the text typed
/// ([revert]). Hidden from the library's exports.
mixin TypedInputState<W extends StatefulWidget, T> on State<W> {
  /// The value the widget is built with.
  T get widgetValue;

  /// Called with the value the field is to take; null for a disabled
  /// field.
  // ignore: unsafe_variance
  void Function(T value)? get onChanged;

  /// The node the widget is given, if one is.
  FocusNode? get focusNode;

  /// [value] as the field shows it.
  String format(T value);

  /// The value [text] is, within the bounds or not; null for text that is
  /// no value.
  ({T value})? parse(String text);

  /// Whether [value] is within the bounds.
  bool fits(T value);

  /// [value] within the bounds: the nearest bound for one beyond them.
  T clamp(T value);

  /// The value [count] steps after [from], before it when negative; null
  /// for none.
  T? stepped(T from, int count);

  /// The value the field shows: the widget's, or the one the last change
  /// gave, until the widget is built with another.
  T get value => _value;
  late T _value = widgetValue;

  /// What holds the text.
  late final controller = TextEditingController(text: format(_value));

  FocusNode? _own;
  FocusNode? _given;

  /// The node of the field.
  FocusNode get node => focusNode ?? (_own ??= FocusNode());

  // whether the text was typed since it showed the value last
  var _typed = false;

  // the keys bound as built last
  var _keys = const <String, VoidCallback?>{};

  late final _actions = <Type, Action<Intent>>{
    _Key: _KeyAction(_takes, _does),
  };

  /// Whether [key] is taken now: while the field has the focus, Escape
  /// while text is typed.
  bool _takes(_Key key) =>
      node.hasFocus && (key != _escape ? _keys[key.name] != null : _typed);

  void _does(_Key key) => key == _escape ? revert() : _keys[key.name]?.call();

  /// Whether it takes the focus and changes.
  bool get enabled => onChanged != null;

  @override
  void initState() {
    super.initState();
    _given = focusNode;
    node.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(W oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(focusNode, _given)) {
      // the Focus below lets an own node go after this build: it is
      // disposed with this state
      (_given ?? _own)?.removeListener(_focusChanged);
      _given = focusNode;
      node.addListener(_focusChanged);
    }
    if (widgetValue != _value) {
      _value = widgetValue;
      _show();
    } else if (!_typed) {
      // as the widget shows it now
      _show();
    }
  }

  // out of the tree, the field takes nothing as the focus leaves it

  @override
  void deactivate() {
    node.removeListener(_focusChanged);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    node.addListener(_focusChanged);
  }

  @override
  void dispose() {
    _own?.dispose();
    controller.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (!node.hasFocus) {
      commit();
    }
    setState(() {});
  }

  /// Takes the text typed, if it was, as the value: within the bounds as
  /// it is, beyond them as the nearest bound; text that is no value gives
  /// way to the value.
  void commit() {
    if (!_typed) {
      return;
    }
    final typed = parse(controller.text);
    if (typed == null) {
      revert();
    } else {
      change(clamp(typed.value));
    }
  }

  /// Takes [value] as the value, calling [onChanged] when it is another,
  /// and shows it.
  void change(T value) {
    if (value != _value) {
      _value = value;
      onChanged?.call(value);
    }
    revert();
  }

  /// Shows the value in place of the text typed.
  void revert() {
    _show();
    setState(() {});
  }

  void _show() {
    if (_typed) {
      _typed = false;
      // Escape is taken no more
      node.markKeysChanged();
    }
    final text = format(_value);
    if (controller.text != text) {
      controller.text = text;
    }
  }

  /// Steps the value [count] steps ([stepped]) from the text typed, if it
  /// is a value, or from the value; returns whether it did.
  bool stepBy(int count) {
    final T from;
    if (_typed) {
      final typed = parse(controller.text);
      if (typed == null) {
        return false;
      }
      from = clamp(typed.value);
    } else {
      from = _value;
    }
    final to = stepped(from, count);
    if (to == null) {
      return false;
    }
    change(clamp(to));
    return true;
  }

  /// Whether the text typed is no value, or one beyond the bounds.
  bool get _wrong {
    if (!_typed) {
      return false;
    }
    final typed = parse(controller.text);
    return typed == null || !fits(typed.value);
  }

  void _edited(String text) {
    if (!_typed) {
      node.markKeysChanged();
    }
    setState(() => _typed = true);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event.code == KeyCode.enter &&
        event.modifiers == 0 &&
        event.kind != KeyKind.release) {
      commit();
    }
    return KeyEventResult.ignored;
  }

  void _pressed(PointerEvent event, VoidCallback? onPressed) {
    if (event.button == 0) {
      node.requestFocus();
      onPressed?.call();
    }
  }

  /// The field, then [trailing] a cell after it: [keys] bound while it
  /// has the focus, [hints] for them, and Escape while text is typed;
  /// [onWheel] the wheel over it while it has the focus; [onPressed] a
  /// press of the left button on the field, which focuses it. The field
  /// is in [style], and while it has the focus [focusedStyle] over it,
  /// [fieldFocused] when null, its selection then [fieldSelection].
  Widget buildField(
    BuildContext context, {
    required Map<String, VoidCallback?> keys,
    required Map<String, String> hints,
    required Widget trailing,
    required bool autofocus,
    required Style? style,
    required Style? focusedStyle,
    required Style? errorStyle,
    String? placeholder,
    PointerEventListener? onWheel,
    VoidCallback? onPressed,
  }) {
    final theme = Theme.of(context);
    final enabled = this.enabled;
    final on = enabled && node.hasFocus;
    final shown = !enabled
        ? theme.muted
        : _wrong
        ? errorStyle ?? theme.error
        : const Style();
    _keys = keys;
    // bound whether it has the focus or not, so that a key that comes
    // right after the focus is its; the action passes on those that come
    // while it has not
    return Shortcuts(
      enabled
          ? {for (final name in keys.keys) name: _Key(name), 'escape': _escape}
          : const {},
      hints: enabled ? hints : const {},
      child: Actions(
        _actions,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: Listener(
            onScroll: on ? onWheel : null,
            child: Row(
              gap: 1,
              children: [
                Expanded(
                  child: Listener(
                    onDown: enabled ? (e) => _pressed(e, onPressed) : null,
                    child: TextField(
                      controller: controller,
                      focusNode: node,
                      autofocus: autofocus,
                      // the input's own hints, the field's left out
                      keyHints: false,
                      canRequestFocus: enabled,
                      placeholder: placeholder,
                      onChanged: _edited,
                      style: fieldRest(
                        theme,
                      ).merge(style ?? const Style()).merge(shown),
                      focusedStyle: focusedStyle ?? fieldFocused(theme),
                      selectionStyle: focusedStyle == null
                          ? fieldSelection(theme)
                          : null,
                    ),
                  ),
                ),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A key a [TypedInputState] binds, by its name.
final class _Key extends Intent {
  const _Key(this.name);

  final String name;

  @override
  bool operator ==(Object other) => other is _Key && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

const _escape = _Key('escape');

/// Does a [_Key] while [takes] says so.
final class _KeyAction extends Action<_Key> {
  _KeyAction(this.takes, this.does);

  final bool Function(_Key key) takes;
  final void Function(_Key key) does;

  @override
  bool isEnabled(_Key intent) => takes(intent);

  @override
  void invoke(_Key intent) => does(intent);
}
