/// A program run in a pseudo-terminal, through dart:ffi on Linux and macOS.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'libc.dart' as c;

// Examples can assume:
// import 'dart:io';

/// The most one message of [Pty.output] carries.
const _chunk = 65536;

/// How many messages may wait for the listener before the pseudo-terminal
/// is read no further (and the program blocks in its writes).
const _inFlight = 4;

// What the main isolate tells the I/O isolate, a byte each through a pipe.
const _ack = 0x61; // a message of output was taken
const _want = 0x77; // say when the master takes writes again
const _quit = 0x71; // stop reading: the terminal is closed

// What the I/O isolate tells the main one, besides output and the end.
const _writable = 'writable';
const _hangup = 'hangup';

/// The program's end, as the I/O isolate saw it.
final class _Exited {
  const _Exited(this.code);

  /// See [Pty.exitCode].
  final int? code;
}

/// A program run in a pseudo-terminal: what it writes comes out of
/// [output], what [write] is given it reads from its terminal, and
/// [resize] sets the size it reads (TIOCGWINSZ) and sends it SIGWINCH.
///
/// The program leads a session of its own with the pseudo-terminal as its
/// controlling terminal and its process group in the foreground: `tty`
/// names [ttyName], Ctrl+C written to it is SIGINT to that group, a shell
/// runs jobs and stops them with Ctrl+Z. It starts with every signal at
/// its default and none blocked, IUTF8 set on the terminal.
///
/// The child is made with posix_spawn (pidfd_spawn where glibc has it),
/// never with a fork of the VM: a new session (POSIX_SPAWN_SETSID), the
/// slave opened as descriptor 0 by its leader, which makes it the
/// controlling terminal, then duplicated to 1 and 2, every other
/// descriptor closed. The master is read by an isolate of its own polling
/// it, which also waits for the program's end.
///
/// `ls` run to its end, its output printed:
///
/// ```dart
/// final pty = Pty.start('ls', const ['--color=always']);
/// await pty.output.forEach(stdout.add);
/// print('exit code: ${await pty.exitCode}');
/// ```
///
/// See also:
///
///  * `TerminalSession`, a program in a [Pty] with the emulator it writes
///    to, for a `TerminalView`.
final class Pty {
  Pty._(
    this.pid,
    this.ttyName,
    this._master,
    this._pidfd,
    this._wakeIn,
    this._wakeOut,
    this._width,
    this._height,
  ) : _scratch = c.calloc(1, _chunk + 16).cast();

