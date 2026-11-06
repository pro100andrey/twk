// The TaskList page.
part of 'data.dart';

/// What each step of the build takes: fetch, core, widgets, tests, deploy.
const _buildMs = [1400, 1200, 1600, 2400, 1200];

/// The tests, failing.
const _failMs = 1500;

/// Done, before it runs again.
const _restMs = 3000;

/// What each step of a run takes, its rest the last: 0 fetch, 1 and 2
/// compile, 3 test, 4 deploy, then the rest (failed: no deploy).
List<int> _runMs({required bool failed}) => [
  for (final (i, ms) in _buildMs.indexed)
    if (!failed || i < 4) ...[if (failed && i == 3) _failMs else ms],
  _restMs,
];

/// The steps each task of the run goes from and to: the fetch, the
/// compile, its two files, the tests and the deploy.
const _taskSpans = [(0, 1), (1, 3), (1, 2), (2, 3), (3, 4), (4, 5)];

/// The tasks of the Code's `_tasks` at [step]: 0 fetch, 1 and 2 compile, 3
/// test, 4 deploy, 5 done; [into] ms into the run whose steps start at
/// [starts]. Each is given its time on the gallery's clock, which a route's
/// `t=` stops: the list's own, from the frame it saw a task running, would
/// go on.
List<TaskItem> _liveTasks(
  int step,
  int into,
  List<int> starts, {
  required bool failed,
}) {
  // a task that runs from step [from] to step [to], failing with [fails]
  TaskItem task(
    String label,
    int from,
    int to, {
    bool fails = false,
    List<TaskItem> children = const [],
  }) {
    final (status, ms) = step < from
        ? (TaskItemStatus.pending, null)
        : step < to
        ? (TaskItemStatus.running, into - starts[from])
        : (
            fails ? TaskItemStatus.failed : TaskItemStatus.done,
            starts[to] - starts[from],
          );
    return TaskItem(
      label,
      status: status,
      elapsed: ms == null ? null : Duration(milliseconds: ms),
      children: children,
    );
  }

  return [
    task('Fetch dependencies', 0, 1),
    task(
      'Compile',
      1,
      3,
      children: [
        task('lib/core.dart', 1, 2),
        task('lib/widgets.dart', 2, 3),
      ],
    ),
    if (failed) ...[
      task('Run the tests', 3, 4, fails: true),
      TaskItem(
        'Deploy',
        status: step < 4 ? TaskItemStatus.pending : TaskItemStatus.skipped,
      ),
    ] else ...[
      task('Run the tests', 3, 4),
      task('Deploy', 4, 5),
    ],
  ];
}

/// The tasks of a build at [step]: those before it done, it running, or
/// failed and those after it skipped, and those after it pending; the task
/// running has run [ran].
List<TaskItem> _stepTasks(int step, Duration ran, {required bool failed}) {
  TaskItemStatus at(int i) => i < step
      ? TaskItemStatus.done
      : i > step
      ? (failed ? TaskItemStatus.skipped : TaskItemStatus.pending)
      : (failed ? TaskItemStatus.failed : TaskItemStatus.running);
  Duration? time(int i) => at(i) == TaskItemStatus.running ? ran : null;
  return [
    TaskItem('Fetch dependencies', status: at(0), elapsed: time(0)),
    TaskItem(
      'Compile',
      status: at(1),
      elapsed: time(1),
      children: [
        TaskItem(
          'lib/core.dart',
          status: step > 0 ? TaskItemStatus.done : TaskItemStatus.pending,
        ),
        TaskItem('lib/widgets.dart', status: at(1), elapsed: time(1)),
      ],
    ),
    TaskItem('Run the tests', status: at(2), elapsed: time(2)),
    TaskItem('Deploy', status: at(3), elapsed: time(3)),
  ];
}

/// Asks [wake] for the gallery time at which a task running since [since]
/// has run a second more than at [ms], as the list moves its time on.
void _wakeAtSecond(int since, int ms, void Function(int) wake) =>
    wake(since + ((ms - since) ~/ 1000 + 1) * 1000);

/// The stage of the TaskList page, which keeps the gallery time the step
/// it shows was chosen at, as the design's state does.
final class _TaskStage extends StatefulWidget {
  const _TaskStage(this.o);

  final Options o;

  @override
  State<_TaskStage> createState() => _TaskStageState();
}

final class _TaskStageState extends State<_TaskStage> {
  // the step shown and failed, and the gallery time it was chosen at
  Object? _stepKey;
  var _since = 0;

  @override
  Widget build(BuildContext context) => Timed((context, ms, wake) {
    final o = widget.o;
    final step = o(_taskListStep);
    final failed = o(_taskListFailed);
    List<TaskItem> tasks;
    if (step is int) {
      // the task it runs has run since the step was chosen
      final key = (step, failed);
      if (_stepKey != key) {
        _stepKey = key;
        _since = ms;
      }
      tasks = _stepTasks(
        step,
        Duration(milliseconds: ms - _since),
        failed: failed,
      );
      if (!failed && step < 4) {
        _wakeAtSecond(_since, ms, wake);
      }
    } else {
      // the run, again and again, on the gallery's clock: the step it is
      // at, and a build at the next
      final run = _runMs(failed: failed);
      // where each step starts, ms into the run, and where it ends
      final starts = [0];
      for (final d in run) {
        starts.add(starts.last + d);
      }
      final into = ms % starts.last;
      final i = starts.lastIndexWhere((s) => s <= into);
      wake(ms - into + starts[i + 1]);
      final step = failed && i >= 4 ? 5 : i;
      tasks = _liveTasks(step, into, starts, failed: failed);
      // what runs moves its time on at each second from its start
      for (final (from, to) in _taskSpans) {
        if (from <= step && step < to) {
          _wakeAtSecond(ms - into + starts[from], ms, wake);
        }
      }
    }
    return SizedBox(
      width: 40,
      child: TaskList(
        // a list of its own for each step: its tasks done show no time
        key: step is int ? ValueKey((step, failed)) : null,
        spinner: _spinners[o(_taskListSpinner)],
        showElapsed: o(_taskListElapsed),
        tasks: tasks,
      ),
    );
  });
}

