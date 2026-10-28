import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/src/fill.dart';

void main() {
  test('fillU32 / fillI32 == naive loop for every length and offset', () {
    for (var len = 0; len <= 300; len++) {
      for (final start in const <int>[0, 1, 7, 33]) {
        final a = Uint32List(start + len + 5)..fillRange(0, start + len + 5, 7);
        final b = Int32List(start + len + 5)..fillRange(0, start + len + 5, 7);
        fillU32(a, start, start + len, 0xABCDEF);
        fillI32(b, start, start + len, -3);
        for (var i = 0; i < a.length; i++) {
          final inside = i >= start && i < start + len;
          expect(
            a[i],
            inside ? 0xABCDEF : 7,
            reason: 'u32 len=$len start=$start i=$i',
          );
          expect(
            b[i],
            inside ? -3 : 7,
            reason: 'i32 len=$len start=$start i=$i',
          );
        }
      }
    }
  });

  test('runEndU32 == naive scan for every start/end/run position', () {
    for (var n = 0; n <= 40; n++) {
      for (var diffAt = 0; diffAt <= n; diffAt++) {
        final a = Uint32List(n)..fillRange(0, n, 5);
        if (diffAt < n) {
          a[diffAt] = 6;
        }
        final a64 = view64(a);
        for (var start = 0; start <= n; start++) {
          for (var end = start; end <= n; end++) {
            var want = start;
            while (want < end && a[want] == 5) {
              want++;
            }
            expect(
              runEndU32(a, a64, start, end, 5),
              want,
              reason: 'n=$n diffAt=$diffAt start=$start end=$end',
            );
          }
        }
      }
    }
  });

  test('firstDiffU32 / lastDiffU32 == naive scans', () {
    for (var len = 0; len <= 40; len++) {
      for (var d1 = -1; d1 < len; d1++) {
        for (var d2 = d1; d2 < len; d2++) {
          final a = Uint32List(len + 3)..fillRange(0, len + 3, 9);
          final b = Uint32List(len + 3)..fillRange(0, len + 3, 9);
          if (d1 >= 0) {
            b[1 + d1] = 1; // differences at d1 and d2 (relative to start 1)
            b[1 + d2] = 1;
          }
          for (final start in const <int>[1, 2]) {
            final end = 1 + len;
            if (start > end) {
              continue;
            }
            var first = end;
            var last = start;
            for (var i = start; i < end; i++) {
              if (a[i] != b[i]) {
                first = first == end ? i : first;
                last = i + 1;
              }
            }
            final reason = 'len=$len d1=$d1 d2=$d2 start=$start';
            expect(
              firstDiffU32(a, view64(a), b, view64(b), start, end),
              first,
              reason: reason,
            );
            expect(
              lastDiffU32(a, view64(a), b, view64(b), start, end),
              last,
              reason: reason,
            );
          }
        }
      }
    }
  });

  test('equalRangeU32 == naive compare', () {
    for (var n = 0; n <= 24; n++) {
      for (var diffAt = -1; diffAt < n; diffAt++) {
        final a = Uint32List(n)..fillRange(0, n, 9);
        final b = Uint32List(n)..fillRange(0, n, 9);
        if (diffAt >= 0) {
          b[diffAt] = 8;
        }
        for (var start = 0; start <= n; start++) {
          for (var end = start; end <= n; end++) {
            final want = diffAt < start || diffAt >= end;
            expect(
              equalRangeU32(a, view64(a), b, view64(b), start, end),
              want,
              reason: 'n=$n diffAt=$diffAt start=$start end=$end',
            );
          }
        }
      }
    }
  });
}
