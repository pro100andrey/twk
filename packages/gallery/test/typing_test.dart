// The gallery opened at a route that types keys runs on its Terminal
// wrapped in Typing, which passes on every capability the terminal has:
// the window's title and notifications, the progress in its tab, the
// mouse reports switched as the app needs, and handing it to another
// program.
import 'dart:async';
import 'dart:convert';

import 'package:gallery/gallery.dart';
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show
        MouseTracking,
        Terminal,
        TerminalLink,
        mouseTrackingSequence,
        progressSequence,
        titleSequence;
import 'package:twk_test/twk_test.dart' show FakeClock;

import '../bin/gallery.dart' show Typing;

void main() {
  test('under Typing, the gallery sets its title', () async {
    final run = await _Run.start(
      galleryApp(),
      const TerminalOptions(mouse: false),
    );
    await run.clock.elapse(const Duration(milliseconds: 100));
    await run.quit();
    expect(run.link.written, contains(titleSequence('twk gallery')));
  });

  test('under Typing, a notification reaches the terminal', () async {
    final run = await _Run.start(
      const Text('notifies'),
      const TerminalOptions(mouse: false),
      environment: _windowsTerminal,
    );
    await run.settle();
    run.binding.notify('Build', 'done');
    await run.settle();
    await run.quit();
    expect(run.link.written, contains('\x1b]777;notify;Build;done\x1b\\'));
  });

  test('under Typing, the progress in the tab reaches the terminal', () async {
    final run = await _Run.start(
      const TerminalProgress(value: 0.5, child: Text('half')),
      const TerminalOptions(mouse: false),
      environment: _windowsTerminal,
    );
    await run.settle();
    final shown = run.link.written;
    await run.quit();
    expect(
      shown,
      contains(progressSequence(ProgressState.normal, percent: 50)),
    );
  });

  test('under Typing, the mouse reports are switched off for an app that '
      'listens to none', () async {
    final run = await _Run.start(
      const Text('no mouse'),
      const TerminalOptions(),
    );
    await run.settle();
    // before quitting: closing turns the reports off by itself
    final shown = run.link.written;
    await run.quit();
    expect(
      shown,
      contains(mouseTrackingSequence(MouseTracking.drags, MouseTracking.off)),
    );
  });

  test('under Typing, handing the terminal to another program reaches the '
      'terminal, which over a link refuses it', () async {
    final run = await _Run.start(
      const Text('suspends'),
      const TerminalOptions(mouse: false),
    );
    await run.settle();
    var ran = false;
    final suspended = run.binding.twkApp.suspend(() async => ran = true);
    await expectLater(
      run.clock.elapseUntil(suspended),
      throwsA(isA<UnsupportedError>()),
    );
    await run.quit();
    expect(ran, isFalse);
  });
}

/// Windows Terminal, which shows a progress and notifications (OSC 777).
const _windowsTerminal = {'TERM': 'xterm-256color', 'WT_SESSION': '1'};

/// An app running under a fake [clock] on a [Terminal] over [link],
/// wrapped in a [Typing] that types nothing.
final class _Run {
  _Run(this.clock, this.link, this.binding, this.done);

  /// Opens a terminal of [options] over a link of [environment], and runs
  /// [app] on it under [Typing].
  static Future<_Run> start(
    Widget app,
    TerminalOptions options, {
    Map<String, String> environment = const {'TERM': 'xterm-256color'},
  }) async {
    final clock = FakeClock();
    final link = clock.run(() => _Link(environment));
    final terminal = await clock.elapseUntil(
      clock.run(() => Terminal.overLink(link, options)),
    );
    final binding = clock.run(
      () => AppBinding(
        Typing(terminal, const []),
        maxFps: 1000,
        clock: clock.stopwatch,
      ),
    );
    final done = clock.run(() => binding.run(app));
    return _Run(clock, link, binding, done);
  }

  final FakeClock clock;
  final _Link link;
  final AppBinding binding;
  final Future<void> done;

  /// Lets the app show what it was asked to.
  Future<void> settle() => clock.elapse(const Duration(milliseconds: 100));

  /// Ends the app and waits for it.
  Future<void> quit() async {
    binding.quit();
    await clock.elapseUntil(done);
  }
}

/// A terminal at the far end of a link, 100 × 30, of [environment], that
/// answers the probe as a VT220 does, and keeps what is written.
final class _Link implements TerminalLink {
  _Link(this.environment) {
    _input.add(utf8.encode('\x1b[?62;22c'));
  }

  final _input = StreamController<List<int>>();
  final _bytes = <int>[];

  /// Everything written to the terminal.
  String get written => utf8.decode(_bytes);

  @override
  final Map<String, String> environment;

  @override
  bool get windows => false;

  @override
  int get columns => 100;

  @override
  int get lines => 30;

  @override
  int? get eraseChar => 0x7F;

  @override
  void enterRaw() {}

  @override
  void restore() {}

  @override
  Stream<List<int>> get input => _input.stream;

  @override
  void add(List<int> bytes) => _bytes.addAll(bytes);

  @override
  Future<void> flush() async {}

  @override
  Stream<void> get resizes => const Stream.empty();

  @override
  void restoreWith(List<int> bytes) {}

  @override
  Future<void> close() => _input.close();
}
