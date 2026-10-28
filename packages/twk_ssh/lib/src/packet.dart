/// The binary packet protocol (RFC 4253 §6): payloads framed with their
/// length and random padding, encrypted and authenticated once keys are in
/// effect, numbered in sequence.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'crypto.dart';
import 'wire.dart';

/// The longest packet taken from a client, as OpenSSH's PACKET_MAX_SIZE.
const int maxPacketLength = 256 * 1024;

Uint8List _sequenceBytes(int sequence) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, sequence);

/// Packets to the client.
final class PacketWriter {
  DirectionKeys? _keys;

  /// The number of the next packet, from 0, wrapping at 2^32.
  int get sequence => _sequence;
  var _sequence = 0;

  @visibleForTesting
  set sequence(int value) => _sequence = value;

  /// Bytes sent since the keys last changed ([rekey]), MACs included.
  int get bytes => _bytes;
  var _bytes = 0;

  /// Packets sent since the keys last changed ([rekey]).
  int get packets => _packets;
  var _packets = 0;

  /// Packets from now on go through [keys].
  void rekey(DirectionKeys keys) {
    _keys = keys;
    _bytes = 0;
    _packets = 0;
  }

  /// Under strict key exchange, the packet after NEWKEYS is number 0.
  void resetSequence() => _sequence = 0;

  /// [payload] as a packet.
  Uint8List encode(List<int> payload) {
    final keys = _keys;
    final block = keys == null ? 8 : keys.blockSize;
    final etm = keys?.etm ?? false;
    // what the block size must divide: all of the packet, or all but the
    // length when that goes unencrypted
    final covered = (etm ? 1 : 5) + payload.length;
    var pad = block - covered % block;
    if (pad < 4) {
      pad += block;
    }
    final length = 1 + payload.length + pad;
    final macLength = keys?.macLength ?? 0;
    final out = Uint8List(4 + length + macLength)
      ..[4] = pad
      ..setRange(5, 5 + payload.length, payload)
      ..setRange(5 + payload.length, 4 + length, randomBytes(pad));
    out.buffer.asByteData().setUint32(0, length);
    if (keys != null) {
      final mac = keys.mac..reset();
      if (etm) {
        keys.cipher.processBytes(out, 4, length, out, 4);
        mac
          ..update(_sequenceBytes(_sequence), 0, 4)
          ..update(out, 0, 4 + length);
      } else {
        mac
          ..update(_sequenceBytes(_sequence), 0, 4)
          ..update(out, 0, 4 + length);
        keys.cipher.processBytes(out, 0, 4 + length, out, 0);
      }
      mac.doFinal(out, 4 + length);
    }
    _sequence = (_sequence + 1) & 0xFFFFFFFF;
    _bytes += out.length;
    _packets++;
    return out;
  }
}

/// Packets from the client: bytes go in as they are read ([add]), whole
/// payloads come out ([next]).
///
/// A packet's length is checked as soon as it is known, before anything
/// is allocated for it or more of it is waited for: no longer than
/// [maxPacketLength], aligned to the cipher's block, room for the padding.
/// The MAC is checked in constant time before the padding is read; with
/// encrypt-then-MAC, before anything is decrypted.
final class PacketReader {
  DirectionKeys? _keys;

  var _buffer = Uint8List(1 << 14);
  var _start = 0;
  var _end = 0;

  /// The first block of a packet whose rest hasn't arrived, decrypted, and
  /// the length it holds.
  Uint8List? _first;
  var _length = 0;

  /// The number of the next packet, from 0, wrapping at 2^32.
  int get sequence => _sequence;
  var _sequence = 0;

  @visibleForTesting
  set sequence(int value) => _sequence = value;

  /// Bytes taken and not yet part of a payload returned.
  int get buffered => _end - _start;

  /// Bytes of the packets [next] returned since the keys last changed
  /// ([rekey]), MACs included.
  int get bytes => _bytes;
  var _bytes = 0;

