/// The modules of a QR code: [QrSymbol], text encoded as ISO/IEC 18004
/// says.
library;

import 'dart:convert' show utf8;
import 'dart:typed_data';

import 'reed_solomon.dart';
import 'tables.dart';

/// How much of a QR code may be lost and the code still read: the four
/// levels of error correction, each restoring about the share of its
/// codewords it names, at the cost of room for data.
enum QrErrorCorrection {
  /// L: about 7 % of the codewords.
  low(0x1),

  /// M: about 15 %.
  medium(0x0),

  /// Q: about 25 %.
  quartile(0x3),

  /// H: about 30 %.
  high(0x2);

  const QrErrorCorrection(this._bits);

  // the two bits the format information names it by
  final int _bits;
}

/// How the data of a QR code is held: each mode takes fewer bits for what
/// it can hold than the one after it.
enum QrMode {
  /// Digits, three in 10 bits.
  numeric(0x1, 10, 12, 14),

  /// Digits, capital letters and ` $%*+-./:`, two in 11 bits.
  alphanumeric(0x2, 9, 11, 13),

  /// Bytes, 8 bits each: text as its UTF-8.
  byte(0x4, 8, 16, 16);

  const QrMode(this.indicator, this._small, this._medium, this._large);

  /// The four bits that start the data in this mode.
  final int indicator;

  // the bits of the count of characters, by the version's range
  final int _small;
  final int _medium;
  final int _large;

  /// The bits the count of characters takes in a symbol of [version].
  int countBits(int version) => version < 10
      ? _small
      : version < 27
      ? _medium
      : _large;

  /// The bits [count] characters take in this mode.
  int dataBits(int count) => switch (this) {
    numeric => 10 * (count ~/ 3) + const [0, 4, 7][count % 3],
    alphanumeric => 11 * (count ~/ 2) + 6 * (count % 2),
    byte => 8 * count,
  };
}

/// The characters of [QrMode.alphanumeric], each its value.
const _alphanumeric = r'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';

/// Text as a QR code, ISO/IEC 18004 (Model 2): a square of [size] × [size]
/// modules, each dark or light ([isDark]), which a scanner reads with a
/// quiet zone of light modules around it, 4 wide by the standard.
///
/// The data is in a single [mode], the one of fewest bits that holds all
/// of it ([QrSymbol.encode]), at the error correction [level] asked for,
/// in the smallest [version] (1 to 40, 21 to 177 modules a side) it fits
/// in; after it the terminator and the pad codewords, the codewords split
/// into the blocks of the version and level, each with its Reed-Solomon
/// codewords, interleaved and placed from the bottom right corner up and
/// down in columns two wide. Around them are the function patterns: the
/// three finder patterns and their separators, the timing patterns, the
/// alignment patterns, the dark module, and the format information
/// (level and mask) twice and, from version 7, the version information
/// twice, each with its BCH code. Of the eight [mask] patterns the data
/// is laid under, the one the standard's four penalty rules score lowest
/// is taken, the first of those that tie: runs of five modules or more of
/// a color in a row or a column (3, and 1 for each module over five);
/// blocks of 2 × 2 of a color (3 each); dark, light, three dark, light,
/// dark in a row or a column with four light modules before or after it,
/// those outside the symbol light as the quiet zone is (40 each); and
/// every 5 % the dark modules are off half of them (10).
final class QrSymbol {
  QrSymbol._(this.version, this.level, this.mode, this.mask, this._modules)
    : size = 4 * version + 17;

  /// [text] as a QR code, in the mode of fewest bits that holds all of it:
  /// [QrMode.numeric] for digits alone, [QrMode.alphanumeric] for digits,
  /// capital letters and ` $%*+-./:`, [QrMode.byte] for its UTF-8
  /// otherwise (as phones read it; no ECI says so). See [QrSymbol.bytes].
  factory QrSymbol.encode(
    String text, {
    QrErrorCorrection level = QrErrorCorrection.medium,
    int? version,
    int? mask,
  }) {
    final mode = modeOf(text);
    return QrSymbol._of(
      mode,
      mode == QrMode.byte ? utf8.encode(text) : text.codeUnits,
      level,
      version,
      mask,
    );
  }

