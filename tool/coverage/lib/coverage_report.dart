/// A package's test coverage: gathered from `dart test --coverage`, tied to
/// the public declarations whose lines no test runs, and written up as
/// Markdown.
library;

import 'dart:convert';
import 'dart:io';

import 'package:coverage/coverage.dart';
import 'package:twk_doc_snippets/declarations.dart';
import 'package:twk_doc_snippets/packages.dart';

import 'children.dart';

/// How many test files `dart test` runs at once under coverage.
///
/// After each test file the runner collects its coverage over the VM
/// service, whose `getVM` reads `/proc/self/smaps`: the bigger the process,
/// the longer that takes. With a dozen files at once the runner holds 1.3
/// to 1.9 GB and a `getVM` takes up to 400 ms, while package:coverage gives
/// it 200 ms and asks again, without end: the requests pile up, every one
/// of them late, and the run spins at 100 % CPU forever. Four at once keep
/// the runner under 1 GB and a `getVM` near 20 ms.
const coverageConcurrency = 4;

/// How long a run may go without a test file's coverage written before it
/// is taken for stuck, stopped, and the files not yet measured run again.
const stallAfter = Duration(minutes: 5);

/// Runs [package]'s tests with coverage into [dir] and answers the hits of
/// each line of its `lib/` files that the tests loaded, by the file's path
/// relative to the package (`lib/src/box.dart`), with whether the tests
/// passed.
///
/// The Dart processes the tests start count too (children.dart): the
/// runner is package:test's script run as the copied SDK's `dart`, where
/// [testRunner] finds it and the platform allows.
///
/// A run in which no test file's coverage is written for [stall] is
/// stopped, and the test files not measured yet run in a new one, up to
/// [attempts] runs; the tests fail when the last of them stalls too.
Future<(Map<String, Map<int, int>>, bool)> collect(
  RepoPackage package,
  Directory dir, {
  Duration stall = stallAfter,
  int attempts = 3,
}) async {
  var passed = true;
  List<String>? files;
  final runner = testRunner(package);
  final children = runner == null
      ? null
      : ChildCoverage.start(
          package,
          Directory('${dir.path}.children')..createSync(),
          Directory('${dir.path}/children'),
        );
  for (var attempt = 1; ; attempt++) {
    final report = File('${dir.path}.$attempt.jsonl');
    final test = await Process.start(
      Platform.resolvedExecutable,
      [
        // package:test's runner itself, told the copied SDK's dart is the
        // one it runs as, which the tests start their processes with
        if (runner != null && children != null) ...[
          '--resolved_executable_name=${children.dart}',
          '--packages=${package.packageConfigFile!.path}',
          runner,
        ] else
          'test',
        '--coverage=${dir.path}',
        '--concurrency=$coverageConcurrency',
        '--reporter=failures-only',
        '--file-reporter=json:${report.path}',
        ...?files,
      ],
      workingDirectory: package.path,
      mode: ProcessStartMode.inheritStdio,
    );
    final code = await watch(test, dir, stall);
    if (report.existsSync() && failedIn(report.readAsStringSync())) {
      passed = false;
    }
    if (code != null) {
      passed = passed && code == 0;
      break;
    }
    dropUnreadable(dir);
    files = unmeasured(package, dir);
    stderr.writeln(
      'coverage: ${package.name}: no test file finished in '
      '${stall.inSeconds} s; stopped, ${counted(files.length, 'file')} '
      'not measured yet',
    );
    if (files.isEmpty) {
      break;
    }
    if (attempt == attempts) {
      passed = false;
      break;
    }
  }
  if (children != null) {
    await children.stop();
    stdout.writeln(
      '${package.name}: ${counted(children.measured, 'process', 'processes')} '
      'the tests started measured'
      '${children.lost == 0 ? '' : ', ${children.lost} not (ended by exit() '
                'or a signal, or still running)'}',
    );
  }
  final maps = await HitMap.parseFiles(
    [
      for (final e in dir.listSync(recursive: true))
        if (e is File && e.path.endsWith('.json')) e,
    ],
    checkIgnoredLines: true,
    packagePath: package.path,
  );
  final prefix = 'package:${package.name}/';
  return (
    {
      for (final MapEntry(:key, :value) in maps.entries)
        if (key.startsWith(prefix))
          'lib/${key.substring(prefix.length)}': value.lineHits,
    },
    passed,
  );
}

