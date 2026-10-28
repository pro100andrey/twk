/// [RawTty]: the terminal on stdin in raw mode, through libc's termios
/// (`libc.dart`), on Linux and macOS.
library;

import 'dart:ffi';
import 'dart:io';

import 'libc.dart' as c;

const _stdin = 0;

/// Bigger than `struct termios` on Linux (60 bytes) and macOS (72).
const _termiosBytes = 256;

/// The four flag fields that start `struct termios`: 32 bits each on
/// Linux, 64 on macOS.
final _flagBytes = Platform.isMacOS ? 32 : 16;

/// The terminal on stdin as `cfmakeraw` leaves it: every byte typed comes
/// through as it is, Ctrl+C, Ctrl+Z, Ctrl+\ and Ctrl+S included, nothing
/// is echoed, and what is written goes out unchanged (no output
/// processing: a line feed is not made CR LF). [restore] puts back what
/// [enter] found.
///
/// For a program that passes the keys typed on to another, such as one
/// in a `Pty`; an app of twk's has its terminal set up by the core.
///
/// ```dart
/// final tty = RawTty.enter(); // null where stdin is no terminal
/// try {
///   // read stdin byte by byte
/// } finally {
///   tty?.restore();
/// }
/// ```
final class RawTty {
  RawTty._(this._saved, this._raw, this._scratch);

  /// Puts the terminal on stdin in raw mode; null where stdin is no
  /// terminal, or off Linux and macOS.
  static RawTty? enter() {
    if (!Platform.isLinux && !Platform.isMacOS || !stdin.hasTerminal) {
      return null;
    }
    final memory = c.calloc(3, _termiosBytes).cast<Uint8>();
    final saved = memory.cast<Void>();
    final raw = (memory + _termiosBytes).cast<Void>();
    final scratch = (memory + 2 * _termiosBytes).cast<Void>();
    if (c.tcgetattr(_stdin, saved) != 0) {
      c.free(saved);
      return null;
    }
    raw
        .cast<Uint8>()
        .asTypedList(_termiosBytes)
        .setAll(0, saved.cast<Uint8>().asTypedList(_termiosBytes));
    c.cfmakeraw(raw);
    if (c.tcsetattr(_stdin, c.tcsanow, raw) != 0) {
      c.free(saved);
      return null;
    }
    return RawTty._(saved, raw, scratch);
  }

  final Pointer<Void> _saved;
  final Pointer<Void> _raw;
  final Pointer<Void> _scratch;
  var _restored = false;

  /// The terminal is as [enter] left it: nothing, such as a shell taking
  /// the terminal while this process was stopped, changed its modes since.
  bool get isRaw {
    if (_restored || c.tcgetattr(_stdin, _scratch) != 0) {
      return true;
    }
    final now = _scratch.cast<Uint8>().asTypedList(_flagBytes);
    final raw = _raw.cast<Uint8>().asTypedList(_flagBytes);
    for (var i = 0; i < _flagBytes; i++) {
      if (now[i] != raw[i]) {
        return false;
      }
    }
    return true;
  }

  /// Puts the terminal in raw mode again, after something changed it.
  void reenter() {
    if (!_restored) {
      c.tcsetattr(_stdin, c.tcsanow, _raw);
    }
  }

  /// Puts back the modes [enter] found, once; with [discardInput] what was
  /// typed and not read yet is dropped (answers to queries the terminal
  /// was sent).
  void restore({bool discardInput = false}) {
    if (_restored) {
      return;
    }
    _restored = true;
    c.tcsetattr(_stdin, discardInput ? c.tcsaflush : c.tcsanow, _saved);
    c.free(_saved);
  }
}
