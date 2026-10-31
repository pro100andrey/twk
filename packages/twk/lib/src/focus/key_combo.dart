/// Keys as key bindings name them: a [KeyCombo], parsed from a string such
/// as `ctrl+s`, `shift+tab` or `A`.
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart' show KeyCode, KeyEvent, KeyKind, Mod;

/// A key and the modifiers held with it, as a key binding names it; it
/// [accepts] the [KeyEvent]s a terminal sends for that key.
///
/// A binding names it with a string, which [KeyCombo.parse] reads:
///
/// * The modifiers and then the key, joined by `+`: `ctrl+s`, `alt+enter`,
///   `ctrl+alt+x`, `shift+tab`. The modifiers are `ctrl`, `alt`, `shift`
///   and `super` ([Mod]), in any order, each once.
/// * The key is one character, which stands for itself (`a`, `?`, `я`,
///   `+`), `space`, or a [KeyCode]'s name in lower case: `enter`, `tab`,
///   `backspace`, `escape`, `up`, `down`, `left`, `right`, `home`, `end`,
///   `pageup`, `pagedown`, `insert`, `delete`, `f1` to `f12`. Escape is
///   `esc` too, the name a key hint shows it by: the same key, which
///   [toString] writes `escape`.
/// * Only the character has a case: `A` is Shift and `a`, the same combo
///   as `shift+a`, and `ctrl+A` is `ctrl+shift+a`. Shift alone with a
///   character that has no case names no key: it types another character
///   (`!` for `shift+1` on most layouts), and that one names the key.
/// * `+` as the key comes last: `+`, `ctrl++`.
/// * Keys pressed one after another are apart by one space: `ctrl+x
///   ctrl+s`, `g g` ([parseSequence]). In a sequence, `leader` stands for
///   a leader key given to it: `leader f` (`LeaderKey`).
///
/// A string that is not one is a [FormatException] naming the part that is
/// wrong, and the name meant where that is plain (`Enter`, `ret`, `cmd`).
/// [toString] writes a combo as it is parsed: the modifiers in the order
/// `ctrl`, `alt`, `shift`, `super`, Shift and a letter as the capital.
///
/// Without the kitty keyboard protocol (`TerminalInfo.kittyKeyboard`) a
/// terminal sends Ctrl and a letter as a control character, and some of
/// those are other keys: `ctrl+i` arrives as `tab`, `ctrl+m` and `ctrl+j`
/// as `enter`, `ctrl+[` as `escape`, `ctrl+h` as a `backspace`, `ctrl+2`
/// as `ctrl+space`; Ctrl, Shift and a letter as Ctrl and the letter; Ctrl
/// or Shift with `enter` or `escape` as the key alone; Super not at all.
/// A binding of `ctrl+i` fires there only on the protocol's terminals;
/// `tab` fires on all.
///
/// A key read from a name, and asked whether an event is it:
///
/// ```dart
/// final save = KeyCombo.parse('ctrl+s');
/// bool isSave(KeyEvent event) => save.accepts(event);
/// ```
@immutable
final class KeyCombo {
  /// [code], a key without a character, with [modifiers] ([Mod] bits); see
  /// [KeyCombo.char] for the others.
  const KeyCombo(this.code, {this.modifiers = 0})
    : char = '',
      assert(code != KeyCode.char, 'KeyCombo.char names a character'),
      assert(modifiers >= 0 && modifiers < 16, 'not Mod bits: $modifiers');

  /// [char], one character, typed with [modifiers] ([Mod] bits); a capital
  /// letter is the small one with Shift.
  factory KeyCombo.char(String char, {int modifiers = 0}) {
    assert(char.runes.length == 1, 'not one character: "$char"');
    assert(modifiers >= 0 && modifiers < 16, 'not Mod bits: $modifiers');
    return KeyCombo._ofChar(char, modifiers);
  }

  /// The combo [spec] names; a [FormatException] if it names none, or more
  /// than one key.
  factory KeyCombo.parse(String spec) {
    final keys = parseSequence(spec);
    if (keys.length != 1) {
      throw FormatException(
        '"$spec" is ${keys.length} keys; one is meant',
        spec,
      );
    }
    return keys.single;
  }

  /// The combo of the key [event] is for, which [accepts] it.
  factory KeyCombo.fromEvent(KeyEvent event) => event.code == KeyCode.char
      ? KeyCombo._ofChar(event.char, event.modifiers)
      : KeyCombo._(event.code, '', event.modifiers);

  const KeyCombo._(this.code, this.char, this.modifiers);

  // [char] with [modifiers], a capital letter as the small one with Shift
  factory KeyCombo._ofChar(String char, int modifiers) {
    final lower = char.toLowerCase();
    return lower != char && char.toUpperCase() == char
        ? KeyCombo._(KeyCode.char, lower, modifiers | Mod.shift)
        : KeyCombo._(KeyCode.char, char, modifiers);
  }

