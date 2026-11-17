// An app on a driver's time: TWK_DRIVEN taken only from the parent it names,
// the zone whose timers go to the driven clock, and ext.twk.clock moving
// that clock. The app runs for real (a binding on a headless terminal, in
// the zone `DrivenStart` makes), and what the test waits for is the app's
// own events, never the wall clock.
//
// The timers this file starts (`Timer`, `Future.delayed`) are the subject:
// they run on the driven clock, the wall is never waited for.
// ignore_for_file: twk_lints/wall_time_in_tests
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/cli.dart' show CliTerminal;
import 'package:twk/src/binding/driven_start.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/libc.dart' show getppid;
import 'package:twk_test/twk_test.dart' show Vt;

typedef Json = Map<String, Object?>;

/// A count that a periodic timer of the app adds one to, every second.
final class _Ticks extends StatefulWidget {
  const _Ticks();

  @override
  State<_Ticks> createState() => _TicksState();
}

final class _TicksState extends State<_Ticks> {
  var _n = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = AppBinding.of(context).startPeriodic(
      const Duration(seconds: 1),
      (_) => setState(() => _n++),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('tick $_n');
}

/// A count that a raw `Future.delayed` of the app's own code adds one to.
final class _Delayed extends StatefulWidget {
  const _Delayed();

  @override
  State<_Delayed> createState() => _DelayedState();
}

final class _DelayedState extends State<_Delayed> {
  var _n = 0;

  @override
  void initState() {
    super.initState();
    unawaited(
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _n = 1);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) => Text('delayed $_n');
}

/// A binding running an app on a headless terminal, driven by the clock of
/// its start, or on real time without one.
final class _Run {
  _Run._(this.binding, this.term, this.done, this.start);

  static Future<_Run> of(Widget app, {bool driven = true}) async {
    final start = driven
        ? DrivenStart.of(
            environment: {'TWK_DRIVEN': '42'},
            parentPid: 42,
          )
        : null;
    final term = HeadlessTerminal(width: 20, height: 3);
    Future<_Run> make() async {
      final binding = AppBinding(
        term,
        clock: start?.clock,
        startTime: start?.startTime,
      );
      return _Run._(binding, term, binding.run(app), start);
    }

    final run = await (start == null ? make() : start.zone.run(make));
    // the first frame is due at once: the clock wakes itself for it
    await run.until((_) => run.binding.twkApp.framesRun > 0);
    await run.binding.twkApp.frameEnd;
    return run;
  }

  final AppBinding binding;
  final HeadlessTerminal term;
  final Future<void> done;
  final DrivenStart? start;

  DrivenClock get clock => start!.clock;

  Future<Json> call(
    String method, [
    Map<String, String> params = const {},
  ]) async {
    final response = await binding.callServiceExtension(method, params);
    if (response.isError()) {
      throw StateError(
        '$method: ${response.errorCode} ${response.errorDetail}',
      );
    }
    return jsonDecode(response.result!) as Json;
  }

  Future<(int, String)> failure(
    String method,
    Map<String, String> params,
  ) async {
    final response = await binding.callServiceExtension(method, params);
    expect(response.isError(), isTrue);
    final detail = jsonDecode(response.errorDetail!) as Json;
    return (response.errorCode!, detail['message']! as String);
  }

  /// Lets the event loop turn until [test] holds: what the app does by
  /// itself, with no clock of the wall in it.
  Future<void> until(bool Function(_Run) test) async {
    for (var i = 0; i < 1000 && !test(this); i++) {
      await pumpEventQueue(times: 1);
    }
    expect(test(this), isTrue, reason: 'the app did not get there');
  }

  String get text {
    final vt = Vt(term.width, term.height);
    term.frames.forEach(vt.feed);
    return vt.lines.join('\n');
  }

