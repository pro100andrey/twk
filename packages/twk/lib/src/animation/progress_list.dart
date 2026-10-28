/// Many tasks at once, each with its bar, rate and time left: a
/// [ProgressTracker] of [ProgressTask]s, and the [ProgressList] that shows
/// them.
///
/// @docImport 'spinner.dart';
library;

import 'dart:async';
import 'dart:collection';

import 'package:twk_core/twk_core.dart'
    show
        BorderType,
        BoxConstraints,
        PaintContext,
        RenderObject,
        TextSegmenter,
        fitText;

import '../binding/app_binding.dart';
import '../data/chart_glyphs.dart';
import '../data/task_list.dart';
import '../data/task_marks.dart';
import '../foundation/change_notifier.dart';
import '../foundation/format.dart';
import '../foundation/helpers.dart';
import '../framework/framework.dart';
import '../semantics/semantics.dart';
import '../style/style.dart';
import 'progress_bar.dart';
import 'spinner.dart';
import 'steps.dart';

// Examples can assume:
// late ProgressTracker tracker;
// late Stream<List<int>> body;
// late int size;
// Future<void> build() async {}

/// What a [ProgressTask] counts, which says how its amounts and its rate
/// are written.
enum ProgressUnit {
  /// Things: `12/40`, `3.5/s`, `120/s`, `1.2k/s`.
  count,

  /// Bytes, in decimal units: `512 B`, `1.2 MB`, `1.2 MB/s`, `620 kB/s`.
  bytes,
}

/// How a [ProgressList] draws the bar of a task.
enum ProgressBarShape {
  /// A block a cell high, filled in eighths of a cell, as a [ProgressBar]:
  /// `█████▌    `.
  blocks,

  /// A heavy line drawn as a `LineGauge` draws it: as far as the task is
  /// done in its status' color, to the nearest half cell, the rest of the
  /// line in the theme's border color, `━━━━━╸━━━━`; ASCII where the
  /// terminal draws box drawing two columns wide.
  line,
}

/// A column of a [ProgressList], in the order the list is given them.
enum ProgressColumn {
  /// The mark of the task's [TaskStatus], as a [TaskList] shows it: a
  /// spinner while it runs, `✓`, `✗`, `↓`, `◦`.
  mark,

  /// The task's label, cut off with an ellipsis where the row is short.
  label,

  /// A bar as a [ProgressBar] draws it: filled as far as the task is
  /// done, sweeping while it runs without a total.
  bar,

  /// How much is done in whole percent, `62%`; blank without a total.
  percent,

  /// How much is done of how much: `12/40`, `1.2/3.4 MB`; without a total,
  /// how much is done, blank while that is nothing.
  count,

  /// How fast it goes while it runs ([ProgressTask.rate]): `1.2 MB/s`;
  /// blank while nothing is done.
  rate,

  /// The time left while it runs ([ProgressTask.eta]): `ETA 00:04`,
  /// `ETA --:--` before a rate is known, blank without a total; once it is
  /// done or failed, the time it took (`3.1 s`), unless the list shows
  /// [elapsed] too.
  eta,

  /// The time it has run ([ProgressTask.elapsed]): `00:12` while it runs,
  /// `3.1 s` once it is done or failed.
  elapsed,
}

/// Tasks going on at once, added and removed as they come, each counting
/// how far it has got: what a [ProgressList] shows, and what a program
/// that is not an app reads to write a line per task.
///
/// Its listeners are told when a task is added or removed, set going,
/// done, failed or skipped, and when its label or its total changes; not
/// at each [ProgressTask.advance] or [ProgressTask.update], which may come
/// a million times a second: a list reads those at the steps of its
/// spinner. [onTaskFinished] has each task as it is done, failed or
/// skipped.
///
/// The times — how long a task has run, its rate and the time it has
/// left — are read on [clock], for the tracker's whole life: the one it
/// is constructed with, else a stopwatch of its own started with it, the
/// wall clock. Nothing replaces it, a [ProgressList] showing it neither.
/// So that a test's fake clock moves them, an app hands its tracker the
/// app's clock, as the State that keeps it does from its `initState`:
/// `ProgressTracker(clock: AppBinding.of(context).twkApp.clock)`.
///
/// Two downloads at once, a task each:
///
/// ```dart
/// Future<void> fetch(ProgressTracker tracker) => Future.wait([
///   tracker.run(
///     'Downloading assets.zip',
///     (task) => body.forEach((chunk) => task.advance(chunk.length)),
///     total: size,
///     unit: ProgressUnit.bytes,
///   ),
///   tracker.run('Building binary', (_) => build()),
/// ]);
/// ```
final class ProgressTracker extends ChangeNotifier {
  /// A tracker without tasks, whose tasks' [ProgressTask.rate] is over
  /// [rateWindow], reading the time on [clock]; without one, on a
  /// stopwatch of its own, started now.
  ProgressTracker({
    this.rateWindow = const Duration(seconds: 5),
    Stopwatch? clock,
  }) : assert(rateWindow > Duration.zero, 'a window of no time'),
       clock = clock ?? (Stopwatch()..start());

