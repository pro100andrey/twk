/// The widgets the prompts of a [Cli] are in the interactive mode: a line
/// ([TextPromptView]), yes or no ([ConfirmPromptView]), one or any of a
/// list ([ChoicePromptView]), each answering through a [PromptAnswer].
///
/// @docImport 'cli.dart';
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:twk/twk.dart';

import 'prompt_exception.dart';
import 'prompts.dart' show choicesShown;
import 'theme.dart';

/// Where the widget of a prompt puts its answer, or why there is none,
/// for the prompt that mounted it to commit.
final class PromptAnswer<T> {
  /// The answer to [question], once given.
  PromptAnswer(this.question);

  /// The question asked.
  final String question;

  final _done = Completer<(T, String)>();

  /// Whether it is answered, cancelled or failed.
  bool get isDone => _done.isCompleted;

  /// The value answered and how the committed line shows it.
  Future<(T value, String shown)> get future => _done.future;

  /// Answers [value], shown as [shown]; once only.
  void give(T value, String shown) {
    if (!isDone) {
      _done.complete((value, shown));
    }
  }

  /// Leaves the question for [reason]; once only.
  void cancel(PromptCancelReason reason) {
    if (!isDone) {
      _done.completeError(PromptCancelledException(question, reason));
    }
  }

  /// Ends it with [error]: the session ended by one.
  void fail(Object error, StackTrace stack) {
    if (!isDone) {
      _done.completeError(error, stack);
    }
  }
}

/// Ctrl+C cancels [answer] as an interrupt and Ctrl+D as the end of
/// input, where [atEmpty] says the prompt is empty; the other keys that
/// reach it go to [onKey].
final class _PromptKeys extends StatelessWidget {
  const _PromptKeys({
    required this.answer,
    required this.child,
    this.atEmpty,
    this.onKey,
  });

  final PromptAnswer<Object?> answer;
  final bool Function()? atEmpty;
  final KeyEventResult Function(KeyEvent event)? onKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (node, event) {
      if (event.kind == KeyKind.release) {
        return KeyEventResult.ignored;
      }
      if (event.modifiers == Mod.ctrl && event.char == 'c') {
        answer.cancel(PromptCancelReason.interrupt);
        return KeyEventResult.handled;
      }
      if (event.modifiers == Mod.ctrl &&
          event.char == 'd' &&
          (atEmpty?.call() ?? true)) {
        answer.cancel(PromptCancelReason.endOfInput);
        return KeyEventResult.handled;
      }
      return onKey?.call(event) ?? KeyEventResult.ignored;
    },
    child: child,
  );
}

/// `? question (hint) `: how a prompt starts its row.
List<Span> _asking(CliTheme theme, String question, String? hint) => [
  Span('? ', theme.answer),
  Span(question, theme.question),
  if (hint != null && hint.isNotEmpty) Span(' ($hint)', theme.hint),
  const Span(' '),
];

/// `✗ message`, under a prompt whose answer was refused.
Widget _refusal(CliTheme theme, String message) =>
    Text.rich([Span('✗ ', theme.error), Span(message, theme.error)]);

/// A line of text to answer: the question, the default in [hint], then a
/// `TextField`, its text masked with `*` where [hidden]. Enter gives the
/// text to [submit], which answers or says why not: the message shows
/// under the field until the text changes.
///
/// With [suggest], what it gives for the text before the caret shows
/// under the field to choose from (`Autocomplete`), rows made for it in
/// the region.
final class TextPromptView extends StatefulWidget {
  /// A field answering through [answer].
  const TextPromptView({
    required this.answer,
    required this.theme,
    required this.question,
    required this.submit,
    super.key,
    this.hint,
    this.hidden = false,
    this.placeholder,
    this.suggest,
  });

  /// Where the answer goes; Ctrl+C and Ctrl+D at an empty field cancel it.
  final PromptAnswer<Object?> answer;

  /// The styles of the question, the hint and a refusal.
  final CliTheme theme;

