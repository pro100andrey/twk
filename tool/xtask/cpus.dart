// Which CPUs the benchmark has to itself, and which are left for the rest.
//
// The fleet's rule: the benchmark runs pinned to one core (BENCH_CPU, 23 by
// default) and that core's SMT sibling stays idle, so everything else that
// is heavy runs on the other CPUs. Read from /sys and /proc (Linux); where
// they aren't there, or the core isn't online, nothing is pinned.
import 'dart:io';

/// The core the benchmark is pinned to unless BENCH_CPU names another.
const defaultBenchCpu = 23;

/// The CPUs of a list such as `0-10,12-22` or `11,23`; null when it isn't
/// one.
Set<int>? parseCpuList(String text) {
  final cpus = <int>{};
  for (final part in text.trim().split(',')) {
    if (part.isEmpty) {
      continue;
    }
    final range = part.split('-');
    final from = int.tryParse(range.first);
    final to = range.length == 2 ? int.tryParse(range.last) : from;
    if (range.length > 2 || from == null || to == null || to < from) {
      return null;
    }
    for (var c = from; c <= to; c++) {
      cpus.add(c);
    }
  }
  return cpus;
}

/// [cpus] written as `taskset -c` takes them, runs joined: `0-10,12-22`.
String formatCpuList(Set<int> cpus) {
  final sorted = cpus.toList()..sort();
  final parts = <String>[];
  for (var i = 0; i < sorted.length;) {
    var j = i;
    while (j + 1 < sorted.length && sorted[j + 1] == sorted[j] + 1) {
      j++;
    }
    parts.add(j == i ? '${sorted[i]}' : '${sorted[i]}-${sorted[j]}');
    i = j + 1;
  }
  return parts.join(',');
}

/// What this machine says about its CPUs, read once.
final class Cpus {
  const Cpus({required this.allowed, required this.siblings});

  /// Read from /proc and /sys.
  factory Cpus.host() => Cpus(
    allowed: _read('/proc/self/status', (text) {
      for (final line in text.split('\n')) {
        if (line.startsWith('Cpus_allowed_list:')) {
          return parseCpuList(line.substring(line.indexOf(':') + 1));
        }
      }
      return null;
    }),
    siblings: (cpu) => _read(
      '/sys/devices/system/cpu/cpu$cpu/topology/thread_siblings_list',
      parseCpuList,
    ),
  );

  /// The CPUs this process may run on (`Cpus_allowed_list`), or null.
  final Set<int>? allowed;

  /// The SMT siblings of a CPU, itself included; null when it isn't online.
  final Set<int>? Function(int cpu) siblings;

  /// The benchmark's core: BENCH_CPU in [env], else [defaultBenchCpu];
  /// null when that isn't a number.
  static int? benchCpu(Map<String, String> env) =>
      int.tryParse(env['BENCH_CPU'] ?? '$defaultBenchCpu');

  /// The CPUs left when [bench] and its siblings are taken out of the
  /// allowed ones; null when there is nothing to leave out (the core isn't
  /// online or allowed) or nothing would be left.
  Set<int>? spare(int bench) {
    final all = allowed;
    final taken = siblings(bench);
    if (all == null || taken == null || !all.contains(bench)) {
      return null;
    }
    final left = all.difference(taken);
    return left.isEmpty ? null : left;
  }

  static T? _read<T>(String path, T? Function(String text) parse) {
    try {
      return parse(File(path).readAsStringSync());
    } on FileSystemException {
      return null;
    }
  }
}
