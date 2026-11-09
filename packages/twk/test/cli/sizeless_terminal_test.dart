// The process's terminal (CliTerminal.system) on a pseudo-terminal of no
// size, as `script` opens one with no terminal around it (a background job,
// CI): a terminal all the same, its width COLUMNS or none, in a process of
// its own; and on /dev/null, a character device that is no terminal, none.
@Tags(['process'])
@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show compiledProgram, runProcess;

const _program = '''
import 'dart:convert';
import 'dart:io';

import 'package:twk/cli.dart';

void main() {
  final plain = CliTerminal.system(environment: const {});
  final wide = CliTerminal.system(environment: const {'COLUMNS': '99'});
  stderr.writeln(jsonEncode([
    plain.capabilities.outputIsTerminal,
    plain.capabilities.ansi,
    plain.columns,
    wide.columns,
  ]));
}
''';

/// [text] in the file at [path], written only where it holds something
/// else, whole or not at all.
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
  late String kernel;
  final script = ['/usr/bin/script', '/bin/script'].where(
    (path) => File(path).existsSync(),
  );

  setUpAll(() async {
    const program = '.dart_tool/twk_test/sizeless/sizeless.dart';
    _keep(program, _program);
    kernel = await compiledProgram(
      program,
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    );
  });

  List<Object?> said(String output) => jsonDecode(
    output.split(RegExp(r'\r?\n')).lastWhere((l) => l.startsWith('[')),
  ) as List<Object?>;

  test(
    'a pseudo-terminal of no size is a terminal: ANSI on, its width '
    'COLUMNS where given, else none',
    () async {
      // dart:io reads ANSI support from the process's own TERM, which a
      // CI runner may not set
      final result = await runProcess(
        script.first,
        ['-qfec', '${Platform.resolvedExecutable} $kernel', '/dev/null'],
        environment: {'TERM': 'xterm-256color'},
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(said('${result.stdout}'), [true, true, null, 99]);
    },
    skip: script.isEmpty ? 'no script(1) here' : false,
  );

  test('stdout on /dev/null, a character device, is no terminal', () async {
    final result = await runProcess('/bin/sh', [
      '-c',
      r'exec "$0" "$1" </dev/null >/dev/null',
      Platform.resolvedExecutable,
      kernel,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(said('${result.stderr}'), [false, false, null, 99]);
  });
}