/// The script of package:test's runner (`bin/test.dart`) in [package]'s
/// resolution; null when it has none, or no `test` package.
String? testRunner(RepoPackage package) {
  final config = package.packageConfigFile;
  if (config == null) {
    return null;
  }
  final json = jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
  for (final p
      in (json['packages']! as List<Object?>).cast<Map<String, Object?>>()) {
    if (p['name'] == 'test') {
      final at = p['rootUri']! as String;
      final root = config.uri.resolve(at.endsWith('/') ? at : '$at/');
      final script = File.fromUri(root.resolve('bin/test.dart'));
      return script.existsSync() ? script.path : null;
    }
  }
  return null;
}

/// Waits for [test] to exit and answers its exit code, or stops it and
/// answers null when no `.json` file under [dir] is new for [stall].
Future<int?> watch(Process test, Directory dir, Duration stall) async {
  var exited = false;
  final code = test.exitCode.whenComplete(() => exited = true);
  var last = DateTime.now();
  while (!exited) {
    await Future.any([code, Future<void>.delayed(_poll(stall))]);
    if (exited) {
      break;
    }
    for (final e in dir.listSync(recursive: true)) {
      if (e is File && e.path.endsWith('.json')) {
        final at = e.lastModifiedSync();
        if (at.isAfter(last)) {
          last = at;
        }
      }
    }
    if (DateTime.now().difference(last) > stall) {
      // the runner waits for the tests running to finish on the first
      // signal, and those wait for it
      test.kill();
      await Future.any([
        code,
        Future<void>.delayed(const Duration(seconds: 5)),
      ]);
      test.kill(ProcessSignal.sigkill);
      await code;
      return null;
    }
  }
  return code;
}

Duration _poll(Duration stall) {
  final tenth = stall ~/ 10;
  return tenth < const Duration(seconds: 5)
      ? tenth
      : const Duration(seconds: 5);
}

/// Whether the JSON reporter's [lines] report a test that failed; a line
/// cut off, the last of a run stopped while it wrote it, reports nothing.
bool failedIn(String lines) => const LineSplitter()
    .convert(lines)
    .where((line) => line.contains('"testDone"'))
    .map(_decodeOrNull)
    .any(
      (event) => switch (event) {
        {'type': 'testDone', 'result': 'failure' || 'error'} => true,
        _ => false,
      },
    );

Object? _decodeOrNull(String line) {
  try {
    return jsonDecode(line);
  } on FormatException {
    return null;
  }
}

/// Deletes the coverage files under [dir] that a stopped run left half
/// written.
void dropUnreadable(Directory dir) {
  for (final e in dir.listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.json')) {
      try {
        jsonDecode(e.readAsStringSync());
      } on FormatException {
        e.deleteSync();
      }
    }
  }
}

/// The test files of [package] (`test/box_test.dart`, sorted) with no
/// coverage file under [dir].
List<String> unmeasured(RepoPackage package, Directory dir) {
  final tests = Directory('${package.path}/test');
  return [
    for (final e in tests.listSync(recursive: true, followLinks: false))
      if (e is File && e.path.endsWith('_test.dart'))
        if (e.path.substring(package.path.length + 1) case final file
            when !File('${dir.path}/$file.vm.json').existsSync())
          file,
  ]..sort();
}

/// Whether [source], a Dart file, imports a library only a browser has
/// (`dart:js_interop`, `dart:html`, `package:web`), which no test on the VM
/// can load.
bool browserOnly(String source) => _browserImport.hasMatch(source);

final _browserImport = RegExp(
  r'''^\s*import\s+['"](dart:js_interop|dart:js_util|dart:html|package:web/)''',
  multiLine: true,
);

/// One file of a package's `lib/` and what its tests ran of it.
final class FileCoverage {
  /// [file] (relative to its package), its [declarations], and the [hits]
  /// of its lines; null [hits] when no test loaded it. [browser] when it is
  /// [browserOnly].
  FileCoverage(this.file, this.declarations, this.hits, {this.browser = false});

  /// The file, relative to its package.
  final String file;

  /// Its declarations.
  final List<Declaration> declarations;

  /// How many times each line that has code ran; null when no test loaded
  /// the file.
  final Map<int, int>? hits;

  /// Whether a test loaded it.
  bool get loaded => hits != null;

  /// Whether only a browser can load it ([browserOnly]).
  final bool browser;

