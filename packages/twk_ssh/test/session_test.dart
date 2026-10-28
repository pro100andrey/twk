import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:test/test.dart';
import 'package:twk_ssh/twk_ssh.dart';
import 'package:twk_test/twk_test.dart';

import 'support.dart';

/// [n] bytes counting up, wrapping at 256.
Uint8List counting(int n) => Uint8List.fromList(List.generate(n, (i) => i));

void main() {
  final alice = ClientKey.ed25519();
  final bob = ClientKey.ed25519();

  test(
    'a shell with a terminal: its size, input, output, exit status',
    () async {
      final seen = Completer<SshSession>();
      final server = await serve(
        auth: acceptKeys([alice]),
        onSession: (session) async {
          seen.complete(session);
          session.add(utf8.encode('hello ${session.user}\r\n'));
          final line = await readUntil(session.input, (s) => s.contains('\r'));
          session.add(utf8.encode('got $line\n'));
        },
      );
      final client = await connect(server, identities: [alice.pair]);
      final shell = await client.shell(
        pty: const SSHPtyConfig(type: 'xterm-kitty', width: 100, height: 30),
        environment: {'COLORTERM': 'truecolor'},
      );
      final output = readUntil(shell.stdout, (s) => s.contains('got'));
      shell.write(utf8.encode('ping\r'));
      expect(await output, 'hello alice\r\ngot ping\r\n');
      final session = await seen.future;
      expect(session.pty!.term, 'xterm-kitty');
      expect([session.pty!.columns, session.pty!.rows], [100, 30]);
      expect(session.environment, {'COLORTERM': 'truecolor'});
      expect(session.command, isNull);
      expect(session.publicKey, alice.publicKey);
      await shell.done;
      expect(shell.exitCode, 0);
      await session.done;
    },
  );

  test('a command without a terminal, and the status it exits with', () async {
    final seen = Completer<SshSession>();
    final server = await serve(
      auth: acceptKeys([alice]),
      onSession: (session) async {
        seen.complete(session);
        session.add(utf8.encode('ran ${session.command}'));
        await session.exit(3);
      },
    );
    final client = await connect(server, identities: [alice.pair]);
    final run = await client.execute('build --fast');
    expect(await readUntil(run.stdout, (_) => false), 'ran build --fast');
    await run.done;
    expect(run.exitCode, 3);
    final session = await seen.future;
    expect(session.pty, isNull);
    expect(session.command, 'build --fast');
  });

  test('a handler that throws exits with 1', () async {
    final errors = <Object>[];
    final server = await SshServer.bind(
      '127.0.0.1',
      0,
      hostKeys: [hostKey],
      auth: acceptKeys([alice]),
      onSession: (_) => throw StateError('broken'),
      onError: (e, _) => errors.add(e),
    );
    addTearDown(server.close);
    final client = await connect(server, identities: [alice.pair]);
    final run = await client.execute('x');
    await run.done;
    expect(run.exitCode, 1);
    expect(errors, [isA<StateError>()]);
  });

  test('a resize reaches the session as its new terminal size', () async {
    final sizes = <List<int>>[];
    final resized = Completer<void>();
    final server = await serve(
      auth: acceptKeys([alice]),
      onSession: (session) async {
        session.resizes.listen((pty) {
          sizes.add([pty.columns, pty.rows, pty.pixelWidth]);
          expect(session.pty, same(pty));
          resized.complete();
        });
        session.add(utf8.encode('ready'));
        await resized.future;
      },
    );
    final client = await connect(server, identities: [alice.pair]);
    final shell = await client.shell();
    await readUntil(shell.stdout, (s) => s == 'ready');
    shell.resizeTerminal(132, 43, 1320);
    await shell.done;
    expect(sizes, [
      [132, 43, 1320],
    ]);
  });

  test('signals the client sends reach the session by name', () async {
    final server = await serve(
      auth: acceptKeys([alice]),
      onSession: (session) async {
        final signal = session.signals.first;
        session
          ..add(utf8.encode('ready'))
          ..add(utf8.encode(await signal));
      },
    );
    final client = await connect(server, identities: [alice.pair]);
    final shell = await client.shell();
    final out = shell.stdout.asBroadcastStream();
    await readUntil(out, (s) => s == 'ready');
    shell.kill(SSHSignal.INT);
    expect(await readUntil(out, (s) => s == 'INT'), 'INT');
  });

  test(
    'two sessions at once each see their own user, input and output',
    () async {
      final server = await serve(
        auth: acceptKeys([alice, bob]),
        onSession: (session) async {
          final line = await readUntil(session.input, (s) => s.endsWith('\r'));
          session.add(utf8.encode('${session.user} typed $line'));
        },
      );
      final a = await connect(server, identities: [alice.pair]);
      final b = await connect(server, user: 'bob', identities: [bob.pair]);
      final shellA = await a.shell();
      final shellB = await b.shell();
      final outA = readUntil(shellA.stdout, (_) => false);
      final outB = readUntil(shellB.stdout, (_) => false);
      shellB
        ..write(utf8.encode('one '))
        ..write(utf8.encode('two\r'));
      shellA.write(utf8.encode('three\r'));
      expect(await outA, 'alice typed three\r');
      expect(await outB, 'bob typed one two\r');
      expect(server.connections, hasLength(2));
    },
  );

  test('EOF ends the input, the connection going away the session', () async {
    final eof = Completer<void>();
    final ended = Completer<void>();
    final server = await serve(
      auth: acceptKeys([alice]),
      onSession: (session) async {
        session.add(utf8.encode('ready'));
        await session.input.drain<void>();
        eof.complete();
        await session.done;
        ended.complete();
      },
    );
    final client = await connect(server, identities: [alice.pair]);
    final shell = await client.shell();
    await readUntil(shell.stdout, (s) => s == 'ready');
    unawaited(shell.stdin.close());
    await eof.future.timeout(const Duration(seconds: 5));
    expect(ended.isCompleted, isFalse);
    await client.close();
    await ended.future.timeout(const Duration(seconds: 5));
  });

  test('one session per connection: a second channel is refused', () async {
    final server = await serve(
      auth: acceptKeys([alice]),
      onSession: (session) => session.done,
    );
    final client = await connect(server, identities: [alice.pair]);
    await client.shell();
    await expectLater(client.shell(), throwsA(isA<SSHChannelOpenError>()));
  });

  test('output goes no faster than the client grants', () async {
    late SshSession session;
    final written = Completer<void>();
    final flushed = Completer<void>();
    final server = await serve(
      auth: acceptKeys([alice]),
      onSession: (s) async {
        await s.input.first;
        session = s..add(counting(3 << 20));
        written.complete();
        await s.flush();
        flushed.complete();
      },
    );
    final client = await connect(server, identities: [alice.pair]);
    final shell = await client.shell();
    final received = BytesBuilder();
    // paused, the client grants nothing beyond its first 2 MiB
    final reading = shell.stdout.listen(received.add)..pause();
    shell.write(utf8.encode('go'));
    await written.future;
    await waitUntil(
      () => session.pendingOutput == 1 << 20,
      'the output past the window to wait',
    );
    // a window the client granted before the answer would be in by then
    await client.ping();
    expect(session.pendingOutput, 1 << 20);
    expect(flushed.isCompleted, isFalse);
    reading.resume();
    await shell.done;
    await reading.cancel();
    expect(flushed.isCompleted, isTrue);
    expect(received.takeBytes(), counting(3 << 20));
  });

  test(
    "input the app doesn't read is held no further than the window",
    () async {
      late SshSession session;
      final started = Completer<void>();
      final read = Completer<void>();
      final received = BytesBuilder();
      final server = await serve(
        auth: acceptKeys([alice]),
        onSession: (s) async {
          session = s;
          started.complete();
          await read.future;
          await for (final bytes in s.input) {
            received.add(bytes);
            if (received.length == 3 << 20) {
              break;
            }
          }
        },
      );
      final client = await connect(server, identities: [alice.pair]);
      final shell = await client.shell();
      await started.future;
      shell.write(counting(3 << 20));
      await waitUntil(
        () => session.heldInput == SshSession.window,
        'the input to fill the window',
      );
      // data the client sent before the answer would be in by then
      await client.ping();
      expect(session.heldInput, SshSession.window);
      read.complete();
      await shell.done;
      expect(received.takeBytes(), counting(3 << 20));
    },
  );
}
