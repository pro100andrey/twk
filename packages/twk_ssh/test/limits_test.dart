import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_ssh/src/transport.dart';
import 'package:twk_ssh/src/wire.dart';
import 'package:twk_ssh/twk_ssh.dart';
import 'package:twk_test/twk_test.dart';

import 'support.dart';

void main() {
  final alice = ClientKey.ed25519();

  /// A message the server answers with UNIMPLEMENTED, 48 bytes for 48
  /// under aes128-ctr and hmac-sha2-256.
  const unknown = [70];

  /// An IGNORE, answered by nothing, as long.
  const ignore = [SshMsg.ignore, 0, 0, 0, 0];

  group('the server rekeys', () {
    test('after the time of the limit, on its clock', () async {
      final clock = FakeClock();
      final server = await serve(
        auth: acceptKeys([alice]),
        onSession: (session) => session.done,
        rekeyLimit: const SshRekeyLimit(time: Duration(minutes: 10)),
        clock: clock.stopwatch,
      );
      final client = await RawClient.connect(server);
      await client.exchangeKeys();
      final transport = server.connections.single.transport;
      await clock.elapse(const Duration(minutes: 9, seconds: 59));
      client.send(unknown);
      await client.expectNext(SshMsg.unimplemented);
      expect(transport.serverKeyExchanges, 0);
      await clock.elapse(const Duration(seconds: 1));
      // the next packet read starts the exchange; the answer to it waits
      // for the new keys
      client.send(unknown);
      final between = await client.exchangeKeys(first: false);
      expect(between, isEmpty);
      await client.expectNext(SshMsg.unimplemented);
      expect(transport.serverKeyExchanges, 1);
      // and the time starts again from the new keys
      await clock.elapse(const Duration(minutes: 9, seconds: 59));
      client.send(unknown);
      await client.expectNext(SshMsg.unimplemented);
      expect(transport.serverKeyExchanges, 1);
      // the answer above came after the client's NEWKEYS was read
      expect(transport.keyExchanges, 2);
      await client.logIn('alice', alice.pair);
    });

    test('before it sends a packet past the time', () async {
      final clock = FakeClock();
      late SshSession session;
      final opened = Completer<void>();
      final server = await serve(
        auth: acceptKeys([alice]),
        onSession: (s) {
          session = s;
          opened.complete();
          return s.done;
        },
        rekeyLimit: const SshRekeyLimit(time: Duration(minutes: 10)),
        clock: clock.stopwatch,
      );
      final client = await RawClient.connect(server);
      await client.exchangeKeys();
      await client.logIn('alice', alice.pair);
      await client.openShell();
      await opened.future;
      await clock.elapse(const Duration(minutes: 10));
      // the server speaks first: its KEXINIT goes before the data, which
      // goes under the new keys
      session.add(utf8.encode('late'));
      final between = await client.exchangeKeys(first: false);
      expect(between, isEmpty);
      final data = SshReader(await client.expectNext(SshMsg.channelData))
        ..byte()
        ..uint32();
      expect(utf8.decode(data.string()), 'late');
      expect(server.connections.single.transport.serverKeyExchanges, 1);
    });

    test('after the bytes of the limit it reads', () async {
      final server = await serve(
        auth: acceptKeys([alice]),
        onSession: (session) => session.done,
        rekeyLimit: const SshRekeyLimit(bytes: 48 * 100),
      );
      final client = await RawClient.connect(server);
      await client.exchangeKeys();
      final transport = server.connections.single.transport;
      // 98 IGNOREs and a message answered, 48 bytes each: under the limit
      for (var i = 0; i < 98; i++) {
        client.send(ignore);
      }
      client.send(unknown);
      final answer = await client.next();
      expect(answer?[0], SshMsg.unimplemented);
      expect(transport.serverKeyExchanges, 0);
      // an IGNORE, answered by nothing, reaches it: the server starts the
      // exchange on reading it
      client.send(ignore);
      final kexInit = await client.next();
      expect(kexInit?[0], SshMsg.kexInit);
      await client.exchangeKeys(first: false, serverKexInit: kexInit);
      expect(transport.serverKeyExchanges, 1);
      await client.logIn('alice', alice.pair);
    });

    test('after the bytes of the limit it sends', () async {
      late SshSession session;
      final opened = Completer<void>();
      final server = await serve(
        auth: acceptKeys([alice]),
        onSession: (s) {
          session = s;
          opened.complete();
          return s.done;
        },
        rekeyLimit: const SshRekeyLimit(bytes: 64 << 10),
      );
      final client = await RawClient.connect(server);
      await client.exchangeKeys();
      await client.logIn('alice', alice.pair);
      await client.openShell();
      await opened.future;
      final transport = server.connections.single.transport;
      // 128 KiB of output, the client sending nothing meanwhile
      session.add(Uint8List(128 << 10));
      int dataLength(Uint8List p) =>
          (SshReader(p)
                ..byte()
                ..uint32())
              .string()
              .length;
      // the limit's bytes of data under the old keys, packets of 32 KiB
      var before = 0;
      Uint8List? kexInit;
      while (kexInit == null) {
        final p = (await client.next())!;
        if (p[0] == SshMsg.kexInit) {
          kexInit = p;
        } else {
          expect(p[0], SshMsg.channelData);
          before += dataLength(p);
        }
      }
      expect(before, 64 << 10);
      final between = await client.exchangeKeys(
        first: false,
        serverKexInit: kexInit,
      );
      expect(between, isEmpty);
      expect(transport.serverKeyExchanges, 1);
      // the rest under the new keys
      var after = 0;
      while (before + after < 128 << 10) {
        after += dataLength(await client.expectNext(SshMsg.channelData));
      }
      expect(after, 64 << 10);
    });

    test('before the packets of either way reach the most', () async {
      SshTransport.maxPackets = 20;
      addTearDown(() => SshTransport.maxPackets = 1 << 31);
      final server = await serve(
        auth: acceptKeys([alice]),
        onSession: (session) => session.done,
      );
      final client = await RawClient.connect(server);
      await client.exchangeKeys();
      final transport = server.connections.single.transport;
      // the server sent its NEWKEYS under the old keys, EXT_INFO not asked
      for (var i = 0; i < 19; i++) {
        client.send(unknown);
      }
      for (var i = 0; i < 19; i++) {
        await client.expectNext(SshMsg.unimplemented);
      }
      expect(transport.serverKeyExchanges, 0);
      client.send(unknown);
      await client.exchangeKeys(first: false);
      expect(transport.serverKeyExchanges, 1);
    });

    test('a dartssh2 client, losing nothing', () async {
      final server = await serve(
        auth: acceptKeys([alice]),
        onSession: (s) async {
          await for (final bytes in s.input) {
            s.add(bytes); // an echo
            if (utf8.decode(bytes, allowMalformed: true).contains('end')) {
              break;
            }
          }
        },
        rekeyLimit: const SshRekeyLimit(bytes: 16 << 10),
      );
      final client = await connect(server, identities: [alice.pair]);
      final shell = await client.shell();
      final out = shell.stdout.asBroadcastStream();
      final sent = StringBuffer();
      for (var i = 0; i < 2000; i++) {
        sent.write('line $i of the echo, rekeyed along the way\n');
      }
      final echo = readUntil(
        out,
        (s) => s.contains('end'),
        timeout: const Duration(seconds: 30),
      );
      shell
        ..write(utf8.encode('$sent'))
        ..write(utf8.encode('end'));
      expect(await echo, '${sent}end');
      final transport = server.connections.single.transport;
      expect(transport.serverKeyExchanges, greaterThan(0));
      await shell.done;
      expect(shell.exitCode, 0);
    });
  });

  group('connections that have not logged in', () {
    test('beyond the most are closed at once', () async {
      final server = await serve(
        auth: acceptKeys([alice]),
        onSession: (session) => session.done,
        maxUnauthenticated: 2,
      );
      Future<RawClient> accepted() async {
        final client = await RawClient.connect(server)
          ..version();
        expect((await client.next())![0], SshMsg.kexInit);
        return client;
      }

      final first = await RawClient.connect(server);
      await first.exchangeKeys();
      final second = await accepted();
      final third = await RawClient.connect(server);
      expect(await third.closes(const Duration(seconds: 5)), isTrue);
      expect(third.serverVersion, isNull);
      expect(server.refused, 1);
      // one logs in: there is room again
      await first.logIn('alice', alice.pair);
      final fourth = await accepted();
      // one goes away: room again, once the server has seen it go
      second.socket.destroy();
      await waitUntil(
        () => server.connections.length == 2,
        'the server to see the second go',
      );
      await accepted();
      expect(server.connections, hasLength(3));
      // full again
      final sixth = await RawClient.connect(server);
      expect(await sixth.closes(const Duration(seconds: 5)), isTrue);
      expect(server.refused, 2);
      fourth.socket.destroy();
    });

    test('at least one must be let in', () async {
      await expectLater(
        serve(
          auth: acceptKeys([alice]),
          onSession: (session) => session.done,
          maxUnauthenticated: 0,
        ),
        throwsRangeError,
      );
    });
  });
}
