/// The input of the process's own terminal read by an isolate of its own
/// rather than through dart:io's `stdin` ([IsolateInput]), over what each
/// platform reads it with ([InputDevice]: `PosixInput` on Linux and macOS,
/// `WindowsInput` on Windows).
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'link.dart' show TerminalException;

/// How a platform reads its terminal's input in an isolate: a wake object
/// made and signalled in the isolate that listens, and the loop the
/// reading isolate runs, which waits on the input and the wake object at
/// once and stops as soon as the wake object is signalled.
///
/// The loop ([spawn]) is given the wake object and a port. It sends
/// each chunk read as a [Uint8List], [inputEnded] once the input ends,
/// or a [String] saying what failed, and returns after [inputEnded], a
/// failure, or the wake object signalled; it reads nothing once the wake
/// object is signalled, which it looks at first.
///
/// [W] is the wake object, which is sent to the reading isolate: of ints
/// (file descriptors, a handle's address).
abstract interface class InputDevice<W extends Object> {
  /// A new wake object, unsignalled; a [TerminalException] where none can
  /// be made.
  W openWake();

  /// Signals [wake], at once.
  void signal(W wake);

  /// Frees [wake], once the reader waiting on it has stopped.
  void closeWake(W wake);

  /// Spawns the reading isolate on [wake], its loop sending to [port];
  /// its exit (null) and an error it throws (a list of the error and its
  /// stack) go to [port] too.
  Future<void> spawn(W wake, SendPort port);
}

/// What a reader sends once the input ended (the terminal hung up).
const inputEnded = 0;

/// What an [InputDevice] reads, as a stream that reads it only while it is
/// listened to and not paused.
///
/// dart:io's `stdin` is listened to once in a process: cancelled, it
/// closes the input (fd 0, the console's handle), after which `stdin`
/// itself throws and a program started with
/// `ProcessStartMode.inheritStdio` reads nothing; paused, it keeps the
/// process from ending. This reads in an isolate that waits on the input
/// beside a wake object and reads only what is there: paused or
/// cancelled, it is told at once and stops, having read nothing more. The
/// input stays as it was, for another program or a later terminal, and
/// once it stops nothing of it keeps the process alive. Each one is a
/// reader of its own.
final class IsolateInput<W extends Object> {
  /// A reader of what the device reads.
  IsolateInput(this._device);

  final InputDevice<W> _device;

  late final _controller = StreamController<List<int>>(
    onListen: _start,
    onPause: _stop,
    onResume: _start,
    onCancel: _cancel,
  );

  /// The bytes read; listened to once. It ends when the input does (the
  /// terminal hung up), with a [TerminalException] where reading failed.
  /// Paused, it reads nothing more from then on: the reader is told at
  /// once, before `pause` returns, so a program given the terminal right
  /// after gets what is typed for it.
  Stream<List<int>> get stream => _controller.stream;

  // the reader that runs or is to run, while listened to and not paused
  _Reader<W>? _reader;
  // the last reader's having stopped, which the next one waits for: one
  // isolate reads the input at a time
  var _stopped = Future<void>.value();
  var _cancelled = false;

  void _start() {
    if (_cancelled || _reader != null) {
      return;
    }
    try {
      _reader = _Reader(_device, _controller)..spawnAfter(_stopped);
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

/// One run of the reading isolate: its wake object made at once, the
/// isolate spawned once the one before it stopped, and [stop] it.
final class _Reader<W extends Object> {
  _Reader(this._device, this._out) : _wake = _device.openWake() {
    // what it read, then that it ended, on one port: the bytes it sent
    // before it stopped come before the news that it did
    _port.listen((message) {
      switch (message) {
        case final Uint8List bytes:
          if (!_out.isClosed) {
            _out.add(bytes);
          }
        case inputEnded:
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

  final InputDevice<W> _device;
  final StreamController<List<int>> _out;
  final W _wake;
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
          await _device.spawn(_wake, _port.sendPort);
        } on Object catch (e) {
          _fail('no isolate to read the terminal with: $e');
          _exited.complete();
        }
      }),
    );
  }

  /// Tells the isolate to stop, at once: it reads nothing after the wake
  /// object is signalled, which it looks at first, and one not spawned yet
  /// never is. Completes once it has stopped, its wake object and port
  /// closed.
  Future<void> stop() {
    _woken = true;
    _device.signal(_wake);
    return _exited.future.then((_) {
      _device.closeWake(_wake);
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
