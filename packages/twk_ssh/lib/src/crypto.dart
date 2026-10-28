/// The algorithms the server speaks: the key exchange, the ciphers and the
/// MACs, and the hashes and random bytes they need.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:cipherlib/cipherlib.dart' show MLKEM;
import 'package:meta/meta.dart';
import 'package:pinenacl/tweetnacl.dart';
import 'package:pointycastle/export.dart';

import 'wire.dart';

final _random = Random.secure();

/// [n] bytes from the system's secure random source.
Uint8List randomBytes(int n) {
  final out = Uint8List(n);
  for (var i = 0; i < n; i++) {
    out[i] = _random.nextInt(256);
  }
  return out;
}

/// Whether [a] and [b] hold the same bytes, in a time that depends only
/// on their length: every byte is compared whatever the first difference.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// The SHA-256 digest of [data].
Uint8List sha256(List<int> data) =>
    SHA256Digest().process(Uint8List.fromList(data));

/// The hybrid post-quantum key exchange: ML-KEM-768 (FIPS 203) and
/// X25519, combined with SHA-256 (RFC 10042).
const mlkem768x25519 = 'mlkem768x25519-sha256';

/// The key exchange methods, in the order the server prefers them: the
/// hybrid [mlkem768x25519], then curve25519-sha256 (RFC 8731) under both
/// of its names.
const List<String> kexAlgorithms = [
  mlkem768x25519,
  'curve25519-sha256',
  'curve25519-sha256@libssh.org',
];

/// Advertised by a server that does strict key exchange (OpenSSH's
/// PROTOCOL, the Terrapin countermeasure); the client's counterpart.
const strictKexServer = 'kex-strict-s-v00@openssh.com';

/// Advertised by a client that does strict key exchange.
const strictKexClient = 'kex-strict-c-v00@openssh.com';

/// Advertised by a client that takes SSH_MSG_EXT_INFO (RFC 8308).
const extInfoClient = 'ext-info-c';

/// A curve25519 key pair for one key exchange.
final class X25519 {
  /// A key pair of a secret from [randomBytes].
  X25519() : _secret = randomBytes(32) {
    TweetNaCl.crypto_scalarmult_base(publicKey, _secret);
  }

  final Uint8List _secret;

  /// The public key, sent to the client.
  final publicKey = Uint8List(32);

  /// The shared secret with the client's [peer] key. Throws
  /// [SshProtocolException] for a key of the wrong length or one of small
  /// order, whose secret is all zeros (RFC 8731 §3).
  Uint8List agree(Uint8List peer) {
    if (peer.length != 32) {
      throw const SshProtocolException(
        'curve25519 key of the wrong length',
        SshDisconnect.keyExchangeFailed,
      );
    }
    final shared = Uint8List(32);
    TweetNaCl.crypto_scalarmult(shared, _secret, Uint8List.fromList(peer));
    if (shared.every((b) => b == 0)) {
      throw const SshProtocolException(
        'curve25519 key of small order',
        SshDisconnect.keyExchangeFailed,
      );
    }
    return shared;
  }
}

/// The server's side of one key exchange: what it answers the client's
/// init message with, and the shared secret.
typedef KexAgreement = ({Uint8List reply, Uint8List secret});

/// The server's side of the exchange [name], one of [kexAlgorithms], with
/// the client's init message's key [init] (Q_C, or C_INIT of the hybrid):
/// the server's reply (Q_S, or S_REPLY) and K encoded as the exchange
/// hash and the key derivation take it, an mpint for curve25519-sha256
/// (RFC 8731) and a string for the hybrid (RFC 10042 §2.4, §2.5). Throws
/// [SshProtocolException] for a key that fails its checks.
KexAgreement agree(String name, Uint8List init) {
  final ephemeral = X25519();
  if (name != mlkem768x25519) {
    final secret = ephemeral.agree(init);
    return (
      reply: ephemeral.publicKey,
      secret: (SshWriter()..mpint(secret)).takeBytes(),
    );
  }
  // C_INIT = C_PK2 || C_PK1: the ML-KEM encapsulation key, then X25519's
  if (init.length != mlkem768EncapsulationKeyLength + 32) {
    throw const SshProtocolException(
      'an mlkem768x25519 key of the wrong length',
      SshDisconnect.keyExchangeFailed,
    );
  }
  final ek = Uint8List.sublistView(init, 0, mlkem768EncapsulationKeyLength);
  final classical = ephemeral.agree(
    Uint8List.sublistView(init, mlkem768EncapsulationKeyLength),
  );
  final (:ciphertext, :secret) = mlkem768Encapsulate(ek);
  return (
    // S_REPLY = S_CT2 || S_PK1
    reply: Uint8List.fromList([...ciphertext, ...ephemeral.publicKey]),
    // K = SHA-256(K_PQ || K_CL), as a string
    secret: (SshWriter()..string(sha256([...secret, ...classical])))
        .takeBytes(),
  );
}

