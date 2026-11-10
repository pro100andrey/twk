// `twk play`'s controls on a fake terminal and a fake clock: Space
// pauses and plays on, Right a frame on, Left a frame back (the terminal
// reset and the frames before written at once), Home from the start, q
// quits; a frame is what twk_test's screenFrames takes for one; the
// status line is under the recording, shown paused and wiped after,
// never part of what is played.

import 'dart:async';

import 'package:test/test.dart';
import 'package:twk_dev/src/cast.dart';
import 'package:twk_dev/src/play.dart';
import 'package:twk_test/twk_test.dart' show screenFrames;

const _up = '\x1b[?2026h';
const _down = '\x1b[?2026l';
const _right = '\x1b[C';
const _left = '\x1b[D';
const _home = '\x1b[H';

/// Three frames: `A`, then `B` and `C` in one update, then `D`; and `E`
/// inside an update never ended, which is no frame.
final String _text = [
  '{"version": 2, "width": 40, "height": 6}',
  '[0.0, "o", "A"]',
  '[1.0, "o", "${r'\u001b'}[?2026hB"]',
  '[1.1, "o", "C${r'\u001b'}[?2026l"]',
  '[2.0, "o", "D"]',
  '[2.5, "i", "x"]',
  '[3.0, "o", "${r'\u001b'}[?2026hE"]',
].join('\n');

/// Time that moves only when the test says.
final class _Clock extends PlayClock {
  Duration _now = Duration.zero;
  final _waiting = <(Duration, Completer<void>)>[];

  @override
  Duration get elapsed => _now;

  @override
  Future<void> pause(Duration duration, Future<void> stop) async {
    final due = (_now + duration, Completer<void>());
    _waiting.add(due);
    await Future.any([due.$2.future, stop]);
    _waiting.remove(due);
  }

