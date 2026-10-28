// runApp on a terminal in memory, on a fake clock it is handed: each
// option it takes reaches the binding it runs the app with.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart' show FakeClock;

import 'harness.dart';

void main() {
  final logs = LogSink();
  const viewport = Viewport.fixed(2, 1, 10, 3);

  // the option, whether it takes the inline mode, runApp started with an
  // app, a terminal, a clock and a value of the option other than its
  // default, and what of the binding shows that value
  final cases =
      <
        (
          String,
          bool,
          Future<void> Function(Widget, TerminalBackend, Stopwatch),
          Object? Function(AppBinding),
          Matcher,
        )
      >[
        (
          'maxFps',
          false,
          (app, term, clock) =>
              runApp(app, terminal: term, clock: clock, maxFps: 25),
          (b) => b.twkApp.maxFps,
          equals(25),
        ),
        (
          'maxInlineRows',
          true,
          (app, term, clock) => runApp(
            app,
            mode: ScreenMode.inline,
            terminal: term,
            clock: clock,
            maxInlineRows: 3,
          ),
          (b) => b.twkApp.maxInlineRows,
          equals(3),
        ),
        (
          'clearInlineOnExit',
          true,
          (app, term, clock) => runApp(
            app,
            mode: ScreenMode.inline,
            terminal: term,
            clock: clock,
            clearInlineOnExit: true,
          ),
          (b) => b.twkApp.clearInlineOnExit,
          isTrue,
        ),
        (
          'logs',
          false,
          (app, term, clock) =>
              runApp(app, terminal: term, clock: clock, logs: logs),
          (b) => b.twkApp.logs,
          same(logs),
        ),
        (
          'exitOnCtrlC',
          false,
          (app, term, clock) =>
              runApp(app, terminal: term, clock: clock, exitOnCtrlC: false),
          (b) => b.exitOnCtrlC,
          isFalse,
        ),
        (
          'viewport',
          true,
          (app, term, clock) => runApp(
            app,
            mode: ScreenMode.inline,
            terminal: term,
            clock: clock,
            viewport: viewport,
          ),
          (b) => b.twkApp.viewport,
          equals(viewport),
        ),
        // both ways, as the default is what TWK_SCREEN_READER says
        for (final on in [true, false])
          (
            'screenReader: $on',
            false,
            (app, term, clock) =>
                runApp(app, terminal: term, clock: clock, screenReader: on),
            (b) => b.screenReader,
            equals(on),
          ),
      ];

  for (final (option, inline, start, shown, matcher) in cases) {
    test('runApp hands $option and its clock to the binding', () async {
      final clock = FakeClock();
      final key = GlobalKey<ProbeState>();
      final term = clock.run(
        () => HeadlessTerminal(
          width: 20,
          height: 6,
          options: TerminalOptions(alternateScreen: !inline),
        ),
      );
      final done = clock.run(
        () => start(
          Probe(key: key, (_) => const Label('app')),
          term,
          clock.stopwatch,
        ),
      );
      await clock.settle();
      final binding = AppBinding.of(key.currentContext!);
      expect(binding.twkApp.clock, same(clock.stopwatch));
      expect(shown(binding), matcher);
      binding.quit();
      await clock.elapseUntil(done);
      expect(term.closed, isTrue);
    });
  }
}
