/// The progress of a [Cli], as what its output can do shows it: one
/// operation with a spinner ([CliProgress]), or many tasks with bars, rate
/// and time left ([runTasks], behind [Cli.tasks]).
///
/// @docImport 'cli.dart';
library;

import 'dart:async';

import 'package:meta/meta.dart';

import '../../twk.dart';

import 'capabilities.dart';
import 'cli.dart';
import 'prompts.dart' show lineWidget;
import 'session.dart';

// Examples can assume:
// late Cli cli;
// Future<int> writeFiles() async => 3;

/// How a progress shows itself, from what the output can do, fixed when it
/// starts.
enum _Look {
  /// Live in the inline session: a spinner or a list, redrawn.
  live,

  /// Lines on a terminal that does not redraw: the message on start, each
  /// changed one, the closing line.
  lines,

  /// The closing line alone: the output is no terminal.
  outcome;

  static _Look of(Cli cli) {
    if (cli.mode == CliMode.interactive && !cli.sessionEnded) {
      return live;
    }
    return cli.terminal.capabilities.outputIsTerminal ? lines : outcome;
  }
}

/// How often what is live shows the time again.
const _tick = Duration(milliseconds: 100);

/// An operation going on, shown until it ends in one line saying how it
/// went: [Cli.progress] starts one.
///
/// What it shows follows what the output can do, fixed when it starts:
///
/// * In the interactive mode (a terminal that redraws, somebody at it): a
///   spinner, the message and the time so far, live in the inline session
///   below what is live there already, and below the prompts asked while
///   it runs; lines logged meanwhile land above it. The terminal's tab
///   shows a progress going on (OSC 9;4, where the terminal takes it).
///   The closing line, committed in its place, carries the time it took:
///   `✓ Built in 3.1 s`.
/// * On a terminal that does not redraw (`NO_COLOR`, `TERM=dumb`,
///   `--no-color`, and where nobody answers, `CI` or `--no-input`): the
///   message as it starts, each changed message from [update], and the
///   closing line, `✓ Built`.
/// * Where the output is no terminal (a pipe, a file, a CI log): the
///   closing line alone, so the record holds the outcome and no frames.
///
/// The closing line is written once, by whichever of [complete], [fail]
/// and [cancel] comes first ([cancel] writes none); every later call is
/// ignored, and so is [update]. [run] closes it on its body's outcome, so
/// an error cannot leave a spinner, and the frames it asks for, going.
/// Its lines are written whatever the console's level, as a prompt's
/// are.
///
/// ```dart
/// final count = await cli
///     .progress('Writing files')
///     .run(writeFiles, done: (n) => 'Wrote $n files');
/// ```
final class CliProgress {
  /// Starts showing [message] on the console's terminal: what
  /// [Cli.progress] does.
  @internal
  CliProgress(this._cli, String message)
    : _message = message,
      _look = _Look.of(_cli),
      _clock = _cli.terminal.clock.stopwatch() {
    switch (_look) {
      case _Look.live:
        unawaited(
          _cli.session().then(
            _opened,
            onError: (Object _) {
              // the session's error is its opener's: shown as lines here
              _openFailed = true;
              if (_closing case final line?) {
                _cli.writeLine(line);
              }
            },
          ),
        );
      case _Look.lines:
        _writeMessage(message);
      case _Look.outcome:
        break;
    }
  }

  final Cli _cli;
  final _Look _look;
  final Stopwatch _clock;
  String _message;

  // the message written last, in the lines look
  String? _written;

  CliSession? _session;
  CliLive? _live;
  var _openFailed = false;

  // the closing line of a progress that ended before the session opened
  List<Span>? _closing;
  var _done = false;

  /// Whether it is still going: none of [complete], [fail] and [cancel]
  /// has been called.
  bool get isActive => !_done;

  /// What it says it is doing.
  String get message => _message;

