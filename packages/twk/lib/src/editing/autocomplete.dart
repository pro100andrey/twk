/// Autocomplete: an [Autocomplete] suggests what to put in a text field as
/// the user types, and puts in the [Suggestion] chosen.
library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart' show KeyCode, KeyEvent, KeyKind;

import '../focus/focus.dart';
import '../focus/hinted_keys.dart';
import '../foundation/change_notifier.dart';
import '../framework/framework.dart';
import '../layout/box.dart';
import '../layout/shadow.dart';
import '../overlay/fuzzy.dart';
import '../overlay/layer.dart';
import '../overlay/options.dart';
import '../overlay/panel.dart';
import '../overlay/popover.dart';
import '../style/style.dart';
import 'text_editing.dart';

/// What an [Autocomplete] suggests: [text] to put in place of the query,
/// shown as [label] with [detail] after it.
///
/// Two suggestions are equal when their text, label and detail are.
///
/// ```dart
/// const suggestion = Suggestion(
///   'git commit --amend',
///   label: 'amend',
///   detail: 'rewrite the last commit',
/// );
/// ```
@immutable
final class Suggestion {
  /// A suggestion of [text], shown as [label] (or the text) and [detail].
  const Suggestion(this.text, {this.label, this.detail});

  /// What goes in place of the query when it is chosen.
  final String text;

  /// What the list shows; [text] when null.
  final String? label;

  /// What is said after the label, muted; null for nothing.
  final String? detail;

  @override
  bool operator ==(Object other) =>
      other is Suggestion &&
      other.text == text &&
      other.label == label &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(text, label, detail);

  @override
  String toString() => 'Suggestion($text)';
}

/// Suggests what to put in the field in [child] that edits [controller], a
/// `TextField` or a `TextArea`, as the user types.
///
/// The query is the text
/// before the caret; with a [trigger], such as `/` or `@`, the text after
/// the trigger up to the caret, where the trigger starts a word (at the
/// start of the text or after a blank, at most 256 characters before the
/// caret) and no blank follows it. Each time the query changes,
/// [suggestions] is asked for those that go with it; what it gives, at
/// once or in a future, shows under the field in a [Popover], the first
/// highlighted, the characters of the query in each label standing out
/// ([fuzzyMatch]). With no trigger, an empty query asks for nothing; an
/// answer that comes after the query changed again does not show.
///
/// While they show, the keys that reach the field go to them first: Up and
/// Down highlight the one before and after; Enter puts the highlighted
/// one's [Suggestion.text] in place of the query, and [onSelected] is
/// called with it; Tab puts in the start the suggestions' texts share,
/// where that is longer than the query and starts as it does, ignoring
/// case, and does what Enter does where not; Escape hides them.
/// Hidden or chosen, they show again once the text changes; the caret
/// moved does not show them. They hide too when the focus leaves the field
/// and the popover, and when a button is pressed outside both. While
/// they show, the field's keys are among those a `KeyHintsBar` shows
/// ([FocusManagerKeys.activeKeys]), before the field's own, unless
/// [keyHints] is false: `choose` for Up and Down, `put in` for Enter,
/// `complete` for Tab; the popover's Escape `close` after them.
///
/// At most [rows] show at once, on a panel as [popupLook] says: raised, of
/// the theme's surface and text without an outline, the rows all it has,
/// casting the theme's panel shadow ([Panel.shadowOf]); or a [Panel] in a
/// border of the theme's border color ([PanelLook.bordered]). Without a
/// trigger, the query is put together from the pieces the controller
/// keeps the text in at each change: for a `TextArea` of a large text, a
/// trigger. Without an [Overlay] above it the build fails with a
/// [StateError] that says where to place one.
///
/// A field that suggests the names of the people of a chat after `@`:
///
/// ```dart
/// final controller = TextEditingController();
/// const people = ['ada', 'alan', 'grace'];
/// final field = Autocomplete(
///   controller: controller,
///   trigger: '@',
///   suggestions: (query) => [
///     for (final name in people)
///       if (name.startsWith(query)) Suggestion('@$name '),
///   ],
///   child: TextField(controller: controller, autofocus: true),
/// );
/// ```
final class Autocomplete extends StatefulWidget {
  /// Suggestions for the field in [child] that edits [controller].
  ///
  /// It asserts that [trigger], where given, is not empty, and that [rows]
  /// is above 0.
  const Autocomplete({
    required this.controller,
    required this.suggestions,
    required this.child,
    super.key,
    this.trigger,
    this.onSelected,
    this.rows = 8,
    this.popupLook = PanelLook.raised,
    this.popupFadeIn = const Duration(milliseconds: 120),
    this.keyHints = true,
  }) : assert(trigger != '', 'trigger is empty'),
       assert(rows > 0, 'rows below 1');

