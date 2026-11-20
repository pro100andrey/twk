// Session against the fakes of the four ports: the frame the input is
// awaited for, the frame emulator held to the boundary of the frame it is
// at, a query past it answered at once, every end of the app a result and
// not a timeout, the driver's own timeout on a clock it is given.
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/twk.dart' show DrivenClock, ElementFinder;
import 'package:twk_core/twk_core.dart' show KeyCode, KeyEvent, Mod;
import 'package:twk_driver/twk_driver.dart';

import 'fakes.dart';

/// A session on fakes, past its first frame (the first frame wrote
/// "start", 5 bytes).
Future<
  ({
    Session session,
    FakeProcess process,
    FakeService service,
    FakeScreen screen,
    DrivenClock clock,
  })
>
started({
  int framesBefore = 0,
  bool driven = true,
  void Function(FakeService service)? setUp,
}) async {
  final process = FakeProcess();
  final service = FakeService()
    ..frames = framesBefore
    // the app ran frames before the driver came: status says where it is
    ..statusWritten = framesBefore == 0 ? 0 : 5
    ..driven = driven;
  setUp?.call(service);
  final screen = FakeScreen();
  final clock = DrivenClock();
  final starting = Session.start(
    const ProcessSpec('app.dart'),
    ports: SessionPorts(
      process: process,
      screen: (_, _) => screen,
      connect: (_) async => service,
      clock: clock,
    ),
    timeout: const Duration(seconds: 5),
    driven: driven,
  );
  await pumpEventQueue();
  process.launched.terminal.app('start');
  if (framesBefore == 0) {
    service
      ..frame(frame: 1, inputRead: 0, outputWritten: 5)
      // from now on the app is where that frame left it
      ..frames = 1
      ..statusWritten = 5;
  }
  final session = await starting;
  return (
    session: session,
    process: process,
    service: service,
    screen: screen,
    clock: clock,
  );
}

