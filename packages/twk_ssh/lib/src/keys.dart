/// Keys: the server's host keys, and the public keys clients log in with,
/// as an authorized_keys file lists them.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:pinenacl/ed25519.dart' as ed25519;
import 'package:pointycastle/ecc/ecc_fp.dart' as fp;
import 'package:pointycastle/export.dart';

import 'crypto.dart';
import 'wire.dart';

/// The fingerprint OpenSSH shows for [blob], a public key in the SSH
/// encoding: `SHA256:` and the base64 of its hash, unpadded.
String _fingerprint(Uint8List blob) =>
    'SHA256:${base64.encode(sha256(blob)).replaceAll('=', '')}';

/// A key the server proves itself with: ssh-ed25519, RSA (signing
/// rsa-sha2-256) or ECDSA on nistp256, nistp384 or nistp521.
final class SshHostKey {
  SshHostKey._(this._pair);

  /// The first key of [pem], an OpenSSH, PKCS#1 or SEC1 private key,
  /// decrypted with [passphrase] if it is encrypted. Throws
  /// [FormatException] for one that holds no key of a supported type.
  factory SshHostKey.fromPem(String pem, {String? passphrase}) {
    final List<SSHKeyPair> pairs;
    try {
      pairs = SSHKeyPair.fromPem(pem, passphrase);
    } on Object catch (e) {
      throw FormatException('not a private key: $e');
    }
    for (final pair in pairs) {
      if (_algorithms.contains(pair.type)) {
        return SshHostKey._(pair);
      }
    }
    throw const FormatException('no host key of a supported type');
  }

  /// A new ssh-ed25519 key.
  factory SshHostKey.generate() {
    final key = ed25519.SigningKey.generate();
    return SshHostKey._(
      OpenSSHEd25519KeyPair(
        Uint8List.fromList(key.verifyKey.asTypedList),
        Uint8List.fromList(key.asTypedList),
        'twk_ssh host key',
      ),
    );
  }

  /// The key in the file at [path] (see [SshHostKey.fromPem]).
  static Future<SshHostKey> load(String path, {String? passphrase}) async =>
      SshHostKey.fromPem(
        await File(path).readAsString(),
        passphrase: passphrase,
      );

  /// The key in the file at [path]; when there is none, a new ssh-ed25519
  /// key written there, readable by its owner only (mode 0600; on Windows
  /// the directory's permissions apply).
  static Future<SshHostKey> loadOrGenerate(String path) async {
    final file = File(path);
    if (file.existsSync()) {
      return SshHostKey.fromPem(file.readAsStringSync());
    }
    final key = SshHostKey.generate();
    // created empty and restricted before the key goes in
    await file.create(recursive: true, exclusive: true);
    if (!Platform.isWindows) {
      final chmod = await Process.run('chmod', ['600', path]);
      final mode = file.statSync().mode;
      if (chmod.exitCode != 0 || mode & 0x3F != 0) {
        await file.delete();
        throw FileSystemException('cannot make the file private', path);
      }
    }
    await file.writeAsString(key.toPem(), flush: true);
    return key;
  }

  static const _algorithms = {
    'ssh-ed25519',
    'rsa-sha2-256',
    'ecdsa-sha2-nistp256',
    'ecdsa-sha2-nistp384',
    'ecdsa-sha2-nistp521',
  };

  final SSHKeyPair _pair;

  /// The host key algorithm it signs with.
  String get algorithm => _pair.type;

  /// The public key in the SSH encoding.
  Uint8List get publicKey => _pair.toPublicKey().encode();

  /// As OpenSSH shows it: `SHA256:...`.
  String get fingerprint => _fingerprint(publicKey);

  /// The public key as a line of an authorized_keys or known_hosts file.
  String get publicKeyLine => '${_pair.name} ${base64.encode(publicKey)}';

  /// The private key in OpenSSH's format, unencrypted.
  String toPem() => _pair.toPem();

  /// The signature of [data] in the SSH encoding.
  Uint8List sign(Uint8List data) => _pair.sign(data).encode();
}

/// A public key a client logs in with, in the SSH encoding ([blob]):
/// ssh-ed25519, ssh-rsa (2048 bits or more, signing with rsa-sha2-256 or
/// rsa-sha2-512), or ECDSA on nistp256, nistp384 or nistp521. Equal when
/// the encodings are.
final class SshPublicKey {
  SshPublicKey._(this.type, this.blob, this._verify);

