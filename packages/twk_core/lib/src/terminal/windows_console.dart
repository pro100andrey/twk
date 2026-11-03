/// [WindowsConsole], the Windows console's modes through kernel32, via
/// `dart:ffi` only (no `package:ffi`): VT processing for output, VT
/// sequences for input, UTF-8 code pages, and restoring everything on
/// exit. It compiles on every platform; kernel32 is opened only when one
/// is made.
library;

import 'dart:ffi';

import '../platform/kernel32.dart';

// input modes
const _enableProcessedInput = 0x0001;
const _enableLineInput = 0x0002;
const _enableEchoInput = 0x0004;
const _enableWindowInput = 0x0008;
const _enableMouseInput = 0x0010;
const _enableQuickEditMode = 0x0040;
const _enableExtendedFlags = 0x0080;
const _enableVirtualTerminalInput = 0x0200;

// output modes
const _enableProcessedOutput = 0x0001;
const _enableVirtualTerminalProcessing = 0x0004;
const _disableNewlineAutoReturn = 0x0008;

const _cpUtf8 = 65001;

/// The modes of the process's Windows console that a terminal app needs,
/// and the console's own to put back.
///
/// [enable] switches the console to VT input and output and UTF-8 code
/// pages, [restore] puts back what it found. The process's own terminal
/// link (`StdioLink`) uses one on Windows, for its raw mode.
final class WindowsConsole {
  /// The console of this process, through kernel32; throws
  /// [ArgumentError] where kernel32 can't be opened (not on Windows).
  factory WindowsConsole() => WindowsConsole._(
    kernel32 ?? (throw ArgumentError('kernel32 can not be opened')),
  );

  WindowsConsole._(this._k);

  final Kernel32 _k;

  int? _origIn;
  int? _origOut;
  int? _origOutCp;
  int? _origInCp;

  int? _mode(Pointer<Void> h) {
    final p = _k.alloc(4).cast<Uint32>();
    try {
      return _k.getConsoleMode(h, p) != 0 ? p.value : null;
    } finally {
      _k.free(p.cast());
    }
  }

  /// Switches the console to VT input/output and UTF-8. Returns false if
  /// the handles aren't consoles (redirected) or VT isn't available
  /// (Windows < 10 1809).
  bool enable() {
    final hin = _k.getStdHandle(stdInputHandle);
    final hout = _k.getStdHandle(stdOutputHandle);
    _origIn = _mode(hin);
    _origOut = _mode(hout);
    if (_origIn == null || _origOut == null) {
      return false;
    }
    _origOutCp = _k.getConsoleOutputCP();
    _origInCp = _k.getConsoleCP();

    final outMode =
        _origOut! |
        _enableProcessedOutput |
        _enableVirtualTerminalProcessing |
        _disableNewlineAutoReturn;
    if (_k.setConsoleMode(hout, outMode) == 0) {
      return false;
    }

    var inMode = _origIn! | _enableVirtualTerminalInput | _enableExtendedFlags;
    inMode &=
        ~(_enableProcessedInput |
            _enableLineInput |
            _enableEchoInput |
            _enableQuickEditMode | // would swallow mouse clicks
            _enableWindowInput |
            _enableMouseInput); // mouse arrives as VT sequences instead
    if (_k.setConsoleMode(hin, inMode) == 0) {
      _k.setConsoleMode(hout, _origOut!);
      return false;
    }
    _k.setConsoleOutputCP(_cpUtf8);
    _k.setConsoleCP(_cpUtf8);
    return true;
  }

  /// Puts back the modes and code pages [enable] found; nothing for those
  /// it didn't read.
  void restore() {
    final hin = _k.getStdHandle(stdInputHandle);
    final hout = _k.getStdHandle(stdOutputHandle);
    if (_origIn != null) {
      _k.setConsoleMode(hin, _origIn!);
    }
    if (_origOut != null) {
      _k.setConsoleMode(hout, _origOut!);
    }
    if (_origOutCp != null) {
      _k.setConsoleOutputCP(_origOutCp!);
    }
    if (_origInCp != null) {
      _k.setConsoleCP(_origInCp!);
    }
  }
}
