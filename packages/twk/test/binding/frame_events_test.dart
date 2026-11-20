// The events a driver syncs on (`ext.twk.flags` `frameEvents`): twk.frame
// after every frame, with the bytes of input the app had taken in when its
// build began and the bytes it wrote; twk.input for what was read or
// dispatched and led to no frame, or not yet.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/log.dart' hide log;
import 'package:twk/log.dart' as twk show log;
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import 'service_extensions_test.dart' show call;

typedef Json = Map<String, Object?>;

/// A count that a key adds one to, or that a key leaves be.
final class _Keys extends StatefulWidget {
  const _Keys({required this.counts});

  final bool counts;

  @override
  State<_Keys> createState() => _KeysState();
}

final class _KeysState extends State<_Keys> {
  var _n = 0;

  @override
  Widget build(BuildContext context) => InputListener(
    onEvent: (event) {
      if (event is KeyEvent && widget.counts) {
        setState(() => _n++);
      }
      return true;
    },
    child: Text('n $_n'),
  );
}

/// A key changes the screen; building it logs, in the frame.
final class _Logs extends StatefulWidget {
  const _Logs();

  @override
  State<_Logs> createState() => _LogsState();
}

final class _LogsState extends State<_Logs> {
  var _n = 0;

  @override
  Widget build(BuildContext context) {
    twk.log('built $_n', level: LogLevel.debug);
    return InputListener(
      onEvent: (event) {
        if (event is KeyEvent) {
          setState(() => _n++);
        }
        return true;
      },
      child: Text('logs $_n'),
    );
  }
}