  /// The key [blob] holds; throws [FormatException] for one malformed or of
  /// a type not supported.
  factory SshPublicKey.decode(Uint8List blob) {
    try {
      final r = SshReader(blob);
      final type = r.utf8String();
      switch (type) {
        case 'ssh-ed25519':
          final key = r.string();
          _end(r, key.length == 32);
          return SshPublicKey._(
            type,
            blob,
            (algorithm, data, signature) =>
                algorithm == type && _verifyEd25519(key, data, signature),
          );
        case 'ssh-rsa':
          final e = _bigInt(r.mpint());
          final n = _bigInt(r.mpint());
          _end(r, n.bitLength >= 2048 && e > BigInt.one);
          return SshPublicKey._(
            type,
            blob,
            (algorithm, data, signature) =>
                _verifyRsa(n, e, algorithm, data, signature),
          );
        case 'ecdsa-sha2-nistp256' ||
            'ecdsa-sha2-nistp384' ||
            'ecdsa-sha2-nistp521':
          final curveName = type.substring('ecdsa-sha2-'.length);
          final curve = switch (curveName) {
            'nistp256' => ECCurve_secp256r1(),
            'nistp384' => ECCurve_secp384r1(),
            _ => ECCurve_secp521r1(),
          };
          _end(r, r.utf8String() == curveName);
          final q = _point(curve, r.string());
          _end(r, true);
          return SshPublicKey._(
            type,
            blob,
            (algorithm, data, signature) =>
                algorithm == type &&
                _verifyEcdsa(curve, q, curveName, data, signature),
          );
      }
      throw FormatException('a key of type $type');
    } on SshProtocolException catch (e) {
      throw FormatException(e.message);
    }
  }