  /// How long it has gone on, or went on until it was closed.
  Duration get elapsed => _clock.elapsed;

  /// Says [message] while the operation goes on: shown in place of the
  /// last one where it is live, written as a line on a terminal that does
  /// not redraw where it is not the one written last, kept for the closing
  /// line where the output is no terminal.
  void update(String message) {
    if (_done) {
      return;
    }
    _message = message;
    switch (_look) {
      case _Look.live:
        _live?.update(_view());
      case _Look.lines:
        _writeMessage(message);
      case _Look.outcome:
        break;
    }
  }

  /// Ends it done, its closing line `✓` and [message], else the last one.
  void complete([String? message]) => _finish(done: true, message);

  /// Ends it failed, its closing line `✗` and [message], else the last one.
  void fail([String? message]) => _finish(done: false, message);

  /// Ends it without a closing line: what was live goes.
  void cancel() {
    if (_done) {
      return;
    }
    _done = true;
    _clock.stop();
    _live?.remove();
  }

  /// Runs [body] under it and closes it on the outcome: [complete] with
  /// [done]'s message for the value, [fail] with [failed]'s for the error,
  /// which is thrown again. Completes with the body's value.
  ///
  /// Closed by [body] itself, it stays as the body left it. Should [done]
  /// or [failed] throw, it is cancelled and that error goes on.
  Future<T> run<T>(
    FutureOr<T> Function() body, {
    String Function(T result)? done,
    String Function(Object error)? failed,
  }) async {
    final T result;
    try {
      result = await body();
    } on Object catch (error) {
      try {
        fail(failed?.call(error));
      } finally {
        cancel();
      }
      rethrow;
    }
    try {
      complete(done?.call(result));
    } finally {
      cancel();
    }
    return result;
  }

  void _opened(CliSession session) {
    _session = session;
    if (_closing case final line?) {
      _closing = null;
      _commit(session, line);
    } else if (!_done) {
      _live = session.mount(_view(), last: true);
    }
  }

  void _finish(String? message, {required bool done}) {
    if (_done) {
      return;
    }
    _done = true;
    _clock.stop();
    final theme = _cli.theme;
    final line = [
      if (done) Span('✓ ', theme.success) else Span('✗ ', theme.error),
      Span(_oneLine(message ?? _message)),
      if (_look == _Look.live)
        Span(' in ${formatTook(_clock.elapsed)}', theme.hint),
    ];
    if (_look != _Look.live || _openFailed) {
      _cli.writeLine(line);
      return;
    }
    final session = _session;
    if (session == null) {
      // committed once the session is open
      _closing = line;
      return;
    }
    _commit(session, line);
  }

  void _commit(CliSession session, List<Span> line) {
    if (!session.isOpen) {
      // the session ended under it (Ctrl+C): the terminal is back
      _cli.writeLine(line);
      return;
    }
    unawaited(session.commit(lineWidget(line)));
    _live?.remove();
  }

  void _writeMessage(String message) {
    if (message != _written) {
      _written = message;
      _cli.writeLine([Span(_oneLine(message))]);
    }
  }

  Widget _view() => _SpinnerView(
    message: _oneLine(_message),
    clock: _clock,
    hint: _cli.theme.hint,
  );
}

