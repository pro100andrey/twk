// A package's test files joined in generated entry points, so `dart test`
// compiles, loads and JITs one isolate a group instead of one a file. Each
// entry imports its files with a prefix and calls each `main()` inside
// `group('<file path>', ...)`, so a failure still names its file. A file the
// join could change the meaning of stays apart and runs as it is. `dart test
// <file>` is unchanged for every file.
//
// The `group-tests` verb (verbs.dart) writes them afresh on each run, under
// [groupsDirectory], so that a new test file is in a group without anybody
// asking, and keeps the run's times there for the next run's balance.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Where a package's entry points are, from the package: not checked in.
const groupsDirectory = '.dart_tool/test_groups';

/// The json reporter's log of the last run, from the package.
const timesFile = '$groupsDirectory/times.json';

/// Reasons a file stays out, each a pattern in the file's source. These are
/// the things a join changes: where the file is told to run, what it
/// measures about its own place, the isolate it shares with others.
final _reasons = <String, RegExp>{
  'annotation (@TestOn, @Tags, @Timeout, @Skip)': RegExp(
    r'^@(TestOn|Tags|Timeout|Skip)\b',
    multiLine: true,
  ),
  'async main': RegExp(r'\bmain\(\s*\)\s*async\b|Future<void>\s+main\('),
  'main is not `void main()`': RegExp(r'^(?![\s\S]*\nvoid main\(\)\s*\{)'),
  'Platform.script': RegExp(r'Platform\.script'),
  'Isolate lookups': RegExp(r'\bIsolate\.'),
  'reads a stack of its own (StackTrace.current, Trace)': RegExp(
    r'StackTrace\.current|\bTrace\.|Frame\.caller|\.stackTrace\b',
  ),
  'starts a process': RegExp(
    r'\bProcess\.(run|start)|\brunProcess\(|\bstartProcess\(',
  ),
};

final _processTag = RegExp(r"^@Tags\(\[.*'process'.*\]\)", multiLine: true);

/// Files left out by hand, for what a pattern cannot see: the value says
/// what in the file a join would change.
///
/// The audit of the mutable statics a test of packages/twk assigns found
/// each reset by the test or read as a difference, so none is listed:
///
/// - `Screen.sweepFloor` (switcher_test): restored by `addTearDown`.
/// - `DebugAids.runEditor` (editor_test): restored in `tearDown`.
/// - `AppBinding.postEvent` (hot_reload_test, service_extensions_test, the
///   latter `process`-tagged): restored by `addTearDown`.
/// - `Provider.debugCheckInvalidValueType` (provider_test): restored by
///   `addTearDown`.
/// - `TextBuffer.joins` (text_buffer, text_area, text_editing and the two
///   perf tests): only ever read as a difference of two reads.
/// - `LogView.renderVisits` (log_view_perf_test): set to 0 right before the
///   measured work, read right after it.
/// - state a test keeps in its own file (`Probe.builds`, `Fill.paints`,
///   `builds`, `lastGrid`...): a file's library is imported once, so it is
///   the file's own.
///
/// Private statics of lib (`TextBuffer._lastId`, `Cli._default`,
/// `Terminal._ofStdio`, `AppBinding._registered`, `_anyVisual`, caches) are
/// no test's to assign; they are what the runs below put to the proof.
const _byHand = <String, String>{};

/// Which file of a suite goes where.
final class TestGroups {
  /// [groups] of files, and those [apart], each with why.
  const TestGroups({required this.groups, required this.apart});

  /// The files of each entry point, none of them empty.
  final List<List<String>> groups;

  /// The files that stay out of the entry points, each with why.
  final Map<String, String> apart;
}

