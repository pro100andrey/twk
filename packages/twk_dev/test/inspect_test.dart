// `twk inspect`'s side of a running app: an app of a package made for the
// test, run by `twk run`, which says where its VM service is; the
// inspector finds it there, connects, reads the tree, selects a node at a
// cell and by a click the app picks, outlines it, and finds the app again
// once `twk run` has restarted it; `twk run` leaving the file alone
// when another one wrote it since; `twk inspect` in a terminal of the
// test's (see terminal.dart) showing the tree of an app at its address;
// and `twk inspect` without one closing the connection it opened.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk_dev/src/app_client.dart';
import 'package:twk_dev/src/inspect.dart';
import 'package:twk_dev/src/run.dart';
import 'package:twk_test/twk_test.dart'
    show runProcess, startProcess, waitUntil;
import 'package:vm_service/utils.dart';

import 'terminal.dart';
import 'twk.dart';

/// How long an app is given to start, here and in the tests' other waits
/// for it: `twk run` runs it from source.
const _start = Duration(seconds: 60);

/// Waits until [said], what an app wrote, has [line], failing with all of
/// it after [_start].
Future<void> _says(StringBuffer said, String line) async {
  try {
    await waitUntil(
      () => '$said'.contains(line),
      'the app to say "$line"',
      timeout: _start,
    );
  } on TestFailure catch (e) {
    fail('${e.message}; it said: $said');
  }
}

/// The nodes of the tree [node] is the root of, root first.
List<Json> nodesOf(Json node) => [
  node,
  for (final child in node['children']! as List<Object?>)
    ...nodesOf(child! as Json),
];

