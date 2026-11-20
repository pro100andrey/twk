// A session built from the ports a caller gives, without an app service:
// waits on output, the app-only calls refused, a recorder's terminal
// seeing every chunk with its time, and the same ports with a service.
import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk/twk.dart' show DrivenClock, ElementFinder;
import 'package:twk_driver/twk_driver.dart';

import 'fakes.dart';

/// What a recorder is: a terminal around another, noting each chunk with
/// the time of its clock and each write.
final class RecordingTerminal implements TerminalPort {
  RecordingTerminal(this._inner, this._clock);

  final TerminalPort _inner;
  final DrivenClock _clock;
  final chunks = <(int, String)>[];
  final writes = <(int, String)>[];

  @override
  Stream<Uint8List> get output => _inner.output.map((bytes) {
    chunks.add((_clock.elapsedMicroseconds, String.fromCharCodes(bytes)));
    return bytes;
  });

  @override
  bool? get nlToCrNl => _inner.nlToCrNl;

  @override
  Uint8List? get modesAtEnd => _inner.modesAtEnd;

  @override
  void write(List<int> bytes) {
    writes.add((_clock.elapsedMicroseconds, String.fromCharCodes(bytes)));
    _inner.write(bytes);
  }

  @override
  void resize(int width, int height) => _inner.resize(width, height);
}

final class RecordingLaunched implements Launched {
  RecordingLaunched(this._inner, this.terminal);

  final Launched _inner;

  @override
  final RecordingTerminal terminal;

  @override
  Future<int?> get exitCode => _inner.exitCode;

  @override
  Future<Uri> get serviceUri => _inner.serviceUri;

  @override
  Future<void> kill() => _inner.kill();
}

/// A process port whose program is wrapped by [wrap].
final class WrappingProcess implements ProcessPort {
  WrappingProcess(this._inner, this.wrap);

  final FakeProcess _inner;
  final Launched Function(Launched) wrap;

  @override
  Future<Launched> spawn(ProcessSpec spec) async =>
      wrap(await _inner.spawn(spec));
}