/// The files of [sources], source by path from the package, in [groups]
/// entry points balanced by [times], seconds by file, their size where a
/// file has none; with [shuffle], a seed, in an order of that seed instead.
TestGroups planGroups(
  Map<String, String> sources, {
  int groups = 8,
  Map<String, double> times = const {},
  int? shuffle,
}) {
  final joined = <String>[];
  final apart = <String, String>{};
  for (final MapEntry(key: file, value: source) in sources.entries) {
    final reasons = [
      for (final MapEntry(key: reason, value: pattern) in _reasons.entries)
        if (pattern.hasMatch(source)) reason,
      if (source.contains(file)) 'names its own path',
      ?_byHand[file],
    ];
    if (reasons.isEmpty) {
      joined.add(file);
    } else {
      apart[file] = reasons.join('; ');
    }
  }
  double weight(String file) => times[file] ?? sources[file]!.length / 20000;
  joined.sort();
  if (shuffle != null) {
    joined.shuffle(Random(shuffle));
  } else {
    joined.sort((a, b) => weight(b).compareTo(weight(a)));
  }
  final load = List<double>.filled(groups, 0);
  final members = List.generate(groups, (_) => <String>[]);
  // the heaviest first (or in the shuffled order), each to the lightest group
  for (final file in joined) {
    var lightest = 0;
    for (var i = 1; i < groups; i++) {
      if (load[i] < load[lightest]) {
        lightest = i;
      }
    }
    members[lightest].add(file);
    load[lightest] += weight(file);
  }
  return TestGroups(
    groups: [
      for (final files in members)
        if (files.isNotEmpty) files..sort(),
    ],
    apart: apart,
  );
}

/// The source of an entry point joining [files], paths from the package.
String entryPoint(List<String> files) {
  final up = '../' * groupsDirectory.split('/').length;
  return [
    '// Generated by tool/xtask/test_groups.dart: do not edit.',
    "import 'package:test/test.dart';",
    for (final (i, file) in files.indexed) "import '$up$file' as f$i;",
    '',
    'void main() {',
    for (final (i, file) in files.indexed) "  group('$file', f$i.main);",
    '}',
    '',
  ].join('\n');
}

/// What to give `dart test` for [plan] with the entry points of
/// [groupsDirectory]: those, then the files apart but the `process` ones of
/// [sources], which `process-test` runs. A `@TestOn` of another platform is
/// `dart test`'s to pass by.
List<String> testArguments(TestGroups plan, Map<String, String> sources) => [
  for (var i = 0; i < plan.groups.length; i++)
    '$groupsDirectory/group_${i}_test.dart',
  for (final file in plan.apart.keys)
    if (!_processTag.hasMatch(sources[file]!)) file,
];

/// Writes the entry points of [plan] into [directory], the last run's gone.
void writeGroups(Directory directory, TestGroups plan) {
  directory.createSync(recursive: true);
  for (final file in directory.listSync().whereType<File>()) {
    if (file.path.endsWith('_test.dart')) {
      file.deleteSync();
    }
  }
  for (final (i, files) in plan.groups.indexed) {
    File(
      '${directory.path}/group_${i}_test.dart',
    ).writeAsStringSync(entryPoint(files));
  }
}

/// The test files of the package at [directory], source by path from it.
Map<String, String> testSources(Directory directory) {
  final skip = directory.path.length + 1;
  return {
    for (final entry in Directory(
      '${directory.path}/test',
    ).listSync(recursive: true))
      if (entry is File && entry.path.endsWith('_test.dart'))
        entry.path.substring(skip): entry.readAsStringSync(),
  };
}

/// Seconds the tests of each file took, from the lines of a json reporter's
/// log. A group's suite is many files: a test says its file by the start of
/// its name, the group it was run in, or by its suite when run as it is.
Map<String, double> timesOf(Iterable<String> log) {
  final times = <String, double>{};
  final suites = <int, String>{};
  final tests = <int, (String, int)>{};
  for (final line in log) {
    if (!line.startsWith('{')) {
      continue;
    }
    final event = jsonDecode(line) as Map<String, dynamic>;
    switch (event['type']) {
      case 'suite':
        final suite = event['suite'] as Map<String, dynamic>;
        suites[suite['id'] as int] = suite['path'] as String;
      case 'testStart':
        final test = event['test'] as Map<String, dynamic>;
        final suite = suites[test['suiteID']];
        final first = (test['name'] as String).split(' ').first;
        final file = first.endsWith('_test.dart') ? first : suite;
        if (file != null && !file.startsWith(groupsDirectory)) {
          tests[test['id'] as int] = (file, event['time'] as int);
        }
      case 'testDone':
        if (tests[event['testID']] case (final file, final started)?) {
          times[file] =
              (times[file] ?? 0) + ((event['time'] as int) - started) / 1000;
        }
      default:
    }
  }
  return times;
}
