// The test `twk test-from-cast` writes, and the screen files it runs the
// test once to write: on the walkthrough's app recorded by a tape the test
// analyzes clean and passes, and fails where a screen file is edited; on a
// recording with a tab in a checked row it passes too, the emulator that
// wrote the file being the one that checks it.
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

  /// The screen file [name] of the test at [out], goldens/<name>/<file>.
  File golden(String out, String file) => File(
    p.join(
      p.dirname(out),
      'goldens',
      p.basenameWithoutExtension(out).replaceFirst(RegExp(r'_test$'), ''),
      file,
    ),
  );

  test('the test of the walkthrough recording analyzes and passes, and '
      'fails on an edited screen file', () async {
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
    expect(
      (made.stdout as String).split('\n').first,
      startsWith('wrote '),
    );
    expect(made.stdout, contains('goldens/tally/last.txt'));
    final screen = golden(out, 'last.txt');
    expect(screen.existsSync(), isTrue);
    expect(screen.readAsStringSync(), contains('tea        2'));

    final rel = p.relative(out, from: await packageDirectory());
    final analyzed = await dart(['analyze', '--fatal-infos', rel]);
    expect(analyzed.exitCode, 0, reason: '${analyzed.stdout}');
    final ran = await dart(['test', rel]);
    expect(ran.exitCode, 0, reason: '${ran.stdout}${ran.stderr}');

    // a screen file edited: the test says it differs
    screen.writeAsStringSync(
      screen.readAsStringSync().replaceFirst('tea ', 'tex '),
    );
    final failed = await dart(['test', rel]);
    expect(failed.exitCode, isNot(0));
    expect(failed.stdout, contains('differs from'));
  });

  test('a recording with a tab in a checked row: the screen file is the '
      "emulator's, so the marker's check passes; the emulator says it did "
      'not take the tab in', () async {
    final cast = p.join(dir.path, 'tabs.cast');
    File(cast).writeAsStringSync(
      '{"version": 2, "width": 20, "height": 3}\n'
      '[0.1, "o", "a\\tb\\r\\n"]\n'
      '[0.2, "m", "tabbed"]\n',
    );
    final out = p.join(dir.path, 'test', 'tabs_test.dart');

    final made = await twkHere(['test-from-cast', cast, '--out=$out']);
    // Vt reports a tab as a raw control byte: the run fails on that alone
    expect(made.exitCode, 1);
    expect((made.stdout as String).split('\n').first, startsWith('wrote '));
    expect(made.stderr, contains('0x9'));
    expect(golden(out, '1.txt').readAsStringSync(), contains('│ab'));

    final rel = p.relative(out, from: await packageDirectory());
    final marker = await dart(['test', rel, '-n', 'the marker']);
    expect(marker.exitCode, 0, reason: '${marker.stdout}${marker.stderr}');
  });
}