  /// The question asked.
  final String question;

  /// Takes the text on Enter: null once it answered, else why not.
  final String? Function(String text) submit;

  /// The default, shown after the question; null for none.
  final String? hint;

  /// Whether the text shows as `*`.
  final bool hidden;

  /// What the empty field shows.
  final String? placeholder;

  /// What to suggest for the text before the caret.
  final FutureOr<List<String>> Function(String typed)? suggest;

  @override
  State<TextPromptView> createState() => _TextPromptViewState();
}

final class _TextPromptViewState extends State<TextPromptView> {
  final _controller = TextEditingController();
  String? _refused;

  // the rows the suggestions are shown in, below the field
  var _reserved = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_moved);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// No query, as the caret is at the start or text is selected: no
  /// suggestions.
  void _moved() {
    final selection = _controller.value.selection;
    if (_reserved > 0 &&
        (!selection.isCollapsed || selection.extentOffset <= 0)) {
      setState(() => _reserved = 0);
    }
  }

  void _shown(int count) {
    // the popup's rows, and its shadow's
    final rows = count == 0 ? 0 : math.min(count, 8) + 1;
    if (mounted && rows != _reserved) {
      setState(() => _reserved = rows);
    }
  }

  FutureOr<Iterable<Suggestion>> _suggestions(String typed) {
    List<Suggestion> of(List<String> texts) {
      _shown(texts.length);
      return [for (final text in texts) Suggestion(text)];
    }

    final given = widget.suggest!(typed);
    return given is Future<List<String>> ? given.then(of) : of(given);
  }

  void _submit(String text) {
    if (widget.answer.isDone) {
      return;
    }
    final refused = widget.submit(text);
    if (refused != _refused) {
      setState(() => _refused = refused);
    }
  }

  void _changed(String _) {
    if (_refused != null) {
      setState(() => _refused = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final suggest = widget.suggest;
    Widget field = TextField(
      controller: _controller,
      autofocus: true,
      obscureText: widget.hidden,
      obscuringCharacter: '*',
      placeholder: widget.placeholder,
      style: const Style(),
      focusedStyle: const Style(),
      keyHints: false,
      onChanged: _changed,
      onSubmitted: _submit,
    );
    if (suggest != null) {
      field = Autocomplete(
        controller: _controller,
        suggestions: _suggestions,
        onSelected: (_) => _shown(0),
        popupFadeIn: Duration.zero,
        keyHints: false,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          // Escape hides the suggestions, and their rows go
          onKeyEvent: (node, event) {
            if (event.code == KeyCode.escape && event.kind != KeyKind.release) {
              _shown(0);
            }
            return KeyEventResult.ignored;
          },
          child: field,
        ),
      );
    }
    Widget view = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text.rich(
              _asking(theme, widget.question, widget.hint),
              wrap: TextWrap.none,
            ),
            Expanded(child: field),
          ],
        ),
        if (_reserved > 0) SizedBox(height: _reserved),
        if (_refused case final refused?) _refusal(theme, refused),
      ],
    );
    if (suggest != null) {
      view = Overlay(child: view);
    }
    return _PromptKeys(
      answer: widget.answer,
      atEmpty: () => _controller.text.isEmpty,
      child: view,
    );
  }
}

/// Yes or no: the question, then the answers of a `ConfirmInput`. `y` and
/// `n` answer, either case; Left and Right highlight yes and no, Enter
/// answers the one highlighted, [defaultValue]'s at first. Without a
/// default neither is, and Enter answers nothing until one is: nothing is
/// agreed to on anybody's behalf.
final class ConfirmPromptView extends StatefulWidget {
  /// Yes or no, answering through [answer].
  const ConfirmPromptView({
    required this.answer,
    required this.theme,
    required this.question,
    required this.submit,
    super.key,
    this.defaultValue,
  });

  /// Where the answer goes; Ctrl+C and Ctrl+D cancel it.
  final PromptAnswer<Object?> answer;

