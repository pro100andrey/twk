// A process monitor, after btop: how busy the CPU is and how much memory
// is used, as gauges under sparklines of the minutes before, and the
// processes in a table sorted by the CPU they use, or in a tree under
// their parents. Read from /proc once a second on Linux, made up
// elsewhere and with --synthetic.
//
// A click on a title sorts by its column, again the other way; s does
// that for the column sorted by, < and > sort by the column before or
// after it. The arrows, PageUp, PageDown, Home and End select a process.
// t shows the tree, or the table again, with the process selected there
// selected: Left and Right collapse and expand, * expands all below.
// q quits.
//
//   dart run example/monitor.dart
//   dart run example/monitor.dart --synthetic   # made-up processes
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' show sin;

import 'package:twk/twk.dart';

Future<void> main(List<String> args) => runApp(
  Monitor(
    source: !args.contains('--synthetic') && ProcSource.available
        ? ProcSource()
        : SyntheticSource(),
  ),
);

/// A process as a sample saw it.
final class Proc {
  const Proc({
    required this.pid,
    required this.ppid,
    required this.name,
    this.command = '',
    this.cpu = 0,
    this.memory = 0,
    this.threads = 1,
  });

  final int pid;

  /// The pid of its parent; 0 for none.
  final int ppid;

  final String name;

  /// Its command line; empty for a kernel thread.
  final String command;

  /// How much of a CPU it used since the sample before: 1 for all of one.
  final double cpu;

  /// The memory it holds, in bytes.
  final int memory;

  final int threads;
}

/// What a [ProcessSource] read.
final class Sample {
  const Sample({
    required this.cpu,
    required this.memoryUsed,
    required this.memoryTotal,
    required this.processes,
    this.load = (0, 0, 0),
  });

  /// How much of all the CPUs was busy since the sample before, from 0 to
  /// 1.
  final double cpu;

  /// The memory used and all of it, in bytes.
  final int memoryUsed;
  final int memoryTotal;

  /// The load average over 1, 5 and 15 minutes.
  final (double, double, double) load;

  final List<Proc> processes;
}

/// Where the samples come from.
abstract interface class ProcessSource {
  /// What the system is doing now, the CPU used since the read before
  /// (since it started, for the first).
  Future<Sample> read();
}

/// The system as Linux shows it in /proc, read in an isolate of its own:
/// the files of hundreds of processes take tens of milliseconds, which the
/// app's isolate spends on frames meanwhile.
final class ProcSource implements ProcessSource {
  /// Reads [root], a directory laid out as /proc is.
  ProcSource({String root = '/proc'}) : _reader = _ProcReader(root);

  /// Whether the system has /proc.
  static bool get available => File('/proc/stat').existsSync();

  // what the reads before saw: copied to the isolate of a read, which
  // sends it back
  _ProcReader _reader;

  @override
  Future<Sample> read() async {
    final reader = _reader;
    final (sample, after) = await Isolate.run(() => (reader.read(), reader));
    _reader = after;
    return sample;
  }
}

/// What reads /proc, and remembers what it read.
final class _ProcReader {
  _ProcReader(this.root);

  final String root;

  // the jiffies of all the CPUs at the read before, and those of each
  // process by pid; the command lines by pid, with the start of the
  // process they are of
  var _total = 0;
  var _idle = 0;
  var _times = <int, int>{};
  final _commands = <int, (int, String)>{};

