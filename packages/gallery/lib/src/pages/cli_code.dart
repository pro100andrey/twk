// The Code tab of App › Cli: the programs of lib/cli/, as they are there
// (test/pages/cli_test.dart holds each to its file). Kept apart from
// them, which import twk_cli, so that the page builds in a browser too.

/// The source of each program of lib/cli/, by its name.
const cliCode = <String, String>{
  'create': r'''
// Asks what a new app is to be: its name, a template, its features and a
// last yes or no. At a terminal each question is a widget until it is
// answered, then a line: `✔ Template? server`.
import 'package:twk/twk.dart';
import 'package:twk_cli/twk_cli.dart';

Future<void> main(List<String> args) => Cli.runWithArgs(args, create);

Future<void> create(Cli cli, List<String> rest) async {
  final name = await cli.prompt(
    'Project name?',
    defaultValue: 'my_app',
    validate: (name) => RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)
        ? null
        : 'lowercase letters, digits and _',
  );
  final template = await cli.chooseOne(
    'Template?',
    choices: ['console', 'package', 'server', 'web'],
  );
  final features = await cli.chooseAny(
    'Features?',
    choices: ['Linter', 'Docker', 'Tests', 'CI'],
    defaultValues: ['Linter'],
  );
  if (!await cli.confirm('Create $name?')) {
    cli.info('Nothing created.');
    return;
  }
  cli.success([
    'Created '.bold,
    name,
    ' from ',
    template.italic,
    ' with ${features.join(', ')}',
  ]);
}
''',
  'install': r'''
// Resolves, then downloads and compiles at once: a spinner while one thing
// is done, then a task list with bars, rates and the time left, where the
// terminal redraws; lines logged meanwhile land above them.
import 'dart:async';

import 'package:twk/twk.dart';
import 'package:twk_cli/twk_cli.dart';

Future<void> main(List<String> args) => Cli.runWithArgs(args, install);

Future<void> install(Cli cli, List<String> rest) async {
  final resolving = cli.progress('Resolving');
  for (var i = 1; i <= 4; i++) {
    await _wait(150);
    resolving.update('Resolving ($i of 4)');
  }
  resolving.complete('Resolved 4 packages');

  await cli.tasks(
    (tracker) => Future.wait([
      tracker.run(
        'assets.zip',
        (task) => _download(task, 2400000, 30),
        total: 2400000,
        unit: ProgressUnit.bytes,
      ),
      tracker.run(
        'fonts.tar',
        (task) => _download(task, 900000, 15),
        total: 900000,
        unit: ProgressUnit.bytes,
      ),
      tracker.run('Compiling', (task) async {
        await _wait(1200);
        cli.info('compiled 118 libraries');
        await _wait(600);
      }),
    ]),
  );
  cli.success('Installed in build/app.');
}

/// [size] bytes in [steps], one each 60 ms.
Future<void> _download(ProgressTask task, int size, int steps) async {
  for (var i = 0; i < steps; i++) {
    await _wait(60);
    task.advance(size ~/ steps);
  }
}

Future<void> _wait(int ms) => Future.delayed(Duration(milliseconds: ms));
''',
  'check': r'''
// Reads a config and fails on it: inspect() shows what was read, and the
// error Cli.run catches ends the run with its traceback, the line it was
// thrown at highlighted as Dart (twk_rich's dartSourceLines), and exit
// code 1.
import 'dart:convert';

import 'package:twk_cli/twk_cli.dart';
import 'package:twk_rich/twk_rich.dart' show dartSourceLines;

Future<void> main(List<String> args) =>
    Cli.runWithArgs(args, check, sourceLines: dartSourceLines);

const _text = '{"version": 2, "target": "web"}';

Future<void> check(Cli cli, List<String> rest) async {
  final map = await cli.progress('Reading twk.yaml').run(() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return jsonDecode(_text) as Map<String, Object?>;
  }, done: (_) => 'Read twk.yaml');
  await cli.inspect(map, label: 'config');
  cli.success('Deploying ${_name(map)}.');
}

String _name(Map<String, Object?> map) {
  if (map['name'] case final String name) {
    return name;
  }
  throw StateError('no "name" set');
}
''',
};
