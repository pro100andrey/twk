// `twk tape --check`: a tape run as a test. Nothing is written (no Output,
// no Screenshot); each statement is reported as it passes; the first Wait
// that times out fails with the screen and exit 1, its timeout the clock's
// (a fake one here, fired by the test), not the wall's.
@Tags(['process'])
@TestOn('linux || mac-os')
@Timeout(Duration(seconds: 90))
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk_dev/src/tape.dart';
import 'package:twk_test/twk_test.dart' show waitFor, waitUntil;

void main() {
  late String temp;
  setUp(() async {
    temp = (await Directory.systemTemp.createTemp('twk_check_')).path;
    addTearDown(() => Directory(temp).delete(recursive: true));
  });

  test('a passing tape reports each statement and a last line, writes '
      'nothing, and the program is gone', () async {
    final cast = p.join(temp, 'out', 't.cast');
    final shot = p.join(temp, 'out', 's.svg');
    final said = <String>[];
    final clock = _Clock();
    final runner = TapeRunner(
      Tape.parse('''
Output $cast
Set Width 20
Set Height 3
Set TypingSpeed 10ms
Set WaitTimeout 60s
Run cat
Type "hi"
Wait "hi"
Enter
Sleep 1s
Hide
Show
Screenshot $shot
''', name: 't.tape'),
      check: true,
      clock: clock,
      log: said.add,
      report: said.add,
    );
    addTearDown(() => runner.stop(130));
    final code = await waitFor(runner.run(), 'the tape to run');

    expect(code, 0, reason: '$said');
    expect(said, [
      't.tape:4: ok Set TypingSpeed 10ms',
      't.tape:5: ok Set WaitTimeout 60s',
      't.tape:7: ok Type "hi"',
      't.tape:8: ok Wait "hi"',
      't.tape:9: ok Enter',
      't.tape:10: ok Sleep 1s',
      't.tape:11: ok Hide',
      't.tape:12: ok Show',
      't.tape:13: ok Screenshot $shot (not written)',
      't.tape: passed, 9 statements',
    ]);
    expect(Directory(p.join(temp, 'out')).existsSync(), isFalse);
  });

  test('the first Wait that times out fails the tape with the screen, on '
      "the clock's timeout; the statements after it are not run", () async {
    final said = <String>[];
    final out = <String>[];
    final clock = _Clock();
    final pid = p.join(temp, 'pid');
    final cast = p.join(temp, 't.cast');
    final runner = TapeRunner(
      Tape.parse('''
Output $cast
Set Width 30
Set Height 3
Set WaitTimeout 60s
Run sh -c "echo \$\$ > $pid; echo waiting; exec sleep 30"
Wait /waiting/
Wait@300ms /never/
Type "after"
''', name: 't.tape'),
      check: true,
      clock: clock,
      log: said.add,
      report: out.add,
    );
    addTearDown(() => runner.stop(130));
    final ran = runner.run();
    // the Wait is waiting, its alarm set for the timeout it names
    await waitUntil(
      () => clock.alarms.any((a) => a.$1.inMilliseconds == 300),
      'the Wait to wait',
    );
    clock.fire();

    expect(await waitFor(ran, 'the tape to fail'), 1);
    expect(out, [
      't.tape:4: ok Set WaitTimeout 60s',
      't.tape:6: ok Wait /waiting/',
      't.tape:7: FAIL Wait@300ms /never/',
      't.tape: failed, 2 of 4 statements passed',
    ]);
    expect(said, [
      [
        'twk tape: t.tape:7: Wait timed out after 0.3s for /never/; the screen:',
        '│waiting',
        '│',
        '│',
      ].join('\n'),
    ]);
    expect(File(cast).existsSync(), isFalse);
    expect(_running(int.parse(File(pid).readAsStringSync().trim())), isFalse);
  });
}

/// Time whose pauses are over at once and whose alarms the test fires.
final class _Clock extends TapeClock {
  Duration _elapsed = Duration.zero;
  final alarms = <(Duration, void Function(), Timer)>[];

  @override
  Duration get elapsed => _elapsed;

  @override
  Future<void> pause(Duration duration, Future<void> stop) async {
    await Future.any([Future<void>.delayed(Duration.zero), stop]);
    _elapsed += duration;
  }

  @override
  Timer alarm(Duration duration, void Function() fire) {
    // A Timer is what the runner holds to cancel; this one never goes
    // off by itself, it only says whether the alarm is still wanted.
    // ignore: twk_lints/wall_time_in_tests
    final held = Timer(const Duration(days: 1), () {});
    alarms.add((duration, fire, held));
    return held;
  }

  /// The alarms still wanted go off.
  void fire() {
    for (final (_, f, held) in alarms) {
      if (held.isActive) {
        f();
      }
    }
  }
}

bool _running(int pid) {
  final ps = Process.runSync('ps', ['-o', 'stat=', '-p', '$pid']);
  final stat = (ps.stdout as String).trim();
  return stat.isNotEmpty && !stat.startsWith('Z');
}
