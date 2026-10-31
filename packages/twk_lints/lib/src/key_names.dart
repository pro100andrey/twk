/// Key names as twk reads them: [parseKeys], a port of twk's
/// `KeyCombo.parseSequence`, and [withoutKitty], how a terminal without
/// the kitty keyboard protocol sends the key one names.
///
/// The plugin does not import twk (see the README), so the parser is
/// ported here, its messages too; `test/key_names_test.dart` holds both
/// to twk's own: the names, the messages of the names that are not ones,
/// and the keys an xterm sends, through twk_core's input parser.
library;

/// A key a name stands for: a key without a character ([code], its name
/// in lower case) or a character ([char]), with [modifiers] ([shift],
/// [alt], [ctrl] and [superKey] bits, as twk_core's `Mod`).
final class KeySpec {
  /// The key [code] (`enter`, `pageup`) with [modifiers].
  const KeySpec.key(String this.code, [this.modifiers = 0]) : char = '';

  /// The character [char], a letter in lower case, with [modifiers].
  const KeySpec.char(this.char, [this.modifiers = 0]) : code = null;

  /// The key's name in lower case; null for a character.
  final String? code;

  /// The character; empty for a key without one.
  final String char;

  /// The modifier bits.
  final int modifiers;

  /// Shift's bit.
  static const shift = 1;

  /// Alt's bit.
  static const alt = 2;

  /// Ctrl's bit.
  static const ctrl = 4;

  /// Super's bit.
  static const superKey = 8;

  @override
  bool operator ==(Object other) =>
      other is KeySpec &&
      other.code == code &&
      other.char == char &&
      other.modifiers == modifiers;

  @override
  int get hashCode => Object.hash(code, char, modifiers);

  /// The key as twk's `KeyCombo.toString` writes it: the modifiers in the
  /// order `ctrl`, `alt`, `shift`, `super`, Shift and a letter as the
  /// capital.
  @override
  String toString() {
    final upper = char.toUpperCase();
    final capital =
        modifiers & shift != 0 && upper != char && upper.toLowerCase() == char;
    final name = code ?? (char == ' ' ? 'space' : (capital ? upper : char));
    final shown = capital ? modifiers & ~shift : modifiers;
    return [
      for (final MapEntry(key: modifier, value: bit) in _modifiers.entries)
        if (shown & bit != 0) modifier,
      name,
    ].join('+');
  }
}

/// A name that is not one, with twk's message for it.
final class KeyNameException implements Exception {
  /// A name that is not one, as [message] says.
  const KeyNameException(this.message);

  /// What is wrong, as twk's `FormatException` says it.
  final String message;

  @override
  String toString() => message;
}

/// The stand-in for `leader` in a sequence that may name one.
const leaderKey = KeySpec.key('leader');

/// The keys [spec] names one after another, as twk's
/// `KeyCombo.parseSequence` reads them; with [leader], `leader` stands for
/// [leaderKey], as under a `LeaderKey`. A [KeyNameException] with twk's
/// message for a name that is not one.
List<KeySpec> parseKeys(String spec, {bool leader = false}) {
  final keys = <KeySpec>[];
  for (final key in spec.split(' ')) {
    if (key.isEmpty) {
      throw const KeyNameException('keys apart by one space each');
    }
    keys.add(_parse(spec, key, leader: leader));
  }
  return keys;
}

/// The one key [spec] names, as twk's `KeyCombo.parse` reads it.
KeySpec parseKey(String spec) {
  final keys = parseKeys(spec);
  if (keys.length != 1) {
    throw KeyNameException('"$spec" is ${keys.length} keys; one is meant');
  }
  return keys.single;
}

KeySpec _parse(String spec, String key, {required bool leader}) {
  Never fail(String message) => throw KeyNameException(message);

  if (key == 'leader') {
    return leader
        ? leaderKey
        : fail(
            '"leader" in "$spec" stands for a leader key, and none is given',
          );
  }
  if (key.endsWith('+leader')) {
    fail('"leader" in "$key" takes no modifiers: it is a key of its own');
  }
  final cut = key.length < 2 ? -1 : key.lastIndexOf('+', key.length - 2);
  final name = key.substring(cut + 1);
  var modifiers = 0;
  if (cut >= 0) {
    for (final m in key.substring(0, cut).split('+')) {
      final bit = _modifiers[m];
      if (bit == null) {
        fail(
          '"$m" in "$key" is not a modifier: ctrl, alt, shift or super'
          '${_hint(m, _modifiers.keys)}',
        );
      }
      if (modifiers & bit != 0) {
        fail('"$m" twice in "$key"');
      }
      modifiers |= bit;
    }
  }
  if (name == 'space') {
    if (modifiers == KeySpec.shift) {
      fail('"$key": Shift and space type a space: "space" names the key');
    }
    return KeySpec.char(' ', modifiers);
  }
  if (keyNames.contains(name)) {
    return KeySpec.key(name, modifiers);
  }
  // Escape by the name a key hint shows it by
  if (name == 'esc') {
    return KeySpec.key('escape', modifiers);
  }
  if (name.runes.length != 1) {
    if (_modifiers.containsKey(name)) {
      fail('"$name" in "$key" is a modifier: the key comes after it');
    }
    if (name.endsWith('+')) {
      fail('"$key" has no key after its last "+"');
    }
    fail(
      '"$name" in "$key" is neither one character nor a key: space, '
      '${keyNames.where((k) => !k.startsWith('f')).join(', ')}, f1 to '
      'f12${_hint(name, ['space', ...keyNames])}',
    );
  }
  final rune = name.runes.single;
  if (rune < 0x20 || rune == 0x7F) {
    fail('a control character in "$key" is not a key: name it');
  }
  if (modifiers == KeySpec.shift && name.toUpperCase() == name.toLowerCase()) {
    fail(
      '"$key": Shift and "$name" type another character, which names the '
      'key',
    );
  }
  final lower = name.toLowerCase();
  return lower != name && name.toUpperCase() == name
      ? KeySpec.char(lower, modifiers | KeySpec.shift)
      : KeySpec.char(name, modifiers);
}

