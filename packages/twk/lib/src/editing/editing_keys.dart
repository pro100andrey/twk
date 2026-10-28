/// The keys that edit text, which the editing widgets share
/// ([editingKey]), where they move the caret to ([CaretStops]), what they
/// copy to the clipboard with ([copyToClipboard]), and when they call
/// `onEditingComplete` as the focus leaves them ([EditingCompletion]).
library;

import 'dart:convert' show ascii;

import 'package:twk_core/twk_core.dart'
    show KeyCode, KeyEvent, KeyKind, Mod, clipboardSequence;

import '../binding/app_binding.dart';
import '../focus/focus_tree.dart';
import '../foundation/change_notifier.dart';
import '../framework/framework.dart';
import 'text_buffer.dart';
import 'text_editing.dart';

/// Where the editing keys move the caret to in a text: characters and
/// words as [TextBoundaries] finds them in all of it, and its ends as the
/// ends of the caret's line. Left and Right go back and on in it, as it is
/// stored; a widget that draws it in visual order moves them as it is
/// drawn.
class CaretStops {
  /// The stops of a text as it is stored.
  const CaretStops();

  /// Where Left moves the caret from [offset]: the character before it.
  int left(TextBuffer text, int offset) => characterBefore(text, offset);

  /// Where Right moves it: the end of the character after it.
  int right(TextBuffer text, int offset) => characterAfter(text, offset);

  /// Where Ctrl+Left and Alt+Left move it: the start of the word before.
  int wordLeft(TextBuffer text, int offset) => wordBefore(text, offset);

  /// Where Ctrl+Right and Alt+Right move it: the end of the word after.
  int wordRight(TextBuffer text, int offset) => wordAfter(text, offset);

  /// Where Left puts the caret that ends [selection]: at its start.
  int selectionLeft(TextBuffer text, TextSelection selection) =>
      selection.start;

  /// Where Right puts it: at its end.
  int selectionRight(TextBuffer text, TextSelection selection) => selection.end;

  /// The start of the character before [offset].
  int characterBefore(TextBuffer text, int offset) =>
      text.characterStartBefore(offset);

  /// The end of the character at [offset].
  int characterAfter(TextBuffer text, int offset) =>
      text.characterEndAfter(offset);

  /// The start of the word before [offset].
  int wordBefore(TextBuffer text, int offset, {bool blankDelimited = false}) =>
      text.wordStartBefore(offset, blankDelimited: blankDelimited);

  /// The end of the word after [offset].
  int wordAfter(TextBuffer text, int offset) => text.wordEndAfter(offset);

  /// The start of the line [offset] is on.
  int lineStart(TextBuffer text, int offset) => 0;

  /// The end of the line [offset] is on.
  int lineEnd(TextBuffer text, int offset) => text.length;
}

