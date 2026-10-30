/// A line of text the user edits: [TextField].
library;

import 'dart:typed_data';

import 'package:twk_core/twk_core.dart'
    show
        Attr,
        BoxConstraints,
        Canvas,
        Color,
        CursorShape,
        DiagnosticPropertiesBuilder,
        InputEvent,
        KeyCode,
        KeyEvent,
        KeyKind,
        PaintContext,
        PasteEvent,
        PipelineTextOrder,
        RenderObject,
        TextAlign,
        TextDirection,
        TextOrder,
        TextSegmenter;

import '../binding/app_binding.dart';
import '../focus/focus_tree.dart';
import '../focus/hinted_keys.dart';
import '../foundation/change_notifier.dart';
import '../foundation/listenable_builder.dart';
import '../framework/framework.dart';
import '../semantics/semantics.dart';
import '../style/style.dart';
import '../text/widgets.dart' show DefaultTextStyle, Text;
import 'autocomplete.dart';
import 'bidi_row.dart';
import 'caret.dart';
import 'editing_keys.dart';
import 'field_mouse.dart';
import 'input_decoration.dart';
import 'text_buffer.dart';
import 'text_editing.dart';

/// A field of a line of text the user edits, which its [controller]
/// holds.
///
/// It is one row as wide as its constraints allow (in a `Row`, `Expanded`
/// gives it the room left); where they do not limit its width, and asked
/// for the width it would like (`IntrinsicWidth`), as wide as its text or
/// its placeholder and a column for the caret.
///
/// A prompt whose field runs to the end of the row, the text sent on
/// Enter:
///
/// ```dart
/// final controller = TextEditingController();
/// final prompt = Row(
///   children: [
///     const Text('> '),
///     Expanded(
///       child: TextField(
///         controller: controller,
///         placeholder: 'type a command',
///         autofocus: true,
///         onSubmitted: (text) {
///           print('run $text');
///           controller.clear();
///         },
///       ),
///     ),
///   ],
/// );
/// ```
///
/// While it has the focus:
///
/// * a character typed goes in at the caret, in place of the selection;
/// * the editing keys move the caret, select and delete by characters, the
///   grapheme clusters of Unicode, and by words ([TextBoundaries]): Left
///   and Right, with Ctrl or Alt a word, as Alt+B and Alt+F; Home, End,
///   Ctrl+A and Ctrl+E to the ends; with Shift each of them selects.
///   Backspace and Delete, with Ctrl or Alt a word, as Alt+D; Ctrl+W back
///   to a blank, Ctrl+U and Ctrl+K to the ends; Ctrl+D the character after
///   the caret. Each deletes the selection instead when there is one;
/// * Ctrl+Z undoes the last change, typing a word at a time, Ctrl+Y (and
///   Ctrl+Shift+Z) makes it again ([TextEditingController.undo]);
/// * Ctrl+C copies the selection to the system clipboard (OSC 52, wrapped
///   for tmux or GNU screen inside one, as a `SelectionArea` copies),
///   Ctrl+X cuts it: copies and deletes it. With nothing selected they
///   go up, Ctrl+C to quit the app; obscured, the field copies nothing;
/// * Enter calls [onEditingComplete], then [onSubmitted] with the text;
/// * a paste (bracketed paste) goes to [onPaste] first; unless that takes
///   it, it goes in as typed, its lines joined by blanks, without a line
///   break at its end and other control characters.
///
/// [onEditingComplete] is called on Enter, as Flutter's, and as the focus
/// leaves the field after a change the user made since it was called
/// last.
///
/// With [readOnly] nothing the user does changes the text: the keys that
/// move the caret and select do what they do, and the mouse, but a
/// character typed, the keys that delete, undo and redo, and a paste
/// [onPaste] leaves go up to the nodes above, Ctrl+X too: Ctrl+C copies.
/// With [enabled] false the field takes neither the focus, which Tab
/// passes by and which it loses where it has it, nor the mouse, and shows
/// in [disabledStyle] over [style], as the other controls do disabled.
///
/// The mouse, with the left button: a press focuses the field and places
/// the caret at the character in the cell (a wide one's second cell too,
/// the end of the text past it, through the sideways scroll); a drag
/// selects from there to the mouse; a double press selects the word there
/// (as Ctrl+Left and Ctrl+Right find words) or the run of blanks, a
/// triple press the text, and a drag after either goes on by words or the
/// whole text; with Shift, a press selects from the selection's base. A
/// press is the next of a double or triple one in the same cell within
/// 300 ms of the release before it. The press is the field's: a
/// `SelectionArea` around it selects nothing by it. Obscured, a double
/// press selects the whole text. While the field takes no focus
/// ([canRequestFocus]), it takes no mouse.
///
/// The keys it does not take go up to the nodes above its [Focus]: Tab,
/// Escape, Up and Down, Enter without [onSubmitted] and
/// [onEditingComplete], with [readOnly] those that would edit, Ctrl+D
/// with nothing after the caret, Ctrl+Z and Ctrl+Y with nothing to undo
/// or redo, Ctrl+C and Ctrl+X with nothing selected, and those with Ctrl
/// or Alt it does not name.
/// [onChanged] is called with the text after each change the user makes.
///
/// While it has the focus, the keys it takes that do more than edit are
/// among those a `KeyHintsBar` shows (`FocusManagerKeys.activeKeys`),
/// unless [keyHints] is false: Enter `submit` with [onSubmitted], Ctrl+C
/// `copy` and Ctrl+X `cut` while something is selected, Ctrl+Z `undo`
/// while there is a change to undo; an `Autocomplete`'s keys before them
/// while its suggestions show.
///
/// The terminal's cursor, in [cursorShape] (a bar by default), shows the
/// caret while the field has the focus, so that the terminal's input
/// method composes text there; the selection shows in [selectionStyle]
/// meanwhile. The text scrolls sideways to keep the caret in view.
///
/// In visual order (`PipelineOwner.textOrder`) a text with right-to-left
/// characters is drawn in the order UAX #9 gives, from the left edge: its
/// right-to-left runs reversed, their brackets mirrored. The caret shows
/// at the edge of the run it is in, the more deeply embedded one where two
/// meet; Left and Right move it a cell at a time as it is drawn, Ctrl and
/// Alt with them a word back or on as the paragraph runs (on for Left in a
/// right-to-left one); Alt+B and Alt+F, Home and End, and the keys that
/// delete go as the text is stored. The selection is the text between its
/// ends as stored, wherever its pieces are drawn. Empty, the field shows
/// [placeholder]. A text shorter than the field, and the column after it
/// kept for the caret, or the placeholder and that column, are placed by
/// [textAlign]: at the left, in the middle (the odd column after them) or
/// at the right; [TextAlign.start] and [TextAlign.end] by the direction
/// of the text's paragraph in visual order, [TextAlign.justify] at the
/// start. A longer one scrolls as at the left. With [obscureText] each
/// character shows as [obscuringCharacter]. With [maxLength] it takes no
/// more characters than that from the user: what is typed or pasted
/// beyond is left out. The controller's composing range shows
/// underlined.
///
/// The styles, each merged over those before it: [style] over the
/// `DefaultTextStyle`'s and under them the theme's text, with no
/// background of its own: the field paints over what is under it, a page,
/// a dialog, a selected row, a gradient (`RenderObject.keepsUnderlay`), a
/// `Box` drawn around it giving its edge (the controls that show a field
/// without a box, `NumberInput`, `DatePicker`, `TextFormField` and
/// `FilePicker`, sink theirs in [ThemeData.well], underlined in
/// [ThemeData.border]'s color where the well is the background);
/// [focusedStyle] while the field has the focus (a field without a box
/// around it shows the focus so, on [ThemeData.selection]), then
/// [placeholderStyle] for the placeholder (the theme's [ThemeData.muted]
/// when null) and [selectionStyle] for the selection
/// ([ThemeData.selection] when null); disabled, [disabledStyle] (the
/// theme's [ThemeData.muted] when null) in place of [focusedStyle].
///
/// With a [decoration] it is drawn in an [InputDecorator]: an icon, a
/// label, a border, a prefix and a suffix, a helper or an error line, in
/// the colors of the focus; with [maxLength] the decoration's counter
/// counts its characters (`3/40`) unless it has one of its own. Without
/// one, the field is its row alone.
///
/// A screen reader reads it as a [SemanticsRole.textBox] of its
/// [semanticsLabel], or of its decoration's label or its placeholder
/// without one, its text as its value (`textbox Name: anna`); with
/// [obscureText], `protected` in place of its text, never its
/// characters; `disabled` after it with [enabled] false.
///
/// A repaint boundary: a keystroke repaints nothing else, unless the field
/// takes its width from its text. It measures and draws its whole text at
/// each change: for a text of many thousand characters, a `TextArea`.
///
/// See also:
///
///  * `TextArea`, a text of many lines.
///  * `TextFormField`, a field of a `Form`, validated.
///  * [Autocomplete], which suggests what to type.
final class TextField extends StatefulWidget {
  /// A field of the text of [controller], or of one of its own.
  ///
  /// It asserts that [maxLength], where given, is not below 0, and that
  /// [obscuringCharacter] is not empty.
  const TextField({
    super.key,
    this.controller,
    this.placeholder,
    this.semanticsLabel,
    this.obscureText = false,
    this.obscuringCharacter = '•',
    this.maxLength,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.onPaste,
    this.readOnly = false,
    this.enabled = true,
    this.textAlign = TextAlign.left,
    this.focusNode,
    this.autofocus = false,
    this.canRequestFocus,
    this.style,
    this.focusedStyle,
    this.placeholderStyle,
    this.selectionStyle,
    this.disabledStyle,
    this.cursorShape = CursorShape.bar,
    this.keyHints = true,
    this.decoration,
  }) : assert(maxLength == null || maxLength >= 0, 'maxLength below 0'),
       assert(obscuringCharacter != '', 'obscuringCharacter is empty');

