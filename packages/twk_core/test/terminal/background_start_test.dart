// An app started in the background (`app &`) in a pseudo-terminal
// (tool/pty_run.py), running suspend_app.dart under an interactive bash:
// it stops, as a job does that wants the terminal, before it changes a mode
// or writes a query to the shell's terminal, and opens once fg gives it the
// terminal (twk-bugs.md item 17).
@Tags(['process'])
@TestOn('linux || mac-os')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show compiledProgram, runProcess;

import '../support/environment.dart';

void main() {
  late String app;
  setUpAll(
    () async => app = await compiledProgram(
      'test/terminal/suspend_app.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    ),
  );

  test('an app started with & does nothing to the terminal until fg gives it '
      'the terminal, then opens', () async {
    final dir = await Directory.systemTemp.createTemp('twk_background_start');
    addTearDown(() => dir.delete(recursive: true));
    final out = '${dir.path}/out.bin';
    // The shell waits (in its own time, ps polling, not the test's) until
    // the job is stopped, says its state, then fg after a line is typed.
    final line =
        '"${Platform.resolvedExecutable}" "$app" 2>&3 & '
        r'job=$!; n=0; '
        r'while [ $n -lt 400 ]; do '
        r's=$(ps -o stat= -p $job); '
        r'case "$s" in T*) break;; esac; '
        r'n=$((n+1)); sleep 0.05; done; '
        r'echo "job state: $s"; read x; fg';
    final res = await runProcess(
      'python3',
      [
        '../../tool/pty_run.py',
        '--timeout',
        '120',
        '--input',
        'none',
        '--out',
        out,
        '--when',
        'job state: ',
        '--when',
        'suspend app 100x30',
        '--input',
        r'#1:\r,#2:q',
        '--',
        '/bin/sh',
        '-c',
        r'exec 3>&2 2>&0 "$@"',
        'sh',
        'bash',
        '--norc',
        '--noprofile',
        '-i',
        '-c',
        line,
      ],
      environment: childEnvironment(),
      includeParentEnvironment: false,
      group: true,
    );
    final said = '${res.stdout}${res.stderr}';
    expect(res.exitCode, 0, reason: said);
    final bytes = String.fromCharCodes(await File(out).readAsBytes());
    final state = bytes.indexOf('job state: ');
    expect(state, isNonNegative, reason: said);
    expect(bytes.substring(0, state), isNot(contains('\x1b[?1049h')));
    expect(bytes.substring(0, state), isNot(contains('\x1b[?2026\$p')));
    expect(bytes.substring(state), contains('job state: T'));
    expect(bytes.substring(state), contains('\x1b[?1049h'));
    expect(said, contains('handed over 0 times'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('an app stopped for want of the terminal ends on SIGTERM, as `timeout` '
      'sends it with SIGCONT, having touched nothing', () async {
    final dir = await Directory.systemTemp.createTemp('twk_background_term');
    addTearDown(() => dir.delete(recursive: true));
    final out = '${dir.path}/out.bin';
    final line =
        '"${Platform.resolvedExecutable}" "$app" 2>&3 & '
        r'job=$!; n=0; '
        r'while [ $n -lt 400 ]; do '
        r's=$(ps -o stat= -p $job); '
        r'case "$s" in T*) break;; esac; '
        r'n=$((n+1)); sleep 0.05; done; '
        r'echo "job state: $s"; kill -TERM $job; kill -CONT $job; '
        // a zombie passes `kill -0`, so ps says whether it is gone
        r'n=0; while [ $n -lt 60 ]; do '
        r's=$(ps -o stat= -p $job); case "$s" in Z*|"") break;; esac; '
        r'n=$((n+1)); sleep 0.05; done; '
        r'case "$s" in Z*|"") echo "job gone";; '
        r'*) echo "job still there: $s"; kill -KILL $job;; esac';
    final res = await runProcess(
      'python3',
      [
        '../../tool/pty_run.py',
        '--timeout',
        '60',
        '--input',
        'none',
        '--out',
        out,
        '--',
        '/bin/sh',
        '-c',
        r'exec 3>&2 2>&0 "$@"',
        'sh',
        'bash',
        '--norc',
        '--noprofile',
        '-i',
        '-c',
        line,
      ],
      environment: childEnvironment(),
      includeParentEnvironment: false,
      group: true,
    );
    final said = '${res.stdout}${res.stderr}';
    final bytes = String.fromCharCodes(await File(out).readAsBytes());
    expect(bytes, contains('job state: T'), reason: said);
    expect(bytes, contains('job gone'), reason: '$bytes$said');
    expect(bytes, isNot(contains('\x1b[?1049h')));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
