/// Keys and mouse reports as the bytes a terminal sends for them.
library;

import 'dart:convert';

import 'package:twk/twk.dart' show KeyCode, KeyCombo, Mod, MouseKind;

/// The bytes a terminal sends for each key of [spec], in turn: keys as
/// [KeyCombo.parseSequence] reads them, apart by spaces (`ctrl+s`,
/// `shift+tab`, `g g`, `ctrl+x ctrl+s`); a [FormatException] for a spec
/// that is not one.
///
/// With [kitty] the keys are encoded as by a terminal with the kitty
/// keyboard protocol on (its first level: Escape and the keys with Ctrl,
/// Alt or Super are `CSI … u`); without it as by xterm, where some keys
/// have no bytes of their own (Ctrl+Shift and a letter, Ctrl+Enter,
/// Super): an [ArgumentError] names them.
List<List<int>> keyBytes(String spec, {required bool kitty}) => [
  for (final combo in KeyCombo.parseSequence(spec))
    _keyBytes(combo, kitty: kitty) ??
        (throw ArgumentError.value(
          spec,
          'spec',
          '"$combo" has no bytes of its own without the kitty keyboard '
              'protocol',
        )),
];

/// The final byte of the CSI a key without a character is sent with, and
/// the number before it: `CSI A`, `CSI 1 ; m A` with modifiers; `CSI 5 ~`,
/// `CSI 5 ; m ~` with them. F1 to F4 without modifiers are `SS3 P` to
/// `SS3 S`.
const Map<KeyCode, (String, int)> _csi = {
  KeyCode.up: ('A', 1),
  KeyCode.down: ('B', 1),
  KeyCode.right: ('C', 1),
  KeyCode.left: ('D', 1),
  KeyCode.home: ('H', 1),
  KeyCode.end: ('F', 1),
  KeyCode.f1: ('P', 1),
  KeyCode.f2: ('Q', 1),
  KeyCode.f3: ('R', 1),
  KeyCode.f4: ('S', 1),
  KeyCode.insert: ('~', 2),
  KeyCode.delete: ('~', 3),
  KeyCode.pageUp: ('~', 5),
  KeyCode.pageDown: ('~', 6),
  KeyCode.f5: ('~', 15),
  KeyCode.f6: ('~', 17),
  KeyCode.f7: ('~', 18),
  KeyCode.f8: ('~', 19),
  KeyCode.f9: ('~', 20),
  KeyCode.f10: ('~', 21),
  KeyCode.f11: ('~', 23),
  KeyCode.f12: ('~', 24),
};

/// The codes of the kitty protocol for the keys sent as `CSI code u`.
const Map<KeyCode, int> _kittyCodes = {
  KeyCode.enter: 13,
  KeyCode.tab: 9,
  KeyCode.backspace: 127,
  KeyCode.escape: 27,
};

const _esc = 0x1B;

/// The bytes of [combo]; null where xterm sends nothing of its own.
List<int>? _keyBytes(KeyCombo combo, {required bool kitty}) =>
    combo.code == KeyCode.char
    ? _charBytes(combo.char, combo.modifiers, kitty: kitty)
    : _keyCodeBytes(combo.code, combo.modifiers, kitty: kitty);

/// [char] typed with [mods]; null where xterm sends nothing of its own.
List<int>? _charBytes(String char, int mods, {required bool kitty}) {
  // Shift and a letter types the capital
  final capital = mods & Mod.shift != 0 && char.toUpperCase() != char;
  final c = capital ? char.toUpperCase() : char;
  if (mods & ~Mod.shift == 0) {
    return utf8.encode(c);
  }
  if (kitty) {
    return _csiBytes('${char.runes.single};${mods + 1}', 'u');
  }
  // Shift and a character without case types what the layout says
  if (mods & Mod.superKey != 0 || mods & Mod.shift != 0 && !capital) {
    return null;
  }
  final alt = mods & Mod.alt != 0 ? const [_esc] : const <int>[];
  if (mods & Mod.ctrl == 0) {
    return [...alt, ...utf8.encode(c)];
  }
  if (capital) {
    return null; // Ctrl+Shift+a letter
  }
  final control = switch (c) {
    ' ' || '@' => 0x00,
    '[' => 0x1B,
    r'\' => 0x1C,
    ']' => 0x1D,
    '^' => 0x1E,
    '_' => 0x1F,
    '?' => 0x7F,
    _ when c.length == 1 && c.compareTo('a') >= 0 && c.compareTo('z') <= 0 =>
      c.codeUnitAt(0) - 0x60,
    _ => null,
  };
  return control == null ? null : [...alt, control];
}