  /// How far back a task's [ProgressTask.rate] looks.
  final Duration rateWindow;

  /// What the times of its tasks are read on: the clock it was
  /// constructed with, or its own stopwatch.
  final Stopwatch clock;

  final _tasks = <ProgressTask>[];

  final _finished = StreamController<ProgressTask>.broadcast(sync: true);

  /// Its tasks, in the order they were added.
  List<ProgressTask> get tasks => UnmodifiableListView(_tasks);

  /// Each task as it is done, failed or skipped, at once, while it is the
  /// tracker's: what a program writes a line for ([ProgressTask.summary])
  /// where it cannot show the list.
  Stream<ProgressTask> get onTaskFinished => _finished.stream;

  /// Whether no task is pending or running; true without tasks.
  bool get finished => !_tasks.any(
    (t) => t.status == TaskStatus.pending || t.status == TaskStatus.running,
  );

  /// Adds a task named [label], pending, after the others: of [total]
  /// [unit]s, or of an amount not known while [total] is null.
  ProgressTask add(
    String label, {
    num? total,
    ProgressUnit unit = ProgressUnit.count,
  }) {
    final task = ProgressTask._(this, label, total, unit);
    _tasks.add(task);
    notifyListeners();
    return task;
  }

  /// Adds a task named [label] as [add] does, sets it going and runs
  /// [body] with it: the task is done when the body returns, unless the
  /// body finished it itself, and failed with the error when it throws,
  /// which is thrown again. Completes with what the body returns.
  Future<T> run<T>(
    String label,
    FutureOr<T> Function(ProgressTask task) body, {
    num? total,
    ProgressUnit unit = ProgressUnit.count,
  }) async {
    final task = add(label, total: total, unit: unit)..start();
    final T result;
    try {
      result = await body(task);
    } on Object catch (error) {
      task.fail(error);
      rethrow;
    }
    task.done();
    return result;
  }

  /// Takes [task] out of the tracker; a task not in it is ignored. What it
  /// is told after is told to no one.
  void remove(ProgressTask task) {
    if (task._tracker == this && _tasks.remove(task)) {
      task._tracker = null;
      notifyListeners();
    }
  }

  Duration get _now => clock.elapsed;

  void _changed(ProgressTask task) {
    if (task._tracker == this) {
      notifyListeners();
    }
  }

  void _settled(ProgressTask task) {
    if (task._tracker == this) {
      notifyListeners();
      _finished.add(task);
    }
  }

  /// Closes [onTaskFinished] too.
  @override
  void dispose() {
    unawaited(_finished.close());
    super.dispose();
  }
}

/// How much a task had done at a time: what its rate is measured from.
final class _Sample {
  _Sample(this.at, this.completed);

  Duration at;
  num completed;
}

/// A task of a [ProgressTracker] ([ProgressTracker.add]): its [label], how
/// much of its [total] it has [completed], and where it stands ([status]).
///
/// It is pending until [start], [advance] or [update] sets it going; then
/// [done], [fail] or [skip] finish it, after which [start], [advance] and
/// [update] are ignored, and so are [done], [fail] and [skip] again.
final class ProgressTask {
  ProgressTask._(this._tracker, this._label, this._total, this.unit);

  // null once removed
  ProgressTracker? _tracker;

  /// What it counts.
  final ProgressUnit unit;

  String _label;

  /// What it is called, after its mark; set, the tracker's listeners are
  /// told.
  String get label => _label;
  set label(String l) {
    if (l != _label) {
      _label = l;
      _tracker?._changed(this);
    }
  }

  num? _total;

  /// How much there is to do; null while not known, which an
  /// indeterminate bar shows. Set, the tracker's listeners are told.
  num? get total => _total;
  set total(num? t) {
    if (t != _total) {
      _total = t;
      _tracker?._changed(this);
    }
  }

  num _completed = 0;

  /// How much is done.
  num get completed => _completed;

