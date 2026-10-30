/// Lines of text the user edits: [TextArea].
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
        Mod,
        PaintContext,
        PasteEvent,
        PipelineTextOrder,
        RenderObject,
        StyleTable,
        TextMode,
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
import '../text/widgets.dart' show DefaultTextStyle;
import 'autocomplete.dart';
import 'bidi_row.dart';
import 'caret.dart';
import 'editing_keys.dart';
import 'field_mouse.dart';
import 'text_buffer.dart';
import 'text_editing.dart';
import 'text_field.dart';
import 'text_rows.dart';

/// A text area: lines of text the user edits, which its [controller]
/// holds, each line broken by word into rows as wide as the area.
///
/// It is as many rows tall as its text takes, at least [minLines] and at
/// most [maxLines], within its constraints; beyond, it scrolls to keep the
/// caret in view. As wide as its constraints allow; where they do not
/// limit its width, and asked for the width it would like
/// (`IntrinsicWidth`), as wide as its widest line and a column for the
/// caret.
///
/// A message box of three to eight rows, sent with Enter, a line broken
/// with Alt+Enter:
///
/// ```dart
/// final controller = TextEditingController();
/// final box = TextArea(
///   controller: controller,
///   placeholder: 'write a message',
///   minLines: 3,
///   maxLines: 8,
///   autofocus: true,
///   onSubmitted: (text) {
///     print('send $text');
///     controller.clear();
///   },
/// );
/// ```
///
/// A row breaks after blanks and between two wide characters (CJK), a word
/// longer than a row between characters; blanks at the end of a row hang
/// past its edge. The caret after a line takes a column of its own: on a
/// row of its own after a full one.
///
/// While it has the focus, the keys edit as in a [TextField]: characters,
/// words, Shift selecting, Backspace and Delete, with the ends of the
/// caret's line for Home, End, Ctrl+A, Ctrl+E, Ctrl+U and Ctrl+K (Ctrl+U
/// and Ctrl+K at the start and the end join the lines); Ctrl+Z undoes,
/// Ctrl+Y redoes; Ctrl+C copies the selection to the system clipboard,
/// its line breaks too, Ctrl+X cuts it. And:
///
/// * Up and Down move the caret a row, wrapped or not, to the column it
///   had before the first of them; from the first row Up moves it to the
///   start of the text, from the last Down to the end. PageUp and PageDown
///   move it as many rows as the area shows, and the text with it.
///   Ctrl+Home and Ctrl+End move it to the ends of the text. With Shift
///   each of them selects;
/// * Enter breaks the line; with [onSubmitted], Enter calls
///   [onEditingComplete] and then it with the text instead, and Alt+Enter
///   (Shift+Enter where the terminal tells it apart) breaks the line;
/// * a paste (bracketed paste) goes to [onPaste] first; unless that takes
///   it, it goes in as typed, its line breaks too, without its other
///   control characters but tabs.
///
/// [onEditingComplete] is called as well as the focus leaves the area
/// after a change the user made since it was called last. [readOnly] and
/// [enabled] go as a [TextField]'s: read-only, the keys that move the
/// caret by rows and the others that move and select do what they do, and
/// Enter submits, but nothing changes the text, the keys that would going
/// up, Enter that would break the line too, and Ctrl+X: Ctrl+C copies;
/// disabled, the area takes neither the focus nor the mouse and shows in
/// [disabledStyle].
///
/// The mouse goes as in a [TextField]: a press focuses the area and
/// places the caret at the character in the cell, through the scroll (past
/// the end of a row, its end; below the last row, the end of the text); a
/// drag selects, across rows and lines; a double press selects the word in
/// the line, a triple press the line, between its line breaks.
///
/// The keys it does not take go up to the nodes above its [Focus]: Tab,
/// Escape, Up on the start of the text and Down at its end, Ctrl+Z and
/// Ctrl+Y with nothing to undo or redo, Ctrl+C and Ctrl+X with nothing
/// selected, and those with Ctrl or Alt it does not name. [onChanged] is
/// called with the text after each change the user makes, [onEdited] with
/// the controller's value, its text read only as it is asked for.
///
/// While it has the focus, the keys it takes that do more than move and
/// delete are among those a `KeyHintsBar` shows
/// (`FocusManagerKeys.activeKeys`), unless [keyHints] is false: Enter
/// `new line`, or with [onSubmitted] Enter `submit` and Alt+Enter `new
/// line`; Ctrl+C `copy` and Ctrl+X `cut` while something is selected;
/// Ctrl+Z `undo` while there is a change to undo; an `Autocomplete`'s keys
/// before them while its suggestions show.
///
/// The terminal's cursor, in [cursorShape] (a bar by default), shows the
/// caret while the area has the focus; the selection shows in
/// [selectionStyle] meanwhile, a line break in it as a cell. Empty, the
/// area shows [placeholder]. The controller's composing range shows
/// underlined. The styles are a [TextField]'s.
///
/// A screen reader reads it as a [SemanticsRole.textBox] of its
/// [semanticsLabel], or of its placeholder without one, as a [TextField]
/// is, its text as its value, a line for each of its lines; the text is
/// put together only as it is read. Disabled, `disabled` after it.
///
/// In visual order (`PipelineOwner.textOrder`) each row with right-to-left
/// characters, and each of a line whose first strong character is right
/// to left, is drawn in the order UAX #9 gives in its line's direction,
/// from the left edge; the rows are broken as the text is stored. The
/// caret and the keys go as in a [TextField] in visual order, Left and
/// Right a cell at a time as the row is drawn and at its edge on into the
/// row after as the line runs, or back into the row before; Up and Down
/// keep the column as drawn.
///
/// A repaint boundary: a keystroke repaints nothing else, unless the area
/// grows or shrinks. It lays out and paints the rows in view and those it
/// counts for its height only, and reads its text in the pieces the
/// controller keeps it in; an edit breaks into rows again the rows from
/// the one before it on, until one starts where one started before. So a
/// keystroke costs as much in a megabyte of text, of many lines or of
/// one, as in a line. Of the rows in view it paints those whose text or
/// selection changed: a scroll, or a line break typed or deleted, moves
/// the others on the screen with them. A line is broken into rows from
/// its start as far as is shown, once: so moving to the end of a line of
/// a megabyte, or above it from the line after it, takes as long as
/// that.
///
/// See also:
///
///  * [TextField], a line of text.
///  * `Autocomplete`, which suggests what to type.
final class TextArea extends StatefulWidget {
  /// An area of the text of [controller], or of one of its own.
  ///
  /// It asserts that [minLines] is above 0 and [maxLines], where given,
  /// not below it.
  const TextArea({
    super.key,
    this.controller,
    this.placeholder,
    this.semanticsLabel,
    this.minLines = 1,
    this.maxLines,
    this.onChanged,
    this.onEdited,
    this.onSubmitted,
    this.onEditingComplete,
    this.onPaste,
    this.readOnly = false,
    this.enabled = true,
    this.focusNode,
    this.autofocus = false,
    this.canRequestFocus,
    this.style,
    this.placeholderStyle,
    this.selectionStyle,
    this.disabledStyle,
    this.cursorShape = CursorShape.bar,
    this.keyHints = true,
  }) : assert(minLines > 0, 'minLines below 1'),
       assert(maxLines == null || maxLines >= minLines, 'maxLines < minLines');

