// Every way AppBinding.run ends unmounts the app: quit, an error of the
// terminal's input (a link's session ending) and an error of the app's own
// code, in an event or in a frame. Its states are disposed before run
// completes, with or without the error, and no timer of theirs or of the
// binding is left: a process that runs many apps (one per SSH session)
// keeps none of an app that ended.
import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show TerminalException, TerminalInfo;
import 'package:twk_test/twk_test.dart' show FakeClock;

import 'harness.dart';

/// A [HeadlessTerminal] whose input can end with an error, as a link's
/// does when its session ends ([TerminalException]).
final class _FailingTerminal implements TerminalBackend {
  _FailingTerminal(this.term) {
    term.events.listen(_events.add, onDone: _events.close);
  }

  final HeadlessTerminal term;
  final _events = StreamController<InputEvent>();

  /// Ends the input with [error].
  void fail(Object error) => _events.addError(error);

  @override
  TerminalInfo get info => term.info;
  @override
  int get width => term.width;
  @override
  int get height => term.height;
  @override
  Stream<InputEvent> get events => _events.stream;
  @override
  void write(Uint8List bytes) => term.write(bytes);
  @override
  Future<void> flush() => term.flush();
  @override
  Future<void> close() => term.close();
}

/// A state that holds a timer of the app's clock and a frame callback an
/// hour away, as a widget that animates or polls does, both let go in
/// its dispose, which [_Holder.onDispose] records.
final class _Holder extends StatefulWidget {
  const _Holder(this.onDispose, {this.child = const Label('held')});

  final void Function() onDispose;
  final Widget child;

  @override
  State<_Holder> createState() => _HolderState();
}

final class _HolderState extends State<_Holder> {
  late final Timer _timer;
  late final int _callback;
  late final AppBinding _binding;

