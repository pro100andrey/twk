// What testTwk's trackDisposables reports, seen from outside: the tests of
// fixtures/disposables.dart run in a process of their own.
@Tags(['process'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show runProcess;

void main() {
  test('trackDisposables fails a test that left a controller undisposed, '
      'naming it and where it was made; off, or with all disposed, it '
      'passes; a test that failed reports its own error', () async {
    final run = await runProcess(Platform.resolvedExecutable, [
      'test',
      '--reporter=json',
      'test/fixtures/disposables.dart',
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
      'loading test/fixtures/disposables.dart': 'success',
      'a controller left undisposed': 'failure',
      'a controller left undisposed, tracking off': 'success',
      'every controller disposed': 'success',
      'a test that fails': 'failure',
      'a timer left running': 'failure',
      'a timer left running, checking off': 'success',
      'the timer cancelled': 'success',
      'a plain app': 'success',
      'a row overflowed': 'failure',
      'a row overflowed, checking off': 'success',
      'a row overflowed on purpose': 'success',
      'a row that fits': 'success',
    });
    final timer = errors['a timer left running']!.single;
    expect(timer, contains('failOnPendingTimers'));
    expect(timer, contains('a periodic timer, every 1.000 s'));
    expect(timer, contains('disposables.dart'));
    final overflow = errors['a row overflowed']!.single;
    expect(overflow, contains('failOnOverflow'));
    expect(overflow, contains('A RenderFlex overflowed by 2 columns'));
    final error = errors['a controller left undisposed']!.single;
    expect(error, contains('the test made an object it did not dispose'));
    expect(error, contains('ScrollController created at:'));
    expect(error, contains('disposables.dart'));
    expect(error, isNot(contains('TextEditingController')));
    expect(errors['a test that fails']!.single, contains('its own'));
  });
}
