// `twk record` in a terminal of the test's (see terminal.dart): the
// session recorded (the header, what was written, typed and resized),
// the terminal passed through in raw mode and put back at the end, also
// when the recording fails, when a signal ends it and after a shell took
// the terminal from it while it was stopped; what the command left on
// turned off; the recording played through the test emulator to the
// screen the terminal showed.
@TestOn('linux || mac-os')
@Timeout(Duration(minutes: 4))
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk_dev/twk_dev.dart';
import 'package:twk_test/twk_test.dart' show ScreenFrame, screenFrames;
import 'package:twk_test/twk_test.dart' show runProcess;

import 'terminal.dart';
import 'twk.dart';

final String _dart = Platform.resolvedExecutable;

/// The screens [cast] showed, as twk_test's emulator shows them.
List<ScreenFrame> _frames(Cast cast) =>
    screenFrames(cast.header.width, cast.header.height, cast.writes);

void main() {
  // the walkthrough's app twk record runs, compiled once
  late String tally;
  setUpAll(() async {
    await compileTwk();
    tally = await compiled('example/tally.dart');
  });

  late String temp;
  setUp(() async {
    temp = (await Directory.systemTemp.createTemp('twk_record_')).path;
    addTearDown(() => Directory(temp).delete(recursive: true));
  });

  test(
    'records the output, the keys and a resize of a session through a '
    'terminal in raw mode, put back at the end; the recording plays '
    'through the emulator to the screen the terminal showed',
    () async {
      final cast = p.join(temp, 's.cast');
      final started = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final t = await Terminal.twk([
        'record',
        '--keys',
        '--title=tally',
        '--out=$cast',
        '--',
        _dart,
        tally,
      ]);
      final before = t.modes;
      expect(before.raw, isFalse);

      await t.until(
        () => t.lines.any((l) => l.contains('q quit')),
        'the tally',
      );
      expect(t.modes.raw, isTrue, reason: '${t.modes}');
      t.type('+');
      await t.until(
        () => t.lines.any((l) => l.contains('› coffee     1 ■')),
        'coffee counted',
      );
      t.resize(64, 16);
      await t.until(
        () => t.lines.last.startsWith('╰') && t.lines.last.length == 64,
        'the tally at the new size',
      );
      final shown = t.lines;
      t.type('q');

      expect(await t.ended(), exits(0));
      expect(t.modes.same(before), isTrue, reason: '${t.modes}');
      expect(t.text, contains('twk record: recording '));

      final recording = Cast.read(cast);
      final header = recording.header;
      expect((header.width, header.height), (60, 14));
      expect(header.title, 'tally');
      expect(header.command, '$_dart $tally');
      expect(header.env['TERM'], 'xterm-256color');
      expect(header.idleTimeLimit, 2);
      expect(
        header.timestamp,
        inInclusiveRange(
          started,
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ),
      );
      final events = recording.events;
      expect(events.first.code, CastEvent.output);
      final resizes = [
        for (final e in events)
          if (e.code == CastEvent.resize) e.size,
      ];
      expect(resizes, [(64, 16)]);
      final typed = [
        for (final e in events)
          if (e.code == CastEvent.input) e.data,
      ].join();
      expect(typed, allOf(contains('+'), endsWith('q')));
      for (var i = 1; i < events.length; i++) {
        final gap = events[i].time - events[i - 1].time;
        expect(gap, inInclusiveRange(0, 2), reason: '${events[i]}');
      }

      final frames = _frames(recording);
      expect(frames.last.lines, shown);
      expect((frames.last.width, frames.last.height), (64, 16));
      expect(frames.last.errors, isEmpty);
    },
  );

  test('records no keys without --keys; ends with the exit code of the '
      'command', () async {
    final cast = p.join(temp, 's.cast');
    final t = await Terminal.twk([
      'record',
      '--out=$cast',
      '--',
      'sh',
      '-c',
      r'read x; echo "got $x"; exit 3',
    ]);
    await t.until(() => t.modes.raw, 'raw mode');
    t.type('hi\r');

    expect(await t.ended(), exits(3));
    final events = Cast.read(cast).events;
    expect(events.map((e) => e.code).toSet(), {CastEvent.output});
    expect(events.map((e) => e.data).join(), 'hi\r\ngot hi\r\n');
  });

  test('turns off what the command left turned on, which the recording '
      'does not have', () async {
    final cast = p.join(temp, 's.cast');
    const left = '\x1b[?1049h\x1b[?1000h\x1b[?25lleft on';
    final t = await Terminal.twk([
      'record',
      '--out=$cast',
      '--',
      'printf',
      r'\033[?1049h\033[?1000h\033[?25lleft on',
    ]);

    expect(await t.ended(), exits(0));
    expect(t.text, contains('$left\x1b[0m\x1b[?1000l\x1b[?25h\x1b[?1049l'));
    expect(t.screen.alternateScreen, isFalse);
    expect(t.screen.cursorVisible, isTrue);
    expect(Cast.read(cast).events.map((e) => e.data).join(), left);
  });

  test('puts the terminal back and hangs the command up when the '
      'recording cannot be written', () async {
    final fifo = p.join(temp, 's.cast');
    expect((await runProcess('mkfifo', [fifo])).exitCode, 0);
    final t = await Terminal.twk([
      'record',
      '--out=$fifo',
      '--',
      'sh',
      '-c',
      'while :; do echo tick; sleep 0.05; done',
    ]);
    final before = t.modes;
    final header = Completer<void>();
    final reader = File(fifo).openRead().listen((_) {
      if (!header.isCompleted) {
        header.complete();
      }
    });
    await header.future.timeout(wait);
    await t.until(() => t.modes.raw && t.text.contains('tick'), 'a tick');
    // the recording's reader goes away: its next write fails
    await reader.cancel();

    expect(await t.ended(), exits(1));
    expect(t.text, contains('twk record: cannot write $fifo: Broken pipe'));
    expect(t.modes.same(before), isTrue, reason: '${t.modes}');
  });

  test('ends with 128 and the number of SIGTERM, the terminal put back and '
      'the command hung up', () async {
    final cast = p.join(temp, 's.cast');
    final t = await Terminal.twk(['record', '--out=$cast', '--', 'cat']);
    final before = t.modes;
    await t.until(() => t.modes.raw, 'raw mode');
    t.type('one\r');
    await t.until(() => t.text.contains('one\r\none\r\n'), 'cat');
    t.pty.kill();

    expect(await t.ended(), exits(143));
    expect(t.modes.same(before), isTrue, reason: '${t.modes}');
    expect(Cast.read(cast).events.map((e) => e.data).join(), 'one\r\none\r\n');
  });

  test('enters raw mode again when continued after a shell put the '
      'terminal back while it was stopped', () async {
    final cast = p.join(temp, 's.cast');
    final t = await Terminal.twk(['record', '--out=$cast', '--', 'cat']);
    final before = t.modes;
    await t.until(() => t.modes.raw, 'raw mode');
    t.pty.kill(ProcessSignal.sigstop);
    addTearDown(() => t.pty.kill(ProcessSignal.sigcont));
    await t.until(() => t.stopped, 'twk record to stop');
    t.modes = before;
    // Real time on purpose: that nothing puts raw mode back while it is
    // stopped is an absence, which no event tells; half a second of it
    // ignore: twk_lints/wall_time_in_tests
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(t.modes.raw, isFalse, reason: 'stopped, it changes nothing');

    t.pty.kill(ProcessSignal.sigcont);
    await t.until(() => t.modes.raw, 'raw mode again');
    // the terminal echoes nothing itself: once the command's terminal,
    // once cat
    t.type('two\r');
    await t.until(() => t.text.contains('two\r\ntwo\r\n'), 'cat');
    t.type('\x04');

    expect(await t.ended(), exits(0));
    expect('two'.allMatches(t.text), hasLength(2));
    expect(t.modes.same(before), isTrue, reason: '${t.modes}');
  });
}