  /// The key of [line], `type base64 [comment]` as an authorized_keys file
  /// has it; null for a line that isn't one.
  static SshPublicKey? parse(String line) {
    final fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length < 2) {
      return null;
    }
    try {
      final key = SshPublicKey.decode(base64.decode(fields[1]));
      return key.type == fields[0] ? key : null;
    } on FormatException {
      return null;
    }
  }

  /// Its type: `ssh-ed25519`, `ssh-rsa`, `ecdsa-sha2-nistp256`, ...
  final String type;

  /// The key in the SSH encoding, as a client sends it and a public key
  /// line holds it in base64.
  final Uint8List blob;

  final bool Function(String algorithm, Uint8List data, Uint8List signature)
  _verify;

  /// As OpenSSH shows it: `SHA256:...`.
  String get fingerprint => _fingerprint(blob);

  /// The signature algorithms it may be used with.
  List<String> get algorithms =>
      type == 'ssh-rsa' ? const ['rsa-sha2-512', 'rsa-sha2-256'] : [type];

  /// Whether [signature], in the SSH encoding, signs [data] with this key
  /// in [algorithm].
  bool verify(String algorithm, Uint8List data, Uint8List signature) {
    try {
      return _verify(algorithm, data, signature);
    } on Object {
      return false;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SshPublicKey && constantTimeEquals(blob, other.blob);

  @override
  int get hashCode => Object.hashAll(blob);

  @override
  String toString() => '$type ${base64.encode(blob)}';

  /// The signature algorithms the server takes, for server-sig-algs.
  static const signatureAlgorithms = [
    'ssh-ed25519',
    'ecdsa-sha2-nistp256',
    'ecdsa-sha2-nistp384',
    'ecdsa-sha2-nistp521',
    'rsa-sha2-512',
    'rsa-sha2-256',
  ];

  static void _end(SshReader r, bool valid) {
    if (!valid) {
      throw const FormatException('a malformed key');
    }
  }

  static BigInt _bigInt(Uint8List magnitude) {
    var n = BigInt.zero;
    for (final b in magnitude) {
      n = (n << 8) | BigInt.from(b);
    }
    return n;
  }

  /// The signature bytes of [signature] when it is in [algorithm].
  static Uint8List _signature(String algorithm, Uint8List signature) {
    final r = SshReader(signature);
    if (r.utf8String() != algorithm) {
      throw const FormatException('a signature in another algorithm');
    }
    final bytes = r.string();
    if (!r.atEnd) {
      throw const FormatException('a malformed signature');
    }
    return bytes;
  }

  static bool _verifyEd25519(Uint8List key, Uint8List data, Uint8List sig) {
    final bytes = _signature('ssh-ed25519', sig);
    if (bytes.length != 64) {
      return false;
    }
    return ed25519.VerifyKey(key).verify(
      signature: ed25519.Signature(bytes),
      message: data,
    );
  }

  static bool _verifyRsa(
    BigInt n,
    BigInt e,
    String algorithm,
    Uint8List data,
    Uint8List sig,
  ) {
    final signer = switch (algorithm) {
      'rsa-sha2-256' => RSASigner(SHA256Digest(), '0609608648016503040201'),
      'rsa-sha2-512' => RSASigner(SHA512Digest(), '0609608648016503040203'),
      _ => null,
    };
    if (signer == null) {
      return false;
    }
    final bytes = _signature(algorithm, sig);
    signer.init(false, PublicKeyParameter<RSAPublicKey>(RSAPublicKey(n, e)));
    return signer.verifySignature(data, RSASignature(bytes));
  }

  static bool _verifyEcdsa(
    ECDomainParameters curve,
    ECPoint q,
    String curveName,
    Uint8List data,
    Uint8List sig,
  ) {
    final r = SshReader(_signature('ecdsa-sha2-$curveName', sig));
    final rs = _bigInt(r.mpint());
    final ss = _bigInt(r.mpint());
    if (!r.atEnd) {
      return false;
    }
    final digest = switch (curveName) {
      'nistp256' => SHA256Digest(),
      'nistp384' => SHA384Digest(),
      _ => SHA512Digest(),
    };
    final signer = ECDSASigner(digest)
      ..init(false, PublicKeyParameter<ECPublicKey>(ECPublicKey(q, curve)));
    return signer.verifySignature(data, ECSignature(rs, ss));
  }

  /// The uncompressed point [encoded], which must lie on [curve].
  static ECPoint _point(ECDomainParameters curve, Uint8List encoded) {
    final size = (curve.curve.fieldSize + 7) ~/ 8;
    if (encoded.length != 1 + 2 * size || encoded[0] != 4) {
      throw const FormatException('a malformed point');
    }
    final x = _bigInt(Uint8List.sublistView(encoded, 1, 1 + size));
    final y = _bigInt(Uint8List.sublistView(encoded, 1 + size));
    final c = curve.curve as fp.ECCurve;
    final p = c.q!;
    final a = c.a!.toBigInteger()!;
    final b = c.b!.toBigInteger()!;
    if (x >= p ||
        y >= p ||
        (y * y - (x * x * x + a * x + b)) % p != BigInt.zero) {
      throw const FormatException('a point off the curve');
    }
    return c.decodePoint(encoded)!;
  }
}

/// The keys of an authorized_keys file: a key a line lists may log in.
///
/// A line is `type base64 [comment]`; empty lines and those starting with
/// `#` are skipped, and so are lines with options (`from=`, `command=`,
/// `restrict`, ...), which the server doesn't apply: their keys are
/// refused rather than let in without them. Keys of a type not supported
/// (certificates, security keys) are skipped.
final class AuthorizedKeys {
  /// The file's keys: [keys].
  AuthorizedKeys(Iterable<SshPublicKey> keys) : _keys = keys.toSet();

  /// The keys the lines of [text] list.
  factory AuthorizedKeys.parse(String text) {
    final keys = <SshPublicKey>[];
    for (final line in const LineSplitter().convert(text)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }
      final key = SshPublicKey.parse(trimmed);
      if (key != null) {
        keys.add(key);
      }
    }
    return AuthorizedKeys(keys);
  }

  /// The keys the file at [path] lists; throws [FileSystemException] when
  /// it can't be read.
  static Future<AuthorizedKeys> load(String path) async =>
      AuthorizedKeys.parse(await File(path).readAsString());

  final Set<SshPublicKey> _keys;

  /// The keys taken.
  Iterable<SshPublicKey> get keys => _keys;

  /// Whether [key] is one of [keys].
  bool contains(SshPublicKey key) => _keys.contains(key);
}
