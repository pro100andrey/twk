// `twk create`: each template written into a new directory makes a
// package that gets its dependencies, analyzes with no issue, passes its
// tests and is formatted; the name, the checkout and the directory as the
// options and the arguments say, and refused when they are wrong. The
// command runs in this process (`twkHere`).
import 'dart:convert';
import 'dart:io';

import 'package:mold/mold.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk_dev/src/create.dart';
import 'package:twk_dev/src/templates/templates.dart';
import 'package:twk_dev/twk_dev.dart';
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

void main() {
  test('--list names each template with what it is', () async {
    final result = await twkHere(['create', '--list']);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, '''
app        full screen: a list beside a detail pane, the keys below
inline     inline below the prompt: what is said goes to the scrollback
form       full screen: a form whose fields are validated
dashboard  full screen: panels of live readings in a chart, a gauge and bars
''');
  });

  for (final template in templates) {
    test(
      'the ${template.name} template makes a package that gets its '
      'dependencies, analyzes with no issue, passes its tests and is '
      'formatted',
      () async {
        final dir = p.join(await temporary(), '${template.name}_app');
        final created = await twkHere([
          'create',
          dir,
          '--template=${template.name}',
          '--path-to-twk=${await repository()}',
        ]);
        expect(created.exitCode, 0, reason: '${created.stderr}');
        final name = '${template.name}_app';
        expect(filesIn(dir), [
          '.gitignore',
          'README.md',
          'analysis_options.yaml',
          'bin/main.dart',
          'lib/$name.dart',
          'pubspec.yaml',
          'test/${name}_test.dart',
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
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }

  test('by default the app template, the package named after the '
      'directory, twk taken by path from the checkout the command runs '
      'from', () async {
    final dir = p.join(await temporary(), 'My-App 2');
    final result = await twkHere(['create', dir]);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      result.stdout,
      startsWith(
        'twk create: my_app_2, of the template '
        'app, in $dir:\n',
      ),
    );
    final pubspec = File(p.join(dir, 'pubspec.yaml')).readAsStringSync();
    expect(pubspec, startsWith('name: my_app_2\n'));
    final packages = p.join(await repository(), 'packages');
    for (final package in twkPackages) {
      expect(pubspec, contains('  $package:\n    path: $packages/$package\n'));
    }
    expect(
      File(p.join(dir, 'lib', 'my_app_2.dart')).readAsStringSync(),
      contains("const appName = 'my_app_2';"),
    );
    expect(
      File(p.join(dir, 'bin', 'main.dart')).readAsStringSync(),
      startsWith("import 'package:my_app_2/my_app_2.dart';\n"),
    );
  });

  test('without a checkout the packages come from pub at the version of '
      'twk; a path YAML would read otherwise is quoted', () async {
    final twkPubspec = File(
      p.join(await repository(), 'packages', 'twk', 'pubspec.yaml'),
    ).readAsStringSync();
    expect(twkPubspec, contains('\nversion: $twkVersion\n'));
    final template = File(
      p.join(await packageDirectory(), 'templates', 'app', 'pubspec.yaml'),
    ).readAsStringSync();

    final fromPub = withTwkFrom(template);
    expect(fromPub, contains('\n  twk: ^$twkVersion\n'));
    expect(fromPub, contains('\n  twk_dev: ^$twkVersion\n'));
    expect(fromPub, contains('\n  twk_lints: ^$twkVersion\n'));
    expect(fromPub, contains('\n  twk_test: ^$twkVersion\n'));
    expect(fromPub, isNot(contains('dependency_overrides')));

    final quoted = withTwkFrom(template, checkout: "/home/ann/it's: here");
    expect(
      quoted,
      contains("\n  twk:\n    path: '/home/ann/it''s: here/packages/twk'\n"),
    );
    expect(
      quoted,
      endsWith(
        '\ndependency_overrides:\n'
        "  twk:\n    path: '/home/ann/it''s: here/packages/twk'\n"
        "  twk_core:\n    path: '/home/ann/it''s: here/packages/twk_core'\n",
      ),
    );
  });

  test('--dry-run names the files the template would write and writes '
      'none', () async {
    final dir = p.join(await temporary(), 'planned');
    final result = await twkHere(['create', dir, '-t', 'inline', '--dry-run']);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      result.stdout,
      startsWith(
        'twk create --dry-run: would write planned, of the template '
        'inline, in $dir:\n'
        '  .gitignore\n'
        '  README.md\n'
        '  analysis_options.yaml\n'
        '  bin/main.dart\n'
        '  lib/planned.dart\n'
        '  pubspec.yaml\n'
        '  test/planned_test.dart\n',
      ),
    );
    expect(Directory(dir).existsSync(), isFalse);
  });

  test('a directory that is not empty is refused with 1, written into with '
      '--force, the files there of other paths kept', () async {
    final dir = await temporary();
    File(p.join(dir, 'notes.txt')).writeAsStringSync('mine');
    File(p.join(dir, 'pubspec.yaml')).writeAsStringSync('name: old\n');

    final refused = await twkHere(['create', dir, '--name=kept']);
    expect(refused.exitCode, 1);
    expect(
      refused.stderr,
      'twk create: Target already exists and is not empty: $dir; only an '
      'overwrite unpack writes into one. --force writes into it.\n',
    );
    expect(filesIn(dir), ['notes.txt', 'pubspec.yaml']);

    final forced = await twkHere(['create', dir, '--name=kept', '--force']);
    expect(forced.exitCode, 0, reason: '${forced.stderr}');
    expect(File(p.join(dir, 'notes.txt')).readAsStringSync(), 'mine');
    expect(
      File(p.join(dir, 'pubspec.yaml')).readAsStringSync(),
      startsWith('name: kept\n'),
    );
    expect(filesIn(dir), contains('lib/kept.dart'));
    expect(
      forced.stdout,
      allOf(
        contains('  pubspec.yaml (over the one there)\n'),
        contains('  lib/kept.dart\n'),
      ),
    );
  });

  test('--force --dry-run names the files it would write over and writes '
      'none', () async {
    final dir = await temporary();
    File(p.join(dir, 'pubspec.yaml')).writeAsStringSync('name: old\n');

    final result = await twkHere([
      'create',
      dir,
      '-t',
      'inline',
      '--name=kept',
      '--force',
      '--dry-run',
    ]);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      result.stdout,
      startsWith(
        'twk create --dry-run: would write kept, of the template inline, '
        'in $dir:\n'
        '  .gitignore\n'
        '  README.md\n'
        '  analysis_options.yaml\n'
        '  bin/main.dart\n'
        '  lib/kept.dart\n'
        '  pubspec.yaml (over the one there)\n'
        '  test/kept_test.dart\n',
      ),
    );
    expect(filesIn(dir), ['pubspec.yaml']);
    expect(File(p.join(dir, 'pubspec.yaml')).readAsStringSync(), 'name: old\n');
  });

  test('--force over the package it made, as it made it, says each file is '
      'the same there and writes none of them', () async {
    final dir = p.join(await temporary(), 'again');
    final options = ['--path-to-twk=${await repository()}'];
    final made = await twkHere(['create', dir, ...options]);
    expect(made.exitCode, 0, reason: '${made.stderr}');
    final files = filesIn(dir);
    final old = DateTime(2000);
    for (final path in files) {
      File(p.join(dir, path)).setLastModifiedSync(old);
    }

    final again = await twkHere(['create', dir, '--force', ...options]);

    expect(again.exitCode, 0, reason: '${again.stderr}');
    for (final path in files) {
      expect(again.stdout, contains('  $path (the same there)\n'));
      expect(
        File(p.join(dir, path)).lastModifiedSync(),
        old,
        reason: '$path written again',
      );
    }
  });

  test('no directory, two, a name that is no package name and a template '
      'there is not exit with $usageExitCode; a path to twk that is no '
      'checkout with 1', () async {
    final none = await twkHere(['create']);
    expect(none.exitCode, usageExitCode);
    expect(none.stderr, contains('No directory to create the app in.'));

    final two = await twkHere(['create', 'a', 'b']);
    expect(two.exitCode, usageExitCode);
    expect(two.stderr, contains('One directory at most.'));

    final dir = await temporary();
    final digit = await twkHere(['create', p.join(dir, '2fast')]);
    expect(digit.exitCode, usageExitCode);
    expect(
      digit.stderr,
      contains(
        '"2fast" is not a package name: a lower case letter first, then '
        'lower case letters, digits and _; --name=<package> gives the '
        'package another',
      ),
    );

    for (final (name, error) in [
      ('class', '"class" is a reserved word'),
      ('inline', '"inline" is a reserved word'),
      ('twk', '"twk" is the name of a package the app depends on'),
      ('My_App', '"My_App" is not a package name'),
    ]) {
      final named = await twkHere(['create', p.join(dir, 'x'), '--name=$name']);
      expect(named.exitCode, usageExitCode, reason: name);
      expect(named.stderr, contains(error));
    }

    final unknown = await twkHere(['create', dir, '--template=game']);
    expect(unknown.exitCode, usageExitCode);
    expect(unknown.stderr, contains('"game" is not an allowed value'));

    final nowhere = await twkHere([
      'create',
      p.join(dir, 'app'),
      '--path-to-twk=$dir',
    ]);
    expect(nowhere.exitCode, 1);
    expect(
      nowhere.stderr,
      'twk create: no checkout of twk at $dir: it has no packages/twk, '
      'packages/twk_test, packages/twk_dev and packages/twk_lints\n',
    );

    expect(filesIn(dir), isEmpty);
  });

  test('a file in place of the directory, or on the way to it, is refused '
      'with 1 with --force too, and with no word of --force', () async {
    final dir = await temporary();
    final file = p.join(dir, 'file');
    File(file).writeAsStringSync('');
    final under = p.join(file, 'sub', 'app');

    for (final (target, error) in [
      (file, 'Target already exists and is a file, not a directory: $file'),
      (under, 'Cannot create target $under: $file is a file, not a directory.'),
    ]) {
      for (final options in [
        <String>[],
        ['--force'],
        ['--dry-run'],
        ['--force', '--dry-run'],
      ]) {
        final refused = await twkHere([
          'create',
          target,
          '--name=kept',
          ...options,
        ]);
        expect(refused.exitCode, 1, reason: '$target $options');
        expect(
          refused.stderr,
          'twk create: $error\n',
          reason: '$target $options',
        );
      }
    }
    expect(filesIn(dir), ['file']);
  });

  test('into a directory whose parents are not there, --dry-run checks the '
      'target and makes none of them; the run makes them', () async {
    final dir = await temporary();
    final nested = p.join(dir, 'a', 'b', 'nested');

    final planned = await twkHere([
      'create',
      nested,
      '-t',
      'inline',
      '--dry-run',
    ]);
    expect(planned.exitCode, 0, reason: '${planned.stderr}');
    expect(
      planned.stdout,
      startsWith(
        'twk create --dry-run: would write nested, of the template '
        'inline, in $nested:\n'
        '  .gitignore\n',
      ),
    );
    expect(Directory(p.join(dir, 'a')).existsSync(), isFalse);

    final made = await twkHere(['create', nested, '-t', 'inline']);
    expect(made.exitCode, 0, reason: '${made.stderr}');
    expect(filesIn(nested), contains('lib/nested.dart'));
  });

  test('the pubspec is rewritten in the plan: one there as the template has '
      'it is written over, one as twk create writes it is the same there', () {
    final template = templates.firstWhere((t) => t.name == 'inline');
    final dir = Directory.systemTemp.createTempSync('twk_create_test').path;
    addTearDown(() => Directory(dir).deleteSync(recursive: true));
    final pubspec = File(p.join(dir, 'pubspec.yaml'));
    PlannedFile planned() => createPlan(
      template,
      'fresh',
      dir: dir,
      checkout: '/twk',
      overwrite: true,
    ).files.singleWhere((file) => file.to == 'pubspec.yaml');

    // the template's pubspec as substitution makes it, the twk packages
    // still by the paths in the repository
    pubspec.writeAsBytesSync(
      const Unbundler()
          .plan(bytes: template.archive, vars: {packageNameVariable: 'fresh'})
          .files
          .singleWhere((file) => file.to == 'pubspec.yaml')
          .bytes,
    );
    final over = planned();
    expect(over.rewritten, isTrue);
    expect(over.overwrites, isTrue);
    expect(over.identicalToExisting, isFalse);
    expect(over.changed, isTrue);
    expect(
      utf8.decode(over.bytes),
      contains('\n  twk:\n    path: /twk/packages/twk\n'),
    );

    pubspec.writeAsBytesSync(over.bytes);
    final same = planned();
    expect(same.rewritten, isTrue);
    expect(same.identicalToExisting, isTrue);
  });

  test('a directory that cannot be written into is refused with 1, as mold '
      'says', () async {
    final dir = p.join(await temporary(), 'locked');
    Directory(dir).createSync();
    expect(Process.runSync('chmod', ['555', dir]).exitCode, 0);
    addTearDown(() => Process.runSync('chmod', ['755', dir]));
    // where a user writes into it all the same (root)
    try {
      File(p.join(dir, 'probe')).createSync();
      markTestSkipped('$dir can be written into');
      return;
    } on FileSystemException {
      // as it should be
    }

    final result = await twkHere(['create', dir, '--name=app']);
    expect(result.exitCode, 1);
    expect(
      result.stderr,
      allOf(startsWith('twk create: '), contains('No write permission')),
    );
    expect(Directory(dir).listSync(), isEmpty);
  }, testOn: 'linux || mac-os');
}