  /// Runs [executable] with [arguments] in a new pseudo-terminal of
  /// [width] by [height] cells.
  ///
  /// The program's environment is this process's (unless
  /// [includeParentEnvironment] is false) with TERM set to
  /// `xterm-256color`, the dialect the emulator speaks, and [environment]
  /// over both; an [executable] without a slash is looked for in its PATH.
  /// Throws a [ProcessException] when the program can't be started, an
  /// [ArgumentError] for an argument, a variable or a directory with a NUL
  /// character in it, an [UnsupportedError] off Linux and macOS.
  factory Pty.start(
    String executable,
    List<String> arguments, {
    int width = 80,
    int height = 24,
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) {
    if (!Platform.isLinux && !Platform.isMacOS) {
      throw UnsupportedError('Pty runs on Linux and macOS only');
    }
    _checkSize(width, height);
    final env = {
      if (includeParentEnvironment) ...Platform.environment,
      'TERM': 'xterm-256color',
      ...?environment,
    };
    final path = _resolve(executable, arguments, env['PATH']);
    final scope = c.NativeScope();
    final attr = scope.alloc<Void>(1024);
    final actions = scope.alloc<Void>(1024);
    var attrMade = false;
    var actionsMade = false;
    var master = -1;
    var slave = -1;
    final wake = scope.alloc<Int>(2 * sizeOf<Int>())
      ..[0] = -1
      ..[1] = -1;
    Never fail(String call, int code) => throw ProcessException(
      executable,
      arguments,
      c.describe(call, code),
      code,
    );
    void check(String call, int rc) {
      if (rc != 0) {
        fail(call, rc);
      }
    }

    try {
      if (c.pipe(wake) != 0) {
        fail('pipe', c.errno);
      }
      c.setCloexec(wake[0]);
      c.setCloexec(wake[1]);
      c.setNonblocking(wake[1]);
      master = c.posixOpenpt(c.oRdwr | c.oNoctty);
      if (master < 0) {
        fail('posix_openpt', c.errno);
      }
      c.setCloexec(master);
      if (c.grantpt(master) != 0) {
        fail('grantpt', c.errno);
      }
      if (c.unlockpt(master) != 0) {
        fail('unlockpt', c.errno);
      }
      final name = c.ptsName(master, scope);
      final slavePath = scope.string(name);
      // Opened here too, to set it up before the program runs; O_NOCTTY,
      // so it never becomes this process's controlling terminal.
      slave = c.open(slavePath, c.oRdwr | c.oNoctty | c.oCloexec, 0);
      if (slave < 0) {
        fail('open $name', c.errno);
      }
      if (!_setSize(slave, width, height, scope.alloc(8))) {
        fail('ioctl TIOCSWINSZ', c.errno);
      }
      // c_iflag's low 32 bits come first on both (a 64-bit field on macOS,
      // little-endian on x86-64 and arm64).
      final termios = scope.alloc<Uint32>(256);
      if (c.tcgetattr(slave, termios.cast()) == 0) {
        termios.value |= c.iutf8;
        c.tcsetattr(slave, c.tcsanow, termios.cast());
      }

      check('posix_spawnattr_init', c.spawnattrInit(attr));
      attrMade = true;
      final none = scope.alloc<Void>(256);
      final all = scope.alloc<Void>(256);
      c.sigemptyset(none);
      c.sigfillset(all);
      check('posix_spawnattr_setsigmask', c.spawnattrSetsigmask(attr, none));
      // What the VM ignores (SIGPIPE) would stay ignored across exec.
      check(
        'posix_spawnattr_setsigdefault',
        c.spawnattrSetsigdefault(attr, all),
      );
      check(
        'posix_spawnattr_setflags (POSIX_SPAWN_SETSID needs glibc 2.26)',
        c.spawnattrSetflags(
          attr,
          c.spawnSetsid |
              c.spawnSetSigMask |
              c.spawnSetSigDef |
              c.spawnCloexecDefault,
        ),
      );
      check('posix_spawn_file_actions_init', c.actionsInit(actions));
      actionsMade = true;
      if (workingDirectory != null) {
        final addchdir =
            c.actionsAddchdir ??
            (throw UnsupportedError(
              'posix_spawn_file_actions_addchdir_np is missing',
            ));
        check(
          'posix_spawn_file_actions_addchdir_np',
          addchdir(actions, scope.string(workingDirectory)),
        );
      }
      // Opened by the new session's leader without O_NOCTTY: it becomes
      // the controlling terminal, the leader's process group the
      // foreground one.
      check(
        'posix_spawn_file_actions_addopen',
        c.actionsAddopen(actions, 0, slavePath, c.oRdwr, 0),
      );
      check(
        'posix_spawn_file_actions_adddup2',
        c.actionsAdddup2(actions, 0, 1),
      );
      check(
        'posix_spawn_file_actions_adddup2',
        c.actionsAdddup2(actions, 0, 2),
      );
      if (c.actionsAddclosefrom case final closefrom?) {
        check(
          'posix_spawn_file_actions_addclosefrom_np',
          closefrom(actions, 3),
        );
      }
      final pid = scope.alloc<Int>(sizeOf<Int>());
      final pidfd = scope.alloc<Int>(sizeOf<Int>());
      check(
        'posix_spawn $path',
        c.spawn(
          pid,
          pidfd,
          scope.string(path),
          actions,
          attr,
          scope.strings([executable, ...arguments]),
          scope.strings([
            for (final MapEntry(:key, :value) in env.entries) '$key=$value',
          ]),
        ),
      );
      c.setNonblocking(master);
      final pty = Pty._(
        pid.value,
        name,
        master,
        pidfd.value,
        wake[0],
        wake[1],
        width,
        height,
      );
      unawaited(
        Isolate.spawn(
          _ioLoop,
          (master, wake[0], pid.value, pidfd.value, pty._port.sendPort),
          onExit: pty._port.sendPort,
          onError: pty._port.sendPort,
          debugName: 'pty ${pid.value}',
        ).then<void>((_) {}, onError: pty._ioFailed),
      );
      return pty;
    } catch (_) {
      for (final fd in [master, wake[0], wake[1]]) {
        if (fd >= 0) {
          c.close(fd);
        }
      }
      rethrow;
    } finally {
      if (slave >= 0) {
        c.close(slave);
      }
      if (attrMade) {
        c.spawnattrDestroy(attr);
      }
      if (actionsMade) {
        c.actionsDestroy(actions);
      }
      scope.release();
    }
  }

  /// The program's process id, or -1 when it ended before its id was read.
  final int pid;

  /// The slave's path, e.g. `/dev/pts/3`: what `tty` prints in it.
  final String ttyName;

  int _master;

  /// A pidfd for the program, or -1: closed here (then -1), used by the I/O
  /// isolate.
  int _pidfd;
  final int _wakeIn;
  final int _wakeOut;

  /// [_chunk] bytes for writes, then the wake byte and a winsize.
  final Pointer<Uint8> _scratch;

  late final _port = RawReceivePort(_onMessage, 'pty');
  late final _output = StreamController<Uint8List>(
    onListen: _payAcks,
    onResume: _payAcks,
    onCancel: _payAcks,
  );
  final _exit = Completer<int?>();
  final _pending = ListQueue<Uint8List>();
  var _pendingAt = 0;
  var _awaiting = false;
  var _acksOwed = 0;
  var _closed = false;
  var _hungUp = false;
  var _ended = false;
  int _width;
  int _height;

  /// What the program writes to its terminal, in pieces of up to 64 KiB.
  /// Single-subscription; while it isn't listened to or is paused, the
  /// terminal is read no further and the program blocks in its writes. It
  /// ends when every descriptor of the slave was closed (the program and
  /// what it left running ended, or closed them), or [close] was called.
  ///
  /// Ended so, the terminal is hung up once the program ended, not
  /// before: a program closes its terminal before its exit (cat at the end
  /// of its input does), and the hang-up's SIGHUP would kill it in
  /// between, its exit code lost.
  Stream<Uint8List> get output => _output.stream;

  /// The program's exit code once it ended, the signal's number negated
  /// when one killed it (as `dart:io`'s `Process.exitCode`).
  ///
  /// The VM waits for any child while a `Process` it started runs, so it
  /// may take the program's end first; Linux 6.15 and later still tell it
  /// through the pidfd made with the program, elsewhere it is null then.
  Future<int?> get exitCode => _exit.future;

  /// How many columns the terminal has, as [resize] set it last.
  int get width => _width;

  /// How many rows the terminal has, as [resize] set it last.
  int get height => _height;

  /// Hands [bytes] to the program as typed input. What the terminal doesn't
  /// take at once waits, in order, for the program to read; dropped once
  /// the terminal hung up or was closed.
  void write(List<int> bytes) {
    if (_closed || _hungUp || bytes.isEmpty) {
      return;
    }
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    if (_pending.isEmpty) {
      final done = _writeSome(data, 0);
      if (done == data.length) {
        return;
      }
      _pending.add(Uint8List.fromList(Uint8List.sublistView(data, done)));
      _pendingAt = 0;
    } else {
      _pending.add(Uint8List.fromList(data));
    }
    _awaitWritable();
  }

  /// Sets the terminal's size; the program's foreground process group gets
  /// SIGWINCH when it changed.
  void resize(int width, int height) {
    _checkSize(width, height);
    if (width == _width && height == _height) {
      return;
    }
    _width = width;
    _height = height;
    if (_master >= 0) {
      _setSize(_master, width, height, (_scratch + _chunk + 8).cast());
    }
  }

  /// Sends [signal] to the program; false once it ended or when it
  /// couldn't be sent.
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      !_exit.isCompleted && signalProcess(pid, _pidfd, signal);

  /// Hangs the terminal up, as closing its window does: [output] ends,
  /// input still waiting is dropped, and the program (with its foreground
  /// job) gets SIGHUP as the master closes, also when it closed the
  /// terminal itself and runs on.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _pending.clear();
    if (_hungUp) {
      // the I/O isolate reads the master no more: it is closed here
      _closeMaster();
    } else {
      _wake(_quit);
    }
  }

