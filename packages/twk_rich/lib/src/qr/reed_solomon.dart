/// Reed-Solomon error correction as QR codes use it: [ReedSolomon].
library;

import 'dart:typed_data';

/// Reed-Solomon error correction over GF(2⁸) as QR codes use it: the field
/// of the polynomial x⁸ + x⁴ + x³ + x² + 1 (0x11D), α = 2.
final class ReedSolomon {
  ReedSolomon._();

  // α^i for i up to 509, so that a product needs no reduction
  static final Uint8List _exp = () {
    final exp = Uint8List(512);
    var x = 1;
    for (var i = 0; i < 255; i++) {
      exp[i] = x;
      exp[i + 255] = x;
      x <<= 1;
      if (x & 0x100 != 0) {
        x ^= 0x11D;
      }
    }
    return exp;
  }();

  // log_α(x) for x from 1 to 255
  static final Uint8List _log = () {
    final log = Uint8List(256);
    for (var i = 0; i < 255; i++) {
      log[_exp[i]] = i;
    }
    return log;
  }();

  /// The product of [a] and [b] in the field.
  static int multiply(int a, int b) =>
      a == 0 || b == 0 ? 0 : _exp[_log[a] + _log[b]];

  static final _generators = <int, Uint8List>{};

  /// The generator polynomial of [degree] error correction codewords,
  /// (x − α⁰)(x − α¹)…(x − α^(degree−1)): its coefficients from that of
  /// x^degree, which is 1, down to the constant.
  static Uint8List generator(int degree) =>
      _generators[degree] ??= _makeGenerator(degree);

  static Uint8List _makeGenerator(int degree) {
    var g = Uint8List.fromList([1]);
    for (var i = 0; i < degree; i++) {
      // g · (x − αⁱ), subtraction being addition, XOR
      final next = Uint8List(g.length + 1);
      for (var k = 0; k < g.length; k++) {
        next[k] ^= g[k];
        next[k + 1] ^= multiply(g[k], _exp[i]);
      }
      g = next;
    }
    return g;
  }

  /// The [degree] error correction codewords of [data]: the remainder of
  /// data(x) · x^degree divided by the generator polynomial.
  static Uint8List remainder(List<int> data, int degree) {
    final g = generator(degree);
    final r = Uint8List(degree);
    for (final byte in data) {
      final factor = byte ^ r[0];
      r.setRange(0, degree - 1, r, 1);
      r[degree - 1] = 0;
      if (factor != 0) {
        for (var k = 0; k < degree; k++) {
          r[k] ^= multiply(g[k + 1], factor);
        }
      }
    }
    return r;
  }
}
