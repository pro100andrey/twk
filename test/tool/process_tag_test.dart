// The tests that start a real process are tagged, as they run apart from the
// others (`process-test` in xtask.yaml): one left untagged would run among the
// thousands of others and compete with them for the CPU its deadlines need.
import 'dart:io';

import 'package:test/test.dart';

/// What starts a process, a pseudo-terminal or a program a suite compiled.
final _starts = RegExp(
  r'Process\.(start|run)\b|startProcess\(|runProcess\(|compiledProgram\('
  r'|Pty\.|startTwk\(|Terminal\.(twk|start)\(|templateCycle\(|compileTwk\('
  r'|\bcompiled\(',
);

/// A test a guide shows whole (doc/guides/testing.md), which has no tag to
/// explain to its reader.
const _shownInAGuide = 'packages/twk_term/test/example/run_app_test.dart';

void main() {
  test('a test file of a package that starts a process is tagged process', () {
    final untagged = [
      for (final package in Directory('packages').listSync())
        if (Directory('${package.path}/test').existsSync())
          for (final file in Directory('${package.path}/test').listSync(
            recursive: true,
          ))
            if (file is File &&
                file.path.endsWith('_test.dart') &&
                file.path != _shownInAGuide &&
                _starts.hasMatch(file.readAsStringSync()) &&
                !file.readAsStringSync().contains("@Tags(['process'])"))
              file.path,
    ];
    expect(untagged, isEmpty);
  });
}
