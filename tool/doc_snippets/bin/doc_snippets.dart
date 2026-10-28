// The ```dart examples of every `///` doc comment in lib/ of the core and
// of every package, each written to a Dart file of its own that sees its
// package's public libraries, and analyzed: an error, a warning or an info
// fails it, reported at the doc comment's file:line. The conventions are
// lib/snippets.dart's and doc/internals/quality/README.md's.
//
//   dart run tool/doc_snippets/bin/doc_snippets.dart [PACKAGE...]
//   dart run tool/xtask.dart doc-snippets
//
// --keep keeps the generated files (and names their directory).
import 'dart:io';

import 'package:twk_doc_snippets/packages.dart';
import 'package:twk_doc_snippets/snippets.dart';

/// What an example need not be held to: names an example declares to show
/// them, imports it is handed and does not use, code after a `throw`.
const _ignored = [
  'unused_local_variable',
  'unused_element',
  'unused_field',
  'unused_import',
  'unnecessary_import',
  'unused_shown_name',
  'dead_code',
];

Future<void> main(List<String> args) async {
  final keep = args.contains('--keep');
  final root = findRoot();
  final List<RepoPackage> packages;
  try {
    packages = selectPackages(
      repoPackages(root),
      args.where((a) => !a.startsWith('--')),
    );
  } on UnknownPackage catch (e) {
    stderr.writeln('doc_snippets: ${e.message}');
    exitCode = 2;
    return;
  }
  final temp = Directory.systemTemp.createTempSync('twk_doc_snippets_');
  File('${temp.path}/analysis_options.yaml').writeAsStringSync(
    [
      'analyzer:',
      '  language:',
      '    strict-casts: true',
      '    strict-inference: true',
      '    strict-raw-types: true',
      '  errors:',
      for (final code in _ignored) '    $code: ignore',
      '',
    ].join('\n'),
  );

  // The generated file, absolute, to the source file it came from and the
  // generated file's line origins.
  final origins = <String, (String, Generated, Snippet)>{};
  var snippets = 0;
  var skipped = 0;
  var files = 0;
  for (final package in packages) {
    final dir = '${temp.path}/${package.name}';
    var written = 0;
    for (final file in package.libraryFiles()) {
      final source = File(file).readAsStringSync();
      if (!source.contains('```')) {
        continue;
      }
      final found = snippetsOf(source);
      if (found.isEmpty) {
        continue;
      }
      files++;
      final preamble = preambleOf(source);
      for (final s in found) {
        snippets++;
        if (s.skipped) {
          skipped++;
          continue;
        }
        if (written == 0) {
          Directory('$dir/.dart_tool').createSync(recursive: true);
          File(
            '$dir/.dart_tool/package_config.json',
          ).writeAsStringSync(package.packageConfig());
          File('$dir/pubspec.yaml').writeAsStringSync(
            'name: ${package.name}_doc_snippets\n'
            'environment:\n  sdk: ^3.13.5\n',
          );
        }
        final generated = generate(s, preamble, package.publicLibraries());
        final out = '$dir/snippet_${written++}.dart';
        File(out).writeAsStringSync(generated.text);
        origins[out] = (package.relative(file), generated, s);
      }
    }
  }

  final findings = origins.isEmpty
      ? const <Finding>[]
      : await analyzeJson(temp.path);
  // Each issue by the file, line and column it is reported at, to sort.
  final reported = <(String, int, int, String)>[];
  for (final f in findings) {
    final origin = origins[f.file];
    if (origin == null) {
      reported.add((
        f.file,
        f.line,
        f.column,
        '${f.severity} ${f.code}: '
            '${f.message}',
      ));
      continue;
    }
    final (file, generated, snippet) = origin;
    final from = f.line - 1 < generated.origins.length
        ? generated.origins[f.line - 1]
        : null;
    final (line, column) = from == null
        ? (snippet.fenceLine, 1)
        : (from.$1, from.$2 + f.column);
    reported.add((
      file,
      line,
      column,
      '${f.severity} ${f.code}: ${f.message}'
          '${from == null ? ' (in the code around the example)' : ''}',
    ));
  }
  reported.sort((a, b) {
    final byFile = a.$1.compareTo(b.$1);
    if (byFile != 0) {
      return byFile;
    }
    final byLine = a.$2.compareTo(b.$2);
    return byLine != 0 ? byLine : a.$3.compareTo(b.$3);
  });
  for (final (file, line, column, text) in reported) {
    stdout.writeln('$file:$line:$column: $text');
  }
  stdout.writeln(
    '$snippets examples in $files files of ${packages.length} packages: '
    '${snippets - skipped} analyzed, $skipped not; '
    '${reported.length} issues.',
  );
  if (keep) {
    stdout.writeln('the generated files are in ${temp.path}');
  } else {
    temp.deleteSync(recursive: true);
  }
  if (reported.isNotEmpty) {
    exitCode = 1;
  }
}
