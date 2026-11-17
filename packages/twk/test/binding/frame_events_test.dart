// The events a driver syncs on (`ext.twk.flags` `frameEvents`): twk.frame
// after every frame, with the bytes of input the app had taken in when its
// build began and the bytes it wrote; twk.input for what was read or
// dispatched and led to no frame, or not yet.
import 'dart:convert';

import 'package:test/test.dart';
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
      'size',
      'inputRead',
      'outputWritten',
      'inputPending',
      'scheduled',
      'frameDue',
      'time',
      'nextDue',
    ]);
    expect(frame['version'], 1);
    expect(frame['frame'], frames + 1);
    expect(frame['drawn'], isTrue);
    expect(frame['size'], {'width': 10, 'height': 2});
    expect(frame['inputRead'], 1, reason: 'the key was read before the frame');
    expect(frame['outputWritten'], t.terminal.bytesWritten);
    expect(frame['inputPending'], isFalse);
    expect(frame['scheduled'], isFalse);
    expect(frame['frameDue'], isNull);
    expect(frame['time'], isA<int>());
    expect(frame['nextDue'], isNull);
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
}