  /// What the field in [child] edits.
  final TextEditingController controller;

  /// What goes with a query, at once or in a future; the query is the
  /// text after the [trigger], without it.
  final FutureOr<Iterable<Suggestion>> Function(String query) suggestions;

  /// What the field is in.
  final Widget child;

  /// What a query starts after; null for the text before the caret.
  final String? trigger;

  /// Called with a suggestion once it is put in.
  final void Function(Suggestion suggestion)? onSelected;

  /// The most suggestions shown at once; 8 by default.
  final int rows;

  /// How the suggestions' popup stands out of what is under it: a raised
  /// panel by default.
  final PanelLook popupLook;

  /// How long the suggestions' popup takes to fade in from what is under
  /// it as they show, easing out; 120 ms by default, zero for at once.
  final Duration popupFadeIn;

  /// Whether the keys it takes while the suggestions show carry their
  /// hints, for a `KeyHintsBar`; false leaves them out, the keys going to
  /// the suggestions still.
  final bool keyHints;

  @override
  State<Autocomplete> createState() => _AutocompleteState();
}

/// Whether the [Autocomplete] nearest above [context], when it completes
/// [controller], took [event]: a field asks with each key that reaches it
/// before it handles the key itself.
bool autocompleteTook(
  BuildContext context,
  TextEditingController controller,
  KeyEvent event,
) {
  final scope = context.getInheritedWidgetOfExactType<_AutocompleteScope>();
  return scope != null &&
      identical(scope.state.widget.controller, controller) &&
      scope.state._take(event);
}

/// [field], the `Focus` of [node], a field that edits [controller], under
/// the hints of the keys the [Autocomplete] nearest above [context] takes
/// ([autocompleteTook]) when it completes [controller]: what a field puts
/// right above its `Focus`, its own hints above it, so that those of the
/// suggestions come first.
Widget autocompleteKeys(
  BuildContext context,
  TextEditingController controller,
  FocusNode node,
  Widget field,
) {
  final scope = context.getInheritedWidgetOfExactType<_AutocompleteScope>();
  final state =
      scope != null && identical(scope.state.widget.controller, controller)
      ? scope.state
      : null;
  return HintedKeys(
    node: node,
    hints: _AutocompleteState._hints,
    takes: state?._takes ?? _never,
    changes: state?._showing,
    child: field,
  );
}

bool _never(String key) => false;

/// Whether the suggestions of the [Autocomplete] nearest above [context]
/// show, when it completes [controller]; null without one. A field's
/// Enter goes to them while they show ([autocompleteTook]).
ValueListenable<bool>? autocompleteShowing(
  BuildContext context,
  TextEditingController controller,
) {
  final scope = context.getInheritedWidgetOfExactType<_AutocompleteScope>();
  return scope != null && identical(scope.state.widget.controller, controller)
      ? scope.state._showing
      : null;
}

/// A query: the start of what it puts a suggestion in place of, and its
/// text, which goes on to the caret.
typedef _Query = (int start, String text);

final class _AutocompleteState extends State<Autocomplete> {
  _Query? _query;

  // the text the suggestions hide for, until it changes
  Object? _hiddenIn;

  var _suggestions = const <Suggestion>[];
  var _highlighted = 0;

  // the number of the query asked for last
  var _asked = 0;

  // whether a suggestion is being put in
  var _picking = false;

  // whether the suggestions show, which the keys they take follow
  final ValueNotifier<bool> _showing = ValueNotifier(false);

  /// What the keys do while the suggestions show.
  static const _hints = {
    'up': 'choose',
    'down': 'choose',
    'enter': 'put in',
    'tab': 'complete',
  };

  /// Whether [_take] takes the key of [_hints] named [key] now, for its
  /// hint.
  bool _takes(String key) => widget.keyHints && _showing.value;

  /// Tells [_showing] whether the suggestions show, as [_take] says.
  void _told() => _showing.value = _suggestions.isNotEmpty && _query != null;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(Autocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _query = null;
      _hiddenIn = null;
      _asked++;
      _suggestions = const [];
      _told();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _showing.dispose();
    super.dispose();
  }

  /// The query in [value]; null for none.
  _Query? _queryIn(TextEditingValue value) {
    final selection = value.selection;
    final caret = selection.extentOffset;
    final text = textBufferOf(value);
    if (!selection.isCollapsed || caret < 0 || caret > text.length) {
      return null;
    }
    final trigger = widget.trigger;
    if (trigger == null) {
      return caret == 0 ? null : (0, text.substring(0, caret));
    }
    final from = caret > _reach ? caret - _reach : 0;
    final read = text.substring(from, caret);
    final blank = read.lastIndexOf(_blank);
    if (blank < 0 && from > 0) {
      return null;
    }
    final word = read.substring(blank + 1);
    return word.startsWith(trigger)
        ? (from + blank + 1 + trigger.length, word.substring(trigger.length))
        : null;
  }

