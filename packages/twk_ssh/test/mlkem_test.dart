import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_ssh/src/crypto.dart';
import 'package:twk_ssh/src/wire.dart';

Uint8List _hex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

/// What a call that is to fail its key's checks throws.
final Matcher _keyExchangeFailed = throwsA(
  isA<SshProtocolException>().having(
    (e) => e.reason,
    'reason',
    SshDisconnect.keyExchangeFailed,
  ),
);

void main() {
  // NIST's ACVP vectors for FIPS 203 (test/data/mlkem768_acvp.json says
  // which file of which commit): the encapsulation the server does, from a
  // given m, and the check of the client's key.
  final vectors = jsonDecode(
    File('test/data/mlkem768_acvp.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final encapsulation = (vectors['encapsulation']! as List)
      .cast<Map<String, Object?>>();
  final keyChecks = (vectors['encapsulationKeyCheck']! as List)
      .cast<Map<String, Object?>>();

  test('the vectors are all there', () {
    expect(encapsulation, hasLength(25));
    expect(keyChecks, hasLength(10));
    expect(keyChecks.where((t) => t['testPassed'] == false), hasLength(5));
  });

  group('ML-KEM-768 encapsulation, ACVP', () {
    for (final t in encapsulation) {
      test('tcId ${t['tcId']}', () {
        final (:ciphertext, :secret) = mlkem768Encapsulate(
          _hex(t['ek']! as String),
          m: _hex(t['m']! as String),
        );
        expect(ciphertext, _hex(t['c']! as String));
        expect(secret, _hex(t['k']! as String));
      });
    }
  });

  group('ML-KEM-768 encapsulation key check, ACVP', () {
    for (final t in keyChecks) {
      test('tcId ${t['tcId']}: ${t['reason']}', () {
        final ek = _hex(t['ek']! as String);
        if (t['testPassed'] == true) {
          expect(mlkem768Encapsulate(ek).ciphertext, hasLength(1088));
        } else {
          expect(() => mlkem768Encapsulate(ek), _keyExchangeFailed);
        }
      });
    }
  });

  test('a key of the wrong length is refused', () {
    final ek = _hex(encapsulation.first['ek']! as String);
    expect(
      () => mlkem768Encapsulate(Uint8List.sublistView(ek, 1)),
      _keyExchangeFailed,
    );
    expect(
      () => mlkem768Encapsulate(Uint8List.fromList([...ek, 0])),
      _keyExchangeFailed,
    );
  });

  test('each coefficient is checked, the last too', () {
    final ek = _hex(encapsulation.first['ek']! as String);
    // the last of the 768 coefficients: the high 12 bits of bytes
    // 1150..1151; 0xFFF is not below q
    final bad = Uint8List.fromList(ek)
      ..[1150] |= 0xF0
      ..[1151] = 0xFF;
    expect(() => mlkem768Encapsulate(bad), _keyExchangeFailed);
    // and the first: the low 12 bits of bytes 0..1
    final first = Uint8List.fromList(ek)
      ..[0] = 0xFF
      ..[1] |= 0x0F;
    expect(() => mlkem768Encapsulate(first), _keyExchangeFailed);
  });

  test('without m, each encapsulation draws fresh bytes', () {
    final ek = _hex(encapsulation.first['ek']! as String);
    expect(
      mlkem768Encapsulate(ek).secret,
      isNot(mlkem768Encapsulate(ek).secret),
    );
  });
}
