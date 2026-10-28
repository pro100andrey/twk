/// zlib where there is no dart:io (the web): inflating in Dart (RFC 1950
/// and 1951: stored, fixed and dynamic Huffman blocks), and deflating into
/// stored blocks, which every inflater reads; the VM's are dart:io's
/// (`zlib_io.dart`).
library;

import 'dart:typed_data';

/// The data the zlib stream [data] holds; a [FormatException] where it is
/// not one, or its checksum does not match.
Uint8List zlibInflate(List<int> data) {
  if (data.length < 6) {
    throw const FormatException('zlib stream too short');
  }
  final cmf = data[0];
  final flg = data[1];
  if (cmf & 0x0F != 8 || (cmf << 8 | flg) % 31 != 0 || flg & 0x20 != 0) {
    throw const FormatException('not a zlib stream of deflated data');
  }
  final inflater = _Inflater(data, 2);
  final out = inflater.run();
  final at = inflater.endOfBlocks();
  if (at + 4 > data.length) {
    throw const FormatException('zlib stream without its checksum');
  }
  final want =
      data[at] << 24 | data[at + 1] << 16 | data[at + 2] << 8 | data[at + 3];
  if (_adler32(out) != want) {
    throw const FormatException('zlib checksum does not match');
  }
  return out;
}

/// [data] as a zlib stream of stored blocks (deflate's level 0); [level]
/// is taken and left aside, as there is no compressor here.
Uint8List zlibDeflate(List<int> data, {int level = 6}) {
  final out = BytesBuilder(copy: false)..add(const [0x78, 0x01]);
  var at = 0;
  do {
    final n = data.length - at < 0xFFFF ? data.length - at : 0xFFFF;
    final last = at + n == data.length;
    out
      ..addByte(last ? 1 : 0)
      ..addByte(n & 0xFF)
      ..addByte(n >> 8)
      ..addByte(~n & 0xFF)
      ..addByte(~n >> 8 & 0xFF)
      ..add(data.sublist(at, at + n));
    at += n;
  } while (at < data.length);
  final sum = _adler32(data);
  out.add([sum >> 24 & 0xFF, sum >> 16 & 0xFF, sum >> 8 & 0xFF, sum & 0xFF]);
  return out.takeBytes();
}

int _adler32(List<int> data) {
  var a = 1;
  var b = 0;
  for (var i = 0; i < data.length;) {
    // 5552 bytes keep b under 2^32 between the reductions
    final end = i + 5552 < data.length ? i + 5552 : data.length;
    for (; i < end; i++) {
      a += data[i];
      b += a;
    }
    a %= 65521;
    b %= 65521;
  }
  return b << 16 | a;
}

/// A Huffman code by its lengths: the symbols of each length, in order.
final class _Huffman {
  _Huffman(List<int> lengths) {
    for (final l in lengths) {
      counts[l]++;
    }
    counts[0] = 0;
    final offsets = List.filled(16, 0);
    for (var l = 1; l < 16; l++) {
      offsets[l] = offsets[l - 1] + counts[l - 1];
    }
    symbols = List.filled(lengths.length, 0);
    for (var s = 0; s < lengths.length; s++) {
      if (lengths[s] != 0) {
        symbols[offsets[lengths[s]]++] = s;
      }
    }
  }

  final List<int> counts = List.filled(16, 0);
  late final List<int> symbols;
}

const _lengthBase = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, //
  35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
];
const _lengthExtra = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, //
  3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
];
const _distBase = [
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, //
  257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289,
  16385, 24577,
];
const _distExtra = [
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, //
  7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
];

/// The order code lengths come in, in a dynamic block's header.
const _order = [
  16,
  17,
  18,
  0,
  8,
  7,
  9,
  6,
  10,
  5,
  11,
  4,
  12,
  3,
  13,
  2,
  14,
  1,
  15,
];

final class _Inflater {
  _Inflater(this._in, this._at);

  final List<int> _in;
  int _at;
  var _bits = 0;
  var _count = 0;
  final _out = BytesBuilder(copy: false);
  var _window = Uint8List(1 << 16);
  var _length = 0;

  /// The byte after the last block: its bits dropped.
  int endOfBlocks() => _at;

  int _bitsOf(int n) {
    while (_count < n) {
      if (_at >= _in.length) {
        throw const FormatException('deflate data cut short');
      }
      _bits |= _in[_at++] << _count;
      _count += 8;
    }
    final v = _bits & ((1 << n) - 1);
    _bits >>= n;
    _count -= n;
    return v;
  }

