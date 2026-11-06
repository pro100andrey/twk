// What `twk create` makes of a template, the helpers of its tests. A cycle is
// a file's, `create_<template>_test.dart`, for the four to run at once, each in
// a directory of its own that stays the same from one run to the next
// ([stableDirectory]).
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show runProcess;

import 'twk.dart';

/// The checkout of the twk repository this package is in.
Future<String> repository() async =>
    p.normalize(p.join(await packageDirectory(), '..', '..'));

/// A new empty directory, deleted after the test.
Future<String> temporary() async {
  final dir = await Directory.systemTemp.createTemp('twk_create_test');
  addTearDown(() => dir.delete(recursive: true));
  return dir.path;
}

/// The directory [name] under this package's `.dart_tool`, empty, deleted after
/// the test: for a `dart analyze`, whose plugin is built for a path it has not
/// seen, 18 s against 2, and kept by that path though the directory goes.
Future<String> stableDirectory(String name) async {
  final dir = Directory(
    p.join(await packageDirectory(), '.dart_tool', 'twk_create', name),
  );
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }
  addTearDown(() => dir.delete(recursive: true));
  return dir.path;
}

/// Runs `dart` with [arguments] in [dir] and expects it to exit with 0.
Future<ProcessResult> dart(String dir, List<String> arguments) async {
  final result = await runProcess(
    Platform.resolvedExecutable,
    arguments,
    workingDirectory: dir,
    // dart test's own reporter, not GitHub's, whose output is read
    environment: {'GITHUB_ACTIONS': ''},
    group: true,
  );
  expect(
    result.exitCode,
    0,
    reason: 'dart ${arguments.join(' ')}:\n${result.stdout}${result.stderr}',
  );
  return result;
}

/// The paths of the files under [dir], sorted.
List<String> filesIn(String dir) => [
  for (final entity in Directory(dir).listSync(recursive: true))
    if (entity is File) p.relative(entity.path, from: dir),
]..sort();

/// Tests that the template [name] makes a package that gets its
/// dependencies, analyzes with no issue, passes its tests and is formatted.
void templateCycle(String name) {
  test(
    'the $name template makes a package that gets its dependencies, '
    'analyzes with no issue, passes its tests and is formatted',
    () async {
      final dir = await stableDirectory('${name}_app');
      final created = await twkHere([
        'create',
        dir,
        '--template=$name',
        '--path-to-twk=${await repository()}',
      ]);
      expect(created.exitCode, 0, reason: '${created.stderr}');
      final package = '${name}_app';
      expect(filesIn(dir), [
        '.gitignore',
        'README.md',
        'analysis_options.yaml',
        'bin/main.dart',
        'lib/$package.dart',
        'pubspec.yaml',
        'test/${package}_test.dart',
      ]);

      await dart(dir, ['pub', 'get', '--offline']);
      final analyzed = await dart(dir, ['analyze']);
      expect(analyzed.stdout, contains('No issues found!'));
      final tested = await dart(dir, ['test']);
      expect(tested.stdout, contains('All tests passed!'));
      await dart(dir, [
        'format',
        '--output=none',
        '--set-exit-if-changed',
        '.',
      ]);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