const Map<String, SpinnerFrames> _spinners = {
  'dots': SpinnerFrames.dots,
  'line': SpinnerFrames.line,
  'arc': SpinnerFrames.arc,
};

/// The TaskList page's `step` option.
const _taskListStep = ChoiceOption<Object>(
  'step',
  'step',
  values: ['live', 0, 1, 2, 3, 4],
  labels: ['live', 'fetch', 'compile', 'test', 'deploy', 'done'],
);

/// The TaskList page's `failed` option.
const _taskListFailed = SwitchOption('failed', 'failed');

/// The TaskList page's `elapsed` option.
const _taskListElapsed = SwitchOption(
  'elapsed',
  'elapsed',
  initial: true,
);

/// The TaskList page's `spinner` option.
const _taskListSpinner = ChoiceOption<String>(
  'spinner',
  'spinner',
  values: ['dots', 'line', 'arc'],
);

final _taskList = GalleryPage(
  group: _group,
  title: 'TaskList',
  options: const [
    _taskListStep,
    _taskListFailed,
    _taskListElapsed,
    _taskListSpinner,
  ],
  build: (context, o) => _TaskStage(o),
  code: (o) {
    final step = o(_taskListStep);
    final failed = o(_taskListFailed);
    final spinner = o(_taskListSpinner);
    final tasks = step is int ? '_build($step, failed: $failed)' : '_tasks';
    final list = [
      '@override',
      'Widget build(BuildContext context) => SizedBox(',
      '  width: 40,',
      '  child: TaskList(',
      if (step is int) ...[
        '    // a list of its own for each step: its tasks done show no time',
        '    key: const ValueKey(($step, $failed)),',
      ],
      if (spinner != 'dots') '    spinner: SpinnerFrames.$spinner,',
      if (!o(_taskListElapsed)) '    showElapsed: false,',
      '    tasks: $tasks,',
      '  ),',
      ');',
    ];
    if (step is int) {
      return [
        ...list,
        '',
        codeLine([
          '/// The tasks of a build at [step]: those before it done, it ',
          'running, or',
        ]),
        '/// failed and those after it skipped, and those after it pending.',
        'List<TaskItem> _build(int step, {required bool failed}) {',
        '  TaskItemStatus at(int i) => i < step',
        '      ? .done',
        '      : i > step',
        '      ? (failed ? .skipped : .pending)',
        '      : (failed ? .failed : .running);',
        '  return [',
        "    TaskItem('Fetch dependencies', status: at(0)),",
        '    TaskItem(',
        "      'Compile',",
        '      status: at(1),',
        '      children: [',
        codeLine([
          "        TaskItem('lib/core.dart', status: step > 0 ? .done : ",
          '.pending),',
        ]),
        "        TaskItem('lib/widgets.dart', status: at(1)),",
        '      ],',
        '    ),',
        "    TaskItem('Run the tests', status: at(2)),",
        "    TaskItem('Deploy', status: at(3)),",
        '  ];',
        '}',
      ].join('\n');
    }
    final next = failed ? 'step < 4 ? step : 5' : 'step';
    return [
      '// what runs: 0 fetch, 1 and 2 compile, 3 test, 4 deploy, 5 done',
      'var _step = 0;',
      '',
      '@override',
      'void initState() {',
      '  super.initState();',
      '  unawaited(_run());',
      '}',
      '',
      '/// The build, again and again: each step a while, then the next.',
      'Future<void> _run() async {',
      '  const ms = [${_runMs(failed: failed).join(', ')}];',
      '  while (mounted) {',
      '    for (var step = 0; step < ms.length && mounted; step++) {',
      '      setState(() => _step = $next);',
      '      await Future<void>.delayed(Duration(milliseconds: ms[step]));',
      '    }',
      '  }',
      '}',
      '',
      'List<TaskItem> get _tasks {',
      '  // a task that runs from step [from] to step [to]',
      '  TaskItemStatus at(int from, int to) =>',
      '      _step < from ? .pending : (_step < to ? .running : .done);',
      '  return [',
      "    TaskItem('Fetch dependencies', status: at(0, 1)),",
      '    TaskItem(',
      "      'Compile',",
      '      status: at(1, 3),',
      '      children: [',
      "        TaskItem('lib/core.dart', status: at(1, 2)),",
      "        TaskItem('lib/widgets.dart', status: at(2, 3)),",
      '      ],',
      '    ),',
      if (failed) ...[
        '    TaskItem(',
        "      'Run the tests',",
        codeLine([
          '      status: _step < 3 ? .pending : (_step < 4 ? .running : ',
          '.failed),',
        ]),
        '    ),',
        "    TaskItem('Deploy', status: _step < 4 ? .pending : .skipped),",
      ] else ...[
        "    TaskItem('Run the tests', status: at(3, 4)),",
        "    TaskItem('Deploy', status: at(4, 5)),",
      ],
      '  ];',
      '}',
      '',
      ...list,
    ].join('\n');
  },
);
