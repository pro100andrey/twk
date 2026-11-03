/// The input of the process's own terminal on Windows, the console's input
/// buffer, read by an isolate of its own through kernel32 ([WindowsInput],
/// for an [IsolateInput]).
library;

import 'dart:convert' show utf8;
import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:typed_data';

import 'isolate_input.dart';
import 'link.dart' show TerminalException;

/// The console's input buffer (the standard input's handle) read beside
/// an event, a handle's address being the wake object: what an
/// [IsolateInput] reads on Windows.
///
/// The isolate waits on the event and the console at once, the event
/// first, and reads only the records the console has
/// (`ReadConsoleInputW`, which returns at once when there are some): the
/// characters of the keys pressed, which in the console's VT input mode
/// are the sequences of the keys, as UTF-8. It never blocks in a read, so
/// once the event is set it reads nothing more, and the console's handle
/// is left open, for a program started after and a later terminal.
final class WindowsInput implements InputDevice<int> {
  WindowsInput._(this._k);

  /// The reader of the console, or null where it can't be one: not
  /// Windows, or kernel32 without what it calls.
  static WindowsInput? open() {
    if (!Platform.isWindows) {
      return null;
    }
    final k = _Kernel32.of();
    return k == null ? null : WindowsInput._(k);
  }

  final _Kernel32 _k;

  @override
  int openWake() {
    // manual reset, unset: set once, it stays set for the waits after
    final event = _k.createEvent(nullptr, 1, 0, nullptr);
    if (event == nullptr) {
      throw const TerminalException('no event to read the console with');
    }
    return event.address;
  }

  @override
  void signal(int wake) => _k.setEvent(Pointer.fromAddress(wake));

  @override
  void closeWake(int wake) => _k.closeHandle(Pointer.fromAddress(wake));

  @override
  Future<void> spawn(int wake, SendPort port) => Isolate.spawn(
    _read,
    (wake, port),
    onExit: port,
    onError: port,
    debugName: 'terminal input',
  );
}

const _stdInputHandle = -10;
const _infinite = 0xFFFFFFFF;
const _waitObject0 = 0;
const _keyEvent = 0x0001;
const _vkMenu = 0x12;

// the records one read takes
const _records = 512;

// INPUT_RECORD: EventType (WORD), two bytes of padding, then the event; of
// a KEY_EVENT_RECORD bKeyDown (BOOL), wRepeatCount, wVirtualKeyCode,
// wVirtualScanCode, UnicodeChar (WORDs), dwControlKeyState (DWORD)
const _recordSize = 20;
const _eventType = 0;
const _keyDown = 4;
const _repeat = 8;
const _virtualKey = 10;
const _char = 14;

/// Reads the console until the event [args].$1 is set, sending what it
/// reads to [args].$2, or what failed.
void _read((int, SendPort) args) {
  final (wake, port) = args;
  final k = _Kernel32.of()!;
  final console = k.getStdHandle(_stdInputHandle);
  final handles = k.alloc(2 * sizeOf<IntPtr>()).cast<IntPtr>()
    ..[0] = wake
    ..[1] = console.address;
  final records = k.alloc(_records * _recordSize).cast<Uint8>();
  final count = k.alloc(sizeOf<Uint32>()).cast<Uint32>();
  // the high surrogate a read ended with, for the next one
  int? high;
  try {
    while (true) {
      final woke = k.waitForMultipleObjects(
        2,
        handles.cast(),
        0,
        _infinite,
      );
      // told to stop (the event first, so it wins when both are set): the
      // console is not read again, whatever it has
      if (woke == _waitObject0) {
        return;
      }
      if (woke != _waitObject0 + 1) {
        port.send('waiting on the console failed');
        return;
      }
      if (k.readConsoleInput(console, records.cast(), _records, count) == 0) {
        port.send('reading the console failed');
        return;
      }
      final units = <int>[?high];
      high = null;
      final data = records.asTypedList(count.value * _recordSize);
      final view = ByteData.sublistView(data);
      for (var at = 0; at < data.length; at += _recordSize) {
        if (view.getUint16(at + _eventType, Endian.little) != _keyEvent) {
          continue;
        }
        final char = view.getUint16(at + _char, Endian.little);
        final down = view.getInt32(at + _keyDown, Endian.little) != 0;
        // a character comes with its key down, but one typed as Alt and
        // digits with Alt let go
        final alt = view.getUint16(at + _virtualKey, Endian.little) == _vkMenu;
        if (char == 0 || !(down || alt)) {
          continue;
        }
        final repeat = view.getUint16(at + _repeat, Endian.little);
        for (var i = repeat < 1 ? 1 : repeat; i > 0; i--) {
          units.add(char);
        }
      }
      if (units.isNotEmpty && units.last & 0xFC00 == 0xD800) {
        high = units.removeLast();
      }
      if (units.isNotEmpty) {
        port.send(
          Uint8List.fromList(utf8.encode(String.fromCharCodes(units))),
        );
      }
    }
  } finally {
    k
      ..free(handles.cast())
      ..free(records.cast())
      ..free(count.cast());
  }
}

