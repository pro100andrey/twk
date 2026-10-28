// The public members of the core and of every package that have no doc
// comment, as the analyzer's public_member_api_docs lint finds them: a
// report per package in doc/internals/quality/undocumented/<package>.md
// (file:line and the member's name), and their counts in its README.md.
//
//   dart run tool/doc_snippets/bin/undocumented.dart [PACKAGE...]
//   dart run tool/xtask.dart undocumented
//
// Named packages have their reports written again; the counts of the
// others in README.md are kept.
import 'dart:io';

import 'package:twk_doc_snippets/packages.dart';
import 'package:twk_doc_snippets/undocumented.dart';

Future<void> main(List<String> args) async {
  final root = findRoot();
  final all = repoPackages(root);
  final List<RepoPackage> packages;
  try {
    packages = selectPackages(all, args);
  } on UnknownPackage catch (e) {
    stderr.writeln('undocumented: ${e.message}');
    exitCode = 2;
    return;
  }
  final temp = Directory.systemTemp.createTempSync('twk_undocumented_');
  final Map<String, List<Undocumented>> found;
  try {
    found = await findUndocumented(packages, temp);
  } finally {
    temp.deleteSync(recursive: true);
  }
  final out = Directory('$root/doc/internals/quality/undocumented')
    ..createSync(recursive: true);
  for (final package in packages) {
    final members = found[package.name];
    if (members == null) {
      continue;
    }
    final revision = revisionOf(root, ['${package.dir}/lib']);
    File(
      '${out.path}/${package.name}.md',
    ).writeAsStringSync(undocumentedReport(package, members, revision));
    stdout.writeln('${package.name}: ${members.length}');
  }
  File('${out.path}/README.md').writeAsStringSync(_index(all, out));
}

/// The table of every package's count, read back from the reports.
String _index(List<RepoPackage> all, Directory out) {
  final rows = <String>[];
  var total = 0;
  for (final package in all) {
    final report = File('${out.path}/${package.name}.md');
    if (!report.existsSync()) {
      continue;
    }
    final text = report.readAsStringSync();
    final count =
        int.tryParse(RegExp(r'\*\*(\d+)\*\*').firstMatch(text)?[1] ?? '0') ?? 0;
    final at = RegExp(r'^At (\S+),', multiLine: true).firstMatch(text)?[1];
    total += count;
    rows.add(
      '| [${package.name}](${package.name}.md) | `${package.dir}` | $count '
      '| $at |',
    );
  }
  const about =
      'Per package, by `dart run tool/xtask.dart undocumented`: the public '
      "members the analyzer's `public_member_api_docs` finds without a "
      'doc comment. The standard is '
      '[doc/internals/quality/README.md](../README.md).';
  return [
    '# Undocumented public members',
    '',
    about,
    '',
    '| package | directory | undocumented | at |',
    '| --- | --- | ---: | --- |',
    ...rows,
    '| **all** | | **$total** | |',
    '',
  ].join('\n');
}