  TaskStatus _status = TaskStatus.pending;

  /// Where it stands.
  TaskStatus get status => _status;

  Object? _error;

  /// What it failed with ([fail]); null while it has not, or failed with
  /// none.
  Object? get error => _error;

  // when it was set going and when it finished, on the tracker's clock
  Duration? _started;
  Duration? _ended;

  // how much it had done when, the oldest first, over the tracker's rate
  // window and one before it
  final _samples = ListQueue<_Sample>();

  bool get _over =>
      _status != TaskStatus.pending && _status != TaskStatus.running;

  Duration get _now => _tracker?._now ?? _ended ?? _started ?? Duration.zero;

  /// Sets it going, from pending; otherwise does nothing.
  void start() {
    if (_status != TaskStatus.pending) {
      return;
    }
    final now = _now;
    _status = TaskStatus.running;
    _started = now;
    _samples
      ..clear()
      ..add(_Sample(now, _completed));
    _tracker?._changed(this);
  }

  /// Counts [by] more done, setting it going while it is pending.
  void advance([num by = 1]) => update(_completed + by);

  /// Counts [completed] done, setting it going while it is pending.
  void update(num completed) {
    if (_over) {
      return;
    }
    if (_status == TaskStatus.pending) {
      start();
    }
    _completed = completed;
    final now = _now;
    final samples = _samples;
    // a sample a twentieth of the window at most: the last one moves on
    // while the one before it is that recent
    final bucket = (_tracker?.rateWindow ?? Duration.zero) ~/ 20;
    if (samples.length >= 2 &&
        now - samples.elementAt(samples.length - 2).at < bucket) {
      samples.last
        ..at = now
        ..completed = completed;
    } else {
      samples.add(_Sample(now, completed));
    }
  }

  /// Finishes it done, renamed [label] where that is given, all of its
  /// [total] counted done where that is known.
  void done([String? label]) {
    if (_over) {
      return;
    }
    if (label != null) {
      _label = label;
    }
    if (_total case final total? when _completed < total) {
      _completed = total;
    }
    _finish(TaskStatus.done);
  }

  /// Finishes it failed, with [error] where that is given.
  void fail([Object? error]) {
    if (_over) {
      return;
    }
    _error = error;
    _finish(TaskStatus.failed);
  }

  /// Finishes it skipped: not done, and not to be.
  void skip() {
    if (_over) {
      return;
    }
    _finish(TaskStatus.skipped);
  }

  void _finish(TaskStatus status) {
    final now = _now;
    _started ??= now;
    _ended = now;
    _status = status;
    _samples.clear();
    _tracker?._settled(this);
  }

  /// How much of [total] is done, from 0 to 1; null without a total, 1 for
  /// a total of 0 or less.
  double? get fraction {
    final total = _total;
    if (total == null) {
      return null;
    }
    if (total <= 0) {
      return 1;
    }
    return unitRatio(_completed / total);
  }

  /// How much it does a second while it runs, over the tracker's
  /// [ProgressTracker.rateWindow] up to now, by the tracker's clock: from
  /// the time it was set going until it has run that long; null before
  /// any time has passed, and once it is not running.
  double? get rate {
    if (_status != TaskStatus.running || _samples.isEmpty) {
      return null;
    }
    final now = _now;
    final samples = _samples;
    final from = now - (_tracker?.rateWindow ?? Duration.zero);
    while (samples.length > 1 && samples.elementAt(1).at <= from) {
      samples.removeFirst();
    }
    final first = samples.first;
    final span = (now - first.at).inMicroseconds;
    if (span <= 0) {
      return null;
    }
    return (_completed - first.completed) * 1e6 / span;
  }

  /// The time it has left at its [rate] while it runs: zero once all of
  /// [total] is done; null without a total, without a rate, at a rate of
  /// nothing, and once it is not running.
  Duration? get eta {
    final total = _total;
    if (_status != TaskStatus.running || total == null) {
      return null;
    }
    final left = total - _completed;
    if (left <= 0) {
      return Duration.zero;
    }
    final rate = this.rate;
    if (rate == null || rate <= 0) {
      return null;
    }
    final seconds = left / rate;
    // a thousand hours at most
    return Duration(
      microseconds: (seconds < 3.6e6 ? seconds : 3.6e6) * 1e6 ~/ 1,
    );
  }

  /// How long it has run: from the time it was set going to now, or to the
  /// time it finished; zero while it is pending, and for a task skipped
  /// before it ran.
  Duration get elapsed {
    final started = _started;
    if (started == null) {
      return Duration.zero;
    }
    return (_ended ?? _now) - started;
  }

