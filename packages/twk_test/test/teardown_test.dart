// What testTwk does when a test returns, seen from outside: the tests of
// fixtures/teardown.dart run in a process of their own.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show runProcess;

void main() {
  test('when a test returns or fails, its app is quit; an error the app '
      'ended with that no call threw fails it, as do bytes the emulator does '
      'not take, unless the test failed already', () async {
    final run = await runProcess(Platform.resolvedExecutable, [
      'test',
      '--reporter=json',
      'test/fixtures/teardown.dart',
    ], group: true);
    final names = <int, String>{};
    final results = <String, String>{};
    final errors = <String, List<String>>{};
    for (final line in LineSplitter.split('${run.stdout}')) {
      if (!line.startsWith('{')) {
        continue;
      }
      final event = jsonDecode(line) as Map<String, Object?>;
      switch (event) {
        case {
          'type': 'testStart',
          'test': {'id': final int id, 'name': final String name},
        }:
          names[id] = name;
        case {
          'type': 'error',
          'testID': final int id,
          'error': final String error,
        }:
          (errors[names[id]!] ??= []).add(error);
        case {
          'type': 'testDone',
          'testID': final int id,
          'result': final String result,
        }:
          results[names[id]!] = result;
      }
    }
    expect(results, {
      'loading test/fixtures/teardown.dart': 'success',
      'an app left running': 'success',
      'a test that fails, its app left running': 'failure',
      'an app that fails as it ends': 'error',
      'bytes the emulator does not take': 'error',
      'a test that fails, and bytes the emulator does not take': 'failure',
    });
    expect(errors['a test that fails, its app left running'], [
      contains('the test failed'),
    ]);
    expect(errors['an app that fails as it ends'], [
      contains('dispose failed'),
    ]);
    expect(errors['bytes the emulator does not take'], [
      contains('unsupported private mode 999'),
    ]);
    expect(
      errors['a test that fails, and bytes the emulator does not take'],
      [contains('the test failed')],
    );
  });
}
