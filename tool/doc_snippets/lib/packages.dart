/// The packages of the repository and what the docs and coverage tools do
/// with each: find them, point a copy of one's package resolution somewhere
/// else, and run `dart analyze` over a directory for its diagnostics.
library;

import 'dart:convert';
import 'dart:io';

/// A package of the repository: one under `packages/` (the core,
/// `packages/twk_core`, among them), or a template `twk create` writes.
final class RepoPackage {
  /// The package named [name] in [dir], relative to the repository's
  /// [root] (`.` for the root's own).
  const RepoPackage(this.root, this.dir, this.name);

  /// The repository's root, absolute.
  final String root;

  /// The package's directory relative to [root]: `.` for the root's own.
  final String dir;

  /// The name its pubspec.yaml gives it.
  final String name;

  /// The package's directory, absolute.
  String get path => dir == '.' ? root : '$root/$dir';

  /// Whether it has a `test/` directory.
  bool get hasTests => Directory('$path/test').existsSync();

  /// [file], absolute, relative to [root].
  String relative(String file) =>
      file.startsWith('$root/') ? file.substring(root.length + 1) : file;

  /// The Dart files under its `lib/`, absolute and sorted.
  List<String> libraryFiles() {
    final lib = Directory('$path/lib');
    if (!lib.existsSync()) {
      return const [];
    }
    return [
      for (final e in lib.listSync(recursive: true, followLinks: false))
        if (e is File && e.path.endsWith('.dart')) e.path,
    ]..sort();
  }

  /// Its public libraries, the files directly in `lib/`, as `package:` URIs.
  List<String> publicLibraries() {
    final lib = Directory('$path/lib');
    if (!lib.existsSync()) {
      return const [];
    }
    return [
      for (final e in lib.listSync(followLinks: false))
        if (e is File && e.path.endsWith('.dart'))
          'package:$name/${e.uri.pathSegments.last}',
    ]..sort();
  }

  /// The `.dart_tool/package_config.json` its programs and tests resolve
  /// their imports with: its own (a template's), or for a member of the
  /// pub workspace the root's, the nearest from its directory up to the
  /// repository's [root]; null when it has none, before `dart pub get`.
  File? get packageConfigFile {
    for (var at = Directory(path); ; at = at.parent) {
      final file = File('${at.path}/.dart_tool/package_config.json');
      if (file.existsSync()) {
        return file;
      }
      if (at.path == root || at.parent.path == at.path) {
        return null;
      }
    }
  }

  /// Its package resolution with every root absolute, so that a copy
  /// written anywhere resolves as the original does; with [selfRoot], the
  /// package itself resolves to that directory instead.
  String packageConfig({String? selfRoot}) {
    final file = packageConfigFile;
    if (file == null) {
      throw StateError('$dir: no package_config.json; run dart pub get');
    }
    final config = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final packages = (config['packages']! as List<Object?>)
        .cast<Map<String, Object?>>();
    for (final p in packages) {
      final rootUri = file.uri.resolve(p['rootUri']! as String);
      p['rootUri'] = p['name'] == name && selfRoot != null
          ? Directory(selfRoot).uri.toString()
          : rootUri.toString();
    }
    return const JsonEncoder.withIndent('  ').convert(config);
  }

  @override
  String toString() => '$name ($dir)';
}

/// The repository's root: [from] (the current directory by default) or the
/// nearest directory above it holding `xtask.yaml`.
String findRoot([String? from]) {
  var dir = Directory(from ?? Directory.current.path).absolute;
  while (!File('${dir.path}/xtask.yaml').existsSync()) {
    final up = dir.parent;
    if (up.path == dir.path) {
      throw StateError('no xtask.yaml in ${from ?? '.'} or above it');
    }
    dir = up;
  }
  return dir.path;
}

/// Every package of the repository at [root]: those under `packages/`
/// (the core among them), and the templates under
/// `packages/twk_dev/templates/`, in that order, each group by name. The
/// root's own package, the pub workspace, is none of them: it has no
/// `lib/`.
List<RepoPackage> repoPackages(String root) {
  final found = <RepoPackage>[];
  for (final parent in ['packages', 'packages/twk_dev/templates']) {
    final dir = Directory('$root/$parent');
    if (!dir.existsSync()) {
      continue;
    }
    final dirs = [
      for (final e in dir.listSync(followLinks: false))
        if (e is Directory && File('${e.path}/pubspec.yaml').existsSync())
          e.path,
    ]..sort();
    for (final d in dirs) {
      found.add(RepoPackage(root, d.substring(root.length + 1), _nameOf(d)));
    }
  }
  return found;
}

