// The ProgressList page.
part of 'animation.dart';

/// The downloads of the ProgressList page: a name, a size in bytes, and
/// the bytes each tick brings.
const _downloads = [
  ('assets.zip', 3400000, 170000),
  ('fonts.tar.gz', 1200000, 140000),
  ('docs.tar.gz', 5600000, 90000),
];

/// How often the downloads bring bytes, in ms.
const _progressTick = 300;

/// The ticks after which it all starts again.
const _progressRun = 40;

/// The tick the docs fail at, and the one the build is done at.
const _docsFail = 12;

const _buildDone = 30;

/// The columns the page offers, by name.
const _progressColumns = <String, List<ProgressColumn>>{
  'default': ProgressList.defaultColumns,
  'count': [
    ProgressColumn.mark,
    ProgressColumn.label,
    ProgressColumn.bar,
    ProgressColumn.count,
    ProgressColumn.eta,
  ],
  'elapsed': [
    ProgressColumn.mark,
    ProgressColumn.label,
    ProgressColumn.bar,
    ProgressColumn.percent,
    ProgressColumn.elapsed,
  ],
};

/// Takes [tracker]'s tasks away and adds the downloads and the build, set
/// going, as the Code's `_start` does.
void _startProgress(ProgressTracker tracker) {
  for (final task in [...tracker.tasks]) {
    tracker.remove(task);
  }
  for (final (name, size, _) in _downloads) {
    tracker.add(name, total: size, unit: ProgressUnit.bytes).start();
  }
  tracker.add('Building binary').start();
}

/// The [ticks]th tick of [tracker], as the Code's `_tick` does it.
void _tickProgress(ProgressTracker tracker, int ticks) {
  if (ticks % _progressRun == 0) {
    return _startProgress(tracker);
  }
  final tasks = tracker.tasks;
  for (final (i, (_, _, bytes)) in _downloads.indexed) {
    final task = tasks[i]..advance(bytes);
    if (task.completed >= task.total!) {
      task.done();
    }
  }
  if (ticks % _progressRun == _docsFail) {
    tasks[2].fail('connection reset');
  }
  if (ticks % _progressRun == _buildDone) {
    tasks[3].done();
  }
}

final _progressList = GalleryPage(
  group: 'Animation',
  title: 'ProgressList',
  options: [
    ChoiceOption('columns', 'columns', values: _progressColumns.keys.toList()),
    ChoiceOption(
      'bar',
      'bar',
      values: [for (final s in ProgressBarShape.values) s.name],
    ),
    // a running task's mark, as the Spinner page's frames
    ChoiceOption('spinner', 'spinner', values: _frames.keys.toList()),
    const SwitchOption('hide', 'hide finished'),
    const ChoiceOption(
      'max',
      'at most',
      values: [null, 2],
      labels: ['all', '2'],
    ),
  ],
  build: (context, o) => _Progress(
    columns: _progressColumns[o.choice<String>('columns')]!,
    barShape: ProgressBarShape.values.byName(o.choice('bar')),
    spinner: _frames[o.choice<String>('spinner')]!,
    hideFinished: o.flag('hide'),
    maxVisible: o.choice('max'),
  ),
  code: (o) {
    final columns = o.choice<String>('columns');
    return [
      codeLine([
        '/// The downloads: a name, a size in bytes, and the bytes a tick ',
        'brings.',
      ]),
      'static const _downloads = [',
      for (final (name, size, bytes) in _downloads)
        "  ('$name', $size, $bytes),",
      '];',
      '',
      "/// On the app's clock, which a test's fake clock moves too.",
      'late final _tracker = ProgressTracker(',
      '  clock: AppBinding.of(context).twkApp.clock,',
      ');',
      'late final Timer _timer;',
      'var _ticks = 0;',
      '',
      '@override',
      'void initState() {',
      '  super.initState();',
      '  _start();',
      '  // the bytes that came in, every $_progressTick ms',
      '  _timer = Timer.periodic(',
      '    const Duration(milliseconds: $_progressTick),',
      '    (_) => _tick(),',
      '  );',
      '}',
      '',
      '@override',
      'void dispose() {',
      '  _timer.cancel();',
      '  _tracker.dispose();',
      '  super.dispose();',
      '}',
      '',
      '/// The downloads and the build, from the start.',
      'void _start() {',
      '  for (final task in [..._tracker.tasks]) {',
      '    _tracker.remove(task);',
      '  }',
      '  for (final (name, size, _) in _downloads) {',
      '    _tracker.add(name, total: size, unit: .bytes).start();',
      '  }',
      "  _tracker.add('Building binary').start();",
      '}',
      '',
      'void _tick() {',
      '  // and all again, after ${_progressRun * _progressTick ~/ 1000} s',
      '  if (++_ticks % $_progressRun == 0) {',
      '    return _start();',
      '  }',
      '  final tasks = _tracker.tasks;',
      '  for (final (i, (_, _, bytes)) in _downloads.indexed) {',
      '    final task = tasks[i]..advance(bytes);',
      '    if (task.completed >= task.total!) {',
      '      task.done();',
      '    }',
      '  }',
      '  if (_ticks % $_progressRun == $_docsFail) {',
      "    tasks[2].fail('connection reset');",
      '  }',
      '  if (_ticks % $_progressRun == $_buildDone) {',
      '    tasks[3].done();',
      '  }',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) => SizedBox(',
      '  width: 60,',
      '  child: ProgressList(',
      '    tracker: _tracker,',
      if (columns != 'default') ...[
        '    columns: const [',
        for (final c in _progressColumns[columns]!) '      .${c.name},',
        '    ],',
      ],
      if (o.choice<String>('bar') != 'blocks')
        '    barShape: .${o.choice<String>('bar')},',
      if (o.choice<String>('spinner') != 'dots')
        '    spinner: .${o.choice<String>('spinner')},',
      if (o.flag('hide')) '    hideFinished: true,',
      if (o.choice<int?>('max') case final max?) '    maxVisible: $max,',
      '  ),',
      ');',
    ].join('\n');
  },
);