/// The key [code] with [mods]; null where xterm sends nothing of its own.
List<int>? _keyCodeBytes(KeyCode code, int mods, {required bool kitty}) {
  final csi = _csi[code];
  if (csi != null) {
    final (fin, n) = csi;
    if (mods == 0) {
      return n == 1 && 'PQRS'.contains(fin)
          ? [_esc, 0x4F, fin.codeUnitAt(0)]
          : _csiBytes(n == 1 ? '' : '$n', fin);
    }
    if (!kitty && mods & Mod.superKey != 0) {
      return null;
    }
    return _csiBytes('$n;${mods + 1}', fin);
  }
  if (kitty && (code == KeyCode.escape || mods != 0)) {
    final params = mods == 0 ? '27' : '${_kittyCodes[code]};${mods + 1}';
    return _csiBytes(params, 'u');
  }
  final plain = switch (code) {
    KeyCode.enter => 0x0D,
    KeyCode.tab => 0x09,
    KeyCode.backspace => 0x7F,
    _ => _esc,
  };
  return switch (mods) {
    0 => [plain],
    Mod.alt => [_esc, plain],
    Mod.shift when code == KeyCode.tab => _csiBytes('', 'Z'),
    const (Mod.alt | Mod.shift) when code == KeyCode.tab => [
      _esc,
      ..._csiBytes('', 'Z'),
    ],
    Mod.ctrl when code == KeyCode.backspace => const [0x08],
    const (Mod.alt | Mod.ctrl) when code == KeyCode.backspace => const [
      _esc,
      0x08,
    ],
    _ => null,
  };
}

List<int> _csiBytes(String params, String fin) => [
  _esc,
  0x5B,
  ...ascii.encode(params),
  fin.codeUnitAt(0),
];

/// The SGR report (mode 1006) of the mouse event: [kind] at the cell
/// ([x], [y]), 0-based, with [button] (0 left, 1 middle, 2 right, 8 to 11
/// the side buttons) for a press, release or drag, and [mods] ([Mod]'s
/// Shift, Alt and Ctrl).
List<int> mouseBytes(MouseKind kind, int x, int y, int button, int mods) {
  int buttonBits() => switch (button) {
    0 || 1 || 2 => button,
    >= 8 && <= 11 => 128 | (button - 8),
    _ => throw ArgumentError.value(button, 'button', 'not 0, 1, 2 or 8 to 11'),
  };
  if (mods & ~(Mod.shift | Mod.alt | Mod.ctrl) != 0) {
    throw ArgumentError.value(mods, 'modifiers', 'only Shift, Alt and Ctrl');
  }
  var cb =
      (mods & Mod.shift != 0 ? 4 : 0) |
      (mods & Mod.alt != 0 ? 8 : 0) |
      (mods & Mod.ctrl != 0 ? 16 : 0);
  cb |= switch (kind) {
    MouseKind.down || MouseKind.up => buttonBits(),
    MouseKind.move => 32 | 3,
    MouseKind.drag => 32 | buttonBits(),
    MouseKind.wheelUp => 64,
    MouseKind.wheelDown => 64 | 1,
    MouseKind.wheelLeft => 64 | 2,
    MouseKind.wheelRight => 64 | 3,
  };
  final fin = kind == MouseKind.up ? 'm' : 'M';
  return ascii.encode('\x1b[<$cb;${x + 1};${y + 1}$fin');
}
