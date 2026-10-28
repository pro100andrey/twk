import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_ssh/twk_ssh.dart';
import 'package:twk_test/twk_test.dart';

import 'support.dart';

/// Whether ssh(1) and ssh-keygen are installed.
bool get _haveOpenSsh => onPath('ssh') && onPath('ssh-keygen');

/// What a run of ssh(1) gave.
typedef SshRun = ({int exitCode, String stdout, String stderr});

void main() {
  if (!_haveOpenSsh) {
    test('ssh(1)', () {}, skip: 'ssh(1) or ssh-keygen is not installed');
    return;
  }

  late Directory dir;
  late String keyPath;
  late SshPublicKey key;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('twk_ssh_openssh');
    keyPath = '${dir.path}/id_ed25519';
    final made = await sshKeygen([
      ...['-q', '-t', 'ed25519', '-N', '', '-f', keyPath],
    ]);
    expect(made?.exitCode, 0, reason: '${made?.stderr}');
    key = SshPublicKey.parse(File('$keyPath.pub').readAsStringSync())!;
  });
  tearDownAll(() => dir.deleteSync(recursive: true));

  /// Runs ssh(1) against [server] with [args] after the destination,
  /// [input] on its stdin.
  Future<SshRun> ssh(
    SshServer server,
    List<String> args, {
    List<String> options = const [],
    List<int> input = const [],
    Map<String, String> environment = const {},
    String identity = '',
    bool quiet = true,
  }) async {
    // ssh(1) takes the first value given: [options] go before the defaults
    final process = await startProcess('ssh', [
      ...options,
      ...['-F', '/dev/null', if (quiet) '-q', '-p', '${server.port}'],
      ...['-i', if (identity.isEmpty) keyPath else identity],
      ...[
        '-o',
        'StrictHostKeyChecking=no',
        '-o',
        'UserKnownHostsFile=/dev/null',
      ],
      ...['-o', 'IdentitiesOnly=yes', '-o', 'IdentityAgent=none'],
      ...['-o', 'BatchMode=yes', '-o', 'LogLevel=ERROR'],
      'alice@127.0.0.1',
      ...args,
    ], environment: environment);
    process.stdin.add(input);
    unawaited(process.stdin.close());
    final out = process.stdout.fold(<int>[], (a, b) => a..addAll(b));
    final err = process.stderr.transform(utf8.decoder).join();
    final code = await waitFor(
      process.exitCode,
      'ssh ${args.join(' ')}',
      timeout: const Duration(seconds: 20),
    );
    return (
      exitCode: code,
      stdout: latin1.decode(await out),
      stderr: await err,
    );
  }

  test('a command with key auth, its output and exit status', () async {
    String? command;
    final server = await serve(
      auth: SshAuth(publicKey: (user, k) => user == 'alice' && k == key),
      onSession: (session) async {
        command = session.command;
        session.add(utf8.encode('ran ${session.command}'));
        await session.exit(3);
      },
    );
    final run = await ssh(server, ['echo', 'hi']);
    expect(run.stderr, isEmpty);
    expect(run.stdout, 'ran echo hi');
    expect(run.exitCode, 3);
    expect(command, 'echo hi');
  });

  test('a shell on a terminal: TERM, input, output', () async {
    SshPty? pty;
    final server = await serve(
      auth: SshAuth(publicKey: (_, k) => k == key),
      onSession: (session) async {
        pty = session.pty;
        final line = await readUntil(session.input, (s) => s.contains('\r'));
        session.add(utf8.encode('got ${line.trim()}\r\n'));
      },
    );
    final run = await ssh(
      server,
      const [],
      options: ['-tt'],
      input: utf8.encode('ping\r'),
      environment: {'TERM': 'xterm-256color'},
    );
    expect(run.exitCode, 0, reason: run.stderr);
    expect(run.stdout, contains('got ping'));
    expect(pty!.term, 'xterm-256color');
  });

  test('rekeys ssh(1) starts, both ways, lose nothing', () async {
    late SshConnection connection;
    late SshServer server;
    var received = 0;
    server = await serve(
      auth: SshAuth(publicKey: (_, k) => k == key),
      onSession: (session) async {
        connection = server.connections.single;
        session.add(Uint8List.fromList(List.generate(1 << 20, (i) => i)));
        await for (final bytes in session.input) {
          received += bytes.length;
        }
      },
    );
    final run = await ssh(
      server,
      const ['cat'],
      options: ['-o', 'RekeyLimit=64K'],
      input: Uint8List(256 << 10),
    );
    expect(run.exitCode, 0, reason: run.stderr);
    expect(latin1.encode(run.stdout), List.generate(1 << 20, (i) => i & 0xFF));
    expect(received, 256 << 10);
    expect(connection.transport.keyExchanges, greaterThan(2));
    expect(connection.transport.strictKex, isTrue);
  });

  group('the post-quantum key exchange', () {
    Future<(SshRun, SshConnection)> sshTrue(List<String> options) async {
      late SshConnection connection;
      late SshServer server;
      server = await serve(
        auth: SshAuth(publicKey: (_, k) => k == key),
        onSession: (session) {
          connection = server.connections.single;
          session.add(utf8.encode('in'));
        },
      );
      final run = await ssh(
        server,
        ['true'],
        options: options,
        quiet: !options.contains('LogLevel=INFO'),
      );
      return (run, connection);
    }

    test('is what ssh(1) agrees on by itself, unwarned', () async {
      // LogLevel=INFO before the default ERROR: what OpenSSH 10 warns at,
      // when it agreed on a method that is not post-quantum and its
      // KexAlgorithms was not set (sshconnect.c, warn_nonpq_kex)
      final (run, connection) = await sshTrue(['-o', 'LogLevel=INFO']);
      expect(run.exitCode, 0, reason: run.stderr);
      expect(run.stdout, 'in');
      expect(connection.transport.kexAlgorithm, 'mlkem768x25519-sha256');
      expect(run.stderr, isNot(contains('post-quantum')));
    });

    test('is spoken when it is all ssh(1) offers', () async {
      final (run, connection) = await sshTrue([
        ...['-o', 'KexAlgorithms=mlkem768x25519-sha256'],
      ]);
      expect(run.exitCode, 0, reason: run.stderr);
      expect(run.stdout, 'in');
      expect(connection.transport.kexAlgorithm, 'mlkem768x25519-sha256');
    });
  });

  test('rekeys the server starts, both ways, lose nothing', () async {
    late SshConnection connection;
    late SshServer server;
    var received = 0;
    server = await serve(
      auth: SshAuth(publicKey: (_, k) => k == key),
      rekeyLimit: const SshRekeyLimit(bytes: 64 << 10),
      onSession: (session) async {
        connection = server.connections.single;
        session.add(Uint8List.fromList(List.generate(1 << 20, (i) => i)));
        await for (final bytes in session.input) {
          received += bytes.length;
        }
      },
    );
    final run = await ssh(
      server,
      const ['cat'],
      // ssh(1)'s own limit out of the way
      options: ['-o', 'RekeyLimit=default none'],
      input: Uint8List(256 << 10),
    );
    expect(run.exitCode, 0, reason: run.stderr);
    expect(latin1.encode(run.stdout), List.generate(1 << 20, (i) => i & 0xFF));
    expect(received, 256 << 10);
    // One at least each way, the output's first 64 KiB starting one and
    // the input's another: what is sent while an exchange runs waits for
    // it and goes after under the new keys, which then rekey again at the
    // next packet.
    expect(connection.transport.serverKeyExchanges, greaterThanOrEqualTo(2));
    expect(
      connection.transport.keyExchanges,
      connection.transport.serverKeyExchanges + 1,
    );
    expect(connection.transport.kexAlgorithm, 'mlkem768x25519-sha256');
  });

  test('a key the server does not accept is refused', () async {
    var asked = 0;
    var ran = false;
    final server = await serve(
      auth: SshAuth(publicKey: (_, _) => asked++ < 0),
      onSession: (session) => ran = true,
    );
    final run = await ssh(server, ['true']);
    expect(run.exitCode, 255);
    expect(asked, 1); // the query; nothing signed is sent for a refused key
    expect(ran, isFalse);
  });

  test('a password from SSH_ASKPASS', () async {
    final askpass = File('${dir.path}/askpass')
      ..writeAsStringSync('#!/bin/sh\necho sesame\n');
    expect((await runProcess('chmod', ['700', askpass.path])).exitCode, 0);
    final server = await serve(
      auth: SshAuth(password: (user, password) => password == 'sesame'),
      onSession: (session) => session.add(utf8.encode('in')),
    );
    final run = await ssh(
      server,
      ['true'],
      options: [
        ...['-o', 'BatchMode=no', '-o', 'PubkeyAuthentication=no'],
        ...['-o', 'NumberOfPasswordPrompts=1'],
      ],
      environment: {
        'SSH_ASKPASS': askpass.path,
        'SSH_ASKPASS_REQUIRE': 'force',
        'DISPLAY': ':0',
      },
    );
    expect(run.exitCode, 0, reason: run.stderr);
    expect(run.stdout, 'in');
  });
}