void main() {
  late FakeProcess process;
  late FakeScreen screen;
  late DrivenClock clock;
  late RecordingTerminal recorder;

  Future<Session> compose({bool recording = true}) {
    process = FakeProcess();
    screen = FakeScreen();
    clock = DrivenClock();
    return Session.compose(
      const ProcessSpec('sh'),
      process: WrappingProcess(process, (launched) {
        recorder = RecordingTerminal(launched.terminal, clock);
        return recording ? RecordingLaunched(launched, recorder) : launched;
      }),
      screen: screen,
      clock: clock,
      timeout: const Duration(seconds: 5),
    );
  }

  test('start returns at once; type then wait for a regexp on the screen '
      'the output leaves', () async {
    final session = await compose();
    final term = process.launched.terminal;
    expect(session.driven, isFalse);
    final typed = await session.type('echo hi');
    expect(term.writes, [
      'echo hi'.codeUnits,
    ], reason: 'the bytes are written and the step returns');
    expect(typed.screen, '');
    final wait = session.waitFor(
      (s) => RegExp(r'hi\s*> $').hasMatch(s),
      what: 'the prompt',
    );
    term.app('echo hi\r\n');
    await pumpEventQueue();
    term.app('hi\r\n> ');
    final step = await wait;
    expect(step.screen, endsWith('> '));
    expect(session.screenText, endsWith('> '));
    await session.close();
  });

  test('a wait that nothing answers fails on the given clock, with the '
      'screen', () async {
    final session = await compose();
    process.launched.terminal.app('nothing');
    final wait = session.waitFor((s) => s.contains('never'));
    final failure = expectLater(
      wait,
      throwsA(
        isA<DriverError>()
            .having((e) => e.message, 'message', contains('within 5 s'))
            .having((e) => e.message, 'screen', contains('nothing')),
      ),
    );
    await pumpEventQueue();
    clock.advance(const Duration(seconds: 4));
    await pumpEventQueue();
    clock.advance(const Duration(seconds: 1));
    await failure;
    await session.close();
  });

  test('waitFor takes io as its time here', () async {
    final session = await compose();
    final wait = session.waitFor(
      (s) => s.contains('x'),
      io: const Duration(seconds: 1),
    );
    final failure = expectLater(
      wait,
      throwsA(
        isA<DriverError>().having(
          (e) => e.message,
          'm',
          contains('within 1 s'),
        ),
      ),
    );
    await pumpEventQueue();
    clock.advance(const Duration(seconds: 1));
    await failure;
    await session.close();
  });

  test('find, tap and the clock are refused: not a twk app', () async {
    final session = await compose();
    const finder = ElementFinder.text('Save');
    for (final call in <Future<Object?> Function()>[
      () => session.find(finder),
      () => session.findOne(finder),
      () => session.tap(finder),
      () => session.clock.status(),
    ]) {
      await expectLater(
        call(),
        throwsA(
          isA<DriverError>().having(
            (e) => e.message,
            'message',
            contains('not a twk app (no app service)'),
          ),
        ),
      );
    }
    await session.close();
  });

  test('asking for the driven time without a service is an error', () {
    expect(
      Session.compose(
        const ProcessSpec('sh'),
        process: FakeProcess(),
        screen: FakeScreen(),
        driven: true,
      ),
      throwsArgumentError,
    );
  });

  test('a recording terminal sees every chunk with its time, and what the '
      'driver wrote', () async {
    final session = await compose();
    final term = process.launched.terminal..app('a');
    await pumpEventQueue();
    clock.advance(const Duration(milliseconds: 40));
    term.app('b');
    await pumpEventQueue();
    await session.press('x');
    clock.advance(const Duration(milliseconds: 10));
    term.app('c');
    await pumpEventQueue();
    expect(recorder.chunks, [(0, 'a'), (40000, 'b'), (50000, 'c')]);
    expect(recorder.writes, [(40000, '<x>')]);
    expect(session.screenText, 'abc');
    await session.close();
  });

  test(
    'a screen drawn in part (a synchronized update) is not looked at',
    () async {
      final session = await compose();
      final term = process.launched.terminal;
      final seen = <String>[];
      final wait = session.waitFor((s) {
        seen.add(s);
        return s.contains('done');
      });
      screen.updating = true;
      term.app('done');
      await pumpEventQueue();
      expect(seen.where((s) => s.contains('done')), isEmpty);
      screen.updating = false;
      term.app('!');
      expect((await wait).screen, 'done!');
      await session.close();
    },
  );

  test('resize sets both screens and returns', () async {
    final session = await compose();
    await session.resize(100, 30);
    expect(process.launched.terminal.sizes, [(100, 30)]);
    expect(screen.answeringSize, (100, 30));
    expect(screen.frameSize, (100, 30));
    await session.close();
  });

  test('the program ending is an end: a result of close, AppEnded for '
      'the next step', () async {
    final session = await compose();
    final term = process.launched.terminal;
    final wait = session.waitFor((s) => s.contains('never'));
    final failure = expectLater(wait, throwsA(isA<AppEnded>()));
    await process.launched.exit(3);
    await failure;
    expect(await session.exitCode, 3);
    expect(session.ended, isTrue);
    expect(() => session.type('x'), throwsA(isA<AppEnded>()));
    expect(term.writes, isEmpty);
    await session.close();
  });

  test('attach: a launched program, with a service it is a twk app as '
      'start makes it', () async {
    final launched = FakeLaunched();
    final service = FakeService();
    screen = FakeScreen();
    final attaching = Session.attach(
      launched,
      screen: screen,
      service: service,
      driven: true,
      timeout: const Duration(seconds: 5),
    );
    await pumpEventQueue();
    launched.terminal.app('start');
    service
      ..frame(frame: 1, inputRead: 0, outputWritten: 5)
      ..frames = 1
      ..statusWritten = 5;
    final session = await attaching;
    expect(session.driven, isTrue);
    expect(session.screenText, 'start');
    expect(await session.find(const ElementFinder.text('x')), isEmpty);
    await session.close();
  });
}
