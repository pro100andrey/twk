// The test `twk test-from-cast` writes, on the walkthrough's app recorded by
// a tape: it analyzes clean and passes, and it fails where the recording's
// screen is not what the test says.
@Tags(['process'])
@TestOn('linux || mac-os')
@Timeout(Duration(seconds: 300))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk_dev/src/tape.dart';

import 'twk.dart';

void main() {
  late String tally;
  setUpAll(() async => tally = await compiled('example/tally.dart'));

  late Directory dir;
  setUp(() async {
    // under the package, so that its package configuration resolves the
    // test's imports
    final build = Directory(p.join(await packageDirectory(), 'build'))
      ..createSync(recursive: true);
    dir = build.createTempSync('cast_test_');
    addTearDown(() => dir.delete(recursive: true));
  });

  Future<ProcessResult> dart(List<String> arguments) async => Process.run(
    Platform.resolvedExecutable,
    arguments,
    workingDirectory: await packageDirectory(),
  );

  test('the test of the walkthrough recording analyzes and passes', () async {
    final cast = p.join(dir.path, 'tally.cast');
    final tape = Tape.parse('''
Output $cast
Set Width 40
Set Height 7
Set TypingSpeed 50ms
Set WaitTimeout 60s
Run "${Platform.resolvedExecutable}" "$tally"
Hide
Wait /q quit/
Show
Type "+"
Down
Type "++"
Wait /tea +2/
''', name: 't.tape');
    expect(await TapeRunner(tape, log: (_) {}).run(), 0);
    final out = p.join(dir.path, 'test', 'tally_test.dart');

    final made = await twkHere(['test-from-cast', cast, '--out=$out']);
    expect(made.exitCode, 0, reason: '${made.stderr}');
    final source = File(out).readAsStringSync();
    expect(source, contains('the last screen'));

    final rel = p.relative(out, from: await packageDirectory());
    final analyzed = await dart(['analyze', '--fatal-infos', rel]);
    expect(analyzed.exitCode, 0, reason: '${analyzed.stdout}');
    final ran = await dart(['test', rel]);
    expect(ran.exitCode, 0, reason: '${ran.stdout}${ran.stderr}');

    // the same test over a different recording says what it showed
    File(out).writeAsStringSync(
      source.replaceFirst(
        RegExp(r"lines\[\d+\], '[^\n]*'\);"),
        "lines[0], 'x');",
      ),
    );
    final failed = await dart(['test', rel]);
    expect(failed.exitCode, isNot(0));
  });
}
