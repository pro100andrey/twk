// A probe, not a test: what Ctrl+Space becomes in a console in VT input
// mode, as records (ReadConsoleInputW), through ReadFile (how dart:io's
// stdin read it) and through WindowsInput. Each shape of records is
// written into the console's input buffer with WriteConsoleInputW, a
// sentinel 'z' after it. Its report goes to stderr.
import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:twk_core/src/terminal/isolate_input.dart';
import 'package:twk_core/src/terminal/windows_input.dart';

final _k = DynamicLibrary.open('kernel32.dll');
final int Function() _allocConsole = _k
    .lookupFunction<Int32 Function(), int Function()>('AllocConsole');
final Pointer<Void> Function(
  Pointer<Uint16>,
  int,
  int,
  Pointer<Void>,
  int,
  int,
  Pointer<Void>,
)
_createFile = _k
    .lookupFunction<
      Pointer<Void> Function(
        Pointer<Uint16>,
        Uint32,
        Uint32,
        Pointer<Void>,
        Uint32,
        Uint32,
        Pointer<Void>,
      ),
      Pointer<Void> Function(
        Pointer<Uint16>,
        int,
        int,
        Pointer<Void>,
        int,
        int,
        Pointer<Void>,
      )
    >('CreateFileW');
final int Function(int, Pointer<Void>) _setStdHandle = _k
    .lookupFunction<
      Int32 Function(Int32, Pointer<Void>),
      int Function(int, Pointer<Void>)
    >('SetStdHandle');
final int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint32>)
_writeInput = _k
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32, Pointer<Uint32>),
      int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint32>)
    >('WriteConsoleInputW');
final int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint32>)
_readInput = _k
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32, Pointer<Uint32>),
      int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint32>)
    >('ReadConsoleInputW');
final int Function(Pointer<Void>, Pointer<Uint32>) _events = _k
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint32>),
      int Function(Pointer<Void>, Pointer<Uint32>)
    >('GetNumberOfConsoleInputEvents');
final int Function(Pointer<Void>, Pointer<Uint32>) _getMode = _k
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint32>),
      int Function(Pointer<Void>, Pointer<Uint32>)
    >('GetConsoleMode');
final int Function(Pointer<Void>, int) _setMode = _k
    .lookupFunction<
      Int32 Function(Pointer<Void>, Uint32),
      int Function(Pointer<Void>, int)
    >('SetConsoleMode');
final int Function(Pointer<Void>) _flush = _k
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'FlushConsoleInputBuffer',
    );
final int Function(
  Pointer<Void>,
  Pointer<Uint8>,
  int,
  Pointer<Uint32>,
  Pointer<Void>,
)
_readFile = _k
    .lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Pointer<Uint8>,
        Uint32,
        Pointer<Uint32>,
        Pointer<Void>,
      ),
      int Function(
        Pointer<Void>,
        Pointer<Uint8>,
        int,
        Pointer<Uint32>,
        Pointer<Void>,
      )
    >('ReadFile');
final Pointer<Void> Function(int, int) _localAlloc = _k
    .lookupFunction<
      Pointer<Void> Function(Uint32, IntPtr),
      Pointer<Void> Function(int, int)
    >('LocalAlloc');

Pointer<T> _alloc<T extends NativeType>(int bytes) =>
    _localAlloc(0x0040, bytes).cast(); // zeroed, never freed: one run

late final Pointer<Void> _console;

const _vkControl = 0x11;
const _vkSpace = 0x20;
const _leftCtrl = 0x0008;

/// One key record: (down, virtual key, scan code, char, control state).
typedef Key = (bool, int, int, int, int);

void _write(List<Key> keys) {
  final records = _alloc<Uint8>(keys.length * 20);
  for (var i = 0; i < keys.length; i++) {
    final (down, vk, scan, char, state) = keys[i];
    final at = records + i * 20;
    at.cast<Uint16>().value = 1; // KEY_EVENT
    (at + 4).cast<Int32>().value = down ? 1 : 0;
    (at + 8).cast<Uint16>().value = 1; // repeat
    (at + 10).cast<Uint16>().value = vk;
    (at + 12).cast<Uint16>().value = scan;
    (at + 14).cast<Uint16>().value = char;
    (at + 16).cast<Uint32>().value = state;
  }
  final written = _alloc<Uint32>(4);
  if (_writeInput(_console, records, keys.length, written) == 0) {
    throw StateError('WriteConsoleInputW failed');
  }
}

