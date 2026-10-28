import 'dart:collection';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_ssh/src/crypto.dart';
import 'package:twk_ssh/src/packet.dart';
import 'package:twk_ssh/src/wire.dart';

/// The keys of one direction for [cipher] and [mac], both ends' copies.
(DirectionKeys, DirectionKeys) keysFor(CipherSpec cipher, MacSpec mac) {
  final key = Uint8List.fromList(List.generate(cipher.keyLength, (i) => i));
  final iv = Uint8List.fromList(List.generate(16, (i) => 100 + i));
  final macKey = Uint8List.fromList(List.generate(mac.keyLength, (i) => i * 3));
  DirectionKeys make() => DirectionKeys(
    cipher.create(key, iv),
    mac.create(macKey),
    etm: mac.etm,
  );
  return (make(), make());
}

/// A packet without keys: [length], [pad] and [payload] as given.
Uint8List plain(int length, int pad, List<int> payload) {
  final out = Uint8List(5 + length);
  out.buffer.asByteData().setUint32(0, length);
  out[4] = pad;
  out.setRange(5, 5 + payload.length, payload);
  return out;
}

/// A list that counts the reads of its elements.
final class CountingList extends ListBase<int> {
  CountingList(this._bytes);

  final List<int> _bytes;
  var reads = 0;

  @override
  int get length => _bytes.length;

  @override
  set length(int value) => throw UnsupportedError('fixed');

  @override
  int operator [](int index) {
    reads++;
    return _bytes[index];
  }

  @override
  void operator []=(int index, int value) => _bytes[index] = value;
}

Matcher throwsProtocol([int reason = SshDisconnect.protocolError]) => throwsA(
  isA<SshProtocolException>().having((e) => e.reason, 'reason', reason),
);