/// Does what [event] does to [controller] as an editing key, and returns
/// whether it is one; a release is none. Text typed goes to [type]; the
/// caret moves to [stops].
///
/// * A character, alone or with Shift, is typed.
/// * Left and Right move the caret a character, to the start or the end
///   of the selection when there is one; with Ctrl or Alt a word, as Alt+B
///   and Alt+F do. Home and Ctrl+A move it to the start of the line, End
///   and Ctrl+E to its end. With Shift each of them selects. Where [stops]
///   says so, Left and Right go as the text is drawn ([CaretStops.left]).
///   Alt+B and Alt+F, Home and End, and the keys that delete always go as
///   the text is stored.
/// * Backspace deletes the character before the caret, Delete and Ctrl+D
///   the one after it; with Ctrl or Alt the word, as Alt+D does after it.
///   Ctrl+W deletes back to a blank, Ctrl+U to the start of the line,
///   Ctrl+K to its end; at the start or the end, the character before or
///   after it. Each deletes the selection instead when there is one.
///   Ctrl+D with nothing after the caret and nothing selected is no
///   editing key.
/// * Ctrl+Z undoes the last change, Ctrl+Y (and Ctrl+Shift+Z) makes it
///   again; with nothing to undo or redo they are no editing keys.
/// * Ctrl+C gives what is selected to [copy], Ctrl+X too and deletes it;
///   with nothing selected, or without [copy], they are no editing keys:
///   Ctrl+C goes on to quit the app, an app's Ctrl+X to what it binds.
///
/// Words are [TextBoundaries]'; a character is a grapheme cluster. With
/// [readOnly] the keys that would change the text (a character typed, the
/// keys that delete, Ctrl+X, undo and redo) are no editing keys: those
/// that move the caret, select and copy are.
bool editingKey(
  TextEditingController controller,
  KeyEvent event,
  void Function(String text) type, {
  CaretStops stops = const CaretStops(),
  bool readOnly = false,
  void Function(String text)? copy,
}) {
  if (event.kind == KeyKind.release) {
    return false;
  }
  final c = controller;
  final s = c.selection;
  final mods = event.modifiers;
  if (event case KeyEvent(code: KeyCode.char, char: 'c' || 'x')
      when mods == Mod.ctrl) {
    if (copy == null || s.isCollapsed || (readOnly && event.char == 'x')) {
      return false;
    }
    copy(textBufferOf(c.value).substring(s.start, s.end));
    if (event.char == 'x') {
      c.deleteTo(s.extentOffset);
    }
    return true;
  }
  if (readOnly) {
    return _movingKey(event) &&
        editingKey(controller, event, type, stops: stops);
  }
  final text = textBufferOf(c.value);
  final caret = s.extentOffset;
  final shift = mods & Mod.shift != 0;
  final rest = mods & ~Mod.shift;
  final word = rest == Mod.ctrl || rest == Mod.alt;
  switch (event.code) {
    case KeyCode.char when rest == 0 && event.char.isNotEmpty:
      type(event.char);
    case KeyCode.left when rest == 0:
      c.moveCaret(
        !shift && !s.isCollapsed
            ? stops.selectionLeft(text, s)
            : stops.left(text, caret),
        extend: shift,
      );
    case KeyCode.right when rest == 0:
      c.moveCaret(
        !shift && !s.isCollapsed
            ? stops.selectionRight(text, s)
            : stops.right(text, caret),
        extend: shift,
      );
    case KeyCode.left when word:
      c.moveCaret(stops.wordLeft(text, caret), extend: shift);
    case KeyCode.right when word:
      c.moveCaret(stops.wordRight(text, caret), extend: shift);
    case KeyCode.char when mods == Mod.alt && event.char == 'b':
      c.moveCaret(stops.wordBefore(text, caret));
    case KeyCode.char when mods == Mod.alt && event.char == 'f':
      c.moveCaret(stops.wordAfter(text, caret));
    case KeyCode.home when rest == 0:
      c.moveCaret(stops.lineStart(text, caret), extend: shift);
    case KeyCode.end when rest == 0:
      c.moveCaret(stops.lineEnd(text, caret), extend: shift);
    case KeyCode.char when rest == Mod.ctrl && event.char == 'a':
      c.moveCaret(stops.lineStart(text, caret), extend: shift);
    case KeyCode.char when rest == Mod.ctrl && event.char == 'e':
      c.moveCaret(stops.lineEnd(text, caret), extend: shift);
    case KeyCode.backspace when rest == 0:
      c.deleteTo(stops.characterBefore(text, caret));
    case KeyCode.backspace when word:
      c.deleteTo(stops.wordBefore(text, caret));
    case KeyCode.delete when rest == 0:
      c.deleteTo(stops.characterAfter(text, caret));
    case KeyCode.delete when word:
      c.deleteTo(stops.wordAfter(text, caret));
    case KeyCode.char when mods == Mod.alt && event.char == 'd':
      c.deleteTo(stops.wordAfter(text, caret));
    case KeyCode.char when mods == Mod.ctrl && event.char == 'd':
      if (s.isCollapsed && caret == text.length) {
        return false;
      }
      c.deleteTo(stops.characterAfter(text, caret));
    case KeyCode.char when mods == Mod.ctrl && event.char == 'w':
      c.deleteTo(stops.wordBefore(text, caret, blankDelimited: true));
    case KeyCode.char when mods == Mod.ctrl && event.char == 'u':
      final start = stops.lineStart(text, caret);
      c.deleteTo(
        start == caret ? stops.characterBefore(text, caret) : start,
      );
    case KeyCode.char when mods == Mod.ctrl && event.char == 'k':
      final end = stops.lineEnd(text, caret);
      c.deleteTo(end == caret ? stops.characterAfter(text, caret) : end);
    case KeyCode.char when mods == Mod.ctrl && event.char == 'z':
      if (!c.canUndo) {
        return false;
      }
      c.undo();
    case KeyCode.char
        when (mods == Mod.ctrl && event.char == 'y') ||
            (mods == Mod.ctrl | Mod.shift && event.char.toLowerCase() == 'z'):
      if (!c.canRedo) {
        return false;
      }
      c.redo();
    case _:
      return false;
  }
  return true;
}

/// Whether [event] is one of the editing keys that move the caret or
/// select, not one that changes the text.
bool _movingKey(KeyEvent event) {
  final mods = event.modifiers;
  final rest = mods & ~Mod.shift;
  return switch (event.code) {
    KeyCode.left || KeyCode.right || KeyCode.home || KeyCode.end => true,
    KeyCode.char => switch (event.char) {
      'b' || 'f' => mods == Mod.alt,
      'a' || 'e' => rest == Mod.ctrl,
      _ => false,
    },
    _ => false,
  };
}

/// Copies [text] to the system clipboard of the terminal the app runs in,
/// as a `SelectionArea` copies: OSC 52 (`clipboardSequence`), wrapped for
/// tmux or GNU screen when the app runs inside one. Nothing without an app
/// around [context].
void copyToClipboard(BuildContext context, String text) {
  final terminal = AppBinding.maybeOf(context)?.twkApp.terminal;
  if (text.isEmpty || terminal == null) {
    return;
  }
  terminal.write(
    ascii.encode(
      clipboardSequence(text, multiplexer: terminal.info.multiplexer),
    ),
  );
}

/// When an editing widget calls its `onEditingComplete` as the focus
/// leaves it: after a change the user made ([changed]) since it was
/// called last ([done]).
final class EditingCompletion {
  FocusNode? _node;
  late VoidCallback _complete;
  var _changed = false;

  /// Follows [node], to call [complete] as the focus leaves it after a
  /// change.
  void follow(FocusNode node, VoidCallback complete) {
    _complete = complete;
    if (identical(node, _node)) {
      return;
    }
    _node?.removeListener(_focusChanged);
    _node = node..addListener(_focusChanged);
  }

  /// The user changed the text.
  void changed() => _changed = true;

  /// The widget called `onEditingComplete` itself (Enter).
  void done() => _changed = false;

  // a change is made while the node has the focus: it left after one
  void _focusChanged() {
    if (_changed && !_node!.hasFocus) {
      _changed = false;
      _complete();
    }
  }

  /// Stops following the node.
  void dispose() {
    _node?.removeListener(_focusChanged);
    _node = null;
  }
}
