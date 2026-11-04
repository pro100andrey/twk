/// The kernel32 calls the core binds on Windows, through `dart:ffi` (no
/// `package:ffi`): the console's modes and code pages (`WindowsConsole`)
/// and the reading of its input buffer (`WindowsInput`). kernel32 is
/// opened on the first use of [kernel32], in each isolate that uses it.
library;

import 'dart:ffi';

/// kernel32 in this isolate, or null where it can't be opened (not
/// Windows) or lacks a function [Kernel32] calls.
final Kernel32? kernel32 = Kernel32._open();

/// GetStdHandle's STD_INPUT_HANDLE.
const stdInputHandle = -10;

/// GetStdHandle's STD_OUTPUT_HANDLE.
const stdOutputHandle = -11;

/// WaitForMultipleObjects' and WaitForSingleObject's INFINITE.
const infinite = 0xFFFFFFFF;

/// WAIT_OBJECT_0: the first of the handles waited on is signalled.
const waitObject0 = 0;

/// LMEM_FIXED | LMEM_ZEROINIT, for LocalAlloc.
const _lptr = 0x0040;

/// The functions of kernel32 the core calls, each named as kernel32 names
/// it.
final class Kernel32 {
  Kernel32._(DynamicLibrary k)
    : getStdHandle = k
          .lookupFunction<
            Pointer<Void> Function(Int32),
            Pointer<Void> Function(int)
          >('GetStdHandle'),
      getConsoleMode = k
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Uint32>),
            int Function(Pointer<Void>, Pointer<Uint32>)
          >('GetConsoleMode'),
      setConsoleMode = k
          .lookupFunction<
            Int32 Function(Pointer<Void>, Uint32),
            int Function(Pointer<Void>, int)
          >('SetConsoleMode'),
      getConsoleOutputCP = k.lookupFunction<Uint32 Function(), int Function()>(
        'GetConsoleOutputCP',
      ),
      setConsoleOutputCP = k
          .lookupFunction<Int32 Function(Uint32), int Function(int)>(
            'SetConsoleOutputCP',
          ),
      getConsoleCP = k.lookupFunction<Uint32 Function(), int Function()>(
        'GetConsoleCP',
      ),
      setConsoleCP = k
          .lookupFunction<Int32 Function(Uint32), int Function(int)>(
            'SetConsoleCP',
          ),
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
      waitForSingleObject = k
          .lookupFunction<
            Uint32 Function(Pointer<Void>, Uint32),
            int Function(Pointer<Void>, int)
          >('WaitForSingleObject'),
      getNumberOfConsoleInputEvents = k
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Uint32>),
            int Function(Pointer<Void>, Pointer<Uint32>)
          >('GetNumberOfConsoleInputEvents'),
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

  static Kernel32? _open() {
    try {
      return Kernel32._(DynamicLibrary.open('kernel32.dll'));
    } on Object {
      // not Windows, or a function missing
      return null;
    }
  }

  /// GetStdHandle: the handle of [stdInputHandle] or [stdOutputHandle].
  final Pointer<Void> Function(int) getStdHandle;

  /// GetConsoleMode: a console handle's mode into the DWORD given; 0 where
  /// the handle is no console.
  final int Function(Pointer<Void>, Pointer<Uint32>) getConsoleMode;

  /// SetConsoleMode: sets a console handle's mode; 0 on an error.
  final int Function(Pointer<Void>, int) setConsoleMode;

  /// GetConsoleOutputCP: the code page of the console's output.
  final int Function() getConsoleOutputCP;

  /// SetConsoleOutputCP: sets the code page of the console's output.
  final int Function(int) setConsoleOutputCP;

  /// GetConsoleCP: the code page of the console's input.
  final int Function() getConsoleCP;

  /// SetConsoleCP: sets the code page of the console's input.
  final int Function(int) setConsoleCP;

  /// CreateEventW: an event (attributes, manual reset, set, name), or
  /// `nullptr`.
  final Pointer<Void> Function(Pointer<Void>, int, int, Pointer<Void>)
  createEvent;

  /// SetEvent: sets an event; 0 on an error.
  final int Function(Pointer<Void>) setEvent;

  /// CloseHandle: closes a handle; 0 on an error.
  final int Function(Pointer<Void>) closeHandle;

  /// WaitForMultipleObjects: waits (how many, the handles, all of them,
  /// milliseconds or [infinite]); [waitObject0] plus the index of the one
  /// signalled first.
  final int Function(int, Pointer<Pointer<Void>>, int, int)
  waitForMultipleObjects;

  /// WaitForSingleObject: waits for a handle (milliseconds or
  /// [infinite]); [waitObject0] where it is signalled.
  final int Function(Pointer<Void>, int) waitForSingleObject;

  /// GetNumberOfConsoleInputEvents: the records in a console's input
  /// buffer, unread, into the DWORD given; 0 on an error.
  final int Function(Pointer<Void>, Pointer<Uint32>)
  getNumberOfConsoleInputEvents;

  /// ReadConsoleInputW: reads at most as many records as given into the
  /// buffer, how many into the DWORD; it waits while there are none. 0 on
  /// an error.
  final int Function(Pointer<Void>, Pointer<Void>, int, Pointer<Uint32>)
  readConsoleInput;

  final Pointer<Void> Function(int, int) _localAlloc;
  final Pointer<Void> Function(Pointer<Void>) _localFree;

  /// [bytes] of zeroed memory from LocalAlloc, for [free]; `nullptr` where
  /// there is none.
  Pointer<Void> alloc(int bytes) => _localAlloc(_lptr, bytes);

  /// Frees what [alloc] gave.
  void free(Pointer<Void> p) => _localFree(p);
}
