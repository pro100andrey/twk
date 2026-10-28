// `twk play` in a terminal of the test's (see terminal.dart): what the
// program wrote, at its times divided by --speed with the pauses cut;
// what is typed meanwhile dropped; Ctrl+C stopping, with what the
// recording left on turned off; the terminal put back.
@TestOn('linux || mac-os')
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'terminal.dart';
import 'twk.dart';

const _header = '{"version": 2, "width": 40, "height": 6';

void main() {
  setUpAll(compileTwk);

  late String temp;
  setUp(() async {
    temp = (await Directory.systemTemp.createTemp('twk_play_')).path;
    addTearDown(() => Directory(temp).delete(recursive: true));
  });

  /// A recording in [temp] with [lines] after the header.
  String cast(String header, List<String> lines) {
    final path = p.join(temp, 's.cast');
    File(path).writeAsStringSync('$header}\n${lines.join('\n')}\n');
    return path;
  }

  test('writes what the program wrote at its times divided by --speed, '
      'every pause cut to the idle limit; nothing else', () async {
    final path = cast('$_header, "idle_time_limit": 0.5', [
      r'[0.1, "o", "first\r\n"]',
      '[0.2, "i", "typed"]',
      r'[3.0, "o", "second\r\n"]',
      '[3.4, "r", "50x8"]',
      r'[3.6, "o", "third\r\n"]',
    ]);
    final t = await Terminal.twk(['play', '--speed=2', path]);
    final before = t.modes;
    await t.until(() => t.text.contains('first'), 'the first event');
    // Real time on purpose: the pauses of playback are what is measured
    final first = Stopwatch()..start();
    await t.until(() => t.text.contains('third'), 'the last event');
    // at 0.1 s, 0.2 s, then 0.5 s (2.8 s cut), 0.4 s and 0.2 s: 1.2 s, by 2,
    // 0.55 s after the first; less when the test sees the first late, as on
    // a busy machine, but never near none (no pauses) nor past 1.1 s (no
    // speed, or no cut)
    final took = first.elapsedMilliseconds;

    expect(await t.ended(), exits(0));
    expect(took, inInclusiveRange(300, 1100));
    expect(t.text, 'first\r\nsecond\r\nthird\r\n');
    expect(t.modes.same(before), isTrue, reason: '${t.modes}');
  });

  test('stops on Ctrl+C, turning off what the recording left on', () async {
    final path = cast(_header, [
      r'[0.0, "o", "\u001b[?1049h\u001b[?1000h\u001b[?25lplaying"]',
      '[60.0, "o", "never"]',
    ]);
    final t = await Terminal.twk(['play', path]);
    final before = t.modes;
    await t.until(() => t.text.contains('playing') && t.modes.raw, 'playing');
    t.type('x\x03');

    expect(await t.ended(), exits(130));
    expect(
      t.text,
      endsWith('playing\x1b[0m\x1b[?1000l\x1b[?25h\x1b[?1049l'),
    );
    expect(t.screen.alternateScreen, isFalse);
    expect(t.modes.same(before), isTrue, reason: '${t.modes}');
  });

  test(
    'what is typed while it plays does not reach the shell after it',
    () async {
      final path = cast(_header, [
        r'[0.0, "o", "playing\r\n"]',
        r'[0.6, "o", "done\r\n"]',
      ]);
      final t = await Terminal.start('sh', [
        '-c',
        r'"$0" "$1" play "$2"; echo ready; read x; echo "after:$x"',
        Platform.resolvedExecutable,
        twkProgram,
        path,
      ]);
      await t.until(() => t.text.contains('playing') && t.modes.raw, 'playing');
      t.type('typed');
      await t.until(() => t.text.contains('ready'), 'the shell');
      t.type('line\r');

      expect(await t.ended(), exits(0));
      expect(t.text, contains('after:line\r\n'));
      expect(t.text, isNot(contains('typed')));
    },
  );
}