  Sample read() {
    final (total, idle, cpus) = _cpuTimes();
    final elapsed = total - _total;
    final cpu = elapsed > 0 ? 1 - (idle - _idle) / elapsed : 0.0;
    // the jiffies of one CPU
    final perCpu = elapsed / cpus;
    final times = <int, int>{};
    final starts = <int, int>{};
    final processes = <Proc>[];
    for (final entry in Directory(root).listSync()) {
      final pid = int.tryParse(entry.path.substring(root.length + 1));
      if (pid == null) {
        continue;
      }
      final String stat;
      try {
        stat = _read('$root/$pid/stat');
      } on FileSystemException {
        // it ended
        continue;
      }
      // the name is between the first ( and the last ), and may hold both
      final open = stat.indexOf('(');
      final close = stat.lastIndexOf(')');
      final name = stat.substring(open + 1, close);
      final fields = stat.substring(close + 2).split(' ');
      final time = int.parse(fields[11]) + int.parse(fields[12]);
      final start = int.parse(fields[19]);
      times[pid] = time;
      starts[pid] = start;
      processes.add(
        Proc(
          pid: pid,
          ppid: int.parse(fields[1]),
          name: name,
          command: _command(pid, start),
          cpu: perCpu > 0 ? (time - (_times[pid] ?? 0)) / perCpu : 0,
          // pages of 4 KiB, as most Linux systems have
          memory: int.parse(fields[21]) * 4096,
          threads: int.parse(fields[17]),
        ),
      );
    }
    _total = total;
    _idle = idle;
    _times = times;
    _commands.removeWhere((pid, command) => starts[pid] != command.$1);

    final memory = _fields('meminfo');
    final memoryTotal = memory['MemTotal:']! * 1024;
    final available = memory['MemAvailable:'] ?? memory['MemFree:']!;
    final load = _read('$root/loadavg').split(' ');
    return Sample(
      cpu: cpu,
      memoryUsed: memoryTotal - available * 1024,
      memoryTotal: memoryTotal,
      load: (
        double.parse(load[0]),
        double.parse(load[1]),
        double.parse(load[2]),
      ),
      processes: processes,
    );
  }

  /// The jiffies of all the CPUs since the system started, those idle,
  /// and how many CPUs there are.
  (int, int, int) _cpuTimes() {
    final lines = LineSplitter.split(_read('$root/stat'));
    // user nice system idle iowait irq softirq steal: guest is in user
    final jiffies = lines.first
        .split(' ')
        .skip(1)
        .where((f) => f.isNotEmpty)
        .take(8)
        .map(int.parse)
        .toList();
    final core = RegExp(r'^cpu\d');
    final cpus = lines.where(core.hasMatch).length;
    return (
      jiffies.fold(0, (sum, j) => sum + j),
      jiffies[3] + jiffies[4],
      cpus > 0 ? cpus : 1,
    );
  }

  /// The command line of process [pid], started at [start]: read once.
  String _command(int pid, int start) {
    final known = _commands[pid];
    if (known != null && known.$1 == start) {
      return known.$2;
    }
    var command = '';
    try {
      command = _read('$root/$pid/cmdline').replaceAll('\x00', ' ').trim();
    } on FileSystemException {
      // it ended
    }
    _commands[pid] = (start, command);
    return command;
  }

  /// The numbers of a file of `name: number` lines in [root], by name.
  Map<String, int> _fields(String file) => {
    for (final line in LineSplitter.split(_read('$root/$file')))
      if (line.split(RegExp(' +')) case [final name, final value, ...])
        name: int.parse(value),
  };

  String _read(String path) =>
      utf8.decode(File(path).readAsBytesSync(), allowMalformed: true);
}

/// Made-up processes, the CPU they use rising and falling, a compiler
/// started under make every three seconds: the same at each run, for
/// tests and systems without /proc.
final class SyntheticSource implements ProcessSource {
  var _second = 0;

  static const _cpus = 4;
  static const int _memory = 16 << 30;

