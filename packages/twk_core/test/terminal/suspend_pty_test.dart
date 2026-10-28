// The process's own terminal (Terminal.open on stdin and stdout) in a
// pseudo-terminal (tool/pty_run.py), running suspend_app.dart: stopped
// for the shell it was started from by Ctrl+Z and taken back, resized,
// and ended by SIGTERM, the terminal put back each time.
@TestOn('linux || mac-os')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show compiledProgram, runProcess;

import '../support/environment.dart';

/// tool/pty_run.py with [options] running [command]: its exit status, and
/// what it said (its checks, and the command's stderr).
Future<(int, String)> ptyRun(List<String> options, List<String> command) async {
  final res = await runProcess(
    'python3',
    [
      '../../tool/pty_run.py',
      // what a loaded machine may take to start the app, run and end it
      '--timeout',
      '120',
      '--input',
      'none',
      ...options,
      '--',
      ...command,
    ],
    environment: childEnvironment(),
    includeParentEnvironment: false,
    group: true,
  );
  return (res.exitCode, '${res.stdout}${res.stderr}');
}

/// suspend_app.dart, compiled once.
late String _app;

/// What the shell runs: the app, then what it says while it has the
/// terminal, a line it reads (typed once the terminal was resized while
/// the app is stopped), and fg.
String get _shellLine =>
    '"${Platform.resolvedExecutable}" "$_app"; '
    'echo shell has it; read x; fg';

/// What the app draws first, at the size [ptyRun] starts it at.
const _drawn = 'suspend app 100x30';

void main() {
  setUpAll(
    () async => _app = await compiledProgram(
      'test/terminal/suspend_app.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    ),
  );

  test(
    'Ctrl+Z stops the app for the shell, which has the terminal as it was '
    'before the app took it; resized meanwhile, fg gives it back to the '
    'app, at the new size',
    () async {
      // an interactive shell with job control, which gives the terminal
      // back to the app with fg
      final (code, said) = await ptyRun(
        [
          // Ctrl+Z once the app has drawn; resized when the shell has the
          // terminal, before the line that lets it go on to fg; q once the
          // app drew again after it
          '--when',
          _drawn,
          '--when',
          'shell has it',
          '--when',
          'last: fg',
          '--input',
          r'#1:\x1a,#2:\r,#3:q',
          '--suspended',
          'shell has it',
          '--resize',
          '#2:90x25',
        ],
        [
          'bash',
          '--norc',
          '--noprofile',
          '-i',
          '-c',
          _shellLine,
        ],
      );
      expect(code, 0, reason: said);
      expect(said, contains('drew at 90x25, handed over 1 times'));
    },
    timeout: const Timeout(Duration(minutes: 3)),
    // macOS's bash (3.2) in this pseudo-terminal fails to set it up for
    // job control (tcsetattr: Inappropriate ioctl for device) and the app
    // is stopped before it draws: to be found out there (ci-skipped)
    testOn: 'linux',
  );

  test('a resize is drawn at the new size', () async {
    final (code, said) = await ptyRun(
      [
        // resized once the app has drawn, q once it drew at the new size
        '--when',
        _drawn,
        '--when',
        'suspend app 90x25',
        '--input',
        '#2:q',
        '--resize',
        '#1:90x25',
      ],
      [Platform.resolvedExecutable, _app],
    );
    expect(code, 0, reason: said);
    expect(said, contains('drew at 90x25, handed over 0 times'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('SIGTERM puts the terminal back and ends the app with 143', () async {
    final (code, said) = await ptyRun(
      ['--when', _drawn, '--input', '#1:t', '--expect-status', '143'],
      [Platform.resolvedExecutable, _app],
    );
    expect(code, 0, reason: said);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