  /// What it edits; null for one of its own, empty.
  final TextEditingController? controller;

  /// What it shows while its text is empty; null for nothing.
  final String? placeholder;

  /// What a screen reader calls the field, what its text is: `Name`;
  /// null, or empty, for its [placeholder]. Read in place of the
  /// placeholder, which is no name: it shows only while the text is empty,
  /// and is often an example of it (`e.g. anna`).
  final String? semanticsLabel;

  /// Whether each character shows as [obscuringCharacter]: a password.
  final bool obscureText;

  /// What each character shows as with [obscureText]: one character.
  final String obscuringCharacter;

  /// The most characters the user makes the text; null for no limit. A
  /// text set by the controller is kept as it is.
  final int? maxLength;

  /// Called with the text after each change the user makes: the text the
  /// field draws, put together from the pieces the controller keeps it in
  /// once a change for both (a `TextArea`, which draws the rows in view
  /// only, does not put it together for itself).
  final void Function(String text)? onChanged;

  /// Called with the text when Enter is pressed; null, with no
  /// [onEditingComplete], leaves Enter to the nodes above.
  final void Function(String text)? onSubmitted;

  /// Called when Enter is pressed, before [onSubmitted], and as the focus
  /// leaves the field after a change the user made since it was called
  /// last.
  final VoidCallback? onEditingComplete;

