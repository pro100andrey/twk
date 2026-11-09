// The process's own terminal on a pseudo-terminal of no size, as `script`
// opens one with no terminal around it (a background job, CI): a terminal
// all the same, as wide and tall as COLUMNS and LINES say, else 80 × 24,
// in a process of its own.
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

import 'package:twk_core/src/platform/io.dart';

void main() {
  final link = ownTerminalLink();
  print(jsonEncode([outputIsTerminal, link != null, link?.columns, link?.lines]));
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

  Future<List<Object?>> run(Map<String, String> environment) async {
    final result = await runProcess(
      script.first,
      ['-qfec', '${Platform.resolvedExecutable} $kernel', '/dev/null'],
      environment: {...Platform.environment}
        ..remove('COLUMNS')
        ..remove('LINES')
        ..addAll(environment),
      includeParentEnvironment: false,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final line = '${result.stdout}'
        .split(RegExp(r'\r?\n'))
        .lastWhere((l) => l.startsWith('['));
    return jsonDecode(line) as List<Object?>;
  }

  test(
    "a pseudo-terminal of no size is the process's own terminal, 80 × 24, "
    'or as COLUMNS and LINES say',
    () async {
      expect(await run(const {}), [true, true, 80, 24]);
      expect(
        await run(const {'COLUMNS': '120', 'LINES': '40'}),
        [true, true, 120, 40],
      );
    },
    skip: script.isEmpty ? 'no script(1) here' : false,
  );
}