  // how far before the caret a trigger is looked for
  static const _reach = 256;
  static final _blank = RegExp(r'\s');

  void _changed() {
    final value = widget.controller.value;
    final query = _queryIn(value);
    if (query == _query) {
      return;
    }
    _query = query;
    _told();
    final asked = ++_asked;
    if (_picking || identical(textBufferOf(value), _hiddenIn)) {
      return;
    }
    _hiddenIn = null;
    if (query == null) {
      _show(const []);
      return;
    }
    final answer = widget.suggestions(query.$2);
    if (answer is Future<Iterable<Suggestion>>) {
      unawaited(
        answer.then((suggestions) {
          if (mounted && asked == _asked) {
            _show(suggestions);
          }
        }),
      );
    } else {
      _show(answer);
    }
  }

  void _show(Iterable<Suggestion> suggestions) {
    if (_suggestions.isEmpty && suggestions.isEmpty) {
      return;
    }
    setState(() {
      _suggestions = List.unmodifiable(suggestions);
      _highlighted = 0;
    });
    _told();
  }

  /// Hides the suggestions until the text changes.
  void _hide() {
    _hiddenIn = textBufferOf(widget.controller.value);
    _asked++;
    _show(const []);
  }

  void _pick(Suggestion suggestion) {
    final query = _query;
    if (query == null) {
      return;
    }
    final (start, text) = query;
    _picking = true;
    try {
      widget.controller.replace(start, start + text.length, suggestion.text);
    } finally {
      _picking = false;
    }
    _hide();
    widget.onSelected?.call(suggestion);
  }

  /// Puts in the start the suggestions share where that is longer than
  /// the query and starts as it does; else the highlighted one.
  void _complete() {
    final (start, text) = _query!;
    var shared = _suggestions.first.text;
    for (final suggestion in _suggestions.skip(1)) {
      final other = suggestion.text;
      var n = 0;
      while (n < shared.length &&
          n < other.length &&
          shared.codeUnitAt(n) == other.codeUnitAt(n)) {
        n++;
      }
      // not into a character
      shared = shared.substring(
        0,
        shared.characterOffset(shared.characterIndexAt(n)),
      );
    }
    if (shared.length > text.length &&
        shared.toLowerCase().startsWith(text.toLowerCase())) {
      widget.controller.replace(start, start + text.length, shared);
    } else {
      _pick(_suggestions[_highlighted]);
    }
  }

  bool _take(KeyEvent event) {
    if (_suggestions.isEmpty ||
        _query == null ||
        event.kind == KeyKind.release ||
        event.modifiers != 0) {
      return false;
    }
    final n = _suggestions.length;
    switch (event.code) {
      case KeyCode.up:
        setState(() => _highlighted = (_highlighted - 1) % n);
      case KeyCode.down:
        setState(() => _highlighted = (_highlighted + 1) % n);
      case KeyCode.enter:
        _pick(_suggestions[_highlighted]);
      case KeyCode.tab:
        _complete();
      case _:
        return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (Overlay.maybeOf(context) == null) {
      throw StateError(
        'Autocomplete: no Overlay above it: place an Overlay above it, as '
        'around the whole app: Overlay(child: …)',
      );
    }
    final theme = Theme.of(context);
    final query = _query?.$2 ?? '';
    final list = OptionList(
      options: [
        for (final suggestion in _suggestions) _optionOf(suggestion, query),
      ],
      highlighted: _highlighted,
      rows: widget.rows,
    );
    return Popover(
      open: _suggestions.isNotEmpty,
      onDismiss: _hide,
      fadeIn: widget.popupFadeIn,
      popover: switch (widget.popupLook) {
        PanelLook.raised => Shadow(
          shadow: Panel.shadowOf(theme),
          child: Box(style: theme.surface.merge(theme.text), child: list),
        ),
        PanelLook.bordered => Panel(
          look: PanelLook.bordered,
          shadow: false,
          child: list,
        ),
      },
      child: _AutocompleteScope(this, child: widget.child),
    );
  }

  static Option _optionOf(Suggestion suggestion, String query) {
    final label = suggestion.label ?? suggestion.text;
    return Option(
      label,
      marks: fuzzyMatch(query, label)?.positions ?? const [],
      detail: suggestion.detail,
    );
  }
}

/// What a field finds its [Autocomplete] by ([autocompleteTook]).
final class _AutocompleteScope extends InheritedWidget {
  const _AutocompleteScope(this.state, {required super.child});

  final _AutocompleteState state;

  @override
  bool updateShouldNotify(_AutocompleteScope oldWidget) => false;
}