  Future<void> elapse(double seconds) async {
    _now += Duration(microseconds: (seconds * 1e6).round());
    for (final (due, done) in [..._waiting]) {
      if (due <= _now && !done.isCompleted) {
        done.complete();
      }
    }
    await _settle();
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _Run {
  _Run(String text, {int rows = 10, double speed = 1, double? idleLimit}) {
    final cast = Cast.parse(text);
    player = Player(
      cast,
      speed: speed,
      idleLimit: idleLimit,
      output: (s) async => writes.add(s),
      keys: keys.stream,
      rows: rows,
      clock: clock,
    );
    result = player.run().then((code) => exit = code);
  }

  late final Player player;
  late final Future<int> result;
  final clock = _Clock();
  final keys = StreamController<List<int>>();
  final writes = <String>[];
  int? exit;

  /// The writes since [mark], and the mark after them.
  List<String> since(int mark) => writes.sublist(mark);

  Future<void> type(String text) async {
    keys.add(text.codeUnits);
    await _settle();
  }

  /// The program's output, without the status line.
  String get played => writes.where((w) => !w.startsWith('\x1b7')).join();

  /// The last status line, or null.
  String? get status => writes.lastWhere(
    (w) => w.startsWith('\x1b7\x1b[7;1H') && w.contains('paused'),
    orElse: () => '',
  );
}

void main() {
  Future<_Run> started([String? text, int rows = 10]) async {
    final r = _Run(text ?? _text, rows: rows);
    await _settle();
    addTearDown(() async {
      if (r.exit == null) {
        await r.type('q');
      }
      await r.keys.close();
    });
    return r;
  }

  test('plays by the clock, an update written at the time it ends', () async {
    final r = await started();
    expect(r.writes, ['A']);
    await r.clock.elapse(1.05);
    expect(r.writes, ['A'], reason: 'B is inside an update not ended');
    await r.clock.elapse(0.05);
    expect(r.writes, ['A', '${_up}BC$_down']);
    await r.clock.elapse(0.9);
    expect(r.writes.last, 'D');
    await r.clock.elapse(1);
    expect(r.played, endsWith('${_up}E'));
    // keys are read: it stays at the end, paused
    expect(r.exit, isNull);
    expect(r.status, contains('paused  frame 3/3'));
    await r.type('q');
    expect(await r.result, 0);
  });

  test('a frame is what screenFrames takes for one', () async {
    final cast = Cast.parse(_text);
    final frames = screenFrames(
      cast.header.width,
      cast.header.height,
      cast.writes,
    ).length;
    expect(frames, 3);
    final r = await started();
    await r.type(' ');
    expect(r.status, contains('frame 1/$frames'));
    await r.type(_right);
    await r.type(_right);
    await r.type(_right);
    expect(r.status, contains('frame $frames/$frames'));
    // E is a step of its own, no frame: shown, the count stays
    await r.type(_right);
    expect(r.played, endsWith('${_up}E'));
    expect(r.status, contains('frame $frames/$frames'));
  });

  test('Space pauses with a status line under the recording, plays on '
      'from there, wiping it', () async {
    final r = await started();
    await r.clock.elapse(0.5);
    await r.type(' ');
    expect(
      r.writes.last,
      '\x1b7\x1b[7;1H\x1b[2K\x1b[7m paused  frame 1/3  0.000 s / 3.000 s '
      '\x1b[0m\x1b8',
    );
    final mark = r.writes.length;
    await r.clock.elapse(10);
    expect(r.since(mark), isEmpty, reason: 'nothing plays paused');

    await r.type(' ');
    expect(r.writes.last, '\x1b7\x1b[7;1H\x1b[2K\x1b8');
    expect(r.played, 'A');
    await r.clock.elapse(1);
    expect(r.played, 'A');
    await r.clock.elapse(0.1);
    expect(r.played, 'A${_up}BC$_down');
    expect(r.status, contains('frame 1/3'), reason: 'the status is not live');
  });

  test('Right shows the next frame paused, Left the one before: the '
      'terminal reset and the frames before written at once', () async {
    final r = await started();
    await r.clock.elapse(1.1);
    expect(r.played, 'A${_up}BC$_down');
    await r.type(_right);
    expect(r.played, 'A${_up}BC${_down}D');
    expect(r.status, contains('frame 3/3  2.000 s'));

    final mark = r.writes.length;
    await r.type(_left);
    expect(r.since(mark).where((w) => w.startsWith('\x1bc')), [
      '\x1bcA${_up}BC$_down',
    ]);
    expect(r.status, contains('frame 2/3  1.100 s'));
    await r.type(_left);
    expect(r.writes.where((w) => w.startsWith('\x1bc')).last, '\x1bcA');
    await r.type(_left);
    expect(r.writes.where((w) => w.startsWith('\x1bc')).last, '\x1bc');
    expect(r.status, contains('frame 0/3  0.000 s'));
    await r.type(_left);
    await r.type(_right);
    expect(r.writes.last, contains('frame 1/3'));
  });

  test('Left while playing pauses; Home plays from the start', () async {
    final r = await started();
    await r.clock.elapse(2);
    await r.type(_left);
    expect(r.status, contains('paused  frame 2/3'));
    final mark = r.writes.length;
    await r.type(_home);
    expect(r.since(mark).take(2), ['\x1b7\x1b[7;1H\x1b[2K\x1b8', '\x1bc']);
    expect(r.played.endsWith('\x1bcA'), isTrue, reason: r.played);
    await r.clock.elapse(1.1);
    expect(r.played.endsWith('A${_up}BC$_down'), isTrue);
  });

  test('Space after the end plays again from the start', () async {
    final r = await started();
    await r.clock.elapse(3);
    expect(r.exit, isNull, reason: 'stays at the end');
    // Space from the end plays from the start
    await r.type(' ');
    expect(r.played.endsWith('\x1bcA'), isTrue);
    final paused = await started();
    await paused.type(_right);
    await paused.type(_right);
    await paused.type(_right);
    await paused.type(_right);
    await paused.type(' ');
    expect(paused.writes.where((w) => w.startsWith('\x1bc')), ['\x1bc']);
    await paused.clock.elapse(0);
    expect(paused.played.endsWith('\x1bcA'), isTrue);
  });

  test('application cursor keys and kitty keys do as the plain ones', () async {
    final again = await started();
    await again.type(' ');
    await again.type('\x1bOC');
    expect(again.status, contains('frame 2/3'));
    await again.type('\x1bOD');
    expect(again.status, contains('frame 1/3'));
    await again.type('\x1b[32u');
    expect(again.writes.last, '\x1b7\x1b[7;1H\x1b[2K\x1b8');
    await again.type('\x1b[113u');
    expect(await again.result, 0);
  });

  test('q stops with 0 and turns off what the recording left on; '
      'Ctrl+C with 130', () async {
    final text = _text.replaceFirst('"A"', r'"\u001b[?1049h\u001b[?25lA"');
    final q = await started(text);
    await q.type(' ');
    await q.type('q');
    expect(await q.result, 0);
    expect(
      q.writes.last,
      allOf(contains('\x1b[?25h'), endsWith('\x1b[?1049l')),
    );
    expect(
      q.writes[q.writes.length - 2],
      '\x1b7\x1b[7;1H\x1b[2K\x1b8',
      reason: 'the status wiped first',
    );

    final c = await started(text);
    await c.type('\x03');
    expect(await c.result, 130);
    expect(c.writes.last, endsWith('\x1b[?1049l'));
  });

  test('no status line where the terminal has no row under the '
      'recording', () async {
    final r = await started(null, 6);
    await r.type(' ');
    await r.type(_right);
    expect(r.writes, ['A', '${_up}BC$_down']);
  });

  test(
    'the pauses are cut to the idle limit and divided by the speed',
    () async {
      final r = _Run(_text, speed: 2, idleLimit: 0.25);
      addTearDown(() async {
        await r.type('q');
        await r.keys.close();
      });
      await _settle();
      // A at 0, BC at 0.25 + 0.1, D at 0.25 more, divided by 2
      await r.clock.elapse(0.17);
      expect(r.played, 'A');
      await r.clock.elapse(0.01);
      expect(r.played, 'A${_up}BC$_down');
      await r.clock.elapse(0.125);
      expect(r.played.endsWith('D'), isTrue);
    },
  );

  group('readPlayKeys', () {
    void reads(
      String typed,
      List<PlayKey> keys, [
      String rest = '',
      bool continued = false,
    ]) {
      final (read, left) = readPlayKeys(typed, continued: continued);
      expect(read, keys);
      expect(left, rest);
    }

    test('keys, and none in what the terminal answers', () {
      reads(' q\x1b[C\x1b[D\x1b[H\x03', [
        PlayKey.toggle,
        PlayKey.quit,
        PlayKey.next,
        PlayKey.previous,
        PlayKey.start,
        PlayKey.interrupt,
      ]);
      reads('\x1b[?2026;2\$y\x1b[?1;2c\x1b[>0;10;1c', []);
      reads('\x1bP1\$r0 q\x1b\\\x1b]11;rgb:0/0/0\x07 ', [PlayKey.toggle]);
      reads('\x1b[32;1:3u\x1b[1;2C', [PlayKey.next]);
    });

    test('a release is no key, in any form', () {
      reads('\x1b[1;1:3C\x1b[1;1:3D\x1b[1;1:3H\x1b[1;1:3~', []);
      reads('\x1b[1;1:1C\x1b[1;1:2C', [PlayKey.next, PlayKey.next]);
      reads('\x1b[113;1:3u\x1b[99;5:3u\x1b[113;1:1u', [PlayKey.quit]);
    });

    test('Ctrl+C quits after a lone Escape or an unended string', () {
      reads('\x1b\x03', [PlayKey.interrupt]);
      reads('\x1bP\x03', [PlayKey.interrupt]);
      reads('\x1b]xx\x03q', [PlayKey.interrupt, PlayKey.quit]);
      reads('\x1b[1\x03', [PlayKey.interrupt]);
    });

    test('a lone Escape is dropped, not held for the next piece', () {
      reads('\x1b', []);
      reads('q\x1b', [PlayKey.quit]);
    });

    test('a string not ended by the next piece is given up', () {
      reads('\x1bPq', [], '\x1bPq');
      reads('\x1bPq q', [PlayKey.quit, PlayKey.toggle, PlayKey.quit], '', true);
    });

    test('a sequence cut between two pieces is put together', () {
      reads('\x1b[?1;', [], '\x1b[?1;');
      reads('\x1bP1\$r0', [], '\x1bP1\$r0');
      reads('q\x1bP1\$r0', [PlayKey.quit], '\x1bP1\$r0');
      reads('\x1bP1\$r0 q\x1b\\', []);
    });
  });
}