  int _decode(_Huffman h) {
    var code = 0;
    var first = 0;
    var index = 0;
    for (var len = 1; len < 16; len++) {
      code |= _bitsOf(1);
      final count = h.counts[len];
      if (code - count < first) {
        return h.symbols[index + (code - first)];
      }
      index += count;
      first += count;
      first <<= 1;
      code <<= 1;
    }
    throw const FormatException('deflate data with a bad code');
  }

  void _emit(int byte) {
    if (_length == _window.length) {
      _window = Uint8List(_window.length * 2)..setRange(0, _length, _window);
    }
    _window[_length++] = byte;
  }

  Uint8List run() {
    var last = 0;
    while (last == 0) {
      last = _bitsOf(1);
      switch (_bitsOf(2)) {
        case 0:
          _stored();
        case 1:
          _codes(_fixedLengths, _fixedDistances);
        case 2:
          _dynamic();
        default:
          throw const FormatException('deflate block of a reserved type');
      }
    }
    // the bits left of the last byte read are padding
    _bits = 0;
    _count = 0;
    _out.add(Uint8List.sublistView(_window, 0, _length));
    return _out.takeBytes();
  }

  void _stored() {
    _bits = 0;
    _count = 0;
    if (_at + 4 > _in.length) {
      throw const FormatException('deflate data cut short');
    }
    final n = _in[_at] | _in[_at + 1] << 8;
    final check = _in[_at + 2] | _in[_at + 3] << 8;
    if (n != ~check & 0xFFFF) {
      throw const FormatException('stored block of a bad length');
    }
    _at += 4;
    if (_at + n > _in.length) {
      throw const FormatException('deflate data cut short');
    }
    for (var i = 0; i < n; i++) {
      _emit(_in[_at + i]);
    }
    _at += n;
  }

  static final _fixedLengths = _Huffman([
    ...List.filled(144, 8),
    ...List.filled(112, 9),
    ...List.filled(24, 7),
    ...List.filled(8, 8),
  ]);
  static final _fixedDistances = _Huffman(List.filled(30, 5));

  void _dynamic() {
    final nlen = _bitsOf(5) + 257;
    final ndist = _bitsOf(5) + 1;
    final ncode = _bitsOf(4) + 4;
    if (nlen > 286 || ndist > 30) {
      throw const FormatException('deflate block of too many codes');
    }
    final codeLengths = List.filled(19, 0);
    for (var i = 0; i < ncode; i++) {
      codeLengths[_order[i]] = _bitsOf(3);
    }
    final lencode = _Huffman(codeLengths);
    final lengths = <int>[];
    while (lengths.length < nlen + ndist) {
      final sym = _decode(lencode);
      if (sym < 16) {
        lengths.add(sym);
        continue;
      }
      final (repeat, value) = switch (sym) {
        16 when lengths.isNotEmpty => (3 + _bitsOf(2), lengths.last),
        16 => throw const FormatException('deflate repeat with nothing before'),
        17 => (3 + _bitsOf(3), 0),
        _ => (11 + _bitsOf(7), 0),
      };
      if (lengths.length + repeat > nlen + ndist) {
        throw const FormatException('deflate code lengths overrun');
      }
      lengths.addAll(List.filled(repeat, value));
    }
    _codes(
      _Huffman(lengths.sublist(0, nlen)),
      _Huffman(lengths.sublist(nlen)),
    );
  }

  void _codes(_Huffman lengths, _Huffman distances) {
    while (true) {
      final sym = _decode(lengths);
      if (sym < 256) {
        _emit(sym);
      } else if (sym == 256) {
        return;
      } else {
        final i = sym - 257;
        if (i >= _lengthBase.length) {
          throw const FormatException('deflate length of a bad code');
        }
        final len = _lengthBase[i] + _bitsOf(_lengthExtra[i]);
        final d = _decode(distances);
        if (d >= _distBase.length) {
          throw const FormatException('deflate distance of a bad code');
        }
        final dist = _distBase[d] + _bitsOf(_distExtra[d]);
        if (dist > _length) {
          throw const FormatException('deflate distance too far back');
        }
        for (var k = 0; k < len; k++) {
          _emit(_window[_length - dist]);
        }
      }
    }
  }
}
