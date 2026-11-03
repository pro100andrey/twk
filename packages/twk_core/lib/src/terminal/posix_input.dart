/// The input of the process's own terminal on Linux and macOS, read from
/// fd 0 by an isolate of its own through libc rather than through
/// dart:io's `stdin`: [PosixInput].
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:typed_data';

import 'link.dart' show TerminalException;

/// What fd 0 reads, as a stream that reads it only while it is listened to
/// and not paused.
///
/// dart:io's `stdin` is listened to once in a process: cancelled, it
/// closes fd 0, after which `stdin` itself throws and a program started
/// with `ProcessStartMode.inheritStdio` reads nothing ("Bad file
/// descriptor"); paused, it keeps the process from ending. This reads
/// fd 0 in an isolate that polls it beside a wake pipe and reads only what
/// poll says is there: paused or cancelled, it is told through the pipe
/// and stops at once, having read nothing more. fd 0 stays as it was, for
/// another program or a later terminal, and once it stops nothing of it
/// keeps the process alive. Each one is a reader of its own.
final class PosixInput {
  PosixInput._();

  /// A reader of fd 0, or null where it can't be one: not Linux or macOS,
  /// or libc's poll, read, pipe, write and close not to be found.
  static PosixInput? open() {
    if (!(Platform.isLinux || Platform.isMacOS)) {
      return null;
    }
    return _Libc.of() == null ? null : PosixInput._();
  }

  late final _controller = StreamController<List<int>>(
    onListen: _start,
    onPause: _stop,
    onResume: _start,
    onCancel: _cancel,
  );

  /// The bytes read; listened to once. It ends when fd 0 does (the
  /// terminal hung up), with a [TerminalException] where reading failed.
  /// Paused, it reads nothing more from then on: the reader is told at
  /// once, before `pause` returns, so a program given the terminal right
  /// after gets what is typed for it.
  Stream<List<int>> get stream => _controller.stream;

  // the reader that runs or is to run, while listened to and not paused
  _Reader? _reader;
  // the last reader's having stopped, which the next one waits for: one
  // isolate reads fd 0 at a time
  var _stopped = Future<void>.value();
  var _cancelled = false;

  void _start() {
    if (_cancelled || _reader != null) {
      return;
    }
    try {
      _reader = _Reader(_controller)..spawnAfter(_stopped);
    } on TerminalException catch (e) {
      _controller.addError(e);
      unawaited(_controller.close());
    }
  }

  void _stop() {
    final reader = _reader;
    if (reader != null) {
      _reader = null;
      _stopped = reader.stop();
    }
  }

  Future<void> _cancel() async {
    _cancelled = true;
    _stop();
    await _stopped;
    await _controller.close();
  }
}

/// One run of the reading isolate: its wake pipe made at once, the
/// isolate spawned once the one before it stopped, and [stop] it.
final class _Reader {
  _Reader(this._out) : _c = _Libc.of()! {
    final pair = _c.alloc(2 * sizeOf<Int32>()).cast<Int32>();
    try {
      if (_c.pipe(pair) != 0) {
        throw const TerminalException('no pipe to read the terminal with');
      }
      _wakeRead = pair[0];
      _wakeWrite = pair[1];
    } finally {
      _c.free(pair.cast());
    }
    // what it read, then that it ended, on one port: the bytes it sent
    // before it stopped come before the news that it did
    _port.listen((message) {
      switch (message) {
        case final Uint8List bytes:
          if (!_out.isClosed) {
            _out.add(bytes);
          }
        case _ended:
          unawaited(_out.close());
        case final String failure:
          _fail(failure);
        case [final Object? error, _]:
          // it threw (onError sends the error and its stack as strings)
          _fail('reading the terminal failed: $error');
        case null:
          // its exit (onExit sends null)
          _exited.complete();
      }
    });
  }

  final StreamController<List<int>> _out;
  final _Libc _c;
  late final int _wakeWrite;
  late final int _wakeRead;
  final _port = ReceivePort('terminal input');
  final _exited = Completer<void>();
  var _woken = false;

  /// Spawns the isolate once [before] completed, unless [stop] came first.
  void spawnAfter(Future<void> before) {
    unawaited(
      before.then((_) async {
        if (_woken) {
          _exited.complete();
          return;
        }
        try {
          await Isolate.spawn(
            _read,
            (_wakeRead, _port.sendPort),
            onExit: _port.sendPort,
            onError: _port.sendPort,
            debugName: 'terminal input',
          );
        } on Object catch (e) {
          _fail('no isolate to read the terminal with: $e');
          _exited.complete();
        }
      }),
    );
  }

  /// Tells the isolate to stop, at once: it reads nothing after the byte
  /// on the wake pipe, which it looks at first, and one not spawned yet
  /// never is. Completes once it has stopped, its pipe and port closed.
  Future<void> stop() {
    _woken = true;
    final byte = _c.alloc(1).cast<Uint8>()..value = 1;
    try {
      _c.write(_wakeWrite, byte.cast(), 1);
    } finally {
      _c.free(byte.cast());
    }
    return _exited.future.then((_) {
      _c
        ..close(_wakeRead)
        ..close(_wakeWrite);
      _port.close();
    });
  }

  void _fail(String failure) {
    if (!_out.isClosed) {
      _out.addError(TerminalException(failure));
      unawaited(_out.close());
    }
  }
}

// what the isolate sends when fd 0 ended
const _ended = 0;

// the most bytes one read takes
const _chunk = 4096;

const _pollIn = 0x1;
const _pollErr = 0x8;
const _pollHup = 0x10;
const _pollNval = 0x20;
const _eintr = 4;
final _eagain = Platform.isMacOS ? 35 : 11;

/// Reads fd 0 until the wake pipe [args].$1 has a byte, sending what it
/// reads to [args].$2, then [_ended] once fd 0 ends, or what failed.
void _read((int, SendPort) args) {
  final (wake, port) = args;
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
          port.send(_ended);
          return;
        } else if (c.errno != _eintr && c.errno != _eagain) {
          port.send('reading the terminal failed (errno ${c.errno})');
          return;
        }
      } else if (revents & (_pollHup | _pollErr | _pollNval) != 0) {
        port.send(_ended);
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
