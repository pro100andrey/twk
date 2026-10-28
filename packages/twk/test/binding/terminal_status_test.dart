// TerminalProgress: the program's progress in the terminal's tab (OSC
// 9;4) as the last one mounted says, written when it changes, taken away
// when none is mounted, while the terminal is handed to another program
// and when the app ends; nothing where the terminal is not known to show
// it. The pointer's shape set on an app's status, written where the
// terminal shows one.
import 'dart:async';
import 'dart:convert';

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show InputEvent, TerminalInfo, TerminalStateBackend;
import 'package:twk_test/twk_test.dart' show FakeClock;

import 'harness.dart' show FrameLoop;

/// What a test shows: [progress] around a line of text, which
/// [_ShownState.show] changes.
final class _Shown extends StatefulWidget {
  const _Shown(this.progress, {super.key});

  final Widget Function(Widget child) progress;

  @override
  State<_Shown> createState() => _ShownState();
}

final class _ShownState extends State<_Shown> {
  late Widget Function(Widget child) _progress = widget.progress;

  void show(Widget Function(Widget child) progress) =>
      setState(() => _progress = progress);

  @override
  Widget build(BuildContext context) => _progress(const Text('working'));
}

/// An app showing a progress, run full screen on a terminal in memory that
/// shows a program's progress unless told it doesn't, on [clock].
final class _Run {
  _Run(
    Widget Function(Widget child) progress, {
    bool reports = true,
    Multiplexer multiplexer = Multiplexer.none,
  }) {
    clock.run(() {
      term = HeadlessTerminal(
        width: 20,
        height: 2,
        progressReports: reports,
        multiplexer: multiplexer,
      );
      binding = AppBinding(term, maxFps: 1000, clock: clock.stopwatch);
      done = binding.run(_Shown(progress, key: key));
    });
  }

  /// The time of the app.
  final clock = FakeClock();
  late final HeadlessTerminal term;
  late final AppBinding binding;
  late final Future<void> done;
  final key = GlobalKey<_ShownState>();
  var _read = 0;

  /// What the app wrote since the last call.
  String written() {
    final s = utf8.decode([for (final f in term.frames.skip(_read)) ...f]);
    _read = term.frames.length;
    return s;
  }

  /// The progress the app wrote since the last call, each as `state;percent`.
  List<String> progress() => [
    for (final m in RegExp(
      '\x1b]9;4;([^\x1b]*)\x1b\\\\',
    ).allMatches(written()))
      m[1]!,
  ];

  /// Lets the frame loop run for 30 ms of the app's clock.
  Future<void> settle() => clock.settle();

  /// Shows [progress] from the next frame on.
  Future<void> show(Widget Function(Widget child) progress) async {
    key.currentState!.show(progress);
    await settle();
  }

  /// Ends the app and runs it until it has ended.
  Future<void> quit() async {
    binding.quit();
    await clock.elapseUntil(done);
  }
}

/// [terminal], with the refresh each state was set with kept in
/// [refreshes].
final class _Refreshes implements TerminalStateBackend {
  _Refreshes(this.terminal);

  final HeadlessTerminal terminal;
  final refreshes = <Duration?>[];

  @override
  void setTerminalState(
    Object key,
    String sequence,
    String restore, {
    Duration? refresh,
  }) {
    refreshes.add(refresh);
    terminal.setTerminalState(key, sequence, restore);
  }

  @override
  void restoreTerminalState(Object key) => terminal.restoreTerminalState(key);

  @override
  TerminalInfo get info => terminal.info;

  @override
  int get width => terminal.width;

  @override
  int get height => terminal.height;

  @override
  Stream<InputEvent> get events => terminal.events;

  @override
  void write(Uint8List bytes) => terminal.write(bytes);

  @override
  Future<void> flush() => terminal.flush();

  @override
  Future<void> close() => terminal.close();
}

Widget Function(Widget child) _at(
  double? value, [
  ProgressState state = ProgressState.normal,
]) =>
    (child) => TerminalProgress(state: state, value: value, child: child);