  /// [key], at [at] in [spec]; `leader` is [leader].
  factory KeyCombo._parse(
    String spec,
    String key,
    int at,
    KeyCombo? leader,
  ) {
    Never fail(String message, [int offset = 0]) =>
        throw FormatException(message, spec, at + offset);

    if (key == 'leader') {
      return leader ??
          fail(
            '"leader" in "$spec" stands for a leader key, and none is given',
          );
    }
    if (key.endsWith('+leader')) {
      fail(
        '"leader" in "$key" takes no modifiers: it is a key of its own',
        key.length - 6,
      );
    }
    // the key is what follows the last '+' but one at the end: 'ctrl++'
    // is Ctrl and '+'
    final cut = key.length < 2 ? -1 : key.lastIndexOf('+', key.length - 2);
    final name = key.substring(cut + 1);
    var modifiers = 0;
    if (cut >= 0) {
      var offset = 0;
      for (final m in key.substring(0, cut).split('+')) {
        final bit = _modifiers[m];
        if (bit == null) {
          fail(
            '"$m" in "$key" is not a modifier: ctrl, alt, shift or super'
            '${_hint(m, _modifiers.keys)}',
            offset,
          );
        }
        if (modifiers & bit != 0) {
          fail('"$m" twice in "$key"', offset);
        }
        modifiers |= bit;
        offset += m.length + 1;
      }
    }
    final offset = cut + 1;
    if (name == 'space') {
      if (modifiers == Mod.shift) {
        fail('"$key": Shift and space type a space: "space" names the key');
      }
      return KeyCombo._(KeyCode.char, ' ', modifiers);
    }
    final code = _keys[name] ?? (name == 'esc' ? KeyCode.escape : null);
    if (code != null) {
      return KeyCombo._(code, '', modifiers);
    }
    if (name.runes.length != 1) {
      if (_modifiers.containsKey(name)) {
        fail('"$name" in "$key" is a modifier: the key comes after it', offset);
      }
      if (name.endsWith('+')) {
        fail('"$key" has no key after its last "+"', key.length - 1);
      }
      fail(
        '"$name" in "$key" is neither one character nor a key: space, '
        '${_keys.keys.where((k) => !k.startsWith('f')).join(', ')}, f1 to '
        'f12${_hint(name, ['space', ..._keys.keys])}',
        offset,
      );
    }
    final rune = name.runes.single;
    if (rune < 0x20 || rune == 0x7F) {
      fail('a control character in "$key" is not a key: name it', offset);
    }
    if (modifiers == Mod.shift && name.toUpperCase() == name.toLowerCase()) {
      fail(
        '"$key": Shift and "$name" type another character, which names the '
        'key',
      );
    }
    return KeyCombo._ofChar(name, modifiers);
  }

  /// The combos of the keys [spec] names one after another, apart by
  /// spaces (`ctrl+x ctrl+s`), `leader` standing for [leader]; a
  /// [FormatException] if it is not one.
  static List<KeyCombo> parseSequence(String spec, {KeyCombo? leader}) {
    final keys = <KeyCombo>[];
    var at = 0;
    for (final key in spec.split(' ')) {
      if (key.isEmpty) {
        throw FormatException('keys apart by one space each', spec, at);
      }
      keys.add(KeyCombo._parse(spec, key, at, leader));
      at += key.length + 1;
    }
    return keys;
  }

  /// The key; [KeyCode.char] for a character.
  final KeyCode code;

  /// The character for [KeyCode.char], a letter in lower case; empty for
  /// the other keys.
  final String char;

  /// The [Mod] bits of the modifiers held with the key; Shift for a
  /// capital letter.
  final int modifiers;

  /// Whether [event] is a press of this key, or its repeat.
  bool accepts(KeyEvent event) =>
      event.kind != KeyKind.release && KeyCombo.fromEvent(event) == this;

  @override
  bool operator ==(Object other) =>
      other is KeyCombo &&
      other.code == code &&
      other.char == char &&
      other.modifiers == modifiers;

  @override
  int get hashCode => Object.hash(code, char, modifiers);

  /// The combo as [KeyCombo.parse] reads it: `ctrl+A`, `alt+shift+end`,
  /// `space`.
  @override
  String toString() {
    final upper = char.toUpperCase();
    final capital =
        modifiers & Mod.shift != 0 &&
        upper != char &&
        upper.toLowerCase() == char;
    final name = switch (code) {
      KeyCode.char when char == ' ' => 'space',
      KeyCode.char => capital ? upper : char,
      _ => code.name.toLowerCase(),
    };
    final shown = capital ? modifiers & ~Mod.shift : modifiers;
    return [
      for (final MapEntry(key: modifier, value: bit) in _modifiers.entries)
        if (shown & bit != 0) modifier,
      name,
    ].join('+');
  }

  static const Map<String, int> _modifiers = {
    'ctrl': Mod.ctrl,
    'alt': Mod.alt,
    'shift': Mod.shift,
    'super': Mod.superKey,
  };

  static final _keys = <String, KeyCode>{
    for (final code in KeyCode.values)
      if (code != KeyCode.char) code.name.toLowerCase(): code,
  };

  // names of other programs, for the name meant
  static const _meant = <String, String>{
    'control': 'ctrl',
    'cmd': 'super',
    'command': 'super',
    'win': 'super',
    'option': 'alt',
    'opt': 'alt',
    'esc': 'escape',
    'return': 'enter',
    'ret': 'enter',
    'del': 'delete',
    'ins': 'insert',
    'pgup': 'pageup',
    'pgdn': 'pagedown',
    'pgdown': 'pagedown',
    'bs': 'backspace',
    'spacebar': 'space',
  };

  /// `; "<name>" is meant?` when [word] stands for one of [names].
  static String _hint(String word, Iterable<String> names) {
    final lower = word.toLowerCase();
    final meant = names.contains(lower) ? lower : _meant[lower];
    return meant != null && names.contains(meant) ? '; "$meant" is meant?' : '';
  }
}
