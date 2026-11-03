// A one-line field's editing keys, as the list's filter and the palette's
// query take them.
import 'package:twk/twk.dart';

import 'keys.dart';

/// [text] after [e] in a one-line field: `backspace` takes the last
/// character away, `ctrl+u` all of them, a character typed (shift or no
/// modifier) goes at the end; null for any other key.
String? editLine(String text, KeyEvent e) {
  switch (keyName(e)) {
    case 'backspace':
      final runes = text.runes.toList();
      return runes.isEmpty ? text : String.fromCharCodes(runes..removeLast());
    case 'ctrl+u':
      return '';
  }
  if (e.code == KeyCode.char && (e.modifiers & ~Mod.shift) == 0) {
    return text + e.char;
  }
  return null;
}
