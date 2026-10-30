// GlyphTable: clusters interned, their ids swept when no root marks them
// and given out again, the lowest first; what a freed id reads with
// asserts on; U+FFFD, not an error, past the ids a cell has room for.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/src/surface.dart';

void main() {
  test('a sweep frees what no root marks, ignoring code points and flags, '
      'and gives the ids out again, the lowest first', () {
    final t = GlyphTable();
    final a = t.intern('é', 0, 2);
    final b = t.intern('ö', 0, 2);
    final c = t.intern('🇺🇦', 0, 4);
    expect((t.length, t.live, t.sweeps), (3, 3, 0));
    // a cell's word: the id with its flags; a code point marks nothing
    t.sweep((mark) {
      mark(b | kWide | kUncertain);
      mark(0x41);
    });
    expect((t.length, t.live, t.sweeps), (3, 1, 1));
    expect(t.stringOf(b), 'ö');
    expect(t.intern('ö', 0, 2), b, reason: 'kept, found again');
    final d = t.intern('â', 0, 2);
    final e = t.intern('ũ', 0, 2);
    expect([d, e], [a, c]);
    expect(t.stringOf(d), 'â');
    expect(t.bytesOf(e), utf8.encode(t.stringOf(e)));
    expect(t.maxWidthOf(e), 1);
    expect(t.length, 3, reason: 'no new id while one was free');
  });

  test('with asserts, a freed id read before a cluster has it again fails', () {
    final t = GlyphTable();
    final gone = t.intern('é', 0, 2);
    t.sweep((_) {});
    expect(() => t.stringOf(gone), throwsA(isA<AssertionError>()));
    expect(() => t.bytesOf(gone), throwsA(isA<AssertionError>()));
    t.intern('ö', 0, 2);
    expect(t.stringOf(gone), 'ö');
  });
}