/// Ctrl down, Space down and up with [char], Ctrl up, then a sentinel z.
List<Key> _ctrlSpace(int char) => [
  (true, _vkControl, 0x1D, 0, _leftCtrl),
  (true, _vkSpace, 0x39, char, _leftCtrl),
  (false, _vkSpace, 0x39, char, _leftCtrl),
  (false, _vkControl, 0x1D, 0, 0),
  (true, 0x5A, 0x2C, 0x7A, 0),
  (false, 0x5A, 0x2C, 0x7A, 0),
];

String _records() {
  final n = _alloc<Uint32>(4);
  _events(_console, n);
  final count = n.value;
  if (count == 0) {
    return '(none)';
  }
  final buf = _alloc<Uint8>(count * 20);
  _readInput(_console, buf, count, n);
  final out = <String>[];
  for (var i = 0; i < n.value; i++) {
    final at = buf + i * 20;
    final type = at.cast<Uint16>().value;
    if (type != 1) {
      out.add('type$type');
      continue;
    }
    final down = (at + 4).cast<Int32>().value != 0 ? 'down' : 'up';
    final vk = (at + 10).cast<Uint16>().value.toRadixString(16);
    final char = (at + 14).cast<Uint16>().value.toRadixString(16);
    final state = (at + 16).cast<Uint32>().value.toRadixString(16);
    out.add('$down vk$vk ch$char st$state');
  }
  return out.join(', ');
}

String _readFileUntilZ() {
  final buf = _alloc<Uint8>(64);
  final n = _alloc<Uint32>(4);
  final got = <int>[];
  while (!got.contains(0x7A) && got.length < 256) {
    if (_readFile(_console, buf, 64, n, nullptr) == 0) {
      return 'ReadFile failed';
    }
    got.addAll(buf.asTypedList(n.value));
  }
  return got.map((b) => b.toRadixString(16)).join(' ');
}

Future<String> _windowsInputUntilZ() async {
  final got = <int>[];
  final done = Completer<void>();
  final input = IsolateInput(WindowsInput.open()!).stream.listen((bytes) {
    got.addAll(bytes);
    if (got.contains(0x7A) && !done.isCompleted) {
      done.complete();
    }
  });
  await done.future.timeout(const Duration(seconds: 10), onTimeout: () {});
  await input.cancel();
  return got.map((b) => b.toRadixString(16)).join(' ');
}

Future<void> main() async {
  _allocConsole();
  final name = _alloc<Uint16>(16);
  r'CONIN$'.codeUnits.asMap().forEach((i, c) => name[i] = c);
  _console = _createFile(
    name,
    0x80000000 | 0x40000000,
    3,
    nullptr,
    3,
    0,
    nullptr,
  );
  _setStdHandle(-10, _console);
  final mode = _alloc<Uint32>(4);
  _getMode(_console, mode);
  final report = StringBuffer('mode ${mode.value.toRadixString(16)}\n');
  for (final vt in [false, true]) {
    var m = mode.value | 0x0080; // extended flags
    m &= ~(0x0001 | 0x0002 | 0x0004 | 0x0040 | 0x0008 | 0x0010);
    if (vt) {
      m |= 0x0200; // ENABLE_VIRTUAL_TERMINAL_INPUT
    }
    _setMode(_console, m);
    for (final char in [0x00, 0x20]) {
      final label = 'vt $vt char ${char.toRadixString(16)}';
      _flush(_console);
      _write(_ctrlSpace(char));
      report.writeln('$label records: ${_records()}');
      _flush(_console);
      _write(_ctrlSpace(char));
      report.writeln('$label ReadFile: ${_readFileUntilZ()}');
      _flush(_console);
      _write(_ctrlSpace(char));
      report.writeln('$label WindowsInput: ${await _windowsInputUntilZ()}');
    }
  }
  stderr.write(report);
}