/// The names of twk_core's `KeyCode`s but `char`, in lower case and in
/// its order.
const keyNames = [
  'enter',
  'tab',
  'backspace',
  'escape',
  'up',
  'down',
  'left',
  'right',
  'home',
  'end',
  'pageup',
  'pagedown',
  'insert',
  'delete',
  'f1',
  'f2',
  'f3',
  'f4',
  'f5',
  'f6',
  'f7',
  'f8',
  'f9',
  'f10',
  'f11',
  'f12',
];

const Map<String, int> _modifiers = {
  'ctrl': KeySpec.ctrl,
  'alt': KeySpec.alt,
  'shift': KeySpec.shift,
  'super': KeySpec.superKey,
};

// names of other programs, for the name meant
const _meant = {
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

String _hint(String word, Iterable<String> names) {
  final lower = word.toLowerCase();
  final meant = names.contains(lower) ? lower : _meant[lower];
  return meant != null && names.contains(meant) ? '; "$meant" is meant?' : '';
}

/// How a terminal without the kitty keyboard protocol sends a key.
sealed class Arrival {
  const Arrival();
}

/// As the key itself: a binding of it fires on every terminal.
final class AsItself extends Arrival {
  /// The key sent as itself.
  const AsItself();
}

/// As [key], another key: the bytes of a control character that is that
/// key too (`ctrl+i` is a Tab), when [sent]; else as twk's `KeyCombo`
/// documents of a key a terminal sends no bytes of its own for (Ctrl,
/// Shift and a letter as Ctrl and the letter).
final class AsOther extends Arrival {
  /// The key arrives as [key].
  const AsOther(this.key, {required this.sent});

  /// What it arrives as.
  final KeySpec key;

  /// Whether xterm's bytes for the key are [key]'s; false for what twk
  /// documents of a key it has no bytes of its own for.
  final bool sent;
}

/// Not at all (Super), or with no bytes of its own, so as nothing a
/// binding can name.
final class NotSent extends Arrival {
  /// The key does not arrive; [superKey] when it is for Super.
  const NotSent({required this.superKey});

  /// Whether it is Super that is not sent.
  final bool superKey;
}

/// How a terminal without the kitty keyboard protocol sends [key], as an
/// xterm does and twk_core's input parser reads it (see twk's `KeyCombo`).
Arrival withoutKitty(KeySpec key) {
  const shift = KeySpec.shift;
  const alt = KeySpec.alt;
  const ctrl = KeySpec.ctrl;
  final m = key.modifiers;
  if (key == leaderKey) {
    return const AsItself();
  }
  if (m & KeySpec.superKey != 0) {
    return const NotSent(superKey: true);
  }
  final a = m & alt;
  const none = NotSent(superKey: false);
  final code = key.code;
  if (code == null) {
    final c = key.char;
    if (m & shift != 0 && c.toUpperCase() == c) {
      // Shift and a character without case, with another modifier
      return none;
    }
    if (m & ctrl == 0) {
      // a capital, Alt as an ESC before it
      return const AsItself();
    }
    final letter =
        c.length == 1 && c.compareTo('a') >= 0 && c.compareTo('z') <= 0;
    if (m & shift != 0) {
      return letter ? AsOther(KeySpec.char(c, a | ctrl), sent: false) : none;
    }
    return switch (c) {
      ' ' || r'\' || ']' || '^' || '_' => const AsItself(),
      '@' => AsOther(KeySpec.char(' ', a | ctrl), sent: true),
      '[' => AsOther(KeySpec.key('escape', a), sent: true),
      '?' => AsOther(KeySpec.key('backspace', a), sent: true),
      'i' => AsOther(KeySpec.key('tab', a), sent: true),
      'm' || 'j' => AsOther(KeySpec.key('enter', a), sent: true),
      'h' => AsOther(KeySpec.key('backspace', a | ctrl), sent: true),
      '2' => AsOther(KeySpec.char(' ', a | ctrl), sent: false),
      _ when letter => const AsItself(),
      _ => none,
    };
  }
  if (m == 0 || m == alt) {
    return const AsItself();
  }
  return switch (code) {
    'tab' when m & ~alt == shift => const AsItself(),
    'backspace' when m & ~alt == ctrl => const AsItself(),
    'enter' || 'escape' => AsOther(KeySpec.key(code, a), sent: false),
    'tab' || 'backspace' => none,
    _ => const AsItself(),
  };
}