void main() {
  late List<(String, Json)> posted;
  setUp(() {
    posted = [];
    final post = AppBinding.postEvent;
    AppBinding.postEvent = (kind, [data = const {}]) {
      posted.add((kind, data));
      return true;
    };
    addTearDown(() => AppBinding.postEvent = post);
  });

  Iterable<Json> of(String kind) => [
    for (final (k, d) in posted)
      if (k == kind) d,
  ];

  Future<void> on(TwkTester t) =>
      call(t, 'ext.twk.flags', {'frameEvents': 'true'});

  testTwk('off by default: frames and input post nothing, and the app arms '
      'no timer for input', (t) async {
    await t.pumpWidget(const _Keys(counts: true), size: (10, 2));
    expect(t.binding.debug.frameEvents, isFalse);
    expect(t.binding.twkApp.onInputSettled, isNull);
    await t.press('a');
    await t.pump();
    expect(t.lines.first, startsWith('n 1'));
    expect(posted, isEmpty);
    expect((await call(t, 'ext.twk.flags'))['frameEvents'], isFalse);
  });

  testTwk('twk.log: the records of the log, batched, before the next '
      'event; none while off', (t) async {
    await t.pumpWidget(const _Keys(counts: true), size: (10, 2));
    final logs = t.binding.twkApp.logs;
    void log(String m, {LogLevel level = LogLevel.info, Object? error}) =>
        logs.run(() => twk.log(m, level: level, error: error));
    log('before');
    expect(posted, isEmpty);
    await on(t);
    log('one');
    log('two', level: LogLevel.warning, error: 'boom');
    expect(posted, isEmpty, reason: 'posted from a timer or the next event');
    await t.press('a');
    await t.pump();
    final kinds = [for (final (k, _) in posted) k];
    expect(kinds.first, 'twk.log');
    expect(kinds.where((k) => k == 'twk.log'), hasLength(1));
    final batch = of('twk.log').single;
    expect(batch['version'], 1);
    final records = (batch['records']! as List).cast<Json>();
    expect([for (final r in records) r['message']], ['one', 'two']);
    expect(records[1], containsPair('level', 'warning'));
    expect(records[1], containsPair('error', 'boom'));
    expect(jsonDecode(jsonEncode(batch)), batch);
    // nothing twice
    posted.clear();
    await t.pump();
    expect(of('twk.log'), isEmpty);
  });

  testTwk('twk.log: what a frame logged comes before its twk.frame', (t) async {
    await t.pumpWidget(const _Logs(), size: (10, 2));
    await on(t);
    await t.press('a');
    await t.pump();
    final kinds = [for (final (k, _) in posted) k];
    expect(kinds, contains('twk.frame'));
    expect(kinds.indexOf('twk.log'), lessThan(kinds.indexOf('twk.frame')));
    expect(kinds.where((k) => k == 'twk.log'), hasLength(1));
  });

  testTwk('twk.log: a record outside a frame goes from a timer; off again, '
      'none', (t) async {
    await t.pumpWidget(const _Keys(counts: true), size: (10, 2));
    final logs = t.binding.twkApp.logs;
    void log(String m) => logs.run(() => twk.log(m));
    await on(t);
    log('late');
    await waitUntil(() => of('twk.log').isNotEmpty, 'the log event');
    expect(
      [for (final r in of('twk.log').single['records']! as List) r],
      [containsPair('message', 'late')],
    );
    posted.clear();
    await call(t, 'ext.twk.flags', {'frameEvents': 'false'});
    log('quiet');
    await t.press('a');
    await t.pump();
    expect(posted, isEmpty);
  });

  testTwk('on, a frame posts twk.frame, with the counters of the terminal '
      'and the app', (t) async {
    await t.pumpWidget(const _Keys(counts: true), size: (10, 2));
    expect(
      (await call(t, 'ext.twk.flags', {'frameEvents': 'true'}))['frameEvents'],
      isTrue,
    );
    expect(posted, isEmpty);
    final app = t.binding.twkApp;
    final frames = app.framesRun;
    await t.press('a');
    await t.pump();
    final frame = of('twk.frame').single;
    expect(frame.keys, [
      'version',
      'frame',
      'drawn',
      'quitting',
      'size',
      'inputRead',
      'outputWritten',
      'inputPending',
      'scheduled',
      'frameDue',
      'time',
      'nextDue',
      'stats',
    ]);
    expect(frame['version'], 1);
    expect(frame['frame'], frames + 1);
    expect(frame['drawn'], isTrue);
    expect(frame['size'], {'width': 10, 'height': 2});
    expect(frame['inputRead'], 1, reason: 'the key was read before the frame');
    expect(frame['outputWritten'], t.terminal.bytesWritten);
    expect(frame['quitting'], isFalse);
    expect(frame['inputPending'], isFalse);
    expect(frame['scheduled'], isFalse);
    expect(frame['frameDue'], isNull);
    expect(frame['time'], isA<int>());
    expect(frame['nextDue'], isNull);
    final stats = app.stats;
    expect(frame['stats'], {
      'micros': stats.lastMicros,
      'build': stats.lastBuildMicros,
      'layout': stats.lastLayoutMicros,
      'paint': stats.lastPaintMicros,
      'present': stats.lastPresentMicros,
      'bytes': stats.lastBytes,
    });
    expect(stats.lastBytes, greaterThan(0));
    // everything in it is JSON
    expect(jsonDecode(jsonEncode(frame)), frame);
  });

  testTwk('a frame that wrote nothing is posted too, undrawn', (t) async {
    await t.pumpWidget(const _Keys(counts: true), size: (10, 2));
    await on(t);
    t.binding.twkApp.requestFrame();
    await t.pump();
    final frame = of('twk.frame').single;
    expect(frame['drawn'], isFalse);
    expect(frame['outputWritten'], t.terminal.bytesWritten);
    expect(frame.containsKey('stats'), isTrue);
    expect(frame['stats'], isNull);
    expect(jsonDecode(jsonEncode(frame)), frame);
  });

  testTwk('a key that changes nothing is acknowledged by twk.input, with no '
      'frame', (t) async {
    await t.pumpWidget(const _Keys(counts: false), size: (10, 2));
    await on(t);
    final frames = t.binding.twkApp.framesRun;
    await t.press('a');
    await t.pump();
    await waitUntil(() => of('twk.input').isNotEmpty, 'twk.input');
    expect(of('twk.frame'), isEmpty);
    final ack = of('twk.input').first;
    expect(ack['inputRead'], 1);
    expect(ack['frame'], frames);
    expect(ack.containsKey('stats'), isFalse);
    expect(ack['drawn'], isFalse);
    expect(ack['scheduled'], isFalse);
  });

  testTwk('a resize is acknowledged with its size', (t) async {
    await t.pumpWidget(const _Keys(counts: true), size: (10, 2));
    await on(t);
    await t.resize(12, 3);
    await t.pump();
    await waitUntil(() => of('twk.input').isNotEmpty, 'twk.input');
    expect(of('twk.input').first['size'], {'width': 12, 'height': 3});
    expect(of('twk.input').first['inputRead'], 0, reason: 'no byte was read');
  });

  testTwk('a lone ESC is pending in what the read of it posts', (t) async {
    await t.pumpWidget(const _Keys(counts: false), size: (10, 2));
    await on(t);
    await t.press('escape');
    await waitUntil(() => of('twk.input').isNotEmpty, 'twk.input');
    final acks = of('twk.input').toList();
    expect(acks.first['inputRead'], 1);
    expect(acks.first['inputPending'], isTrue);
    await waitUntil(() => of('twk.input').length >= 2, 'the Escape key');
    expect(of('twk.input').last['inputPending'], isFalse);
  });

  testTwk('turning the flag off stops the posts and the timer', (t) async {
    await t.pumpWidget(const _Keys(counts: true), size: (10, 2));
    await on(t);
    await call(t, 'ext.twk.flags', {'frameEvents': 'false'});
    expect(t.binding.twkApp.onInputSettled, isNull);
    await t.press('a');
    await t.pump();
    expect(posted, isEmpty);
  });

  testTwk('the app ending turns the events and their listeners off', (t) async {
    await t.pumpWidget(const _Keys(counts: true), size: (10, 2));
    await on(t);
    final app = t.binding.twkApp;
    addTearDown(() async {
      expect(t.binding.debug.frameEvents, isFalse);
      expect(app.onInputSettled, isNull);
      posted.clear();
      app.logs.run(() => twk.log('after the app'));
      await pumpEventQueue();
      expect(posted, isEmpty);
    });
  });

  testTwk('ext.twk.status answers what twk.frame carries, changes nothing '
      'and posts nothing', (t) async {
    await t.pumpWidget(const _Keys(counts: true), size: (10, 2));
    final app = t.binding.twkApp;
    final frames = app.framesRun;
    final status = await call(t, 'ext.twk.status');
    expect(status.keys, [
      'version',
      'frame',
      'quitting',
      'size',
      'inputRead',
      'outputWritten',
      'inputPending',
      'scheduled',
      'frameDue',
      'time',
      'nextDue',
    ]);
    expect(status['version'], 1);
    expect(status['frame'], frames);
    expect(status['size'], {'width': 10, 'height': 2});
    expect(status['outputWritten'], t.terminal.bytesWritten);
    expect(status['quitting'], isFalse);
    expect(status['nextDue'], isNull);
    // asked again: the same, no frame run, nothing posted, the flag as it was
    expect(await call(t, 'ext.twk.status'), status);
    expect(app.framesRun, frames);
    expect(posted, isEmpty);
    expect(t.binding.debug.frameEvents, isFalse);
    expect(AppBinding.serviceExtensions, contains('ext.twk.status'));
  });

  testTwk('ext.twk.status samples the input read afresh, with no event '
      'posted', (t) async {
    await t.pumpWidget(const _Keys(counts: false), size: (10, 2));
    final before = (await call(t, 'ext.twk.status'))['inputRead']! as int;
    await t.press('a');
    final after = (await call(t, 'ext.twk.status'))['inputRead']! as int;
    expect(after, before + 1);
  });
}
