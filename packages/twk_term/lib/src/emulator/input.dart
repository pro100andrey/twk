/// What keys, the mouse, focus and pasted text send to the program, as
/// xterm sends them.
library;

import 'dart:convert';

import 'package:twk_core/twk_core.dart'
    show KeyCode, KeyEvent, KeyKind, Mod, MouseEvent, MouseKind;

import 'modes.dart';

/// The bytes [key] sends: with [cursorKeys] (DECCKM) the arrows, Home and
/// End unmodified as `SS3 x`, with [newLine] (LNM) Enter as CR LF. Alt
/// puts ESC before a key's bytes, Ctrl makes a control character of a
/// letter and of `@[\]^_ ?` and the digits 2 to 8, Shift with a letter
/// types its capital, other modifiers of a special key go into its
/// sequence (`CSI 1 ; m A`). Null for a release.
String? keySequence(
  KeyEvent key, {
  bool cursorKeys = false,
  bool newLine = false,
}) {
  if (key.kind == KeyKind.release) {
    return null;
  }
  final mods = key.modifiers;
  final m = 1 + (mods & (Mod.shift | Mod.alt | Mod.ctrl | Mod.superKey));
  final alt = key.alt ? '\x1b' : '';
  String cursor(String finalChar) => m == 1
      ? (cursorKeys ? '\x1bO$finalChar' : '\x1b[$finalChar')
      : '\x1b[1;$m$finalChar';
  String tilde(int n) => m == 1 ? '\x1b[$n~' : '\x1b[$n;$m~';
  String ss3(String finalChar) =>
      m == 1 ? '\x1bO$finalChar' : '\x1b[1;$m$finalChar';
  return switch (key.code) {
    KeyCode.char => '$alt${key.ctrl ? _ctrl(key.char) : _shifted(key)}',
    KeyCode.enter => '$alt${newLine ? '\r\n' : '\r'}',
    KeyCode.tab => key.shift ? '\x1b[Z' : '$alt\t',
    KeyCode.backspace => '$alt${key.ctrl ? '\x08' : '\x7f'}',
    KeyCode.escape => '$alt\x1b',
    KeyCode.up => cursor('A'),
    KeyCode.down => cursor('B'),
    KeyCode.right => cursor('C'),
    KeyCode.left => cursor('D'),
    KeyCode.home => cursor('H'),
    KeyCode.end => cursor('F'),
    KeyCode.insert => tilde(2),
    KeyCode.delete => tilde(3),
    KeyCode.pageUp => tilde(5),
    KeyCode.pageDown => tilde(6),
    KeyCode.f1 => ss3('P'),
    KeyCode.f2 => ss3('Q'),
    KeyCode.f3 => ss3('R'),
    KeyCode.f4 => ss3('S'),
    KeyCode.f5 => tilde(15),
    KeyCode.f6 => tilde(17),
    KeyCode.f7 => tilde(18),
    KeyCode.f8 => tilde(19),
    KeyCode.f9 => tilde(20),
    KeyCode.f10 => tilde(21),
    KeyCode.f11 => tilde(23),
    KeyCode.f12 => tilde(24),
  };
}

/// The text [key], a character, types: its capital with Shift (as a
/// terminal with the kitty protocol reports Shift and a letter).
String _shifted(KeyEvent key) {
  final char = key.char;
  if (!key.shift) {
    return char;
  }
  final upper = char.toUpperCase();
  return upper.runes.length == 1 ? upper : char;
}