  /// Whether no test loaded it although one on the VM could: a gap, its
  /// public declarations with code counted as such.
  bool get unloaded => !loaded && !browser;

  /// Whether no test loaded it, only a browser being able to.
  bool get browserUnloaded => !loaded && browser;

  /// The lines with code, a test having loaded the file.
  int get lines => hits?.length ?? 0;

  /// The lines with code that no test ran, ascending.
  late final List<int> uncovered = [
    for (final MapEntry(:key, :value) in (hits ?? const {}).entries)
      if (value == 0) key,
  ]..sort();

  /// Its public declarations (not types: their members) with lines no test
  /// ran, each with those lines and the lines it has code on.
  List<(Declaration, List<int>, int)> uncoveredPublic() {
    final hits = this.hits;
    if (hits == null) {
      return const [];
    }
    return [
      for (final d in declarations)
        if (d.isPublic && !d.isType)
          if (_linesOf(d, hits) case (final missed, final all)
              when missed.isNotEmpty)
            (d, missed, all),
    ];
  }

  /// The public declarations with code (not types, nor abstract or
  /// external members) of a file no test loaded, a getter and its setter
  /// once.
  List<Declaration> get publicDeclarations {
    final seen = <String>{};
    return [
      for (final d in declarations)
        if (d.isPublic && d.hasCode && seen.add(d.name)) d,
    ];
  }
}

(List<int>, int) _linesOf(Declaration d, Map<int, int> hits) {
  final missed = <int>[];
  var all = 0;
  for (var line = d.firstLine; line <= d.lastLine; line++) {
    final h = hits[line];
    if (h == null) {
      continue;
    }
    all++;
    if (h == 0) {
      missed.add(line);
    }
  }
  return (missed, all);
}

/// [count] and [one] (`line`), made plural (`lines`, or [many]) unless
/// [count] is 1.
String counted(int count, String one, [String? many]) =>
    '$count ${count == 1 ? one : many ?? '${one}s'}';

/// [lines] (ascending) as ranges: `3-5, 9`.
String ranges(List<int> lines) {
  final out = <String>[];
  for (var i = 0; i < lines.length;) {
    var j = i;
    while (j + 1 < lines.length && lines[j + 1] == lines[j] + 1) {
      j++;
    }
    out.add(i == j ? '${lines[i]}' : '${lines[i]}-${lines[j]}');
    i = j + 1;
  }
  return out.join(', ');
}

/// The totals a report starts with, and the index lists.
final class Totals {
  /// The totals of [files].
  factory Totals.of(List<FileCoverage> files) {
    var lines = 0;
    var uncovered = 0;
    var public = 0;
    var unloaded = 0;
    var notLoaded = 0;
    var browser = 0;
    for (final f in files) {
      lines += f.lines;
      uncovered += f.uncovered.length;
      public += f.uncoveredPublic().length;
      if (f.publicDeclarations.isNotEmpty) {
        if (f.unloaded) {
          notLoaded++;
          unloaded += f.publicDeclarations.length;
        } else if (f.browserUnloaded) {
          browser++;
        }
      }
    }
    return Totals._(lines, uncovered, public, unloaded, notLoaded, browser);
  }

  Totals._(
    this.lines,
    this.uncovered,
    this.public,
    this.unloaded,
    this.notLoaded,
    this.browser,
  );

  /// Lines with code in the files the tests loaded.
  final int lines;

  /// Those of them no test ran.
  final int uncovered;

  /// Public declarations with lines no test ran, in the files tests
  /// loaded.
  final int public;

  /// Public declarations with code in the files no test loaded.
  final int unloaded;

  /// Files no test loaded that have public declarations with code, but
  /// for the browser's.
  final int notLoaded;

  /// Browser-only files ([browserOnly]) no test loaded that have public
  /// declarations with code: not gaps, as no test on the VM can load them.
  final int browser;

  /// The public declarations [public] and [unloaded] count.
  int get gaps => public + unloaded;

  /// The share of [lines] the tests ran, as `87.5 %`.
  String get percent => lines == 0
      ? '-'
      : '${((lines - uncovered) * 100 / lines).toStringAsFixed(1)} %';
}

