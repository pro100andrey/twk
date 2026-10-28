import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cipherlib/cipherlib.dart' show MLKEM;
import 'package:dartssh2/dartssh2.dart';
import 'package:test/test.dart';
import 'package:twk_ssh/src/crypto.dart';
import 'package:twk_ssh/src/transport.dart';
import 'package:twk_ssh/src/wire.dart';
import 'package:twk_ssh/twk_ssh.dart';
import 'package:twk_test/twk_test.dart';

import 'support.dart';

void main() {
  final alice = ClientKey.ed25519();
  late SshServer server;
  // the server's deadlines, the login's of 500 ms among them, run on it:
  // they fire when a test moves it, not while a slow exchange runs
  late FakeClock clock;

  setUp(() async {
    clock = FakeClock();
    server = await serve(
      auth: acceptKeys([alice]),
      onSession: (session) => session.done,
      loginTimeout: const Duration(milliseconds: 500),
      timers: (duration, callback) =>
          clock.run(() => Timer(duration, callback)),
    );
  });

  Future<RawClient> exchanging(Uint8List kexInit) async {
    final client = await RawClient.connect(server)
      ..version()
      ..send(kexInit);
    final first = await client.next();
    expect(first![0], SshMsg.kexInit);
    return client;
  }

  test("the server's KEXINIT offers strict kex and what it speaks", () async {
    final client = await RawClient.connect(server)
      ..version();
    final r = SshReader((await client.next())!)
      ..byte()
      ..raw(16);
    expect(client.serverVersion, 'SSH-2.0-twk_ssh_0.1');
    expect(r.nameList(), [
      'mlkem768x25519-sha256',
      'curve25519-sha256',
      'curve25519-sha256@libssh.org',
      'kex-strict-s-v00@openssh.com',
    ]);
    expect(r.nameList(), ['ssh-ed25519']);
    expect(r.nameList(), ['aes128-ctr', 'aes192-ctr', 'aes256-ctr']);
    r.nameList();
    expect(r.nameList(), [
      'hmac-sha2-256-etm@openssh.com',
      'hmac-sha2-512-etm@openssh.com',
      'hmac-sha2-256',
      'hmac-sha2-512',
    ]);
    r.nameList();
    expect(r.nameList(), ['none']);
  });

  group('before NEWKEYS', () {
    test('a message of the layers above ends the connection', () async {
      final client = await exchanging(clientKexInit())
        ..send(
          (SshWriter()
                ..byte(SshMsg.serviceRequest)
                ..utf8String('ssh-userauth'))
              .takeBytes(),
        );
      expect(await client.disconnectReason(), SshDisconnect.protocolError);
    });

    test('IGNORE is taken, but not under strict kex', () async {
      final lenient = await exchanging(clientKexInit())
        ..send(const [SshMsg.ignore, 0, 0, 0, 0])
        ..sendMessage(
          (w) => w
            ..byte(SshMsg.kexEcdhInit)
            ..string(X25519().publicKey),
        );
      await lenient.expectNext(SshMsg.kexEcdhReply);
      final strict = await exchanging(clientKexInit(strict: true))
        ..send(const [SshMsg.ignore, 0, 0, 0, 0]);
      expect(await strict.disconnectReason(), SshDisconnect.protocolError);
    });

    test('under strict kex the KEXINIT must be the first packet', () async {
      final client = await RawClient.connect(server)
        ..version()
        ..send(const [SshMsg.ignore, 0, 0, 0, 0])
        ..send(clientKexInit(strict: true));
      expect(await client.disconnectReason(), SshDisconnect.protocolError);
    });

    test('a second KEXINIT ends the connection', () async {
      final client = await exchanging(clientKexInit())
        ..send(clientKexInit());
      expect(await client.disconnectReason(), SshDisconnect.protocolError);
    });

    test('NEWKEYS before the exchange ends the connection', () async {
      final client = await exchanging(clientKexInit())
        ..send(const [SshMsg.newKeys]);
      expect(await client.disconnectReason(), SshDisconnect.protocolError);
    });
  });

  group('no algorithm in common ends it with KEY_EXCHANGE_FAILED', () {
    final cases = {
      'key exchange': clientKexInit(kex: ['diffie-hellman-group14-sha256']),
      'host key': clientKexInit(hostKeys: ['ssh-rsa']),
      'cipher': clientKexInit(ciphers: ['aes256-gcm@openssh.com']),
      'MAC': clientKexInit(macs: ['hmac-sha1']),
      'compression': clientKexInit(compression: ['zlib']),
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      test(key, () async {
        final client = await exchanging(value);
        expect(
          await client.disconnectReason(),
          SshDisconnect.keyExchangeFailed,
        );
      });
    }

    test('and a dartssh2 client offering only those is refused', () async {
      await expectLater(
        () async => (await connect(
          server,
          identities: [alice.pair],
          algorithms: const SSHAlgorithms(cipher: [SSHCipherType.aes256gcm]),
        )).authenticated,
        throwsA(isA<SSHError>()),
      );
    });
  });

  group('the client key of the exchange', () {
    Future<int?> offering(List<int> key) async {
      final client = await exchanging(clientKexInit())
        ..send(
          (SshWriter()
                ..byte(SshMsg.kexEcdhInit)
                ..string(key))
              .takeBytes(),
        );
      return client.disconnectReason();
    }

    test('of small order is refused', () async {
      expect(await offering(Uint8List(32)), SshDisconnect.keyExchangeFailed);
    });

    test('of the wrong length is refused', () async {
      expect(
        await offering(Uint8List(31)..[0] = 9),
        SshDisconnect.keyExchangeFailed,
      );
    });
  });

  test(
    'a key exchange message outside an exchange ends the connection',
    () async {
      final client = await RawClient.connect(server);
      await client.exchangeKeys();
      client
        ..sendMessage(
          (w) => w
            ..byte(SshMsg.kexEcdhInit)
            ..string(X25519().publicKey),
        )
        // answered, were the message above taken
        ..sendMessage(
          (w) => w
            ..byte(SshMsg.serviceRequest)
            ..utf8String('ssh-userauth'),
        );
      final first = (await client.next())!;
      expect(first[0], SshMsg.disconnect);
      expect((SshReader(first)..byte()).uint32(), SshDisconnect.protocolError);
    },
  );

  group('mlkem768x25519-sha256', () {
    test('agrees on keys the client logs in under', () async {
      final client = await RawClient.connect(server);
      await client.exchangeKeys(kex: mlkem768x25519);
      expect(server.connections.single.transport.kexAlgorithm, mlkem768x25519);
      await client.logIn('alice', alice.pair);
    });

    test('and a rekey of it', () async {
      final client = await RawClient.connect(server);
      await client.exchangeKeys(kex: mlkem768x25519);
      await client.exchangeKeys(first: false, kex: mlkem768x25519);
      await client.logIn('alice', alice.pair);
      expect(server.connections.single.transport.keyExchanges, 2);
    });

    test("is the server's choice only after the client's", () async {
      final client = await exchanging(
        clientKexInit(kex: ['curve25519-sha256', mlkem768x25519]),
      );
      client.sendMessage(
        (w) => w
          ..byte(SshMsg.kexEcdhInit)
          ..string(X25519().publicKey),
      );
      await client.expectNext(SshMsg.kexEcdhReply);
      expect(
        server.connections.single.transport.kexAlgorithm,
        'curve25519-sha256',
      );
    });

    group('a C_INIT that fails its checks is refused', () {
      Future<int?> offering(List<int> init) async {
        final client = await exchanging(clientKexInit(kex: [mlkem768x25519]))
          ..sendMessage(
            (w) => w
              ..byte(SshMsg.kexEcdhInit)
              ..string(init),
          );
        return client.disconnectReason();
      }

      final ek = MLKEM.kem768().keygen().encapsulationKey;
      final x25519 = X25519().publicKey;

      test('the right one is not', () async {
        final client = await exchanging(clientKexInit(kex: [mlkem768x25519]))
          ..sendMessage(
            (w) => w
              ..byte(SshMsg.kexEcdhInit)
              ..string([...ek, ...x25519]),
          );
        final reply = SshReader(await client.expectNext(SshMsg.kexEcdhReply))
          ..byte()
          ..string();
        expect(reply.string(), hasLength(1088 + 32));
      });

      test('X25519 alone', () async {
        expect(await offering(x25519), SshDisconnect.keyExchangeFailed);
      });

      test('a byte short', () async {
        expect(
          await offering([...ek, ...x25519.sublist(1)]),
          SshDisconnect.keyExchangeFailed,
        );
      });

      test('a coefficient not below q', () async {
        final bad = Uint8List.fromList(ek)
          ..[0] = 0xFF
          ..[1] |= 0x0F;
        expect(
          await offering([...bad, ...x25519]),
          SshDisconnect.keyExchangeFailed,
        );
      });

      test('an X25519 key of small order', () async {
        expect(
          await offering([...ek, ...Uint8List(32)]),
          SshDisconnect.keyExchangeFailed,
        );
      });
    });
  });

  test('a packet longer than the maximum is refused at its length', () async {
    final client = await RawClient.connect(server)
      ..version();
    await client.next();
    client.socket.add(Uint8List(4)..buffer.asByteData().setUint32(0, 1 << 30));
    expect(await client.disconnectReason(), SshDisconnect.protocolError);
  });

  test('a version line that is too long, or not SSH 2, is refused', () async {
    // the login timeout doesn't close it first: its clock stays put
    final long = await RawClient.connect(server);
    long.socket.add(List.filled(300, 0x41));
    expect(await long.closes(const Duration(seconds: 2)), isTrue);
    final old = await RawClient.connect(server)
      ..version('SSH-1.5-old');
    expect(await old.closes(const Duration(seconds: 2)), isTrue);
    expect(old.rawText, contains('Protocol mismatch.'));
  });

  test("a client that doesn't log in in time is let go", () async {
    final client = await RawClient.connect(server)
      ..version();
    expect((await client.next())![0], SshMsg.kexInit);
    final transport = server.connections.single.transport;
    await clock.elapse(const Duration(milliseconds: 499));
    expect(transport.isClosed, isFalse);
    await clock.elapse(const Duration(milliseconds: 1));
    expect(transport.isClosed, isTrue);
    expect(await client.disconnectReason(), SshDisconnect.byApplication);
  });

  test('a client that logged in is not let go at the deadline', () async {
    final client = await RawClient.connect(server);
    await client.exchangeKeys();
    await client.logIn('alice', alice.pair);
    final transport = server.connections.single.transport;
    await clock.elapse(const Duration(minutes: 1));
    expect(transport.isClosed, isFalse);
    // and still answers
    client.send(const [70]);
    await client.expectNext(SshMsg.unimplemented);
  });

  test('strict kex with a dartssh2 client, and a rekey it starts', () async {
    late SshSession session;
    final rekeyed = Completer<void>();
    final server = await serve(
      auth: acceptKeys([alice]),
      onSession: (s) async {
        session = s;
        await for (final bytes in s.input) {
          s.add(bytes); // an echo
          if (utf8.decode(bytes).contains('end')) {
            break;
          }
        }
        await rekeyed.future;
      },
    );
    final client = await connect(server, identities: [alice.pair]);
    final shell = await client.shell();
    final out = shell.stdout.asBroadcastStream();
    shell.write(utf8.encode('before '));
    await readUntil(out, (s) => s.contains('before'));
    final connection = server.connections.single;
    expect(connection.transport.strictKex, isTrue);
    expect(connection.transport.keyExchanges, 1);
    // the session's output goes on while the exchange runs
    final echo = readUntil(out, (s) => s.contains('end'));
    final rekey = client.rekey();
    shell.write(utf8.encode('after end'));
    await rekey;
    expect(await echo, 'after end');
    expect(connection.transport.keyExchanges, 2);
    rekeyed.complete();
    await shell.done;
    expect(shell.exitCode, 0);
    await session.done.timeout(const Duration(seconds: 5));
  });

  test("a client that doesn't read can't make the server queue more", () async {
    SshTransport.maxQueued = 16 << 10;
    addTearDown(() => SshTransport.maxQueued = 1 << 20);
    final client = await RawClient.connect(server, receiveBuffer: 4096);
    await client.exchangeKeys();
    await client.logIn('alice', alice.pair);
    final transport = server.connections.single.transport;
    client.pause();
    // A message the server doesn't know is answered with UNIMPLEMENTED,
    // 48 bytes for 48: 9.6 MB of answers the client doesn't read, more
    // than the kernel takes in for it (4 MB at most for the server's
    // socket, as Linux's tcp_wmem has it, and the client's 4 KiB), so the
    // server's writes wait and its queue would grow.
    const n = 200000;
    for (var i = 0; i < n; i++) {
      client.send(const [70]);
    }
    await waitUntil(
      () => transport.readingPaused,
      'the server to stop reading',
    );
    expect(transport.maxQueuedSeen, lessThan(SshTransport.maxQueued + 1024));
    // the rest at the speed of a client that reads
    client
      ..setReceiveBuffer(1 << 20)
      ..resume();
    var answers = 0;
    while (answers < n) {
      final p = await client.next();
      expect(p?[0], SshMsg.unimplemented);
      answers++;
    }
    expect(transport.maxQueuedSeen, lessThan(SshTransport.maxQueued + 1024));
    // some 7 s on an idle machine: what the ciphers cost, both ways; past
    // 90 s on a CI runner of 4 cores, running every package's suite at once
  }, timeout: const Timeout(Duration(minutes: 5)));

  test(
    "the server's output waits while a rekey the client started runs",
    () async {
      var writing = true;
      final server = await serve(
        auth: acceptKeys([alice]),
        onSession: (s) async {
          while (writing && !s.isDone) {
            s.add(Uint8List(1024));
            // a turn of the event loop, so that the transport reads too
            await Future<void>.delayed(Duration.zero);
          }
        },
      );
      final client = await RawClient.connect(server);
      await client.exchangeKeys();
      await client.logIn('alice', alice.pair);
      await client.openShell(window: 64 << 20);
      await client.expectNext(SshMsg.channelData);
      final between = await client.exchangeKeys(first: false);
      expect(between.where((id) => id >= 50), isEmpty, reason: '$between');
      // what was held comes after NEWKEYS, under the new keys
      await client.expectNext(
        SshMsg.channelData,
        skip: const {SshMsg.channelData},
      );
      // The held output went at the server's NEWKEYS, before the client's
      // was read: the answer to a request sent after it says it has been.
      client.sendMessage(
        (w) => w
          ..byte(SshMsg.globalRequest)
          ..utf8String('ping@twk')
          ..boolean(true),
      );
      await client.expectNext(
        SshMsg.requestFailure,
        skip: const {SshMsg.channelData},
      );
      expect(server.connections.single.transport.keyExchanges, 2);
      writing = false;
    },
  );
}
