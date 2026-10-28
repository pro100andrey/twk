/// The rest of raw mode on Linux and macOS, through libc's termios via
/// `dart:ffi` only (no `package:ffi`). dart:io's raw mode leaves ISIG on, so
/// Ctrl+\ would kill the process (SIGQUIT can't be watched from Dart) and
/// Ctrl+Z would stop it, both with the terminal still in raw mode; it also
/// leaves flow control on, so Ctrl+S would freeze the screen. With these
/// off the keys, and Ctrl+C, arrive as input like any other key.
library;

import 'dart:ffi';
import 'dart:io';

typedef _TcGetAttrD = int Function(int, Pointer<Uint8>);
typedef _TcSetAttrD = int Function(int, int, Pointer<Uint8>);
typedef _MallocD = Pointer<Void> Function(int);
typedef _FreeD = void Function(Pointer<Void>);

const _stdinFd = 0;
const _tcsanow = 0;

/// Bigger than `struct termios` on every supported platform.
const _termiosBytes = 256;

/// The termios flags of stdin that dart:io's raw mode leaves on, turned
/// off ([enterRaw]) and put back ([restore]), with the tty's erase
/// character.
///
/// The process's own terminal link (`StdioLink`) uses one on Linux and
/// macOS ([forStdin]), after dart:io's own raw mode.
final class PosixTty {
  PosixTty._(
    this._flagBytes,
    this._lflagOffset,
    this._isig,
    this._ixon,
    this._eraseOffset,
    DynamicLibrary c,
  ) : _tcgetattr = c
          .lookupFunction<Int32 Function(Int32, Pointer<Uint8>), _TcGetAttrD>(
            'tcgetattr',
          ),
      _tcsetattr = c
          .lookupFunction<
            Int32 Function(Int32, Int32, Pointer<Uint8>),
            _TcSetAttrD
          >('tcsetattr'),
      _malloc = c.lookupFunction<Pointer<Void> Function(IntPtr), _MallocD>(
        'malloc',
      ),
      _free = c.lookupFunction<Void Function(Pointer<Void>), _FreeD>('free');

  /// Returns the termios of stdin, with the flag layout of this platform's
  /// `struct termios`, or null where it isn't known (not Linux, Android or
  /// macOS) or libc can't be reached.
  static PosixTty? forStdin() {
    final linux = Platform.isLinux || Platform.isAndroid;
    if (!linux && !Platform.isMacOS) {
      return null;
    }
    final c = DynamicLibrary.process();
    for (final symbol in ['tcgetattr', 'tcsetattr', 'malloc', 'free']) {
      if (!c.providesSymbol(symbol)) {
        return null;
      }
    }
    return linux
        // four 32-bit tcflag_t (c_iflag first, c_lflag fourth), c_line, then
        // c_cc with VERASE at index 2
        ? PosixTty._(4, 12, 0x1, 0x400, 17 + 2, c)
        // four 64-bit tcflag_t (unsigned long), then c_cc with VERASE at 3
        : PosixTty._(8, 24, 0x80, 0x200, 32 + 3, c);
  }

  /// c_iflag is the first field everywhere; ICRNL has the same value.
  static const _iflagOffset = 0;
  static const _icrnl = 0x100;

  final int _flagBytes;
  final int _lflagOffset;
  final int _isig;
  final int _ixon;
  final int _eraseOffset;
  final _TcGetAttrD _tcgetattr;
  final _TcSetAttrD _tcsetattr;
  final _MallocD _malloc;
  final _FreeD _free;

  /// The bits [enterRaw] cleared, as they were; null when nothing to
  /// restore.
  (int, int)? _saved;

  /// The tty's erase character (VERASE) as [enterRaw] found it: the byte
  /// the Backspace key sends, 0x7F or 0x08 (^H) on some setups.
  int? eraseChar;

  /// Turns off what dart:io's raw mode leaves on: terminal-generated
  /// signals (ISIG), output flow control (IXON: Ctrl+S would freeze the
  /// screen until Ctrl+Q) and CR to NL translation of input (ICRNL: Enter
  /// and Ctrl+J would be the same byte). Returns false if that failed.
  bool enterRaw() {
    final iMask = _ixon | _icrnl;
    final old = _update((i, l) => (i & ~iMask, l & ~_isig));
    if (old == null) {
      return false;
    }
    _saved = (old.$1 & iMask, old.$2 & _isig);
    eraseChar = old.$3;
    return true;
  }

  /// Puts the bits back as they were. Must run while stdin is still open.
  void restore() {
    final saved = _saved;
    if (saved == null) {
      return;
    }
    _saved = null;
    final iMask = _ixon | _icrnl;
    _update((i, l) => ((i & ~iMask) | saved.$1, (l & ~_isig) | saved.$2));
  }

  /// Applies [change] to (c_iflag, c_lflag); returns their old values and
  /// the erase character, or null when the terminal attributes couldn't be
  /// read or written.
  (int, int, int)? _update((int, int) Function(int iflag, int lflag) change) {
    final p = _malloc(_termiosBytes).cast<Uint8>();
    if (p.address == 0) {
      return null;
    }
    try {
      if (_tcgetattr(_stdinFd, p) != 0) {
        return null;
      }
      final iflag = _read(p, _iflagOffset);
      final lflag = _read(p, _lflagOffset);
      final old = (iflag, lflag, (p + _eraseOffset).value);
      final now = change(iflag, lflag);
      if (now == (iflag, lflag)) {
        return old;
      }
      _write(p, _iflagOffset, now.$1);
      _write(p, _lflagOffset, now.$2);
      return _tcsetattr(_stdinFd, _tcsanow, p) == 0 ? old : null;
    } finally {
      _free(p.cast());
    }
  }

  int _read(Pointer<Uint8> p, int offset) {
    final field = Pointer<Uint8>.fromAddress(p.address + offset);
    return _flagBytes == 4
        ? field.cast<Uint32>().value
        : field.cast<Uint64>().value;
  }

  void _write(Pointer<Uint8> p, int offset, int value) {
    final field = Pointer<Uint8>.fromAddress(p.address + offset);
    if (_flagBytes == 4) {
      field.cast<Uint32>().value = value;
    } else {
      field.cast<Uint64>().value = value;
    }
  }
}
