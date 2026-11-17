// `twk.scheduled`: what a driven app tells a driver when something outside a
// step of the driver asks for a frame or changes its timers (a child's
// answer, a socket), which no frame and no read of input says. The app
// runs for real on a headless terminal and a driven clock; nothing waits on
// the wall.
//
// The timers this file starts are the subject: they run on the driven clock.
// ignore_for_file: twk_lints/wall_time_in_tests

import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/src/binding/driven_start.dart';
import 'package:twk/twk.dart';

typedef Json = Map<String, Object?>;

late _CountState _state;

/// A count that a key, a timer of the app and the test (from outside) add
/// to.
final class _Count extends StatefulWidget {
  const _Count();

  @override
  State<_Count> createState() => _CountState();
}

final class _CountState extends State<_Count> {
  var n = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _state = this;
  }

  void bump() => setState(() => n++);

  @override
  Widget build(BuildContext context) => InputListener(
    onEvent: (event) {
      if (event is KeyEvent) {
        bump();
      }
      return true;
    },
    child: Text('n $n'),
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

  Future<(AppBinding, HeadlessTerminal, DrivenStart?)> launch({
    bool driven = true,
    bool events = true,
  }) async {
    final start = driven
        ? DrivenStart.of(environment: {'TWK_DRIVEN': '42'}, parentPid: 42)
        : null;
    final term = HeadlessTerminal(width: 20, height: 3);
    Future<AppBinding> make() async {
      final binding = AppBinding(
        term,
        clock: start?.clock,
        startTime: start?.startTime,
      );
      unawaited(binding.run(const _Count()));
      return binding;
    }

    final binding = await (start == null ? make() : start.zone.run(make));
    addTearDown(binding.quit);
    for (var i = 0; i < 1000 && binding.twkApp.framesRun == 0; i++) {
      await pumpEventQueue(times: 1);
    }
    await binding.twkApp.frameEnd;
    if (events) {
      final r = await binding.callServiceExtension('ext.twk.flags', {
        'frameEvents': 'true',
      });
      expect(r.isError(), isFalse);
    }
    posted.clear();
    return (binding, term, start);
  }

  test('a frame asked for from outside a step is told, once for the turn '
      'whatever number of timers it started', () async {
    final (binding, _, start) = await launch();
    _state
      ..bump()
      ..bump();
    expect(of('twk.scheduled'), isEmpty, reason: 'after the turn, not in it');
    await pumpEventQueue();
    final e = of('twk.scheduled').single;
    expect(e['scheduled'], isTrue);
    expect(e['frame'], binding.twkApp.framesRun);
    expect(e['time'], 0);
    expect(e['nextDue'], isNotNull);
    expect(e['frameDue'], binding.twkApp.frameDue);
    expect(e['inputRead'], 0);
    expect(of('twk.frame'), isEmpty, reason: 'the clock stands');
    start!.clock.advance(const Duration(seconds: 1));
  });

  test('a timer the app starts or cancels outside a step is told', () async {
    final (_, _, start) = await launch();
    final timer = start!.zone.run(
      () => Timer(const Duration(seconds: 5), () {}),
    );
    await pumpEventQueue();
    expect(of('twk.scheduled').single['nextDue'], 5000000);
    posted.clear();
    timer.cancel();
    await pumpEventQueue();
    expect(of('twk.scheduled').single['nextDue'], isNull);
  });

  test("not inside a move of the clock: its answer is the driver's", () async {
    final (binding, _, start) = await launch();
    _state.timer = start!.zone.run(
      () => Timer(const Duration(seconds: 1), _state.bump),
    );
    await pumpEventQueue();
    posted.clear();
    final r = await binding.callServiceExtension('ext.twk.clock', {
      'op': 'advance',
      'by': '2000000',
    });
    expect(r.isError(), isFalse);
    expect(jsonDecode(r.result!), containsPair('frame', 2));
    await pumpEventQueue();
    expect(of('twk.scheduled'), isEmpty);
    expect(of('twk.frame'), isNotEmpty);
  });

  test('not as the acknowledgement of input: a read is told by twk.input or '
      'the frame', () async {
    final (_, term, _) = await launch();
    term.type('a');
    await pumpEventQueue();
    expect(of('twk.scheduled'), isEmpty);
    expect(of('twk.input').followedBy(of('twk.frame')), isNotEmpty);
  });

  test('none while frameEvents is off', () async {
    final (binding, _, _) = await launch(events: false);
    _state.bump();
    await pumpEventQueue();
    expect(posted, isEmpty);
    // and switched on and off again, none, with no timer left armed
    await binding.callServiceExtension('ext.twk.flags', {
      'frameEvents': 'true',
    });
    _state.bump();
    await binding.callServiceExtension('ext.twk.flags', {
      'frameEvents': 'false',
    });
    await pumpEventQueue();
    expect(of('twk.scheduled'), isEmpty);
  });

  test('none on an app that is not driven', () async {
    final (_, _, _) = await launch(driven: false);
    _state.bump();
    await pumpEventQueue();
    expect(of('twk.scheduled'), isEmpty);
  });
}