const _lptr = 0x0040; // LMEM_ZEROINIT | LMEM_FIXED

/// What of kernel32 the reader calls (each isolate looks it up for
/// itself).
final class _Kernel32 {
  _Kernel32._(DynamicLibrary k)
    : getStdHandle = k
          .lookupFunction<
            Pointer<Void> Function(Int32),
            Pointer<Void> Function(int)
          >('GetStdHandle'),
      createEvent = k
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>, Int32, Int32, Pointer<Void>),
            Pointer<Void> Function(Pointer<Void>, int, int, Pointer<Void>)
          >('CreateEventW'),
      setEvent = k
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('SetEvent'),
      closeHandle = k
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('CloseHandle'),
      waitForMultipleObjects = k
          .lookupFunction<
            Uint32 Function(Uint32, Pointer<Pointer<Void>>, Int32, Uint32),
            int Function(int, Pointer<Pointer<Void>>, int, int)
          >('WaitForMultipleObjects'),
      readConsoleInput = k
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Void>,
              Uint32,
              Pointer<Uint32>,
            ),
            int Function(Pointer<Void>, Pointer<Void>, int, Pointer<Uint32>)
          >('ReadConsoleInputW'),
      _localAlloc = k
          .lookupFunction<
            Pointer<Void> Function(Uint32, IntPtr),
            Pointer<Void> Function(int, int)
          >('LocalAlloc'),
      _localFree = k
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>),
            Pointer<Void> Function(Pointer<Void>)
          >('LocalFree');

  static _Kernel32? _cached;

  /// kernel32, or null where it can't be opened.
  static _Kernel32? of() {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }
    try {
      return _cached = _Kernel32._(DynamicLibrary.open('kernel32.dll'));
    } on Object {
      // not Windows, or a function missing (ArgumentError)
      return null;
    }
  }

  final Pointer<Void> Function(int) getStdHandle;
  final Pointer<Void> Function(Pointer<Void>, int, int, Pointer<Void>)
  createEvent;
  final int Function(Pointer<Void>) setEvent;
  final int Function(Pointer<Void>) closeHandle;
  final int Function(int, Pointer<Pointer<Void>>, int, int)
  waitForMultipleObjects;
  final int Function(Pointer<Void>, Pointer<Void>, int, Pointer<Uint32>)
  readConsoleInput;
  final Pointer<Void> Function(int, int) _localAlloc;
  final Pointer<Void> Function(Pointer<Void>) _localFree;

  /// [bytes] of zeroed memory, for [free].
  Pointer<Void> alloc(int bytes) => _localAlloc(_lptr, bytes);

  /// Frees what [alloc] gave.
  void free(Pointer<Void> p) => _localFree(p);
}
