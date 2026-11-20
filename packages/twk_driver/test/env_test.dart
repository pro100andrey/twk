// The color variables of the developer's shell do not reach the program a
// session starts.
@Tags(['process'])
@TestOn('linux || mac-os')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  Future<String> probe([List<String> args = const []]) async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['test/app/env_probe.dart', ...args],
      // the shell of a developer who wants no colors
      environment: {'NO_COLOR': '1', 'FORCE_COLOR': '1', 'KEPT': 'yes'},
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return (result.stdout as String).trim();
  }

  test('NO_COLOR and FORCE_COLOR of the host are empty to the program, '
      'other variables pass', () async {
    expect(await probe(), 'colors:[][][yes]');
  });

  test('what the caller gives is kept', () async {
    expect(await probe(['given']), 'colors:[given][][yes]');
  });
}
