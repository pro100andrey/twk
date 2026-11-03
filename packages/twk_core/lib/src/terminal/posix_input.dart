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
  Stream<List<int>> get stream => _controller.stream;

  // what runs or is to run, one thing at a time: a start waits for the
  // reader it replaces to have stopped
  var _work = Future<void>.value();
  _Reader? _reader;
  var _cancelled = false;

  void _start() {
    _work = _work.then((_) async {
      if (_cancelled ||
          _controller.isPaused ||
          _controller.isClosed ||
          _reader != null) {
        return;
      }
      _reader = await _Reader.start(_controller);
    });
  }

  void _stop() {
    _work = _work.then((_) => _stopReader());
  }

  Future<void> _cancel() {
    _cancelled = true;
    return _work = _work.then((_) async {
      await _stopReader();
      await _controller.close();
    });
  }

  Future<void> _stopReader() async {
    final reader = _reader;
    _reader = null;
    await reader?.stop();
  }
}

/// One run of the reading isolate, from its start to its [stop].
final class _Reader {
  _Reader._(this._c, this._wakeWrite, this._wakeRead, this._port);

  static Future<_Reader> start(StreamController<List<int>> out) async {
    final c = _Libc.of()!;
    final pair = c.alloc(2 * sizeOf<Int32>()).cast<Int32>();
    final int wakeRead;
    final int wakeWrite;
    try {
      if (c.pipe(pair) != 0) {
        throw const TerminalException('no pipe to read the terminal with');
      }
      wakeRead = pair[0];
      wakeWrite = pair[1];
    } finally {
      c.free(pair.cast());
    }
    // what it read, then that it ended, on one port: the bytes it sent
    // before it stopped come before the news that it did
    final port = ReceivePort('terminal input');
    final reader = _Reader._(c, wakeWrite, wakeRead, port);
    port.listen((message) {
      switch (message) {
        case final Uint8List bytes:
          if (!out.isClosed) {
            out.add(bytes);
          }
        case _ended:
          unawaited(out.close());
        case final String failure:
          if (!out.isClosed) {
            out.addError(TerminalException(failure));
            unawaited(out.close());
          }
        case null:
          // its exit (onExit sends null)
          reader._exited.complete();
      }
    });
    try {
      await Isolate.spawn(
        _read,
        (wakeRead, port.sendPort),
        onExit: port.sendPort,
        onError: port.sendPort,
        debugName: 'terminal input',
      );
    } on Object {
      reader._close();
      rethrow;
    }
    return reader;
  }

  final _Libc _c;
  final int _wakeWrite;
  final int _wakeRead;
  final ReceivePort _port;
  final _exited = Completer<void>();

  /// Tells the isolate to stop and waits until it has: it reads nothing
  /// after the byte on the wake pipe, which it looks at first.
  Future<void> stop() async {
    final byte = _c.alloc(1).cast<Uint8>()..value = 1;
    try {
      _c.write(_wakeWrite, byte.cast(), 1);
    } finally {
      _c.free(byte.cast());
    }
    await _exited.future;
    _close();
  }

  void _close() {
    _c
      ..close(_wakeRead)
      ..close(_wakeWrite);
    _port.close();
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
