// A probe, not a test: runs windows_nul_probe_app.dart and prints what it
// found, for the CI log. Removed once its answer is in WindowsInput.
@TestOn('windows')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show compiledProgram, runProcess;

void main() {
  test('PROBE Ctrl+Space in the console', () async {
    final app = await compiledProgram(
      'test/terminal/windows_nul_probe_app.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    );
    final res = await runProcess(
      Platform.resolvedExecutable,
      [app],
      timeout: const Duration(minutes: 2),
    );
    // the report is for the CI log, which shows what a test prints
    // ignore: avoid_print
    print('PROBE-NUL exit ${res.exitCode}\n${res.stdout}${res.stderr}');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
