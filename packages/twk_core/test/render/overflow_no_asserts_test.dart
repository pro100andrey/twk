@Tags(['process'])
library;

// With asserts off the overflow marker still appears where it is turned on
// (TWK_DEBUG=overflow, Ctrl+G w): the cells cut off are measured by the
// layout, not by an assert.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('the marker shows with asserts off', () async {
    final r = await Process.run(Platform.resolvedExecutable, [
      'run',
      'test/render/overflow_no_asserts_app.dart',
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect('${r.stdout}'.split('\n'), [
      'asserts=false',
      'abcd+2',
      '     ▚',
      'true',
      '',
    ]);
  });
}