  /// What it edits; null for one of its own, empty.
  final TextEditingController? controller;

  /// What it shows while its text is empty; null for nothing.
  final String? placeholder;

  /// What a screen reader calls the area, what its text is: `Notes`;
  /// null, or empty, for its [placeholder], as [TextField.semanticsLabel].
  final String? semanticsLabel;

  /// The fewest rows it takes.
  final int minLines;

  /// The most rows it takes; null for as many as its text takes.
  final int? maxLines;

  /// Called with the text after each change the user makes. The text is
  /// put together for it from the pieces the controller keeps it in: for a
  /// large text a copy of it each keystroke, which [onEdited] and a
  /// listener of the controller do not pay for.
  final void Function(String text)? onChanged;

  /// Called with the controller's value after each change the user makes,
  /// as [onChanged] is with its text, before it: the value's text is put
  /// together from the pieces the controller keeps it in only when it is
  /// read (`TextEditingValue.text`), once for the value. So that a change
  /// in a large text costs as much as in a short one until the text is
  /// read.
  final void Function(TextEditingValue value)? onEdited;

  /// Called with the text when Enter is pressed; null for Enter to break
  /// the line.
  final void Function(String text)? onSubmitted;

  /// Called when Enter submits, before [onSubmitted], and as the focus
  /// leaves the area after a change the user made since it was called
  /// last; not on Enter that breaks the line.
  final VoidCallback? onEditingComplete;

  /// Called with what is pasted, as the terminal gave it, while the area
  /// has the focus, before it goes in: true when the app took it, and
  /// nothing goes in; false for it to go in as ever.
  final bool Function(String text)? onPaste;

  /// Whether nothing the user does changes the text: the caret moves and
  /// selects, nothing is typed, deleted, undone or pasted.
  final bool readOnly;

  /// Whether the area takes the focus and the mouse; false shows it in
  /// [disabledStyle].
  final bool enabled;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// See [FocusNode.canRequestFocus].
  final bool? canRequestFocus;

  /// Every cell, the theme's surface and text under it.
  final Style? style;

  /// The placeholder; [ThemeData.muted] when null.
  final Style? placeholderStyle;

  /// The selection while the area has the focus; [ThemeData.selection]
  /// when null.
  final Style? selectionStyle;

  /// Every cell while the area is disabled ([enabled] false), over
  /// [style]; [ThemeData.muted] when null.
  final Style? disabledStyle;

  /// The shape of the terminal's cursor at the caret while the area has the
  /// focus: a steady bar by default, or a block or an underline, each
  /// steady or blinking ([CursorShape]); [CursorShape.terminalDefault]
  /// for the shape the user set in the terminal.
  final CursorShape cursorShape;

  /// Whether the keys it takes that do more than move and delete carry
  /// their hints, for a `KeyHintsBar`; false leaves them out, the keys
  /// doing what they do still.
  final bool keyHints;

  @override
  State<TextArea> createState() => _TextAreaState();
}

final class _TextAreaState extends State<TextArea> {
  TextEditingController? _ownController;
  FocusNode? _ownNode;

  // what lays the text out, which moves the caret by rows
  _RenderTextArea? _area;

  // when onEditingComplete is called as the focus leaves
  final _completion = EditingCompletion();

