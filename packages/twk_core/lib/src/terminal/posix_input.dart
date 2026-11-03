/// The input of the process's own terminal on Linux and macOS, fd 0, read
/// by an isolate of its own through libc ([PosixInput], for an
/// [IsolateInput]).
library;

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:typed_data';

import 'isolate_input.dart';
import 'link.dart' show TerminalException;

/// fd 0 read with poll beside a wake pipe (its read and write ends): what
/// an [IsolateInput] reads on Linux and macOS.
final class PosixInput implements InputDevice<(int, int)> {
  PosixInput._(this._c);

  /// The reader of fd 0, or null where it can't be one: not Linux or
  /// macOS, or libc's poll, read, pipe, write and close not to be found.
  static PosixInput? open() {
    if (!(Platform.isLinux || Platform.isMacOS)) {
      return null;
    }
    final c = _Libc.of();
    return c == null ? null : PosixInput._(c);
  }

  final _Libc _c;

  @override
  (int, int) openWake() {
    final pair = _c.alloc(2 * sizeOf<Int32>()).cast<Int32>();
    try {
      if (_c.pipe(pair) != 0) {
        throw const TerminalException('no pipe to read the terminal with');
      }
      return (pair[0], pair[1]);
    } finally {
      _c.free(pair.cast());
    }
  }

  @override
  void signal((int, int) wake) {
    final byte = _c.alloc(1).cast<Uint8>()..value = 1;
    try {
      _c.write(wake.$2, byte.cast(), 1);
    } finally {
      _c.free(byte.cast());
    }
  }

  @override
  void closeWake((int, int) wake) {
    _c
      ..close(wake.$1)
      ..close(wake.$2);
  }

  @override
  Future<void> spawn((int, int) wake, SendPort port) => Isolate.spawn(
    _read,
    (wake, port),
    onExit: port,
    onError: port,
    debugName: 'terminal input',
  );
}

// the most bytes one read takes
const _chunk = 4096;

const _pollIn = 0x1;
const _pollErr = 0x8;
const _pollHup = 0x10;
const _pollNval = 0x20;
const _eintr = 4;
final _eagain = Platform.isMacOS ? 35 : 11;

/// Reads fd 0 until the wake pipe [args].$1 has a byte, sending what it
/// reads to [args].$2, then [inputEnded] once fd 0 ends, or what failed.
void _read(((int, int), SendPort) args) {
  final ((wake, _), port) = args;
  final c = _Libc.of()!;
  final fds = c.alloc(2 * sizeOf<_PollFd>()).cast<_PollFd>();
  final buf = c.alloc(_chunk).cast<Uint8>();
  try {
    while (true) {
      fds[0]
        ..fd = 0
        ..events = _pollIn
        ..revents = 0;
      fds[1]
        ..fd = wake
        ..events = _pollIn
        ..revents = 0;
      if (c.poll(fds, 2, -1) < 0) {
        // a signal (SIGWINCH): poll is not restarted. Its errno can't be
        // trusted after a call that is not a leaf one, and nothing else
        // makes poll fail here
        continue;
      }
      // told to stop: fd 0 is not read again, whatever it has
      if (fds[1].revents != 0) {
        return;
      }
      final revents = fds[0].revents;
      if (revents & _pollIn != 0) {
        final got = c.read(0, buf.cast(), _chunk);
        if (got > 0) {
          port.send(Uint8List.fromList(buf.asTypedList(got)));
        } else if (got == 0) {
          port.send(inputEnded);
          return;
        } else if (c.errno != _eintr && c.errno != _eagain) {
          port.send('reading the terminal failed (errno ${c.errno})');
          return;
        }
      } else if (revents & (_pollHup | _pollErr | _pollNval) != 0) {
        port.send(inputEnded);
        return;
      }
    }
  } finally {
    c
      ..free(fds.cast())
      ..free(buf.cast());
  }
}

/// `struct pollfd`, as Linux and macOS lay it out.
final class _PollFd extends Struct {
  @Int32()
  external int fd;

  @Int16()
  external int events;

  @Int16()
  external int revents;
}

typedef _ReadN = IntPtr Function(Int32, Pointer<Void>, IntPtr);
typedef _ReadD = int Function(int, Pointer<Void>, int);

/// What of libc the reader calls, looked up in the process (each isolate
/// looks it up for itself).
final class _Libc {
  _Libc._(DynamicLibrary c, String errno)
    : poll = c
          .lookupFunction<
            Int32 Function(Pointer<_PollFd>, UnsignedLong, Int32),
            int Function(Pointer<_PollFd>, int, int)
          >('poll'),
      // read only what poll found, so it doesn't block: a leaf call, after
      // which errno is the one it set
      read = c.lookupFunction<_ReadN, _ReadD>('read', isLeaf: true),
      write = c.lookupFunction<_ReadN, _ReadD>('write'),
      pipe = c
          .lookupFunction<
            Int32 Function(Pointer<Int32>),
            int Function(Pointer<Int32>)
          >('pipe'),
      close = c.lookupFunction<Int32 Function(Int32), int Function(int)>(
        'close',
      ),
      _malloc = c
          .lookupFunction<
            Pointer<Void> Function(IntPtr),
            Pointer<Void> Function(int)
          >('malloc'),
      _free = c
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('free'),
      _errno = c
          .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
            errno,
            isLeaf: true,
          );

  static _Libc? _cached;

  /// libc, or null where one of its functions can't be found.
  static _Libc? of() {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }
    final c = DynamicLibrary.process();
    final errno = Platform.isMacOS ? '__error' : '__errno_location';
    for (final symbol in [
      'poll',
      'read',
      'write',
      'pipe',
      'close',
      'malloc',
      'free',
      errno,
    ]) {
      if (!c.providesSymbol(symbol)) {
        return null;
      }
    }
    return _cached = _Libc._(c, errno);
  }

  final int Function(Pointer<_PollFd>, int, int) poll;
  final _ReadD read;
  final _ReadD write;
  final int Function(Pointer<Int32>) pipe;
  final int Function(int) close;
  final Pointer<Void> Function(int) _malloc;
  final void Function(Pointer<Void>) _free;
  final Pointer<Int32> Function() _errno;

  /// errno, read right after the leaf call that set it ([read]).
  int get errno => _errno().value;

  /// [bytes] of memory from malloc, for [free].
  Pointer<Void> alloc(int bytes) => _malloc(bytes);

  /// Frees what [alloc] gave.
  void free(Pointer<Void> p) => _free(p);
}
