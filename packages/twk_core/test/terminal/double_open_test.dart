// Two opens at once of the process's terminal, in a pseudo-terminal
// (tool/pty_run.py): the probe takes a while, and the second must not get
// past the guard during it, entering raw mode twice beside a second reader.
@Tags(['process'])
@TestOn('linux || mac-os')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show compiledProgram, runProcess;

import '../support/environment.dart';

void main() {
  test('a second open during the first is refused', () async {
    final app = await compiledProgram(
      'test/terminal/double_open_app.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    );
    final dir = await Directory.systemTemp.createTemp('twk_double_open');
    addTearDown(() => dir.delete(recursive: true));
    final said = File('${dir.path}/said');
    final res = await runProcess(
      'python3',
      [
        '../../tool/pty_run.py',
        '--timeout',
        '60',
        '--input',
        'none',
        '--out',
        '${dir.path}/out.bin',
        '--',
        Platform.resolvedExecutable,
        app,
        said.path,
      ],
      environment: childEnvironment(),
      includeParentEnvironment: false,
      group: true,
    );
    expect(res.exitCode, 0, reason: '${res.stdout}${res.stderr}');
    expect(said.readAsStringSync(), 'opened TerminalException');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