/// The length of an ML-KEM-768 encapsulation key, in bytes.
const mlkem768EncapsulationKeyLength = 1184;

/// The length of an ML-KEM-768 ciphertext, in bytes.
const mlkem768CiphertextLength = 1088;

final _mlkem768 = MLKEM.kem768();

/// ML-KEM-768's encapsulation (FIPS 203), the part the server does: a
/// shared secret encapsulated for [ek], from the 32 random bytes [m],
/// fresh from [randomBytes] unless a test gives them (ACVP's vectors).
/// Throws [SshProtocolException] for a key that fails the checks of
/// FIPS 203 §7.2, its length and its modulus check.
///
/// The arithmetic is cipherlib's. `ML-KEM.Encaps` is `Encaps_internal` of
/// fresh random bytes (FIPS 203 Algorithms 17 and 20), so its `$encaps`,
/// `Encaps_internal`, is what is called either way: NIST's vectors hold
/// the very call the server makes.
({Uint8List ciphertext, Uint8List secret}) mlkem768Encapsulate(
  Uint8List ek, {
  @visibleForTesting Uint8List? m,
}) {
  if (ek.length != mlkem768EncapsulationKeyLength) {
    throw const SshProtocolException(
      'an ML-KEM-768 key of the wrong length',
      SshDisconnect.keyExchangeFailed,
    );
  }
  // The modulus check: ByteEncode12(ByteDecode12(ek)) is ek, so each of
  // the 768 12-bit coefficients of t is below q = 3329. ek is public.
  for (var i = 0; i < 3 * 384; i += 3) {
    final a = ek[i] | (ek[i + 1] & 0x0F) << 8;
    final b = ek[i + 1] >> 4 | ek[i + 2] << 4;
    if (a >= 3329 || b >= 3329) {
      throw const SshProtocolException(
        'an ML-KEM-768 key that fails its modulus check',
        SshDisconnect.keyExchangeFailed,
      );
    }
  }
  final r = _mlkem768.$encaps(ek, m ?? randomBytes(32));
  return (ciphertext: r.cipherText, secret: r.sharedSecret.bytes);
}

/// A cipher by its SSH name.
final class CipherSpec {
  const CipherSpec._(this.name, this.keyLength);

  /// Its SSH name: `aes128-ctr`, ...
  final String name;

  /// The length of its key, in bytes.
  final int keyLength;

  /// The block a packet's length is a multiple of, in bytes.
  int get blockSize => 16;

  /// The length of its initial counter, in bytes.
  int get ivLength => 16;

  /// The ciphers spoken, in the order the server prefers them.
  static const all = [
    CipherSpec._('aes128-ctr', 16),
    CipherSpec._('aes192-ctr', 24),
    CipherSpec._('aes256-ctr', 32),
  ];

  /// The cipher keyed with [key], its counter starting at [iv].
  StreamCipher create(Uint8List key, Uint8List iv) =>
      CTRStreamCipher(AESEngine())
        ..init(true, ParametersWithIV(KeyParameter(key), iv));
}

/// A MAC by its SSH name; [etm] when it covers the encrypted packet
/// (OpenSSH's encrypt-then-MAC), the plain one otherwise.
final class MacSpec {
  const MacSpec._(this.name, this.keyLength, this.etm);

  /// Its SSH name: `hmac-sha2-256`, ...
  final String name;

  /// The length of its key, in bytes.
  final int keyLength;

  /// Whether it covers the encrypted packet.
  final bool etm;

  /// The length of the MAC, in bytes: as long as its key.
  int get length => keyLength;

  /// The MACs spoken, in the order the server prefers them.
  static const all = [
    MacSpec._('hmac-sha2-256-etm@openssh.com', 32, true),
    MacSpec._('hmac-sha2-512-etm@openssh.com', 64, true),
    MacSpec._('hmac-sha2-256', 32, false),
    MacSpec._('hmac-sha2-512', 64, false),
  ];

  /// The MAC keyed with [key].
  Mac create(Uint8List key) =>
      (keyLength == 32 ? HMac(SHA256Digest(), 64) : HMac(SHA512Digest(), 128))
        ..init(KeyParameter(key));
}

/// The cipher and MAC one direction's packets go through once keys are
/// in effect.
final class DirectionKeys {
  /// Packets through [cipher] and [mac], encrypt-then-MAC with [etm].
  DirectionKeys(this.cipher, this.mac, {required this.etm});

  /// Encrypts or decrypts the packets.
  final StreamCipher cipher;

  /// Authenticates the packets.
  final Mac mac;

  /// Whether [mac] covers the encrypted packet, its length left plain.
  final bool etm;

  /// The block a packet's length is a multiple of, in bytes.
  int get blockSize => 16;

  /// The length of a packet's MAC, in bytes.
  int get macLength => mac.macSize;
}
