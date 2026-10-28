// The binding of an app on a terminal in memory, on a fake clock: the app
// shown in either screen mode, rebuilds before frames, input to the
// listeners, quitting and what is left after it.
// ignore_for_file: avoid_print
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';
import 'package:twk_test/vt_terminal.dart';

import 'harness.dart';

void main() {
  test('the app is shown full screen, and AppBinding.of(context).quit() '
      'ends it with the terminal restored', () async {
    final key = GlobalKey<ProbeState>();
    final run = Run(
      Probe(
        key: key,
        (_) => column(const [Label('hello'), Label('world')]),
      ),
    );
    await run.settle();
    expect(run.rows, ['hello', 'world', '', '']);
    expect(run.term.closed, isFalse);
    final binding = AppBinding.of(key.currentContext!);
    expect(binding.mode, ScreenMode.fullscreen);
    binding.quit();
    await run.ended();
    expect(run.term.closed, isTrue);
  });

  test('in the inline mode the app is a region below the history as tall '
      'as it, which stays when it ends', () async {
    final clock = FakeClock();
    final term = clock.run(() => VtTerminal(height: 6, history: [r'$ app']));
    final key = GlobalKey<ProbeState>();
    final done = clock.run(
      () => AppBinding(term, maxFps: 1000, clock: clock.stopwatch).run(
        Probe(
          key: key,
          (_) => column(const [Label('one'), Label('two')]),
        ),
      ),
    );
    await clock.settle();
    expect(term.lines, [r'$ app', 'one', 'two', '', '', '']);
    final binding = AppBinding.of(key.currentContext!);
    expect(binding.mode, ScreenMode.inline);
    binding.quit();
    await clock.elapseUntil(done);
    expect(term.closed, isTrue);
    expect(term.lines.take(3), [r'$ app', 'one', 'two']);
    expect(term.vt.cy, 3, reason: 'the cursor on the line below the region');
  });

  test('outside an app there is no binding: AppBinding.of is a StateError '
      'naming the widget that asked', () {
    late BuildContext context;
    RootWidget(
      child: Builder(
        builder: (c) {
          context = c;
          return const Label('x');
        },
      ),
    ).attach(BuildOwner());
    expect(AppBinding.maybeOf(context), isNull);
    expect(
      () => AppBinding.of(context),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'no app above Builder: runApp runs one',
        ),
      ),
    );
  });

  test('a terminal in the other screen mode than the one asked for is an '
      'ArgumentError, and is left alone', () async {
    final term = HeadlessTerminal();
    await expectLater(
      runApp(const Label('x'), mode: ScreenMode.inline, terminal: term),
      throwsArgumentError,
    );
    expect(term.frames, isEmpty);
    expect(term.closed, isFalse);
  });

  test('the text is in the order the terminal needs (AppBinding.textOrder): '
      'visual where the app orders right-to-left text, logical where the '
      'terminal does', () async {
    for (final (bidi, order) in [
      (BidiReordering.app, TextOrder.visual),
      (BidiReordering.terminal, TextOrder.logical),
    ]) {
      final key = GlobalKey<ProbeState>();
      final clock = FakeClock();
      final term = clock.run(() => HeadlessTerminal(bidi: bidi));
      final done = clock.run(
        () => AppBinding(
          term,
          clock: clock.stopwatch,
        ).run(Probe(key: key, (_) => const Label('x'))),
      );
      await clock.settle();
      final binding = AppBinding.of(key.currentContext!);
      expect(binding.textOrder, order, reason: '$bidi');
      binding.quit();
      await clock.elapseUntil(done);
    }
  });

  test('a terminal ordered otherwise than bidi asks is an ArgumentError, '
      'and is left alone', () async {
    final term = HeadlessTerminal(bidi: BidiReordering.terminal);
    await expectLater(
      runApp(const Label('x'), terminal: term, bidi: BidiReordering.app),
      throwsArgumentError,
    );
    expect(term.frames, isEmpty);
    expect(term.closed, isFalse);
  });

  test('setState rebuilds before the next frame; several in a row are one '
      'build and one frame', () async {
    final key = GlobalKey<ProbeState>();
    final run = Run(Probe(key: key, (s) => Label('count ${s.count}')));
    await run.settle();
    final state = key.currentState!;
    expect((state.builds, run.term.frames.length), (1, 1));
    for (var i = 0; i < 3; i++) {
      state.change(() => state.count++);
    }
    await run.settle();
    expect((state.builds, run.term.frames.length), (2, 2));
    expect(run.rows.first, 'count 3');
    run.term.type('\x03');
    await run.ended();
  });

  testTwk('setState calls closer than a frame apart build once a frame, '
      'at most maxFps times a second', (t) async {
    // on the tester's clock, which moves only as the test says: the gaps
    // are the binding's, not the machine's
    final key = GlobalKey<ProbeState>();
    final builtAt = <Duration>[];
    await t.pumpWidget(
      Probe(key: key, (s) {
        builtAt.add(t.clock.elapsed);
        return Label('count ${s.count}');
      }),
      size: (20, 4),
      maxFps: 20,
    );
    final state = key.currentState!;
    final changes = t.clock.run(
      () => Timer.periodic(
        const Duration(milliseconds: 2),
        (_) => state.change(() => state.count++),
      ),
    );
    await t.pump(const Duration(milliseconds: 150));
    changes.cancel();
    await t.pump(const Duration(milliseconds: 100));
    expect(state.count, 75);
    expect(state.builds, greaterThan(2));
    expect(t.terminal.frames, hasLength(state.builds));
    for (var i = 1; i < builtAt.length; i++) {
      expect(
        builtAt[i] - builtAt[i - 1],
        greaterThanOrEqualTo(const Duration(milliseconds: 50)),
      );
    }
    expect(t.lines.first, 'count ${state.count}');
  });

  test('keys typed before the first frame go to the listeners it '
      'mounts', () async {
    final seen = <String>[];
    final run = Run(
      InputListener(
        onEvent: (e) {
          if (e is KeyEvent) {
            seen.add(e.char);
          }
          return e is KeyEvent && e.char == 'a';
        },
        child: const Label('x'),
      ),
    );
    run.term.type('a');
    await run.settle();
    expect(seen, ['a']);
    run.term.type('\x03');
    await run.ended();
  });

  test('input goes to the InputListeners, the one mounted last first, until '
      'one returns true', () async {
    final seen = <String>[];
    bool listener(String name, InputEvent e, {required String takes}) {
      if (e is KeyEvent) {
        seen.add('$name ${e.char}');
      }
      return e is KeyEvent && e.char == takes;
    }

    final run = Run(
      InputListener(
        onEvent: (e) => listener('outer', e, takes: 'b'),
        child: InputListener(
          onEvent: (e) => listener('inner', e, takes: 'a'),
          child: const Label('x'),
        ),
      ),
    );
    await run.settle();
    run.term.type('ab');
    await run.settle();
    expect(seen, ['inner a', 'inner b', 'outer b']);
    run.term.type('\x03');
    await run.ended();
  });

  test(
    'an InputListener sees the events from its mount to its unmount',
    () async {
      final seen = <String>[];
      final key = GlobalKey<ProbeState>();
      final run = Run(
        Probe(
          key: key,
          (s) => s.count == 0
              ? InputListener(
                  onEvent: (e) {
                    if (e is KeyEvent) {
                      seen.add(e.char);
                    }
                    return true;
                  },
                  child: const Label('x'),
                )
              : const Label('y'),
        ),
      );
      await run.settle();
      run.term.type('a');
      final state = key.currentState!;
      state.change(() => state.count++);
      await run.settle();
      run.term.type('b');
      expect(seen, ['a']);
      run.term.type('\x03');
      await run.ended();
    },
  );

  test(
    'Ctrl+C that no listener takes quits; one a listener takes does not',
    () async {
      var take = true;
      final run = Run(
        InputListener(onEvent: (_) => take, child: const Label('x')),
      );
      await run.settle();
      run.term.type('\x03');
      await run.settle();
      expect(run.term.closed, isFalse);
      take = false;
      run.term.type('\x03');
      await run.ended();
      expect(run.term.closed, isTrue);
    },
  );

  test('with exitOnCtrlC false, Ctrl+C does not quit', () async {
    final key = GlobalKey<ProbeState>();
    final run = Run(
      Probe(key: key, (_) => const Label('x')),
      exitOnCtrlC: false,
    );
    await run.settle();
    run.term.type('\x03');
    await run.settle();
    expect(run.term.closed, isFalse);
    AppBinding.of(key.currentContext!).quit();
    await run.ended();
  });

  test('when the app ends, its states are disposed', () async {
    final disposed = <String>[];
    final run = Run(
      Column(
        children: [
          Probe((_) => const Label('a'), onDispose: () => disposed.add('a')),
          Probe((_) => const Label('b'), onDispose: () => disposed.add('b')),
        ],
      ),
    );
    await run.settle();
    expect(disposed, isEmpty);
    run.term.type('\x03');
    await run.ended();
    expect(disposed, unorderedEquals(['a', 'b']));
  });

  test('what the first build removes is disposed with it', () async {
    final disposed = <String>[];
    final key = GlobalKey<ProbeState>();
    // the child's initState has its parent build something else instead
    void replace(ProbeState _) {
      final parent = key.currentState!;
      parent.change(() => parent.count++);
    }

    final run = Run(
      Probe(
        key: key,
        (s) => s.count == 0
            ? Probe(
                (_) => const Label('a'),
                onInit: replace,
                onDispose: () => disposed.add('a'),
              )
            : const Label('b'),
      ),
    );
    await run.settle();
    expect(run.rows.first, 'b');
    expect(disposed, ['a']);
    run.term.type('\x03');
    await run.ended();
  });

  test('what a LayoutBuilder removes is disposed in the frame that lays it '
      'out, which asks for no other', () async {
    // the frame loop schedules each frame with a timer in the app's zone
    var frames = 0;
    final disposedIn = <int>[];
    final run = Run(
      LayoutBuilder(
        builder: (context, c) => c.maxW > 6
            ? Probe(
                (_) => const Label('wide'),
                onDispose: () => disposedIn.add(frames),
              )
            : const Label('narrow'),
      ),
      width: 8,
      height: 1,
      zone: ZoneSpecification(
        createTimer: (self, parent, zone, duration, f) {
          frames++;
          return parent.createTimer(zone, duration, f);
        },
      ),
    );
    await run.settle();
    expect(run.rows, ['wide']);
    final before = frames;
    run.term.resize(6, 1);
    run.vt.resize(6, 1);
    await run.settle();
    expect(run.rows, ['narrow']);
    expect(disposedIn, [before + 1]);
    expect(frames, before + 1);
    run.term.type('\x03');
    await run.ended();
  });

  test('print and log() in builds, the first one included, go to the log '
      'sink', () async {
    final key = GlobalKey<ProbeState>();
    final run = Run(
      Probe(key: key, (s) {
        print('build ${s.count}');
        log('logged ${s.count}');
        return const Label('x');
      }),
    );
    await run.settle();
    final state = key.currentState!;
    state.change(() => state.count++);
    await run.settle();
    expect(run.logged(LogLevel.info), [
      'build 0',
      'logged 0',
      'build 1',
      'logged 1',
    ]);
    run.term.type('\x03');
    await run.ended();
  });

  test('a timer the first build starts runs in the app: its error ends the '
      'app after the terminal is restored', () async {
    final run = Run(
      Probe(
        (_) => const Label('x'),
        onInit: (_) => Timer(
          const Duration(milliseconds: 5),
          () => throw StateError('later'),
        ),
      ),
    );
    await expectLater(run.ended(), throwsStateError);
    expect(run.term.closed, isTrue);
  });

  test('a resize lays the app out at the new size', () async {
    final run = Run(const Fill('#'), width: 3, height: 2);
    await run.settle();
    expect(run.rows, ['###', '###']);
    run.term.resize(4, 3);
    run.vt.resize(4, 3);
    await run.settle();
    expect(run.rows, ['####', '####', '####']);
    run.term.type('\x03');
    await run.ended();
  });

  test('attachRootWidget shows another app; widgets that match keep their '
      'state', () async {
    final key = GlobalKey<ProbeState>();
    final run = Run(Probe(key: key, (s) => Label('a ${s.count}')));
    await run.settle();
    final state = key.currentState!..count = 7;
    AppBinding.of(key.currentContext!).attachRootWidget(
      Probe(key: key, (s) => Label('b ${s.count}')),
    );
    await run.settle();
    expect(key.currentState, same(state));
    expect(run.rows.first, 'b 7');
    run.term.type('\x03');
    await run.ended();
  });

  test('the environment given is what the binding reads: TWK_SCREEN_READER '
      "and TWK_DEBUG, the core's names known without a list of its own; "
      'given none, nothing is on', () {
    final asked = AppBinding(
      HeadlessTerminal(),
      environment: const {
        'TWK_SCREEN_READER': '1',
        'TWK_DEBUG': 'overlay,frames,relayout,mine',
      },
    );
    expect(asked.screenReader, isTrue);
    expect(asked.debug.keys, isTrue);
    expect(asked.debug.overlay, isTrue);
    expect(asked.debug.relayout, isTrue);
    expect(asked.twkApp.framesInRow, isTrue);
    final warnings = [
      for (final r in asked.twkApp.logs.records)
        if (r.level == LogLevel.warning) r.message,
    ];
    const mine =
        "TWK_DEBUG names nothing it knows as 'mine': it takes keys, overlay, "
        'console, rainbow, relayout, frames, timeline, logs, comma-separated';
    expect(warnings, [mine]);
    expect(
      AppBinding(
        HeadlessTerminal(),
        screenReader: false,
        environment: const {'TWK_SCREEN_READER': '1'},
      ).screenReader,
      isFalse,
      reason: 'the parameter over the environment',
    );

    final none = AppBinding(HeadlessTerminal(), environment: const {});
    expect(none.twkApp.environment, isEmpty);
    expect(none.screenReader, isFalse);
    expect(none.debug.keys, isFalse);
    expect(none.debug.overlay, isFalse);
    expect(none.twkApp.logs.records, isEmpty);
  });

  test("with no environment given, the terminal's TWK_SCREEN_READER and "
      "TWK_DEBUG (TerminalInfo.settings) over the process's turn the "
      'screen reader and the debug aids on, through runApp too; an '
      'environment given, as twk_ssh gives none, keeps them off', () async {
    const settings = {'TWK_SCREEN_READER': '1', 'TWK_DEBUG': 'overlay,frames'};
    final linked = AppBinding(HeadlessTerminal(settings: settings));
    expect(linked.screenReader, isTrue);
    expect(linked.debug.keys, isTrue);
    expect(linked.debug.overlay, isTrue);
    expect(linked.twkApp.framesInRow, isTrue);
    final off = AppBinding(
      HeadlessTerminal(
        settings: const {'TWK_SCREEN_READER': '0', 'TWK_DEBUG': ''},
      ),
    );
    expect(
      (off.screenReader, off.debug.keys, off.debug.overlay),
      (false, false, false),
      reason: "set otherwise, whatever the process's says",
    );
    final given = AppBinding(
      HeadlessTerminal(settings: settings),
      environment: const {},
    );
    expect(
      (given.screenReader, given.debug.keys, given.twkApp.framesInRow),
      (false, false, false),
    );

    final key = GlobalKey<ProbeState>();
    final clock = FakeClock();
    final term = clock.run(
      () => HeadlessTerminal(settings: const {'TWK_SCREEN_READER': '1'}),
    );
    final done = clock.run(
      () => runApp(
        Probe(key: key, (_) => const Label('x')),
        terminal: term,
        clock: clock.stopwatch,
      ),
    );
    await clock.settle();
    final binding = AppBinding.of(key.currentContext!);
    expect(binding.screenReader, isTrue, reason: 'runApp leaves it to them');
    binding.quit();
    await clock.elapseUntil(done);
  });
}
