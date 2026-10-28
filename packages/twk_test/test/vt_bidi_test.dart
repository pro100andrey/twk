// The emulator takes BDSM, ECMA-48's bidirectional support mode (8): an
// app on a terminal that honours it resets it (explicit mode) and sets it
// again on its way out; DECRQM asking for it is taken as other queries
// are. Other ANSI modes are still errors.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_test/vt.dart';

void main() {
  test('CSI 8 l is explicit mode, CSI 8 h implicit again, nothing shown, '
      'nothing rejected', () {
    final vt = Vt(10, 2)..feed(utf8.encode('\x1b[8\$pa\x1b[8l'));
    expect(vt.bidiExplicit, isTrue);
    vt.feed(utf8.encode('b\x1b[8h'));
    expect(vt.bidiExplicit, isFalse);
    expect(vt.errors, isEmpty);
    expect(vt.dump().split('\n').first.trimRight(), 'ab');
  });

  test('another ANSI mode is still an error', () {
    final vt = Vt(10, 2, strict: false)..feed(utf8.encode('\x1b[4h'));
    expect(vt.errors, ['unsupported CSI 4h']);
    expect(vt.bidiExplicit, isFalse);
  });
}