  void _onMessage(Object? message) {
    switch (message) {
      case final TransferableTypedData data:
        _output.add(data.materialize().asUint8List());
        if (_output.isPaused) {
          _acksOwed++;
        } else {
          _wake(_ack);
        }
      case _writable:
        _flush();
      case _hangup:
        // on close, or every descriptor of the slave closed: the master is
        // closed then, or once the program ended (_end)
        _hangUp(closeMaster: _closed);
      case _Exited(:final code):
        _exit.complete(code);
      case [final Object error, final Object? stack]:
        _output.addError(RemoteError('$error', '$stack'));
      case null:
        _end();
    }
  }

  void _ioFailed(Object error, StackTrace stack) {
    _output.addError(error, stack);
    _end();
  }

  /// The I/O isolate ended: after the hang-up and the program's end, or
  /// when it failed (the program is then killed).
  void _end() {
    if (_ended) {
      return;
    }
    _ended = true;
    _port.close();
    c.close(_wakeIn);
    c.close(_wakeOut);
    if (!_exit.isCompleted) {
      signalProcess(pid, _pidfd, ProcessSignal.sigkill);
    }
    if (_pidfd >= 0) {
      c.close(_pidfd);
      _pidfd = -1;
    }
    _hangUp();
    c.free(_scratch.cast());
    if (!_exit.isCompleted && pid <= 0) {
      _exit.complete(null);
    } else if (!_exit.isCompleted) {
      final status = c.calloc(1, sizeOf<Int>()).cast<Int>();
      Timer.periodic(const Duration(milliseconds: 10), (timer) {
        final r = c.waitpid(pid, status, c.wnohang);
        if (r != 0) {
          timer.cancel();
          _exit.complete(r == pid ? _exitCodeOf(status.value) : null);
          c.free(status.cast());
        }
      });
    }
  }

