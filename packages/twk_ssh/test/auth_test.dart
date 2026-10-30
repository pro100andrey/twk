import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:test/test.dart';
import 'package:twk_ssh/src/wire.dart';
import 'package:twk_ssh/twk_ssh.dart';
import 'package:twk_test/twk_test.dart';

import 'support.dart';

void main() {
  final alice = ClientKey.ed25519();
  final mallory = ClientKey.ed25519();

  /// A server that runs nothing, under [auth], its time on [clock].
  Future<SshServer> serving(
    SshAuth auth, {
    List<SshHostKey>? hostKeys,
    FakeClock? clock,
  }) => serve(
    auth: auth,
    onSession: (s) => s.done,
    hostKeys: hostKeys,
    clock: clock?.stopwatch,
  );

  /// Waits for [server] to see the refused connections end, then past the
  /// penalty they gave the address: the next connection is let in.
  Future<void> forgiven(SshServer server, FakeClock clock) async {
    await waitUntil(
      () => server.connections.every((c) => c.user != null),
      'the refused connections to end',
    );
    await clock.elapse(const SshPenalty().max);
  }

  Matcher refused() => throwsA(isA<SSHAuthFailError>());

  test(
    'a key the server accepts logs in; the user and key are asked',
    () async {
      final asked = <String>[];
      final server = await serving(
        SshAuth(
          publicKey: (user, key) {
            asked.add('$user ${key.fingerprint}');
            return key == alice.publicKey;
          },
        ),
      );
      final client = await connect(
        server,
        user: 'carol',
        identities: [alice.pair],
      );
      await client.authenticated;
      expect(asked.toSet(), {'carol ${alice.publicKey.fingerprint}'});
    },
  );

  test('a key the server does not accept is refused', () async {
    final server = await serving(acceptKeys([alice]));
    final client = await connect(server, identities: [mallory.pair]);
    await expectLater(client.authenticated, refused());
  });

  test('a password the callback accepts logs in, others are refused', () async {
    final clock = FakeClock();
    final server = await serving(
      SshAuth(password: (user, password) => user == 'bob' && password == 'pw'),
      clock: clock,
    );
    final ok = await connect(server, user: 'bob', password: () => 'pw');
    await ok.authenticated;
    final wrong = await connect(server, user: 'bob', password: () => 'nope');
    await expectLater(wrong.authenticated, refused());
    await wrong.close();
    await forgiven(server, clock);
    final other = await connect(server, user: 'eve', password: () => 'pw');
    await expectLater(other.authenticated, refused());
  });

  test('no "none": a client with nothing to offer is refused', () async {
    final server = await serving(
      SshAuth(publicKey: (_, _) => true, password: (_, _) => true),
    );
    final client = await connect(server);
    await expectLater(client.authenticated, refused());
  });

  test('a connection gets maxAttempts failures, then it is ended', () async {
    for (final (limit, asked) in [(3, 3), (20, 8)]) {
      var calls = 0;
      final server = await serving(
        SshAuth(
          publicKey: (_, _) {
            calls++;
            return false;
          },
          maxAttempts: limit,
        ),
      );
      final keys = [for (var i = 0; i < 8; i++) ClientKey.ed25519().pair];
      final client = await connect(server, identities: keys);
      await expectLater(client.authenticated, throwsA(isA<SSHError>()));
      await server.connections.firstOrNull?.done;
      expect(calls, asked, reason: 'limit $limit');
    }
  });

  group('by hand', () {
    /// A raw client of a server under [auth], its keys exchanged and, with
    /// [service], the authentication service granted.
    Future<RawClient> raw(SshAuth auth, {bool service = true}) async {
      final client = await RawClient.connect(await serving(auth));
      await client.exchangeKeys();
      if (service) {
        client.sendMessage(
          (w) => w
            ..byte(SshMsg.serviceRequest)
            ..utf8String('ssh-userauth'),
        );
        await client.expectNext(SshMsg.serviceAccept);
      }
      return client;
    }

    /// A USERAUTH_REQUEST of [user] by [method], what [rest] writes after.
    void request(
      RawClient client,
      String method, [
      void Function(SshWriter w)? rest,
      String user = 'alice',
    ]) => client.sendMessage((w) {
      w
        ..byte(SshMsg.userauthRequest)
        ..utf8String(user)
        ..utf8String('ssh-connection')
        ..utf8String(method);
      rest?.call(w);
    });

    /// The reason of the DISCONNECT [client] gets next, as the first
    /// message it gets.
    Future<int> disconnected(RawClient client) async {
      final p = (await client.next())!;
      expect(p[0], SshMsg.disconnect, reason: 'message ${p[0]}');
      return (SshReader(p)..byte()).uint32();
    }

    test('a signature that is not of the key is refused', () async {
      final client = await raw(acceptKeys([alice]));
      final blob = alice.pair.toPublicKey().encode();
      void signed(SshWriter w) => w
        ..boolean(true)
        ..utf8String('ssh-ed25519')
        ..string(blob);
      // what alice would sign, signed by mallory
      final data = SshWriter()
        ..string(client.sessionId!)
        ..byte(SshMsg.userauthRequest)
        ..utf8String('alice')
        ..utf8String('ssh-connection')
        ..utf8String('publickey');
      signed(data);
      final forged = mallory.pair.sign(data.takeBytes()).encode();
      request(client, 'publickey', (w) {
        signed(w);
        w.string(forged);
      });
      await client.expectNext(SshMsg.userauthFailure);
    });

    test('a key offered under an algorithm not its own is refused', () async {
      final client = await raw(acceptKeys([alice]));
      request(
        client,
        'publickey',
        (w) => w
          ..boolean(false)
          ..utf8String('rsa-sha2-256')
          ..string(alice.pair.toPublicKey().encode()),
      );
      await client.expectNext(SshMsg.userauthFailure);
    });

    test('"none" is answered once, then counts as a failure', () async {
      final client = await raw(
        SshAuth(password: (_, _) => true, maxAttempts: 1),
      );
      request(client, 'none');
      await client.expectNext(SshMsg.userauthFailure);
      request(client, 'none');
      expect(await disconnected(client), SshDisconnect.noMoreAuthMethods);
    });

    test('a password change is refused, the password right or not', () async {
      final client = await raw(SshAuth(password: (_, p) => p == 'pw'));
      request(
        client,
        'password',
        (w) => w
          ..boolean(true)
          ..utf8String('pw')
          ..utf8String('new'),
      );
      await client.expectNext(SshMsg.userauthFailure);
    });

    test('a channel before the login ends the connection', () async {
      final client = await raw(acceptKeys([alice]));
      client.sendMessage(
        (w) => w
          ..byte(SshMsg.channelOpen)
          ..utf8String('session')
          ..uint32(0)
          ..uint32(1 << 20)
          ..uint32(1 << 15),
      );
      expect(await disconnected(client), SshDisconnect.protocolError);
    });

    test('a login before its service ends the connection', () async {
      final client = await raw(acceptKeys([alice]), service: false);
      request(client, 'none');
      expect(await disconnected(client), SshDisconnect.protocolError);
    });
  });

  group('with ssh-keygen', () {
    late Directory dir;
    setUpAll(() => dir = Directory.systemTemp.createTempSync('twk_ssh_auth'));
    tearDownAll(() => dir.deleteSync(recursive: true));

    /// A key of [type] and [bits]; null, the test marked skipped, without
    /// ssh-keygen.
    Future<ClientKey?> keygen(String type, int bits) async {
      final key = await ClientKey.keygen(dir, type, bits);
      if (key == null) {
        markTestSkipped('ssh-keygen is not installed');
      }
      return key;
    }

    for (final (type, bits) in [
      ('rsa', 3072),
      ('ecdsa', 256),
      ('ecdsa', 384),
      ('ecdsa', 521),
    ]) {
      test('a $type $bits key logs in', () async {
        final key = await keygen(type, bits);
        if (key == null) {
          return;
        }
        final server = await serving(acceptKeys([key]));
        final client = await connect(server, identities: [key.pair]);
        await client.authenticated;
      });
    }

    test('an RSA key under 2048 bits is refused', () async {
      final key = await keygen('rsa', 1024);
      if (key == null) {
        return;
      }
      var asked = false;
      final server = await serving(SshAuth(publicKey: (_, _) => asked = true));
      final client = await connect(server, identities: [key.pair]);
      await expectLater(client.authenticated, refused());
      expect(asked, isFalse);
    });

    for (final (type, bits) in [('rsa', 3072), ('ecdsa', 256)]) {
      test('the server proves itself with a $type host key', () async {
        final path = '${dir.path}/host_$type';
        final made = await sshKeygen([
          ...['-q', '-t', type, '-b', '$bits', '-N', '', '-f', path],
        ]);
        if (made == null) {
          markTestSkipped('ssh-keygen is not installed');
          return;
        }
        expect(made.exitCode, 0, reason: '${made.stderr}');
        final host = await SshHostKey.load(path);
        final server = await serving(acceptKeys([alice]), hostKeys: [host]);
        String? offered;
        final client = SSHClient(
          await SSHSocket.connect('127.0.0.1', server.port),
          username: 'alice',
          identities: [alice.pair],
          onVerifyHostKey: (type, _) {
            offered = type;
            return true;
          },
        );
        addTearDown(client.close);
        await client.authenticated;
        expect(offered, host.algorithm);
      });
    }
  });

  test('an authorized_keys file is read at each attempt', () async {
    final dir = Directory.systemTemp.createTempSync('twk_ssh_keys');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/authorized_keys')
      ..writeAsStringSync('# none yet\n');
    final clock = FakeClock();
    final server = await serving(
      SshAuth.authorizedKeys(file.path),
      clock: clock,
    );
    final before = await connect(server, identities: [alice.pair]);
    await expectLater(before.authenticated, refused());
    await before.close();
    await forgiven(server, clock);
    file.writeAsStringSync('${alice.publicKey} alice@laptop\n');
    final after = await connect(server, identities: [alice.pair]);
    await after.authenticated;
    file.deleteSync();
    final gone = await connect(server, identities: [alice.pair]);
    await expectLater(gone.authenticated, refused());
  });

  test(
    'an authorized_keys file others may write, or in a directory they may '
    'write, lets no key in',
    () async {
      final dir = Directory.systemTemp.createTempSync('twk_ssh_keys');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/authorized_keys')
        ..writeAsStringSync('${alice.publicKey} alice@laptop\n');
      Future<void> chmod(String mode, String path) async =>
          expect((await Process.run('chmod', [mode, path])).exitCode, 0);
      await chmod('600', file.path);
      await AuthorizedKeys.load(file.path);
      await chmod('620', file.path);
      await expectLater(
        AuthorizedKeys.load(file.path),
        throwsA(isA<FileSystemException>()),
      );
      await chmod('600', file.path);
      await chmod('777', dir.path);
      await expectLater(
        AuthorizedKeys.load(file.path),
        throwsA(isA<FileSystemException>()),
      );
      await chmod('1777', dir.path);
      await AuthorizedKeys.load(file.path);
      await chmod('700', dir.path);
    },
    testOn: '!windows',
  );
}
