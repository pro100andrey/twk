/// Fast range fills for typed lists.
///
/// `fillRange` on a typed list is a plain element loop, while `setRange`
/// between ranges of the same typed list is a `memmove`. Filling a short
/// seed and doubling it with `setRange` is several times faster for a row
/// and tens of times faster for a whole screen.
library;

import 'dart:typed_data';

const _seed = 16;

/// Sets `a[start, end)` to [value].
@pragma('vm:prefer-inline')
void fillU32(Uint32List a, int start, int end, int value) {
  final n = end - start;
  if (n <= 2 * _seed) {
    for (var i = start; i < end; i++) {
      a[i] = value;
    }
    return;
  }
  _fillU32Long(a, start, n, value);
}

void _fillU32Long(Uint32List a, int start, int n, int value) {
  for (var i = start; i < start + _seed; i++) {
    a[i] = value;
  }
  var filled = _seed;
  while (filled < n) {
    final c = filled < n - filled ? filled : n - filled;
    a.setRange(start + filled, start + filled + c, a, start);
    filled += c;
  }
}

/// Sets `a[start, end)` to [value].
@pragma('vm:prefer-inline')
void fillI32(Int32List a, int start, int end, int value) {
  final n = end - start;
  if (n <= 2 * _seed) {
    for (var i = start; i < end; i++) {
      a[i] = value;
    }
    return;
  }
  for (var i = start; i < start + _seed; i++) {
    a[i] = value;
  }
  var filled = _seed;
  while (filled < n) {
    final c = filled < n - filled ? filled : n - filled;
    a.setRange(start + filled, start + filled + c, a, start);
    filled += c;
  }
}

/// 64-bit view over a Uint32List (two cells per word) for pairwise scans.
/// An odd trailing element is not covered; callers handle the tail. [a]
/// must start at an 8-byte aligned offset (true for any list allocated on
/// its own); otherwise `asUint64List` throws.
Uint64List view64(Uint32List a) =>
    a.buffer.asUint64List(a.offsetInBytes, a.length >> 1);

/// First index in [start, end) whose value differs from [value] ([end] if
/// none), comparing two elements per step through [a64] (see [view64]).
/// A word holding (value, value) is the same in either byte order.
@pragma('vm:prefer-inline')
int runEndU32(Uint32List a, Uint64List a64, int start, int end, int value) {
  var i = start;
  if ((i & 1) == 1) {
    if (i >= end || a[i] != value) {
      return i;
    }
    i++;
  }
  final pair = value | (value << 32);
  final lim = end & ~1;
  while (i < lim && a64[i >> 1] == pair) {
    i += 2;
  }
  while (i < end && a[i] == value) {
    i++;
  }
  return i;
}

/// First index in [start, end) where [a] and [b] differ ([end] if none),
/// two elements per step through the 64-bit views.
@pragma('vm:prefer-inline')
int firstDiffU32(
  Uint32List a,
  Uint64List a64,
  Uint32List b,
  Uint64List b64,
  int start,
  int end,
) {
  var i = start;
  if ((i & 1) == 1 && i < end) {
    if (a[i] != b[i]) {
      return i;
    }
    i++;
  }
  final lim = end & ~1;
  while (i < lim && a64[i >> 1] == b64[i >> 1]) {
    i += 2;
  }
  while (i < end && a[i] == b[i]) {
    i++;
  }
  return i;
}

/// One past the last index in [start, end) where [a] and [b] differ
/// ([start] if none), two elements per step through the 64-bit views.
@pragma('vm:prefer-inline')
int lastDiffU32(
  Uint32List a,
  Uint64List a64,
  Uint32List b,
  Uint64List b64,
  int start,
  int end,
) {
  var i = end;
  if ((i & 1) == 1 && i > start) {
    if (a[i - 1] != b[i - 1]) {
      return i;
    }
    i--;
  }
  while (i - 2 >= start && a64[(i >> 1) - 1] == b64[(i >> 1) - 1]) {
    i -= 2;
  }
  while (i > start && a[i - 1] == b[i - 1]) {
    i--;
  }
  return i;
}

/// Whether a[start, end) == b[start, end), two elements per step through
/// the 64-bit views.
@pragma('vm:prefer-inline')
bool equalRangeU32(
  Uint32List a,
  Uint64List a64,
  Uint32List b,
  Uint64List b64,
  int start,
  int end,
) {
  var i = start;
  if ((i & 1) == 1 && i < end) {
    if (a[i] != b[i]) {
      return false;
    }
    i++;
  }
  final lim = end & ~1;
  while (i < lim) {
    if (a64[i >> 1] != b64[i >> 1]) {
      return false;
    }
    i += 2;
  }
  return i >= end || a[i] == b[i];
}
