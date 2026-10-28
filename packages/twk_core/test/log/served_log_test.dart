// An app's log served for `twk logs` while it runs when TWK_DEBUG names
// `logs`: served_app.dart in a process of its own, in a project of the
// test's.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart'
    show compiledProgram, startProcess, waitFor, waitUntil;

import '../support/environment.dart';
import 'log_server_test.dart' show Client;

/// served_app.dart running in a project of the test's ([start]).
final class ServedApp {
  ServedApp._(this._process) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line == 'running' && !_running.isCompleted) {
            _running.complete();
          }
        });
    _stderr = _process.stderr.transform(utf8.decoder).join();
  }

  /// Starts the app, compiled to [kernel], in [project] with `TWK_DEBUG`
  /// set to [debug]; completes once its first frame ran.
  static Future<ServedApp> start(
    String kernel,
    String project,
    String debug,
  ) async {
    final app = ServedApp._(
      await startProcess(
        Platform.resolvedExecutable,
        [kernel],
        workingDirectory: project,
        environment: childEnvironment({'TWK_DEBUG': debug}),
        includeParentEnvironment: false,
      ),
    );
    await waitFor(app._running.future, 'served_app.dart to run');
    return app;
  }

  final Process _process;
  final _running = Completer<void>();
  late final Future<String> _stderr;

  /// Ends the app: its exit code and what it wrote to stderr.
  Future<(int, String)> quit() async {
    await _process.stdin.close();
    return (await waitFor(_process.exitCode, 'its exit'), await _stderr);
  }
}

/// The address in [file] once an app wrote it there.
Future<LocalAddress> served(String file) async {
  LocalAddress? address;
  await waitUntil(
    () => (address = LocalAddress.read(file)) != null,
    'the address in $file',
  );
  return address!;
}

void main() {
  late String kernel;
  setUpAll(
    () async => kernel = await compiledProgram(
      'test/log/served_app.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    ),
  );

  late String project;
  late String file;
  setUp(() {
    project = Directory.systemTemp.createTempSync('twk_served').path;
    File('$project/pubspec.yaml').writeAsStringSync('name: app\n');
    file = LocalAddress.fileOf('logs', project);
  });
  tearDown(() => Directory(project).deleteSync(recursive: true));

  test('TWK_DEBUG=logs: the log is served while run() runs', () async {
    final app = await ServedApp.start(kernel, project, 'logs');
    final address = await served(file);
    final client = await Client.connect(address);
    await client.waitFor('first frame');

    expect(await app.quit(), (0, ''));
    await client.closed;
    expect(File(file).existsSync(), isFalse);
  });

  test('without it nothing is served', () async {
    final app = await ServedApp.start(kernel, project, 'frames');
    expect((await app.quit()).$1, 0);
    expect(
      Directory('$project/.dart_tool').existsSync(),
      isFalse,
      reason: 'serving makes the directory of the address files',
    );
  });

  test('a log that cannot be served is a warning, written after the '
      'restore; the app runs on', () async {
    File('$project/.dart_tool').writeAsStringSync('not a directory');
    final app = await ServedApp.start(kernel, project, 'logs');
    final (code, stderr) = await app.quit();
    expect(code, 0);
    expect(
      stderr,
      matches(r'^\S+ warning the log is not served for twk logs: '),
    );
  });
}
