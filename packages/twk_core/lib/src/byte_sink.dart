/// [ByteSink], a growable byte buffer a frame's escape sequences and text
/// are written into without allocating per write, and [decimalDigits].
///
/// @docImport 'presenter.dart';
library;

import 'dart:typed_data';

/// A growable byte buffer that the presenter writes a frame into: bytes,
/// ASCII, decimal numbers, UTF-8 code points and CSI sequences, with no
/// allocation per write.
///
/// The buffer doubles when a write needs more room than it has; [reset]
/// empties it and keeps its capacity, so a frame after the first writes
/// into the memory the earlier frames grew. [view] reads the bytes without
/// copying them, [takeCopy] copies them for a consumer that keeps them.
///
/// ```dart
/// final sink = ByteSink()
///   ..csi(2, 0x4A) // ESC [ 2 J
///   ..ascii('hi');
/// final bytes = sink.takeCopy(); // [27, 91, 50, 74, 104, 105]
/// ```
///
/// See also:
///
///  * [Presenter.out], the sink a frame's bytes are in.
final class ByteSink {
  /// An empty sink whose buffer starts with room for [capacity] bytes,
  /// 16 KiB by default; 0 is allowed, and it grows on the first write.
  ByteSink([int capacity = 1 << 14]) : _buf = Uint8List(capacity);

  Uint8List _buf;

  /// How many bytes were written since the sink was made or last [reset].
  ///
  /// Setting it lower drops the bytes after it; it must not be set beyond
  /// the bytes written.
  var length = 0;
  var _view = Uint8List(0); // onto _buf, as long as the last view taken

  /// The bytes written so far (a view; valid until the next write/reset).
  Uint8List get view {
    if (_view.length != length) {
      _view = Uint8List.sublistView(_buf, 0, length);
    }
    return _view;
  }

  /// A copy of the bytes written so far (safe to hand to an async sink).
  Uint8List takeCopy() => Uint8List.fromList(view);

  /// Empties the sink, keeping its buffer for the next writes.
  void reset() => length = 0;

  /// Drops the first [n] bytes.
  void removePrefix(int n) {
    _buf.setRange(0, length - n, _buf, n);
    length -= n;
  }

  @pragma('vm:prefer-inline')
  void _ensure(int n) {
    if (length + n > _buf.length) {
      _grow(n);
    }
  }

  void _grow(int n) {
    var cap = _buf.isEmpty ? 64 : _buf.length * 2;
    while (cap < length + n) {
      cap *= 2;
    }
    _buf = Uint8List(cap)..setRange(0, length, _buf);
    _view = Uint8List(0);
  }

  /// Appends the byte [b] (0 to 255).
  @pragma('vm:prefer-inline')
  void byte(int b) {
    _ensure(1);
    _buf[length++] = b;
  }

  /// Appends every byte of [b].
  void bytes(Uint8List b) {
    _ensure(b.length);
    _buf.setRange(length, length + b.length, b);
    length += b.length;
  }

  /// Appends [s], one byte per code unit; [s] must be ASCII, or the bytes
  /// written are each code unit's low 8 bits.
  void ascii(String s) {
    _ensure(s.length);
    for (var i = 0; i < s.length; i++) {
      _buf[length++] = s.codeUnitAt(i);
    }
  }

  /// Appends [v] in decimal ASCII digits, without a sign or leading zeros:
  /// the number of an escape sequence's parameter.
  ///
  /// Throws a [RangeError] when [v] is negative, which no parameter of a
  /// sequence is.
  void decimal(int v) {
    if (v < 10) {
      if (v < 0) {
        // a negative parameter would corrupt the sequence: fail loudly
        throw RangeError.value(v, 'v', 'must be non-negative');
      }
      byte(0x30 + v);
      return;
    }
    var digits = 0;
    for (var t = v; t > 0; t ~/= 10) {
      digits++;
    }
    _ensure(digits);
    var p = length + digits;
    for (var t = v; t > 0; t ~/= 10) {
      _buf[--p] = 0x30 + t % 10;
    }
    length += digits;
  }

  /// Appends the UTF-8 encoding of the Unicode scalar value [cp]: one to
  /// four bytes.
  @pragma('vm:prefer-inline')
  void codePoint(int cp) {
    if (cp < 0x80) {
      byte(cp);
      return;
    }
    _ensure(4);
    final b = _buf;
    if (cp < 0x800) {
      b[length++] = 0xC0 | (cp >> 6);
      b[length++] = 0x80 | (cp & 0x3F);
    } else if (cp < 0x10000) {
      b[length++] = 0xE0 | (cp >> 12);
      b[length++] = 0x80 | ((cp >> 6) & 0x3F);
      b[length++] = 0x80 | (cp & 0x3F);
    } else {
      b[length++] = 0xF0 | (cp >> 18);
      b[length++] = 0x80 | ((cp >> 12) & 0x3F);
      b[length++] = 0x80 | ((cp >> 6) & 0x3F);
      b[length++] = 0x80 | (cp & 0x3F);
    }
  }

  /// Makes room for [n] more bytes: the next [n] bytes may then be written
  /// with [codePointReserved].
  @pragma('vm:prefer-inline')
  void reserve(int n) => _ensure(n);

  /// [codePoint] without making room: [reserve] made it, 4 bytes for each
  /// code point.
  @pragma('vm:prefer-inline')
  void codePointReserved(int cp) {
    final b = _buf;
    if (cp < 0x80) {
      b[length++] = cp;
    } else if (cp < 0x800) {
      b[length++] = 0xC0 | (cp >> 6);
      b[length++] = 0x80 | (cp & 0x3F);
    } else if (cp < 0x10000) {
      b[length++] = 0xE0 | (cp >> 12);
      b[length++] = 0x80 | ((cp >> 6) & 0x3F);
      b[length++] = 0x80 | (cp & 0x3F);
    } else {
      b[length++] = 0xF0 | (cp >> 18);
      b[length++] = 0x80 | ((cp >> 12) & 0x3F);
      b[length++] = 0x80 | ((cp >> 6) & 0x3F);
      b[length++] = 0x80 | (cp & 0x3F);
    }
  }

  /// Appends the CSI sequence `ESC [ n <final>`: [n] in decimal, then the
  /// byte [finalByte] (`0x41` for `A`, say).
  void csi(int n, int finalByte) {
    _ensure(3);
    _buf[length++] = 0x1B;
    _buf[length++] = 0x5B;
    decimal(n);
    byte(finalByte);
  }
}

/// How many decimal digits [v] has, which must not be negative: 1 for 0
/// to 9, 2 for 10 to 99, and so on.
///
/// The length [ByteSink.decimal] writes for [v], known without writing it.
@pragma('vm:prefer-inline')
int decimalDigits(int v) {
  if (v < 10) {
    return 1;
  }
  if (v < 100) {
    return 2;
  }
  if (v < 1000) {
    return 3;
  }
  if (v < 10000) {
    return 4;
  }
  var d = 5;
  for (var t = v ~/ 100000; t > 0; t ~/= 10) {
    d++;
  }
  return d;
}
