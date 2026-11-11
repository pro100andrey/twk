// `twk record --replay`: what a recording typed typed into a live command,
// in a terminal of the test's (see terminal.dart): the tally of a recorded
// session reaches the recorded screen, the terminal's answers are not
// typed again, the person's keys wait until the replay is over, and the
// command is hung up when the replay is to end.
@Tags(['process'])
@TestOn('linux || mac-os')
@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk_dev/src/replay.dart';
import 'package:twk_dev/twk_dev.dart';
import 'package:twk_test/twk_test.dart' show screenFrames;

import 'terminal.dart';
import 'twk.dart';

final String _dart = Platform.resolvedExecutable;

void main() {
  late String tally;
  setUpAll(() async {
    await compileTwk();
    tally = await compiled('example/tally.dart');
  });

  late String temp;
  setUp(() async {
    temp = (await Directory.systemTemp.createTemp('twk_replay_')).path;
    addTearDown(() => Directory(temp).delete(recursive: true));
  });

  /// A recording by hand: [events] of a terminal of 60 by 14.
  String cast(List<CastEvent> events) {
    final path = p.join(temp, 'in.cast');
    File(path).writeAsStringSync(
      '${jsonEncode(const CastHeader(width: 60, height: 14).toJson())}\n'
      '${events.map((e) => '${e.encode()}\n').join()}',
    );
    return path;
  }

  test('a replayed tally session reaches the recorded screen, and the '
      'answers it recorded are not typed again', () async {
    final first = p.join(temp, 'first.cast');
    final t = await Terminal.twk([
      'record', '--keys', '--out=$first', '--', _dart, tally, //
    ]);
    await t.until(() => t.lines.any((l) => l.contains('q quit')), 'tally');
    t.type('+');
    await t.until(
      () => t.lines.any((l) => l.contains('› coffee     1 ■')),
      'coffee counted',
    );
    t.type('+');
    await t.until(
      () => t.lines.any((l) => l.contains('› coffee     2 ■')),
      'coffee counted twice',
    );
    t.type('q');
    expect(await t.ended(), exits(0));
    final recorded = Cast.read(first);
    // the emulator of the test answered the app's queries: they are in it
    final typed = recorded.events
        .where((e) => e.code == CastEvent.input)
        .map((e) => e.data)
        .join();
    expect(typed, matches(RegExp(r'\x1b\[\?[\d;]*\$y')));

    final second = p.join(temp, 'second.cast');
    final r = await Terminal.twk([
      'record', '--keys', '--out=$second', '--replay=$first', //
      '--replay-speed=asap', '--', _dart, tally, //
    ]);
    expect(await r.ended(), exits(0));
    expect(r.text, contains('twk record: replaying 3 inputs'));

    final replayed = Cast.read(second);
    List<List<String>> screens(Cast c) => [
      for (final f in screenFrames(c.header.width, c.header.height, c.writes))
        f.lines,
    ];
    final want = screens(recorded);
    final got = screens(replayed);
    for (final mark in ['coffee     1 ■ ', 'coffee     2 ■■']) {
      expect(want.any((s) => s.any((l) => l.contains(mark))), isTrue);
    }
    // The replay reaches the last of them. The one between is not held to:
    // as soon as possible, a key goes once the command has been quiet for
    // Recorder.settle, which a command slow to start is before its first
    // frame, and it then draws the two keys in one frame (the runner of the
    // CI did; one CPU shared with six busy loops does every time).
    expect(
      got.any((s) => s.any((l) => l.contains('coffee     2 ■■'))),
      isTrue,
      reason: '${got.lastOrNull}',
    );
    // the keys typed, once each; the answers in it are the live terminal's
    final splitter = InputSplitter();
    final keys = StringBuffer();
    for (final e in replayed.events) {
      if (e.code == CastEvent.output) {
        splitter.sawOutput(e.data);
      } else if (e.code == CastEvent.input) {
        for (final piece in splitter.add(e.data)) {
          if (!piece.isAnswer) {
            keys.write(piece.text);
          }
        }
      }
    }
    expect('$keys', '++q');
  });

  test("the person's keys wait for the end of the replay, and are the "
      "command's after it", () async {
    final input = cast([
      const CastEvent(0.1, 'o', 'ready\r\n'),
      const CastEvent(0.3, 'i', 'one\r'),
    ]);
    final out = p.join(temp, 'out.cast');
    final t = await Terminal.twk([
      'record', '--out=$out', '--replay=$input', //
      '--', 'sh', '-c',
      r'echo ready; read a; echo "got $a"; read b; echo "got $b"',
    ]);
    await t.until(() => t.text.contains('got one'), 'the replayed line');
    t.type('two\r');
    expect(await t.ended(), exits(0));
    expect(t.text, contains('got two'));
  });

  test('--replay-then=end hangs the command up once it is quiet', () async {
    final input = cast([
      const CastEvent(0.1, 'o', 'ready\r\n'),
      const CastEvent(0.2, 'i', 'hi\r'),
    ]);
    final out = p.join(temp, 'out.cast');
    final t = await Terminal.twk([
      'record', '--out=$out', '--replay=$input', '--replay-speed=4', //
      '--replay-then=end', '--', 'sh', '-c',
      r'echo ready; read a; echo "got $a"; sleep 600',
    ]);
    expect(await t.ended(), exits(0));
    expect(t.text, contains('got hi'));
  });

  test('refuses a replay option without --replay, and a recording it '
      'cannot read', () async {
    final a = await Terminal.twk(['record', '--replay-then=end', '--', 'true']);
    expect(await a.ended(), exits(64));
    final b = await Terminal.twk([
      'record', '--replay=${p.join(temp, 'none.cast')}', '--', 'true', //
    ]);
    expect(await b.ended(), exits(64));
    final c = await Terminal.twk([
      'record', '--replay=${cast([])}', '--replay-speed=0', '--', 'true', //
    ]);
    expect(await c.ended(), exits(64));
  });
}
