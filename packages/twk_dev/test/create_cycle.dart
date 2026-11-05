// What `twk create` makes of a template, the helpers of its tests. A cycle is
// a file's, `create_<template>_test.dart`, for the four to run at once: most
// of one is a `dart analyze` building its plugin for a directory it has not
// seen, which a suite's tests would wait for one after the other.
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
      final dir = p.join(await temporary(), '${name}_app');
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
    // the four at once on a runner of four cores
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
