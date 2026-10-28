/// A process a test starts, ended with the test however the test ends:
/// [startProcess], [runProcess]. Every signal they send goes through
/// [guardedSignal], which refuses whatever the test did not start.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:test/test.dart';

import 'wait.dart';

// Examples can assume:
// import 'dart:io';
// import 'package:test/test.dart';

/// [Process.start] of [executable] with [arguments], in [workingDirectory]
/// with [environment], ended when the test ends, however it ends (it
/// returns, fails, throws or times out): a tear-down registered as it
/// starts kills it (`SIGKILL`) if it still runs then and waits, with a
/// bound, for its exit, a [TestFailure] naming it otherwise.
///
/// [group] is for a process that starts processes of its own (a shell, a
/// `dart` that runs an app, a compiler, `twk run`): on Linux it is started
/// in a new session, and so a process group, of its own (by `setsid`),
/// whose id is its pid. Its children are in that group unless they leave
/// it, and the tear-down kills the group, and with it what it started,
/// even when the process itself has ended and left them running. The
/// group is the process's own only once the process is seen leading it,
/// before it runs [executable] (which waits for that, on a line of its
/// stdin it does not see): a process that is not is killed, and the start
/// is a [TestFailure]. Elsewhere [group] does nothing, and the tear-down
/// kills the process alone. A process in a session of its own has no
/// controlling terminal.
///
/// It finds nothing to kill by name, environment or a listing of the
/// processes: it kills the process it started and the group made for it,
/// and nothing else ([guardedSignal]).
///
/// Its waits are real timers: called in a `FakeClock`'s zone it would wait
/// for that clock, so it is called outside it, as a test's body is.
///
/// A shell, and the `sleep` it starts, gone when the test ends:
///
/// ```dart
/// test('a shell', () async {
///   final shell = await startProcess('sh', [
///     '-c',
///     'sleep 300 & wait',
///   ], group: true);
///   expect(shell.pid, isPositive);
/// });
/// ```
///
/// See also:
///
///  * [runProcess], for a process whose output is all that is wanted.
Future<Process> startProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment = true,
  bool group = false,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final inGroup = group && Platform.isLinux;
  final process = await Process.start(
    inGroup ? 'setsid' : executable,
    [
      if (inGroup) ...['sh', '-c', _released, executable],
      ...arguments,
    ],
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
  );
  final what = '$executable (pid ${process.pid})';
  final started = _Started(process, what);
  addTearDown(() => started.end(timeout));
  if (inGroup) {
    await started.lead(timeout);
  }
  return started.process;
}

/// [Process.run] of [executable] with [arguments], as [startProcess]
/// starts it: ended when the test ends if it still runs then, [group]
/// killed then too. What it wrote is decoded by [stdoutEncoding] and
/// [stderrEncoding], or left as bytes where one is null; its stdin is
/// closed.
///
/// A test that times out while it runs ends it:
///
/// ```dart
/// test('the date', () async {
///   final res = await runProcess('date', []);
///   expect(res.exitCode, 0);
/// });
/// ```
Future<ProcessResult> runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment = true,
  bool group = false,
  Encoding? stdoutEncoding = systemEncoding,
  Encoding? stderrEncoding = systemEncoding,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final process = await startProcess(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
    group: group,
    timeout: timeout,
  );
  unawaited(process.stdin.close());
  Future<Object> read(Stream<List<int>> stream, Encoding? encoding) async {
    final bytes = await stream.fold(
      BytesBuilder(copy: false),
      (b, chunk) => b..add(chunk),
    );
    return encoding == null
        ? bytes.takeBytes()
        : encoding.decode(bytes.takeBytes());
  }

  final (out, err, code) = await (
    read(process.stdout, stdoutEncoding),
    read(process.stderr, stderrEncoding),
    process.exitCode,
  ).wait;
  return ProcessResult(process.pid, code, out, err);
}