  @override
  void initState() {
    super.initState();
    // the zone is the fake clock's: an hour of the app's clock
    _timer = Zone.current.createTimer(const Duration(hours: 1), () {});
    _binding = AppBinding.of(context);
    _callback = _binding.scheduleFrameCallback(
      (_) {},
      at: _binding.frameTime + const Duration(hours: 1),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    _binding.cancelFrameCallback(_callback);
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Runs [app] on a [_FailingTerminal] on [clock], as the harness's [Run]
/// does on a [HeadlessTerminal].
Future<void> _run(FakeClock clock, _FailingTerminal term, Widget app) =>
    clock.run(
      () => AppBinding(
        term,
        maxFps: 1000,
        clock: clock.stopwatch,
        environment: const {},
      ).run(app),
    );

void main() {
  test('quit: the states are disposed and no timer is left', () async {
    final disposed = <String>[];
    final key = GlobalKey<ProbeState>();
    final run = Run(
      Probe(key: key, (_) => _Holder(() => disposed.add('held'))),
    );
    await run.settle();
    expect(disposed, isEmpty);
    expect(run.clock.pendingTimers, greaterThan(0));
    AppBinding.of(key.currentContext!).quit();
    await run.ended();
    expect(disposed, ['held']);
    // what ending itself scheduled, at no delay, has run
    await run.settle();
    expect(run.clock.pendingTimers, 0);
  });

  test('an error of the input (the session ended): the states are disposed '
      'before run throws it, and no timer is left', () async {
    final clock = FakeClock();
    final term = clock.run(
      () => _FailingTerminal(HeadlessTerminal(width: 20, height: 4)),
    );
    final disposed = <String>[];
    final done = _run(clock, term, _Holder(() => disposed.add('held')));
    unawaited(done.then((_) {}, onError: (_) {}));
    await clock.settle();
    expect(disposed, isEmpty);
    term.fail(const TerminalException('the session ended'));
    final error = await clock
        .elapseUntil(done)
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect(error, isA<TerminalException>());
    expect(term.term.closed, isTrue);
    expect(disposed, ['held']);
    // what ending itself scheduled, at no delay, has run
    await clock.settle();
    expect(clock.pendingTimers, 0);
  });

  test("an error of the app's code in an event: the states are disposed "
      'before run throws it, and no timer is left', () async {
    final disposed = <String>[];
    final run = Run(
      _Holder(
        () => disposed.add('held'),
        child: InputListener(
          onEvent: (_) => throw StateError('boom'),
          child: const Label('x'),
        ),
      ),
    );
    await run.settle();
    run.term.type('a');
    final error = await run.ended().then<Object?>(
      (_) => null,
      onError: (Object e) => e,
    );
    expect(error, isA<WidgetError>());
    expect(disposed, ['held']);
    // what ending itself scheduled, at no delay, has run
    await run.settle();
    expect(run.clock.pendingTimers, 0);
  });

  test(
    "an error of the app's code in a frame, before its build: the "
    'states are disposed before run throws it, and no timer is left',
    () async {
      final disposed = <String>[];
      final key = GlobalKey<ProbeState>();
      final run = Run(
        Probe(key: key, (_) => _Holder(() => disposed.add('held'))),
      );
      await run.settle();
      AppBinding.of(
        key.currentContext!,
      ).scheduleFrameCallback((_) => throw StateError('boom'));
      final error = await run.ended().then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );
      expect(error, isStateError);
      expect(disposed, ['held']);
      // what ending itself scheduled, at no delay, has run
      await run.settle();
      expect(run.clock.pendingTimers, 0);
    },
  );

  test('a state whose dispose throws as the app ends with an error: the '
      "error that ended it is thrown, and the dispose's is logged", () async {
    final run = Run(
      _Holder(
        () => throw StateError('dispose'),
        child: InputListener(
          onEvent: (_) => throw StateError('boom'),
          child: const Label('x'),
        ),
      ),
    );
    await run.settle();
    run.term.type('a');
    final error = await run.ended().then<Object?>(
      (_) => null,
      onError: (Object e) => e,
    );
    expect(error, isA<WidgetError>());
    expect(
      [for (final r in run.logs.records) '${r.error}'],
      contains('Bad state: dispose'),
    );
  });

  test('quit, the middle one of three states throwing in dispose: all three '
      'are disposed, and run throws its error', () async {
    final disposed = <String>[];
    final key = GlobalKey<ProbeState>();
    final run = Run(
      Probe(
        key: key,
        (_) => column([
          _Holder(() => disposed.add('a')),
          _Holder(() {
            disposed.add('b');
            throw StateError('dispose');
          }),
          _Holder(() => disposed.add('c')),
        ]),
      ),
    );
    await run.settle();
    AppBinding.of(key.currentContext!).quit();
    final error = await run.ended().then<Object?>(
      (_) => null,
      onError: (Object e) => e,
    );
    expect('$error', 'Bad state: dispose');
    expect(disposed, ['a', 'b', 'c']);
    await run.settle();
    expect(run.clock.pendingTimers, 0);
  });

  test('an error ending the app, the middle one of three states throwing in '
      "dispose: all three are disposed, the dispose's error is logged once "
      'and the one that ended the app thrown', () async {
    final disposed = <String>[];
    final run = Run(
      InputListener(
        onEvent: (_) => throw StateError('boom'),
        child: column([
          _Holder(() => disposed.add('a')),
          _Holder(() {
            disposed.add('b');
            throw StateError('dispose');
          }),
          _Holder(() => disposed.add('c')),
        ]),
      ),
    );
    await run.settle();
    run.term.type('a');
    final error = await run.ended().then<Object?>(
      (_) => null,
      onError: (Object e) => e,
    );
    expect(error, isA<WidgetError>());
    expect(disposed, ['a', 'b', 'c']);
    expect(
      [
        for (final r in run.logs.records)
          if ('${r.error}' == 'Bad state: dispose') r,
      ],
      hasLength(1),
    );
    await run.settle();
    expect(run.clock.pendingTimers, 0);
  });
}
