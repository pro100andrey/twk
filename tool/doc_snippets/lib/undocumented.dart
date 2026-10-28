/// The public members without a doc comment, as the analyzer's
/// `public_member_api_docs` lint finds them, and the report of them.
library;

import 'dart:io';

import 'declarations.dart';
import 'packages.dart';

/// A public member without a doc comment.
final class Undocumented {
  /// The member [name]d, of [kind], on [line] of [file].
  const Undocumented(this.file, this.line, this.name, this.kind);

  /// Its file, relative to the repository's root.
  final String file;

  /// The line its name is on, from 1.
  final int line;

  /// Its name, qualified by its type's (`Box.child`).
  final String name;

  /// What it declares (`class`, `method`, `field`, ...).
  final String kind;
}

/// The lint's findings in each of [packages], by package name: each
/// package's `lib/` is copied to a directory of its own under [temp],
/// which resolves as the package does and enables the lint alone, and
/// analyzed there in one run.
Future<Map<String, List<Undocumented>>> findUndocumented(
  List<RepoPackage> packages,
  Directory temp,
) async {
  File(
    '${temp.path}/analysis_options.yaml',
  ).writeAsStringSync('linter:\n  rules:\n    - public_member_api_docs\n');
  final copies = <String, RepoPackage>{};
  for (final package in packages) {
    final lib = Directory('${package.path}/lib');
    if (!lib.existsSync()) {
      continue;
    }
    final dir = '${temp.path}/${package.name}';
    for (final file in package.libraryFiles()) {
      final to = File('$dir/${file.substring(package.path.length + 1)}');
      to.parent.createSync(recursive: true);
      File(file).copySync(to.path);
    }
    Directory('$dir/.dart_tool').createSync();
    File(
      '$dir/.dart_tool/package_config.json',
    ).writeAsStringSync(package.packageConfig(selfRoot: dir));
    File('$dir/pubspec.yaml').writeAsStringSync(
      'name: ${package.name}\n'
      'environment:\n  sdk: ^3.13.5\n',
    );
    copies[dir] = package;
  }

  final found = {for (final p in copies.values) p.name: <Undocumented>[]};
  final declarations = <String, List<Declaration>>{};
  for (final f in await analyzeJson(temp.path)) {
    if (f.code != 'public_member_api_docs') {
      continue;
    }
    final dir = copies.keys.firstWhere((d) => f.file.startsWith('$d/'));
    final package = copies[dir]!;
    final original = '${package.path}${f.file.substring(dir.length)}';
    final decls = declarations.putIfAbsent(
      original,
      () => declarationsOf(File(original).readAsStringSync()),
    );
    final decl = decls.where((d) => d.nameOffset == f.offset).firstOrNull;
    final name =
        decl?.name ??
        File(
          original,
        ).readAsStringSync().substring(f.offset, f.offset + f.length);
    found[package.name]!.add(
      Undocumented(
        package.relative(original),
        f.line,
        name,
        decl?.kind ?? 'member',
      ),
    );
  }
  for (final list in found.values) {
    list.sort(
      (a, b) => a.file == b.file
          ? a.line.compareTo(b.line)
          : a.file.compareTo(b.file),
    );
  }
  return found;
}

/// The report of [package]'s [members], as Markdown: how many, then each
/// file with its members.
String undocumentedReport(
  RepoPackage package,
  List<Undocumented> members,
  String revision,
) {
  final out = StringBuffer()
    ..writeln('# Undocumented public members: ${package.name}')
    ..writeln()
    ..writeln(
      'At $revision, by `dart run tool/xtask.dart undocumented`: the '
      "analyzer's `public_member_api_docs` over `${package.dir}/lib`. "
      'The standard they are written to is '
      '[doc/internals/quality/README.md](../README.md).',
    )
    ..writeln();
  if (members.isEmpty) {
    out.writeln('Every public member has a doc comment.');
    return out.toString();
  }
  final byFile = <String, List<Undocumented>>{};
  for (final m in members) {
    byFile.putIfAbsent(m.file, () => []).add(m);
  }
  out
    ..writeln(
      '**${members.length}** members in ${byFile.length} files '
      '(the files with the most first).',
    )
    ..writeln();
  final files = byFile.keys.toList()
    ..sort((a, b) {
      final by = byFile[b]!.length.compareTo(byFile[a]!.length);
      return by != 0 ? by : a.compareTo(b);
    });
  for (final file in files) {
    final list = byFile[file]!;
    out
      ..writeln('## `$file` (${list.length})')
      ..writeln();
    for (final m in list) {
      out.writeln('- `$file:${m.line}` ${m.kind} `${m.name}`');
    }
    out.writeln();
  }
  return out.toString();
}