/// A package name no package of the repository has.
final class UnknownPackage implements Exception {
  /// The [message] saying which names and what the packages are.
  const UnknownPackage(this.message);

  /// Which names no package has, and which packages there are.
  final String message;

  @override
  String toString() => message;
}

/// Those of [all] that [names] name, or all of them when it names none;
/// a name no package has throws [UnknownPackage], so that a typo can't
/// check nothing and pass.
List<RepoPackage> selectPackages(
  List<RepoPackage> all,
  Iterable<String> names,
) {
  final wanted = {for (final n in names) n.trim()}..remove('');
  if (wanted.isEmpty) {
    return all;
  }
  final known = {for (final p in all) p.name};
  final unknown = wanted.difference(known);
  if (unknown.isNotEmpty) {
    throw UnknownPackage(
      'no package ${(unknown.toList()..sort()).join(', ')} '
      '(there are ${(known.toList()..sort()).join(', ')})',
    );
  }
  return [
    for (final p in all)
      if (wanted.contains(p.name)) p,
  ];
}

String _nameOf(String dir) {
  final pubspec = File('$dir/pubspec.yaml').readAsLinesSync();
  for (final line in pubspec) {
    final m = RegExp(r'^name:\s*(\S+)').firstMatch(line);
    if (m != null) {
      return m[1]!;
    }
  }
  throw StateError('$dir/pubspec.yaml names no package');
}

/// One diagnostic of `dart analyze --format=json`.
final class Finding {
  /// A finding from its parts.
  const Finding({
    required this.file,
    required this.line,
    required this.column,
    required this.offset,
    required this.length,
    required this.severity,
    required this.code,
    required this.message,
  });

  /// The finding as the analyzer's JSON gives it.
  factory Finding.fromJson(Map<String, Object?> json) {
    final location = json['location']! as Map<String, Object?>;
    final range = location['range']! as Map<String, Object?>;
    final start = range['start']! as Map<String, Object?>;
    final end = range['end']! as Map<String, Object?>;
    final offset = start['offset']! as int;
    return Finding(
      file: location['file']! as String,
      line: start['line']! as int,
      column: start['column']! as int,
      offset: offset,
      length: (end['offset']! as int) - offset,
      severity: (json['severity']! as String).toLowerCase(),
      code: json['code']! as String,
      message: json['problemMessage']! as String,
    );
  }

  /// The file, absolute.
  final String file;

  /// Where in [file] it starts, from 1.
  final int line;

  /// The column on [line] it starts at, from 1.
  final int column;

  /// Where in [file] it starts, from 0.
  final int offset;

  /// How many characters it spans.
  final int length;

  /// `error`, `warning` or `info`.
  final String severity;

  /// The diagnostic's name, as `undefined_identifier`.
  final String code;

  /// What the analyzer says.
  final String message;
}

/// Runs `dart analyze --format=json` over [dir] and answers its findings;
/// throws when the analyzer did not answer with JSON.
Future<List<Finding>> analyzeJson(String dir) async {
  final result = await Process.run(Platform.resolvedExecutable, [
    'analyze',
    '--format=json',
    '--no-fatal-warnings',
    dir,
  ]);
  final out = result.stdout as String;
  final start = out.indexOf('{');
  if (start < 0) {
    if (result.exitCode == 0) {
      return const [];
    }
    throw StateError('dart analyze $dir: ${result.stderr}$out');
  }
  final json = jsonDecode(out.substring(start)) as Map<String, Object?>;
  return [
    for (final d in json['diagnostics']! as List<Object?>)
      Finding.fromJson(d! as Map<String, Object?>),
  ];
}

/// The commit the work tree at [root] is at, short, with `+` after it when
/// a file under [paths] (relative to [root]) differs from it; `unknown`
/// where git does not answer.
String revisionOf(String root, [List<String> paths = const []]) {
  final head = Process.runSync('git', [
    'rev-parse',
    '--short',
    'HEAD',
  ], workingDirectory: root);
  if (head.exitCode != 0) {
    return 'unknown';
  }
  final rev = (head.stdout as String).trim();
  final status = Process.runSync('git', [
    'status',
    '--porcelain',
    '--untracked-files=no',
    '--',
    ...paths,
  ], workingDirectory: root);
  return (status.stdout as String).trim().isEmpty ? rev : '$rev+';
}
