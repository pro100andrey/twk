// The test's terminal itself (terminal.dart): the tty it holds open is not
// passed to a process started meanwhile, which would hold the output open
// until it ended — under `handover -j`, a compile of another suite in the
// same VM made two suites wait out their 90 s for an output that had ended.
@TestOn('linux || mac-os')
// past terminal.dart's wait, so that a failure says what was waited for
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:test/test.dart';

import 'terminal.dart';

void main() {
  test('the output ends with the program while a process started meanwhile '
      'still runs', () async {
    final t = await Terminal.start('/bin/sh', ['-c', 'echo hi']);
    final other = await Process.start('sleep', ['600']);
    addTearDown(other.kill);
    var otherEnded = false;
    other.exitCode.then((_) => otherEnded = true).ignore();
    expect(await t.ended(), 0);
    expect(t.outputDone, isTrue);
    expect(otherEnded, isFalse);
  });
}