  /// pid, ppid, name, command, the most of a CPU used, MiB held, threads.
  static const _processes = <(int, int, String, String, double, int, int)>[
    (1, 0, 'systemd', '/usr/lib/systemd/systemd --system', .02, 14, 1),
    (2, 0, 'kthreadd', '', 0, 0, 1),
    (14, 2, 'ksoftirqd/0', '', .03, 0, 1),
    (51, 2, 'kworker/1:2', '', .05, 0, 1),
    (312, 1, 'systemd-journal', '/lib/systemd/systemd-journald', .04, 48, 1),
    (498, 1, 'NetworkManager', '/usr/bin/NetworkManager -n', .02, 21, 4),
    (733, 1, 'sshd', '/usr/bin/sshd -D', 0, 9, 1),
    (801, 1, 'dockerd', '/usr/bin/dockerd -H fd://', .08, 96, 22),
    (950, 801, 'containerd', '/usr/bin/containerd', .06, 52, 14),
    (1203, 950, 'postgres', 'postgres -D /var/lib/postgresql/data', .3, 220, 1),
    (1240, 1203, 'postgres', 'postgres: checkpointer', .04, 30, 1),
    (1241, 1203, 'postgres', 'postgres: walwriter', .06, 18, 1),
    (1500, 1, 'tmux: server', 'tmux new -s work', .03, 8, 1),
    (1501, 1500, 'zsh', '-zsh', 0, 6, 1),
    (1502, 1500, 'zsh', '-zsh', 0, 6, 1),
    (2210, 1501, 'dart', 'dart run example/monitor.dart', .12, 140, 9),
    (2600, 1502, 'make', 'make -j4', .02, 4, 1),
    (4102, 733, 'sshd', 'sshd: ann [priv]', 0, 11, 1),
    (4120, 4102, 'bash', '-bash', 0, 5, 1),
    (4388, 4120, 'vim', 'vim lib/main.dart', .01, 32, 1),
  ];

  @override
  Future<Sample> read() async {
    final s = _second++;
    // the part of the program being compiled
    final part = s ~/ 3;
    final processes = [
      for (final (pid, ppid, name, command, cpu, mib, threads) in _processes)
        Proc(
          pid: pid,
          ppid: ppid,
          name: name,
          command: command,
          cpu: cpu * (1 + sin(s / 3 + pid)) / 2,
          memory: mib << 20,
          threads: threads,
        ),
      Proc(
        pid: 3000 + part,
        ppid: 2600,
        name: 'cc',
        command: 'cc -O2 -c src/part$part.c',
        cpu: .5 + .2 * (s % 3),
        memory: (40 + 30 * (s % 3)) << 20,
      ),
    ];
    final busy = processes.fold<double>(0, (sum, p) => sum + p.cpu);
    final held = processes.fold(0, (sum, p) => sum + p.memory);
    return Sample(
      cpu: busy / _cpus,
      // the kernel's and the caches' too
      memoryUsed: held + (3 << 30) + (s % 20 << 24),
      memoryTotal: _memory,
      load: (busy, 1.1 + .2 * sin(s / 30), .9),
      processes: processes,
    );
  }
}

/// The processes of the last sample, for a [Table].
final class _Rows extends TableSource<Proc> {
  var _processes = const <Proc>[];

  void update(List<Proc> processes) {
    _processes = processes;
    notifyListeners();
  }

  @override
  int get rowCount => _processes.length;

  @override
  Proc rowAt(int index) => _processes[index];
}

/// The table's columns: made once, as the table sorts and measures again
/// for other columns.
final _columns = [
  TableColumn<Proc>(
    title: 'pid',
    width: const .fixed(7),
    align: .right,
    cell: (p) => TableCell('${p.pid}'),
    compare: (a, b) => a.pid.compareTo(b.pid),
  ),
  TableColumn<Proc>(
    title: 'name',
    width: const .content(max: 16),
    cell: (p) => TableCell(p.name),
    compare: (a, b) => a.name.compareTo(b.name),
  ),
  TableColumn<Proc>(
    title: 'cpu%',
    width: const .fixed(6),
    align: .right,
    cell: (p) => TableCell(_percent(p.cpu)),
    compare: (a, b) => a.cpu.compareTo(b.cpu),
  ),
  TableColumn<Proc>(
    title: 'mem',
    width: const .fixed(6),
    align: .right,
    cell: (p) => TableCell(_bytes(p.memory)),
    compare: (a, b) => a.memory.compareTo(b.memory),
  ),
  TableColumn<Proc>(
    title: 'thr',
    width: const .fixed(5),
    align: .right,
    cell: (p) => TableCell('${p.threads}'),
    compare: (a, b) => a.threads.compareTo(b.threads),
  ),
  TableColumn<Proc>(
    title: 'command',
    width: const .fr(1),
    cell: (p) => TableCell(p.command.isEmpty ? '[${p.name}]' : p.command),
    compare: (a, b) => a.command.compareTo(b.command),
  ),
];