  /// The styles of the question.
  final CliTheme theme;

  /// The question asked.
  final String question;

  /// Takes the answer.
  final void Function(bool value) submit;

  /// The answer highlighted at first; null for none.
  final bool? defaultValue;

  @override
  State<ConfirmPromptView> createState() => _ConfirmPromptViewState();
}

final class _ConfirmPromptViewState extends State<ConfirmPromptView> {
  late bool? _highlighted = widget.defaultValue;

  void _answer(bool value) {
    if (!widget.answer.isDone) {
      setState(() => _highlighted = value);
      widget.submit(value);
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event.kind == KeyKind.release || event.modifiers & ~Mod.shift != 0) {
      return KeyEventResult.ignored;
    }
    switch (event.code) {
      case KeyCode.char when event.char == 'y' || event.char == 'Y':
        _answer(true);
      case KeyCode.char when event.char == 'n' || event.char == 'N':
        _answer(false);
      case KeyCode.enter:
        if (_highlighted case final value?) {
          _answer(value);
        }
      case KeyCode.left:
        setState(() => _highlighted = true);
      case KeyCode.right:
        setState(() => _highlighted = false);
      case KeyCode.tab:
        // the answers are shown, not focused
        break;
      case _:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlighted = _highlighted;
    return _PromptKeys(
      answer: widget.answer,
      child: Focus(
        autofocus: true,
        onKeyEvent: _key,
        child: Row(
          children: [
            Text.rich(
              _asking(widget.theme, widget.question, null),
              wrap: TextWrap.none,
            ),
            ConfirmInput(
              '',
              // made anew as the highlight moves: it is shown, not focused
              key: ValueKey(highlighted),
              defaultValue: highlighted ?? true,
              onConfirmed: (_) {},
              highlightedStyle: highlighted == null
                  ? theme.surface.merge(
                      theme.muted.merge(const Style(attrsOff: Attr.bold)),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// One of a list, or any of it ([multiple]): the question, then a
/// `SelectionList` of [labels], [choicesShown] rows at most. Up and Down
/// move, Space toggles where [multiple], Enter gives the indices to
/// [submit], which answers or says why not: the message shows under the
/// list until the selection changes. With [filter], what is typed (Space
/// too, where not [multiple]) narrows the list to the labels it matches
/// ([fuzzyMatch]), shown after the question; Backspace takes it back.
final class ChoicePromptView extends StatefulWidget {
  /// A list answering through [answer].
  const ChoicePromptView({
    required this.answer,
    required this.theme,
    required this.question,
    required this.labels,
    required this.multiple,
    required this.submit,
    super.key,
    this.selected = const {},
    this.filter = false,
  });

  /// Where the answer goes; Ctrl+C and Ctrl+D with no filter typed cancel
  /// it.
  final PromptAnswer<Object?> answer;

  /// The styles of the question, the hint and a refusal.
  final CliTheme theme;

  /// The question asked.
  final String question;

  /// How each choice reads.
  final List<String> labels;

  /// Whether any number of them is chosen, rather than one.
  final bool multiple;

  /// The indices selected at first: one at most where not [multiple].
  final Set<int> selected;

  /// Whether what is typed filters the list.
  final bool filter;

  /// Takes the indices chosen, in order: null once it answered, else why
  /// not.
  final String? Function(Set<int> chosen) submit;

  @override
  State<ChoicePromptView> createState() => _ChoicePromptViewState();
}

final class _ChoicePromptViewState extends State<ChoicePromptView> {
  late final SelectionController<int> _selection = SelectionController(
    multiple: widget.multiple,
    selected: widget.selected,
    cursor: widget.multiple && widget.selected.isNotEmpty
        ? widget.selected.reduce(math.min)
        : null,
  )..addListener(_selectionChanged);

  var _query = '';
  late List<int> _shown = [for (var i = 0; i < widget.labels.length; i++) i];
  String? _refused;

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  // the first of [_shown] in view
  var _top = 0;

  void _selectionChanged() => setState(() => _refused = null);

  /// Where in [_shown] the cursor is.
  int _cursorAt() {
    final c = _selection;
    final key = c.cursor ?? (c.multiple ? null : c.selected.firstOrNull);
    final at = key == null ? -1 : _shown.indexOf(key);
    return at < 0 ? 0 : at;
  }

  void _filter(String query) {
    final labels = widget.labels;
    setState(() {
      _query = query;
      _shown = [
        for (var i = 0; i < labels.length; i++)
          if (fuzzyMatch(query, labels[i]) != null) i,
      ];
    });
    final first = _shown.firstOrNull;
    _selection.cursor = first;
    if (first != null && !widget.multiple) {
      _selection.select(first);
    }
  }

  KeyEventResult _key(KeyEvent event) {
    if (!widget.filter || event.modifiers & ~Mod.shift != 0) {
      return KeyEventResult.ignored;
    }
    if (event.code == KeyCode.char) {
      _filter('$_query${event.char}');
      return KeyEventResult.handled;
    }
    if (event.code == KeyCode.backspace && _query.isNotEmpty) {
      final runes = _query.runes.toList()..removeLast();
      _filter(String.fromCharCodes(runes));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _submit(int cursor) {
    if (widget.answer.isDone) {
      return;
    }
    final Set<int> chosen;
    if (widget.multiple) {
      chosen = {..._selection.selected};
    } else if (_shown.contains(cursor)) {
      chosen = {cursor};
    } else {
      return;
    }
    final refused = widget.submit(chosen);
    if (refused != _refused) {
      setState(() => _refused = refused);
    }
  }

  Widget _item(BuildContext context, int index) {
    final label = widget.labels[_shown[index]];
    final match = _query.isEmpty ? null : fuzzyMatch(_query, label);
    if (match == null) {
      return Text(label, wrap: TextWrap.none);
    }
    final marked = match.positions.toSet();
    final mark = widget.theme.answer.merge(const Style(attrs: Attr.bold));
    final spans = <Span>[];
    var offset = 0;
    for (final rune in label.runes) {
      final char = String.fromCharCode(rune);
      spans.add(marked.contains(offset) ? Span(char, mark) : Span(char));
      offset += char.length;
    }
    return Text.rich(spans, wrap: TextWrap.none);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final String hint;
    if (widget.filter && _query.isNotEmpty) {
      hint = '';
    } else if (widget.filter) {
      hint = widget.multiple
          ? 'type to filter, space to toggle'
          : 'type to filter';
    } else {
      hint = widget.multiple ? 'space to toggle' : '';
    }
    final rows = math.min(_shown.length, choicesShown);
    final at = _cursorAt();
    if (at < _top) {
      _top = at;
    } else if (at >= _top + rows) {
      _top = at - rows + 1;
    }
    _top = _top.clamp(0, _shown.length - rows);
    return _PromptKeys(
      answer: widget.answer,
      atEmpty: () => _query.isEmpty,
      onKey: _key,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich([
            ..._asking(theme, widget.question, hint),
            if (_query.isNotEmpty) Span(_query),
          ], wrap: TextWrap.none),
          // all of the list laid out, the rows of the cursor in view
          SizedBox(
            height: rows,
            child: Stack(
              children: [
                Positioned(
                  top: -_top,
                  left: 0,
                  right: 0,
                  height: _shown.length,
                  child: SelectionList<int>(
                    controller: _selection,
                    autofocus: true,
                    itemCount: _shown.length,
                    keyOf: (i) => _shown[i],
                    itemBuilder: _item,
                    onSubmitted: _submit,
                  ),
                ),
              ],
            ),
          ),
          if (_shown.isEmpty) Text('  no match', style: theme.hint),
          if (_refused case final refused?) _refusal(theme, refused),
        ],
      ),
    );
  }
}