  /// The output ends, the input is dropped; with [closeMaster] the
  /// terminal is hung up.
  void _hangUp({bool closeMaster = true}) {
    if (closeMaster) {
      _closeMaster();
    }
    if (_hungUp) {
      return;
    }
    _hungUp = true;
    _pending.clear();
    unawaited(_output.close());
  }

  void _closeMaster() {
    if (_master >= 0) {
      c.close(_master);
      _master = -1;
    }
  }

  void _payAcks() {
    for (; _acksOwed > 0; _acksOwed--) {
      _wake(_ack);
    }
  }

  void _wake(int byte) {
    if (_ended) {
      return;
    }
    final p = (_scratch + _chunk)..value = byte;
    c.write(_wakeOut, p.cast(), 1);
  }

  void _awaitWritable() {
    if (!_awaiting) {
      _awaiting = true;
      _wake(_want);
    }
  }

  void _flush() {
    _awaiting = false;
    while (_pending.isNotEmpty && !_hungUp) {
      final head = _pending.first;
      final at = _writeSome(head, _pendingAt);
      if (at < head.length) {
        _pendingAt = at;
        _awaitWritable();
        return;
      }
      _pending.removeFirst();
      _pendingAt = 0;
    }
  }

  /// Writes [data] from [start] on until the master takes no more; where
  /// it got to (the end when the write failed for good).
  int _writeSome(Uint8List data, int start) {
    var at = start;
    while (at < data.length) {
      final n = math.min(data.length - at, _chunk);
      _scratch.asTypedList(n).setRange(0, n, data, at);
      final wrote = c.write(_master, _scratch.cast(), n);
      if (wrote > 0) {
        at += wrote;
        continue;
      }
      final error = c.errno;
      if (wrote < 0 && error == c.eintr) {
        continue;
      }
      return wrote < 0 && error != c.eagain ? data.length : at;
    }
    return at;
  }
}

void _checkSize(int width, int height) {
  RangeError.checkValueInInterval(width, 1, 0xffff, 'width');
  RangeError.checkValueInInterval(height, 1, 0xffff, 'height');
}

/// TIOCSWINSZ on [fd], through the 8 bytes at [winsize].
bool _setSize(int fd, int width, int height, Pointer<Uint16> winsize) {
  winsize
    ..[0] = height
    ..[1] = width
    ..[2] = 0
    ..[3] = 0;
  return c.ioctl(fd, c.tiocswinsz, winsize.cast()) == 0;
}

/// [executable] itself when it has a slash, else the first executable file
/// of that name in [path], as execvp looks.
String _resolve(String executable, List<String> arguments, String? path) {
  if (executable.contains('/')) {
    return executable;
  }
  if (executable.isNotEmpty) {
    for (final dir in (path ?? '/usr/bin:/bin').split(':')) {
      final candidate = '${dir.isEmpty ? '.' : dir}/$executable';
      final stat = FileStat.statSync(candidate);
      if (stat.type == FileSystemEntityType.file && stat.mode & 0x49 != 0) {
        return candidate;
      }
    }
  }
  throw ProcessException(executable, arguments, 'not found in PATH', 2);
}

/// A wait status as `dart:io` gives exit codes.
/// Sends [signal] to the program [pid] and [pidfd] name: through the pidfd
/// where there is one, which reaches that process and no other, else by
/// [pid] only when it is positive — kill(2) with 0 signals the caller's
/// process group and with -1 every process the user owns. False when it
/// wasn't sent. [throughPidfd], [toPidfd] and [toPid] stand in for the
/// system in tests.
bool signalProcess(
  int pid,
  int pidfd,
  ProcessSignal signal, {
  bool? throughPidfd,
  int Function(int pidfd, int signal) toPidfd = c.pidfdSendSignal,
  bool Function(int pid, ProcessSignal signal) toPid = Process.killPid,
}) {
  if (pidfd >= 0 && (throughPidfd ?? c.pidfdSignals)) {
    return toPidfd(pidfd, signal.signalNumber) == 0;
  }
  return pid > 0 && toPid(pid, signal);
}

