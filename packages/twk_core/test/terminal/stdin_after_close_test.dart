// The process's own terminal in a pseudo-terminal (tool/pty_run.py),
// running stdin_after_close_app.dart: once a terminal that read keys is
// closed, fd 0 is as it was, so a program that inherits it reads what is
// typed, a second terminal opened after reads keys, and the process ends
// on its own, the terminal put back.
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
      'test/terminal/stdin_after_close_app.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    ),
  );

  test('a closed terminal leaves fd 0 to a program started after and to a '
      'terminal opened again, and the process ends', () async {
    final res = await runProcess(
      'python3',
      [
        '../../tool/pty_run.py',
        // what a loaded machine may take to start the app and run it
        '--timeout',
        '120',
        '--input',
        'none',
        // a key for the first terminal, a line for the program after it, a
        // key for the second terminal, each once it asks
        '--when',
        'press a key',
        '--when',
        'child> ',
        '--when',
        'again a key',
        '--input',
        r'#1:a,#2:hello\r,#3:b',
        '--',
        Platform.resolvedExecutable,
        app,
      ],
      environment: childEnvironment(),
      includeParentEnvironment: false,
      group: true,
    );
    final said = '${res.stdout}${res.stderr}';
    // the status 0 is pty_run's: the app ended by itself, with status 0,
    // the terminal put back
    expect(res.exitCode, 0, reason: said);
    expect(said, contains('first a, child exit 0, second b'));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