/// Runs [body] with a [ProgressTracker] whose tasks [cli] shows as what its
/// output can do: what [Cli.tasks] does.
///
/// * live: a [ProgressList] of [columns] in the inline session, below what
///   is live there and below the prompts asked meanwhile, the tab's
///   progress (OSC 9;4) following how much of all of it is done; once the
///   body ends, the list as it stands is committed in its place. With
///   [hideFinished] a task done or skipped leaves the list, its
///   [ProgressTask.summary] committed above it.
/// * lines: each task's label as it is set going and as it changes while
///   it runs, and its summary once it is done, failed or skipped.
/// * outcome: each task's summary as it ends.
@internal
Future<T> runTasks<T>(
  Cli cli,
  FutureOr<T> Function(ProgressTracker tracker) body, {
  List<ProgressColumn>? columns,
  bool hideFinished = false,
  ProgressBarShape barShape = ProgressBarShape.line,
  int? maxBarWidth = 30,
}) async {
  final tracker = ProgressTracker(clock: cli.terminal.clock.stopwatch());
  final shown = columns ?? ProgressList.defaultColumns;
  var look = _Look.of(cli);
  CliSession? session;
  if (look == _Look.live) {
    try {
      session = await cli.session();
    } on Object {
      look = cli.terminal.capabilities.outputIsTerminal
          ? _Look.lines
          : _Look.outcome;
    }
  }
  void summary(ProgressTask task) {
    final line = summaryLine(task, cli);
    if (session case final session? when session.isOpen) {
      unawaited(session.commit(lineWidget(line)));
    } else {
      cli.writeLine(line);
    }
  }

  final StreamSubscription<ProgressTask>? finished;
  final void Function()? announce;
  CliLive? live;
  if (session != null) {
    live = session.mount(
      _TasksView(
        tracker: tracker,
        columns: shown,
        hideFinished: hideFinished,
        barShape: barShape,
        maxBarWidth: maxBarWidth,
      ),
      last: true,
    );
    announce = null;
    finished = hideFinished
        ? tracker.onTaskFinished.listen((task) {
            if (task.status != TaskStatus.failed) {
              summary(task);
            }
          })
        : null;
  } else {
    final labels = Expando<String>();
    if (look == _Look.lines) {
      announce = () {
        for (final task in tracker.tasks) {
          if (task.status == TaskStatus.running && labels[task] != task.label) {
            labels[task] = task.label;
            cli.writeLine([Span(_oneLine(task.label))]);
          }
        }
      };
      tracker.addListener(announce);
    } else {
      announce = null;
    }
    finished = tracker.onTaskFinished.listen(summary);
  }
  try {
    return await Future<T>.sync(() => body(tracker));
  } finally {
    await finished?.cancel();
    if (announce != null) {
      tracker.removeListener(announce);
    }
    Future<void>? written;
    if (session != null && session.isOpen) {
      final left = tracker.tasks.any((t) => !hideFinished || _stays(t));
      if (left) {
        written = session.commit(
          ProgressList(
            tracker: tracker,
            columns: shown,
            hideFinished: hideFinished,
            barShape: barShape,
            maxBarWidth: maxBarWidth,
          ),
        );
      }
    }
    live?.remove();
    await written;
    tracker.dispose();
  }
}

/// Whether [task] stays in a list that hides the finished ones.
bool _stays(ProgressTask task) =>
    task.status != TaskStatus.done && task.status != TaskStatus.skipped;

/// [task]'s [ProgressTask.summary] as a line, its mark in the theme's
/// success, error or hint.
@internal
List<Span> summaryLine(ProgressTask task, Cli cli) {
  final summary = _oneLine(task.summary);
  final theme = cli.theme;
  final space = summary.indexOf(' ');
  if (space < 0) {
    return [Span(summary)];
  }
  return [
    Span(summary.substring(0, space), switch (task.status) {
      TaskStatus.done => theme.success,
      TaskStatus.failed => theme.error,
      _ => theme.hint,
    }),
    Span(summary.substring(space)),
  ];
}

/// [text] on one line: its line breaks and tabs a space.
String _oneLine(String text) => text.replaceAll(_breaks, ' ');

final _breaks = RegExp(r'[\r\n\t\v\f]+');

/// Frame callbacks of an app every [_tick] of its clock, counted from
/// its start, while started: what the views show the time again by.
final class _Ticks {
  _Ticks(this.onTick);

  final void Function() onTick;

  AppBinding? _binding;
  int? _callback;

