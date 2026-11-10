// The scripts of `twk completion` in the shells themselves: they parse, and
// bash's completes a subcommand, an option, and the files a command takes.
@Tags(['process'])
@TestOn('linux || mac-os')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk_dev/src/cli.dart';
import 'package:twk_dev/src/completion.dart';

Future<bool> _has(String shell) async {
  try {
    return (await Process.run(shell, ['-c', 'true'])).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  late Directory dir;
  final runner = twkRunner();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('twk_completion');
    for (final f in ['a.cast', 'b.txt', 'c.tape', 'd.dart']) {
      File(p.join(dir.path, f)).writeAsStringSync('');
    }
    Directory(p.join(dir.path, 'sub')).createSync();
  });
  tearDown(() => dir.delete(recursive: true));

  Future<String> script(CompletionShell shell) async {
    final file = File(p.join(dir.path, '.twk.${shell.name}'))
      ..writeAsStringSync(completionScript(runner, shell));
    return file.path;
  }

  test('bash parses it', () async {
    if (!await _has('bash')) {
      markTestSkipped('no bash');
      return;
    }
    final result = await Process.run('bash', [
      '-n',
      await script(CompletionShell.bash),
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  test('zsh parses it', () async {
    if (!await _has('zsh')) {
      markTestSkipped('no zsh');
      return;
    }
    final result = await Process.run('zsh', [
      '-n',
      await script(CompletionShell.zsh),
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  test('fish parses it', () async {
    if (!await _has('fish')) {
      markTestSkipped('no fish');
      return;
    }
    final result = await Process.run('fish', [
      '--no-execute',
      await script(CompletionShell.fish),
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  group('bash completes', () {
    Future<List<String>> complete(List<String> words) async {
      final file = await script(CompletionShell.bash);
      final quoted = words.map((w) => "'$w'").join(' ');
      final command =
          'source "$file"; COMP_WORDS=($quoted); '
          r'COMP_CWORD=$((${#COMP_WORDS[@]} - 1)); _twk; '
          r'printf "%s\n" "${COMPREPLY[@]}"';
      final result = await Process.run('bash', [
        '-c',
        command,
      ], workingDirectory: dir.path);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return (result.stdout as String)
          .split('\n')
          .where((l) => l.isNotEmpty)
          .toList();
    }

    setUp(() async {
      if (!await _has('bash')) {
        markTestSkipped('no bash');
      }
    });

    test('a subcommand', () async {
      expect(await complete(['twk', 'pl']), ['play']);
    });

    test('an option, with the --no- form of a flag', () async {
      expect(await complete(['twk', 'run', '--no-']), [
        '--no-asserts',
        '--no-watch-deps',
      ]);
    });

    test('the values of an option', () async {
      expect(await complete(['twk', 'create', '-t', 'da']), ['dashboard']);
    });

    test('the recordings for play, the tapes for tape, the programs for '
        'run', () async {
      expect(await complete(['twk', 'play', '']), ['a.cast', 'sub']);
      expect(await complete(['twk', 'tape', '']), ['c.tape', 'sub']);
      expect(await complete(['twk', 'run', '']), ['d.dart', 'sub']);
    });
  });
}