void main() {
  test('start sets frameEvents and waits for the first frame', () async {
    final t = await started();
    expect(t.service.calls.first, contains('flags'));
    expect(t.service.calls.first, contains('frameEvents'));
    expect(t.session.frame, 1);
    expect(t.session.screenText, 'start');
    await t.session.close();
  });

  test('a frame ran before the events: the clock status is the baseline, and '
      'it asks nothing of the app', () async {
    final t = await started(framesBefore: 3);
    expect(t.service.calls.any((c) => c.startsWith('clock')), isTrue);
    expect(t.service.calls.any((c) => c.startsWith('status')), isFalse);
    expect(t.service.calls.any((c) => c.startsWith('reassemble')), isFalse);
    expect(t.session.frame, 3);
    expect(t.session.screenText, 'start');
    await t.session.close();
  });

  test("close twice: the second is the first one's report, an app the "
      'driver let go is not one that exited by itself', () async {
    final t = await started();
    final first = await t.session.close();
    expect(first.exitedByItself, isFalse);
    final second = await t.session.close();
    expect(identical(second, first), isTrue);
    expect(second.exitedByItself, isFalse);
    expect(second.problems, isEmpty);
  });

  test('type of an empty text is a step that sends nothing and waits for '
      'no frame', () async {
    final t = await started();
    final before = t.process.launched.terminal.writes.length;
    final step = await t.session.type('');
    expect(t.process.launched.terminal.writes.length, before);
    expect(step.frame, t.session.frame);
    await t.session.close();
  });

  test('pressKey presses the event itself: Shift and space', () async {
    final t = await started();
    final term = t.process.launched.terminal;
    final press = t.session.pressKey(
      const KeyEvent(KeyCode.char, char: ' ', modifiers: Mod.shift),
    );
    await pumpEventQueue();
    expect(term.writes.last, '< >'.codeUnits);
    term.app('A');
    t.service.frame(frame: 2, inputRead: 3, outputWritten: 6);
    expect((await press).frame, 2);
    await t.session.close();
  });

  group('time', () {
    test('the app is offered the driver: TWK_DRIVEN is the driver pid, and '
        'the start time when there is one', () async {
      final process = FakeProcess();
      final service = FakeService();
      final screen = FakeScreen();
      final starting = Session.start(
        const ProcessSpec('app.dart', environment: {'A': 'b'}),
        ports: SessionPorts(
          process: process,
          screen: (_, _) => screen,
          connect: (_) async => service,
          clock: DrivenClock(),
          driverPid: 4242,
        ),
        startTime: DateTime.utc(2026, 5, 6, 7, 8, 9),
      );
      await pumpEventQueue();
      process.launched.terminal.app('start');
      service.frame(frame: 1, inputRead: 0, outputWritten: 5);
      final session = await starting;
      expect(process.specs.single.environment, {
        'A': 'b',
        'TWK_DRIVEN': '4242@2026-05-06T07:08:09.000Z',
      });
      expect(session.driven, isTrue);
      await session.close();
    });

    test('the start fails at once, saying why, when the app did not take '
        'the time offered (a `dart run` between)', () async {
      final process = FakeProcess();
      final service = FakeService()..driven = false;
      await expectLater(
        Session.start(
          const ProcessSpec('app.dart'),
          ports: SessionPorts(
            process: process,
            screen: (_, _) => FakeScreen(),
            connect: (_) async => service,
            clock: DrivenClock(),
            driverPid: 4242,
          ),
        ),
        throwsA(
          isA<DriverError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('not driven'),
              contains('4242'),
              contains('dart run'),
            ),
          ),
        ),
      );
      expect(process.launched.killed, isTrue);
    });

    test('a VM service address that never comes is a timeout, and the app '
        'is killed', () async {
      final process = FakeProcess();
      final clock = DrivenClock();
      process.launched.pendingServiceUri = Completer<Uri>();
      final starting = Session.start(
        const ProcessSpec('app.dart'),
        ports: SessionPorts(
          process: process,
          screen: (_, _) => FakeScreen(),
          connect: (_) async => FakeService(),
          clock: clock,
        ),
        timeout: const Duration(seconds: 5),
      );
      final expectation = expectLater(
        starting,
        throwsA(
          isA<DriverError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('the VM service address'),
              contains('within 0:00:05'),
            ),
          ),
        ),
      );
      await pumpEventQueue();
      clock.advance(const Duration(seconds: 5));
      await expectation;
      expect(process.launched.killed, isTrue);
    });

    test('a VM service connection that never answers is a timeout, and the '
        'app is killed', () async {
      final process = FakeProcess();
      final clock = DrivenClock();
      final connecting = Completer<AppServicePort>();
      final starting = Session.start(
        const ProcessSpec('app.dart'),
        ports: SessionPorts(
          process: process,
          screen: (_, _) => FakeScreen(),
          connect: (_) => connecting.future,
          clock: clock,
        ),
        timeout: const Duration(seconds: 5),
      );
      final expectation = expectLater(
        starting,
        throwsA(
          isA<DriverError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('the VM service'),
              contains('within 0:00:05'),
            ),
          ),
        ),
      );
      await pumpEventQueue();
      clock.advance(const Duration(seconds: 5));
      await expectation;
      expect(process.launched.killed, isTrue);
    });

    test('a service call that never answers is a timeout of the driver '
        'clock', () async {
      final t = await started();
      t.service.pendingAnswers['find'] = Completer<Json>();
      final finding = t.session.find(const ElementFinder.text('Save'));
      final expectation = expectLater(
        finding,
        throwsA(
          isA<DriverError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('ext.twk.find'),
              contains('within 0:00:05'),
            ),
          ),
        ),
      );
      await pumpEventQueue();
      t.clock.advance(const Duration(seconds: 5));
      await expectation;
      await t.session.close();
    });

    test('a session on real time sets no variable and starts from status, '
        'and waitFor needs io there', () async {
      final t = await started(driven: false);
      expect(t.process.specs.single.environment, isEmpty);
      expect(t.service.calls.any((c) => c.startsWith('status')), isTrue);
      expect(t.service.calls.any((c) => c.startsWith('clock')), isFalse);
      expect(t.session.driven, isFalse);
      await expectLater(
        t.session.waitFor((s) => s.contains('x')),
        throwsA(
          isA<DriverError>().having(
            (e) => e.message,
            'message',
            contains('io'),
          ),
        ),
      );
      // with io: the frames of real time are waited for, up to io
      var done = false;
      final wait = t.session.waitFor(
        (s) => s.contains('late'),
        io: const Duration(seconds: 5),
      );
      unawaited(wait.then((_) => done = true));
      await pumpEventQueue();
      expect(done, isFalse);
      t.process.launched.terminal.app('late');
      t.service.frame(frame: 2, inputRead: 0, outputWritten: 9);
      expect((await wait).frame, 2);
      await t.session.close();
    });

    test('a real-time wait ends at io on the driver clock', () async {
      final t = await started(driven: false);
      final wait = t.session.waitFor(
        (s) => s.contains('never'),
        io: const Duration(seconds: 2),
      );
      final failure = expectLater(
        wait,
        throwsA(
          isA<DriverError>().having(
            (e) => e.message,
            'message',
            contains('within 2 s'),
          ),
        ),
      );
      await pumpEventQueue();
      t.clock.advance(const Duration(seconds: 2));
      await failure;
      await t.session.close();
    });

    test('press moves the clock to the frame the input asked for, and to '
        'nothing further', () async {
      final t = await started();
      final term = t.process.launched.terminal;
      t.service.timers.add(1000000);
      final press = t.session.press('a');
      await pumpEventQueue();
      t.service.input(
        frame: 1,
        inputRead: 3,
        outputWritten: 5,
        scheduled: true,
        frameDue: 8333,
        time: 100,
      );
      await pumpEventQueue();
      // advanceTo the frame's time: the timer a second away is not fired
      expect(t.service.calls.last, 'clock {op: advanceTo, to: 8333}');
      expect(t.service.time, 8333);
      expect(t.service.timers, [1000000]);
      term.app('Z');
      t.service.frame(frame: 2, inputRead: 3, outputWritten: 6);
      expect((await press).frame, 2);
      await t.session.close();
    });

    test(
      'press on an input that asked for no frame leaves the clock be',
      () async {
        final t = await started();
        final press = t.session.press('a');
        await pumpEventQueue();
        t.service.input(frame: 1, inputRead: 3, outputWritten: 5);
        await press;
        expect(
          t.service.calls.where((c) => c.startsWith('clock {op: advance')),
          isEmpty,
        );
        await t.session.close();
      },
    );

    /// An app that draws a tick for each second its clock reaches, and
    /// starts the next second's timer: an animation.
    void spin(FakeService service, FakeTerminal term) {
      service.timers.add(1000000);
      service.onMove = (time) {
        final text = 'tick${time ~/ 1000000}';
        term.app(text);
        service
          ..statusWritten += text.length
          ..frames += 1
          ..frame(
            frame: service.frames,
            inputRead: 0,
            outputWritten: service.statusWritten,
          );
        if (service.timers.isEmpty) {
          service.timers.add(time + 1000000);
        }
      };
    }

    test('waitFor moves the clock from timer to timer until the screen is '
        'what it waits for', () async {
      final t = await started();
      spin(t.service, t.process.launched.terminal);
      final step = await t.session.waitFor((s) => s.contains('tick3'));
      expect(step.screen, contains('tick3'));
      expect(t.service.time, 3000000);
      expect(
        t.service.calls.where((c) => c.contains('advanceTo')),
        hasLength(3),
      );
      await t.session.close();
    });

    test('waitFor sees a state that lasted one frame of the advance', () async {
      final t = await started();
      final term = t.process.launched.terminal;
      // a move draws "blink" and "off" in two frames, in one advance
      t.service.timers.add(1000000);
      t.service.onMove = (time) {
        for (final text in ['blink', 'off']) {
          term.app(text);
          t.service
            ..statusWritten += text.length
            ..frames += 1
            ..frame(
              frame: t.service.frames,
              inputRead: 0,
              outputWritten: t.service.statusWritten,
            );
        }
      };
      final step = await t.session.waitFor((s) => s.endsWith('blink'));
      expect(step.screen, endsWith('blink'));
      await t.session.close();
    });

    test('waitFor fails "not within" the budget of app time, with the timers '
        'that wait', () async {
      final t = await started();
      spin(t.service, t.process.launched.terminal);
      await expectLater(
        t.session.waitFor(
          (s) => s.contains('never'),
          budget: const Duration(milliseconds: 2500),
          what: 'the word',
        ),
        throwsA(
          isA<DriverError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('no the word within 2.5 s of app time'),
              contains('lib/spinner.dart:40'),
              contains('tick2'),
            ),
          ),
        ),
      );
      // the clock went to the budget, not past it
      expect(t.service.time, 2500000);
      await t.session.close();
    });

    test('waitFor on a quiet app is "never" at once, with the frame, and '
        'the closest line where it is told what is looked for', () async {
      final t = await started();
      await expectLater(
        t.session.waitFor(
          (s) => s.contains('Count: 9'),
          near: 'Count: 9',
          what: 'the count',
        ),
        throwsA(
          isA<DriverError>().having(
            (e) => e.message,
            'message',
            allOf(
              startsWith('never: no the count at frame 1'),
              contains('io:'),
              contains('Screen at frame 1'),
            ),
          ),
        ),
      );
      // nothing was moved to find out
      expect(t.service.calls.where((c) => c.contains('advance')), isEmpty);
      await t.session.close();
    });

    test('waitFor on an app that never reads what was written fails within '
        'the timeout, on the driver clock, with the screen', () async {
      final t = await started();
      final press = t.session.press('a');
      final pressed = expectLater(press, throwsA(isA<DriverError>()));
      await pumpEventQueue();
      t.clock.advance(const Duration(seconds: 5));
      await pressed;
      // 1 byte written, 0 read: the app has not read its input
      Object? result;
      final wait = t.session
          .waitFor((s) => s.contains('never'), what: 'the word')
          .then<void>((_) {}, onError: (Object e) => result = e);
      await pumpEventQueue();
      t.clock.advance(const Duration(seconds: 5));
      await pumpEventQueue();
      // a bound that fails, not hangs: the wait is over by the timeout
      expect(
        result,
        isA<DriverError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('no the word'),
            contains('read what was written'),
            contains('within 5 s'),
            contains('Screen at frame 1'),
          ),
        ),
      );
      await wait;
      await t.session.close();
    });

    test('waitFor on an app that is neither quiet nor has a timer fails '
        'within the timeout instead of waiting for ever', () async {
      final t = await started();
      // a frame is asked for that never comes: not quiet, no timer due
      t.service.scheduled = true;
      Object? result;
      final wait = t.session
          .waitFor((s) => s.contains('never'), what: 'the word')
          .then<void>((_) {}, onError: (Object e) => result = e);
      await pumpEventQueue();
      t.clock.advance(const Duration(seconds: 5));
      await pumpEventQueue();
      expect(
        result,
        isA<DriverError>().having(
          (e) => e.message,
          'message',
          allOf(contains('the app to settle'), contains('Screen at frame 1')),
        ),
      );
      await wait;
      await t.session.close();
    });

    test('two concurrent waits end each at its own deadline and leave the '
        "session's timeout as it was", () async {
      final t = await started();
      Object? short;
      Object? long;
      final a = t.session
          .waitForScreen(
            (s) => s.contains('never'),
            timeout: const Duration(seconds: 3),
            what: 'the short one',
          )
          .then<void>((_) {}, onError: (Object e) => short = e);
      final b = t.session
          .waitForScreen(
            (s) => s.contains('never'),
            timeout: const Duration(seconds: 10),
            what: 'the long one',
          )
          .then<void>((_) {}, onError: (Object e) => long = e);
      await pumpEventQueue();
      t.clock.advance(const Duration(seconds: 3));
      await pumpEventQueue();
      expect(short, isA<DriverError>());
      expect(long, isNull);
      t.clock.advance(const Duration(seconds: 7));
      await pumpEventQueue();
      expect(
        long,
        isA<DriverError>().having((e) => e.message, 'message', contains('10')),
      );
      await Future.wait([a, b]);
      // each wait's bound was its own: the session's was never lent
      expect(t.session.timeout, const Duration(seconds: 5));
      await t.session.close();
    });

    test('a waitFor predicate that throws on a later frame fails that wait '
        'with its error, at once', () async {
      final t = await started();
      Object? result;
      final wait = t.session
          .waitFor(
            (s) => s.contains('late') ? throw RangeError('short') : false,
            io: const Duration(seconds: 1),
          )
          .then<void>((_) {}, onError: (Object e) => result = e);
      await pumpEventQueue();
      t.process.launched.terminal.app('late');
      t.service.frame(frame: 2, inputRead: 0, outputWritten: 9);
      await pumpEventQueue();
      // bounded: a wait that is not over fails here, it does not hang
      expect(result, isA<RangeError>());
      await wait;
      await t.session.close();
    });

    test('the quiet error names its option as data', () async {
      final t = await started();
      final error = await t.session
          .waitFor((s) => s.contains('x'))
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(error, isA<QuietApp>());
      final quiet = error! as QuietApp;
      expect(quiet.message, contains('pass io: to wait for it'));
      expect(quiet.messageUsing('io_ms'), contains('pass io_ms: to wait'));
      expect(quiet.messageUsing('io_ms'), isNot(contains('pass io:')));
      await t.session.close();
    });

    test('a quiet app waited on with io is given real time for the frames '
        'that may still come, then is "never"', () async {
      final t = await started();
      final late = t.session.waitFor(
        (s) => s.contains('late'),
        io: const Duration(seconds: 3),
      );
      await pumpEventQueue();
      t.process.launched.terminal.app('late');
      t.service.frame(frame: 2, inputRead: 0, outputWritten: 9);
      expect((await late).frame, 2);

      final none = expectLater(
        t.session.waitFor(
          (s) => s.contains('absent'),
          io: const Duration(seconds: 3),
        ),
        throwsA(
          isA<DriverError>().having(
            (e) => e.message,
            'message',
            allOf(startsWith('never'), contains('3 s')),
          ),
        ),
      );
      await pumpEventQueue();
      t.clock.advance(const Duration(seconds: 3));
      await none;
      await t.session.close();
    });

    test('a quiet app waited on with io: what asks for a frame from outside '
        'says so with twk.scheduled, and the wait goes on to that frame, '
        'with no poll and no move of the driver clock', () async {
      final t = await started();
      final wait = t.session.waitFor(
        (s) => s.contains('late'),
        io: const Duration(seconds: 3),
      );
      await pumpEventQueue();
      final before = t.clock.elapsedMicroseconds;
      t.service.onMove = (time) {
        if (time >= 1000) {
          t.process.launched.terminal.app('late');
          t.service.frame(frame: 2, inputRead: 0, outputWritten: 9);
        }
      };
      // a child's answer: a frame is asked for a gap after the last
      t.service
        ..timers.add(1000)
        ..scheduled = true
        ..frameDue = 1000
        ..scheduledEvent();
      expect((await wait).frame, 2);
      expect(
        t.clock.elapsedMicroseconds,
        before,
        reason: 'no time of the driver passed',
      );
      await t.session.close();
    });

    test('without the event the io wait does not notice what the app asked '
        'for until the io time is out, on the driver clock', () async {
      final t = await started();
      var done = false;
      final wait = t.session.waitFor(
        (s) => s.contains('late'),
        io: const Duration(seconds: 3),
      );
      unawaited(wait.then((_) => done = true, onError: (_) => done = true));
      await pumpEventQueue();
      t.service.onMove = (time) {
        if (time >= 1000) {
          t.process.launched.terminal.app('late');
          t.service.frame(frame: 2, inputRead: 0, outputWritten: 9);
        }
      };
      // asked for, and nothing said
      t.service
        ..timers.add(1000)
        ..scheduled = true
        ..frameDue = 1000;
      await pumpEventQueue();
      expect(done, isFalse);
      expect(t.service.calls.where((c) => c.contains('advance')), isEmpty);
      t.clock.advance(const Duration(seconds: 3));
      expect((await wait).frame, 2);
      await t.session.close();
    });

    test(
      'waitFor returns the screen shown now without moving anything',
      () async {
        final t = await started();
        final step = await t.session.waitFor((s) => s == 'start');
        expect(step.frame, 1);
        expect(
          t.service.calls.where((c) => c.startsWith('clock')),
          hasLength(1),
        );
        await t.session.close();
      },
    );

    test('the app ending ends a waitFor', () async {
      final t = await started();
      spin(t.service, t.process.launched.terminal);
      var exited = false;
      t.service.onMove = (time) {
        if (!exited) {
          exited = true;
          unawaited(t.process.launched.exit(1));
          unawaited(t.service.close());
        }
        t.service.timers.add(time + 1000000);
      };
      await expectLater(
        t.session.waitFor((s) => s.contains('x')),
        throwsA(isA<AppEnded>()),
      );
    });
  });

  test('press returns at the frame that took the key in, not before, and '
      'the frame emulator stops at its boundary', () async {
    final t = await started();
    final term = t.process.launched.terminal;
    var done = false;
    final press = t.session.press('a').then((s) {
      done = true;
      return s;
    });
    await pumpEventQueue();
    expect(term.writes.last, '<a>'.codeUnits);
    // the app draws "X" and then starts a next frame's "Y", not yet posted
    term.app('XY');
    t.service.input(frame: 1, inputRead: 3, outputWritten: 5);
    await pumpEventQueue();
    // a twk.input that is not scheduled: the app asked for no frame, done
    final step = await press;
    expect(done, isTrue);
    expect(step.frame, 1);
    // the bytes of 'XY' are past the boundary (5): not on the screen
    expect(t.screen.frames, ['start']);
    await t.session.close();
  });

  test('a key not yet read is waited for, a frame of an earlier read is not '
      'its frame', () async {
    final t = await started();
    final term = t.process.launched.terminal;
    var done = false;
    final press = t.session.press('a').then((s) {
      done = true;
      return s;
    });
    await pumpEventQueue();
    // a frame built before the key was read: inputRead 0 < 3
    term.app('A');
    t.service.frame(frame: 2, inputRead: 0, outputWritten: 6);
    await pumpEventQueue();
    expect(done, isFalse);
    term.app('B');
    t.service.frame(frame: 3, inputRead: 3, outputWritten: 7);
    final step = await press;
    expect(step.frame, 3);
    expect(t.screen.frames, ['start', 'A', 'B']);
    await t.session.close();
  });

  test('twk.input with a frame scheduled waits for that frame', () async {
    final t = await started();
    final term = t.process.launched.terminal;
    var done = false;
    final press = t.session.press('a').then((s) {
      done = true;
      return s;
    });
    await pumpEventQueue();
    t.service.input(frame: 1, inputRead: 3, outputWritten: 5, scheduled: true);
    await pumpEventQueue();
    expect(done, isFalse);
    term.app('Z');
    t.service.frame(frame: 2, inputRead: 3, outputWritten: 6);
    expect((await press).frame, 2);
    await t.session.close();
  });

  test('input held in the parser (a lone ESC) is not yet read', () async {
    final t = await started();
    var done = false;
    final press = t.session.press('escape').then((s) {
      done = true;
      return s;
    });
    await pumpEventQueue();
    t.service.input(
      frame: 1,
      inputRead: 8,
      outputWritten: 5,
      inputPending: true,
    );
    await pumpEventQueue();
    expect(done, isFalse);
    t.service.input(frame: 1, inputRead: 8, outputWritten: 5);
    await press;
    await t.session.close();
  });

  test('a query past the frame boundary is answered at once, and its answer '
      'counts in what the app must have read', () async {
    final t = await started();
    final term = t.process.launched.terminal..app('frame?');
    // the app writes a frame and then, in the same read, a query
    await pumpEventQueue();
    // answered although the frame emulator has not been given it
    expect(term.writes.last, '!'.codeUnits);
    expect(t.screen.frames, ['start']);
    var done = false;
    final press = t.session.press('a').then((_) => done = true);
    await pumpEventQueue();
    // written: 1 (the answer) + 3 (the key); the app has read the answer
    // only so far
    t.service.input(frame: 2, inputRead: 1, outputWritten: 11);
    await pumpEventQueue();
    expect(done, isFalse);
    t.service.input(frame: 2, inputRead: 4, outputWritten: 11);
    await press;
    expect(t.screen.frames.last, 'frame?');
    await t.session.close();
  });

  test('a key the app answers as quitting: the step waits for the exit '
      'and returns it, the service closing first is no error', () async {
    final t = await started();
    final term = t.process.launched.terminal;
    var done = false;
    final press = t.session.press('q').then((s) {
      done = true;
      return s;
    });
    await pumpEventQueue();
    t.service.input(frame: 1, inputRead: 3, outputWritten: 5, quitting: true);
    await t.service.close();
    await pumpEventQueue();
    // the acknowledgement is not the answer: the exit is
    expect(done, isFalse);
    // no clock moved: it waits for the process as long as it takes
    t.clock.advance(const Duration(seconds: 3));
    await pumpEventQueue();
    expect(done, isFalse);
    term.app('bye');
    await t.process.launched.exit(0);
    final step = await press;
    expect(step.exit!.code, 0);
    expect(step.exit!.expected, isTrue);
    expect(step.exit!.message, 'the app exited (0)');
    expect(step.screen, contains('bye'));
    // every call after it is the same result, not an error
    final again = await t.session.press('up');
    expect(identical(again.exit, step.exit), isTrue);
    expect(identical((await t.session.type('x')).exit, step.exit), isTrue);
    expect(identical((await t.session.resize(5, 5)).exit, step.exit), isTrue);
    expect(await t.session.exitCode, 0);
    final report = await t.session.close();
    expect(report.exitCode, 0);
  });

  test('the process ending before the quitting acknowledgement is read is '
      'still the app that said it', () async {
    final t = await started();
    final press = t.session.press('q');
    await pumpEventQueue();
    await t.process.launched.exit(0);
    await pumpEventQueue();
    t.service.input(frame: 1, inputRead: 3, outputWritten: 5, quitting: true);
    await t.service.close();
    expect((await press).exit!.expected, isTrue);
  });

  test('an exit with no quitting acknowledgement is unexpected, with the '
      'screen, and every call after it says the same', () async {
    final t = await started();
    final press = t.session.press('a');
    final expectation = expectLater(
      press,
      throwsA(
        isA<AppEnded>()
            .having((e) => e.exitCode, 'exitCode', 1)
            .having((e) => e.expected, 'expected', isFalse)
            .having(
              (e) => e.message,
              'message',
              contains('exited unexpectedly (1)'),
            )
            .having((e) => e.screen, 'screen', contains('boom')),
      ),
    );
    await pumpEventQueue();
    t.process.launched.terminal.app('boom');
    await t.process.launched.exit(1);
    await t.service.close();
    await expectation;
    await expectLater(
      t.session.press('b'),
      throwsA(isA<AppEnded>().having((e) => e.exitCode, 'code', 1)),
    );
    await expectLater(
      t.session.tap(const ElementFinder.text('x')),
      throwsA(isA<AppEnded>()),
    );
    expect(await t.session.exitCode, 1);
  });

  test('the VM service closing, the process alive, is an end that is no '
      'timeout, once the process is given a moment', () async {
    final t = await started();
    final press = t.session.press('a');
    final expectation = expectLater(
      press,
      throwsA(
        isA<AppEnded>().having(
          (e) => e.message,
          'm',
          contains('VM service closed unexpectedly'),
        ),
      ),
    );
    await pumpEventQueue();
    await t.service.close();
    await pumpEventQueue();
    t.clock.advance(const Duration(seconds: 2));
    await expectation;
    await t.session.close();
  });

  test("an app that does not answer is a timeout of the driver's clock, "
      'with the screen', () async {
    final t = await started();
    final press = t.session.press('a');
    final expectation = expectLater(
      press,
      throwsA(
        isA<DriverError>()
            .having((e) => e.message, 'message', contains('within 0:00:05'))
            .having((e) => e.message, 'screen', contains('start')),
      ),
    );
    await pumpEventQueue();
    t.clock.advance(const Duration(seconds: 4));
    await pumpEventQueue();
    t.clock.advance(const Duration(seconds: 1));
    await expectation;
    await t.session.close();
  });

  test('resize waits for a frame at the new size, the frame emulator '
      'resized at that frame', () async {
    final t = await started();
    final term = t.process.launched.terminal;
    var done = false;
    final resize = t.session.resize(100, 30).then((s) {
      done = true;
      return s;
    });
    await pumpEventQueue();
    expect(term.sizes, [(100, 30)]);
    expect(t.screen.answeringSize, (100, 30));
    t.service.input(frame: 1, inputRead: 0, outputWritten: 5);
    await pumpEventQueue();
    expect(done, isFalse);
    expect(t.screen.frameSize, (80, 24));
    term.app('big');
    t.service.frame(
      frame: 2,
      inputRead: 0,
      outputWritten: 8,
      width: 100,
      height: 30,
    );
    await resize;
    expect(t.screen.frameSize, (100, 30));
    await t.session.close();
  });

  test('waitForScreen checks the screen of each frame', () async {
    final t = await started();
    final term = t.process.launched.terminal;
    final wait = t.session.waitForScreen(
      (s) => s.endsWith('two'),
      timeout: const Duration(seconds: 1),
    );
    term.app('one');
    t.service.frame(frame: 2, inputRead: 0, outputWritten: 8);
    term.app('two');
    // the frames come one after the other, each seen
    t.service.frame(frame: 3, inputRead: 0, outputWritten: 11);
    expect((await wait).frame, 3);
    await t.session.close();
  });

  group('finders and tap', () {
    Json found(List<Map<String, Object?>> matches) => {
      'version': 1,
      'frame': 1,
      'count': matches.length,
      'matches': matches,
    };
    Map<String, Object?> node(int id, String type, {Map<String, int>? shown}) =>
        {
          'id': id,
          'type': type,
          'key': null,
          'text': 'Save',
          'rect': {'x': 4, 'y': 2, 'width': 8, 'height': 1},
          'shown': shown ?? {'x': 4, 'y': 2, 'width': 8, 'height': 1},
        };

    test('a finder is strict: none or many is an error naming them', () async {
      final t = await started();
      t.service.answers['find'] = (_) =>
          found([node(1, 'Button'), node(2, 'Button')]);
      await expectLater(
        t.session.findOne(const ElementFinder.text('Save')),
        throwsA(
          isA<DriverError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('2 nodes'),
              contains('(node 1)'),
              contains('(node 2)'),
            ),
          ),
        ),
      );
      t.service.answers['find'] = (_) => found([]);
      await expectLater(
        t.session.findOne(const ElementFinder.text('Save')),
        throwsA(
          isA<DriverError>().having(
            (e) => e.message,
            'm',
            contains('matches nothing'),
          ),
        ),
      );
      expect(
        t.service.calls.last,
        contains(jsonEncode(const ElementFinder.text('Save').toJson())),
      );
      await t.session.close();
    });

    Future<void> tapsFailing(
      dynamic Function(Json) hit,
      Matcher message, {
      bool tracked = true,
      Map<String, int>? shown,
    }) async {
      final t = await started();
      t.screen.mouseTracked = tracked;
      t.service.answers['find'] = (_) =>
          found([node(7, 'Button', shown: shown)]);
      t.service.answers['hitTest'] = (p) => {
        'version': 1,
        'frame': 1,
        ...hit(p) as Json,
      };
      await expectLater(
        t.session.tap(const ElementFinder.text('Save')),
        throwsA(
          isA<DriverError>().having((e) => e.message, 'message', message),
        ),
      );
      // nothing was sent
      expect(t.process.launched.terminal.writes, isEmpty);
      await t.session.close();
    }

    test('tap on a node no cell shows is "not visible"', () async {
      final t = await started();
      t.service.answers['find'] = (_) => found([
        {...node(7, 'Button'), 'shown': null},
      ]);
      await expectLater(
        t.session.tap(const ElementFinder.text('Save')),
        throwsA(
          isA<DriverError>().having(
            (e) => e.message,
            'm',
            contains('not visible'),
          ),
        ),
      );
      await t.session.close();
    });

    test('tap on a covered node names what covers it', () async {
      await tapsFailing(
        (_) => {
          'takenBy': null,
          'path': [
            {'id': 51, 'type': 'Dialog', 'render': 52},
          ],
          'listeners': <Object>[],
          'absorbedBy': null,
        },
        allOf(contains('covered by Dialog (node 51)'), contains('cell 8,2')),
      );
    });

    test('tap on a node nothing there takes a click on says so', () async {
      await tapsFailing(
        (_) => {
          'takenBy': null,
          'path': [
            {'id': 7, 'type': 'Button', 'render': 8},
          ],
          'listeners': [
            {
              'render': 8,
              'type': 'Listener',
              'callbacks': ['hover'],
            },
          ],
          'absorbedBy': null,
        },
        contains('nothing there takes a click'),
      );
    });

    test('tap while the console takes the mouse says which', () async {
      await tapsFailing(
        (_) => {
          'takenBy': 'console',
          'path': <Object>[],
          'listeners': <Object>[],
          'absorbedBy': null,
        },
        contains('console takes the mouse'),
      );
    });

    test('tap on an app that does not track the mouse says so', () async {
      await tapsFailing(
        (_) => {
          'takenBy': null,
          'path': [
            {'id': 7, 'type': 'Button', 'render': 8},
          ],
          'listeners': [
            {
              'render': 8,
              'type': 'Listener',
              'callbacks': ['down', 'up'],
            },
          ],
          'absorbedBy': null,
        },
        contains('does not track the mouse'),
        tracked: false,
      );
    });

    test('tap that reaches its target sends down and up at its middle '
        'cell and returns at the frame', () async {
      final t = await started();
      final term = t.process.launched.terminal;
      t.service.answers['find'] = (_) => found([node(7, 'Button')]);
      t.service.answers['hitTest'] = (p) => {
        'version': 1,
        'frame': 1,
        'cell': {'x': 8, 'y': 2},
        'takenBy': null,
        'path': [
          {'id': 9, 'type': 'Text', 'render': 10},
          {'id': 7, 'type': 'Button', 'render': 8},
        ],
        'listeners': [
          {
            'render': 8,
            'type': 'Listener',
            'callbacks': ['down', 'up'],
          },
        ],
        'absorbedBy': null,
      };
      final tap = t.session.tap(const ElementFinder.text('Save'));
      await pumpEventQueue();
      expect(t.service.calls.last, contains('hitTest {x: 8, y: 2}'));
      expect(term.writes.map(String.fromCharCodes), ['{down 8,2}']);
      // the down is read, the up follows: each its own frame
      t.service.input(frame: 1, inputRead: 10, outputWritten: 5);
      await pumpEventQueue();
      expect(term.writes.map(String.fromCharCodes), ['{down 8,2}', '{up 8,2}']);
      t.service.frame(frame: 2, inputRead: 18, outputWritten: 5);
      expect((await tap).frame, 2);
      await t.session.close();
    });
  });
}
