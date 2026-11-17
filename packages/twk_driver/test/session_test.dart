// Session against the fakes of the four ports: the frame the input is
// awaited for, the frame emulator held to the boundary of the frame it is
// at, a query past it answered at once, every end of the app a result and
// not a timeout, the driver's own timeout on a clock it is given.
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/twk.dart' show DrivenClock, ElementFinder;
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
started({int framesBefore = 0}) async {
  final process = FakeProcess();
  final service = FakeService()
    ..frames = framesBefore
    // the app ran frames before the driver came: status says where it is
    ..statusWritten = framesBefore == 0 ? 0 : 5;
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
  );
  await pumpEventQueue();
  process.launched.terminal.app('start');
  if (framesBefore == 0) {
    service.frame(frame: 1, inputRead: 0, outputWritten: 5);
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

  test('a frame ran before the events: status is the baseline, and it asks '
      'nothing of the app', () async {
    final t = await started(framesBefore: 3);
    expect(t.service.calls.any((c) => c.startsWith('status')), isTrue);
    expect(t.service.calls.any((c) => c.startsWith('reassemble')), isFalse);
    expect(t.session.frame, 3);
    expect(t.session.screenText, 'start');
    await t.session.close();
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