/// A stopwatch at the time it is set to: the gallery's, as the tracker
/// reads it, so that a route's `t=` stills the times it shows.
final class _Watch implements Stopwatch {
  Duration at = Duration.zero;

  @override
  Duration get elapsed => at;

  @override
  int get elapsedMicroseconds => at.inMicroseconds;

  @override
  int get elapsedMilliseconds => at.inMilliseconds;

  @override
  int get elapsedTicks => at.inMicroseconds;

  @override
  int get frequency => 1000000;

  @override
  bool get isRunning => true;

  @override
  void reset() {}

  @override
  void start() {}

  @override
  void stop() {}
}

/// The downloads and the build in a ProgressList, ticked on the gallery's
/// clock from when the page was built: each tick the Code's timer would
/// have run by now is run, the tracker's time at the tick's.
final class _Progress extends StatefulWidget {
  const _Progress({
    required this.columns,
    required this.barShape,
    required this.spinner,
    required this.hideFinished,
    required this.maxVisible,
  });

  final List<ProgressColumn> columns;
  final ProgressBarShape barShape;
  final SpinnerFrames spinner;
  final bool hideFinished;
  final int? maxVisible;

  @override
  State<_Progress> createState() => _ProgressState();
}

final class _ProgressState extends State<_Progress> with MotionState {
  final _watch = _Watch();
  late final _tracker = ProgressTracker(clock: _watch);
  Duration? _born;
  var _ticks = 0;

  @override
  void dispose() {
    _tracker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    motion.begin(context);
    final now = motion.now;
    final born = _born ??= motion.frozen ? Duration.zero : now;
    if (_ticks == 0 && _tracker.tasks.isEmpty) {
      _watch.at = Duration.zero;
      _startProgress(_tracker);
    }
    final due = (now - born).inMilliseconds ~/ _progressTick;
    while (_ticks < due) {
      _ticks++;
      _watch.at = Duration(milliseconds: _ticks * _progressTick);
      _tickProgress(_tracker, _ticks);
    }
    _watch.at = now - born;
    motion
      ..wakeAt(born + Duration(milliseconds: (_ticks + 1) * _progressTick))
      ..end();
    return SizedBox(
      width: 60,
      child: ProgressList(
        tracker: _tracker,
        columns: widget.columns,
        barShape: widget.barShape,
        spinner: widget.spinner,
        hideFinished: widget.hideFinished,
        maxVisible: widget.maxVisible,
      ),
    );
  }
}
