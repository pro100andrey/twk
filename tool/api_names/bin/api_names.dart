// The public names of each published package, written to
// doc/internals/api/<package>.txt (one `library kind name` line each,
// sorted), and held to tool/api_names/banned_names.txt: a banned name with
// no exception, or an exception that matches nothing, fails.
//
//   dart run tool/api_names/bin/api_names.dart
//   dart run tool/xtask.dart api-names
//
// The files are written whatever the rules say; the xtask task fails where
// that changed a file, so that a name added, renamed or removed shows in
// the diff of a pull request.
import 'dart:io';

import 'package:twk_api_names/api_names.dart';

Future<void> main() async {
  final root = _findRoot();
  // the packages published to pub.dev: those whose pubspec does not say
  // `publish_to: none`
  final List<String> published;
  try {
    published = publishedPackages('$root/packages');
  } on FormatException catch (e) {
    stderr.writeln('api_names: ${e.message}');
    exitCode = 1;
    return;
  }
  final rules = Rules.parse(
    File('$root/tool/api_names/banned_names.txt').readAsStringSync(),
  );
  final out = Directory('$root/doc/internals/api')..createSync(recursive: true);
  final names = <String, List<ApiName>>{};
  final paths = [for (final p in published) '$root/packages/$p'];
  final found = await publicNamesOf(paths);
  for (final package in published) {
    final list = found['$root/packages/$package']!;
    names[package] = list;
    File('${out.path}/$package.txt').writeAsStringSync(renderNames(list));
    stdout.writeln('$package: ${list.length}');
  }
  final problems = checkRules(rules, names);
  for (final p in problems) {
    stderr.writeln('api_names: $p');
  }
  if (problems.isNotEmpty) {
    exitCode = 1;
  }
}

String _findRoot() {
  var dir = Directory.current.absolute;
  while (!File('${dir.path}/xtask.yaml').existsSync()) {
    final up = dir.parent;
    if (up.path == dir.path) {
      throw StateError('no xtask.yaml in the current directory or above it');
    }
    dir = up;
  }
  return dir.path;
}