  /// Called with what is pasted, as the terminal gave it, while the field
  /// has the focus, before it goes in: true when the app took it, and
  /// nothing goes in; false for it to go in as ever.
  final bool Function(String text)? onPaste;

  /// Whether nothing the user does changes the text: the caret moves and
  /// selects, nothing is typed, deleted, undone or pasted.
  final bool readOnly;

  /// Whether the field takes the focus and the mouse; false shows it in
  /// [disabledStyle].
  final bool enabled;

  /// Where a text shorter than the field goes, its caret's column after
  /// it.
  final TextAlign textAlign;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// See [FocusNode.canRequestFocus].
  final bool? canRequestFocus;

  /// Every cell, the `DefaultTextStyle`'s and the theme's text under it,
  /// over what is under the field.
  final Style? style;

  /// Every cell while the field has the focus, over [style]; null for
  /// nothing more.
  final Style? focusedStyle;

  /// The placeholder; [ThemeData.muted] when null.
  final Style? placeholderStyle;

  /// The selection while the field has the focus; [ThemeData.selection]
  /// when null.
  final Style? selectionStyle;

  /// Every cell while the field is disabled ([enabled] false), over
  /// [style]; [ThemeData.muted] when null.
  final Style? disabledStyle;

  /// The shape of the terminal's cursor at the caret while the field has
  /// the focus: a steady bar by default, or a block or an underline, each
  /// steady or blinking ([CursorShape]); [CursorShape.terminalDefault] for
  /// the shape the user set in the terminal.
  final CursorShape cursorShape;

  /// Whether the keys it takes that do more than edit carry their hints,
  /// for a `KeyHintsBar`; false leaves them out, the keys doing what they
  /// do still.
  final bool keyHints;

  /// What is drawn around the field ([InputDecorator]); null for the
  /// field's row alone.
  final InputDecoration? decoration;

  @override
  State<TextField> createState() => _TextFieldState();
}

final class _TextFieldState extends State<TextField> {
  TextEditingController? _ownController;
  FocusNode? _ownNode;

  // what draws the text, which moves the caret as it draws it
  _RenderTextField? _field;

  // when onEditingComplete is called as the focus leaves
  final _completion = EditingCompletion();

  // whether the field was disabled, so that enabled again it may take the
  // focus again
  var _wasDisabled = false;

  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  /// Whether Enter submits.
  bool get _submits =>
      widget.onSubmitted != null || widget.onEditingComplete != null;

  @override
  void initState() {
    super.initState();
    _completion.follow(_node, () => widget.onEditingComplete?.call());
  }

  @override
  void didUpdateWidget(TextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _completion.follow(_node, () => widget.onEditingComplete?.call());
  }

