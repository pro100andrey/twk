// What an app records while it owns the screen — print, log() and
// uncaught errors from its handlers and timers — and what reaches stderr
// once the terminal is restored.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart' show FakeClock, FakeStderr;

import '../app_test.dart' show Probe;

void main() {
  // The apps run on a clock of the test's: their frames, and the timers
  // their handlers start, fire as it moves on ([pass]), so what a test
  // sees does not depend on how fast the machine is.
  late FakeClock clock;
  late HeadlessTerminal term;
  late TwkApp app;
  late Probe probe;
  // ignore: close_sinks, stands in for stderr, which stays open
  late FakeStderr err;

  /// Moves the clock on by [ms]: the frames and timers due by then run.
  Future<void> pass([int ms = 30]) => clock.elapse(Duration(milliseconds: ms));

  void start({LogSink? logs}) {
    clock = FakeClock();
    term = HeadlessTerminal(width: 20, height: 4);
    err = FakeStderr(tag: () => term.closed ? 'restored' : 'on screen');
    app = TwkApp(
      term,
      maxFps: 1000,
      logs: logs,
      clock: clock.stopwatch,
      environment: const {},
    );
    probe = Probe(
      app.screen.styles.pen(const Pen(bg: Color.rgb(0, 0, 0))),
      clock: clock.stopwatch,
    );
  }

  /// Runs the app with [onEvent] on the clock, with [err] for stderr;
  /// types Enter once the first frame is shown, and moves the clock on
  /// until the app ended, a second at most.
  Future<void> runWith(void Function(InputEvent e) onEvent) async {
    final done = clock.run(
      () => IOOverrides.runZoned(
        () => app.run(probe, onEvent),
        stderr: () => err,
      ),
    );
    await pass();
    expect(probe.paints, 1, reason: 'the first frame is shown');
    term.type('\r');
    var over = false;
    unawaited(
      done.then((_) => over = true, onError: (Object _) => over = true),
    );
    for (var i = 0; i < 100 && !over; i++) {
      await pass(10);
    }
    if (!over) {
      fail('the app has not ended a second on');
    }
    return done;
  }

  List<(LogLevel, String)> recorded() => [
    for (final r in app.logs.records) (r.level, r.message),
  ];

  test('print in handlers and timers is recorded, not printed', () async {
    final printed = <String>[];
    await runZoned(
      () {
        // the clock's zone, and so the app's, is in this one
        start();
        return runWith((e) {
          print('in a handler');
          Timer(Duration.zero, () {
            print('in a timer');
            app.quit();
          });
        });
      },
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => printed.add(line),
      ),
    );
    expect(printed, isEmpty);
    expect(recorded(), [
      (LogLevel.info, 'in a handler'),
      (LogLevel.info, 'in a timer'),
    ]);
    expect(err.writes, isEmpty, reason: 'nothing worse than info');
  });

  test('log() records into the app it runs in', () async {
    start();
    final error = StateError('odd');
    final stack = StackTrace.current;
    await runWith((e) {
      log('looked', level: LogLevel.debug);
      log('careful', level: LogLevel.warning, error: error, stack: stack);
      app.quit();
    });
    expect(recorded(), [
      (LogLevel.debug, 'looked'),
      (LogLevel.warning, 'careful'),
    ]);
    expect(app.logs.records.last.error, same(error));
    expect(app.logs.records.last.stack, same(stack));
  });

  test('an uncaught error is recorded and still ends run()', () async {
    start();
    final failure = StateError('handler failed');
    await expectLater(
      runWith((e) {
        // after the end: recorded, nothing else
        Timer(Duration.zero, () => throw StateError('later'));
        throw failure;
      }),
      throwsA(same(failure)),
    );
    expect(term.closed, isTrue);
    await pass();
    final [first, later] = app.logs.records;
    expect(first.level, LogLevel.error);
    expect(first.error, same(failure));
    expect(first.stack, isNotNull);
    expect(later.level, LogLevel.error);
    expect('${later.error}', 'Bad state: later');
  });

  test('a log file that cannot be written ends run() with its error', () async {
    final dir = Directory.systemTemp.createTempSync('twk_log');
    addTearDown(() => dir.deleteSync(recursive: true));
    start(logs: LogSink(path: dir.path));
    await expectLater(
      runWith((e) => print('lost')),
      throwsA(isA<FileSystemException>()),
    );
    expect(term.closed, isTrue);
  });

  test('warnings and errors reach stderr after the restore, in order, '
      'except the error run() ends with', () async {
    start();
    final failure = StateError('fatal');
    await expectLater(
      runWith((e) {
        print('chatter');
        log('first', level: LogLevel.warning);
        log('second', level: LogLevel.error, error: StateError('caught'));
        log('third', level: LogLevel.warning);
        throw failure;
      }),
      throwsA(same(failure)),
    );
    expect(err.writes, [
      matches(r'^restored: \S+ warning first$'),
      matches(r'^restored: \S+ error second: Bad state: caught$'),
      matches(r'^restored: \S+ warning third$'),
    ]);
  });
}
