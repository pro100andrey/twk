// The frame benchmark as a verb: tool/bench.dart under the machine's bench
// lock, pinned to the benchmark's core, its report read for what
// CONTRIBUTING.md forbids.
import 'dart:io';

import 'package:xtask/xtask.dart';

import 'cpus.dart';

/// The lock two benchmarks on this machine never share, unless BENCH_LOCK
/// names another: agents running at once on one machine take it.
const defaultBenchLock = '/tmp/twk/bench.lock';

/// Runs `dart run tool/bench.dart` against BENCH_BASELINE (HEAD unless
/// set; a `--baseline=` among the arguments wins), with the arguments after
/// `--` passed on. Under `flock` on the bench lock, and `taskset -c` on the
/// benchmark's core, each where the tool is installed and, for the core,
/// online; said so when one is left out. Its output is shown as it comes
/// (`tee`) and read when it ends: fails when the benchmark failed or its
/// report says what [judgeReport] fails.
Future<int> bench(VerbContext c, Cpus cpus) async {
  final cpu = Cpus.benchCpu(c.env);
  final pinned =
      cpu != null &&
      (cpus.allowed?.contains(cpu) ?? false) &&
      cpus.siblings(cpu) != null &&
      c.which('taskset') != null;
  final lock = c.env['BENCH_LOCK'] ?? defaultBenchLock;
  final locked = c.which('flock') != null;
  if (locked) {
    File(lock).parent.createSync(recursive: true);
  }
  final baseline = c.args.any((a) => a.startsWith('--baseline='))
      ? const <String>[]
      : ['--baseline=${c.env['BENCH_BASELINE'] ?? 'HEAD'}'];
  c.log(
    'bench: ${locked ? 'waiting for $lock' : 'flock not installed: not locked'}'
    ' · ${pinned ? 'pinned to CPU $cpu' : 'not pinned: expect noise'}',
  );
  final res = await c.tee([
    if (locked) ...['flock', lock],
    if (pinned) ...['taskset', '-c', '$cpu'],
    'dart',
    'run',
    'tool/bench.dart',
    ...baseline,
    ...c.args,
  ]);
  if (res.exitCode != 0) {
    c.log('bench: tool/bench.dart failed (exit ${res.exitCode})');
    return ExitCode.taskFailed;
  }
  final (:failed, :notes) = judgeReport(res.stdout);
  notes.forEach(c.log);
  return failed ? ExitCode.taskFailed : ExitCode.success;
}

/// What tool/bench.dart's [report] says against CONTRIBUTING.md: a
/// scenario that writes more bytes per frame fails; one slower by more
/// than 5 % fails only when the times count — the run pinned and the
/// core's sibling idle — and is otherwise noted, to be measured again when
/// the machine is quiet.
({bool failed, List<String> notes}) judgeReport(String report) {
  String? after(String prefix) {
    for (final line in report.split('\n')) {
      if (line.startsWith(prefix)) {
        return line.substring(prefix.length).trim();
      }
    }
    return null;
  }

  final noise = report
      .split('\n')
      .firstWhere(
        (l) => l.startsWith('pinned to CPU') || l.startsWith('not pinned'),
        orElse: () => '',
      );
  final counts = noise.startsWith('pinned to CPU') && !noise.contains('busy:');
  final slower = after('slower by more than 5%:');
  final bytes = after('more bytes per frame:');
  if (slower == null || bytes == null) {
    return (failed: false, notes: ['bench: no baseline, nothing compared']);
  }
  final notes = <String>[];
  var failed = false;
  if (bytes != 'none') {
    failed = true;
    notes.add('bench: more bytes per frame in $bytes');
  }
  if (slower != 'none') {
    if (counts) {
      failed = true;
      notes.add('bench: slower by more than 5 %: $slower');
    } else {
      notes.add(
        'bench: slower by more than 5 %: $slower — but the times do not '
        'count (${noise.isEmpty ? 'no noise line' : noise}); run it again '
        'when the machine is quiet',
      );
    }
  } else if (!counts) {
    notes.add('bench: the times do not count ($noise)');
  }
  if (notes.isEmpty) {
    notes.add('bench: no more bytes, none slower');
  }
  return (failed: failed, notes: notes);
}
