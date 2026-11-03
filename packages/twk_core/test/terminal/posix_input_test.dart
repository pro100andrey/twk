// The reader of fd 0 (PosixInput), in a program of its own with a line
// already waiting on fd 0 (posix_input_paused_app.dart): paused as soon as
// it is listened to, it reads nothing, and a program started after it gets
// the line.
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
      'test/terminal/posix_input_paused_app.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    ),
  );

  test('a reader paused as it is listened to reads nothing, and leaves '
      'what fd 0 has to a program started after', () async {
    final res = await runProcess(
      'sh',
      ['-c', r'printf "abc\n" | "$0" "$1"', Platform.resolvedExecutable, app],
      environment: childEnvironment(),
      includeParentEnvironment: false,
      group: true,
      // what a loaded machine may take to start the app
      timeout: const Duration(minutes: 2),
    );
    final said = '${res.stdout}${res.stderr}';
    expect(res.exitCode, 0, reason: said);
    expect(res.stdout, contains('child abc'), reason: said);
    expect(res.stderr, contains('read 0, child exit 0'), reason: said);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
