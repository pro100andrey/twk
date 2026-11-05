// The process's own terminal in a pseudo-terminal (tool/pty_run.py),
// running one_terminal_app.dart: a second Terminal.open on it while the
// first has it is refused, rather than a second reader of fd 0 that takes
// the keys the first one is waiting for; a suspended first gives way to a
// second and has it again after.
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
      'test/terminal/one_terminal_app.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    ),
  );

  test("a second terminal on the process's stdio is refused while the first "
      'has it, and keys still reach the first', () async {
    final res = await runProcess(
      'python3',
      [
        '../../tool/pty_run.py',
        '--timeout',
        '120',
        '--input',
        'none',
        '--when',
        'first ready',
        '--when',
        'second ready',
        '--when',
        'first again',
        '--input',
        '#1:a,#2:b,#3:c',
        '--',
        Platform.resolvedExecutable,
        app,
      ],
      environment: childEnvironment(),
      includeParentEnvironment: false,
      group: true,
    );
    final said = '${res.stdout}${res.stderr}';
    expect(res.exitCode, 0, reason: said);
    expect(said, contains('refused, first a, second b, first c'));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
