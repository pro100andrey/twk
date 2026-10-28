// Tests that end every way a test ends while what they started runs,
// whose ends process_test.dart checks from outside: run by `dart test` in
// a process of its own. Each writes what it started to the file
// TWK_PROCESS_LOG names, a line `<pid> <start time>` each; once all have
// ended, it writes the file TWK_PROCESS_DONE names.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart';

final _log = File(Platform.environment['TWK_PROCESS_LOG']!);

/// Writes [pid] with the time it started to the log.
void started(int pid) {
  final stat = File('/proc/$pid/stat').readAsStringSync();
  final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
  _log.writeAsStringSync('$pid ${fields[19]}\n', mode: FileMode.append);
}

/// The first line [process] writes, as a number.
Future<int> firstNumber(Process process) async => int.parse(
  await process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .first,
);

void main() {
  tearDownAll(
    () => File(Platform.environment['TWK_PROCESS_DONE']!).writeAsStringSync(''),
  );

  test('returns, a process left running', () async {
    started((await startProcess('sleep', ['300'])).pid);
  });

  test('fails, a process left running', () async {
    started((await startProcess('sleep', ['300'])).pid);
    fail('the test failed');
  });

  test('throws, a process left running', () async {
    started((await startProcess('sleep', ['300'])).pid);
    throw StateError('the test threw');
  });

  test(
    'times out, a process left running',
    () async {
      started((await startProcess('sleep', ['300'])).pid);
      await Completer<void>().future;
    },
    timeout: const Timeout(Duration(seconds: 2)),
  );

  test('fails, a shell and what it started running', () async {
    final shell = await startProcess('sh', [
      '-c',
      r'sleep 300 & echo $!; wait',
    ], group: true);
    started(shell.pid);
    started(await firstNumber(shell));
    fail('the test failed');
  });

  test('returns, the shell ended and what it started running', () async {
    final res = await runProcess('sh', [
      '-c',
      r'sleep 300 >/dev/null 2>&1 & echo $!',
    ], group: true);
    expect(res.exitCode, 0);
    started(int.parse('${res.stdout}'.trim()));
  });

  test(
    'times out in runProcess, a shell and what it started running',
    () async {
      final pids = File('${_log.path}.run');
      unawaited(
        runProcess('sh', [
          '-c',
          r'sleep 300 & echo $$ $! > "$0"; wait',
          pids.path,
        ], group: true),
      );
      // the shell's pid and its sleep's, as it writes them
      await waitUntil(
        () => pids.existsSync() && pids.readAsStringSync().endsWith('\n'),
        'the shell to write its pids',
      );
      pids.readAsStringSync().trim().split(' ').map(int.parse).forEach(started);
      await Completer<void>().future;
    },
    timeout: const Timeout(Duration(seconds: 3)),
  );
}