/// The samples the sparklines keep.
const _history = 240;

final class Monitor extends StatefulWidget {
  const Monitor({required this.source, super.key});

  final ProcessSource source;

  @override
  State<Monitor> createState() => _MonitorState();
}

final class _MonitorState extends State<Monitor> {
  // the last sample; null until the first read ends
  Sample? _sample;
  var _reading = false;
  // the CPU busy and the memory used at each sample, oldest first: a new
  // list each time, which the sparklines repaint for
  var _cpu = const <double>[];
  var _memory = const <double>[];
  // the parent of each process, the processes by their parents' pids,
  // and those without one
  var _ppids = const <int, int>{};
  var _children = const <int, List<Proc>>{};
  var _roots = const <Proc>[];
  // the pids of the processes that had children
  final _parents = <int>{};
  final _rows = _Rows();
  // by the CPU used, the most first
  final _table = TableController(sortColumn: 2, sortAscending: false);
  final _tree = TreeController();
  late final Timer _timer;
  var _showTree = false;

  @override
  void initState() {
    super.initState();
    _read();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _read());
  }

  @override
  void dispose() {
    _timer.cancel();
    _rows.dispose();
    _table.dispose();
    _tree.dispose();
    super.dispose();
  }

  /// Reads a sample, unless the read before has not ended.
  void _read() {
    if (_reading) {
      return;
    }
    _reading = true;
    unawaited(
      widget.source
          .read()
          .then((sample) {
            if (mounted) {
              setState(() => _take(sample));
            }
          })
          // a read that failed (a process gone while /proc was read) is
          // logged, and the next tick reads again
          .catchError((Object error) => log('reading failed: $error'))
          .whenComplete(() => _reading = false),
    );
  }

  void _take(Sample sample) {
    _sample = sample;
    _cpu = _add(_cpu, sample.cpu);
    _memory = _add(_memory, sample.memoryUsed / sample.memoryTotal);
    _rows.update(sample.processes);

    final ppids = {for (final p in sample.processes) p.pid: p.ppid};
    final children = <int, List<Proc>>{};
    final roots = <Proc>[];
    for (final p in sample.processes) {
      if (ppids.containsKey(p.ppid)) {
        (children[p.ppid] ??= []).add(p);
      } else {
        roots.add(p);
      }
    }
    _ppids = ppids;
    _children = children;
    _roots = roots;
    // a process shows its children until collapsed
    _tree.expandAll(children.keys.where(_parents.add));
  }

  static List<double> _add(List<double> history, double value) => [
    ...history.length < _history ? history : history.skip(1),
    value,
  ];

  void _toggleTree() => setState(() {
    _showTree = !_showTree;
    if (_showTree) {
      final pid = _table.selectedKey;
      _tree.selectedKey = pid;
      // the process selected shows, its ancestors expanded
      _tree.expandAll([
        for (var at = _ppids[pid]; at != null; at = _ppids[at]) at,
      ]);
    } else {
      _table.selectedKey = _tree.selectedKey;
    }
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // the gauges and the sparklines paint both colors of their cells
    final base = theme.background.merge(theme.text);
    final sample = _sample;
    final (load1, load5, load15) = sample?.load ?? (0, 0, 0);
    return KeyBindings(
      {'t': _toggleTree, 'q': () => AppBinding.of(context).quit()},
      child: Box(
        style: base,
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            SizedBox(
              height: 6,
              child: Row(
                crossAxisAlignment: .stretch,
                children: [
                  Expanded(
                    child: _Meter(
                      title: 'cpu',
                      about: sample == null
                          ? null
                          : 'load ${load1.toStringAsFixed(2)} '
                                '${load5.toStringAsFixed(2)} '
                                '${load15.toStringAsFixed(2)}',
                      history: _cpu,
                      style: base.merge(theme.info),
                    ),
                  ),
                  Expanded(
                    child: _Meter(
                      title: 'mem',
                      about: sample == null
                          ? null
                          : '${_bytes(sample.memoryUsed)} of '
                                '${_bytes(sample.memoryTotal)}',
                      history: _memory,
                      style: base.merge(theme.accent),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Box(
                border: Border.all(type: .rounded, style: theme.border),
                titles: [
                  BorderTitle(
                    ' ${sample?.processes.length ?? 0} processes ',
                    style: theme.primary,
                  ),
                ],
                padding: const .only(left: 1),
                child: _showTree
                    ? _ProcessTree(
                        roots: _roots,
                        children: _children,
                        controller: _tree,
                      )
                    : Table<Proc>.source(
                        source: _rows,
                        columns: _columns,
                        rowKey: (p) => p.pid,
                        controller: _table,
                        autofocus: true,
                      ),
              ),
            ),
            _KeyHints([
              ('↑↓', 'select'),
              if (_showTree) ...[
                ('←→', 'fold'),
                ('*', 'unfold all'),
                ('t', 'table'),
              ] else ...[
                ('s < >', 'sort'),
                ('t', 'tree'),
              ],
              ('q', 'quit'),
            ]),
          ],
        ),
      ),
    );
  }
}

/// The processes as a tree: [roots] and the [children] of each by pid,
/// each with its pid, its share of a CPU and its memory.
final class _ProcessTree extends StatelessWidget {
  const _ProcessTree({
    required this.roots,
    required this.children,
    required this.controller,
  });

  final List<Proc> roots;
  final Map<int, List<Proc>> children;
  final TreeController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TreeView<Proc>(
      roots: roots,
      children: (p) => children[p.pid] ?? const [],
      hasChildren: (p) => children.containsKey(p.pid),
      nodeKey: (p) => p.pid,
      controller: controller,
      autofocus: true,
      label: (context, entry) {
        final p = entry.node;
        return Row(
          children: [
            Expanded(
              child: Text(p.name, wrap: .none, overflow: .ellipsis),
            ),
            Text(
              '${'${p.pid}'.padLeft(8)}${_percent(p.cpu).padLeft(7)}'
              '${_bytes(p.memory).padLeft(7)}',
              style: theme.muted,
            ),
          ],
        );
      },
    );
  }
}

/// [history] as a sparkline in [style], over a gauge of its last value,
/// in a box titled [title], and [about] at the right.
final class _Meter extends StatelessWidget {
  const _Meter({
    required this.title,
    required this.about,
    required this.history,
    required this.style,
  });

  final String title;
  final String? about;
  final List<double> history;
  final Style style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = history.lastOrNull ?? 0;
    return Box(
      border: Border.all(type: .rounded, style: theme.border),
      titles: [
        BorderTitle(' $title ', style: theme.primary),
        if (about case final about?)
          BorderTitle(' $about ', style: theme.muted, alignment: .topRight),
      ],
      padding: const .x(1),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Expanded(
            child: Sparkline(data: history, max: 1, style: style),
          ),
          LineGauge(
            ratio: ratio,
            label: '${_percent(ratio).padLeft(5)}% ',
            filledStyle: ratio < .7
                ? theme.success
                : (ratio < .9 ? theme.warning : theme.error),
            unfilledStyle: theme.border,
          ),
        ],
      ),
    );
  }
}

/// A share of a CPU as a percentage: `12.5`.
String _percent(double share) => (share * 100).toStringAsFixed(1);

/// [bytes] as `ps` shows them: `512K`, `12.3M`, `1.5G`.
String _bytes(int bytes) {
  const units = ['B', 'K', 'M', 'G', 'T'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit > 0 && value < 100 ? 1 : 0;
  return '${value.toStringAsFixed(digits)}${units[unit]}';
}

/// A row of [keys], each before what it does.
final class _KeyHints extends StatelessWidget {
  const _KeyHints(this.keys);

  final List<(String, String)> keys;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text.rich(
      [
        for (final (key, does) in keys) ...[
          Span(' $key ', theme.primary).bold,
          Span('$does ', theme.muted),
        ],
      ],
      wrap: .none,
      overflow: .ellipsis,
    );
  }
}