  /// Packets [next] returned since the keys last changed ([rekey]).
  int get packets => _packets;
  var _packets = 0;

  /// Packets after the one [next] returned last go through [keys].
  void rekey(DirectionKeys keys) {
    _keys = keys;
    _bytes = 0;
    _packets = 0;
  }

  /// Under strict key exchange, the packet after NEWKEYS is number 0.
  void resetSequence() => _sequence = 0;

  /// Takes [bytes] read from the socket.
  void add(List<int> bytes) {
    if (_end + bytes.length > _buffer.length) {
      final kept = _end - _start;
      if (kept + bytes.length <= _buffer.length) {
        _buffer.setRange(0, kept, _buffer, _start);
      } else {
        var size = _buffer.length * 2;
        while (size < kept + bytes.length) {
          size *= 2;
        }
        _buffer = Uint8List(size)..setRange(0, kept, _buffer, _start);
      }
      _start = 0;
      _end = kept;
    }
    _buffer.setRange(_end, _end + bytes.length, bytes);
    _end += bytes.length;
  }

  /// The payload of the next packet, or null until all of it is here.
  /// Throws [SshProtocolException] for a packet that is malformed or fails
  /// its MAC.
  Uint8List? next() {
    final keys = _keys;
    final block = keys == null ? 8 : keys.blockSize;
    final etm = keys?.etm ?? false;
    if (_first == null) {
      final head = keys == null || etm ? 4 : block;
      if (buffered < head) {
        return null;
      }
      final first = Uint8List.fromList(
        Uint8List.sublistView(_buffer, _start, _start + head),
      );
      if (keys != null && !etm) {
        keys.cipher.processBytes(first, 0, head, first, 0);
      }
      final length = first.buffer.asByteData().getUint32(0);
      // a length byte, a byte of payload, four of padding
      if (length < 6 || length > maxPacketLength) {
        throw SshProtocolException('a packet of $length bytes');
      }
      if ((etm ? length : length + 4) % block != 0) {
        throw SshProtocolException('a packet of $length bytes, unaligned');
      }
      _first = first;
      _length = length;
    }
    final length = _length;
    final macLength = keys?.macLength ?? 0;
    if (buffered < 4 + length + macLength) {
      return null;
    }
    final first = _first!;
    _first = null;
    final packet = Uint8List(4 + length);
    if (keys == null) {
      packet.setRange(0, 4 + length, _buffer, _start);
    } else if (etm) {
      packet.setRange(0, 4 + length, _buffer, _start);
      _checkMac(keys, packet, _start + 4 + length);
      keys.cipher.processBytes(packet, 4, length, packet, 4);
    } else {
      packet.setRange(0, first.length, first);
      keys.cipher.processBytes(
        _buffer,
        _start + first.length,
        4 + length - first.length,
        packet,
        first.length,
      );
      _checkMac(keys, packet, _start + 4 + length);
    }
    _start += 4 + length + macLength;
    if (_start == _end) {
      _start = _end = 0;
    }
    _sequence = (_sequence + 1) & 0xFFFFFFFF;
    _bytes += 4 + length + macLength;
    _packets++;
    final pad = packet[4];
    if (pad < 4 || pad > length - 2) {
      throw SshProtocolException('$pad bytes of padding in $length');
    }
    return Uint8List.sublistView(packet, 5, 4 + length - pad);
  }

  void _checkMac(DirectionKeys keys, Uint8List packet, int macAt) {
    final mac = keys.mac..reset();
    final expected = Uint8List(keys.macLength);
    mac
      ..update(_sequenceBytes(_sequence), 0, 4)
      ..update(packet, 0, packet.length)
      ..doFinal(expected, 0);
    final got = Uint8List.sublistView(_buffer, macAt, macAt + keys.macLength);
    if (!constantTimeEquals(expected, got)) {
      throw const SshProtocolException('MAC mismatch', SshDisconnect.macError);
    }
  }
}
