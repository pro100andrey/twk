// TWK_LOG and the real stdout and stderr: the app of log_app.dart in a
// process of its own, its error left unhandled.
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show compiledProgram, runProcess;

import '../support/environment.dart';

void main() {
  late String app;
  setUpAll(
    () async => app = await compiledProgram(
      'test/log/log_app.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    ),
  );

  test('TWK_LOG gets every record, stdout nothing, stderr the warnings '
      'after the restore', () async {
    final dir = Directory.systemTemp.createTempSync('twk_log');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/app.log';
    final res = await runProcess(
      Platform.resolvedExecutable,
      [app],
      environment: childEnvironment({'TWK_LOG': path}),
      includeParentEnvironment: false,
    );
    expect(res.stdout, '');
    expect((res.stderr as String).split('\n').take(4), [
      'restored',
      matches(r'^\S+ warning slow$'),
      'Unhandled exception:',
      'Bad state: fatal',
    ]);
    expect(res.exitCode, 255);
    expect(File(path).readAsLinesSync().take(3), [
      matches(r'^\S+ info in a handler$'),
      matches(r'^\S+ warning slow$'),
      matches(r'^\S+ error uncaught error: Bad state: fatal$'),
    ]);
  });
}