  /// [bytes] as a QR code in [QrMode.byte], each from 0 to 255, at the
  /// error correction [level], in [version] (1 to 40) or the smallest
  /// version they fit in when null, laid under [mask] (0 to 7) or the one
  /// the penalty rules score lowest when null. Data that does not fit in
  /// [version], or in version 40 at [level], is an [ArgumentError].
  factory QrSymbol.bytes(
    List<int> bytes, {
    QrErrorCorrection level = QrErrorCorrection.medium,
    int? version,
    int? mask,
  }) {
    for (final b in bytes) {
      RangeError.checkValueInInterval(b, 0, 255, 'byte');
    }
    return QrSymbol._of(QrMode.byte, bytes, level, version, mask);
  }

  factory QrSymbol._of(
    QrMode mode,
    List<int> data,
    QrErrorCorrection level,
    int? version,
    int? mask,
  ) {
    if (version != null) {
      RangeError.checkValueInInterval(version, 1, 40, 'version');
    }
    if (mask != null) {
      RangeError.checkValueInInterval(mask, 0, 7, 'mask');
    }
    final v = versionFor(mode, data.length, level, version);
    final template = _Template.of(v);
    final codewords = qrCodewords(mode, data, level, v);
    final placed = template.place(codewords);
    if (mask != null) {
      return QrSymbol._(
        v,
        level,
        mode,
        mask,
        template.masked(placed, mask, level),
      );
    }
    var best = 0;
    Uint8List? bestModules;
    var bestScore = -1;
    for (var m = 0; m < 8; m++) {
      final modules = template.masked(placed, m, level);
      final score = penalty(modules, template.size);
      if (bestScore < 0 || score < bestScore) {
        best = m;
        bestModules = modules;
        bestScore = score;
      }
    }
    return QrSymbol._(v, level, mode, best, bestModules!);
  }

  /// The version, from 1 to 40, which sets [size].
  final int version;

  /// The level of error correction.
  final QrErrorCorrection level;

  /// The mode the data is in.
  final QrMode mode;

  /// The mask pattern the data is laid under, from 0 to 7.
  final int mask;

  /// The modules of a side: 4 × [version] + 17.
  final int size;

  // a byte per module, row by row: 1 dark, 0 light
  final Uint8List _modules;

  /// Whether the module in column [x] of row [y], from the top left
  /// corner, is dark.
  bool isDark(int x, int y) {
    RangeError.checkValueInInterval(x, 0, size - 1, 'x');
    RangeError.checkValueInInterval(y, 0, size - 1, 'y');
    return _modules[y * size + x] != 0;
  }

  /// The rows from the top, a character per module: `#` dark, `.` light.
  @override
  String toString() => [
    for (var y = 0; y < size; y++)
      String.fromCharCodes([
        for (var x = 0; x < size; x++)
          0x2E - _modules[y * size + x] * (0x2E - 0x23),
      ]),
  ].join('\n');
}

/// The mode of fewest bits that holds all of [text]; [QrMode.byte] for
/// none.
QrMode modeOf(String text) {
  if (text.isEmpty) {
    return QrMode.byte;
  }
  var numeric = true;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c < 0x30 || c > 0x39) {
      numeric = false;
      if (!_alphanumeric.contains(text[i])) {
        return QrMode.byte;
      }
    }
  }
  return numeric ? QrMode.numeric : QrMode.alphanumeric;
}

/// The smallest version that holds [count] characters in [mode] at
/// [level], [version] itself when given and they fit in it; an
/// [ArgumentError] when they do not.
int versionFor(
  QrMode mode,
  int count,
  QrErrorCorrection level,
  int? version,
) {
  final bits = mode.dataBits(count);
  for (var v = version ?? 1; v <= (version ?? 40); v++) {
    final countBits = mode.countBits(v);
    if (count < 1 << countBits &&
        4 + countBits + bits <= dataCodewords(v, level.index) * 8) {
      return v;
    }
  }
  throw ArgumentError(
    '${mode.name} data of $count characters does not fit in a QR code of '
    '${version == null ? 'any version' : 'version $version'} at the '
    '${level.name} level',
  );
}

