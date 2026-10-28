/// Tasks and how far they have got: a [TaskList] of [TaskItem]s, each with
/// its [TaskStatus].
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        BoxConstraints,
        HitTestBehavior,
        PaintContext,
        PipelineOwner,
        RenderObject,
        RenderObjectWithChildMixin,
        TextOverflow,
        TextSegmenter,
        TextWrap;

import '../animation/spinner.dart';
import '../animation/steps.dart';
import '../binding/app_binding.dart';
import '../foundation/format.dart';
import '../framework/framework.dart';
import '../layout/basic.dart';
import '../layout/flex.dart';
import '../layout/one_child.dart';
import '../style/style.dart';
import '../text/widgets.dart';
import 'chart_glyphs.dart';
import 'task_marks.dart';

/// Where a [TaskItem] stands, shown by the mark before its label.
enum TaskStatus {
  /// Not started: `◦`, in [ThemeData.muted].
  pending,

  /// Going on: a spinner, in [ThemeData.primary].
  running,

  /// Done: `✓`, in [ThemeData.success].
  done,

  /// Failed: `✗`, in [ThemeData.error].
  failed,

  /// Not done, and not to be: `↓`, the label too in [ThemeData.muted].
  skipped,
}

/// A task of a [TaskList]: its [label], its [status] and the tasks it is
/// made of ([children]).
@immutable
final class TaskItem {
  /// A task named [label], [status] pending by default, made of
  /// [children].
  const TaskItem(
    this.label, {
    this.status = TaskStatus.pending,
    this.id,
    this.elapsed,
    this.children = const [],
  });

  /// The task's name, after its mark.
  final String label;

  /// Where the task stands: the mark before [label].
  final TaskStatus status;

  /// What tells the task from its siblings while the list changes, which
  /// keeps its row and the time it has run; null for its [label]. Siblings
  /// have different ones.
  final Object? id;

  /// How long the task has run, or ran once it is done or failed, as the
  /// app knows it: a [TaskList] with [TaskList.showElapsed] shows it as it
  /// shows a time it measured, in place of that, and moves it on only when
  /// it is given another — for tasks that ran before the list saw them, or
  /// times the app takes from elsewhere (a build's report, a clock of its
  /// own). Null, the list measures it. A task pending or skipped shows none.
  final Duration? elapsed;

  /// The tasks it is made of, shown below it, indented.
  final List<TaskItem> children;
}

/// Tasks and how far they have got, a row each: build steps, an
/// installer's stages, what an agent does. A row shows the mark of the
/// task's [TaskStatus], its label, cut off with an ellipsis, and with
/// [showElapsed], in [ThemeData.muted] after it, the time it has run on the
/// app's clock, from the frame that showed it running, as a
/// `ProgressList` writes it: a clock in whole seconds while it runs
/// (`00:12`), then, once it is done or failed, to the tenth of a second
/// under a minute (`3.1 s`) and a clock past it (`01:05`). A task
/// pending or skipped shows none, and a task the list shows done before
/// it ran neither, unless it is given its time ([TaskItem.elapsed]). The
/// [TaskItem.children] of a task are in the rows below it, indented two
/// cells a level.
///
/// The list is as tall as its rows and as wide as it may be. Each row is
/// a repaint boundary laid out on its own: a task that changes, or whose
/// spinner or time moves on, repaints its row and nothing else, and a row
/// stays with its task ([TaskItem.id]) while tasks come and go around it.
/// Outside an app the spinner shows its first frame and no time is shown.
///
/// The styles, each merged over those before it: the theme's background
/// and text and [style] for a row.
///
/// A build of three steps, the second made of two:
///
/// ```dart
/// const TaskList(
///   tasks: [
///     TaskItem('Fetch', status: TaskStatus.done),
///     TaskItem(
///       'Compile',
///       status: TaskStatus.running,
///       children: [
///         TaskItem('core', status: TaskStatus.done),
///         TaskItem('widgets', status: TaskStatus.running),
///       ],
///     ),
///     TaskItem('Test'),
///   ],
/// )
/// ```
///
/// See also:
///
///  * [Spinner], the mark of a running task on its own.
///  * `TreeView`, for a tree the user moves through and folds.
final class TaskList extends StatelessWidget {
  /// Shows [tasks], a row each.
  const TaskList({
    required this.tasks,
    super.key,
    this.spinner = SpinnerFrames.dots,
    this.showElapsed = true,
    this.style,
  });

  /// The tasks, in order, each followed by its [TaskItem.children].
  final List<TaskItem> tasks;

  /// What a running task's mark shows in turn.
  final SpinnerFrames spinner;

  /// Whether a row shows the time its task has run.
  final bool showElapsed;

