// `twk tape` on twk_driver's session, with a twk app: Wait Widget and Wait
// Text look into the app's tree, Click taps a widget after checking that
// the click reaches it, and says why when it would not; on a program that
// is no twk app they fail saying so.
@Tags(['process'])
@TestOn('linux || mac-os')
@Timeout(Duration(seconds: 120))
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk_dev/src/tape.dart';
import 'package:twk_dev/twk_dev.dart';
import 'package:twk_test/twk_test.dart' show ScreenFrame, screenFrames, waitFor;

import 'twk.dart';

void main() {
  late String app;
  setUpAll(() async => app = await compiled('test/tape_app.dart'));

  late String temp;
  setUp(() async {
    temp = (await Directory.systemTemp.createTemp('twk_tape_')).path;
    addTearDown(() => Directory(temp).delete(recursive: true));
  });

  /// Runs [body] after the header of a tape of the app, with a clock that
  /// moves by the tape's pauses alone; its exit code, what it said and what
  /// the check reported.
  Future<(int, List<String>, List<String>)> run(
    String body, {
    String run = '',
    bool check = true,
  }) async {
    final said = <String>[];
    final reported = <String>[];
    final runner = TapeRunner(
      Tape.parse(
        'Set Width 30\nSet Height 6\nSet WaitTimeout 60s\n'
        '${run.isEmpty ? 'Run "${Platform.resolvedExecutable}" "$app"' : run}\n'
        '$body',
        name: 't.tape',
      ),
      log: said.add,
      report: reported.add,
      check: check,
      clock: _Steps(),
    );
    final ran = runner.run();
    addTearDown(() async {
      runner.stop(130);
      await waitFor(ran.then((_) {}, onError: (_) {}), 'the tape to stop');
    });
    return (await ran, said, reported);
  }

  test('waits for a widget and for text in the app, clicks a button, and the '
      'tap reaches it', () async {
    final (code, said, reported) = await run('''
Wait Widget Button
Wait Text "Saved: 0"
Click "Save"
Wait Text "Saved: 1"
Click@10ms "Save"
Wait /Saved: 2/
''');

    expect(code, 0, reason: '$said');
    expect(reported, [
      't.tape:3: ok Set WaitTimeout 60s',
      't.tape:5: ok Wait Widget Button',
      't.tape:6: ok Wait Text "Saved: 0"',
      't.tape:7: ok Click "Save"',
      't.tape:8: ok Wait Text "Saved: 1"',
      't.tape:9: ok Click@10ms "Save"',
      't.tape:10: ok Wait /Saved: 2/',
      't.tape: passed, 7 statements',
    ]);
  });

  test('records a tape of an app: the click shows in the recording', () async {
    final cast = p.join(temp, 't.cast');
    final (code, said, _) = await run('''
Output $cast
Wait Text "Saved: 0"
Click "Save"
Wait Text "Saved: 1"
''', check: false);

    expect(code, 0, reason: '$said');
    final recorded = Cast.read(cast);
    final frames = screenFrames(
      recorded.header.width,
      recorded.header.height,
      recorded.writes,
    );
    String screen(ScreenFrame f) => f.lines.join('\n');
    final before = frames.indexWhere((f) => screen(f).contains('Saved: 0'));
    expect(before, greaterThanOrEqualTo(0));
    expect(screen(frames.last), contains('Saved: 1'));
    expect(
      frames.take(before).any((f) => screen(f).contains('Saved: 1')),
      isFalse,
    );
  });

  test('a click on a covered widget fails saying what covers it; a wait for '
      'a widget the app lacks times out with the screen', () async {
    final (code, said, reported) = await run('''
Wait Widget Button
Click "Under"
''');

    expect(code, 1);
    expect(said.single, startsWith('twk tape: t.tape:6: Click "Under": '));
    expect(said.single, contains('is covered by Text'));
    expect(reported.last, 't.tape: failed, 2 of 3 statements passed');

    final (late, lateSaid, _) = await run('Wait@300ms Widget Nope\n');
    expect(late, 1);
    expect(
      lateSaid.single,
      allOf(
        startsWith(
          'twk tape: t.tape:5: Wait timed out after 0.3s for Widget Nope; '
          'the screen:\n│',
        ),
        contains('Saved: 0'),
      ),
    );
  });

  test('a program that is no twk app has no widgets to wait for or click: '
      'both fail saying so', () async {
    final (code, said, _) = await run(
      'Wait Widget Button\n',
      run: 'Run cat',
    );
    expect(code, 1);
    expect(said.single, contains('not a twk app'));

    final (click, clickSaid, _) = await run('Click "Save"\n', run: 'Run cat');
    expect(click, 1);
    expect(clickSaid.single, contains('not a twk app'));
  });
}

/// Time that goes on by the tape's pauses alone, each at once.
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
