// The process's terminal (CliTerminal.system) where its stdout is a
// pipe: how wide it is by COLUMNS, as the core's plain output takes it,
// in a process of its own.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show compiledProgram, runProcess;

const _program = '''
import 'dart:convert';

import 'package:twk/cli.dart';

void main() {
  final widths = [
    for (final columns in [null, '120', '0', '-3', 'wide'])
      CliTerminal.system(
        environment: {'COLUMNS': ?columns},
      ).columns,
  ];
  print(jsonEncode(widths));
}
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
  late String kernel;

  setUpAll(() async {
    // in a directory of the package's that stays from one run to the
    // next, as its kernel does
    const program = '.dart_tool/twk_test/columns/columns.dart';
    _keep(program, _program);
    kernel = await compiledProgram(
      program,
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    );
  });

  test('on a pipe, COLUMNS where it is a positive number, else none', () async {
    final result = await runProcess(Platform.resolvedExecutable, [kernel]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(jsonDecode('${result.stdout}'), [null, 120, null, null, null]);
  });
}
