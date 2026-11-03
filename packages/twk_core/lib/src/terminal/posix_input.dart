/// The input of the process's own terminal on Linux and macOS, fd 0, read
/// by an isolate of its own through libc ([PosixInput], for an
/// [IsolateInput]).
library;

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:typed_data';

import '../platform/libc.dart' as c;
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
  PosixInput._();

  /// The reader of fd 0, or null where it can't be one: not Linux or
  /// macOS.
  static PosixInput? open() =>
      Platform.isLinux || Platform.isMacOS ? PosixInput._() : null;

  @override
  (int, int, int) openWake() {
    final stop = c.calloc(1, sizeOf<Int32>()).cast<Int32>();
    final pair = c.calloc(2, sizeOf<Int>()).cast<Int>();
    try {
      if (stop == nullptr || pair == nullptr || c.pipe(pair) != 0) {
        c.free(stop.cast());
        throw const TerminalException('no pipe to read the terminal with');
      }
      return (pair[0], pair[1], stop.address);
    } finally {
      c.free(pair.cast());
    }
  }

  @override
  void signal((int, int, int) wake) {
    // the flag for the reads that don't wait, the pipe for a wait
    Pointer<Int32>.fromAddress(wake.$3).value = 1;
    final byte = c.calloc(1, 1).cast<Uint8>()..value = 1;
    try {
      c.write(wake.$2, byte.cast(), 1);
    } finally {
      c.free(byte.cast());
    }
  }

  @override
  void closeWake((int, int, int) wake) {
    c.close(wake.$1);
    c.close(wake.$2);
    c.free(Pointer.fromAddress(wake.$3));
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

/// Reads fd 0, sending what it reads to [args].$2, then [inputEnded] once
/// fd 0 ends, or what failed, until it is told to stop: the flag at
/// [args].$1.$3, looked at before each read, and the wake pipe
/// [args].$1.$1, waited on beside fd 0 when it has nothing.
void _read(((int, int, int), SendPort) args) {
  final ((wake, _, flag), port) = args;
  final stop = Pointer<Int32>.fromAddress(flag);
  final fds = c.calloc(2, sizeOf<c.PollFd>()).cast<c.PollFd>();
  final buf = c.calloc(1, _chunk).cast<Uint8>();
  final there = c.calloc(1, sizeOf<Int>()).cast<Int>();
  try {
    while (true) {
      // told to stop: fd 0 is not read again, whatever it has
      if (stop.value != 0) {
        return;
      }
      // what fd 0 has, read without waiting
      there.value = 0;
      if (c.ioctl(0, c.fionread, there.cast()) == 0 && there.value > 0) {
        final n = there.value < _chunk ? there.value : _chunk;
        final got = c.read(0, buf.cast(), n);
        if (got > 0) {
          port.send(Uint8List.fromList(buf.asTypedList(got)));
          continue;
        }
      }
      fds[0]
        ..fd = 0
        ..events = c.pollIn
        ..revents = 0;
      fds[1]
        ..fd = wake
        ..events = c.pollIn
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
      if (revents & c.pollIn != 0) {
        final got = c.read(0, buf.cast(), _chunk);
        if (got > 0) {
          port.send(Uint8List.fromList(buf.asTypedList(got)));
        } else if (got == 0) {
          port.send(inputEnded);
          return;
        } else if (c.errno != c.eintr && c.errno != c.eagain) {
          port.send('reading the terminal failed (errno ${c.errno})');
          return;
        }
      } else if (revents & (c.pollHup | c.pollErr | c.pollNval) != 0) {
        port.send(inputEnded);
        return;
      }
    }
  } finally {
    c.free(fds.cast());
    c.free(buf.cast());
    c.free(there.cast());
  }
}
