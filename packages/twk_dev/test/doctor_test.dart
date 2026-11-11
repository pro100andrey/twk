import 'dart:async';
// `twk doctor`: the terminal's probe, the versions of the lock, the files of
// `.dart_tool/twk` and the skill for agents, in one report, as text and as
// JSON. The terminal is the fake one of twk_test, the project a directory
// written for the test.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk/cli.dart' show CliTerminal;
import 'package:twk_core/twk_core.dart';
import 'package:twk_dev/src/agents.dart';
import 'package:twk_dev/src/doctor.dart';
import 'package:twk_test/cli.dart';
import 'package:twk_test/twk_test.dart' show waitFor;

String _lock(Map<String, String> versions) {
  final b = StringBuffer('packages:\n');
  for (final MapEntry(:key, :value) in versions.entries) {
    b.write('  $key:\n    source: hosted\n    version: "$value"\n');
  }
  return b.toString();
}

void main() {
  late Directory root;
  late String project;

  setUp(() {
    root = Directory.systemTemp.createTempSync('twk_doctor');
    project = p.normalize(root.absolute.path);
    File(p.join(project, 'pubspec.yaml')).writeAsStringSync(
      'name: demo\nenvironment:\n  sdk: ^3.13.5\ndependencies:\n'
      '  twk: ^0.3.0\n',
    );
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// `twk doctor` with [arguments] over [terminal]: its exit code and what
  /// it wrote.
  Future<(int, String)> doctor(
    List<String> arguments, {
    CliTerminal? terminal,
  }) async {
    final out = StringBuffer();
    final runner = CommandRunner<int>('twk', '')
      ..addCommand(
        DoctorCommand(
          terminal: () => terminal,
          environment: {'TERM': 'xterm-256color', 'HOME': '/home'},
          out: out,
        ),
      );
    final code = await runner.run(['doctor', '-C', project, ...arguments]);
    return (code ?? 0, out.toString());
  }

  test('reports the terminal as the probe found it', () async {
    final clock = FakeClock();
    final (code, out) = await doctor(
      [],
      terminal: FakeCliTerminal.interactive(fakeClock: clock),
    );
    expect(code, 0);
    expect(out, contains('TERM            xterm-256color'));
    expect(out, contains('colors          trueColor'));
    expect(out, contains('DEC 2026        '));
    expect(out, contains('kitty keyboard  '));
    expect(out, contains('graphics        none'));
    expect(out, contains('links (OSC 8)   yes'));
    expect(out, contains('answers         '));
    expect(out, contains(' in 0 ms'));
    expect(out, isNot(contains('HOME')));
  });

  test('closes the terminal it opened', () async {
    final terminal = FakeCliTerminal.interactive();
    await doctor([], terminal: terminal);
    expect(terminal.opened, 1);
    expect(terminal.backend!.closed, isTrue);
  });

  test('without a terminal reports the project only', () async {
    final (code, out) = await doctor([]);
    expect(code, 0);
    expect(out, contains('none: stdin and stdout are not a terminal'));
    expect(out, contains('Project  $project'));
    expect(out, contains('Dart            '));
  });

  test('the terminal is null in the JSON without one', () async {
    final (_, out) = await doctor(['--json']);
    final json = jsonDecode(out) as Map<String, Object?>;
    expect(json['terminal'], isNull);
    expect(json['project'], project);
    expect(json['dart'], isA<String>());
  });

  test('the terminal in the JSON', () async {
    final (_, out) = await doctor(
      ['--json'],
      terminal: FakeCliTerminal.interactive(),
    );
    final terminal =
        (jsonDecode(out) as Map<String, Object?>)['terminal']!
            as Map<String, Object?>;
    expect(terminal['colors'], 'trueColor');
    expect(terminal['probeMilliseconds'], 0);
    expect(terminal['version'], '');
  });

  test('the versions of the lock agree', () async {
    File(p.join(project, 'pubspec.lock')).writeAsStringSync(
      _lock({'twk': '0.3.0', 'twk_core': '0.3.0', 'twk_dev': '0.3.0'}),
    );
    final (code, out) = await doctor([]);
    expect(code, 0);
    expect(out, contains('twk_dev         0.3.0 (locked)'));
    expect(out, contains('twk_test        not found'));
    expect(out, contains('the versions agree'));
  });

  test('versions that differ fail with 1 and are named', () async {
    File(p.join(project, 'pubspec.lock')).writeAsStringSync(
      _lock({'twk': '0.3.0', 'twk_core': '0.3.0', 'twk_dev': '0.2.0'}),
    );
    final (code, out) = await doctor([]);
    expect(code, 1);
    expect(out, contains('twk_dev         0.2.0'));
    expect(out, contains('DISAGREE'));
    final (_, json) = await doctor(['--json']);
    expect((jsonDecode(json) as Map<String, Object?>)['agree'], isFalse);
  });

  /// A workspace in [root]: the lock lists no member, the package config
  /// names them, [versions] being those of the members by name.
  void workspace(Map<String, String> versions) {
    for (final MapEntry(:key, :value) in versions.entries) {
      final dir = Directory(p.join(project, 'packages', key))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: $key\nversion: $value\nresolution: workspace\n',
      );
    }
    Directory(p.join(project, '.dart_tool')).createSync();
    File(p.join(project, '.dart_tool', 'package_config.json'))
        .writeAsStringSync(
          jsonEncode({
            'configVersion': 2,
            'packages': [
              for (final name in versions.keys)
                {'name': name, 'rootUri': '../packages/$name'},
            ],
          }),
        );
    File(p.join(project, 'pubspec.lock')).writeAsStringSync(
      'packages:\n  args:\n    source: hosted\n    version: "2.0.0"\n',
    );
  }

  test('the members of a workspace are read from the package config', () async {
    workspace({'twk': '0.3.0', 'twk_core': '0.3.0'});
    final (code, out) = await doctor([]);
    expect(code, 0);
    expect(out, contains('twk             0.3.0 (workspace)'));
    expect(out, contains('twk_core        0.3.0 (workspace)'));
    expect(out, contains('twk_dev         not found'));
    expect(out, contains('the versions agree'));
    final (_, json) = await doctor(['--json']);
    final report = jsonDecode(json) as Map<String, Object?>;
    expect(report['versions'], {'twk': '0.3.0', 'twk_core': '0.3.0'});
    expect(report['sources'], {'twk': 'workspace', 'twk_core': 'workspace'});
  });

  test('members of a workspace that differ fail with 1', () async {
    workspace({'twk': '0.3.0', 'twk_core': '0.2.0'});
    final (code, out) = await doctor([]);
    expect(code, 1);
    expect(out, contains('DISAGREE'));
  });

  test(
    'a workspace read from a member, and a lock and members mixed',
    () async {
      workspace({'twk': '0.3.0', 'twk_core': '0.3.0'});
      File(p.join(project, 'pubspec.lock')).writeAsStringSync(
        _lock({'twk_test': '0.3.0'}),
      );
      project = p.join(project, 'packages', 'twk');
      final (_, json) = await doctor(['--json']);
      final report = jsonDecode(json) as Map<String, Object?>;
      expect(report['sources'], {
        'twk_test': 'locked',
        'twk': 'workspace',
        'twk_core': 'workspace',
      });
      expect(report['agree'], isTrue);
    },
  );

  test('says when no twk package is found', () async {
    File(p.join(project, 'pubspec.lock')).writeAsStringSync(_lock({}));
    final (code, out) = await doctor([]);
    expect(code, 0);
    expect(out, contains('none found to compare'));
    expect(out, isNot(contains('the versions agree')));
  });

  test('says there is no lock', () async {
    final (_, out) = await doctor([]);
    expect(out, contains('pubspec.lock    none found'));
  });

  test('a service that listens, and one left behind', () async {
    final dir = LocalAddress.directoryOf(project);
    final (server, address) = await LocalAddress.bind(dir, 'logs');
    addTearDown(server.close);
    server.listen((socket) => socket.destroy());
    await address.write(LocalAddress.fileOf('logs', project));
    final (gone, left) = await LocalAddress.bind(dir, 'shell');
    await left.write(LocalAddress.fileOf('shell', project));
    await gone.close();

    final (_, out) = await doctor([]);
    expect(out, matches(RegExp(r'logs +\S+ \(listening\)')));
    expect(out, matches(RegExp(r'shell +\S+ \(left behind\)')));
    expect(out, isNot(contains('no app running')));
  });

  test('says no app runs where .dart_tool/twk has nothing', () async {
    final (_, out) = await doctor([]);
    expect(out, contains('no app running'));
  });

  group('the skill for agents', () {
    String skillPath() => agentsPlan(
      project,
    ).changes.firstWhere((c) => c.file.isSkill).path;

    test('not installed', () async {
      final (_, out) = await doctor([]);
      expect(out, contains('not installed'));
    });

    test('current once twk agents has written it', () async {
      agentsPlan(project).apply();
      final (_, out) = await doctor([]);
      expect(out, contains('agents skill    current'));
    });

    test('older where a file differs from the pack and is as it wrote '
        'it', () async {
      final plan = agentsPlan(project)..apply();
      final path = plan.changes.firstWhere((c) => c.file.isSkill).path;
      final file = File(p.joinAll([project, ...path.split('/')]));
      final old = utf8.encode('an older skill\n');
      file.writeAsBytesSync(old);
      final manifest = File(p.join(file.parent.path, agentsManifest));
      final listed =
          jsonDecode(manifest.readAsStringSync()) as Map<String, Object?>;
      final name = p.posix.relative(path, from: p.posix.dirname(path));
      (listed['files']! as Map<String, Object?>)[name] = agentsHash(old);
      manifest.writeAsStringSync(jsonEncode(listed));

      final (_, out) = await doctor([]);
      expect(out, contains('older than this twk_dev: 1 file(s)'));
      final (_, json) = await doctor(['--json']);
      final agents =
          (jsonDecode(json) as Map<String, Object?>)['agents']!
              as Map<String, Object?>;
      expect(agents['stale'], [path]);
    });

    test('a file the project changed is named, not called older', () async {
      agentsPlan(project).apply();
      final path = skillPath();
      File(
        p.joinAll([project, ...path.split('/')]),
      ).writeAsStringSync("the project's own\n");
      final (_, out) = await doctor([]);
      expect(out, isNot(contains('older than')));
      expect(out, contains('changed by the project, kept: '));
    });

    test('nothing for a project that does not use twk', () async {
      File(
        p.join(project, 'pubspec.yaml'),
      ).writeAsStringSync('name: demo\nenvironment:\n  sdk: ^3.13.5\n');
      final (_, out) = await doctor([]);
      expect(out, isNot(contains('agents skill')));
    });
  });

  test('a connect that completes after the timeout is closed', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final accepted = <Socket>[];
    final closed = Completer<void>();
    server.listen((s) {
      accepted.add(s);
      s.listen(null, onDone: closed.complete);
    });
    final late = Completer<Socket>();
    final result = connects(
      () => late.future,
      timeout: const Duration(milliseconds: 1),
    );
    expect(await result, isFalse);
    late.complete(Socket.connect(server.address, server.port));
    // the server sees the client go
    await waitFor(
      closed.future,
      'the server to see the late socket closed',
      timeout: const Duration(seconds: 30),
    );
  });
}