  // whether the area was disabled, so that enabled again it may take the
  // focus again
  var _wasDisabled = false;

  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _completion.follow(_node, () => widget.onEditingComplete?.call());
  }

  @override
  void didUpdateWidget(TextArea oldWidget) {
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
    if (!node.hasFocus || event.kind == KeyKind.release) {
      return KeyEventResult.ignored;
    }
    final c = _controller;
    if (autocompleteTook(context, c, event)) {
      return KeyEventResult.handled;
    }
    final before = textBufferOf(c.value);
    final area = _area;
    if (event.code == KeyCode.enter) {
      final mods = event.modifiers;
      final submitted = widget.onSubmitted;
      if (mods == 0 && submitted != null) {
        _completion.done();
        widget.onEditingComplete?.call();
        submitted(c.text);
        return KeyEventResult.handled;
      }
      if (widget.readOnly ||
          (mods != 0 && mods != Mod.alt && mods != Mod.shift)) {
        return KeyEventResult.ignored;
      }
      _type('\n');
    } else if (area == null || !area.rowKey(c, event)) {
      if (!editingKey(
        c,
        event,
        _type,
        stops: area?.stops ?? _stops,
        readOnly: widget.readOnly,
        copy: _copy,
      )) {
        return KeyEventResult.ignored;
      }
    }
    _told(before);
    return KeyEventResult.handled;
  }

  static const _stops = CaretStops();

  void _copy(String text) => copyToClipboard(context, text);

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
    _type(_pasted(event.text));
    _told(before);
    return true;
  }

  /// Puts [text] in place of the selection.
  void _type(String text) {
    final c = _controller;
    if (text.isNotEmpty || !c.selection.isCollapsed) {
      c.insert(text);
    }
  }

  void _told(TextBuffer before) {
    final w = widget;
    final told =
        w.onChanged != null ||
        w.onEdited != null ||
        w.onEditingComplete != null;
    if (told && !textBufferOf(_controller.value).sameText(before)) {
      _completion.changed();
      w.onEdited?.call(_controller.value);
      w.onChanged?.call(_controller.text);
    }
  }

  /// [text] pasted (its line breaks `\n`, as the parser gives them)
  /// without the other control characters but tabs.
  static String _pasted(String text) => text.replaceAll(_controls, '');

  static final _controls = RegExp('[\x00-\x08\x0b-\x1f\x7f]');

  /// Whether [_onKey] takes the key of the hints named [key] now: Enter
  /// but while an `Autocomplete`'s suggestions show, Alt+Enter always.
  bool _takes(String key) => switch (key) {
    'enter' => !_suggesting,
    'ctrl+z' => !widget.readOnly && _controller.canUndo,
    'ctrl+c' => !_controller.selection.isCollapsed,
    'ctrl+x' => !widget.readOnly && !_controller.selection.isCollapsed,
    _ => true,
  };

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

  static const _hints = {
    'enter': 'new line',
    'ctrl+c': 'copy',
    'ctrl+x': 'cut',
    'ctrl+z': 'undo',
  };
  static const _submitHints = {
    'enter': 'submit',
    'alt+enter': 'new line',
    'ctrl+c': 'copy',
    'ctrl+x': 'cut',
    'ctrl+z': 'undo',
  };
  static const _readOnlyHints = {'ctrl+c': 'copy'};
  static const _readOnlySubmitHints = {'enter': 'submit', 'ctrl+c': 'copy'};

  /// The hints of the keys it takes.
  Map<String, String> get _hintsNow {
    final w = widget;
    if (!w.keyHints) {
      return const {};
    }
    final submits = w.onSubmitted != null;
    if (w.readOnly) {
      return submits ? _readOnlySubmitHints : _readOnlyHints;
    }
    return submits ? _submitHints : _hints;
  }

  /// What [Focus.canRequestFocus] is: false while disabled, true where it
  /// was and [TextArea.canRequestFocus] leaves it to the node.
  bool? get _canRequestFocus {
    if (!widget.enabled) {
      _wasDisabled = true;
      return false;
    }
    return widget.canRequestFocus ?? (_wasDisabled ? true : null);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final node = _node;
    return _AreaSemantics(
      this,
      child: InputListener(
        onEvent: _onEvent,
        child: HintedKeys(
          node: node,
          hints: _hintsNow,
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
                offsetAt: (x, y) => _area?.offsetAt(x, y),
                wordAt: (text, offset) {
                  final line = text.lineOf(offset);
                  return wordIn(
                    text,
                    offset,
                    text.lineStart(line),
                    text.lineEnd(line),
                  );
                },
                lineAt: (text, offset) {
                  final line = text.lineOf(offset);
                  return TextRange(
                    start: text.lineStart(line),
                    end: text.lineEnd(line),
                  );
                },
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) => _Area(this, controller.value),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A [TextArea] as a screen reader reads it, its text as it is when read.
final class _AreaSemantics extends Semantics {
  const _AreaSemantics(this.editor, {required super.child})
    : super(role: SemanticsRole.textBox);

  final _TextAreaState editor;

  @override
  String? get label => switch (editor.widget) {
    TextArea(semanticsLabel: final label?) when label.isNotEmpty => label,
    TextArea(:final placeholder) => placeholder,
  };

  @override
  String get value => editor._controller.text;

  @override
  SemanticsState get state =>
      editor.widget.enabled ? _enabled : const SemanticsState(disabled: true);
}

const _enabled = SemanticsState();

/// The text of a [TextArea] as its controller has it, in its theme's
/// styles where the area has none, the caret shown while the [Focus]
/// above it has the focus.
final class _Area extends LeafRenderObjectWidget {
  const _Area(this.state, this.value);

  final _TextAreaState state;
  final TextEditingValue value;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final area = _RenderTextArea();
    updateRenderObject(context, area);
    return area;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderTextArea renderObject,
  ) {
    final a = state.widget;
    final theme = Theme.of(context);
    // over what is under it: the theme's text and the DefaultTextStyle's
    // colors, no background of the theme's
    var style = theme.text
        .merge(DefaultTextStyle.of(context))
        .merge(a.style ?? _plain);
    if (!a.enabled) {
      style = style.merge(a.disabledStyle ?? theme.muted);
    }
    state._area = renderObject
      ..text = textBufferOf(value)
      ..selection = value.selection
      ..composing = value.composing
      ..placeholder = a.placeholder ?? ''
      ..lines = (a.minLines, a.maxLines)
      ..focused = Focus.of(context).hasFocus
      ..style = style
      ..placeholderStyle = a.placeholderStyle ?? theme.muted
      ..selectionStyle = a.selectionStyle ?? theme.selection
      ..cursorShape = a.cursorShape;
  }
}

const _plain = Style();
const _underline = Style(attrs: Attr.underline);
// the text color under the style's; no background: the area paints over
// what is under it, which the core keeps for it and it puts back under the
// rows it repaints (keepsUnderlay)
const _opaque = Style(fg: Color.defaultColor);
const int _unbounded = BoxConstraints.unbounded;

/// What a [TextArea] lays out and paints: the rows of its text in view,
/// scrolled to keep the caret's in view, and the terminal's cursor at the
/// caret while [focused].
final class _RenderTextArea extends RenderObject {
  // where a row with a selection or a composing range is painted in
  // pieces ([sortedOnce])
  final _cuts = Int32List(6);

  TextBuffer _text = TextBuffer.empty;
  TextBuffer get text => _text;
  set text(TextBuffer t) {
    if (!identical(t, _text)) {
      _text = t;
      _contentChanged();
    }
  }

  var _placeholder = '';
  String get placeholder => _placeholder;
  set placeholder(String p) {
    if (p != _placeholder) {
      _placeholder = p;
      _shownText = null;
      markNeedsPaint();
    }
  }

  /// The fewest and the most rows, null for no most.
  (int, int?) _lines = (1, null);
  (int, int?) get lines => _lines;
  set lines((int, int?) l) {
    if (l != _lines) {
      _lines = l;
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
      _shownText = null;
      markNeedsPaint();
    }
  }

  Style _placeholderStyle = _plain;
  Style get placeholderStyle => _placeholderStyle;
  set placeholderStyle(Style s) {
    if (s != _placeholderStyle) {
      _placeholderStyle = s;
      _shownText = null;
      markNeedsPaint();
    }
  }

  Style _selectionStyle = _plain;
  Style get selectionStyle => _selectionStyle;
  set selectionStyle(Style s) {
    if (s != _selectionStyle) {
      _selectionStyle = s;
      _shownText = null;
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

  final _rows = TextRows();

  /// The first row shown.
  RowOf _top = (line: 0, row: 0);

  // the column Up and Down keep, the caret they left and its text
  var _goal = 0;
  var _goalAt = -1;
  TextBuffer? _goalText;

  // the size the text asked for at the last layout or question of a
  // parent (see _measure), and whether a parent asked for its width or
  // its height since the last layout
  (int, int)? _measured;
  var _widthAsked = false;
  var _heightAsked = false;

  // the widest line's columns, the text they are of and the segmenter
  // that measured it; the columns of each of its lines
  var _widest = 0;
  TextBuffer? _widestOf;
  TextSegmenter? _widestBy;
  TextMode _widestMode = TextMode.graphemes;
  var _widestAmbiguous = 1;
  var _lineColumns = Int32List(0);
  TextColumns? _columns;

  // what painted it last
  PaintContext? _painted;

  // what each row in view shows since the last paint, _shownInts ints a
  // row (see _paintRows), and the text, the width, the rows' layouts and
  // the styles it shows them in; no text when all of it is to be painted
  // again
  TextBuffer? _shownText;
  var _shown = Int32List(0);
  var _shownWidth = 0;
  var _shownLayouts = 0;
  StyleTable? _shownStyles;
  // the table's sweeps when _shown was painted: its style ids are of then
  var _shownSweeps = 0;
  static const _shownInts = 7;

  // the rows the last paint painted: how many, the first and the last
  var _paintedRows = 0;
  var _firstPainted = -1;
  var _lastPainted = -1;

  static final _detached = TextSegmenter();

  TextSegmenter get _segmenter => owner?.segmenter ?? _detached;

  /// Whether the text is drawn in visual order.
  bool get _visual => owner?.textOrder == TextOrder.visual;

  /// The rows of [text] at [width].
  TextRows _rowsOf(TextBuffer text, int width) =>
      _rows..update(text, width, _segmenter, visual: _visual);

  /// Where the editing keys move the caret: in the caret's line; in visual
  /// order, Left and Right as its rows are drawn.
  CaretStops get stops => _visual ? _AreaStops(this) : const _LineStops();

  @override
  bool get isRepaintBoundary => true;

  // over what is under it, put back under the rows it repaints: the rows
  // it keeps it does not repaint
  @override
  bool get keepsUnderlay => true;

  @override
  bool get putsUnderlayBack => false;

  /// The rows the text takes at [width], between the fewest and the most;
  /// counted up to [most].
  int _rowsWanted(int width, int most) {
    final (fewest, max) = _lines;
    final cap = max != null && max < most ? max : most;
    final rows = _rowsOf(_text, width).count(cap);
    return rows < fewest ? fewest : rows;
  }

  /// The columns of the widest line: of the lines an edit reached since
  /// the text measured last measured again, the others' kept.
  int _widestLine() {
    final text = _text;
    final old = _widestOf;
    if (identical(old, text)) {
      return _widest;
    }
    final segmenter = _segmenter;
    final n = text.lineCount;
    // the lines from first to last of the old text are those from first
    // to newLast of the new; all of them when it can't tell
    var first = 0;
    var newLast = n - 1;
    final change =
        old != null &&
            identical(segmenter, _widestBy) &&
            segmenter.mode == _widestMode &&
            segmenter.ambiguousWidth == _widestAmbiguous
        ? text.changeSince(old)
        : null;
    var widths = _lineColumns;
    if (change == null) {
      if (widths.length < n) {
        widths = _lineColumns = Int32List(n);
      }
    } else {
      first = old!.lineOf(change.start);
      final last = old.lineOf(change.oldEnd);
      newLast = text.lineOf(change.newEnd);
      final oldN = old.lineCount;
      if (widths.length < n) {
        widths = _lineColumns = Int32List(n * 2)..setRange(0, oldN, widths);
      }
      // the lines after the change move to where they are now
      widths.setRange(newLast + 1, n, widths, last + 1);
    }
    final columns = _columns?.segmenter == segmenter
        ? _columns!
        : _columns = TextColumns(segmenter);
    for (var l = first; l <= newLast; l++) {
      columns.measure(text.substring(text.lineStart(l), text.lineEnd(l)));
      widths[l] = columns.width;
    }
    var widest = 0;
    for (var l = 0; l < n; l++) {
      if (widths[l] > widest) {
        widest = widths[l];
      }
    }
    _widestOf = text;
    _widestBy = segmenter;
    _widestMode = segmenter.mode;
    _widestAmbiguous = segmenter.ambiguousWidth;
    return _widest = widest;
  }

  /// What of the area's size follows its text at [c]: the columns of the
  /// widest line and the caret's where [c] leaves the width to it or a
  /// parent asked for it (else -1), and the rows it would like where [c]
  /// leaves the height to it or a parent asked for it (else -1).
  (int, int) _measure(BoxConstraints c) {
    final widthFollows = _widthAsked || c.maxW >= _unbounded;
    final wanted = widthFollows ? _widestLine() + 1 : -1;
    final heightFollows = _heightAsked || c.minH < c.maxH;
    final at = c.maxW >= _unbounded ? wanted : c.maxW;
    final most = _heightAsked ? _unbounded : c.maxH;
    return _measured = (wanted, heightFollows ? _rowsWanted(at, most) : -1);
  }

  /// Lays the area out again when its size follows its text and that
  /// asks for another; else repaints it.
  void _contentChanged() {
    final c = constraints;
    final measured = _measured;
    if (c == null || measured == null || measured != _measure(c)) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  @override
  void markNeedsLayout() {
    // the intrinsic sizes are forgotten
    _widthAsked = false;
    _heightAsked = false;
    super.markNeedsLayout();
  }

  @override
  int computeMinIntrinsicWidth(int height) => 1;

  @override
  int computeMaxIntrinsicWidth(int height) {
    _widthAsked = true;
    return _widestLine() + 1;
  }

  @override
  int computeMinIntrinsicHeight(int width) => computeMaxIntrinsicHeight(width);

  @override
  int computeMaxIntrinsicHeight(int width) {
    _heightAsked = true;
    return _rowsWanted(width, _unbounded);
  }

  @override
  void performLayout(BoxConstraints c) {
    final (wanted, rows) = _measure(c);
    width = c.maxW >= _unbounded ? c.constrainW(wanted) : c.maxW;
    height = c.constrainH(rows);
  }

  @override
  void detach() {
    final ctx = _painted;
    if (ctx != null) {
      hideCaret(ctx, this);
    }
    super.detach();
  }

  /// Does what [event] does to [c] as a key that moves the caret by rows
  /// or to the ends of the text, and returns whether it is one.
  bool rowKey(TextEditingController c, KeyEvent event) {
    final mods = event.modifiers;
    final shift = mods & Mod.shift != 0;
    final rest = mods & ~Mod.shift;
    final page = height < 1 ? 1 : height;
    switch (event.code) {
      case KeyCode.up when rest == 0:
        return _moveRows(c, -1, shift, page: false);
      case KeyCode.down when rest == 0:
        return _moveRows(c, 1, shift, page: false);
      case KeyCode.pageUp when rest == 0:
        return _moveRows(c, -page, shift, page: true);
      case KeyCode.pageDown when rest == 0:
        return _moveRows(c, page, shift, page: true);
      case KeyCode.home when rest == Mod.ctrl:
        c.moveCaret(0, extend: shift);
      case KeyCode.end when rest == Mod.ctrl:
        c.moveCaret(textBufferOf(c.value).length, extend: shift);
      case _:
        return false;
    }
    return true;
  }

  /// Moves the caret of [c] [n] rows down (up for [n] below 0), to the
  /// column Up and Down keep, or with [extend] selects to there; from the
  /// first or the last row, to the end of the text that way. With [page]
  /// the text scrolls by as many rows. Returns whether that moved it.
  bool _moveRows(
    TextEditingController c,
    int n,
    bool extend, {
    required bool page,
  }) {
    final text = textBufferOf(c.value);
    final rows = _rowsOf(text, width);
    final caret = c.selection.extentOffset;
    final (at, column) = rows.place(caret);
    final goal = identical(text, _goalText) && caret == _goalAt
        ? _goal
        : column;
    final (to, moved) = rows.move(at, n);
    final int target;
    if (moved == 0) {
      target = n < 0 ? 0 : text.length;
      if (target == caret && (extend || c.selection.isCollapsed)) {
        return false;
      }
    } else {
      target = rows.offsetAt(to, goal);
    }
    if (page && moved != 0) {
      _top = rows.move(_within(rows, _top), moved).$1;
      markNeedsPaint();
    }
    c.moveCaret(target, extend: extend);
    _goal = goal;
    _goalAt = target;
    _goalText = textBufferOf(c.value);
    return true;
  }

  /// [at], or the last row of the text where it is past it.
  static RowOf _within(TextRows rows, RowOf at) {
    if (at.line >= rows.text.lineCount) {
      return rows.last;
    }
    final line = rows.of(at.line);
    return line.hasRow(at.row) ? at : (line: at.line, row: line.rowCount - 1);
  }

  /// The offset the caret goes to for a press in the cell ([x], [y]): of
  /// the character drawn there, a wide one's second column too, through
  /// the scroll; past the end of a row, its end; below the last row, the
  /// end of the text, above the first its start. Null before the area is
  /// laid out.
  int? offsetAt(int x, int y) {
    if (owner == null || constraints == null) {
      return null;
    }
    if (_text.length == 0 || width <= 0) {
      return 0;
    }
    final rows = _rowsOf(_text, width);
    final (at, moved) = rows.move(_within(rows, _top), y);
    if (moved < y) {
      return _text.length;
    }
    if (moved > y) {
      return 0;
    }
    return rows.offsetAt(at, x < 0 ? 0 : x);
  }

  static bool _before(RowOf a, RowOf b) =>
      a.line < b.line || a.line == b.line && a.row < b.row;

  /// Scrolls as little as keeps [caret]'s row in view, without blank rows
  /// after the text.
  void _scrollTo(TextRows rows, RowOf caret) {
    final h = height;
    var top = _within(rows, _top);
    if (_before(caret, top)) {
      top = caret;
    } else if (rows.span(top, caret, h + 1) > h) {
      top = rows.move(caret, 1 - h).$1;
    }
    // fewer rows than the area's from the top to the end of the text
    if (rows.move(top, h - 1).$2 < h - 1) {
      top = rows.move(rows.last, 1 - h).$1;
    }
    _top = top;
  }

  @override
  void invalidatePaintCache() => _shownText = null;

  @override
  void paint(PaintContext ctx) {
    _painted = ctx;
    if (width <= 0 || height <= 0) {
      _shownText = null;
      hideCaret(ctx, this);
      return;
    }
    final canvas = ctx.canvas;
    final styles = canvas.styles;
    final base = _opaque.merge(_style);
    final pen = base.penIn(styles);
    final rows = _rowsOf(_text, width);
    final (caret, column) = rows.place(_selection.extentOffset);
    _scrollTo(rows, caret);
    canvas
      ..save()
      ..clipRect(0, 0, width, height);
    final int y;
    if (_text.length == 0) {
      _shownText = null;
      _paintedRows = height;
      _firstPainted = 0;
      _lastPainted = height - 1;
      putUnderlayBack(canvas, 0, 0, width, height);
      canvas
        ..fill(0, 0, width, height, pen)
        ..text(
          0,
          0,
          _placeholder,
          base.merge(_placeholderStyle).penIn(styles),
        );
      y = rows.span(_top, caret, height + 1) - 1;
    } else {
      y = _paintRows(ctx, rows, caret, base, pen);
    }
    canvas.restore();
    if (_focused && y >= 0 && y < height) {
      showCaret(ctx, this, column, y, shape: _cursorShape);
    } else {
      hideCaret(ctx, this);
    }
    rows.sweep();
  }

  /// Paints the rows in view from the first shown on, in [base] (whose
  /// pen is [pen]): those the last paint showed as they are now are left
  /// as they are. Returns the row in view [caret] is on, -1 for none.
  ///
  /// What a row shows is its text and how it draws it: where it starts
  /// and ends in the text, the part of it selected and the part composed
  /// (from its start, empty as 0, 0), whether its line break shows
  /// selected (1), and in visual order whether it is drawn as a bidi row
  /// (2) of a line that runs right to left (4); the column it starts at
  /// follows from those. A row the last paint showed shows the same text
  /// when it ends before the change of the text since, or starts after
  /// it, moved by as much as it moved.
  ///
  /// A scroll moves the rows on the surface that are in view still
  /// ([_shiftOf]), and what they show with them; those it brought into
  /// view are painted. So does a change of the text that moved the rows
  /// after it ([_tailShiftOf]): a line break, or one deleted, paints the
  /// rows of its line and the one that came into view.
  int _paintRows(
    PaintContext ctx,
    TextRows rows,
    RowOf caret,
    Style base,
    int pen,
  ) {
    final canvas = ctx.canvas;
    final text = _text;
    final h = height;
    final w = width;
    const n = _shownInts;
    var shown = _shown;
    final shownText = _shownText;
    final change =
        shownText != null &&
            shown.length == h * n &&
            _shownWidth == w &&
            _shownLayouts == rows.layouts &&
            identical(_shownStyles, canvas.styles) &&
            canvas.styles.sweeps == _shownSweeps
        ? text.changeSince(shownText)
        : null;
    final whole = change == null;
    if (whole) {
      if (shown.length != h * n) {
        shown = _shown = Int32List(h * n);
      }
      putUnderlayBack(canvas, 0, 0, w, h);
      canvas.fill(0, 0, w, h, pen);
    }
    _paintedRows = 0;
    _firstPainted = _lastPainted = -1;
    final changeStart = change?.start ?? 0;
    final changeEnd = change?.oldEnd ?? 0;
    final moved = (change?.newEnd ?? 0) - changeEnd;
    if (!whole) {
      final shift = _shiftOf(rows, changeStart, changeEnd, moved);
      // the text changed: the rows after the change may show at others
      final edited = changeEnd != changeStart || moved != 0;
      final (gx, gy) = shift == 0 && !edited ? (0, 0) : globalOffset;
      // the surface can move only rows it has: an area partly off it (or
      // cut by an ancestor), or over rows not alike (a gradient down it),
      // paints the rows that show other text instead
      if ((shift != 0 || edited) &&
          canvas.clipContains(gx, gy, gx + w, gy + h) &&
          underlayRowsAlike) {
        if (shift != 0) {
          _scroll(ctx, gx, gy, 0, shift);
        }
        if (edited) {
          final (from, tail) = _tailShiftOf(rows, changeEnd, moved);
          if (tail != 0) {
            _scroll(ctx, gx, gy, from, tail);
          }
        }
      }
    }
    final selected = _focused && !_selection.isCollapsed;
    final composed = _composing.isValid && !_composing.isCollapsed;
    final visual = _visual;
    var caretY = -1;
    var line = _top.line;
    var row = _top.row;
    var y = 0;
    while (y < h) {
      final lineRows = rows.of(line);
      final start = lineRows.start;
      final from = start + lineRows.rowStart(row);
      final to = start + lineRows.rowEnd(row);
      final length = to - from;
      var ss = 0;
      var se = 0;
      if (selected) {
        ss = _clamp(_selection.start - from, length);
        se = _clamp(_selection.end - from, length);
        if (se <= ss) {
          ss = se = 0;
        }
      }
      var cs = 0;
      var ce = 0;
      if (composed) {
        cs = _clamp(_composing.start - from, length);
        ce = _clamp(_composing.end - from, length);
        if (ce <= cs) {
          cs = ce = 0;
        }
      }
      final last = !lineRows.hasRow(row + 1);
      final end = start + lineRows.length;
      var flags =
          selected &&
              last &&
              end < text.length &&
              _selection.start <= end &&
              end < _selection.end
          ? 1
          : 0;
      BidiRow? bidi;
      if (visual) {
        bidi = lineRows.bidiOf(row);
        if (bidi != null) {
          flags |= lineRows.isRtl ? 6 : 2;
        }
      }
      final k = y * n;
      var s = shown[k];
      var e = shown[k + 1];
      if (!whole && s >= 0 && e > changeStart) {
        if (s < changeEnd) {
          // the change is in it
          s = -1;
        } else {
          s += moved;
          e += moved;
        }
      }
      if (whole ||
          s != from ||
          e != to ||
          shown[k + 2] != ss ||
          shown[k + 3] != se ||
          shown[k + 4] != cs ||
          shown[k + 5] != ce ||
          shown[k + 6] != flags) {
        if (!whole) {
          putUnderlayBack(canvas, 0, y, w, 1);
          canvas.fill(0, y, w, 1, pen);
        }
        _paintRow(canvas, lineRows, row, y, base, pen, bidi);
        _painting(y);
      }
      shown
        ..[k] = from
        ..[k + 1] = to
        ..[k + 2] = ss
        ..[k + 3] = se
        ..[k + 4] = cs
        ..[k + 5] = ce
        ..[k + 6] = flags;
      if (line == caret.line && row == caret.row) {
        caretY = y;
      }
      y++;
      if (!last) {
        row++;
      } else if (line + 1 < text.lineCount) {
        line++;
        row = 0;
      } else {
        break;
      }
    }
    // the rows after the end of the text are blank
    for (; y < h; y++) {
      final k = y * n;
      if (whole || shown[k] != _blank) {
        if (!whole) {
          putUnderlayBack(canvas, 0, y, w, 1);
          canvas.fill(0, y, w, 1, pen);
        }
        _painting(y);
      }
      shown[k] = _blank;
    }
    _shownText = text;
    _shownWidth = w;
    _shownLayouts = rows.layouts;
    _shownStyles = canvas.styles;
    _shownSweeps = canvas.styles.sweeps;
    return caretY;
  }

  // what a row in view shows instead of where its text starts: a blank
  // row after the end of the text, or not known (a row a scroll brought
  // into view)
  static const _blank = -1;
  static const _unknown = -2;

  /// How many rows the text moved up in the area since the last paint
  /// (down where below 0), as the row the area starts with now was shown
  /// at another row or the row it started with is at another; 0 where
  /// neither, or the change of the text since reached it: from
  /// [changeStart] to [changeEnd] in the text shown, [moved] the code
  /// units the text after it moved by.
  int _shiftOf(TextRows rows, int changeStart, int changeEnd, int moved) {
    final h = height;
    var line = _top.line;
    var row = _top.row;
    var lineRows = rows.of(line);
    final top = lineRows.start + lineRows.rowStart(row);
    final first = _wasAt(0, changeStart, changeEnd, moved);
    if (top == first) {
      return 0;
    }
    if (first < 0 || top > first) {
      // the text moved up: the row it starts with now was shown lower
      for (var y = 1; y < h; y++) {
        final s = _wasAt(y, changeStart, changeEnd, moved);
        if (s == top) {
          return y;
        }
        if (s > top) {
          break;
        }
      }
      return 0;
    }
    // the text moved down: the row it started with is lower now
    for (var y = 1; y < h; y++) {
      if (lineRows.hasRow(row + 1)) {
        row++;
      } else if (line + 1 < rows.text.lineCount) {
        lineRows = rows.of(++line);
        row = 0;
      } else {
        break;
      }
      final s = lineRows.start + lineRows.rowStart(row);
      if (s == first) {
        return -y;
      }
      if (s > first) {
        break;
      }
    }
    return 0;
  }

  /// Moves the rows in view from [from] on up by [shift] (down where
  /// below 0) on the surface of [ctx], the area at ([gx], [gy]) on it, and
  /// what they show with them; those it leaves are not known.
  void _scroll(PaintContext ctx, int gx, int gy, int from, int shift) {
    final h = height;
    const n = _shownInts;
    final shown = _shown;
    ctx.surface.scrollRect(gx, gx + width, gy + from, gy + h, shift);
    if (shift > 0) {
      shown
        ..setRange(from * n, (h - shift) * n, shown, (from + shift) * n)
        ..fillRange((h - shift) * n, h * n, _unknown);
    } else {
      shown
        ..setRange((from - shift) * n, h * n, shown, from * n)
        ..fillRange(from * n, (from - shift) * n, _unknown);
    }
  }

  /// The rows in view that show the text after the change since the last
  /// paint (from [changeEnd] of the text shown on, [moved] the code units
  /// it moved by), as the first of them that starts a row now and the row
  /// it starts: the row the move starts at and how many rows they moved
  /// up (down where below 0), as [_scroll] takes them. (0, 0) when they
  /// are where they were, or none of them is in view as much as to keep a
  /// row: a line break, or one deleted, moves the rows below it by one,
  /// and a character typed none.
  (int, int) _tailShiftOf(TextRows rows, int changeEnd, int moved) {
    final h = height;
    const n = _shownInts;
    final shown = _shown;
    var line = _top.line;
    var row = _top.row;
    var lineRows = rows.of(line);
    var y = 0;
    var at = lineRows.start + lineRows.rowStart(row);
    for (var j = 0; j < h; j++) {
      final s = shown[j * n];
      if (s < changeEnd) {
        // a row before the change or in it, or of no text
        continue;
      }
      final target = s + moved;
      // the rows after the change start after those in it: a row on
      // from the last tried
      while (at < target) {
        if (++y == h) {
          return (0, 0);
        }
        if (lineRows.hasRow(row + 1)) {
          row++;
        } else if (line + 1 < rows.text.lineCount) {
          lineRows = rows.of(++line);
          row = 0;
        } else {
          return (0, 0);
        }
        at = lineRows.start + lineRows.rowStart(row);
      }
      if (at == target) {
        final from = j < y ? j : y;
        final shift = j - y;
        return shift.abs() < h - from ? (from, shift) : (0, 0);
      }
    }
    return (0, 0);
  }

  /// Where the text row [y] in view showed at the last paint starts in
  /// the text now ([_shiftOf]); below 0 for a row the change reached, or
  /// of no text.
  int _wasAt(int y, int changeStart, int changeEnd, int moved) {
    final k = y * _shownInts;
    final s = _shown[k];
    if (s < 0 || _shown[k + 1] <= changeStart) {
      return s;
    }
    return s < changeEnd ? -1 : s + moved;
  }

  /// Counts row [y] among those painted.
  void _painting(int y) {
    _paintedRows++;
    if (_firstPainted < 0) {
      _firstPainted = y;
    }
    _lastPainted = y;
  }

  /// [o] within 0 and [length].
  static int _clamp(int o, int length) => o < 0 ? 0 : (o > length ? length : o);

  /// Paints [row] of [line] at [y], drawn as [bidi] where there is one, the
  /// selection and the composing range in their styles over [base], whose
  /// pen is [pen].
  void _paintRow(
    Canvas canvas,
    LineRows line,
    int row,
    int y,
    Style base,
    int pen,
    BidiRow? bidi,
  ) {
    if (bidi != null) {
      _paintBidi(canvas, line, row, y, base, bidi);
      return;
    }
    final from = line.rowStart(row);
    final to = line.rowEnd(row);
    final selected = _focused && !_selection.isCollapsed;
    final composed = _composing.isValid && !_composing.isCollapsed;
    if (!selected && !composed) {
      canvas.text(0, y, line.text(from, to), pen);
      return;
    }
    final styles = canvas.styles;
    final start = line.start;
    final ss = selected ? _inRow(_selection.start - start, from, to) : from;
    final se = selected ? _inRow(_selection.end - start, from, to) : from;
    final cs = composed ? _inRow(_composing.start - start, from, to) : from;
    final ce = composed ? _inRow(_composing.end - start, from, to) : from;
    final cuts = _cuts
      ..[0] = from
      ..[1] = ss
      ..[2] = se
      ..[3] = cs
      ..[4] = ce
      ..[5] = to;
    final n = sortedOnce(cuts);
    for (var i = 0; i + 1 < n; i++) {
      final a = cuts[i];
      final b = cuts[i + 1];
      var s = base;
      if (selected && a >= ss && b <= se) {
        s = s.merge(_selectionStyle);
      }
      if (composed && a >= cs && b <= ce) {
        s = s.merge(_underline);
      }
      canvas.text(line.columnOf(a), y, line.text(a, b), s.penIn(styles));
    }
    // a line break selected shows as a cell after the line
    final end = start + line.length;
    if (selected &&
        !line.hasRow(row + 1) &&
        end < _text.length &&
        _selection.start <= end &&
        end < _selection.end) {
      final x = line.columnOf(line.length);
      canvas.text(x, y, ' ', base.merge(_selectionStyle).penIn(styles));
    }
  }

  /// [o], an offset in a line, within the row from [from] to [to].
  static int _inRow(int o, int from, int to) =>
      o < from ? from : (o > to ? to : o);

  /// Paints [row] of [line], drawn as [bidi], at [y], the selection and the
  /// composing range in their styles over [base].
  void _paintBidi(
    Canvas canvas,
    LineRows line,
    int row,
    int y,
    Style base,
    BidiRow bidi,
  ) {
    final styles = canvas.styles;
    final from = line.rowStart(row);
    final at = line.start + from;
    final selected = _focused && !_selection.isCollapsed;
    final composed = _composing.isValid && !_composing.isCollapsed;
    final ss = selected ? _selection.start - at : 0;
    final se = selected ? _selection.end - at : 0;
    final cs = composed ? _composing.start - at : 0;
    final ce = composed ? _composing.end - at : 0;
    final selectedStyle = base.merge(_selectionStyle);
    final pens = [
      base.penIn(styles),
      selectedStyle.penIn(styles),
      base.merge(_underline).penIn(styles),
      selectedStyle.merge(_underline).penIn(styles),
    ];
    final x = line.rowX(row);
    drawBidiRow(
      canvas,
      x,
      y,
      line.text(from, line.rowEnd(row)),
      bidi,
      (o) => pens[(o >= ss && o < se ? 1 : 0) | (o >= cs && o < ce ? 2 : 0)],
    );
    // a line break selected shows as a cell after the row
    final end = line.start + line.length;
    if (selected &&
        !line.hasRow(row + 1) &&
        end < _text.length &&
        _selection.start <= end &&
        end < _selection.end) {
      canvas.text(x + bidi.width, y, ' ', pens[1]);
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add('text', _text.text)
      ..add('lines', _text.lineCount)
      ..add('selection', _selection)
      ..add('composing', _composing, defaultValue: TextRange.empty)
      ..add('top', '${_top.line}:${_top.row}', defaultValue: '0:0')
      ..add('rows kept', _rows.kept)
      ..add(
        'rows painted',
        _paintedRows == 0
            ? 'none'
            : '$_paintedRows, $_firstPainted to $_lastPainted',
      );
    if (_focused) {
      properties.addTag('focused');
    }
  }
}

/// Where the editing keys move the caret in a text area: characters and
/// words in the caret's line and the one next to it, the ends of the
/// caret's line; at the start or the end of a line, over its line break.
final class _LineStops extends CaretStops {
  const _LineStops();

  @override
  int characterBefore(TextBuffer text, int offset) {
    final l = text.lineOf(offset);
    final start = text.lineStart(l);
    if (offset <= start) {
      return offset > 0 ? offset - 1 : 0;
    }
    return text.characterStartBefore(offset, from: start, to: text.lineEnd(l));
  }

  @override
  int characterAfter(TextBuffer text, int offset) {
    final l = text.lineOf(offset);
    final end = text.lineEnd(l);
    if (offset >= end) {
      return offset < text.length ? offset + 1 : offset;
    }
    return text.characterEndAfter(offset, from: text.lineStart(l), to: end);
  }

  @override
  int wordBefore(TextBuffer text, int offset, {bool blankDelimited = false}) {
    final l = text.lineOf(offset);
    return text.wordStartBefore(
      offset,
      blankDelimited: blankDelimited,
      from: text.lineStart(l > 0 ? l - 1 : 0),
      to: offset,
    );
  }

  @override
  int wordAfter(TextBuffer text, int offset) {
    final l = text.lineOf(offset);
    return text.wordEndAfter(
      offset,
      from: offset,
      to: text.lineEnd(l + 1 < text.lineCount ? l + 1 : l),
    );
  }

  @override
  int lineStart(TextBuffer text, int offset) =>
      text.lineStart(text.lineOf(offset));

  @override
  int lineEnd(TextBuffer text, int offset) => text.lineEnd(text.lineOf(offset));
}

/// Where the editing keys move the caret in a text area that draws its
/// text in visual order: Left and Right a cell boundary at a time as the
/// caret's row is drawn; at the row's edge on past it where the line runs
/// that way (the row after, or over the line break), else back before it;
/// Ctrl and Alt with them a word back or on as the line runs; the
/// selection collapsing to the end drawn on that side when both are on
/// one row. Rows drawn as stored, as [_LineStops] moves.
final class _AreaStops extends _LineStops {
  const _AreaStops(this.area);

  final _RenderTextArea area;

  @override
  int left(TextBuffer text, int offset) => _move(text, offset, false);

  @override
  int right(TextBuffer text, int offset) => _move(text, offset, true);

  int _move(TextBuffer text, int offset, bool right) {
    final rows = area._rowsOf(text, area.width);
    final (at, _) = rows.place(offset);
    final line = rows.of(at.line);
    final bidi = line.bidiOf(at.row);
    if (bidi == null) {
      return right
          ? characterAfter(text, offset)
          : characterBefore(text, offset);
    }
    final start = line.start + line.rowStart(at.row);
    // a blank hanging past the row before moves from the start of this one
    final o = offset < start ? 0 : offset - start;
    final to = right ? bidi.moveRight(o) : bidi.moveLeft(o);
    if (to != null) {
      return start + to;
    }
    if (right != line.isRtl) {
      if (line.hasRow(at.row + 1)) {
        return line.start + line.rowEnd(at.row);
      }
      return at.line + 1 < text.lineCount
          ? text.lineStart(at.line + 1)
          : offset;
    }
    if (at.row > 0) {
      return characterBefore(text, start);
    }
    return at.line > 0 ? start - 1 : offset;
  }

  bool _rtl(TextBuffer text, int offset) =>
      area._rowsOf(text, area.width).of(text.lineOf(offset)).isRtl;

  @override
  int wordLeft(TextBuffer text, int offset) =>
      _rtl(text, offset) ? wordAfter(text, offset) : wordBefore(text, offset);

  @override
  int wordRight(TextBuffer text, int offset) =>
      _rtl(text, offset) ? wordBefore(text, offset) : wordAfter(text, offset);

  @override
  int selectionLeft(TextBuffer text, TextSelection selection) =>
      _side(text, selection, left: true) ?? selection.start;

  @override
  int selectionRight(TextBuffer text, TextSelection selection) =>
      _side(text, selection, left: false) ?? selection.end;

  /// The end of [selection] drawn further [left] (or right) where both are
  /// on one row drawn in visual order at columns of their own; else null.
  int? _side(TextBuffer text, TextSelection selection, {required bool left}) {
    final rows = area._rowsOf(text, area.width);
    final (a, ca) = rows.place(selection.baseOffset);
    final (b, cb) = rows.place(selection.extentOffset);
    if (a != b || ca == cb || rows.of(a.line).bidiOf(a.row) == null) {
      return null;
    }
    return (ca < cb) == left ? selection.baseOffset : selection.extentOffset;
  }
}
