/// [WindowsConsole], the Windows console's modes through kernel32, via
/// `dart:ffi` only (no `package:ffi`): VT processing for output, VT
/// sequences for input, UTF-8 code pages, and restoring everything on
/// exit. It compiles on every platform; kernel32 is opened only when one
/// is made.
library;

import 'dart:ffi';

const _stdInputHandle = -10;
const _stdOutputHandle = -11;

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
const _lptr = 0x0040; // LMEM_ZEROINIT | LMEM_FIXED

typedef _GetStdHandleD = Pointer<Void> Function(int);
typedef _GetModeD = int Function(Pointer<Void>, Pointer<Uint32>);
typedef _SetModeD = int Function(Pointer<Void>, int);
typedef _GetCpC = Uint32 Function();
typedef _GetCpD = int Function();
typedef _SetCpC = Int32 Function(Uint32);
typedef _SetCpD = int Function(int);
typedef _LocalAllocD = Pointer<Void> Function(int, int);
typedef _LocalFreeD = Pointer<Void> Function(Pointer<Void>);

/// The modes of the process's Windows console that a terminal app needs,
/// and the console's own to put back.
///
/// [enable] switches the console to VT input and output and UTF-8 code
/// pages, [restore] puts back what it found. The process's own terminal
/// link (`StdioLink`) uses one on Windows, for its raw mode.
final class WindowsConsole {
  /// The console of this process, through kernel32; throws
  /// [ArgumentError] where kernel32 can't be opened (not on Windows).
  factory WindowsConsole() =>
      WindowsConsole._(DynamicLibrary.open('kernel32.dll'));

  WindowsConsole._(DynamicLibrary k32)
    : _getStdHandle = k32
          .lookupFunction<Pointer<Void> Function(Int32), _GetStdHandleD>(
            'GetStdHandle',
          ),
      _getMode = k32
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Uint32>),
            _GetModeD
          >('GetConsoleMode'),
      _setMode = k32
          .lookupFunction<Int32 Function(Pointer<Void>, Uint32), _SetModeD>(
            'SetConsoleMode',
          ),
      _getOutCp = k32.lookupFunction<_GetCpC, _GetCpD>('GetConsoleOutputCP'),
      _setOutCp = k32.lookupFunction<_SetCpC, _SetCpD>('SetConsoleOutputCP'),
      _getInCp = k32.lookupFunction<_GetCpC, _GetCpD>('GetConsoleCP'),
      _setInCp = k32.lookupFunction<_SetCpC, _SetCpD>('SetConsoleCP'),
      _localAlloc = k32
          .lookupFunction<Pointer<Void> Function(Uint32, IntPtr), _LocalAllocD>(
            'LocalAlloc',
          ),
      _localFree = k32
          .lookupFunction<Pointer<Void> Function(Pointer<Void>), _LocalFreeD>(
            'LocalFree',
          );

  final _GetStdHandleD _getStdHandle;
  final _GetModeD _getMode;
  final _SetModeD _setMode;
  final _GetCpD _getOutCp;
  final _SetCpD _setOutCp;
  final _GetCpD _getInCp;
  final _SetCpD _setInCp;
  final _LocalAllocD _localAlloc;
  final _LocalFreeD _localFree;

  int? _origIn;
  int? _origOut;
  int? _origOutCp;
  int? _origInCp;

  int? _mode(Pointer<Void> h) {
    final p = _localAlloc(_lptr, 4).cast<Uint32>();
    try {
      return _getMode(h, p) != 0 ? p.value : null;
    } finally {
      _localFree(p.cast());
    }
  }

  /// Switches the console to VT input/output and UTF-8. Returns false if
  /// the handles aren't consoles (redirected) or VT isn't available
  /// (Windows < 10 1809).
  bool enable() {
    final hin = _getStdHandle(_stdInputHandle);
    final hout = _getStdHandle(_stdOutputHandle);
    _origIn = _mode(hin);
    _origOut = _mode(hout);
    if (_origIn == null || _origOut == null) {
      return false;
    }
    _origOutCp = _getOutCp();
    _origInCp = _getInCp();

    final outMode =
        _origOut! |
        _enableProcessedOutput |
        _enableVirtualTerminalProcessing |
        _disableNewlineAutoReturn;
    if (_setMode(hout, outMode) == 0) {
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
    if (_setMode(hin, inMode) == 0) {
      _setMode(hout, _origOut!);
      return false;
    }
    _setOutCp(_cpUtf8);
    _setInCp(_cpUtf8);
    return true;
  }

  /// Puts back the modes and code pages [enable] found; nothing for those
  /// it didn't read.
  void restore() {
    final hin = _getStdHandle(_stdInputHandle);
    final hout = _getStdHandle(_stdOutputHandle);
    if (_origIn != null) {
      _setMode(hin, _origIn!);
    }
    if (_origOut != null) {
      _setMode(hout, _origOut!);
    }
    if (_origOutCp != null) {
      _setOutCp(_origOutCp!);
    }
    if (_origInCp != null) {
      _setInCp(_origInCp!);
    }
  }
}
