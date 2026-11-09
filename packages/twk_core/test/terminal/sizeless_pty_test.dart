// The process's own terminal on a pseudo-terminal of no size, as `script`
// opens one with no terminal around it (a background job, CI): a terminal
// all the same, as wide and tall as COLUMNS and LINES say, else 80 × 24,
// in a process of its own; and on /dev/null, a character device that is
// no terminal, none. A stdout put in by IOOverrides that says it is no
// terminal is none, whatever the process's own is.
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

import 'package:twk_core/src/platform/io.dart';

/// A stdout that says it is no terminal, and does nothing else.
final class _None implements Stdout {
  @override
  bool get hasTerminal => false;

  @override
  Object? noSuchMethod(Invocation invocation) => null;
}

void main() {
  final link = ownTerminalLink();
  final none = _None();
  final put = IOOverrides.runZoned(stdioIsTerminal, stdout: () => none);
  stderr.writeln(
    jsonEncode([
      stdioIsTerminal(),
      link != null,
      link?.columns,
      link?.lines,
      put,
    ]),
  );
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
    return said('${result.stdout}');
  }

  test(
    "a pseudo-terminal of no size is the process's own terminal, 80 × 24, "
    'or as COLUMNS and LINES say',
    () async {
      expect(await run(const {}), [true, true, 80, 24, false]);
      expect(
        await run(const {'COLUMNS': '120', 'LINES': '40'}),
        [true, true, 120, 40, false],
      );
    },
    skip: script.isEmpty ? 'no script(1) here' : false,
  );

  test(
    'stdin and stdout on /dev/null, a character device, are no terminal',
    () async {
      final result = await runProcess('/bin/sh', [
        '-c',
        r'exec "$0" "$1" </dev/null >/dev/null',
        Platform.resolvedExecutable,
        kernel,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(said('${result.stderr}'), [false, false, null, null, false]);
    },
  );
}