  /// A line of plain text for it: its mark, its label, and, joined by
  /// `•`, how much it did where that says something, the time it took once
  /// it is done or failed, and the error it failed with:
  /// `✓ Downloading assets.zip • 3.4/3.4 MB • 2.1 s`.
  String get summary {
    final parts = ['${taskMark(_status, SpinnerFrames.dots, 0)} $_label'];
    if (_completed > 0 && (_total != null || unit == ProgressUnit.bytes)) {
      parts.add(_count(this));
    }
    if (_status == TaskStatus.done || _status == TaskStatus.failed) {
      parts.add(formatTook(elapsed));
    }
    if (_error case final error?) {
      parts.add('$error');
    }
    return parts.join(' • ');
  }

  @override
  String toString() => 'ProgressTask($_label, ${_status.name})';
}

/// The tasks of a [tracker], a row each, with the [columns] it is given:
/// the mark of each task's [TaskStatus] as a [TaskList] shows it, its
/// label, a bar as a [ProgressBar] draws it — sweeping while the task
/// runs without a total — and how far it has got, how fast it goes and
/// the time it has left:
///
/// ```text
/// ⠹ Downloading assets.zip █████████████▌       62%   1.2 MB/s • ETA 00:04
/// ✓ Building binary        ████████████████████ 100%            3.1 s
/// ```
///
/// The columns line up across the rows, each as wide as the widest of
/// its cells, those of the amounts right-aligned; a column empty in every
/// row takes no room. The label column is as wide as the longest label,
/// the bar takes the rest. Where the row is short, the labels are cut off
/// with an ellipsis before the bar is narrower than 10 cells, then, at 8
/// cells of label, the bar narrows and goes, then the columns after it
/// from the last.
///
/// With [hideFinished] the tasks done or skipped are not shown, the
/// failed ones still are. With [maxVisible], at most that many rows of
/// tasks are shown — the running ones first, then the pending, the
/// failed and the rest — in their order, and a row `+3 more` for those
/// that are not.
///
/// The list is as tall as its rows and as wide as it may be; a repaint
/// boundary. It is built again when the tracker tells its listeners, and
/// while a task it shows runs, at each step of the [spinner] on the app's
/// clock, which repaints the rows with what the tasks have done since:
/// a million [ProgressTask.advance] calls a second cost a frame a step.
/// A bar sweeping moves at the [ProgressBar.step]s, as the others do.
/// Outside an app the spinner shows its first frame and nothing moves.
///
/// The times in its rows — elapsed, rate, time left — are the tasks',
/// read on the tracker's [ProgressTracker.clock], which the list leaves
/// as it is: where a test's fake clock is to move them, the tracker is
/// made with the app's clock (`AppBinding.of(context).twkApp.clock`).
///
/// A screen reader reads it as a list of progress bars, each with its
/// label and how much is done (`progressbar Downloading assets.zip: 62%`),
/// a task not running with its status as the hint.
///
/// A list of what a tracker runs:
///
/// ```dart
/// ProgressList(
///   tracker: tracker,
///   columns: const [
///     ProgressColumn.mark,
///     ProgressColumn.label,
///     ProgressColumn.bar,
///     ProgressColumn.percent,
///     ProgressColumn.eta,
///   ],
///   hideFinished: true,
/// )
/// ```
///
/// See also:
///
///  * [TaskList], for tasks without amounts, given as values.
///  * [ProgressBar], one bar on its own.
final class ProgressList extends StatefulWidget {
  /// Shows the tasks of [tracker] in [columns].
  const ProgressList({
    required this.tracker,
    super.key,
    this.columns = defaultColumns,
    this.hideFinished = false,
    this.maxVisible,
    this.spinner = SpinnerFrames.dots,
    this.barShape = ProgressBarShape.blocks,
    this.maxBarWidth,
  }) : assert(maxVisible == null || maxVisible >= 0, 'fewer than no rows'),
       assert(maxBarWidth == null || maxBarWidth > 0, 'a bar of no cells');

  /// The columns a list shows by default: the mark, the label, the bar,
  /// the percent, the rate and the time left.
  static const List<ProgressColumn> defaultColumns = [
    ProgressColumn.mark,
    ProgressColumn.label,
    ProgressColumn.bar,
    ProgressColumn.percent,
    ProgressColumn.rate,
    ProgressColumn.eta,
  ];

  /// What it shows the tasks of.
  final ProgressTracker tracker;

