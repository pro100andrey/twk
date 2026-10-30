// Ctrl+Z under runApp, on the process's own terminal in a pseudo-terminal
// (tool/pty_run.py) under an interactive shell, running stop_app.dart:
// nothing in the app takes it, so it stops the app for the shell, which
// has the terminal as it was before the app took it; resized meanwhile,
// fg gives it back to the app, drawn at the new size.
@TestOn('linux || mac-os')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show compiledProgram, runProcess;

void main() {
  // the app run in a pseudo-terminal, compiled once
  late String app;
  setUpAll(
    () async => app = await compiledProgram(
      'test/binding/stop_app.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    ),
  );

  test(
    'Ctrl+Z that nothing takes stops the app for the shell, which has the '
    'terminal as it was; fg gives it back to the app, at the new size',
    () async {
      // the app, what the shell says while it has the terminal, a line it
      // reads (typed once the terminal was resized), and fg
      final shellLine =
          '"${Platform.resolvedExecutable}" "$app"; '
          'echo shell has it; read x; fg';
      final res = await runProcess(
        'python3',
        [
          '../../tool/pty_run.py',
          // what a loaded machine may take to start the app, run and end it
          '--timeout',
          '120',
          // Ctrl+Z once the app has drawn; resized when the shell has the
          // terminal, before the line that lets it go on to fg; q once the
          // app drew again at the new size
          '--when',
          'stop app 100x30',
          '--when',
          'shell has it',
          '--when',
          'stop app 90x25',
          '--input',
          r'#1:\x1a,#2:\r,#3:q',
          '--suspended',
          'shell has it',
          '--resize',
          '#2:90x25',
          '--',
          // an interactive bash with job control, its stderr the terminal:
          // bash 3.2 (macOS's) sets the terminal up for job control and
          // hands it to a job through its stderr, which pty_run.py reads
          // as a pipe
          '/bin/sh',
          '-c',
          r'exec 2>&0 "$@"',
          'sh',
          'bash',
          '--norc',
          '--noprofile',
          '-i',
          '-c',
          shellLine,
        ],
        group: true,
      );
      expect(res.exitCode, 0, reason: '${res.stdout}${res.stderr}');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
