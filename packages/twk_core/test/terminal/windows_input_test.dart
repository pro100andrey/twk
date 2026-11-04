// The console's reader (WindowsInput), in a program of its own whose
// standard input is the console (windows_input_app.dart): keys written into
// the console's input buffer are read, a reader cancelled or paused reads
// nothing more and leaves the handle open, a second reader and a program
// started after read what comes next, Ctrl+Space is read as NUL in VT
// input mode, and the program ends on its own.
@TestOn('windows')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show compiledProgram, runProcess;

void main() {
  late String app;
  setUpAll(
    () async => app = await compiledProgram(
      'test/terminal/windows_input_app.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    ),
  );

  test('the console read by readers of its own, one after another, then by '
      'a program started after, and the process ends', () async {
    final res = await runProcess(
      Platform.resolvedExecutable,
      [app],
      // what a loaded machine may take to start the app and run it
      timeout: const Duration(minutes: 2),
    );
    final said = '${res.stdout}${res.stderr}';
    expect(res.exitCode, 0, reason: said);
    expect(
      res.stderr,
      contains(
        // b, 日 and 😀, the last typed as two units
        'first a, left 2 open true, second 62 65e5 1f600, paused left 2, '
        'child exit 0, nul 0 71',
      ),
      reason: said,
    );
    // the c the paused reader left, then hi
    expect(res.stdout, contains('child chi'), reason: said);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
