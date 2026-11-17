// What a TwkApp tells a driver about the input it took in: inputRead, a
// sample of the terminal's bytesRead taken where the event loop is at a
// boundary, and onInputSettled, called once the microtasks of what was read
// or dispatched have run.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart' show FakeClock, waitUntil;

import 'app_test.dart' show Probe;
import 'terminal/fake_link.dart';
import 'terminal/on_clock.dart';

/// What the terminal answers to the probe: synchronized output, the kitty
/// keyboard protocol, then DA1.
const _answers = '\x1b[?2026;2\$y\x1b[?0u\x1b[?62;22c';

void main() {
  late FakeClock clock;
  late TwkApp app;
  late Probe probe;
  late Future<void> done;
  late List<int> frameInput; // inputRead when each frame's build began
  late List<(int, int, bool)> settled; // inputRead, framesRun, scheduled
  void Function()? during; // run by the build of each frame

  setUp(() {
    clock = FakeClock();
    frameInput = [];
    settled = [];
    during = null;
  });

  Future<void> pass([int ms = 30]) => clock.elapse(Duration(milliseconds: ms));

  /// An app on [terminal], on the clock, whose events ask for a frame.
  void start(TerminalBackend terminal, {void Function(InputEvent)? onEvent}) {
    app = TwkApp(terminal, maxFps: 1000, clock: clock.clock)
      ..onInputSettled = () =>
          settled.add((app.inputRead, app.framesRun, app.scheduled));
    probe = Probe(
      app.screen.styles.pen(const Pen()),
      clock: clock.clock,
    );
    done = clock.run(
      () => app.run(
        probe,
        onEvent ?? (_) => app.requestFrame(),
        beforeLayout: () {
          frameInput.add(app.inputRead);
          during?.call();
        },
      ),
    );
  }

  Future<void> settles(int n) =>
      waitUntil(() => settled.length >= n, 'input settled $n times');

  Future<void> end() async {
    app.quit();
    await clock.elapseUntil(done);
  }

  test('a key read before the first frame is not reported by it but by the '
      'next', () async {
    final term = HeadlessTerminal();
    start(term);
    term.type('a');
    await pass();
    expect(frameInput, [0, 1]);
    await settles(1);
    expect(settled.last.$1, 1);
    await end();
  });

  test('a key that changes nothing is acknowledged without a frame', () async {
    final term = HeadlessTerminal();
    start(term, onEvent: (_) {});
    await pass();
    final frames = app.framesRun;
    term.type('a');
    await pass();
    await settles(1);
    expect(settled, [(1, frames, false)]);
    expect(app.framesRun, frames);
    await end();
  });

  test('several reads in a turn of the event loop are one acknowledgement, '
      'the bytes of all of them in it', () async {
    final term = HeadlessTerminal();
    start(term, onEvent: (_) {});
    await pass();
    term
      ..type('a')
      ..type('bc');
    await pass();
    await settles(1);
    expect(settled.single.$1, 3);
    await end();
  });

  test(
    'a lone ESC is pending when read, and counted when it is resolved',
    () async {
      final term = HeadlessTerminal();
      start(term, onEvent: (_) {});
      await pass();
      term.input([0x1b]);
      expect(app.inputPending, isTrue);
      await pass();
      await settles(1);
      expect(
        settled.last.$1,
        1,
        reason: 'the byte is read, though not an event',
      );
      term.timeOutInput();
      expect(app.inputPending, isFalse);
      await pass();
      await settles(2);
      await end();
    },
  );

  test('a resize is acknowledged, and asks for the frame that has its '
      'size', () async {
    final term = HeadlessTerminal();
    start(term);
    await pass();
    term.resize(30, 6);
    await pass();
    await settles(1);
    expect((app.screen.width, app.screen.height), (30, 6));
    // a resize is no read: no bytes
    expect(settled.last.$1, 0);
    expect(frameInput.length, 2);
    await end();
  });

  test('a frame asked for by a Future(...) of the handler is seen as '
      'scheduled by the acknowledgement', () async {
    // in the real zone: its timers run in order on the event loop
    final term = HeadlessTerminal();
    app = TwkApp(term, maxFps: 1000, environment: const {})
      ..onInputSettled = () =>
          settled.add((app.inputRead, app.framesRun, app.scheduled));
    final root = Probe(app.screen.styles.pen(const Pen()));
    final running = app.run(root, (e) => Future(app.requestFrame));
    await waitUntil(() => app.framesRun == 1, 'the first frame');
    term.type('a');
    await settles(1);
    expect(settled.single.$3, isTrue);
    app.quit();
    await running;
  });

  test('an answer the Terminal keeps to itself is acknowledged', () async {
    // the probe is not answered: its late answers are dropped
    final link = FakeLink();
    final term = await clock.open(
      link,
      const TerminalOptions(probeTimeout: Duration(milliseconds: 100)),
    );
    start(term, onEvent: (_) {});
    await pass();
    final open = term.bytesRead;
    link.type('\x1b[?62;22c');
    await pass();
    await settles(1);
    expect(settled.single.$1, open + 9);
    await end();
  });

  test(
    'inputRead starts at the bytes the terminal read while it opened',
    () async {
      final link = FakeLink()..type(_answers);
      final term = await clock.open(link);
      start(term, onEvent: (_) {});
      expect(app.inputRead, term.bytesReadAtOpen);
      expect(app.inputRead, greaterThan(0));
      await pass();
      expect(frameInput, [term.bytesReadAtOpen]);
      await end();
    },
  );

  test(
    'input read while the terminal is handed over is not counted or sampled',
    () async {
      final term = HeadlessTerminal();
      start(term, onEvent: (_) {});
      await pass();
      final suspended = Completer<void>();
      final back = Completer<void>();
      final suspension = clock.run(
        () => app.suspend(() async {
          suspended.complete();
          await back.future;
        }),
      );
      await clock.elapseUntil(suspended.future);
      term.type('a');
      expect(term.bytesRead, 0, reason: 'the other program reads it');
      expect(app.sampleInput(), 0);
      back.complete();
      await clock.elapseUntil(suspension);
      await end();
    },
  );

  test(
    'frameDue and scheduled tell whether a frame is asked for and when',
    () async {
      final term = HeadlessTerminal();
      start(term, onEvent: (_) {});
      expect(app.scheduled, isTrue);
      expect(app.frameDue, isNotNull);
      await pass();
      expect(app.scheduled, isFalse);
      expect(app.frameDue, isNull);
      app.requestFrame();
      expect(app.scheduled, isTrue);
      expect(app.frameDue, isNotNull);
      await end();
    },
  );

  test('frameEnd completes when the running frame ends, and has before it '
      'when none runs', () async {
    final term = HeadlessTerminal();
    start(term, onEvent: (_) {});
    var ended = false;
    during = () {
      unawaited(app.frameEnd.then((_) => ended = true));
      expect(ended, isFalse);
    };
    await clock.elapse(const Duration(milliseconds: 5));
    expect(ended, isTrue);
    during = null;
    await app.frameEnd;
    await end();
  });
}
