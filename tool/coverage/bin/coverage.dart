// Test coverage per package: `dart test --coverage` in the core and in
// every package with a test/, the lines of its lib/ no test runs, and the
// public declarations they are in. A report per package in
// doc/internals/quality/coverage/<package>.md (the uncovered public API
// first, then the files by their uncovered lines), and the totals in its
// README.md.
//
//   dart run tool/coverage/bin/coverage.dart [PACKAGE...]
//   dart run tool/xtask.dart coverage
//
// Without names, every package with tests is measured. The totals of
// packages not measured are kept from their reports. It fails when a
// package's tests fail; the report is written all the same.
//
// The tests run four files at once (coverageConcurrency says why), and a
// run that writes no file's coverage for five minutes is stopped and the
// files not measured yet run again. The Dart processes the tests start are
// measured too (lib/children.dart), and files only a browser can load are
// listed as such, not as gaps.
import 'dart:io';

import 'package:twk_coverage/coverage_report.dart';
import 'package:twk_doc_snippets/declarations.dart';
import 'package:twk_doc_snippets/packages.dart';

Future<void> main(List<String> args) async {
  final root = findRoot();
  final all = repoPackages(root);
  final List<RepoPackage> packages;
  try {
    packages = selectPackages(all, args);
  } on UnknownPackage catch (e) {
    stderr.writeln('coverage: ${e.message}');
    exitCode = 2;
    return;
  }
  final out = Directory('$root/doc/internals/quality/coverage')
    ..createSync(recursive: true);
  final temp = Directory.systemTemp.createTempSync('twk_coverage_');
  final failed = <String>[];
  try {
    for (final package in packages) {
      if (!package.hasTests) {
        stdout.writeln('${package.name}: no test/, skipped');
        continue;
      }
      stdout.writeln('${package.name}: dart test --coverage in ${package.dir}');
      final dir = Directory('${temp.path}/${package.name}')..createSync();
      final (hits, passed) = await collect(package, dir);
      if (!passed) {
        failed.add(package.name);
      }
      final files = [
        for (final file in package.libraryFiles())
          if ((
                file.substring(package.path.length + 1),
                File(file).readAsStringSync(),
              )
              case (final rel, final source))
            FileCoverage(
              rel,
              declarationsOf(source),
              hits[rel],
              browser: browserOnly(source),
            ),
      ];
      final at = package.dir == '.' ? '' : '${package.dir}/';
      final revision = revisionOf(root, ['${at}lib', '${at}test']);
      File('${out.path}/${package.name}.md').writeAsStringSync(
        coverageReport(package, files, revision, passed: passed),
      );
      final t = Totals.of(files);
      stdout.writeln(
        '${package.name}: ${t.percent} of ${t.lines} lines, '
        '${t.gaps} public declarations no test runs all of'
        '${passed ? '' : ' (its tests failed)'}',
      );
    }
  } finally {
    temp.deleteSync(recursive: true);
  }
  File('${out.path}/README.md').writeAsStringSync(_index(all, out));
  if (failed.isNotEmpty) {
    stderr.writeln('coverage: the tests of ${failed.join(', ')} failed');
    exitCode = 1;
  }
}

/// The table of every package's totals, read back from the reports.
String _index(List<RepoPackage> all, Directory out) {
  final rows = <String>[];
  for (final package in all) {
    final report = File('${out.path}/${package.name}.md');
    if (!report.existsSync()) {
      continue;
    }
    final text = report.readAsStringSync();
    String first(String pattern) =>
        RegExp(pattern, multiLine: true).firstMatch(text)?[1] ?? '?';
    rows.add(
      '| [${package.name}](${package.name}.md) | `${package.dir}` '
      '| ${first(r'^- \*\*([^*]+)\*\* of')} '
      '| ${first(r'of (\d+) lines run')} '
      '| ${first(r'^- \*\*(\d+)\*\* public')} '
      '| ${first(r'^At (\S+),')} |',
    );
  }
  const about =
      'Per package, by `dart run tool/xtask.dart coverage`: the share of the '
      'lines of its `lib/` its tests run, and the public declarations with '
      'lines they do not. The standard is '
      '[doc/internals/quality/README.md](../README.md).';
  return [
    '# Test coverage',
    '',
    about,
    '',
    '| package | directory | covered | lines | public gaps | at |',
    '| --- | --- | ---: | ---: | ---: | --- |',
    ...rows,
    '',
  ].join('\n');
}