/// The codewords of a symbol of [version] at [level] holding [data] in
/// [mode] (characters in the first two, bytes in the third), in the order
/// they are placed: the data codewords split into the version's blocks,
/// each followed by its Reed-Solomon codewords, the data of all blocks
/// interleaved, then their error correction.
Uint8List qrCodewords(
  QrMode mode,
  List<int> data,
  QrErrorCorrection level,
  int version,
) {
  final capacity = dataCodewords(version, level.index);
  final bits = _Bits(capacity)
    ..add(mode.indicator, 4)
    ..add(data.length, mode.countBits(version));
  switch (mode) {
    case QrMode.numeric:
      for (var i = 0; i < data.length; i += 3) {
        final n = data.length - i < 3 ? data.length - i : 3;
        var value = 0;
        for (var k = 0; k < n; k++) {
          value = value * 10 + data[i + k] - 0x30;
        }
        bits.add(value, const [0, 4, 7, 10][n]);
      }
    case QrMode.alphanumeric:
      for (var i = 0; i < data.length; i += 2) {
        final first = _alphanumeric.indexOf(String.fromCharCode(data[i]));
        if (i + 1 < data.length) {
          final second = _alphanumeric.indexOf(
            String.fromCharCode(data[i + 1]),
          );
          bits.add(first * 45 + second, 11);
        } else {
          bits.add(first, 6);
        }
      }
    case QrMode.byte:
      for (final b in data) {
        bits.add(b, 8);
      }
  }
  // the terminator, as much of it as there is room for, then up to a byte
  final room = capacity * 8 - bits.length;
  bits.add(0, room < 4 ? room : 4);
  bits.add(0, (8 - bits.length % 8) % 8);
  final words = bits.bytes;
  for (var i = bits.length ~/ 8, pad = 0xEC; i < capacity; i++) {
    words[i] = pad;
    pad ^= 0xEC ^ 0x11;
  }

  final blocks = ecBlocks[level.index][version - 1];
  final ecLength = ecCodewordsPerBlock[level.index][version - 1];
  final total = totalCodewords(version);
  // the blocks of the first group are a codeword shorter than the others
  final short = blocks - total % blocks;
  final shortData = total ~/ blocks - ecLength;
  final dataBlocks = <Uint8List>[];
  final ecOf = <Uint8List>[];
  for (var b = 0, at = 0; b < blocks; b++) {
    final length = shortData + (b < short ? 0 : 1);
    final block = Uint8List.sublistView(words, at, at + length);
    at += length;
    dataBlocks.add(block);
    ecOf.add(ReedSolomon.remainder(block, ecLength));
  }
  final out = Uint8List(total);
  var k = 0;
  for (var i = 0; i <= shortData; i++) {
    for (final block in dataBlocks) {
      if (i < block.length) {
        out[k++] = block[i];
      }
    }
  }
  for (var i = 0; i < ecLength; i++) {
    for (final ec in ecOf) {
      out[k++] = ec[i];
    }
  }
  return out;
}

/// Bits written from the most significant into bytes, as many as it is
/// made with.
final class _Bits {
  _Bits(int capacity) : bytes = Uint8List(capacity);

  final Uint8List bytes;
  var length = 0;

  /// The [count] low bits of [value], the highest first.
  void add(int value, int count) {
    for (var i = count - 1; i >= 0; i--) {
      if ((value >> i) & 1 != 0) {
        bytes[length >> 3] |= 0x80 >> (length & 7);
      }
      length++;
    }
  }
}

/// [value], of [bits] bits, followed by the remainder of its division by
/// [generator], a polynomial of [degree] over GF(2): a BCH code word.
int _bch(int value, int bits, int generator, int degree) {
  var r = value << degree;
  for (var i = bits + degree - 1; i >= degree; i--) {
    if ((r >> i) & 1 != 0) {
      r ^= generator << (i - degree);
    }
  }
  return value << degree | r;
}

/// The 15 bits of format information naming [level] and [mask]: BCH
/// (15, 5) of the generator x¹⁰ + x⁸ + x⁵ + x⁴ + x² + x + 1, XORed with
/// 101010000010010.
int formatBits(QrErrorCorrection level, int mask) =>
    _bch(level._bits << 3 | mask, 5, 0x537, 10) ^ 0x5412;