int _exitCodeOf(int status) =>
    status & 0x7f == 0 ? status >> 8 & 0xff : -(status & 0x7f);

/// The I/O isolate: reads the master while the listener keeps up, says
/// when it takes writes again, waits for the program's end (on a pidfd
/// where there is one, else every 20 ms). It polls with a timeout either
/// way, so the VM can stop it when it exits.
void _ioLoop((int, int, int, int, SendPort) args) {
  final (master, wake, pid, pidfd, port) = args;
  final scope = c.NativeScope();
  final fds = scope.alloc<c.PollFd>(3 * sizeOf<c.PollFd>());
  final buf = scope.alloc<Uint8>(_chunk);
  final status = scope.alloc<Int>(sizeOf<Int>());
  var reading = true;
  var reaped = false;
  var wantOut = false;
  var inFlight = 0;
  // Running since waitpid found the program waited for by somebody else:
  // the kernel keeps its end for the pidfd a few milliseconds later (or
  // never, before Linux 6.15).
  Stopwatch? taken;

  void ended(int? status) {
    reaped = true;
    port.send(_Exited(status == null ? null : _exitCodeOf(status)));
  }

  void hangUp() {
    reading = false;
    port.send(_hangup);
  }

  void watch(int at, int fd, int events) => fds[at]
    ..fd = fd
    ..events = events
    ..revents = 0;

  try {
    while (reading || !reaped) {
      var n = 0;
      final masterAt = reading && (inFlight < _inFlight || wantOut) ? n++ : -1;
      if (masterAt >= 0) {
        watch(
          masterAt,
          master,
          (inFlight < _inFlight ? c.pollIn : 0) | (wantOut ? c.pollOut : 0),
        );
      }
      final wakeAt = n++;
      watch(wakeAt, wake, c.pollIn);
      final pidAt = !reaped && pidfd >= 0 && taken == null ? n++ : -1;
      if (pidAt >= 0) {
        watch(pidAt, pidfd, c.pollIn);
      }
      final timeout = reaped
          ? 1000
          : taken != null
          ? 5
          : pidfd < 0
          ? 20
          : 1000;
      if (c.poll(fds, n, timeout) < 0) {
        continue;
      }
      if (fds[wakeAt].revents != 0) {
        final got = c.read(wake, buf.cast(), 64);
        for (var i = 0; i < got; i++) {
          switch (buf[i]) {
            case _ack:
              inFlight--;
            case _want:
              wantOut = true;
            case _quit when reading:
              hangUp();
          }
        }
      }
      if (masterAt >= 0 && reading) {
        final revents = fds[masterAt].revents;
        final broken = revents & (c.pollHup | c.pollErr | c.pollNval) != 0;
        if (wantOut && (revents & c.pollOut != 0 || broken)) {
          wantOut = false;
          port.send(_writable);
        }
        if (inFlight < _inFlight && (revents & c.pollIn != 0 || broken)) {
          var got = 0;
          var eof = false;
          while (got < _chunk) {
            final r = c.read(master, (buf + got).cast(), _chunk - got);
            if (r > 0) {
              got += r;
              continue;
            }
            final error = r < 0 ? c.errno : 0;
            if (error == c.eintr) {
              continue;
            }
            // 0 or EIO: every descriptor of the slave was closed.
            eof = error != c.eagain;
            break;
          }
          if (got > 0) {
            port.send(TransferableTypedData.fromList([buf.asTypedList(got)]));
            inFlight++;
          }
          if (eof) {
            hangUp();
          }
        }
      }
      if (!reaped && taken == null && (pidAt < 0 || fds[pidAt].revents != 0)) {
        if (pid <= 0) {
          // No id to wait for (the program ended before it was read):
          // waitpid would reap any child; the pidfd tells its end.
          taken = Stopwatch()..start();
        } else {
          final r = c.waitpid(pid, status, c.wnohang);
          if (r == pid) {
            ended(status.value);
          } else if (r < 0 && c.errno == c.echild) {
            taken = Stopwatch()..start();
          }
        }
      }
      if (!reaped && taken != null) {
        final how = pidfd >= 0 ? c.pidfdExitStatus(pidfd) : null;
        if (how != null || pidfd < 0 || taken.elapsedMilliseconds > 500) {
          ended(how);
        }
      }
    }
  } finally {
    scope.release();
  }
}