  /// What a row shows, in order; a column given twice is shown once.
  final List<ProgressColumn> columns;

  /// Whether the tasks done or skipped are left out.
  final bool hideFinished;

  /// How many rows of tasks it shows at most, a row more saying how many
  /// it does not; null for all of them.
  final int? maxVisible;

  /// What a running task's mark shows in turn, and how often the rows of
  /// running tasks are painted again.
  final SpinnerFrames spinner;

  /// How the bar column is drawn: blocks, or a thinner line.
  final ProgressBarShape barShape;

  /// How wide the bar column is at most, the room past it left blank at
  /// the right of the rows; null for all the room the other columns leave.
  final int? maxBarWidth;

  @override
  State<ProgressList> createState() => _ProgressListState();
}

final class _ProgressListState extends State<ProgressList> {
  Steps? _steps;

  @override
  void initState() {
    super.initState();
    widget.tracker.addListener(_changed);
  }

  @override
  void didUpdateWidget(ProgressList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tracker != widget.tracker) {
      oldWidget.tracker.removeListener(_changed);
      widget.tracker.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _steps?.stop();
    widget.tracker.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  /// The tasks shown, and how many are not.
  (List<ProgressTask>, int) _rows() {
    final hide = widget.hideFinished;
    final tasks = [
      for (final t in widget.tracker.tasks)
        if (!hide ||
            (t.status != TaskStatus.done && t.status != TaskStatus.skipped))
          t,
    ];
    final max = widget.maxVisible;
    if (max == null || tasks.length <= max) {
      return (tasks, 0);
    }
    int rank(TaskStatus s) => switch (s) {
      TaskStatus.running => 0,
      TaskStatus.pending => 1,
      TaskStatus.failed => 2,
      TaskStatus.done || TaskStatus.skipped => 3,
    };
    final order = [for (var i = 0; i < tasks.length; i++) i]
      ..sort((a, b) {
        final r = rank(tasks[a].status) - rank(tasks[b].status);
        return r != 0 ? r : a - b;
      });
    final kept = order.take(max).toList()..sort();
    return ([for (final i in kept) tasks[i]], tasks.length - max);
  }

  @override
  Widget build(BuildContext context) {
    final binding = AppBinding.maybeOf(context);
    final (rows, more) = _rows();
    final running = rows.any((t) => t.status == TaskStatus.running);
    final interval = widget.spinner.interval;
    var steps = _steps;
    if (steps == null || steps.binding != binding) {
      steps?.stop();
      steps = _steps = Steps(interval, _changed, binding: binding);
    }
    steps.interval = interval;
    if (running) {
      steps.start();
    } else {
      steps.stop();
    }
    final theme = Theme.of(context);
    final base = opaque(theme.background.merge(theme.text));
    return Semantics(
      nodes: [
        SemanticsNode(
          role: SemanticsRole.list,
          children: [
            for (final task in rows)
              SemanticsNode(
                role: SemanticsRole.progressBar,
                label: task.label,
                value: switch (task.fraction) {
                  final f? => formatPercent(f),
                  null => null,
                },
                hint: task.status == TaskStatus.running
                    ? null
                    : task.status.name,
              ),
            if (more > 0) SemanticsNode(label: '+$more more'),
          ],
        ),
      ],
      child: _List(
        rows: rows,
        more: more,
        columns: widget.columns,
        frames: widget.spinner,
        barShape: widget.barShape,
        maxBarWidth: widget.maxBarWidth,
        styles: _Styles(
          base: base,
          muted: base.merge(theme.muted),
          marks: [
            for (final status in TaskStatus.values)
              base.merge(taskMarkStyle(theme, status)),
          ],
          border: base.merge(theme.border),
        ),
        binding: binding,
      ),
    );
  }
}

/// The styles a [ProgressList] paints in, each over the theme's
/// background and text.
final class _Styles {
  const _Styles({
    required this.base,
    required this.muted,
    required this.marks,
    required this.border,
  });

  final Style base;
  final Style muted;

  /// The style of the mark and the bar of a task at each [TaskStatus], by
  /// its index: a [TaskList]'s ([taskMarkStyle]).
  final List<Style> marks;

  /// The rest of a [ProgressBarShape.line] bar, as a `LineGauge`'s.
  final Style border;

  /// The style of the mark and the bar of a task at [status].
  Style of(TaskStatus status) => marks[status.index];

  @override
  bool operator ==(Object other) =>
      other is _Styles &&
      other.base == base &&
      other.muted == muted &&
      sameList(other.marks, marks) &&
      other.border == border;

