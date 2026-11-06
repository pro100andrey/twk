/// The rest of raw mode on Linux and macOS, through libc's termios via
/// `dart:ffi` only (no `package:ffi`). dart:io's raw mode leaves ISIG on, so
/// Ctrl+\ would kill the process (SIGQUIT can't be watched from Dart) and
/// Ctrl+Z would stop it, both with the terminal still in raw mode; it also
/// leaves flow control on, so Ctrl+S would freeze the screen. With these
/// off the keys, and Ctrl+C, arrive as input like any other key.
library;

import 'dart:ffi';
import 'dart:io';

import '../platform/libc.dart' as c;

const _stdinFd = 0;

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
  );

  /// Returns the termios of stdin, with the flag layout of this platform's
  /// `struct termios`, or null where it isn't known (not Linux, Android or
  /// macOS).
  static PosixTty? forStdin() {
    final linux = Platform.isLinux || Platform.isAndroid;
    if (!linux && !Platform.isMacOS) {
      return null;
    }
    return linux
        // four 32-bit tcflag_t (c_iflag first, c_lflag fourth), c_line, then
        // c_cc with VERASE at index 2
        ? PosixTty._(4, 12, 0x1, 0x400, 17 + 2)
        // four 64-bit tcflag_t (unsigned long), then c_cc with VERASE at 3
        : PosixTty._(8, 24, 0x80, 0x200, 32 + 3);
  }

  /// Returns once this process's group is the foreground group of the
  /// terminal on stdin, stopping itself (SIGSTOP, as a job is stopped that
  /// wants the terminal) for as long as it is not: an app started with `&`
  /// waits here, before it changes a mode or writes a query, for the shell's
  /// `fg`, which hands over the terminal and then continues the job. A
  /// SIGCONT without the terminal (`kill -CONT`) stops it again. Returns at
  /// once where stdin is no controlling terminal (a pipe, another session).
  ///
  /// The kernel would stop a background `tcsetattr` itself (SIGTTOU), but
  /// the Dart VM does not take it, so the process asks.
  static void waitForForeground() {
    while (true) {
      final foreground = _tcgetpgrp(_stdinFd);
      if (foreground < 0 || foreground == _getpgrp()) {
        return;
      }
      _kill(_getpid(), Platform.isMacOS ? _sigstopMacos : _sigstopLinux);
    }
  }

  static const _sigstopLinux = 19;
  static const _sigstopMacos = 17;

  /// c_iflag is the first field everywhere; ICRNL has the same value.
  static const _iflagOffset = 0;
  static const _icrnl = 0x100;

  final int _flagBytes;
  final int _lflagOffset;
  final int _isig;
  final int _ixon;
  final int _eraseOffset;

  /// What SIGTSTP did before [enterRaw]; null while nothing holds it.
  Pointer<Void>? _stopHandler;

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
  ///
  /// A SIGTSTP from outside (`kill -TSTP`) does nothing until [restore]: it
  /// would stop the process with the terminal as it has it, and Dart can't
  /// watch it to give it back first. A handler that does nothing, not
  /// SIG_IGN, which the programs it starts would inherit: exec resets a
  /// handler. Its own stop (`Terminal.stopForShell`) comes after [restore].
  bool enterRaw() {
    // getppid as a handler that does nothing: safe in a signal handler, it
    // leaves errno alone, takes no notice of the signal's number and has an
    // address, where a function of Dart's can't run in a handler
    _stopHandler ??= c.signal(
      c.sigtstp,
      Native.addressOf<NativeFunction<Int Function()>>(c.getppid).cast(),
    );
    final iMask = _ixon | _icrnl;
    final old = _update((i, l) => (i & ~iMask, l & ~_isig));
    if (old == null) {
      return false;
    }
    _saved = (old.$1 & iMask, old.$2 & _isig);
    eraseChar = old.$3;
    return true;
  }

  /// Puts the bits back as they were, and SIGTSTP as [enterRaw] found it.
  /// Must run while stdin is still open.
  void restore() {
    final stop = _stopHandler;
    if (stop != null) {
      c.signal(c.sigtstp, stop);
      _stopHandler = null;
    }
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
    final p = c.calloc(1, _termiosBytes).cast<Uint8>();
    if (p == nullptr) {
      return null;
    }
    try {
      if (c.tcgetattr(_stdinFd, p.cast()) != 0) {
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
      return c.tcsetattr(_stdinFd, c.tcsanow, p.cast()) == 0 ? old : null;
    } finally {
      c.free(p.cast());
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

@Native<Int Function(Int)>(symbol: 'tcgetpgrp', isLeaf: true)
external int _tcgetpgrp(int fd);

@Native<Int Function()>(symbol: 'getpgrp', isLeaf: true)
external int _getpgrp();

@Native<Int Function()>(symbol: 'getpid', isLeaf: true)
external int _getpid();

@Native<Int Function(Int, Int)>(symbol: 'kill', isLeaf: true)
external int _kill(int pid, int sig);