/// Sends [signal] to [target] by [send], once it is one a test may
/// signal, and throws a [StateError] without sending anything otherwise.
/// Every signal [startProcess] sends goes through it.
///
/// A test may signal:
///
///  * the process it started, [started], which is more than 1;
///  * the group made for it, as `-group`: [group] is that process's own
///    (equal to [started]), more than 1, and not the group of the process
///    the tests run in, [runnerGroup].
///
/// Nothing else: not 0 or -1 (which `kill(2)` takes as the caller's group
/// and every process the user owns), not 1, not another pid, not another
/// group, and never the runner's own.
@visibleForTesting
void guardedSignal(
  int target,
  ProcessSignal signal, {
  required int started,
  required int? group,
  required int runnerGroup,
  required void Function(int target, ProcessSignal signal) send,
}) {
  if (started <= 1) {
    throw StateError(
      'refused to signal $target: the process started has '
      'pid $started',
    );
  }
  if (target == started) {
    send(target, signal);
    return;
  }
  if (target >= 0) {
    throw StateError(
      'refused to signal $target: not the process started, '
      '$started',
    );
  }
  if (group == null) {
    throw StateError(
      'refused to signal $target: no group was made for '
      'process $started',
    );
  }
  if (group <= 1 || group != started) {
    throw StateError(
      'refused to signal $target: group $group is not the '
      'own of process $started',
    );
  }
  if (group == runnerGroup || runnerGroup <= 1) {
    throw StateError(
      'refused to signal $target: group $group is the '
      "runner's ($runnerGroup)",
    );
  }
  if (target != -group) {
    throw StateError(
      'refused to signal $target: not -$group, the group '
      'of process $started',
    );
  }
  send(target, signal);
}

/// The process group the tests run in, from `/proc/self/stat`; read once.
@visibleForTesting
int get runnerGroup => _runnerGroup ??= _stat('self')!.group;
int? _runnerGroup;

/// Waits for a line on stdin, then runs what follows as `sh -c` runs it:
/// the process, by then in a session of its own, waits to be seen leading
/// its group before it runs the program.
const _released = r'read -r _ && exec "$0" "$@"';

/// What `/proc/<pid>/stat` says of a process: its group, session and the
/// time it started (which tells a pid used again from the one it was).
typedef _ProcStat = ({String state, int group, int session, int startTime});

_ProcStat? _stat(String pid) {
  final String text;
  try {
    text = File('/proc/$pid/stat').readAsStringSync();
  } on FileSystemException {
    return null;
  }
  // the name, in parentheses, may hold anything: the fields follow the
  // last of them, the state first (field 3)
  final fields = text.substring(text.lastIndexOf(')') + 2).split(' ');
  return (
    state: fields[0],
    group: int.parse(fields[2]),
    session: int.parse(fields[3]),
    startTime: int.parse(fields[19]),
  );
}

/// A process [startProcess] started, and the group made for it once it is
/// seen leading it.
final class _Started {
  _Started(this.process, this.what) {
    unawaited(process.exitCode.then((_) => _ended = true));
  }

  final Process process;
  final String what;
  var _ended = false;

  /// The group made for [process], once seen: its pid.
  int? _group;

  /// When [process] started, as `/proc/<pid>/stat` says, seen with
  /// [_group].
  int? _startTime;

  /// Waits for [process] to lead a session and group of its own, and
  /// then lets it run its program.
  Future<void> lead(Duration timeout) async {
    final pid = process.pid;
    final runner = runnerGroup;
    _ProcStat? seen;
    await waitUntil(
      () {
        seen = _ended ? null : _stat('$pid');
        return _ended ||
            seen == null ||
            (seen!.group == pid && seen!.session == pid);
      },
      '$what to lead a group of its own',
      timeout: timeout,
    );
    final stat = seen;
    // the process blocks on stdin until released: ended, it ended before
    if (_ended || stat == null || stat.group != pid) {
      fail('$what ended before leading a group of its own');
    }
    if (pid <= 1 || stat.group == runner) {
      fail("$what leads the runner's group ($runner)");
    }
    _group = pid;
    _startTime = stat.startTime;
    process.stdin.add(const [0x0a]);
  }

  /// Kills [process] and the group made for it, if any, and waits for
  /// the process to end.
  Future<void> end(Duration timeout) async {
    final group = _group;
    if (group != null && _groupIsOurs(group)) {
      _signal(-group);
    }
    if (!_ended) {
      _signal(process.pid);
    }
    await waitFor(
      process.exitCode,
      '$what to end once killed',
      timeout: timeout,
    );
  }

  /// Whether the number [group] still names the group made for
  /// [process]: a process of that pid is the one seen leading it (alive,
  /// or not yet reaped), or there is none, and the number is either free
  /// or still the group's (the kernel gives no process a pid that a group
  /// of processes still has as its id). A process of that pid that
  /// started at another time took the number once it was free, so the
  /// group was gone.
  bool _groupIsOurs(int group) {
    final stat = _stat('$group');
    return stat == null || stat.startTime == _startTime;
  }

  void _signal(int target) => guardedSignal(
    target,
    ProcessSignal.sigkill,
    started: process.pid,
    group: _group,
    runnerGroup: runnerGroup,
    send: (target, signal) =>
        target > 0 ? process.kill(signal) : Process.killPid(target, signal),
  );
}