  @override
  void dispose() {
    _completion.dispose();
    _ownController?.dispose();
    _ownNode?.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!node.hasFocus) {
      return KeyEventResult.ignored;
    }
    final c = _controller;
    if (autocompleteTook(context, c, event)) {
      return KeyEventResult.handled;
    }
    final before = textBufferOf(c.value);
    if (event case KeyEvent(code: KeyCode.enter, modifiers: 0, :final kind)
        when kind != KeyKind.release) {
      if (!_submits) {
        return KeyEventResult.ignored;
      }
      _completion.done();
      widget.onEditingComplete?.call();
      widget.onSubmitted?.call(c.text);
      return KeyEventResult.handled;
    }
    final stops = _field?.stops ?? const CaretStops();
    if (!editingKey(
      c,
      event,
      _type,
      stops: stops,
      readOnly: widget.readOnly,
      copy: widget.obscureText ? null : _copy,
    )) {
      return KeyEventResult.ignored;
    }
    _told(before);
    return KeyEventResult.handled;
  }

  bool _onEvent(InputEvent event) {
    if (event is! PasteEvent || !_node.hasFocus) {
      return false;
    }
    if (widget.onPaste?.call(event.text) ?? false) {
      return true;
    }
    if (widget.readOnly) {
      return false;
    }
    final before = textBufferOf(_controller.value);
    _type(_oneLine(event.text));
    _told(before);
    return true;
  }

  /// Puts [text] in place of the selection, as much of it as
  /// [TextField.maxLength] leaves room for.
  void _type(String text) {
    final c = _controller;
    var typed = text;
    final max = widget.maxLength;
    if (max != null) {
      final s = c.selection;
      final kept =
          c.text.characterCount -
          (c.text.characterIndexAt(s.end) - c.text.characterIndexAt(s.start));
      final room = max - kept;
      if (room <= 0) {
        typed = '';
      } else if (typed.characterCount > room) {
        typed = typed.substring(
          0,
          typed.characterOffset(room),
        );
      }
    }
    if (typed.isNotEmpty || !c.selection.isCollapsed) {
      c.insert(typed);
    }
  }

  void _copy(String text) => copyToClipboard(context, text);

  void _told(TextBuffer before) {
    final changed = widget.onChanged;
    final told = changed != null || widget.onEditingComplete != null;
    if (told && !textBufferOf(_controller.value).sameText(before)) {
      _completion.changed();
      changed?.call(_controller.text);
    }
  }

  /// [text] pasted as one line: its lines joined by blanks, without the
  /// line break at its end and the other control characters.
  static String _oneLine(String text) {
    final lines = text.endsWith('\n')
        ? text.substring(0, text.length - 1)
        : text;
    return lines.replaceAll('\n', ' ').replaceAll(_controls, '');
  }

  static final _controls = RegExp('[\x00-\x08\x0a-\x1f\x7f]');

  /// Whether [_onKey] takes the key of the hints named [key] now: Enter
  /// but while an `Autocomplete`'s suggestions show.
  bool _takes(String key) => switch (key) {
    'enter' => _submits && !_suggesting,
    'ctrl+c' => _copies,
    'ctrl+x' => _copies && !widget.readOnly,
    _ => !widget.readOnly && _controller.canUndo,
  };

  /// Whether Ctrl+C copies now.
  bool get _copies => !widget.obscureText && !_controller.selection.isCollapsed;

  // whether the suggestions of an Autocomplete show, and what tells it
  ValueListenable<bool>? _showing;
  TextEditingController? _changing;
  Listenable? _changes;

  bool get _suggesting => _showing?.value ?? false;

  /// What [_takes] follows: the controller, and the suggestions.
  Listenable _changesOf(TextEditingController controller) {
    final showing = autocompleteShowing(context, controller);
    final changes = _changes;
    if (identical(showing, _showing) &&
        identical(controller, _changing) &&
        changes != null) {
      return changes;
    }
    _showing = showing;
    _changing = controller;
    return _changes = showing == null
        ? controller
        : Listenable.merge([controller, showing]);
  }

  static const _hints = {'ctrl+c': 'copy', 'ctrl+x': 'cut', 'ctrl+z': 'undo'};
  static const _submitHints = {
    'enter': 'submit',
    'ctrl+c': 'copy',
    'ctrl+x': 'cut',
    'ctrl+z': 'undo',
  };

  /// What [Focus.canRequestFocus] is: false while disabled, true where it
  /// was and [TextField.canRequestFocus] leaves it to the node.
  bool? get _canRequestFocus {
    if (!widget.enabled) {
      _wasDisabled = true;
      return false;
    }
    return widget.canRequestFocus ?? (_wasDisabled ? true : null);
  }

  @override
  Widget build(BuildContext context) {
    final field = _build();
    final decoration = widget.decoration;
    if (decoration == null) {
      return field;
    }
    final max = widget.maxLength;
    return InputDecorator(
      decoration:
          max == null ||
              decoration.counter != null ||
              decoration.counterText != null
          ? decoration
          : decoration.copyWith(counter: _Count(_controller, max)),
      enabled: widget.enabled,
      child: field,
    );
  }

  Widget _build() {
    final controller = _controller;
    final node = _node;
    return _FieldSemantics(
      this,
      child: InputListener(
        onEvent: _onEvent,
        child: HintedKeys(
          node: node,
          hints: !widget.keyHints
              ? const {}
              : _submits
              ? _submitHints
              : _hints,
          takes: _takes,
          changes: _changesOf(controller),
          child: autocompleteKeys(
            context,
            controller,
            node,
            Focus(
              focusNode: node,
              autofocus: widget.autofocus,
              canRequestFocus: _canRequestFocus,
              onKeyEvent: _onKey,
              child: FieldMouse(
                controller: controller,
                focusNode: _node,
                offsetAt: (x, _) => _field?.offsetAt(x),
                wordAt: (text, offset) => widget.obscureText
                    ? TextRange(start: 0, end: text.length)
                    : wordIn(text, offset, 0, text.length),
                lineAt: (text, _) => TextRange(start: 0, end: text.length),
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) => _Field(this, controller.value),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A [TextField] as a screen reader reads it, its text as it is when read.
final class _FieldSemantics extends Semantics {
  const _FieldSemantics(this.editor, {required super.child})
    : super(role: SemanticsRole.textBox);

  final _TextFieldState editor;

  @override
  String? get label => switch (editor.widget) {
    TextField(semanticsLabel: final label?) when label.isNotEmpty => label,
    TextField(decoration: InputDecoration(labelText: final label?))
        when label.isNotEmpty =>
      label,
    TextField(:final placeholder) => placeholder,
  };

  @override
  String get value =>
      editor.widget.obscureText ? 'protected' : editor._controller.text;

  @override
  SemanticsState get state =>
      editor.widget.enabled ? _enabled : const SemanticsState(disabled: true);
}

const _enabled = SemanticsState();

/// How many characters [controller] holds of [max], as a decoration's
/// counter shows them: `3/40`.
final class _Count extends StatelessWidget {
  const _Count(this.controller, this.max);

  final TextEditingController controller;
  final int max;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Text('${controller.text.characterCount}/$max'),
  );
}

/// The text of a [TextField] as its controller has it, in its theme's
/// styles where the field has none, the caret shown while the [Focus]
/// above it has the focus.
final class _Field extends LeafRenderObjectWidget {
  const _Field(this.state, this.value);

  final _TextFieldState state;
  final TextEditingValue value;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final field = _RenderTextField();
    updateRenderObject(context, field);
    return field;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderTextField renderObject,
  ) {
    final f = state.widget;
    final theme = Theme.of(context);
    final focused = Focus.of(context).hasFocus;
    // over what is under it: the theme's text and the DefaultTextStyle's
    // colors, no background of the theme's
    var style = theme.text
        .merge(DefaultTextStyle.of(context))
        .merge(f.style ?? _plain);
    if (!f.enabled) {
      style = style.merge(f.disabledStyle ?? theme.muted);
    } else if (f.focusedStyle case final s? when focused) {
      style = style.merge(s);
    }
    state._field = renderObject
      ..text = value.text
      ..selection = value.selection
      ..composing = value.composing
      ..obscuringCharacter = f.obscureText ? f.obscuringCharacter : null
      ..placeholder = f.placeholder ?? ''
      ..focused = focused
      ..style = style
      ..placeholderStyle = f.placeholderStyle ?? theme.muted
      ..selectionStyle = f.selectionStyle ?? theme.selection
      ..cursorShape = f.cursorShape
      ..textAlign = f.textAlign;
  }
}

const _plain = Style();
// the composing range's: in the text's color, apart from a line under the
// field in another (fieldRest)
const _underline = Style(
  attrs: Attr.underline,
  underlineColor: Color.defaultColor,
);
// the text color under the style's; no background: the field paints over
// what is under it, which the core keeps for it (keepsUnderlay)
const _opaque = Style(fg: Color.defaultColor);

/// What a [TextField] lays out and paints: one row of its text, scrolled
/// sideways to keep the caret in view, and the terminal's cursor at the
/// caret while [focused].
final class _RenderTextField extends RenderObject {
  // where a row with a selection or a composing range is painted in
  // pieces ([sortedOnce])
  final _cuts = Int32List(6);

  var _text = '';
  String get text => _text;
  set text(String t) {
    if (t != _text) {
      _text = t;
      _contentChanged();
    }
  }

  /// What each character shows as; null for the text itself.
  String? _obscuring;
  String? get obscuringCharacter => _obscuring;
  set obscuringCharacter(String? c) {
    if (c != _obscuring) {
      _obscuring = c;
      _contentChanged();
    }
  }

  var _placeholder = '';
  String get placeholder => _placeholder;
  set placeholder(String p) {
    if (p != _placeholder) {
      _placeholder = p;
      _contentChanged();
    }
  }

  var _selection = const TextSelection.collapsed(offset: 0);
  TextSelection get selection => _selection;
  set selection(TextSelection s) {
    if (s != _selection) {
      _selection = s;
      markNeedsPaint();
    }
  }

  TextRange _composing = TextRange.empty;
  TextRange get composing => _composing;
  set composing(TextRange r) {
    if (r != _composing) {
      _composing = r;
      markNeedsPaint();
    }
  }

  var _focused = false;

  /// Whether the caret and the selection show.
  bool get focused => _focused;
  set focused(bool f) {
    if (f != _focused) {
      _focused = f;
      markNeedsPaint();
    }
  }

  Style _style = _plain;
  Style get style => _style;
  set style(Style s) {
    if (s != _style) {
      _style = s;
      markNeedsPaint();
    }
  }

  Style _placeholderStyle = _plain;
  Style get placeholderStyle => _placeholderStyle;
  set placeholderStyle(Style s) {
    if (s != _placeholderStyle) {
      _placeholderStyle = s;
      markNeedsPaint();
    }
  }

  Style _selectionStyle = _plain;
  Style get selectionStyle => _selectionStyle;
  set selectionStyle(Style s) {
    if (s != _selectionStyle) {
      _selectionStyle = s;
      markNeedsPaint();
    }
  }

  CursorShape _cursorShape = CursorShape.bar;

  /// The shape of the terminal's cursor at the caret.
  CursorShape get cursorShape => _cursorShape;
  set cursorShape(CursorShape s) {
    if (s != _cursorShape) {
      _cursorShape = s;
      markNeedsPaint();
    }
  }

  TextAlign _textAlign = TextAlign.left;

  /// Where a text shorter than the field goes.
  TextAlign get textAlign => _textAlign;
  set textAlign(TextAlign a) {
    if (a != _textAlign) {
      _textAlign = a;
      markNeedsPaint();
    }
  }

  /// The first column shown.
  var _scroll = 0;

  /// The columns before the text, by [textAlign], at the last paint.
  var _indent = 0;

  // the text shown with an obscuring character
  String? _masked;

  // the columns of what is shown, measured with the owner's segmenter
  TextColumns? _columns;

  // in visual order, the text last drawn or moved in as it is drawn, the
  // segmenter that measured it and its row; null for none
  String? _bidiText;
  TextSegmenter? _bidiSegmenter;
  BidiRow? _bidiRow;

  // the width the text asked for at the last layout or question of a
  // parent, and whether a parent asked for it since the last layout
  int? _measured;
  var _widthAsked = false;

  // what painted it last
  PaintContext? _painted;

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get keepsUnderlay => true;

  /// What is shown for the text.
  String get _shown {
    final mask = _obscuring;
    return mask == null ? _text : _masked ??= mask * _text.characterCount;
  }

  /// The offset in [_shown] of [offset] in the text.
  int _shownOffset(int offset) {
    final mask = _obscuring;
    return mask == null ? offset : _text.characterIndexAt(offset) * mask.length;
  }

  /// [shown] in the order it is drawn, as [columns] measured it when
  /// given: in visual order, where it has right-to-left characters; else
  /// null, drawn as stored.
  BidiRow? _bidiOf(String shown, [TextColumns? columns]) {
    if (owner?.textOrder != TextOrder.visual || !mayReorder(shown)) {
      return null;
    }
    final segmenter = columns?.segmenter ?? owner!.segmenter;
    if (identical(shown, _bidiText) && identical(segmenter, _bidiSegmenter)) {
      return _bidiRow;
    }
    final c = columns ?? (TextColumns(segmenter)..measure(shown));
    _bidiText = shown;
    _bidiSegmenter = segmenter;
    return _bidiRow = BidiRow(shown, c.starts, c.columns);
  }

  /// Where the editing keys move the caret: Left and Right as the text is
  /// drawn in visual order, unless it is obscured.
  CaretStops get stops =>
      owner?.textOrder == TextOrder.visual && _obscuring == null
      ? _FieldStops(this)
      : const CaretStops();

  TextColumns _columnsWith(TextSegmenter segmenter) {
    final columns = _columns;
    return columns != null && identical(columns.segmenter, segmenter)
        ? columns
        : _columns = TextColumns(segmenter);
  }

  /// The columns the text or the placeholder takes, and one for the caret.
  int _measure() {
    final segmenter = owner?.segmenter ?? TextSegmenter();
    final shown = _shown;
    final w = shown.isEmpty
        ? segmenter.width(_placeholder)
        : (_columnsWith(segmenter)..measure(shown)).width;
    return _measured = w + 1;
  }

  /// Lays the field out again when its width follows its text and that
  /// asks for another; else repaints it.
  void _contentChanged() {
    _masked = null;
    final c = constraints;
    final follows =
        c == null || _widthAsked || c.maxW >= BoxConstraints.unbounded;
    if (follows && _measured != _measure()) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  @override
  void markNeedsLayout() {
    // the intrinsic sizes are forgotten
    _widthAsked = false;
    super.markNeedsLayout();
  }

  @override
  int computeMinIntrinsicWidth(int height) => 1;

  @override
  int computeMaxIntrinsicWidth(int height) {
    _widthAsked = true;
    return _measure();
  }

  @override
  int computeMinIntrinsicHeight(int width) => 1;

  @override
  int computeMaxIntrinsicHeight(int width) => 1;

  @override
  void performLayout(BoxConstraints c) {
    final measured = _measure();
    width = c.maxW >= BoxConstraints.unbounded
        ? c.constrainW(measured)
        : c.maxW;
    height = c.constrainH(1);
  }

  @override
  void detach() {
    final ctx = _painted;
    if (ctx != null) {
      hideCaret(ctx, this);
    }
    super.detach();
  }

  @override
  void paint(PaintContext ctx) {
    _painted = ctx;
    final canvas = ctx.canvas;
    final styles = canvas.styles;
    final base = _opaque.merge(_style);
    canvas.fill(0, 0, width, height, base.penIn(styles));
    final shown = _shown;
    final columns = _columnsWith(canvas.segmenter)..measure(shown);
    final bidi = _bidiOf(shown, columns);
    final row = bidi ?? columns;
    final caret = row.columnOf(_shownOffset(_selection.extentOffset));
    _scrollTo(caret, row);
    final indent = _indent = shown.isEmpty ? 0 : _indentOf(row.width + 1, bidi);
    final x = indent - _scroll;
    if (shown.isEmpty) {
      final placeholderWidth = canvas.segmenter.width(_placeholder);
      final at = _indentOf(placeholderWidth + 1, null);
      canvas.text(
        at,
        0,
        _placeholder,
        base.merge(_placeholderStyle).penIn(styles),
      );
      _indent = _indentOf(1, null);
    } else if (bidi != null) {
      _paintBidi(canvas, x, shown, bidi, base);
    } else {
      final selected = _focused && !_selection.isCollapsed;
      final composed = _composing.isValid && !_composing.isCollapsed;
      if (!selected && !composed) {
        canvas.text(x, 0, shown, base.penIn(styles));
      } else {
        final ss = selected ? _shownOffset(_selection.start) : 0;
        final se = selected ? _shownOffset(_selection.end) : 0;
        final cs = composed ? _shownOffset(_composing.start) : 0;
        final ce = composed ? _shownOffset(_composing.end) : 0;
        final cuts = _cuts
          ..[0] = 0
          ..[1] = ss
          ..[2] = se
          ..[3] = cs
          ..[4] = ce
          ..[5] = shown.length;
        final n = sortedOnce(cuts);
        for (var i = 0; i + 1 < n; i++) {
          final from = cuts[i];
          final to = cuts[i + 1];
          var s = base;
          if (selected && from >= ss && to <= se) {
            s = s.merge(_selectionStyle);
          }
          if (composed && from >= cs && to <= ce) {
            s = s.merge(_underline);
          }
          canvas.text(
            x + columns.columnOf(from),
            0,
            shown.substring(from, to),
            s.penIn(styles),
          );
        }
      }
    }
    if (_focused && width > 0 && height > 0) {
      showCaret(ctx, this, _indent + caret - _scroll, 0, shape: _cursorShape);
    } else {
      hideCaret(ctx, this);
    }
  }

  /// The columns before what is shown, [columns] wide with the caret's,
  /// by [textAlign]; none where it does not fit. [bidi] is how the text is
  /// drawn, whose paragraph's direction places it at the start or the end.
  int _indentOf(int columns, BidiRow? bidi) {
    final room = width - columns;
    if (room <= 0) {
      return 0;
    }
    final rtl = bidi != null && bidi.directionAt(0) == TextDirection.rtl;
    return switch (_textAlign) {
      TextAlign.left || TextAlign.justify => 0,
      TextAlign.center => room ~/ 2,
      TextAlign.right => room,
      TextAlign.start => rtl ? room : 0,
      TextAlign.end => rtl ? 0 : room,
    };
  }

  /// Paints [shown] in the order [bidi] draws it from column [x], the
  /// selection and the composing range in their styles over [base].
  void _paintBidi(
    Canvas canvas,
    int x,
    String shown,
    BidiRow bidi,
    Style base,
  ) {
    final styles = canvas.styles;
    final selected = _focused && !_selection.isCollapsed;
    final composed = _composing.isValid && !_composing.isCollapsed;
    final ss = selected ? _shownOffset(_selection.start) : 0;
    final se = selected ? _shownOffset(_selection.end) : 0;
    final cs = composed ? _shownOffset(_composing.start) : 0;
    final ce = composed ? _shownOffset(_composing.end) : 0;
    final selectedStyle = base.merge(_selectionStyle);
    final pens = [
      base.penIn(styles),
      selectedStyle.penIn(styles),
      base.merge(_underline).penIn(styles),
      selectedStyle.merge(_underline).penIn(styles),
    ];
    drawBidiRow(
      canvas,
      x,
      0,
      shown,
      bidi,
      (o) => pens[(o >= ss && o < se ? 1 : 0) | (o >= cs && o < ce ? 2 : 0)],
    );
  }

  /// The offset the caret goes to for a press in column [x]: of the
  /// character drawn there, a wide one's second column too, through the
  /// scroll; the end of the text past it. Null before the field is laid
  /// out.
  int? offsetAt(int x) {
    if (owner == null || constraints == null) {
      return null;
    }
    final shown = _shown;
    if (shown.isEmpty) {
      return 0;
    }
    final columns = _columnsWith(owner!.segmenter)..measure(shown);
    final shifted = x - _indent + _scroll;
    final column = shifted < 0 ? 0 : shifted;
    final bidi = _bidiOf(shown, columns);
    final int at;
    if (bidi != null) {
      at = bidi.offsetAt(column);
    } else {
      final starts = columns.starts;
      final cs = columns.columns;
      var k = 0;
      while (k + 1 < cs.length && cs[k + 1] <= column) {
        k++;
      }
      at = starts[k];
    }
    final mask = _obscuring;
    return mask == null ? at : _text.characterOffset(at ~/ mask.length);
  }

  /// Scrolls as little as keeps the [caret]'s column in view, at the start
  /// of a cluster, without blank columns after the text but the caret's.
  void _scrollTo(int caret, RowColumns columns) {
    final w = width;
    if (w <= 0) {
      return;
    }
    final most = columns.width + 1 - w;
    var s = _scroll < most ? _scroll : (most < 0 ? 0 : most);
    s = columns.startAtOrBefore(s);
    if (caret < s) {
      s = caret;
    } else if (caret > s + w - 1) {
      s = columns.startAtOrAfter(caret - w + 1);
    }
    _scroll = s;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add('text', _obscuring == null ? _text : _shown)
      ..add('selection', _selection)
      ..add('composing', _composing, defaultValue: TextRange.empty)
      ..add('scroll', _scroll, defaultValue: 0);
    if (_focused) {
      properties.addTag('focused');
    }
  }
}

/// Where the editing keys move the caret in a [TextField] that draws its
/// text in visual order: Left and Right a cell boundary at a time as it is
/// drawn, staying put at its edges; Ctrl and Alt with them a word back or
/// on as the caret's paragraph runs; the selection collapsing to the end
/// drawn on that side. A text without right-to-left characters, as it is
/// stored.
final class _FieldStops extends CaretStops {
  const _FieldStops(this.field);

  final _RenderTextField field;

  BidiRow? _row(TextBuffer text) => field._bidiOf(text.text);

  @override
  int left(TextBuffer text, int offset) {
    final row = _row(text);
    return row == null
        ? super.left(text, offset)
        : row.moveLeft(offset) ?? offset;
  }

  @override
  int right(TextBuffer text, int offset) {
    final row = _row(text);
    return row == null
        ? super.right(text, offset)
        : row.moveRight(offset) ?? offset;
  }

  @override
  int wordLeft(TextBuffer text, int offset) =>
      _row(text)?.directionAt(offset) == TextDirection.rtl
      ? wordAfter(text, offset)
      : wordBefore(text, offset);

  @override
  int wordRight(TextBuffer text, int offset) =>
      _row(text)?.directionAt(offset) == TextDirection.rtl
      ? wordBefore(text, offset)
      : wordAfter(text, offset);

  @override
  int selectionLeft(TextBuffer text, TextSelection selection) {
    final row = _row(text);
    if (row == null) {
      return super.selectionLeft(text, selection);
    }
    final b = row.columnOf(selection.baseOffset);
    final e = row.columnOf(selection.extentOffset);
    return b == e
        ? selection.start
        : (b < e ? selection.baseOffset : selection.extentOffset);
  }

  @override
  int selectionRight(TextBuffer text, TextSelection selection) {
    final row = _row(text);
    if (row == null) {
      return super.selectionRight(text, selection);
    }
    final b = row.columnOf(selection.baseOffset);
    final e = row.columnOf(selection.extentOffset);
    return b == e
        ? selection.end
        : (b > e ? selection.baseOffset : selection.extentOffset);
  }
}
