// What a TwkApp tells a driver about its end: quitting is true once quit()
// was called, and the acknowledgement of the read that led to it (or of the
// quit itself) comes, with it, before run completes.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart' show FakeClock, waitUntil;

import 'app_test.dart' show Probe;

void main() {
  late FakeClock clock;
  late TwkApp app;
  late Future<void> done;
  late List<(bool, bool)> settled; // quitting, whether run had completed
  late bool ended;

  setUp(() {
    clock = FakeClock();
    settled = [];
    ended = false;
  });

  void start(HeadlessTerminal term, {void Function(InputEvent)? onEvent}) {
    app = TwkApp(term, maxFps: 1000, clock: clock.clock)
      ..onInputSettled = () => settled.add((app.quitting, ended));
    final probe = Probe(
      app.screen.styles.pen(const Pen()),
      clock: clock.clock,
    );
    done = clock.run(
      () => app
          .run(probe, onEvent ?? (_) => app.requestFrame())
          .whenComplete(() => ended = true),
    );
  }

  test(
    'quitting is false until quit is called, and quit twice is one',
    () async {
      final term = HeadlessTerminal();
      start(term);
      await clock.elapse(const Duration(milliseconds: 30));
      expect(app.quitting, isFalse);
      app
        ..quit()
        ..quit();
      expect(app.quitting, isTrue);
      await clock.elapseUntil(done);
    },
  );

  test('a key that quits is acknowledged as quitting before run '
      'completes', () async {
    final term = HeadlessTerminal();
    start(term, onEvent: (_) => app.quit());
    await clock.elapse(const Duration(milliseconds: 30));
    term.type('q');
    await clock.elapseUntil(done);
    await waitUntil(() => settled.isNotEmpty, 'the acknowledgement');
    expect(settled.first, (true, false));
    expect(ended, isTrue);
  });

  test('a quit nothing was read for is acknowledged too', () async {
    final term = HeadlessTerminal();
    start(term);
    await clock.elapse(const Duration(milliseconds: 30));
    app.quit();
    await clock.elapseUntil(done);
    await waitUntil(() => settled.isNotEmpty, 'the acknowledgement');
    expect(settled.first, (true, false));
  });
}