void main() {
  group('round trip', () {
    test('without keys', () {
      final writer = PacketWriter();
      final reader = PacketReader();
      for (var n = 1; n < 300; n += 7) {
        final payload = List.generate(n, (i) => i & 0xFF);
        final packet = writer.encode(payload);
        expect((packet.length) % 8, 0);
        reader.add(packet);
        expect(reader.next(), payload);
      }
      expect(reader.next(), isNull);
      expect(reader.sequence, writer.sequence);
    });

    for (final cipher in CipherSpec.all) {
      for (final mac in MacSpec.all) {
        test('${cipher.name} with ${mac.name}, split anywhere', () {
          final (out, into) = keysFor(cipher, mac);
          final writer = PacketWriter()..rekey(out);
          final reader = PacketReader()..rekey(into);
          final payloads = [
            for (var n = 1; n < 600; n += 37)
              List.generate(n, (i) => (n + i) & 0xFF),
          ];
          final wire = [for (final p in payloads) ...writer.encode(p)];
          final got = <List<int>>[];
          // a byte at a time: every split of a packet is met
          for (final b in wire) {
            reader.add([b]);
            for (var p = reader.next(); p != null; p = reader.next()) {
              got.add(p);
            }
          }
          expect(got, payloads);
        });
      }
    }
  });

  group('lengths are checked before the packet is waited for', () {
    test('longer than the maximum, without keys: from its first 4 bytes', () {
      final reader = PacketReader()
        ..add(Uint8List(4)..buffer.asByteData().setUint32(0, 0x7FFFFFFF));
      expect(reader.next, throwsProtocol());
    });

    test('the first aligned length over the maximum is refused', () {
      Uint8List header(int length) =>
          Uint8List(4)..buffer.asByteData().setUint32(0, length);
      final over = PacketReader()..add(header(maxPacketLength + 4));
      expect(over.next, throwsProtocol());
      final at = PacketReader()..add(header(maxPacketLength - 4));
      expect(at.next(), isNull); // taken: it waits for the rest
    });

    test('longer than the maximum, encrypted: from its first block', () {
      final (out, into) = keysFor(CipherSpec.all.first, MacSpec.all[2]);
      final writer = PacketWriter()..rekey(out);
      final reader = PacketReader()..rekey(into);
      final packet = writer.encode(List.filled(100, 1));
      final length = packet.length - 4 - 32;
      // CTR: flipping ciphertext bits flips the same plaintext bits, so
      // the first block now decrypts to a length of 0x7FFFFFFF
      final forged = Uint8List.fromList(packet.sublist(0, 16));
      final want = [0x7F, 0xFF, 0xFF, 0xFF];
      final has = Uint8List(4)..buffer.asByteData().setUint32(0, length);
      for (var i = 0; i < 4; i++) {
        forged[i] ^= has[i] ^ want[i];
      }
      reader.add(forged);
      expect(reader.next, throwsProtocol());
    });

    test('longer than the maximum, encrypt-then-MAC: from its length', () {
      final (_, into) = keysFor(CipherSpec.all.first, MacSpec.all.first);
      final reader = PacketReader()
        ..rekey(into)
        ..add(Uint8List(4)..buffer.asByteData().setUint32(0, 1 << 30));
      expect(reader.next, throwsProtocol());
    });

    test('too short', () {
      for (final length in [0, 4, 5]) {
        final reader = PacketReader()..add(plain(length, 0, const []));
        expect(reader.next, throwsProtocol(), reason: '$length');
      }
    });

    test('too short, encrypt-then-MAC: a length of 0, aligned', () {
      // 0 is a multiple of the block; the MAC isn't waited for
      final (_, into) = keysFor(CipherSpec.all.first, MacSpec.all.first);
      final reader = PacketReader()
        ..rekey(into)
        ..add(Uint8List(4));
      expect(reader.next, throwsProtocol());
    });

    test('not a multiple of the block, its padding right', () {
      // 13 + 4 bytes: not a multiple of 8
      final reader = PacketReader()..add(plain(13, 4, List.filled(8, 1)));
      expect(reader.next, throwsProtocol());
      final (out, into) = keysFor(CipherSpec.all.first, MacSpec.all.first);
      final etm = PacketReader()
        ..rekey(into)
        ..add(Uint8List(4)..buffer.asByteData().setUint32(0, 40));
      expect(etm.next, throwsProtocol()); // 40 is no multiple of 16
      expect(out, isNotNull);
    });
  });

  group('padding', () {
    test('of fewer than 4 bytes is refused', () {
      final reader = PacketReader()..add(plain(12, 3, List.filled(8, 9)));
      expect(reader.next, throwsProtocol());
    });

    test('that leaves no payload is refused', () {
      final reader = PacketReader()..add(plain(12, 11, const []));
      expect(reader.next, throwsProtocol());
    });

    test('of 4 bytes leaves the rest as the payload', () {
      final reader = PacketReader()..add(plain(12, 4, [1, 2, 3, 4, 5, 6, 7]));
      expect(reader.next(), [1, 2, 3, 4, 5, 6, 7]);
    });
  });

  group('MAC', () {
    for (final mac in MacSpec.all) {
      test('a flipped bit fails ${mac.name}', () {
        for (final at in ['ciphertext', 'mac']) {
          final (out, into) = keysFor(CipherSpec.all.first, mac);
          final writer = PacketWriter()..rekey(out);
          final reader = PacketReader()..rekey(into);
          final packet = writer.encode(List.filled(40, 7));
          packet[at == 'mac' ? packet.length - 1 : 20] ^= 1;
          reader.add(packet);
          expect(
            reader.next,
            throwsProtocol(SshDisconnect.macError),
            reason: at,
          );
        }
      });
    }

    test('a packet replayed under the next number fails', () {
      final (out, into) = keysFor(CipherSpec.all.first, MacSpec.all.first);
      final writer = PacketWriter()..rekey(out);
      final reader = PacketReader()..rekey(into);
      final packet = writer.encode([1, 2, 3]);
      reader.add(packet);
      expect(reader.next(), [1, 2, 3]);
      reader.add(packet);
      expect(reader.next, throwsProtocol(SshDisconnect.macError));
    });

    test('is compared reading every byte, whatever differs first', () {
      final a = CountingList(List.filled(32, 0));
      final b = CountingList(List.filled(32, 0)..[0] = 1);
      expect(constantTimeEquals(a, b), isFalse);
      expect(a.reads, 32);
      expect(b.reads, 32);
      expect(constantTimeEquals(List.filled(3, 1), List.filled(3, 1)), isTrue);
      expect(constantTimeEquals(List.filled(3, 1), List.filled(4, 1)), isFalse);
    });
  });

  test('sequence numbers wrap at 2^32, the MAC with them', () {
    final (out, into) = keysFor(CipherSpec.all.last, MacSpec.all.last);
    final writer = PacketWriter()
      ..rekey(out)
      ..sequence = 0xFFFFFFFF;
    final reader = PacketReader()
      ..rekey(into)
      ..sequence = 0xFFFFFFFF;
    for (final p in [
      [1],
      [2],
      [3],
    ]) {
      reader.add(writer.encode(p));
      expect(reader.next(), p);
    }
    expect(writer.sequence, 2);
    expect(reader.sequence, 2);
  });

  test('a strict reset numbers the next packet 0', () {
    final (out, into) = keysFor(CipherSpec.all.first, MacSpec.all.first);
    final writer = PacketWriter()..rekey(out);
    final reader = PacketReader()
      ..rekey(into)
      ..add(writer.encode([1]));
    expect(reader.next(), [1]);
    writer.resetSequence();
    reader.add(writer.encode([2]));
    // the reader still counts from 1: the MAC doesn't match
    expect(reader.next, throwsProtocol(SshDisconnect.macError));
  });
}
