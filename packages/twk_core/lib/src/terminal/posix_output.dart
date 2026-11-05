/// Writing to the process's terminal on Linux and macOS without blocking.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:ffi';

import '../platform/libc.dart' as c;
import 'link.dart';

const _stdoutFd = 1;

/// How long one [PosixOutput._drain] stays for a terminal that reads.
const _reading = Duration(milliseconds: 4);

/// How much is copied out for one write.
const int _chunk = 1 << 16;

/// How soon a terminal that took nothing is tried again: one that took some
/// reads, and is tried again at once.
const _retry = Duration(milliseconds: 2);

/// The process's stdout, written to without blocking.
///
/// dart:io's `stdout` writes in the main isolate: on a terminal that reads
/// nothing write(2) blocks it, and it runs no timer, no key and no handler of
/// a signal until the terminal reads again. This writes what the terminal
/// takes and keeps the rest for later. The descriptor is shared with
/// the shell, which is not to find it non-blocking, so it is so only around
/// the writes.
final class PosixOutput {
  final _pending = ListQueue<List<int>>();

  /// How much of the first of [_pending] is written.
  var _offset = 0;

  /// Whether the terminal took anything in this [_drain].
  var _took = false;

  final _flushes = <Completer<void>>[];
  Timer? _timer;
  Pointer<Uint8>? _buffer;
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
    _pending.add(bytes);
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

  /// Drops what the terminal did not take, and what comes after, ending
  /// what waits for it.
  void close() {
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    _offset = 0;
    _finish();
    final buffer = _buffer;
    if (buffer != null) {
      c.free(buffer.cast());
      _buffer = null;
    }
    final fds = _pollFd;
    if (fds != null) {
      c.free(fds.cast());
      _pollFd = null;
    }
  }

  void _drain() {
    _timer = null;
    _took = false;
    final waited = Stopwatch()..start();
    while (true) {
      _writeWhatFits();
      if (_pending.isEmpty || !_took) {
        break;
      }
      // it reads: a moment for it to take more, as a timer per piece of
      // what it holds would cost a large frame milliseconds
      if (waited.elapsed >= _reading || !_writable()) {
        break;
      }
    }
    if (_pending.isEmpty) {
      _finish();
    } else {
      _timer = Timer(_took ? Duration.zero : _retry, _drain);
    }
  }

  void _writeWhatFits() {
    final flags = c.fcntl(_stdoutFd, c.fGetfl, 0);
    if (flags >= 0) {
      c.fcntl(_stdoutFd, c.fSetfl, flags | c.oNonblock);
    }
    try {
      while (_pending.isNotEmpty) {
        if (!_writeFirst()) {
          break;
        }
      }
    } finally {
      if (flags >= 0) {
        c.fcntl(_stdoutFd, c.fSetfl, flags);
      }
    }
  }

  /// Waits a millisecond at most for the terminal to take more.
  bool _writable() {
    final fds = _pollFd ??= c.calloc(1, sizeOf<c.PollFd>()).cast<c.PollFd>();
    fds.ref
      ..fd = _stdoutFd
      ..events = c.pollOut
      ..revents = 0;
    return c.poll(fds, 1, 1) > 0;
  }

  /// Writes the first of [_pending] as far as the terminal takes it; false
  /// when it took no more.
  bool _writeFirst() {
    final bytes = _pending.first;
    final buffer = _buffer ??= c.calloc(1, _chunk).cast<Uint8>();
    while (_offset < bytes.length) {
      final end = _offset + _chunk < bytes.length
          ? _offset + _chunk
          : bytes.length;
      final n = end - _offset;
      buffer.asTypedList(n).setRange(0, n, bytes, _offset);
      final written = c.write(_stdoutFd, buffer.cast(), n);
      if (written < 0) {
        final errno = c.errno;
        if (errno == c.eintr) {
          continue;
        }
        if (errno == c.eagain) {
          return false;
        }
        _fail(TerminalException('the terminal failed: errno $errno'));
        return false;
      }
      _offset += written;
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
