/// The symbols the QR tests check against other encoders' (see
/// `generate.dart`): a case for each version and level, its data made of
/// a generator of pseudo-random numbers, so that the tests and the
/// generator make the same.
library;

import 'package:twk_rich/src/qr/symbol.dart';
import 'package:twk_rich/src/qr/tables.dart';

/// Data for a symbol of [version] at [level] in [mode].
final class QrCase {
  QrCase(this.version, this.level, this.mode, this.data);

  final int version;
  final QrErrorCorrection level;
  final QrMode mode;

  /// Characters in the numeric and alphanumeric modes, bytes in the byte
  /// mode.
  final List<int> data;

  /// The level's letter, `L`, `M`, `Q` or `H`.
  String get levelLetter => 'LMQH'[level.index];

  @override
  String toString() =>
      '$version-$levelLetter ${mode.name}, ${data.length} characters';
}

/// The characters the data of each mode is made of: none the next mode
/// down could hold, so that an encoder that splits data among modes keeps
/// it in one.
const Map<QrMode, String> _pools = {
  QrMode.numeric: '0123456789',
  QrMode.alphanumeric: r'ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:',
  QrMode.byte: 'abcdefghijklmnopqrstuvwxyz!?,;_~@#&()',
};

/// The most characters [version] holds at [level] in [mode].
int capacityOf(int version, QrErrorCorrection level, QrMode mode) {
  final bits = dataCodewords(version, level.index) * 8 - 4;
  final countBits = mode.countBits(version);
  var count = switch (mode) {
    QrMode.numeric => (bits - countBits) * 3 ~/ 10,
    QrMode.alphanumeric => (bits - countBits) * 2 ~/ 11,
    QrMode.byte => (bits - countBits) ~/ 8,
  };
  while (countBits + mode.dataBits(count) > bits) {
    count--;
  }
  return count;
}

/// A case for each version from 1 to 40 and each level: the mode going
/// round the three, the data as long as the version holds at the level in
/// it for half of them, two thirds of that for the others; bytes include
/// some from 0x80 up.
List<QrCase> qrCases() => [
  for (var version = 1; version <= 40; version++)
    for (final level in QrErrorCorrection.values) _case(version, level),
];

QrCase _case(int version, QrErrorCorrection level) {
  final mode = QrMode.values[(version + level.index) % 3];
  final capacity = capacityOf(version, level, mode);
  final count = (version + level.index).isEven
      ? capacity
      : capacity * 2 ~/ 3 + 1;
  final pool = _pools[mode]!;
  var state = version * 4 + level.index + 1;
  int next() {
    // xorshift32
    state ^= (state << 13) & 0xFFFFFFFF;
    state ^= state >> 17;
    state ^= (state << 5) & 0xFFFFFFFF;
    return state;
  }

  final data = [
    for (var i = 0; i < count; i++)
      if (mode == QrMode.byte && next() % 5 == 0)
        0x80 + next() % 0x80
      else
        pool.codeUnitAt(next() % pool.length),
  ];
  return QrCase(version, level, mode, data);
}

/// FNV-1a, 64 bits, of the modules of a symbol [size] modules a side, row
/// by row, a byte each, 1 for dark, as 16 hexadecimal digits.
String moduleHash(int size, bool Function(int x, int y) isDark) {
  var hash = 0xcbf29ce4 << 32 | 0x84222325;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      hash ^= isDark(x, y) ? 1 : 0;
      hash *= 0x100000001b3;
    }
  }
  String hex(int bits) => bits.toRadixString(16).padLeft(8, '0');
  return hex(hash >>> 32) + hex(hash & 0xFFFFFFFF);
}