/// The 18 bits of version information naming [version]: BCH (18, 6) of the
/// generator x¹² + x¹¹ + x¹⁰ + x⁹ + x⁸ + x⁵ + x² + 1.
int versionBits(int version) => _bch(version, 6, 0x1F25, 12);

/// Whether mask pattern [mask] flips the module in column [x] of row [y].
bool masks(int mask, int x, int y) => switch (mask) {
  0 => (y + x).isEven,
  1 => y.isEven,
  2 => x % 3 == 0,
  3 => (y + x) % 3 == 0,
  4 => (y ~/ 2 + x ~/ 3).isEven,
  5 => (y * x) % 2 + (y * x) % 3 == 0,
  6 => ((y * x) % 2 + (y * x) % 3).isEven,
  _ => ((y + x) % 2 + (y * x) % 3).isEven,
};

/// The penalty the standard's four rules give [modules], [size] × [size]
/// row by row, 1 dark: runs, blocks, finder-like patterns and the balance
/// of dark and light (see [QrSymbol]).
int penalty(Uint8List modules, int size) {
  var score = 0;
  final line = Uint8List(size);
  for (var y = 0; y < size; y++) {
    line.setRange(0, size, modules, y * size);
    score += _linePenalty(line);
  }
  for (var x = 0; x < size; x++) {
    for (var y = 0; y < size; y++) {
      line[y] = modules[y * size + x];
    }
    score += _linePenalty(line);
  }
  var dark = 0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final i = y * size + x;
      dark += modules[i];
      if (x + 1 < size &&
          y + 1 < size &&
          modules[i] == modules[i + 1] &&
          modules[i] == modules[i + size] &&
          modules[i] == modules[i + size + 1]) {
        score += 3;
      }
    }
  }
  // 10 for each full 5 % the dark modules are off half of them
  final total = size * size;
  return score + 10 * ((dark * 20 - total * 10).abs() ~/ total);
}

/// The penalty of rules 1 and 3 in a row or a column: runs of a color five
/// long or longer, and dark, light, three dark, light, dark with four light
/// modules before or after it, outside the symbol light.
int _linePenalty(Uint8List line) {
  final n = line.length;
  var score = 0;
  var run = 1;
  for (var i = 1; i <= n; i++) {
    if (i < n && line[i] == line[i - 1]) {
      run++;
    } else {
      if (run >= 5) {
        score += run - 2;
      }
      run = 1;
    }
  }
  for (var i = 0; i + 7 <= n; i++) {
    if (line[i] == 1 &&
        line[i + 1] == 0 &&
        line[i + 2] == 1 &&
        line[i + 3] == 1 &&
        line[i + 4] == 1 &&
        line[i + 5] == 0 &&
        line[i + 6] == 1 &&
        (_light(line, i - 4, i) || _light(line, i + 7, i + 11))) {
      score += 40;
    }
  }
  return score;
}

/// Whether the modules of [line] from [from] up to [to] are light, those
/// outside it light.
bool _light(Uint8List line, int from, int to) {
  for (var i = from < 0 ? 0 : from; i < to && i < line.length; i++) {
    if (line[i] != 0) {
      return false;
    }
  }
  return true;
}