  @override
  int get hashCode => Object.hash(base, muted, Object.hashAll(marks), border);
}

/// What paints the rows of a [ProgressList].
final class _List extends LeafRenderObjectWidget {
  const _List({
    required this.rows,
    required this.more,
    required this.columns,
    required this.frames,
    required this.barShape,
    required this.maxBarWidth,
    required this.styles,
    required this.binding,
  });

  final List<ProgressTask> rows;
  final int more;
  final List<ProgressColumn> columns;
  final SpinnerFrames frames;
  final ProgressBarShape barShape;
  final int? maxBarWidth;
  final _Styles styles;
  final AppBinding? binding;

  @override
  _RenderProgressList createRenderObject(BuildContext context) =>
      _RenderProgressList(
        rows: rows,
        more: more,
        columns: columns,
        frames: frames,
        barShape: barShape,
        maxBarWidth: maxBarWidth,
        styles: styles,
        binding: binding,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderProgressList renderObject,
  ) {
    renderObject
      ..update(rows, more)
      ..columns = columns
      ..frames = frames
      ..barShape = barShape
      ..maxBarWidth = maxBarWidth
      ..styles = styles;
  }
}

/// The columns whose cells are text, right-aligned.
const Set<ProgressColumn> _textColumns = {
  ProgressColumn.percent,
  ProgressColumn.count,
  ProgressColumn.rate,
  ProgressColumn.eta,
  ProgressColumn.elapsed,
};

/// What a [ProgressList] lays out and paints: a row a task it is given,
/// and one saying how many more there are; the cells of each column made
/// and measured at each paint, from what the tasks say then.
final class _RenderProgressList extends RenderObject {
  _RenderProgressList({
    required this._rows,
    required this._more,
    required this._columns,
    required this._frames,
    required this._barShape,
    required this._maxBarWidth,
    required this._styles,
    required this.binding,
  });

  final AppBinding? binding;

  // the sweep of the bars of running tasks without a total
  late final _sweep = Steps(ProgressBar.step, markNeedsPaint, binding: binding);

  List<ProgressTask> _rows;
  int _more;

  /// Shows [rows] and a row for [more]: laid out again when the number of
  /// rows changes, painted again otherwise, as what the tasks say may
  /// have changed.
  void update(List<ProgressTask> rows, int more) {
    if (rows.length != _rows.length || (more > 0) != (_more > 0)) {
      markNeedsLayout();
    }
    _rows = rows;
    _more = more;
    markNeedsPaint();
  }

  List<ProgressColumn> _columns;
  List<ProgressColumn> get columns => _columns;
  set columns(List<ProgressColumn> c) {
    if (!sameList(c, _columns)) {
      _columns = c;
      markNeedsPaint();
    }
  }

  SpinnerFrames _frames;
  SpinnerFrames get frames => _frames;
  set frames(SpinnerFrames f) {
    if (f != _frames) {
      _frames = f;
      markNeedsPaint();
    }
  }

  ProgressBarShape _barShape;
  ProgressBarShape get barShape => _barShape;
  set barShape(ProgressBarShape b) {
    if (b != _barShape) {
      _barShape = b;
      markNeedsPaint();
    }
  }

  int? _maxBarWidth;
  int? get maxBarWidth => _maxBarWidth;
  set maxBarWidth(int? w) {
    if (w != _maxBarWidth) {
      _maxBarWidth = w;
      markNeedsPaint();
    }
  }

  _Styles _styles;
  _Styles get styles => _styles;
  set styles(_Styles s) {
    if (s != _styles) {
      _styles = s;
      markNeedsPaint();
    }
  }

  final _glyphs = ChartGlyphs();

  @override
  bool get isRepaintBoundary => true;

  @override
  void detach() {
    _sweep.stop();
    super.detach();
  }

  static final _detached = TextSegmenter();

  TextSegmenter get _segmenter => owner?.segmenter ?? _detached;

  int get _height => _rows.length + (_more > 0 ? 1 : 0);

  int _longestLabel(TextSegmenter segmenter) {
    var most = 0;
    for (final task in _rows) {
      final w = segmenter.width(task.label);
      most = w > most ? w : most;
    }
    return most;
  }

  @override
  int computeMinIntrinsicWidth(int height) => 0;

