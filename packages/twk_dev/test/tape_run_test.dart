// `twk tape`'s runner in a pseudo-terminal: what is typed reaches the
// program at the typing speed and Sleep waits, the time between a Hide
// and its Show cut from the recording; Wait goes on once the screen
// shows its text, and one that times out fails, saying so with the
// screen, writing nothing; a tape stopped ends at once; the program is
// gone at the end of each. The walkthrough's app through a tape: the
// keys reach it, the recording plays back to the screen it showed, the
// screenshot and the animation are written.
@TestOn('linux || mac-os')
@Timeout(Duration(seconds: 90))
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk_dev/src/tape.dart';
import 'package:twk_dev/twk_dev.dart';
import 'package:twk_test/twk_test.dart' show ScreenFrame, screenFrames;
import 'package:twk_test/twk_test.dart' show waitFor, waitUntil;

import 'twk.dart';

/// The screens [cast] showed, as twk_test's emulator shows them.
List<ScreenFrame> _frames(Cast cast) =>
    screenFrames(cast.header.width, cast.header.height, cast.writes);

void main() {
  // the walkthrough's app, compiled once
  late String tally;
  setUpAll(() async => tally = await compiled('example/tally.dart'));

  late String temp;
  setUp(() async {
    temp = (await Directory.systemTemp.createTemp('twk_tape_')).path;
    addTearDown(() => Directory(temp).delete(recursive: true));
  });

  /// [runner] run, stopped when the test ends if it still runs then
  /// (which ends its program), the stop waited for with a bound.
  Future<int> running(TapeRunner runner) {
    final ran = runner.run();
    addTearDown(() async {
      runner.stop(130);
      await waitFor(ran.then((_) {}, onError: (_) {}), 'the tape to stop');
    });
    return ran;
  }

  /// Runs [source], by [clock]; its exit code and what it said.
  Future<(int, List<String>)> run(String source, {TapeClock? clock}) async {
    final said = <String>[];
    final code = await running(
      TapeRunner(
        Tape.parse(source, name: 't.tape'),
        log: said.add,
        clock: clock,
      ),
    );
    return (code, said);
  }

  /// The output events of the recording at [path]: their times and data.
  List<(double, String)> outputs(String path) => [
    for (final e in Cast.read(path).events)
      if (e.code == CastEvent.output) (e.time, e.data),
  ];

  test('types at the typing speed and sleeps; the time between Hide and '
      'Show is cut, the screen drawn at the Show', () async {
    final cast = p.join(temp, 't.cast');
    final svg = p.join(temp, 'out', 't.svg');
    // the time the tape's pauses make, not the machine's: an echo is
    // waited for, and is stamped at most a pause late
    final (code, said) = await run('''
Output $cast
Output $svg
Set Width 20
Set Height 3
Set TypingSpeed 100ms
Set WaitTimeout 60s
Run cat
Sleep 100ms
Type "abc"
Wait "abc"
Sleep 500ms
Hide
Type "h"
Wait "abch"
Sleep 1s
Show
Sleep 100ms
Type "d"
Wait "abchd"
''', clock: _Steps());

    expect(code, 0, reason: '$said');
    expect(said, ['twk tape: wrote $cast', 'twk tape: wrote $svg']);
    final events = outputs(cast);
    const redraw = '\x1b[0m\x1b[H\x1b[2J\x1b[1Habch\x1b[1;5H\x1b[?25h';
    final at = events.indexWhere((e) => e.$2 == redraw);
    expect(at, greaterThan(0), reason: '$events');
    // cat's terminal echoes what is typed, in a piece or more
    expect(events.take(at).map((e) => e.$2).join(), 'abc');
    expect(events.skip(at + 1).map((e) => e.$2).join(), 'd');
    // a at 0.1 s, after the sleep; c typed at 0.3 s, 0.1 s before the next
    for (final (time, _) in events.take(at)) {
      expect(time, inInclusiveRange(0.1, 0.4));
    }
    // c's 100 ms, the 500 ms sleep, and nothing of the 1.1 s hidden
    expect(events[at].$1, closeTo(0.9, 1e-6));
    // the 100 ms sleep, d typed and its 100 ms
    for (final (time, _) in events.skip(at + 1)) {
      expect(time, inInclusiveRange(1.0, 1.1));
    }
    final header = Cast.read(cast).header;
    expect((header.width, header.height), (20, 3));
    expect(header.command, 'cat');

    // the screens at their times, to the end of the tape: d's 100 ms on
    final animation = File(svg).readAsStringSync();
    expect(animation, contains('animation:f 1.1s steps(1,end) infinite'));
    final percents = [
      for (final m in RegExp(r'([\d.]+)%\{').allMatches(animation))
        double.parse(m[1]!),
    ];
    expect(percents.first, 0);
    expect(percents.last, 100);
    // the frame drawn at the Show, at its time
    expect(percents, contains(closeTo(0.9 / 1.1 * 100, 0.001)));
  });

  test("waits for text on the screen, and on the cursor's line; a wait "
      'that times out fails with the screen, writing nothing, and the '
      'program is gone', () async {
    final cast = p.join(temp, 't.cast');
    // ready without a line end: the terminal hands `echo`'s "ready\n" to
    // the reader as "ready" and then "\r\n", so a Wait on "ready" could
    // go on, and x be typed and echoed, before the line ended
    final (code, said) = await run('''
Output $cast
Set Width 30
Set Height 4
Set TypingSpeed 10ms
Set WaitTimeout 60s
Run sh -c "sleep 0.5; printf ready; exec cat"
Wait /^ready\$/
Type "x"
Wait+Line "x"
''', clock: _Steps());

    expect(code, 0, reason: '$said');
    // x typed once ready showed: its echo after it
    expect(outputs(cast).map((e) => e.$2).join(), 'readyx');

    final pid = p.join(temp, 'pid');
    final never = p.join(temp, 'never.cast');
    final (failed, why) = await run('''
Output $never
Set Width 30
Set Height 3
Set WaitTimeout 60s
Run sh -c "echo \$\$ > $pid; echo waiting; exec sleep 30"
Wait /waiting/
Wait@300ms /never/
''');

    expect(failed, 1);
    expect(why, [
      [
        'twk tape: t.tape:7: Wait timed out after 0.3s for /never/; the screen:',
        '│waiting',
        '│',
        '│',
      ].join('\n'),
    ]);
    expect(File(never).existsSync(), isFalse);
    expect(_running(_pid(pid)), isFalse);
  });

  test('a screenshot or an output it cannot write fails the tape with 1, '
      'saying where', () async {
    // a file where a directory would have to be
    final file = p.join(temp, 'file');
    File(file).writeAsStringSync('');

    final (shot, shotSaid) = await run('Run cat\nScreenshot $file/s.svg\n');
    expect(shot, 1);
    expect(shotSaid.single, startsWith('twk tape: cannot write $file'));

    final (output, outputSaid) = await run('Output $file/o.cast\nRun cat\n');
    expect(output, 1);
    expect(outputSaid.single, startsWith('twk tape: cannot write $file'));
  });

  test('a tape stopped ends at once with what it was given, writing '
      'nothing, and the program is gone', () async {
    final pid = p.join(temp, 'pid');
    final cast = p.join(temp, 't.cast');
    final runner = TapeRunner(
      Tape.parse('''
Output $cast
Run sh -c "echo \$\$ > $pid; exec sleep 30"
Sleep 20s
'''),
      log: (_) {},
    );
    // Real time on purpose: the runner's own clock, a real one, is what
    // stop cuts short, measured here
    final clock = Stopwatch()..start();
    final ran = running(runner);
    await waitUntil(
      () => File(pid).existsSync() && File(pid).readAsStringSync().isNotEmpty,
      'the program to start and write its pid',
    );
    runner.stop(130);

    expect(await ran, 130);
    // well before the 20 s sleep, the hang-up's 2 s and more besides
    expect(clock.elapsed, lessThan(const Duration(seconds: 15)));
    expect(File(cast).existsSync(), isFalse);
    expect(_running(_pid(pid)), isFalse);
  });

  test('keys go as the modes of the program want them: an arrow with '
      'application cursor keys, Ctrl and Alt with a letter', () async {
    final cast = p.join(temp, 't.cast');
    final (code, said) = await run(
      r'''
Output CAST
Set Width 20
Set Height 3
Set TypingSpeed 20ms
Set WaitTimeout 60s
Run sh -c "printf '\033[?1hready\n'; exec cat"
Wait /ready/
Up
Left
Alt+x
Type "y"
Ctrl+C
Wait "^C"
'''
          .replaceFirst('CAST', cast),
    );

    expect(code, 0, reason: '$said');
    // cat's terminal echoes ESC as ^[, ETX as ^C
    expect(_frames(Cast.read(cast)).last.lines[1], '^[OA^[OD^[xy^C');
  });

  test("the walkthrough's app through a tape: the keys reach it, the "
      'recording plays back to its screen, the screenshot and the '
      'animation show it', () async {
    final cast = p.join(temp, 'tally.cast');
    final svg = p.join(temp, 'tally.svg');
    final still = p.join(temp, 'counted.svg');
    final (code, said) = await run('''
Output $cast
Output $svg
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
Screenshot $still
''');

    expect(code, 0, reason: '$said');
    final frames = _frames(Cast.read(cast));
    expect(frames.first.lines[1], startsWith('│ › coffee     0'));
    expect(frames.last.lines[1], startsWith('│   coffee     1 ■'));
    expect(frames.last.lines[2], startsWith('│ › tea        2 ■■'));
    expect(frames.last.errors, isEmpty);
    // nothing of the start, which was hidden: the first frame is the app's
    expect(Cast.read(cast).events.first.time, 0);

    final shot = File(still).readAsStringSync();
    expect(shot, contains('font-weight:bold'));
    expect(shot, contains('>tea</text>'));
    expect(shot, contains('>■■</text>'));
    expect(shot, contains('<path d="M12 12A6 6 0 0 0 6 18V24'));
    final animation = File(svg).readAsStringSync();
    expect(animation, contains('@keyframes f{0%'));
    expect(animation, contains('>coffee</text>'));
  });
}

/// Time that goes on by the tape's pauses alone, each at once: the
/// recording's times are the tape's, however loaded the machine.
final class _Steps extends TapeClock {
  Duration _elapsed = Duration.zero;

  @override
  Duration get elapsed => _elapsed;

  @override
  Future<void> pause(Duration duration, Future<void> stop) async {
    await Future.any([Future<void>.delayed(Duration.zero), stop]);
    _elapsed += duration;
  }
}

/// The process id the file at [path] has.
int _pid(String path) {
  final pid = int.parse(File(path).readAsStringSync().trim());
  expect(pid, greaterThan(1));
  return pid;
}

/// Whether process [pid] runs: one that ended and was waited for is not
/// there, nor is one that ended and was not (a zombie, `Z`).
bool _running(int pid) {
  final ps = Process.runSync('ps', ['-o', 'stat=', '-p', '$pid']);
  final stat = (ps.stdout as String).trim();
  return stat.isNotEmpty && !stat.startsWith('Z');
}
