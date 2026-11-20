// Driven time against a real twk app in a real pseudo-terminal: the app's
// clock stands until the driver moves it, `press` and `waitFor` move it as
// far as they need, and what is I/O (a child process, a terminal that is
// not read) keeps to real time.
@Tags(['process'])
@TestOn('linux || mac-os')
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_driver/twk_driver.dart';
import 'package:twk_test/twk_test.dart' show waitFor;

/// A process port whose terminal's output can be stopped from being read,
/// as a terminal that has stopped reading is.
final class _Stoppable implements ProcessPort {
  final inner = PtyProcessPort();
  late _StoppableTerminal terminal;
  late Launched launched;

  @override
  Future<Launched> spawn(ProcessSpec spec) async {
    final started = await inner.spawn(spec);
    launched = started;
    terminal = _StoppableTerminal(started.terminal);
    return _StoppedLaunched(started, terminal);
  }
}

final class _StoppedLaunched implements Launched {
  _StoppedLaunched(this._inner, this.terminal);

  final Launched _inner;

  @override
  final TerminalPort terminal;

  @override
  Future<int?> get exitCode => _inner.exitCode;

  @override
  Future<Uri> get serviceUri => _inner.serviceUri;

  @override
  Future<void> kill() => _inner.kill();
}

final class _StoppableTerminal implements TerminalPort {
  _StoppableTerminal(this._inner);

  final TerminalPort _inner;
  StreamSubscription<Uint8List>? _sub;

  /// Stops reading what the app writes.
  void stop() => _sub?.pause();

  /// Reads it again.
  void resume() => _sub?.resume();

  @override
  Stream<Uint8List> get output {
    final controller = StreamController<Uint8List>();
    _sub = _inner.output.listen(
      controller.add,
      onDone: controller.close,
      onError: controller.addError,
    );
    return controller.stream;
  }

  @override
  bool? get nlToCrNl => _inner.nlToCrNl;

  @override
  void write(List<int> bytes) => _inner.write(bytes);

  @override
  void resize(int width, int height) => _inner.resize(width, height);

  @override
  Uint8List? get modesAtEnd => _inner.modesAtEnd;
}

/// The bound of what these tests wait for on real time, which is I/O the
/// driver's clock cannot move: a process start (a compiled app, seconds on
/// a loaded machine: a full handover on s1 runs at a load of 40-60) plus
/// the app terminal's own limits, 1 s of flush and 5 s blind
/// (`_closeFlushLimit`, `_closeBlindLimit` of twk_core's terminal), and
/// the output's 2 ms retries. The product limits stay as they are; this is
/// the bound of the wait, which fails with a message when nothing comes.
const _realTimeBound = Duration(seconds: 90);