void main() {
  test('as the widget says, written when that changes by a whole '
      'percent or a state; a value not known is indeterminate', () async {
    final run = _Run(_at(0.25));
    await run.settle();
    expect(run.progress(), ['1;25']);
    await run.show(_at(0.252));
    expect(run.progress(), isEmpty);
    await run.show(_at(0.3));
    expect(run.progress(), ['1;30']);
    await run.show(_at(0.3, ProgressState.error));
    expect(run.progress(), ['2;30']);
    await run.show(_at(null, ProgressState.paused));
    expect(run.progress(), ['4']);
    await run.show(_at(null));
    expect(run.progress(), ['3']);
    await run.show(_at(0.9, ProgressState.indeterminate));
    expect(run.progress(), isEmpty);
    await run.show(_at(1.5));
    expect(run.progress(), ['1;100']);
    await run.show(_at(double.nan));
    expect(run.progress(), ['1;0']);
    await run.show(_at(0.5, ProgressState.none));
    expect(run.progress(), ['0']);
    await run.show((child) => child);
    expect(run.progress(), isEmpty);
    await run.quit();
    expect(run.progress(), isEmpty);
  });

  test('of the one mounted last, the one before once it is gone, none '
      'once none is', () async {
    final run = _Run(_at(0.1));
    await run.settle();
    expect(run.progress(), ['1;10']);
    await run.show(
      (child) => TerminalProgress(
        value: 0.1,
        child: Column(
          children: [
            child,
            const TerminalProgress(value: 0.6, child: Text('copying')),
          ],
        ),
      ),
    );
    expect(run.progress(), ['1;60']);
    await run.show(_at(0.1));
    expect(run.progress(), ['1;10']);
    await run.show((child) => child);
    expect(run.progress(), ['0']);
    await run.quit();
  });

  test('taken away when the app ends, and while the terminal is handed to '
      'another program', () async {
    final run = _Run(_at(0.4));
    await run.settle();
    expect(run.progress(), ['1;40']);
    await run.clock.elapseUntil(
      run.clock.run(
        () => run.binding.twkApp.suspend(() async {
          expect(run.progress(), ['0']);
        }),
      ),
    );
    await run.settle();
    expect(run.progress(), ['1;40']);
    await run.quit();
    expect(run.term.closed, isTrue);
    expect(run.progress(), ['0']);
  });

  test('written again every 10 s while it stays the same', () async {
    final clock = FakeClock();
    final term = clock.run(
      () => _Refreshes(
        HeadlessTerminal(width: 20, height: 2, progressReports: true),
      ),
    );
    final binding = clock.run(
      () => AppBinding(term, maxFps: 1000, clock: clock.stopwatch),
    );
    final done = clock.run(
      () => binding.run(_at(0.5)(const Text('working'))),
    );
    await clock.settle();
    binding.quit();
    await clock.elapseUntil(done);
    expect(term.refreshes, [const Duration(seconds: 10)]);
  });

  test(
    'inside tmux as it is: tmux 3.7 shows it in the terminal outside',
    () async {
      final run = _Run(_at(0.5), multiplexer: Multiplexer.tmux);
      await run.settle();
      expect(run.written(), contains('\x1b]9;4;1;50\x1b\\'));
      await run.quit();
    },
  );

  test('nothing where the terminal is not known to show it', () async {
    final run = _Run(_at(0.5), reports: false);
    await run.settle();
    await run.show(_at(0.7));
    await run.quit();
    expect(run.written(), isNot(contains('\x1b]9;4')));
  });

  test("the pointer's shape set on an app's status is written, read back, "
      "and the terminal's own given back once it is null", () async {
    final clock = FakeClock();
    final term = clock.run(
      () => HeadlessTerminal(width: 20, height: 2, pointerShapes: true),
    );
    final binding = clock.run(
      () => AppBinding(term, maxFps: 1000, clock: clock.stopwatch),
    );
    final key = GlobalKey();
    final done = clock.run(() => binding.run(Text('x', key: key)));
    await clock.settle();
    final status = TerminalStatus.of(key.currentContext!)!;
    String written() => utf8.decode([for (final f in term.frames) ...f]);
    expect(status.showsPointerShape, isTrue);
    expect(status.pointerShape, isNull);
    status.pointerShape = PointerShape.wait;
    expect(status.pointerShape, PointerShape.wait);
    expect(written(), contains('\x1b]22;wait\x1b\\'));
    status.pointerShape = null;
    expect(status.pointerShape, isNull);
    expect(written(), endsWith('\x1b]22;\x1b\\'));
    binding.quit();
    await clock.elapseUntil(done);
  });

  test("the pointer's shape is neither set nor written where the terminal "
      'is not known to show it', () async {
    final clock = FakeClock();
    final term = clock.run(() => HeadlessTerminal(width: 20, height: 2));
    final binding = clock.run(
      () => AppBinding(term, maxFps: 1000, clock: clock.stopwatch),
    );
    final key = GlobalKey();
    final done = clock.run(() => binding.run(Text('x', key: key)));
    await clock.settle();
    final status = TerminalStatus.of(key.currentContext!)!;
    expect(status.showsPointerShape, isFalse);
    status.pointerShape = PointerShape.wait;
    expect(status.pointerShape, isNull);
    binding.quit();
    await clock.elapseUntil(done);
    expect(
      utf8.decode([for (final f in term.frames) ...f]),
      isNot(contains('\x1b]22;')),
    );
  });
}