  Future<void> quit() async {
    binding.quit();
    await done;
  }
}

void main() {
  group('DrivenStart.of', () {
    DrivenStart? of(Map<String, String> env, {int parent = 42}) =>
        DrivenStart.of(environment: env, parentPid: parent);

    test('is taken from the parent the value names, and only from it', () {
      expect(of({}), isNull);
      expect(of({'TWK_DRIVEN': ''}), isNull);
      expect(of({'TWK_DRIVEN': '42'}), isNotNull);
      // a program the driven app started inherits the variable, and its
      // parent is the app: real time
      expect(of({'TWK_DRIVEN': '42'}, parent: 43), isNull);
      // and so does the program of a `dart run` that put a process between
      expect(of({'TWK_DRIVEN': '42@2026-05-06T07:08:09Z'}, parent: 99), isNull);
    });

    test('names the start time, or the time now', () {
      final named = of({'TWK_DRIVEN': '42@2026-05-06T07:08:09Z'})!;
      expect(named.startTime, DateTime.utc(2026, 5, 6, 7, 8, 9));
      final before = DateTime.now();
      final now = of({'TWK_DRIVEN': '42'})!.startTime;
      expect(now.isBefore(before), isFalse);
    });

    test('a value that names the parent and is no value is refused', () {
      expect(
        () => of({'TWK_DRIVEN': '42@nonsense'}),
        throwsA(isA<FormatException>()),
      );
      expect(() => of({'TWK_DRIVEN': 'me'}), throwsA(isA<FormatException>()));
    });

    test('is ignored in product mode', () {
      expect(
        DrivenStart.of(
          environment: {'TWK_DRIVEN': '42'},
          parentPid: 42,
          product: true,
        ),
        isNull,
      );
    });

    test('the process reads its own parent: an id nobody is is not taken', () {
      // this test process's parent is not pid 1's child of the same id
      expect(
        DrivenStart.of(
          environment: {'TWK_DRIVEN': '2147483647'},
        ),
        isNull,
      );
    });

    test('its zone gives the clock the timers of the app code', () async {
      final start = of({'TWK_DRIVEN': '42'})!;
      final fired = <String>[];
      start.zone.run(() {
        Timer(const Duration(seconds: 2), () => fired.add('timer'));
        Timer.periodic(
          const Duration(seconds: 1),
          (t) => fired.add('periodic${t.tick}'),
        );
        unawaited(
          Future<void>.delayed(
            const Duration(seconds: 3),
            () => fired.add('delayed'),
          ),
        );
      });
      expect(start.clock.pendingTimers, 3);
      await pumpEventQueue();
      expect(fired, isEmpty, reason: 'nothing runs without the clock moving');
      start.clock.advance(const Duration(seconds: 3));
      expect(fired, [
        'periodic1',
        'timer',
        'periodic2',
        // due together, in the order they were started
        'delayed',
        'periodic3',
      ]);
    });

    test('a timer whose callback throws ends in the zone it was made in', () {
      final start = of({'TWK_DRIVEN': '42'})!;
      final errors = <Object>[];
      start.zone
          .fork(
            specification: ZoneSpecification(
              handleUncaughtError: (_, _, _, error, _) => errors.add(error),
            ),
          )
          .run(() => Timer(Duration.zero, () => throw StateError('boom')));
      start.clock.advance(Duration.zero);
      expect(errors, [isA<StateError>()]);
    });
  });

  group('a driven app', () {
    test('runs its first frame by itself and holds still after it', () async {
      final run = await _Run.of(const _Ticks());
      addTearDown(run.quit);
      expect(run.text, contains('tick 0'));
      final status = await run.call('ext.twk.clock');
      expect(status['driven'], isTrue);
      expect(status['time'], 0);
      expect(status['timers'], 1);
      expect(status['nextDue'], 1000000);
      expect(status['quiet'], isFalse);
      // the event loop turns, and the time stays
      await pumpEventQueue();
      expect((await run.call('ext.twk.clock'))['time'], 0);
    });

    test('advance fires the timers in due order, runs the frames they ask '
        'for and leaves the time at the target', () async {
      final run = await _Run.of(const _Ticks());
      addTearDown(run.quit);
      final before = run.binding.twkApp.framesRun;
      final status = await run.call('ext.twk.clock', {
        'op': 'advance',
        'by': '2500000',
      });
      expect(status['time'], 2500000);
      expect(run.text, contains('tick 2'));
      expect(run.binding.twkApp.framesRun, greaterThan(before));
      expect(status['frame'], run.binding.twkApp.framesRun);
      expect(status['nextDue'], 3000000);
      expect(status['scheduled'], isFalse);
    });

    test('advanceTo and next', () async {
      final run = await _Run.of(const _Ticks());
      addTearDown(run.quit);
      var status = await run.call('ext.twk.clock', {'op': 'next'});
      expect(status['time'], 1000000);
      expect(run.text, contains('tick 1'));
      status = await run.call('ext.twk.clock', {
        'op': 'advanceTo',
        'to': '3000000',
      });
      expect(status['time'], 3000000);
      expect(run.text, contains('tick 3'));
      final (_, message) = await run.failure('ext.twk.clock', {
        'op': 'advanceTo',
        'to': '1000',
      });
      expect(message, contains('before'));
    });

    test('a raw Future.delayed of the app is driven too', () async {
      final run = await _Run.of(const _Delayed());
      addTearDown(run.quit);
      expect(run.text, contains('delayed 0'));
      await run.call('ext.twk.clock', {'op': 'advance', 'by': '3000000'});
      expect(run.text, contains('delayed 1'));
    });

    test('quiet is true when no timer waits, no frame is asked for and '
        'nothing is pending; next then stays where it is', () async {
      final run = await _Run.of(const Text('still'));
      addTearDown(run.quit);
      final status = await run.call('ext.twk.clock');
      expect(status['timers'], 0);
      expect(status['nextDue'], isNull);
      expect(status['quiet'], isTrue);
      final next = await run.call('ext.twk.clock', {'op': 'next'});
      expect(next['time'], 0);
      expect(next['quiet'], isTrue);
    });

    test(
      'describe lists the timers by due time and where they began',
      () async {
        final run = await _Run.of(const _Ticks());
        addTearDown(run.quit);
        final status = await run.call('ext.twk.clock', {'describe': 'true'});
        final described = status['describe']! as List<Object?>;
        expect(described, hasLength(1));
        final timer = described.single! as Json;
        expect(timer['due'], 1000000);
        expect(timer['periodic'], isTrue);
        expect(timer['created'], contains('driven_test.dart'));
        expect(
          (await run.call('ext.twk.clock')).containsKey('describe'),
          isFalse,
        );
      },
    );

    test('a second move while one runs is refused, and so are a bad op and '
        'a negative by', () async {
      final run = await _Run.of(const _Ticks());
      addTearDown(run.quit);
      final first = run.call('ext.twk.clock', {
        'op': 'advance',
        'by': '1000000',
      });
      final (_, message) = await run.failure('ext.twk.clock', {
        'op': 'advance',
        'by': '1',
      });
      expect(message, contains('already moving'));
      await first;
      final (_, bad) = await run.failure('ext.twk.clock', {'op': 'skip'});
      expect(bad, contains('op'));
      final (_, negative) = await run.failure('ext.twk.clock', {
        'op': 'advance',
        'by': '-1',
      });
      expect(negative, contains('by'));
    });

    test(
      'status agrees with ext.twk.status, and the events carry nextDue',
      () async {
        final run = await _Run.of(const _Ticks());
        addTearDown(run.quit);
        final plain = await run.call('ext.twk.status');
        final clock = await run.call('ext.twk.clock');
        for (final entry in plain.entries) {
          expect(clock[entry.key], entry.value, reason: entry.key);
        }
        expect(plain['nextDue'], 1000000);
      },
    );

    test(
      'now() reads the start time the driver gave, moved by the clock',
      () async {
        final run = await _Run.of(const _Ticks());
        addTearDown(run.quit);
        final start = run.start!.startTime;
        expect(run.binding.now(), start);
        await run.call('ext.twk.clock', {'op': 'advance', 'by': '2000000'});
        expect(run.binding.now(), start.add(const Duration(seconds: 2)));
      },
    );
  });

  group('an app on real time', () {
    test(
      'answers status as ext.twk.status does, and refuses the moves',
      () async {
        final run = await _Run.of(const Text('real'), driven: false);
        addTearDown(run.quit);
        final status = await run.call('ext.twk.clock');
        expect(status['driven'], isFalse);
        expect(status['timers'], isNull);
        expect(status['nextDue'], isNull);
        expect(status['quiet'], isNull);
        expect(status['time'], isA<int>());
        for (final op in ['advance', 'advanceTo', 'next']) {
          final (_, message) = await run.failure('ext.twk.clock', {
            'op': op,
            'by': '1',
            'to': '1',
          });
          expect(message, 'the app is not driven', reason: op);
        }
      },
    );
  });

  test(
    'ext.twk.reassemble answers the frame last run and the one asked for',
    () async {
      final run = await _Run.of(const _Ticks());
      addTearDown(run.quit);
      final answer = await run.call('ext.twk.reassemble');
      expect(answer['frame'], run.binding.twkApp.framesRun);
      // reassembling asks for a frame, due now or a gap after the last
      expect(answer['frameDue'], isA<int>());
      expect(answer['frameDue'], run.binding.twkApp.frameDue);
    },
  );

  group("the Cli's system terminal", () {
    // this test process's parent stands for the driver
    final parent = getppid();

    test('takes TWK_DRIVEN from the parent it names: a driven clock, the '
        'start time, a zone of its own', () {
      final terminal = CliTerminal.system(
        environment: {'TWK_DRIVEN': '$parent@2026-05-06T07:08:09Z'},
      );
      expect(terminal.clock, isA<DrivenClock>());
      expect(terminal.startTime, DateTime.utc(2026, 5, 6, 7, 8, 9));
      final fired = <int>[];
      terminal.run(() => Timer(const Duration(seconds: 1), () => fired.add(1)));
      expect(fired, isEmpty);
      (terminal.clock as DrivenClock).advance(const Duration(seconds: 1));
      expect(fired, [1]);
    });

    test('is on real time for a parent it does not name, or no variable', () {
      for (final env in [
        <String, String>{},
        {'TWK_DRIVEN': '${parent + 1}'},
      ]) {
        final terminal = CliTerminal.system(environment: env);
        expect(terminal.clock, isNot(isA<DrivenClock>()));
        expect(terminal.startTime, isNull);
      }
    });
  });

  test('the clock extension is registered', () {
    expect(AppBinding.serviceExtensions, contains('ext.twk.clock'));
  });
}