/// The bytes [key] sends under the kitty keyboard protocol's [flags] (as
/// `CSI = flags u` sets them): 1 disambiguate escape codes, 2 report
/// event types, 4 report alternate keys, 8 report all keys as escape
/// codes, 16 report associated text. As kitty sends them:
///
/// * a character typed with no modifier but Shift is its text, unless 8;
///   with other modifiers, or with 8, it is `CSI code ; m u`, its code the
///   unshifted character's (a capital is its letter with Shift), with 4
///   the capital after a colon, with 8 and 16 the text after another `;`;
/// * Enter, Tab and Backspace without modifiers are CR, HT and DEL unless
///   8, Escape is ESC with neither 1 nor 8; with modifiers they are
///   `CSI 13 u`, `CSI 9 u`, `CSI 127 u` and `CSI 27 u` (Shift+Tab too);
/// * the arrows, Home, End, F1, F2 and F4 are `CSI 1 ; m X` (`CSI X`
///   without modifiers), the others `CSI n ; m ~`, F3 `CSI 13 ~`; never in
///   DECCKM's `SS3` form;
/// * with 2 a repeat has `:2` after the modifiers, a release `:3`, and a
///   release is sent at all (of Enter, Tab and Backspace only with 8);
///   without 2 a release sends nothing (null).
String? kittyKeySequence(KeyEvent key, int flags) {
  final disambiguate = flags & 1 != 0;
  final events = flags & 2 != 0;
  final alternates = flags & 4 != 0;
  final allKeys = flags & 8 != 0;
  final release = key.kind == KeyKind.release;
  if (release && !events) {
    return null;
  }
  var mods = key.modifiers & (Mod.shift | Mod.alt | Mod.ctrl | Mod.superKey);
  final action = switch (key.kind) {
    KeyKind.press => 1,
    KeyKind.repeat => 2,
    KeyKind.release => 3,
  };
  String csi(int number, String trailer, {int shifted = 0, String text = ''}) {
    final sb = StringBuffer('\x1b[');
    final second = mods != 0 || (events && action != 1);
    if (number != 1 || shifted != 0 || second || text.isNotEmpty) {
      sb.write(number);
    }
    if (shifted != 0) {
      sb.write(':$shifted');
    }
    if (second || text.isNotEmpty) {
      sb.write(';');
      if (second) {
        sb.write(mods + 1);
        if (events && action != 1) {
          sb.write(':$action');
        }
      }
    }
    if (text.isNotEmpty) {
      sb
        ..write(';')
        ..write(text.runes.join(':'));
    }
    sb.write(trailer);
    return sb.toString();
  }

  switch (key.code) {
    case KeyCode.char:
      final char = key.char;
      if (char.isEmpty) {
        return null;
      }
      var code = char.runes.first;
      var shifted = 0;
      final lower = char.toLowerCase();
      if (lower != char && lower.runes.length == 1) {
        // a capital: its letter with Shift
        mods |= Mod.shift;
        shifted = code;
        code = lower.runes.first;
      } else if (mods & Mod.shift != 0) {
        final upper = char.toUpperCase();
        if (upper != char && upper.runes.length == 1) {
          shifted = upper.runes.first;
        }
      }
      final text = mods & Mod.shift != 0 && shifted != 0
          ? String.fromCharCode(shifted)
          : char;
      final plain = mods & ~Mod.shift == 0;
      if (plain && !allKeys) {
        return release ? csi(code, 'u') : text;
      }
      return csi(
        code,
        'u',
        shifted: alternates && mods & Mod.shift != 0 ? shifted : 0,
        text: flags & 16 != 0 && allKeys && plain && !release ? text : '',
      );
    case KeyCode.enter || KeyCode.tab || KeyCode.backspace:
      final (code, legacy) = switch (key.code) {
        KeyCode.enter => (13, '\r'),
        KeyCode.tab => (9, '\t'),
        _ => (127, '\x7f'),
      };
      if (!allKeys) {
        if (release) {
          return null;
        }
        if (mods == 0) {
          return legacy;
        }
      }
      return csi(code, 'u');
    case KeyCode.escape:
      if (mods == 0 && !disambiguate && !allKeys) {
        return release ? null : '\x1b';
      }
      return csi(27, 'u');
    case KeyCode.up ||
        KeyCode.down ||
        KeyCode.right ||
        KeyCode.left ||
        KeyCode.home ||
        KeyCode.end ||
        KeyCode.insert ||
        KeyCode.delete ||
        KeyCode.pageUp ||
        KeyCode.pageDown ||
        KeyCode.f1 ||
        KeyCode.f2 ||
        KeyCode.f3 ||
        KeyCode.f4 ||
        KeyCode.f5 ||
        KeyCode.f6 ||
        KeyCode.f7 ||
        KeyCode.f8 ||
        KeyCode.f9 ||
        KeyCode.f10 ||
        KeyCode.f11 ||
        KeyCode.f12:
      final (number, trailer) = switch (key.code) {
        KeyCode.up => (1, 'A'),
        KeyCode.down => (1, 'B'),
        KeyCode.right => (1, 'C'),
        KeyCode.left => (1, 'D'),
        KeyCode.home => (1, 'H'),
        KeyCode.end => (1, 'F'),
        KeyCode.insert => (2, '~'),
        KeyCode.delete => (3, '~'),
        KeyCode.pageUp => (5, '~'),
        KeyCode.pageDown => (6, '~'),
        KeyCode.f1 => (1, 'P'),
        KeyCode.f2 => (1, 'Q'),
        KeyCode.f3 => (13, '~'),
        KeyCode.f4 => (1, 'S'),
        KeyCode.f5 => (15, '~'),
        KeyCode.f6 => (17, '~'),
        KeyCode.f7 => (18, '~'),
        KeyCode.f8 => (19, '~'),
        KeyCode.f9 => (20, '~'),
        KeyCode.f10 => (21, '~'),
        KeyCode.f11 => (23, '~'),
        _ => (24, '~'), // f12
      };
      return csi(number, trailer);
  }
}

