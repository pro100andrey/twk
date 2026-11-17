// ByteLog: where the app's count of what it wrote falls in what the
// terminal gave, with the CRs its line discipline added to the LFs.
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_driver/twk_driver.dart';

Uint8List b(String s) => Uint8List.fromList(s.codeUnits);

void main() {
  test('without ONLCR the counts are the bytes', () {
    final log = ByteLog()..add(b('ab\ncd'), onlcr: false);
    expect(log.appLength, 5);
    expect(log.rawOffsetFor(3), 3);
    expect(log.rawOffsetFor(6), isNull);
  });

  test('with ONLCR an LF after a CR counts for nothing, and goes whole', () {
    // the app wrote "ab\ncd": 5 bytes, 6 received
    final log = ByteLog()..add(b('ab\r\ncd'), onlcr: true);
    expect(log.appLength, 5);
    expect(log.rawOffsetFor(2), 2);
    // the boundary after the LF never falls between the CR and it
    expect(log.rawOffsetFor(3), 4);
    expect(log.rawOffsetFor(5), 6);
  });

  test('a CR the app wrote before its LF counts, the added one not', () {
    // the app wrote "a\r\nb": 4 bytes; received "a\r\r\nb"
    final log = ByteLog()..add(b('a\r\r\nb'), onlcr: true);
    expect(log.appLength, 4);
    expect(log.rawOffsetFor(3), 4);
  });

  test('a pair cut between two pieces is counted once', () {
    final log = ByteLog()
      ..add(b('ab\r'), onlcr: true)
      ..add(b('\ncd'), onlcr: true);
    expect(log.appLength, 5);
    // the count that ends on the last CR received is the app's: the
    // piece after it has its LF
    expect(log.rawOffsetFor(3), 4);
    expect(log.rawOffsetFor(4), 5);
  });

  test('slice gives the bytes between two offsets across pieces', () {
    final log = ByteLog()
      ..add(b('abc'), onlcr: false)
      ..add(b('def'), onlcr: false);
    expect(String.fromCharCodes(log.slice(2, 5)), 'cde');
  });
}