/// The function patterns of a version, which every symbol of it shares,
/// and the order its other modules take the bits of the codewords in.
final class _Template {
  _Template._(int version) : size = 4 * version + 17 {
    final n = size;
    _modules = Uint8List(n * n);
    _function = Uint8List(n * n);
    // finder patterns and their separators
    for (final (fx, fy) in [(0, 0), (n - 7, 0), (0, n - 7)]) {
      for (var dy = -1; dy <= 7; dy++) {
        for (var dx = -1; dx <= 7; dx++) {
          final ring = _max(_abs(dx - 3), _abs(dy - 3));
          // 3 the separator; 2 the light ring
          _set(fx + dx, fy + dy, ring != 2 && ring != 4);
        }
      }
    }
    // timing patterns
    for (var i = 8; i < n - 8; i++) {
      _set(i, 6, i.isEven);
      _set(6, i, i.isEven);
    }
    // alignment patterns, but where the finders are
    final centers = alignmentCenters[version - 1];
    final last = centers.length - 1;
    for (var a = 0; a <= last; a++) {
      for (var b = 0; b <= last; b++) {
        if ((a == 0 && b == 0) ||
            (a == 0 && b == last) ||
            (a == last && b == 0)) {
          continue;
        }
        for (var dy = -2; dy <= 2; dy++) {
          for (var dx = -2; dx <= 2; dx++) {
            _set(
              centers[a] + dx,
              centers[b] + dy,
              _max(_abs(dx), _abs(dy)) != 1,
            );
          }
        }
      }
    }
    // the format information, written for each mask, and the dark module
    for (var i = 0; i < 9; i++) {
      if (i != 6) {
        _set(8, i, false);
        _set(i, 8, false);
      }
    }
    for (var i = 0; i < 8; i++) {
      _set(n - 1 - i, 8, false);
      _set(8, n - 1 - i, false);
    }
    _set(8, n - 8, true);
    // the version information
    if (version >= 7) {
      final bits = versionBits(version);
      for (var i = 0; i < 18; i++) {
        final dark = (bits >> i) & 1 != 0;
        _set(n - 11 + i % 3, i ~/ 3, dark);
        _set(i ~/ 3, n - 11 + i % 3, dark);
      }
    }
    // the order of the other modules: up and down columns two wide from
    // the right, the right one of each pair first, column 6 left out
    final order = <int>[];
    var upward = true;
    for (var right = n - 1; right > 0; right -= 2) {
      if (right == 6) {
        right = 5;
      }
      for (var k = 0; k < n; k++) {
        final y = upward ? n - 1 - k : k;
        for (final x in [right, right - 1]) {
          if (_function[y * n + x] == 0) {
            order.add(y * n + x);
          }
        }
      }
      upward = !upward;
    }
    _order = Int32List.fromList(order);
  }

  /// The template of [version], made once.
  factory _Template.of(int version) => _cache[version] ??= _Template._(version);

  static final _cache = <int, _Template>{};

  final int size;
  late final Uint8List _modules;
  late final Uint8List _function;
  late final Int32List _order;

  /// The modules not of a function pattern, in the order data takes them.
  int get dataModules => _order.length;

  void _set(int x, int y, bool dark) {
    if (x < 0 || y < 0 || x >= size || y >= size) {
      return;
    }
    _modules[y * size + x] = dark ? 1 : 0;
    _function[y * size + x] = 1;
  }

  /// The function patterns with [codewords] placed, their bits from the
  /// highest of each, the modules left after them light; not masked, the
  /// format information light.
  Uint8List place(Uint8List codewords) {
    final out = Uint8List.fromList(_modules);
    final bits = codewords.length * 8;
    for (var i = 0; i < _order.length && i < bits; i++) {
      out[_order[i]] = (codewords[i >> 3] >> (7 - (i & 7))) & 1;
    }
    return out;
  }

  /// [placed] with [mask] laid over the modules of data and the format
  /// information of [level] and [mask] written.
  Uint8List masked(Uint8List placed, int mask, QrErrorCorrection level) {
    final n = size;
    final out = Uint8List.fromList(placed);
    for (final i in _order) {
      if (masks(mask, i % n, i ~/ n)) {
        out[i] ^= 1;
      }
    }
    final bits = formatBits(level, mask);
    void put(int x, int y, int bit) => out[y * n + x] = (bits >> bit) & 1;
    // around the top left finder: up column 8, then left along row 8,
    // the timing patterns between
    for (var i = 0; i < 6; i++) {
      put(8, i, i);
    }
    put(8, 7, 6);
    put(8, 8, 7);
    put(7, 8, 8);
    for (var i = 9; i < 15; i++) {
      put(14 - i, 8, i);
    }
    // along row 8 under the top right finder, then down column 8 beside
    // the bottom left one
    for (var i = 0; i < 8; i++) {
      put(n - 1 - i, 8, i);
    }
    for (var i = 8; i < 15; i++) {
      put(8, n - 15 + i, i);
    }
    return out;
  }
}

int _abs(int a) => a < 0 ? -a : a;
int _max(int a, int b) => a > b ? a : b;
