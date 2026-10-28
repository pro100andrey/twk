// The core on the web: tool/web_check.dart's core case, the core's
// test/web/core_app.dart (packages/twk_core) compiled with dart2wasm,
// nothing of dart:io, dart:ffi, dart:isolate or dart:mirrors reached, the
// build run in node. Without a node to run it in (the tool's status 2)
// the test is skipped, not passed.
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show runProcess;

void main() {
  test(
    'the core compiles for the web without dart:io and runs there',
    () async {
      final res = await runProcess(Platform.resolvedExecutable, [
        'run',
        'tool/web_check.dart',
        'core',
      ], group: true);
      final output = '${res.stdout}${res.stderr}';
      if (res.exitCode == 2) {
        markTestSkipped(output);
        return;
      }
      expect(res.exitCode, 0, reason: output);
      expect(res.stdout, contains(RegExp('^core +io +ok', multiLine: true)));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