  @override
  int computeMaxIntrinsicWidth(int height) {
    final segmenter = _segmenter;
    final shown = _columns.toSet();
    var w = 0;
    if (shown.contains(ProgressColumn.mark)) {
      w += taskMarkWidth(segmenter, _frames) + 1;
    }
    if (shown.contains(ProgressColumn.label)) {
      w += _longestLabel(segmenter) + 1;
    }
    if (shown.contains(ProgressColumn.bar)) {
      w += 20 + 1;
    }
    // room for the amounts as they are written at most
    for (final c in shown) {
      if (_textColumns.contains(c)) {
        w += 12;
      }
    }
    return w;
  }

  @override
  int computeMinIntrinsicHeight(int width) => _height;

  @override
  int computeMaxIntrinsicHeight(int width) => _height;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW < BoxConstraints.unbounded
        ? c.maxW
        : c.constrainW(computeMaxIntrinsicWidth(_height));
    height = c.constrainH(_height);
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final segmenter = canvas.segmenter;
    final styles = canvas.styles;
    final s = _styles;
    final basePen = s.base.penIn(styles);
    final mutedPen = s.muted.penIn(styles);
    canvas.fill(0, 0, width, height, basePen);
    final rows = _rows;
    final order = <ProgressColumn>[];
    for (final c in _columns) {
      if (!order.contains(c)) {
        order.add(c);
      }
    }
    final hasMark = order.contains(ProgressColumn.mark);
    final hasLabel = order.contains(ProgressColumn.label);
    final hasBar = order.contains(ProgressColumn.bar);
    final showsElapsed = order.contains(ProgressColumn.elapsed);

    // the cells of the text columns and their widths; a column empty in
    // every row takes no room
    final texts = <ProgressColumn>[];
    final cells = <List<String>>[];
    final widths = <int>[];
    for (final c in order) {
      if (!_textColumns.contains(c)) {
        continue;
      }
      final column = [
        for (final task in rows) _cell(c, task, showsElapsed: showsElapsed),
      ];
      var w = 0;
      for (final cell in column) {
        final cw = segmenter.width(cell);
        w = cw > w ? cw : w;
      }
      if (w > 0) {
        texts.add(c);
        cells.add(column);
        widths.add(w);
      }
    }

    final markW = hasMark ? taskMarkWidth(segmenter, _frames) : 0;
    final longest = hasLabel ? _longestLabel(segmenter) : 0;
    // the widths of the label and the bar, the text columns that fit
    var labelW = 0;
    var barW = 0;
    var shownTexts = texts.length;
    while (true) {
      // the columns but the label and the bar, and the blanks between all
      var fixed = markW;
      var parts = hasMark ? 1 : 0;
      for (var j = 0; j < shownTexts; j++) {
        fixed += widths[j] + (j > 0 ? 3 : 0);
      }
      if (shownTexts > 0) {
        parts++;
      }
      int gaps(int more) {
        final n = parts + more;
        return n > 1 ? n - 1 : 0;
      }

      final labelParts = hasLabel ? 1 : 0;
      final rest = width - fixed;
      final short = longest < 8 ? longest : 8;
      if (hasBar) {
        final room = rest - gaps(labelParts + 1);
        if (room >= longest + 10) {
          labelW = longest;
          barW = room - longest;
          break;
        }
        if (room >= short + 10) {
          labelW = room - 10;
          barW = 10;
          break;
        }
        if (room > short) {
          labelW = short;
          barW = room - short;
          break;
        }
      }
      final room = rest - gaps(labelParts);
      if (room >= short || shownTexts == 0) {
        labelW = room < 0 ? 0 : (room < longest ? room : longest);
        barW = 0;
        break;
      }
      shownTexts--;
    }