/// Ctrl with [char]: the control character xterm sends, or [char] as is.
String _ctrl(String char) {
  if (char.length != 1) {
    return char;
  }
  final c = char.codeUnitAt(0);
  if ((c >= 0x40 && c <= 0x5F) || (c >= 0x61 && c <= 0x7A)) {
    return String.fromCharCode(c & 0x1F); // @, letters, [ \ ] ^ _
  }
  return switch (c) {
    0x20 || 0x32 => '\x00', // space, 2
    0x33 => '\x1b',
    0x34 => '\x1c',
    0x35 => '\x1d',
    0x36 || 0x7E => '\x1e',
    0x37 || 0x2F => '\x1f',
    0x38 || 0x3F => '\x7f',
    _ => char,
  };
}

/// The report of [event] under [protocol] in [encoding]; null when the
/// protocol doesn't report it or its coordinates can't be encoded.
List<int>? mouseSequence(
  MouseEvent event,
  MouseProtocol protocol,
  MouseEncoding encoding,
) {
  if (protocol == MouseProtocol.off) {
    return null;
  }
  final x10 = protocol == MouseProtocol.x10;
  int code;
  var release = false;
  switch (event.kind) {
    case MouseKind.down:
      code = _button(event.button);
    case MouseKind.up:
      if (x10) {
        return null;
      }
      release = true;
      code = encoding == MouseEncoding.sgr ? _button(event.button) : 3;
    case MouseKind.drag:
      if (protocol != MouseProtocol.drags && protocol != MouseProtocol.motion) {
        return null;
      }
      code = _button(event.button);
      if (code >= 0) {
        code += 32;
      }
    case MouseKind.move:
      if (protocol != MouseProtocol.motion) {
        return null;
      }
      code = 35;
    case MouseKind.wheelUp:
      code = 64;
    case MouseKind.wheelDown:
      code = 65;
    case MouseKind.wheelLeft:
      code = 66;
    case MouseKind.wheelRight:
      code = 67;
  }
  if (code < 0) {
    return null;
  }
  if (!x10) {
    final mods = event.modifiers;
    if ((mods & Mod.shift) != 0) {
      code |= 4;
    }
    if ((mods & Mod.alt) != 0) {
      code |= 8;
    }
    if ((mods & Mod.ctrl) != 0) {
      code |= 16;
    }
  }
  final x = event.x + 1;
  final y = event.y + 1;
  switch (encoding) {
    case MouseEncoding.sgr:
      return '\x1b[<$code;$x;$y${release ? 'm' : 'M'}'.codeUnits;
    case MouseEncoding.urxvt:
      return '\x1b[${code + 32};$x;${y}M'.codeUnits;
    case MouseEncoding.utf8:
      if (x + 32 > 2047 || y + 32 > 2047) {
        return null;
      }
      return [
        ...'\x1b[M'.codeUnits,
        ...utf8.encode(String.fromCharCodes([code + 32, x + 32, y + 32])),
      ];
    case MouseEncoding.x10:
      if (x + 32 > 255 || y + 32 > 255) {
        return null;
      }
      return [0x1B, 0x5B, 0x4D, code + 32, x + 32, y + 32];
  }
}

/// The button code of [button] (see `MouseEvent.button`), -1 for none.
int _button(int button) => switch (button) {
  0 || 1 || 2 => button,
  8 || 9 || 10 || 11 => 128 + button - 8,
  _ => -1,
};

/// What pasting [text] sends: line breaks as CR, as typed, and with
/// [bracketed] the text between `CSI 200 ~` and `CSI 201 ~`, an end
/// marker inside it taken out (it would end the paste early).
String pasteSequence(String text, {required bool bracketed}) {
  final t = text.replaceAll('\r\n', '\r').replaceAll('\n', '\r');
  if (!bracketed) {
    return t;
  }
  return '\x1b[200~${t.replaceAll('\x1b[201~', '')}\x1b[201~';
}