  /// Calls [onTick] at the next step of [binding]'s clock, once; nothing
  /// without a binding.
  void next(AppBinding? binding) {
    if (!identical(binding, _binding)) {
      stop();
      _binding = binding;
    }
    if (binding == null || _callback != null) {
      return;
    }
    final step = binding.frameTime.inMicroseconds ~/ _tick.inMicroseconds;
    _callback = binding.scheduleFrameCallback((_) {
      _callback = null;
      onTick();
    }, at: _tick * (step + 1));
  }

  void stop() {
    if (_callback case final callback?) {
      _callback = null;
      _binding?.cancelFrameCallback(callback);
    }
  }
}

/// A spinner, [message] and the time so far on [clock] (`⠹ Building
/// (1.2 s)`), the message cut off with an ellipsis where the row is short;
/// the terminal's tab shows a progress going on.
final class _SpinnerView extends StatefulWidget {
  const _SpinnerView({
    required this.message,
    required this.clock,
    required this.hint,
  });

  final String message;
  final Stopwatch clock;
  final Style hint;

  @override
  State<_SpinnerView> createState() => _SpinnerViewState();
}

final class _SpinnerViewState extends State<_SpinnerView> {
  late final _ticks = _Ticks(_ticked);

  void _ticked() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ticks.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _ticks.next(AppBinding.maybeOf(context));
    return TerminalProgress(
      child: Row(
        children: [
          const Spinner(),
          const SizedBox(width: 1),
          Flexible(
            child: Text(
              widget.message,
              wrap: TextWrap.none,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            ' (${formatTook(widget.clock.elapsed)})',
            style: widget.hint,
            wrap: TextWrap.none,
          ),
        ],
      ),
    );
  }
}

/// The [ProgressList] of [tracker]'s tasks, the terminal's tab showing how
/// much of all of them is done: the mean of their fractions, a task
/// without a total counted as nothing until it ends and as all of it
/// after; indeterminate while no task has a total, in the error state once
/// one failed.
final class _TasksView extends StatefulWidget {
  const _TasksView({
    required this.tracker,
    required this.columns,
    required this.hideFinished,
    required this.barShape,
    required this.maxBarWidth,
  });

  final ProgressTracker tracker;
  final List<ProgressColumn> columns;
  final bool hideFinished;
  final ProgressBarShape barShape;
  final int? maxBarWidth;

  @override
  State<_TasksView> createState() => _TasksViewState();
}

final class _TasksViewState extends State<_TasksView> {
  late final _ticks = _Ticks(_changed);

  @override
  void initState() {
    super.initState();
    widget.tracker.addListener(_changed);
  }

  @override
  void dispose() {
    _ticks.stop();
    widget.tracker.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.tracker.tasks;
    if (tasks.any((t) => t.status == TaskStatus.running)) {
      // what the tasks did since is read again at the next step
      _ticks.next(AppBinding.maybeOf(context));
    } else {
      _ticks.stop();
    }
    return TerminalProgress(
      state: tasks.any((t) => t.status == TaskStatus.failed)
          ? ProgressState.error
          : ProgressState.normal,
      value: overallFraction(tasks),
      child: ProgressList(
        tracker: widget.tracker,
        columns: widget.columns,
        hideFinished: widget.hideFinished,
        barShape: widget.barShape,
        maxBarWidth: widget.maxBarWidth,
      ),
    );
  }
}

/// How much of all of [tasks] is done, from 0 to 1: the mean of their
/// fractions, a task without a total counted as nothing while it is
/// pending or running and as all of it once it ended; null while none has
/// a total.
@internal
double? overallFraction(List<ProgressTask> tasks) {
  if (!tasks.any((t) => t.total != null)) {
    return null;
  }
  var sum = 0.0;
  for (final task in tasks) {
    sum +=
        task.fraction ??
        (task.status == TaskStatus.pending || task.status == TaskStatus.running
            ? 0
            : 1);
  }
  return sum / tasks.length;
}