    final cap = _maxBarWidth;
    if (cap != null && barW > cap) {
      barW = cap;
    }
    final g = _glyphs..use(segmenter);
    final line = _barShape == ProgressBarShape.line;
    final borderPen = s.border.penIn(styles);
    var sweeping = false;
    for (var y = 0; y < rows.length && y < height; y++) {
      final task = rows[y];
      final status = task.status;
      var x = 0;
      var first = true;
      void gap() {
        if (!first) {
          x++;
        }
        first = false;
      }

      if (hasMark) {
        gap();
        canvas.text(
          x,
          y,
          taskMark(status, _frames, _spinnerStep),
          s.of(status).penIn(styles),
        );
        x += markW;
      }
      if (hasLabel && labelW > 0) {
        gap();
        canvas.text(
          x,
          y,
          fitText(segmenter, task.label, labelW),
          status == TaskStatus.skipped ? mutedPen : basePen,
        );
        x += labelW;
      }
      if (barW > 0) {
        gap();
        final pen = opaque(s.of(status)).penIn(styles);
        final fraction =
            task.fraction ?? (status == TaskStatus.done ? 1.0 : null);
        final running = fraction == null && status == TaskStatus.running;
        sweeping |= running;
        final run = running ? ChartGlyphs.sweep(barW, _sweep.current) : null;
        if (line) {
          g.line(
            canvas,
            x,
            y,
            barW,
            BorderType.heavy,
            filledPen: pen,
            unfilledPen: borderPen,
            ratio: fraction ?? 0,
            run: run,
          );
        } else {
          g.blocks(canvas, x, y, barW, 1, fraction ?? 0, pen, run: run);
        }
        x += barW;
      }
      for (var j = 0; j < shownTexts; j++) {
        final cell = cells[j][y];
        if (j == 0) {
          gap();
        } else {
          if (cell.isNotEmpty && cells[j - 1][y].isNotEmpty) {
            canvas.text(x, y, ' • ', mutedPen);
          }
          x += 3;
        }
        final w = segmenter.width(cell);
        final column = texts[j];
        canvas.text(
          x + widths[j] - w,
          y,
          cell,
          column == ProgressColumn.percent || column == ProgressColumn.count
              ? basePen
              : mutedPen,
        );
        x += widths[j];
      }
    }
    if (_more > 0 && rows.length < height) {
      canvas.text(
        0,
        rows.length,
        fitText(segmenter, '+$_more more', width),
        mutedPen,
      );
    }
    if (sweeping) {
      _sweep.start();
    } else {
      _sweep.stop();
    }
  }

  /// The step of the spinner the frame is in.
  int get _spinnerStep {
    final b = binding;
    return b == null
        ? 0
        : b.frameTime.inMicroseconds ~/ _frames.interval.inMicroseconds;
  }
}

/// The text of [column]'s cell for [task]; empty for none.
String _cell(
  ProgressColumn column,
  ProgressTask task, {
  required bool showsElapsed,
}) {
  final status = task.status;
  final running = status == TaskStatus.running;
  final over = status == TaskStatus.done || status == TaskStatus.failed;
  return switch (column) {
    ProgressColumn.percent => switch (task.fraction) {
      final f? => formatPercent(f),
      null => status == TaskStatus.done ? '100%' : '',
    },
    ProgressColumn.count =>
      task.completed == 0 && task.total == null ? '' : _count(task),
    ProgressColumn.rate => switch (running && task.completed != 0
        ? task.rate
        : null) {
      final r? => _rate(r, task.unit),
      null => '',
    },
    ProgressColumn.eta =>
      running
          ? (task.total == null
                ? ''
                : 'ETA ${switch (task.eta) {
                    final e? => formatClock(e),
                    null => '--:--',
                  }}')
          : (over && !showsElapsed ? formatTook(task.elapsed) : ''),
    ProgressColumn.elapsed =>
      running
          ? formatClock(task.elapsed)
          : (over ? formatTook(task.elapsed) : ''),
    ProgressColumn.mark || ProgressColumn.label || ProgressColumn.bar => '',
  };
}

/// How much of how much [task] has done, in its unit: `12/40`,
/// `1.2/3.4 MB`, `1.2 MB`.
String _count(ProgressTask task) {
  final total = task.total;
  if (task.unit == ProgressUnit.count) {
    final done = _number(task.completed);
    return total == null ? done : '$done/${_number(total)}';
  }
  if (total == null) {
    return formatBytes(task.completed);
  }
  final (scale, suffix) = byteUnit(total);
  if (scale == 1) {
    return '${_number(task.completed)}/${_number(total)} B';
  }
  return '${(task.completed / scale).toStringAsFixed(1)}/'
      '${(total / scale).toStringAsFixed(1)} $suffix';
}

/// [n] whole where it is, else to the tenth.
String _number(num n) => n == n.roundToDouble() && n.abs() < 1e15
    ? '${n.round()}'
    : n.toStringAsFixed(1);

/// [rate] a second in [unit], as [formatBytes] writes an amount: `1.2 MB/s`,
/// `3.5/s`, `120/s`, `1.2k/s`.
String _rate(double rate, ProgressUnit unit) {
  if (unit == ProgressUnit.bytes) {
    return '${formatBytes(rate)}/s';
  }
  const units = ['', 'k', 'M', 'G'];
  var scaled = rate;
  var i = 0;
  while (i < units.length - 1 && scaled.abs() >= 1000) {
    scaled /= 1000;
    i++;
  }
  return '${formatFigures(scaled)}${units[i]}/s';
}
