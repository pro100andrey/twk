import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_ssh/twk_ssh.dart';

import 'support.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('twk_ssh_keys'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('a host key', () {
    test('generated into a file is written 0600, and loaded from it', () async {
      final path = '${dir.path}/keys/host_ed25519';
      final made = await SshHostKey.loadOrGenerate(path);
      expect(made.algorithm, 'ssh-ed25519');
      if (!Platform.isWindows) {
        expect(File(path).statSync().mode & 0x1FF, 0x180); // rw-------
      }
      final loaded = await SshHostKey.loadOrGenerate(path);
      expect(loaded.fingerprint, made.fingerprint);
      expect(await SshHostKey.load(path), isA<SshHostKey>());
    });

    test('generated is what ssh-keygen reads', () async {
      final path = '${dir.path}/host';
      final key = await SshHostKey.loadOrGenerate(path);
      final r = await sshKeygen(['-y', '-f', path]);
      if (r == null) {
        markTestSkipped('ssh-keygen is not installed');
        return;
      }
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect((r.stdout as String).trim(), startsWith(key.publicKeyLine));
    });

    test('of a file ssh-keygen wrote, encrypted', () async {
      final path = '${dir.path}/enc';
      final r = await sshKeygen([
        ...['-q', '-t', 'ed25519', '-N', 'secret', '-f', path],
      ]);
      if (r == null) {
        markTestSkipped('ssh-keygen is not installed');
        return;
      }
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final key = await SshHostKey.load(path, passphrase: 'secret');
      expect(
        File('$path.pub').readAsStringSync(),
        startsWith(key.publicKeyLine),
      );
      expect(
        () => SshHostKey.fromPem(File(path).readAsStringSync()),
        throwsFormatException,
      );
    });

    test('is refused when the text holds none', () {
      expect(() => SshHostKey.fromPem('hello'), throwsFormatException);
    });
  });

  group('authorized_keys', () {
    final alice = ClientKey.ed25519();
    final bob = ClientKey.ed25519();
    final carol = ClientKey.ed25519();

    test('takes the key lines, skipping the others', () {
      final keys = AuthorizedKeys.parse(
        [
          '# a comment',
          '',
          '${alice.publicKey} alice@laptop',
          '   ${bob.publicKey}',
          'from="10.0.0.1" ${carol.publicKey}',
          'restrict ${carol.publicKey}',
          'ssh-rsa ${base64.encode(alice.publicKey.blob)}', // a type mismatch
          'ssh-ed25519 not-base64',
          'ssh-ed25519',
        ].join('\n'),
      );
      expect(keys.keys, unorderedEquals([alice.publicKey, bob.publicKey]));
      expect(keys.contains(carol.publicKey), isFalse);
    });

    test('a parsed key equals the one decoded, and prints as it was', () {
      final line = '${alice.publicKey}';
      expect(SshPublicKey.parse('$line comment'), alice.publicKey);
      expect(line, startsWith('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5'));
      expect(alice.publicKey.fingerprint, startsWith('SHA256:'));
    });
  });

  group('a signature', () {
    final alice = ClientKey.ed25519();
    final data = Uint8List.fromList(utf8.encode('signed data'));

    test('verifies with its key, data and algorithm only', () {
      final signature = alice.pair.sign(data).encode();
      final key = alice.publicKey;
      expect(key.verify('ssh-ed25519', data, signature), isTrue);
      expect(key.verify('ssh-rsa', data, signature), isFalse);
      final other = Uint8List.fromList(data)..[0] ^= 1;
      expect(key.verify('ssh-ed25519', other, signature), isFalse);
      final forged = Uint8List.fromList(signature)..[signature.length - 1] ^= 1;
      expect(key.verify('ssh-ed25519', data, forged), isFalse);
      expect(
        ClientKey.ed25519().publicKey.verify('ssh-ed25519', data, signature),
        isFalse,
      );
      expect(key.verify('ssh-ed25519', data, Uint8List(3)), isFalse);
    });

    test('of an RSA key in rsa-sha2-256 and -512, not SHA-1', () async {
      final rsa = await ClientKey.keygen(dir, 'rsa', 2048);
      if (rsa == null) {
        markTestSkipped('ssh-keygen is not installed');
        return;
      }
      expect(rsa.publicKey.algorithms, ['rsa-sha2-512', 'rsa-sha2-256']);
      // dartssh2 signs with rsa-sha2-256
      final signature = rsa.pair.sign(data).encode();
      expect(rsa.publicKey.verify('rsa-sha2-256', data, signature), isTrue);
      expect(rsa.publicKey.verify('rsa-sha2-512', data, signature), isFalse);
      expect(rsa.publicKey.verify('ssh-rsa', data, signature), isFalse);
    });
  });
}
