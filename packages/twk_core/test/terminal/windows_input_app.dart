// The console's reader (WindowsInput), in a program of its own on Windows
// whose standard input is the console's input buffer (CONIN$), keys
// written into it with WriteConsoleInputW: a key read, the buffer left
// open and unread once the reader is cancelled, a second reader reading
// keys (one a surrogate pair), a reader paused while it runs leaving what
// comes after, and a program started after reading a line. It ends on its
// own; its report goes to stderr. windows_input_test.dart runs it.
//
//   dart run test/terminal/windows_input_app.dart
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:twk_core/src/terminal/isolate_input.dart';
import 'package:twk_core/src/terminal/windows_input.dart';

final _k = DynamicLibrary.open('kernel32.dll');
final int Function() _allocConsole = _k
    .lookupFunction<Int32 Function(), int Function()>(
      'AllocConsole',
    );
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
final Pointer<Void> Function(int, int) _localAlloc = _k
    .lookupFunction<
      Pointer<Void> Function(Uint32, IntPtr),
      Pointer<Void> Function(int, int)
    >('LocalAlloc');

Pointer<T> _alloc<T extends NativeType>(int bytes) =>
    _localAlloc(0x0040, bytes).cast(); // zeroed, never freed: one run

late final Pointer<Void> _console;

/// Writes [text] into the console's input buffer as keys typed: a key
/// down and up for each UTF-16 unit, as a paste is.
void type(String text) {
  final units = text.codeUnits;
  final records = _alloc<Uint8>(units.length * 2 * 20);
  for (var i = 0; i < units.length; i++) {
    for (final down in [1, 0]) {
      final at = records + (i * 2 + 1 - down) * 20;
      at.cast<Uint16>().value = 1; // KEY_EVENT
      (at + 4).cast<Int32>().value = down;
      (at + 8).cast<Uint16>().value = 1; // repeat
      (at + 14).cast<Uint16>().value = units[i];
    }
  }
  final written = _alloc<Uint32>(4);
  if (_writeInput(_console, records, units.length * 2, written) == 0 ||
      written.value != units.length * 2) {
    throw StateError('WriteConsoleInputW failed');
  }
}

/// The records in the console's input buffer, unread.
int unread() {
  final n = _alloc<Uint32>(4);
  return _events(_console, n) == 0 ? -1 : n.value;
}

/// Whether the console's handle is open.
bool isOpen() => _getMode(_console, _alloc<Uint32>(4)) != 0;

/// Reads with a reader of its own until what it read decodes to [want].
Future<String> readUntil(String want) async {
  final got = <int>[];
  final done = Completer<String>();
  final input = IsolateInput(WindowsInput.open()!).stream.listen((bytes) {
    got.addAll(bytes);
    final text = utf8.decode(got, allowMalformed: true);
    if (text.length >= want.length && !done.isCompleted) {
      done.complete(text);
    }
  });
  final text = await done.future;
  await input.cancel();
  return text;
}

Future<void> main() async {
  // a console of its own where it has none (that fails where it has one)
  _allocConsole();
  final name = _alloc<Uint16>(16);
  r'CONIN$'.codeUnits.asMap().forEach((i, c) => name[i] = c);
  // inheritable, so a program started after has it as its standard input
  final attributes = _alloc<Uint8>(24);
  attributes.cast<Uint32>().value = 24;
  (attributes + 16).cast<Int32>().value = 1;
  _console = _createFile(
    name,
    0x80000000 | 0x40000000, // GENERIC_READ | GENERIC_WRITE
    3, // FILE_SHARE_READ | FILE_SHARE_WRITE
    attributes.cast(),
    3, // OPEN_EXISTING
    0,
    nullptr,
  );
  if (_console.address == -1 || _console == nullptr) {
    stderr.writeln('no console');
    exitCode = 2;
    return;
  }
  _setStdHandle(-10, _console); // STD_INPUT_HANDLE

  type('a');
  final first = await readUntil('a');

  // cancelled: nothing more read, the handle open
  type('b');
  final leftAfterCancel = unread();
  final open = isOpen();

  type('日😀');
  final second = await readUntil('b日😀');

  // paused while it runs: what comes after is left
  type('x');
  final paused = Completer<void>();
  late final StreamSubscription<List<int>> input;
  input = IsolateInput(WindowsInput.open()!).stream.listen((_) {
    input.pause();
    if (!paused.isCompleted) {
      paused.complete();
    }
  });
  await paused.future;
  type('c');
  await input.cancel();
  final leftAfterPause = unread();

  // a program after them reads the line: the c left, then hi
  type('hi\r');
  // !x! expanded when echo runs (/v:on), not with the line, before set
  final child = await Process.start('cmd', [
    '/v:on',
    '/c',
    'set /p x=& echo child !x!',
  ], mode: ProcessStartMode.inheritStdio);
  final code = await child.exitCode;

  stderr.writeln(
    // the code points, as stderr's encoding is the system's code page
    'first $first, left $leftAfterCancel open $open, second '
    '${second.runes.map((r) => r.toRadixString(16)).join(' ')}, '
    'paused left $leftAfterPause, child exit $code',
  );
}
