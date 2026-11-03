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

/// fd 0 read beside a wake pipe and a stop flag (the pipe's read and write
/// ends and the flag's address): what an [IsolateInput] reads on Linux and
/// macOS.
///
/// What fd 0 has (FIONREAD) is read at once, as dart:io does, and poll
/// waits only when it has nothing: a wait between reads that each find
/// data cost a wake-up each, 8 MB through a pseudo-terminal taking 85 ms
/// where dart:io took 77 and this takes 67. The flag, set before the pipe
/// is written, is looked at before each read.
final class PosixInput implements InputDevice<(int, int, int)> {
  PosixInput._(this._c);

  /// The reader of fd 0, or null where it can't be one: not Linux or
  /// macOS, or libc's poll, ioctl, read, pipe, write and close not to be
  /// found.
  static PosixInput? open() {
    if (!(Platform.isLinux || Platform.isMacOS)) {
      return null;
    }
    final c = _Libc.of();
    return c == null ? null : PosixInput._(c);
  }

  final _Libc _c;

  @override
  (int, int, int) openWake() {
    final pair = _c.alloc(2 * sizeOf<Int32>()).cast<Int32>();
    try {
      if (_c.pipe(pair) != 0) {
        throw const TerminalException('no pipe to read the terminal with');
      }
      final stop = _c.alloc(sizeOf<Int32>()).cast<Int32>()..value = 0;
      return (pair[0], pair[1], stop.address);
    } finally {
      _c.free(pair.cast());
    }
  }

  @override
  void signal((int, int, int) wake) {
    // the flag for the reads that don't wait, the pipe for a wait
    Pointer<Int32>.fromAddress(wake.$3).value = 1;
    final byte = _c.alloc(1).cast<Uint8>()..value = 1;
    try {
      _c.write(wake.$2, byte.cast(), 1);
    } finally {
      _c.free(byte.cast());
    }
  }

  @override
  void closeWake((int, int, int) wake) {
    _c
      ..close(wake.$1)
      ..close(wake.$2)
      ..free(Pointer.fromAddress(wake.$3));
  }

  @override
  Future<void> spawn((int, int, int) wake, SendPort port) => Isolate.spawn(
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
final _fionread = Platform.isMacOS ? 0x4004667F : 0x541B;

/// Reads fd 0 until the stop flag at [args].$1.$3 is set (and the wake
/// pipe [args].$1.$1 has a byte), sending what it reads to [args].$2, then
/// [inputEnded] once fd 0 ends, or what failed.
void _read(((int, int, int), SendPort) args) {
  final ((wake, _, flag), port) = args;
  final stop = Pointer<Int32>.fromAddress(flag);
  final c = _Libc.of()!;
  final fds = c.alloc(2 * sizeOf<_PollFd>()).cast<_PollFd>();
  final buf = c.alloc(_chunk).cast<Uint8>();
  final there = c.alloc(sizeOf<Int32>()).cast<Int32>();
  try {
    while (true) {
      // told to stop: fd 0 is not read again, whatever it has
      if (stop.value != 0) {
        return;
      }
      // what fd 0 has, read without waiting
      there.value = 0;
      if (c.ioctl(0, _fionread, there) == 0 && there.value > 0) {
        final n = there.value < _chunk ? there.value : _chunk;
        final got = c.read(0, buf.cast(), n);
        if (got > 0) {
          port.send(Uint8List.fromList(buf.asTypedList(got)));
          continue;
        }
      }
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
      ..free(buf.cast())
      ..free(there.cast());
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
    : ioctl = c
          .lookupFunction<
            Int32 Function(Int32, UnsignedLong, VarArgs<(Pointer<Int32>,)>),
            int Function(int, int, Pointer<Int32>)
          >('ioctl', isLeaf: true),
      poll = c
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
      'ioctl',
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

  /// ioctl with an int's address, FIONREAD: it doesn't block, so a leaf
  /// call.
  final int Function(int, int, Pointer<Int32>) ioctl;
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
