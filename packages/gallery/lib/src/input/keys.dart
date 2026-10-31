// The gallery's names of keys, as a route's `keys=` and the shell's own
// bindings write them, and back: `tab`, `shift+tab`, `ctrl+p`, `space`,
// `pageup`, `T`.
import 'package:twk/twk.dart';

/// [e] as the gallery names keys: `tab`, `shift+tab`, `ctrl+p`, `t`, `T`,
/// `space`, `pageup`.
String keyName(KeyEvent e) {
  final m = e.modifiers;
  final String base;
  if (e.code == KeyCode.char) {
    base = e.char == ' ' ? 'space' : e.char;
  } else {
    base = switch (e.code) {
      KeyCode.pageUp => 'pageup',
      KeyCode.pageDown => 'pagedown',
      final c => c.name,
    };
  }
  final shift = (m & Mod.shift) != 0 && e.code != KeyCode.char;
  return [
    if ((m & Mod.ctrl) != 0) 'ctrl',
    if ((m & Mod.alt) != 0) 'alt',
    if (shift) 'shift',
    base,
  ].join('+');
}

/// The key event [name] stands for, as [keyName] names it (and `esc`);
/// null for a name that is none.
KeyEvent? keyEvent(String name) {
  var mods = 0;
  var rest = name;
  for (;;) {
    final plus = rest.indexOf('+');
    if (plus <= 0 || plus == rest.length - 1) {
      break;
    }
    final m = switch (rest.substring(0, plus)) {
      'ctrl' => Mod.ctrl,
      'alt' => Mod.alt,
      'shift' => Mod.shift,
      _ => 0,
    };
    if (m == 0) {
      break;
    }
    mods |= m;
    rest = rest.substring(plus + 1);
  }
  if (rest.runes.length == 1) {
    return KeyEvent(KeyCode.char, char: rest, modifiers: mods);
  }
  if (rest == 'space') {
    return KeyEvent(KeyCode.char, char: ' ', modifiers: mods);
  }
  final code = switch (rest) {
    'esc' => KeyCode.escape,
    'pageup' => KeyCode.pageUp,
    'pagedown' => KeyCode.pageDown,
    _ => KeyCode.values.where((c) => c.name == rest).firstOrNull,
  };
  return code == null ? null : KeyEvent(code, modifiers: mods);
}