/// [package]'s coverage report, as Markdown: the totals, the public
/// declarations with lines no test runs (the files with the most first),
/// the files no test loads, then every file by its uncovered lines.
String coverageReport(
  RepoPackage package,
  List<FileCoverage> files,
  String revision, {
  required bool passed,
}) {
  final t = Totals.of(files);
  final dir = package.dir == '.' ? '' : '${package.dir}/';
  final browserFiles = counted(t.browser, 'browser-only file');
  final out = StringBuffer()
    ..writeln('# Test coverage: ${package.name}')
    ..writeln()
    ..writeln(
      'At $revision, by `dart run tool/xtask.dart coverage`: '
      '`dart test --coverage` in `${package.dir}`, the lines of its `lib/` '
      'no test runs. The standard the gaps are filled to is '
      '[doc/internals/quality/README.md](../README.md).',
    )
    ..writeln()
    ..writeln(
      '- **${t.percent}** of ${t.lines} lines run by the tests; '
      '${t.uncovered} not.',
    )
    ..writeln(
      '- **${t.gaps}** public declarations no test runs all of: '
      '${t.public} with lines no test runs, ${t.unloaded} in the '
      '${counted(t.notLoaded, 'file')} no test loads'
      '${t.browser == 0 ? '' : '; the $browserFiles not counted'}.',
    );
  if (!passed) {
    out.writeln(
      '- The tests failed: the numbers are those of the tests that ran.',
    );
  }
  out
    ..writeln()
    ..writeln('## Public declarations with lines no test runs')
    ..writeln();
  final gaps = [
    for (final f in files)
      if (f.uncoveredPublic() case final g when g.isNotEmpty) (f, g),
  ];
  int missedIn(List<(Declaration, List<int>, int)> g) =>
      g.fold(0, (n, e) => n + e.$2.length);
  gaps.sort((a, b) {
    final by = missedIn(b.$2).compareTo(missedIn(a.$2));
    return by != 0 ? by : a.$1.file.compareTo(b.$1.file);
  });
  if (gaps.isEmpty) {
    out
      ..writeln('None.')
      ..writeln();
  }
  for (final (f, g) in gaps) {
    out
      ..writeln('### `$dir${f.file}` (${counted(missedIn(g), 'line')})')
      ..writeln();
    for (final (d, missed, all) in g) {
      out.writeln(
        '- `${d.line}` ${d.kind} `${d.name}`: ${missed.length} of '
        '${counted(all, 'line')} (${ranges(missed)})',
      );
    }
    out.writeln();
  }

  void list(Iterable<FileCoverage> files) {
    for (final f in files) {
      final names = [for (final d in f.publicDeclarations) '`${d.name}`'];
      out.writeln('- `$dir${f.file}`: ${names.join(', ')}');
    }
    out.writeln();
  }

  final unloaded = [
    for (final f in files)
      if (f.unloaded && f.publicDeclarations.isNotEmpty) f,
  ];
  if (unloaded.isNotEmpty) {
    out
      ..writeln('## Files no test loads')
      ..writeln();
    list(unloaded);
  }
  final browser = [
    for (final f in files)
      if (f.browserUnloaded && f.publicDeclarations.isNotEmpty) f,
  ];
  if (browser.isNotEmpty) {
    out
      ..writeln('## Browser-only files')
      ..writeln()
      ..writeln(
        'They import `dart:js_interop`, `dart:html` or `package:web`, which '
        'no test on the VM can load: what runs them is the browser tests '
        '(`dart run tool/xtask.dart browser-test`), which this report does '
        'not measure. Not counted as gaps.',
      )
      ..writeln();
    list(browser);
  }

  final partly =
      [
        for (final f in files)
          if (f.uncovered.isNotEmpty) f,
      ]..sort((a, b) {
        final by = b.uncovered.length.compareTo(a.uncovered.length);
        return by != 0 ? by : a.file.compareTo(b.file);
      });
  out
    ..writeln('## Files by uncovered lines')
    ..writeln();
  if (partly.isEmpty) {
    out.writeln('Every line of every file a test loads runs.');
  } else {
    out
      ..writeln('| file | uncovered | of | lines no test runs |')
      ..writeln('| --- | ---: | ---: | --- |');
    for (final f in partly) {
      out.writeln(
        '| `$dir${f.file}` | ${f.uncovered.length} | ${f.lines} '
        '| ${ranges(f.uncovered)} |',
      );
    }
  }
  final full = files.where((f) => f.loaded && f.uncovered.isEmpty).length;
  out
    ..writeln()
    ..writeln('${counted(full, 'file has', 'files have')} every line run.');
  return out.toString();
}
