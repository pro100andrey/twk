/// The input of the process's own terminal on Windows, the console's input
/// buffer, read by an isolate of its own through kernel32 ([WindowsInput],
/// for an [IsolateInput]).
library;

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:typed_data';

import '../platform/kernel32.dart';
import 'isolate_input.dart';
import 'link.dart' show TerminalException;

/// The console's input buffer (the standard input's handle) read beside
/// an event, a handle's address being the wake object: what an
/// [IsolateInput] reads on Windows.
///
/// The isolate waits on the event and the console at once, the event
/// first, and reads only the records the console has
/// (`ReadConsoleInputW` of no more than `GetNumberOfConsoleInputEvents`
/// says, so it returns at once): the
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
    final k = kernel32;
    return k == null ? null : WindowsInput._(k);
  }

  final Kernel32 _k;

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
  final k = kernel32!;
  final console = k.getStdHandle(stdInputHandle);
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
        infinite,
      );
      // told to stop (the event first, so it wins when both are set): the
      // console is not read again, whatever it has
      if (woke == waitObject0) {
        return;
      }
      if (woke != waitObject0 + 1) {
        port.send('waiting on the console failed');
        return;
      }
      // the wait said there were records, but another program on the
      // console may have taken them since, and a read of none waits for
      // the next key whatever the event: only what is there is read, the
      // event looked at again first
      if (k.getNumberOfConsoleInputEvents(console, count) == 0) {
        port.send('reading the console failed');
        return;
      }
      final there = count.value;
      if (there == 0) {
        continue;
      }
      if (k.waitForSingleObject(Pointer.fromAddress(wake), 0) == waitObject0) {
        return;
      }
      final take = there < _records ? there : _records;
      if (k.readConsoleInput(console, records.cast(), take, count) == 0) {
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
        port.send(utf8OfUnits(units));
      }
    }
  } finally {
    k
      ..free(handles.cast())
      ..free(records.cast())
      ..free(count.cast());
  }
}

/// The UTF-8 of [units], UTF-16 code units, in one pass: the bytes
/// `utf8.encode(String.fromCharCodes(units))` gives, a surrogate without
/// its other half being U+FFFD. Encoded and sent to another isolate, 512
/// units of ASCII take 2.5 µs where that took 3.9, and of CJK and emoji
/// 3.1 where it took 3.7.
Uint8List utf8OfUnits(List<int> units) {
  final out = Uint8List(units.length * 3);
  var o = 0;
  for (var i = 0; i < units.length; i++) {
    var unit = units[i];
    if (unit < 0x80) {
      out[o++] = unit;
    } else if (unit < 0x800) {
      out[o++] = 0xC0 | unit >> 6;
      out[o++] = 0x80 | unit & 0x3F;
    } else if (unit & 0xFC00 == 0xD800 &&
        i + 1 < units.length &&
        units[i + 1] & 0xFC00 == 0xDC00) {
      // a pair: one code point of four bytes
      final point = 0x10000 + ((unit & 0x3FF) << 10 | units[++i] & 0x3FF);
      out[o++] = 0xF0 | point >> 18;
      out[o++] = 0x80 | point >> 12 & 0x3F;
      out[o++] = 0x80 | point >> 6 & 0x3F;
      out[o++] = 0x80 | point & 0x3F;
    } else {
      if (unit & 0xF800 == 0xD800) {
        unit = 0xFFFD;
      }
      out[o++] = 0xE0 | unit >> 12;
      out[o++] = 0x80 | unit >> 6 & 0x3F;
      out[o++] = 0x80 | unit & 0x3F;
    }
  }
  // a copy of what was written: a view would send the whole buffer
  return out.sublist(0, o);
}
