// A program on Cli.run in a project of its own, run as a process whose
// output is a pipe: what it throws, past an asynchronous gap too, or
// leaves uncaught, ends it with the traceback on stderr, the paths from
// its working directory, and the exit code; a prompt nobody can answer
// with its question alone.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show compiledProgram, runProcess;

const _config = '''
import 'dart:convert';

/* The configuration of the tool,
   read from JSON. */
class Config {
  Config(this.name);

  final String name;

  static Config load(String text) {
    final map = jsonDecode(text) as Map<String, Object?>;
    if (map['name'] == null) {
      throw StateError('the config has no "name"');
    }
    return Config(map['name']! as String);
  }

  static Future<Config> fetch(String text) async {
    await Future<void>.delayed(Duration.zero);
    return load(text);
  }
}
''';

const _tool = '''
import 'dart:async';
import 'dart:io';

import 'package:twk_cli/twk_cli.dart';

import '../lib/src/config.dart';

Future<void> main(List<String> args) => Cli.runWithArgs(
  args,
  (cli, rest) async {
    switch (rest.first) {
      case 'sync':
        Config.load('{}');
      case 'async':
        await Config.fetch('{}');
      case 'uncaught':
        unawaited(Config.fetch('{}'));
        await Completer<void>().future;
      case 'prompt':
        await cli.confirm('Proceed?');
      case 'ok':
        cli.info('fine');
    }
  },
  errorExitCode: int.parse(Platform.environment['CODE'] ?? '1'),
);
''';

/// A package configuration that names no package.
const _noPackages = '{"configVersion": 2, "packages": []}\n';

const _excerpt = '''
  lib/src/config.dart:13:7
    11 │     final map = jsonDecode(text) as Map<String, Object?>;
    12 │     if (map['name'] == null) {
  ▶ 13 │       throw StateError('the config has no "name"');
    14 │     }
    15 │     return Config(map['name']! as String);
''';

/// [text] in the file at [path], written only where it holds something
/// else, whole or not at all: a program left as it was is not compiled
/// again, and one compiled meanwhile by another run reads it whole.
void _keep(String path, String text) {
  final file = File(path);
  if (file.existsSync() && file.readAsStringSync() == text) {
    return;
  }
  file.parent.createSync(recursive: true);
  File('$path.$pid')
    ..writeAsStringSync(text)
    ..renameSync(path);
}

void main() {
  // the tool's project, in a directory of the package's that stays from
  // one run to the next, as its kernel does
  final dir = Directory('.dart_tool/twk_test/traceback_tool').absolute;
  late String kernel;

  setUpAll(() async {
    _keep('${dir.path}/lib/src/config.dart', _config);
    _keep('${dir.path}/bin/tool.dart', _tool);
    // the packages it runs with: none, as a tool's whose dependencies are
    // in its kernel, where the VM would find this package's beside the
    // kernel
    _keep('${dir.path}/.dart_tool/package_config.json', _noPackages);
    // compiled once against this package's dependencies, run many times
    kernel = await compiledProgram(
      '${dir.path}/bin/tool.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    );
  });

  Future<ProcessResult> run(List<String> args, {int? code}) => runProcess(
    Platform.resolvedExecutable,
    ['--packages=${dir.path}/.dart_tool/package_config.json', kernel, ...args],
    workingDirectory: dir.path,
    // nothing the environment says of colors or CI: the output is a pipe
    includeParentEnvironment: false,
    environment: {
      'PATH': Platform.environment['PATH'] ?? '',
      'HOME': Platform.environment['HOME'] ?? '',
      'CODE': ?code?.toString(),
    },
  );

  test('a thrown error: the traceback, plain, the paths from the working '
      'directory, the frames of the SDK and twk_cli folded; 1', () async {
    final result = await run(['sync']);
    expect(result.stdout, isEmpty);
    final err = '${result.stderr}';
    expect(
      err,
      startsWith(
        '✗ StateError: Bad state: the config has no "name"\n\n$_excerpt\n',
      ),
    );
    final frames = err.split('\n\n').last.trimRight().split('\n');
    expect(frames, [
      matches(r'^  lib/src/config\.dart:13:7 +Config\.load$'),
      matches(r'^  bin/tool\.dart:\d+:\d+ +main\.<fn>$'),
      matches(r'^  … \d+ frames of .*twk_cli'),
      matches(r'^  bin/tool\.dart:\d+:\d+ +main$'),
      ...[for (final _ in frames.skip(4)) startsWith('  … ')],
    ]);
    expect(err, isNot(contains('\x1B')));
    expect(result.exitCode, 1);
  });

  test('every frame under --verbose; errorExitCode', () async {
    final result = await run(['-v', 'sync'], code: 3);
    final err = '${result.stderr}';
    expect(
      err,
      startsWith('✗ StateError: Bad state: the config has no "name"'),
    );
    expect(err, isNot(contains('… ')));
    expect(err, contains(RegExp(r'\n  dart:async/[^\n]+ _rootRun')));
    expect(err, contains(RegExp(r'\n  package:twk_cli/src/cli\.dart:\d+')));
    expect(result.exitCode, 3);
  });

  test('thrown past an asynchronous gap: the frame of each function '
      'awaited', () async {
    final result = await run(['async']);
    final err = '${result.stderr}';
    expect(err, contains(_excerpt));
    expect(err.split('\n\n').last.trimRight().split('\n').take(3), [
      matches(r'^  lib/src/config\.dart:13:7 +Config\.load$'),
      matches(r'^  lib/src/config\.dart:20:12 +Config\.fetch$'),
      matches(r'^  bin/tool\.dart:\d+:\d+ +main\.<fn>$'),
    ]);
    expect(result.exitCode, 1);
  });

  test('an error nothing awaited ends the run as one thrown', () async {
    final result = await run(['uncaught']);
    expect(
      '${result.stderr}',
      startsWith(
        '✗ StateError: Bad state: the config has no "name"\n\n$_excerpt',
      ),
    );
    expect(result.exitCode, 1);
  });

  test(
    'a prompt nobody can answer: its question and why, no traceback',
    () async {
      final result = await run(['prompt']);
      expect(
        result.stderr,
        '✗ Proceed?  nobody can answer, and it has no default\n',
      );
      expect(result.exitCode, 1);
    },
  );

  test('a run that ends well: its output, 0', () async {
    final result = await run(['ok']);
    expect(result.stdout, 'fine\n');
    expect(result.stderr, isEmpty);
    expect(result.exitCode, 0);
  });
}