/// A package made for a test, in a temporary directory: the app
/// (inspected_app.dart) in `bin/main.dart`.
Future<Directory> _package() async {
  final dir = await Directory.systemTemp.createTemp('twk_inspect_test');
  addTearDown(() => dir.delete(recursive: true));
  final twk = p.normalize(p.join(await packageDirectory(), '..', 'twk'));
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: inspected_app
environment:
  sdk: ^3.13.5
dependencies:
  twk:
    path: $twk
dependency_overrides:
  twk_core:
    path: $twk/../twk_core
''');
  File(p.join(dir.path, 'bin', 'main.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(
      File(p.join(await packageDirectory(), 'test', 'inspected_app.dart'))
          .readAsStringSync(),
    );
  final got = await runProcess(
    Platform.resolvedExecutable,
    [
      'pub',
      'get',
      '--offline',
    ],
    workingDirectory: dir.path,
    group: true,
  );
  expect(got.exitCode, 0, reason: '${got.stdout}${got.stderr}');
  return dir;
}

/// `twk run` of the app of [dir], started there, as a developer starts it.
Future<Process> _twkRun(Directory dir) async {
  final run = await startProcess(
    Platform.resolvedExecutable,
    [
      twkProgram,
      'run',
      'bin/main.dart',
    ],
    workingDirectory: dir.path,
    group: true,
  );
  return run;
}

void main() {
  // the twk command, and the app where twk run does not run it, compiled
  // once
  late String inspected;
  setUpAll(() async {
    await compileTwk();
    inspected = await compiled('test/inspected_app.dart');
  });

  test('twk inspect finds the app twk run runs by its service file, reads '
      'its tree, selects the node at a cell and the one a click picks, '
      'outlines it, and finds the app again once restarted', () async {
    final dir = await _package();

    // looking for it before it runs
    final serviceFile = serviceFileOf(dir.path);
    final running = RunningApps(serviceFile);
    addTearDown(running.stop);
    final apps = StreamIterator(running.apps);
    Future<AppClient> next() async {
      expect(
        await apps.moveNext().timeout(_start),
        isTrue,
      );
      return apps.current;
    }

    final run = await _twkRun(dir);
    final said = StringBuffer();
    run.stdout.transform(utf8.decoder).listen(said.write);
    run.stderr.transform(utf8.decoder).listen(said.write);

    var app = await next();
    expect(app.name, File(serviceFile).readAsStringSync().trim());
    expect(app.name, startsWith('ws://127.0.0.1:'));
    await _says(said, 'running');

    final tree = await app.call('tree');
    final text = nodesOf(tree['root']! as Json).firstWhere(
      (n) => n['name'] == 'Text',
    );
    expect(text['properties'], [
      {'value': '"inspected"'},
    ]);
    final at = await app.call('select', {'x': '4', 'y': '1'});
    expect(at['id'], text['id']);
    expect(at['path'], contains(tree['app']));

    // a click on the app's screen, which the app picks
    final armed = await app.call('flags', {'select': 'true'});
    expect(armed['select'], isTrue);
    final picked = app.picks.first;
    run.stdin.add(utf8.encode('\x1b[<0;6;2M\x1b[<0;6;2m'));
    expect(await picked.timeout(const Duration(seconds: 10)), (5, 1));
    final there = await app.call('select', {'x': '5', 'y': '1'});
    expect(there['id'], text['id']);
    final shown = await app.call('highlight', {'id': '${text['id']}'});
    expect(shown['id'], text['id']);
    expect(shown['render'], text['render']);
    await expectLater(
      app.call('properties', {'id': '999999'}),
      throwsA(
        isA<AppError>().having(
          (e) => e.message,
          'message',
          'no node 999999 '
              'in the app',
        ),
      ),
    );

    // Ctrl+G H: twk run starts the app again, which is found again
    final gone = app.done;
    run.stdin.add(utf8.encode('\x07H'));
    await gone.timeout(const Duration(seconds: 30));
    app = await next();
    // its binding runs before its first frame, which mounts the tree
    late Json again;
    await waitUntil(
      () async => (again = await app.call('tree'))['root'] != null,
      'the tree of the app started again to be mounted',
      timeout: _start,
    );
    expect(
      nodesOf(again['root']! as Json).map((n) => n['name']),
      contains('Text'),
    );

    run.kill();
    expect(await run.exitCode, 143, reason: '$said');
    expect(File(serviceFile).existsSync(), isFalse);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('twk run leaves the service file another twk run wrote since', () async {
    final dir = await _package();
    final file = File(serviceFileOf(dir.path));
    final run = await _twkRun(dir);
    await waitUntil(file.existsSync, 'the service file', timeout: _start);
    expect(file.readAsStringSync(), startsWith('ws://127.0.0.1:'));
    file.writeAsStringSync('ws://127.0.0.1:1/other=/ws\n');
    run.kill();
    expect(await run.exitCode, 143);
    expect(file.readAsStringSync(), 'ws://127.0.0.1:1/other=/ws\n');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('twk inspect in a terminal shows the widget tree of the app at an '
      'address given, or that twk run runs from the project, says when it '
      'has gone, and quits on q with 0', () async {
    // the project twk inspect -C looks in: a directory, no app of its own;
    // under /tmp on macOS, whose own temporary directory is so long that
    // the line naming it is cut at the screen's width
    final dir =
        await (Platform.isMacOS ? Directory('/tmp') : Directory.systemTemp)
            .createTemp('twk_inspect_test');
    addTearDown(() => dir.delete(recursive: true));
    final info = File(p.join(dir.path, 'service.json'));
    final app = await startProcess(Platform.resolvedExecutable, [
      '--enable-vm-service=0',
      '--no-serve-devtools',
      '-DSILENT_VM_SERVICE=true',
      '--write-service-info=${info.uri}',
      inspected,
    ], workingDirectory: dir.path);
    final said = StringBuffer();
    app.stdout.transform(utf8.decoder).listen(said.write);
    app.stderr.transform(utf8.decoder).listen(said.write);
    await _says(said, 'running');
    // the VM service may say where it listens after the app ran
    await waitUntil(
      () => info.existsSync() && info.readAsStringSync().endsWith('}'),
      'the VM service to write where it listens',
      timeout: _start,
    );
    final json = jsonDecode(info.readAsStringSync()) as Json;
    final uri = Uri.parse(json['uri']! as String);
    final address = '${convertToWebSocketUrl(serviceProtocolUrl: uri)}';
    // where twk run would say it is
    File(serviceFileOf(dir.path))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('$address\n');

    final [byAddress, byProject] = await Future.wait([
      Terminal.twk(['inspect', address], width: 120),
      Terminal.twk(['inspect', '-C', dir.path], width: 120),
    ]);
    for (final t in [byAddress, byProject]) {
      await t.until(
        () => t.lines.any((l) => l.contains('└── Text "inspected"')),
        'the tree',
      );
    }
    expect(byAddress.lines, contains(contains('inspecting $address')));

    app.kill();
    await byAddress.shows('the app has gone; q quits');
    await byProject.shows(
      'the app has gone; waiting for an app that twk run runs in ${dir.path}',
    );
    for (final t in [byAddress, byProject]) {
      t.type('q');
      expect(await t.ended(), exits(0));
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('twk inspect at an address, connected but without a terminal, '
      'closes the connection before it exits with 1', () async {
    // a VM service that takes connections and answers nothing: what the
    // inspector asks while it waits for the app stays unanswered
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final connected = Completer<WebSocket>();
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      if (connected.isCompleted) {
        await socket.close();
      } else {
        connected.complete(socket);
      }
    });

    final result = await twkHere([
      'inspect',
      'ws://127.0.0.1:${server.port}/ws',
    ]);
    expect(result.exitCode, 1);
    expect(result.stderr, 'twk inspect: not a terminal\n');
    final socket = await connected.future.timeout(const Duration(seconds: 10));
    addTearDown(socket.close);
    // the other end closes it; until then it would be open for good
    await socket.drain<void>().timeout(
      const Duration(seconds: 10),
      onTimeout: () => fail('twk inspect left the VM service connected'),
    );
  });

  test('the address twk run publishes for twk inspect is the WebSocket one '
      'of the address the VM prints, with or without its last /', () {
    // what HotRunner and VmAppClient.connect both make of it
    String ws(String uri) =>
        '${convertToWebSocketUrl(serviceProtocolUrl: Uri.parse(uri))}';
    expect(ws('http://127.0.0.1:8181/abc=/'), 'ws://127.0.0.1:8181/abc=/ws');
    expect(ws('http://127.0.0.1:8181/abc='), 'ws://127.0.0.1:8181/abc=/ws');
    expect(ws('https://host:1/abc='), 'wss://host:1/abc=/ws');
    expect(ws('ws://127.0.0.1:8181/abc=/ws'), 'ws://127.0.0.1:8181/abc=/ws');
  });
}