  /// A row's style, over the theme's background and text; null for those
  /// alone.
  final Style? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = opaque(
      theme.background.merge(theme.text).merge(style ?? const Style()),
    );
    final binding = AppBinding.maybeOf(context);
    final rows = <Widget>[];
    void add(List<TaskItem> items, int depth, _TaskKey? parent) {
      for (final item in items) {
        final key = _TaskKey(parent, item.id ?? item.label);
        final status = item.status;
        rows.add(
          SizedBox(
            key: ValueKey(key),
            height: 1,
            child: _TaskRow(
              level: depth,
              status: status,
              frames: spinner,
              showElapsed: showElapsed,
              elapsed: item.elapsed,
              style: base,
              markStyle: base.merge(taskMarkStyle(theme, status)),
              elapsedStyle: base.merge(theme.muted),
              binding: binding,
              child: Text(
                item.label,
                style: status == TaskStatus.skipped
                    ? base.merge(theme.muted)
                    : base,
                wrap: TextWrap.none,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        );
        add(item.children, depth + 1, key);
      }
    }

    add(tasks, 0, null);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// What keeps a row with its task: the task's id under the key of its
/// parent.
@immutable
final class _TaskKey {
  const _TaskKey(this.parent, this.id);

  final _TaskKey? parent;
  final Object id;

  @override
  bool operator ==(Object other) =>
      other is _TaskKey && other.id == id && other.parent == parent;

  @override
  int get hashCode => Object.hash(parent, id);
}

/// A row of a [TaskList]: the mark of [status], then the label in [child].
final class _TaskRow extends SingleChildRenderObjectWidget {
  const _TaskRow({
    required this.level,
    required this.status,
    required this.frames,
    required this.showElapsed,
    required this.elapsed,
    required this.style,
    required this.markStyle,
    required this.elapsedStyle,
    required this.binding,
    super.child,
  });

  final int level;
  final TaskStatus status;
  final SpinnerFrames frames;
  final bool showElapsed;
  final Duration? elapsed;
  final Style style;
  final Style markStyle;
  final Style elapsedStyle;
  final AppBinding? binding;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  _RenderTaskRow createRenderObject(BuildContext context) => _RenderTaskRow(
    level: level,
    status: status,
    frames: frames,
    showElapsed: showElapsed,
    given: elapsed,
    style: style,
    markStyle: markStyle,
    elapsedStyle: elapsedStyle,
    binding: binding,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderTaskRow renderObject) {
    renderObject
      ..level = level
      ..status = status
      ..frames = frames
      ..showElapsed = showElapsed
      ..elapsed = elapsed
      ..style = style
      ..markStyle = markStyle
      ..elapsedStyle = elapsedStyle;
  }
}

/// [time] as a task's time, as a `ProgressList` writes it: a clock while
/// it is [running] (`00:12`), else the time it took (`3.1 s`, `01:05`).
String _elapsed(Duration time, {required bool running}) =>
    running ? formatClock(time) : formatTook(time);

/// What a row of a [TaskList] lays out and paints: [level] levels of two
/// cells, the mark of [status] as wide as the widest mark and spinner frame
/// and a blank, its child, then a blank and the time the task has run.
/// It times the task on [binding]'s clock from the frame it is made or set
/// running in to the frame it is set done or failed in, and shows [elapsed]
/// in place of that time where it is given; while it runs and times it, it
/// repaints at each frame of the spinner and shows the time anew at each
/// second, on frame callbacks for those times, laid out again when the
/// time takes other columns.
final class _RenderTaskRow extends RenderObject
    with RenderObjectWithChildMixin {
  _RenderTaskRow({
    required this._level,
    required this._status,
    required this._frames,
    required this._showElapsed,
    required this._given,
    required this._style,
    required this._markStyle,
    required this._elapsedStyle,
    required this.binding,
  }) {
    if (_status == TaskStatus.running) {
      _started = binding?.frameTime;
    }
    _shown = _elapsedNow();
  }

  /// The app whose clock it times the task and steps the spinner by.
  final AppBinding? binding;

  late final _steps = Steps(_frames.interval, markNeedsPaint, binding: binding);

  // when the task was set running and when it stopped, on the app's clock
  Duration? _started;
  Duration? _ended;

  // the time shown, and the frame callback that moves it on
  var _shown = '';
  int? _tick;

  late final FrameCallback _tickCallback = _onTick;

  int _level;
  int get level => _level;
  set level(int l) {
    if (l != _level) {
      _level = l;
      markNeedsLayout();
    }
  }

  TaskStatus _status;
  TaskStatus get status => _status;
  set status(TaskStatus s) {
    if (s == _status) {
      return;
    }
    final now = binding?.frameTime;
    if (s == TaskStatus.running) {
      _started = now;
      _ended = null;
    } else if (_status == TaskStatus.running) {
      _ended = now;
    }
    if (s == TaskStatus.pending || s == TaskStatus.skipped) {
      _started = null;
      _ended = null;
    }
    if (s != TaskStatus.running) {
      _steps.stop();
      _stopTicking();
    }
    _status = s;
    _show();
    _startTicking();
    markNeedsPaint();
  }

  SpinnerFrames _frames;
  SpinnerFrames get frames => _frames;
  set frames(SpinnerFrames f) {
    if (f != _frames) {
      _frames = f;
      _steps.interval = f.interval;
      markNeedsLayout();
    }
  }

  bool _showElapsed;
  bool get showElapsed => _showElapsed;
  set showElapsed(bool s) {
    if (s != _showElapsed) {
      _showElapsed = s;
      if (s) {
        _startTicking();
      } else {
        _stopTicking();
      }
      _show();
    }
  }

  Duration? _given;

  /// The time the task has run as it is given, shown in place of the time
  /// it measures; null for that.
  Duration? get elapsed => _given;
  set elapsed(Duration? e) {
    if (e == _given) {
      return;
    }
    _given = e;
    if (e != null) {
      _stopTicking();
    }
    _show();
    _startTicking();
    markNeedsPaint();
  }

  Style _style;
  Style get style => _style;
  set style(Style s) {
    if (s != _style) {
      _style = s;
      markNeedsPaint();
    }
  }

  Style _markStyle;
  Style get markStyle => _markStyle;
  set markStyle(Style s) {
    if (s != _markStyle) {
      _markStyle = s;
      markNeedsPaint();
    }
  }

  Style _elapsedStyle;
  Style get elapsedStyle => _elapsedStyle;
  set elapsedStyle(Style s) {
    if (s != _elapsedStyle) {
      _elapsedStyle = s;
      markNeedsPaint();
    }
  }

  /// The time to show at the frame running.
  String _elapsedNow() {
    if (_given case final given?) {
      return _showElapsed &&
              _status != TaskStatus.pending &&
              _status != TaskStatus.skipped
          ? _elapsed(given, running: _status == TaskStatus.running)
          : '';
    }
    final started = _started;
    final now = _ended ?? binding?.frameTime;
    if (!_showElapsed || started == null || now == null) {
      return '';
    }
    return _elapsed(now - started, running: _ended == null);
  }

  /// Shows the time at the frame running: lays the row out again when
  /// it takes other columns, repaints it otherwise.
  void _show() {
    final shown = _elapsedNow();
    if (shown == _shown) {
      return;
    }
    final segmenter = _segmenter;
    final relayout = segmenter.width(shown) != segmenter.width(_shown);
    _shown = shown;
    if (relayout) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  /// Moves the time on at the next whole second the task has run, while
  /// it runs: from the time it is attached or set running, not only once
  /// it is painted, so that a row cut off by a clip shows the time it has
  /// run when it comes into view.
  void _startTicking() {
    final b = binding;
    final started = _started;
    if (b == null ||
        _status != TaskStatus.running ||
        owner == null ||
        started == null ||
        _tick != null ||
        !_showElapsed ||
        _given != null) {
      return;
    }
    final seconds = (b.frameTime - started).inSeconds + 1;
    _tick = b.scheduleFrameCallback(
      _tickCallback,
      at: started + Duration(seconds: seconds),
    );
  }

  void _stopTicking() {
    final tick = _tick;
    if (tick != null) {
      _tick = null;
      binding?.cancelFrameCallback(tick);
    }
  }

  void _onTick(Duration time) {
    _tick = null;
    _show();
    _startTicking();
  }

  @override
  void attach(PipelineOwner o) {
    super.attach(o);
    _startTicking();
  }

  @override
  void detach() {
    _steps.stop();
    _stopTicking();
    super.detach();
  }

  @override
  bool get isRepaintBoundary => true;

  /// Hit wherever it is: it paints all of its cells.
  @override
  HitTestBehavior get hitTestBehavior => HitTestBehavior.opaque;

  static final _detached = TextSegmenter();

  TextSegmenter get _segmenter => owner?.segmenter ?? _detached;

  /// Where the child starts.
  int get _indent => _level * 2 + taskMarkWidth(_segmenter, _frames) + 1;

  /// The columns after the child.
  int get _tail => _shown.isEmpty ? 0 : 1 + _segmenter.width(_shown);

  @override
  int computeMinIntrinsicWidth(int height) =>
      _indent + (child?.getMinIntrinsicWidth(height) ?? 0) + _tail;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      _indent + (child?.getMaxIntrinsicWidth(height) ?? 0) + _tail;

  @override
  int computeMinIntrinsicHeight(int width) => 1;

  @override
  int computeMaxIntrinsicHeight(int width) => 1;

  @override
  void performLayout(BoxConstraints c) {
    final indent = _indent;
    final tail = _tail;
    var w = indent + tail;
    if (child case final child?) {
      final room = c.maxW >= BoxConstraints.unbounded
          ? c.maxW
          : (c.maxW > w ? c.maxW - w : 0);
      child.layout(BoxConstraints(0, room, 0, 1), parentUsesSize: true);
      child.parentData
        ..dx = indent
        ..dy = 0;
      w += child.width;
    }
    width = c.constrainW(w);
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final styles = canvas.styles;
    canvas.fill(0, 0, width, height, _style.penIn(styles));
    final x = _level * 2;
    if (_status == TaskStatus.running) {
      _steps.start();
      _startTicking();
    }
    canvas.text(
      x,
      0,
      taskMark(_status, _frames, _steps.current),
      _markStyle.penIn(styles),
    );
    final c = child;
    if (c != null) {
      paintChild(ctx, c);
    }
    if (_shown.isNotEmpty) {
      canvas.text(
        _indent + (c?.width ?? 0) + 1,
        0,
        _shown,
        _elapsedStyle.penIn(styles),
      );
    }
  }
}