void main() {
  late String app;
  setUpAll(
    () async => app = await compiledProgram(
      'test/app/clock_app.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_driver/programs',
    ),
  );

  Future<Session> start({
    List<String> arguments = const [],
    bool driven = true,
  }) async {
    final session = await Session.start(
      ProcessSpec(app, arguments: arguments),
      timeout: const Duration(seconds: 30),
      driven: driven,
      startTime: DateTime.utc(2026, 5, 6),
    );
    addTearDown(session.close);
    return session;
  }

  test('a Spinner app is pressed and asserted without hanging: its frames '
      "are the driver's, and the time stands where it was", () async {
    final s = await start();
    expect(s.driven, isTrue);
    expect(s.screenText, contains('ticks: 0'));
    final none = await s.press('z');
    expect(none.screen, contains('ticks: 0'));
    // a key that draws: the frame is due a gap away on a clock that stands
    // still, and press moves it there
    final up = await s.press('u u');
    expect(up.screen, contains('ups: 2'));
    // the animation ran by no wall-clock second: it has a timer, not a tick
    final status = await s.clock.status();
    expect(status.time, lessThan(1000000));
    expect(status.quiet, isFalse);
    expect(status.timers, greaterThan(0));
  });

  test(
    'a debounce: the key starts 500 ms, waitFor moves the clock to it',
    () async {
      final s = await start(arguments: ['--quiet']);
      final key = await s.press('d');
      expect(key.screen, contains('saved: not saved'));
      expect((await s.clock.status()).quiet, isFalse);
      final step = await s.waitFor((t) => t.contains('saved: saved'));
      expect(step.screen, contains('saved: saved'));
      final status = await s.clock.status();
      expect(status.time, 500000, reason: 'to the timer, not a step past it');
      expect(status.quiet, isTrue);
    },
  );

  test('advance moves the app by hand: the tick of the second', () async {
    final s = await start();
    await s.clock.advance(const Duration(seconds: 3));
    final step = await s.waitFor((t) => t.contains('ticks: 3'));
    expect(step.screen, contains('ticks: 3'));
  });

  test(
    "a raw Future.delayed of the app is on the driver's time too",
    () async {
      final s = await start(arguments: ['--quiet']);
      await s.press('f');
      final status = await s.clock.status(describe: true);
      expect(status.timers, 1);
      expect(status.nextDue, status.time + 2000000);
      await s.waitFor((t) => t.contains('saved: later'));
    },
  );

  test('"never": a quiet app, at once, without moving the clock', () async {
    final s = await start(arguments: ['--quiet']);
    final before = await s.clock.status();
    await expectLater(
      s.waitFor((t) => t.contains('nothing like this'), near: 'saved: x'),
      throwsA(
        isA<DriverError>().having(
          (e) => e.message,
          'message',
          allOf(
            startsWith('never:'),
            contains('Closest line: "saved: not saved"'),
          ),
        ),
      ),
    );
    expect((await s.clock.status()).time, before.time);
  });

  test('"not within": an endless animation, the timers named, the clock '
      'moved the budget and no more', () async {
    final s = await start();
    await expectLater(
      s.waitFor(
        (t) => t.contains('ticks: 99'),
        budget: const Duration(seconds: 3),
      ),
      throwsA(
        isA<DriverError>().having(
          (e) => e.message,
          'message',
          allOf(contains('within 3 s of app time'), contains('periodic timer')),
        ),
      ),
    );
    expect((await s.clock.status()).time, 3000000);
  });

  test('a session on real time works: the app runs by itself, and waitFor '
      'takes the real time io gives it', () async {
    final s = await start(arguments: ['--quiet'], driven: false);
    expect(s.driven, isFalse);
    final status = await s.clock.status();
    expect(status.driven, isFalse);
    expect(status.quiet, isNull);
    await s.press('d');
    final step = await s.waitFor(
      (t) => t.contains('saved: saved'),
      io: const Duration(seconds: 20),
    );
    expect(step.screen, contains('saved: saved'));
    // a clock that is not the driver's cannot be moved
    await expectLater(
      s.clock.advance(const Duration(seconds: 1)),
      throwsA(isA<DriverError>()),
    );
  });

  test('a child process of the driven app is not driven: its parent is '
      'the app, not the driver', () async {
    final s = await start(arguments: ['--quiet']);
    await s.press('c');
    // the child is real I/O: the clock cannot see it, io says to wait
    final step = await s.waitFor(
      (t) => t.contains('child driven='),
      io: const Duration(seconds: 60),
    );
    expect(step.screen, contains('child driven=false'));
  });

  test('a program that takes no TWK_DRIVEN is told at once: here the '
      'variable names a pid that is not its parent', () async {
    await expectLater(
      Session.start(
        ProcessSpec(app, arguments: const ['--quiet']),
        ports: SessionPorts(driverPid: 1),
        timeout: const Duration(seconds: 30),
      ),
      throwsA(
        isA<DriverError>().having(
          (e) => e.message,
          'message',
          contains('not driven'),
        ),
      ),
    );
  });

  test('a terminal that stops reading and reads again gets all the app wrote: '
      'the retries of its output are on real time', () async {
    final port = _Stoppable();
    final s = await Session.start(
      ProcessSpec(app, arguments: const ['--quiet']),
      ports: SessionPorts(process: port),
      timeout: _realTimeBound,
    );
    addTearDown(s.close);
    port.terminal
      ..stop()
      // 400 kB the pseudo-terminal does not hold
      ..write('x'.codeUnits);
    // press waits for the frame within the session's real-time bound: the
    // app's writes are retried every 2 ms until the terminal reads again
    final press = s.press('u');
    port.terminal.resume();
    expect((await press).screen, contains('ups: 1'));
    expect(s.output.length, greaterThan(400000));
  });

  test('an app that quits while its terminal is not read still ends, the '
      'close guards on real time', () async {
    final port = _Stoppable();
    final s = await Session.start(
      ProcessSpec(app, arguments: const ['--quiet']),
      ports: SessionPorts(process: port),
      timeout: _realTimeBound,
    );
    addTearDown(s.close);
    port.terminal.stop();
    // 400 kB the pseudo-terminal does not hold, then the end
    port.terminal
      ..write('x'.codeUnits)
      ..write('q'.codeUnits);
    final code = await waitFor(
      port.launched.exitCode,
      'the app to end though nothing reads its terminal',
      // the close guards of the app's terminal run on real time: up to 1 s
      // (flush) and 5 s (blind), after an app start under a loaded machine
      timeout: _realTimeBound,
    );
    expect(code, 0);
  });
}
