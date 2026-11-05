/// Writing to the process's terminal on Linux and macOS without blocking.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:typed_data';

import '../platform/libc.dart' as c;
import 'link.dart';

/// How soon a terminal that took nothing is tried again: one that took some
/// reads, and is tried again at once.
const _retry = Duration(milliseconds: 2);

/// How long one [PosixOutput._drain] stays for a terminal that reads.
const _reading = Duration(milliseconds: 4);

/// How many passes in a row that take nothing a terminal gets before it is
/// taken to read nothing, and left to [_retry].
const _patience = 2;

/// The process's terminal, written to without blocking.
///
/// dart:io's `stdout` writes in the main isolate: on a terminal that reads
/// nothing write(2) blocks it, and it runs no timer, no key and no handler of
/// a signal until the terminal reads again. This writes what the terminal
/// takes and keeps the rest for later, through a descriptor of its own,
/// opened anew so as not to be stdout's: O_NONBLOCK belongs to what is
/// opened, and the one stdout has is the shell's too.
final class PosixOutput {
  PosixOutput._(this._fd);

  /// An output to the terminal stdout is, or null where it can't be opened
  /// again, for which `stdout` serves.
  static PosixOutput? open() {
    final name = c.ttyname(1);
    if (name == nullptr) {
      return null;
    }
    final fd = c.open(name, c.oWronly | c.oNoctty | c.oNonblock, 0);
    return fd < 0 ? null : PosixOutput._(fd);
  }

  final int _fd;

  final _pending = ListQueue<Uint8List>();

  /// How much of the first of [_pending] is written.
  var _offset = 0;

  /// How many bytes the terminal took so far.
  int get taken => _taken;
  var _taken = 0;

  /// Whether the terminal took anything in this [_drain].
  var _took = false;

  /// How many passes in a row it took nothing.
  var _refused = 0;

  final _flushes = <Completer<void>>[];
  Timer? _timer;
  Pointer<c.PollFd>? _pollFd;
  Object? _failure;
  var _closed = false;

  /// Sends [bytes], which are kept until written: nothing is to write to
  /// them before [flush] completes.
  void add(List<int> bytes) {
    // what comes after [close] (the end of a flush that waited) would
    // keep the process, trying again for a terminal that reads nothing
    if (bytes.isEmpty || _failure != null || _closed) {
      return;
    }
    _pending.add(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
    if (_timer == null) {
      _drain();
    }
  }

  /// Completes once the terminal took all there is, or with what failed;
  /// [close] completes it too.
  Future<void> flush() {
    final failure = _failure;
    if (failure != null) {
      _failure = null;
      return Future.error(failure);
    }
    if (_pending.isEmpty) {
      return Future.value();
    }
    final done = Completer<void>();
    _flushes.add(done);
    return done.future;
  }

  /// Drops what the terminal did not take, and what comes after. What waits
  /// in [flush] completes as if it was taken: the bytes are not to be held
  /// for, and an error would say nothing that closing does not.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    _offset = 0;
    _finish();
    c.close(_fd);
    final fds = _pollFd;
    if (fds != null) {
      c.free(fds.cast());
      _pollFd = null;
    }
  }

  void _drain() {
    _timer = null;
    _took = false;
    Stopwatch? waited;
    while (_pending.isNotEmpty) {
      if (_writeFirst()) {
        continue;
      }
      if (_pending.isEmpty || _refused >= _patience) {
        break;
      }
      // it may be reading: a moment for it to take more, as a timer per
      // piece of what it holds would cost a large frame milliseconds
      waited ??= Stopwatch()..start();
      if (waited.elapsed >= _reading || !_writable()) {
        break;
      }
    }
    _refused = _took ? 0 : _refused + 1;
    if (_pending.isEmpty) {
      _finish();
    } else {
      _timer = Timer(_took ? Duration.zero : _retry, _drain);
    }
  }

  /// Waits a millisecond at most for the terminal to take more.
  bool _writable() {
    final fds = _pollFd ??= c.calloc(1, sizeOf<c.PollFd>()).cast<c.PollFd>();
    fds.ref
      ..fd = _fd
      ..events = c.pollOut
      ..revents = 0;
    return c.poll(fds, 1, 1) > 0;
  }

  /// Writes the first of [_pending] as far as the terminal takes it; false
  /// when it took no more.
  bool _writeFirst() {
    final bytes = _pending.first;
    while (_offset < bytes.length) {
      final rest = _offset == 0 ? bytes : Uint8List.sublistView(bytes, _offset);
      final written = c.write(_fd, rest.address.cast(), rest.length);
      if (written < 0) {
        final errno = c.errno;
        if (errno == c.eintr) {
          continue;
        }
        if (errno != c.eagain) {
          _fail(TerminalException('the terminal failed: errno $errno'));
        }
        return false;
      }
      if (written == 0) {
        return false;
      }
      _offset += written;
      _taken += written;
      _took = true;
    }
    _pending.removeFirst();
    _offset = 0;
    return true;
  }

  void _fail(Object error) {
    _pending.clear();
    _offset = 0;
    if (_flushes.isEmpty) {
      _failure = error;
    }
    for (final done in _flushes) {
      done.completeError(error);
    }
    _flushes.clear();
  }

  void _finish() {
    for (final done in _flushes) {
      done.complete();
    }
    _flushes.clear();
  }
}
