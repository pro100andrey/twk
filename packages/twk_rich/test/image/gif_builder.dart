import 'dart:typed_data';

/// One image of a GIF made by [gifBytes]: [indices] (colour indices of its
/// [width] × [height] pixels, row by row as stored) at ([left], [top]).
final class GifImage {
  GifImage(
    this.width,
    this.height,
    this.indices, {
    this.left = 0,
    this.top = 0,
    this.delayCs = 0,
    this.disposal = 0,
    this.transparent,
    this.interlaced = false,
    this.localColors,
  });

  final int width;
  final int height;
  final List<int> indices;
  final int left;
  final int top;
  final int delayCs;
  final int disposal;
  final int? transparent;
  final bool interlaced;

  /// A local colour table, RGB triples.
  final List<int>? localColors;
}

/// A GIF file of a [width] × [height] screen with the global colours
/// [colors] (RGB triples), [images], and [loop] as NETSCAPE2.0's count
/// where not null. The LZW data is literal codes with a clear code between
/// short runs, which any decoder reads and which needs no encoder.
Uint8List gifBytes(
  int width,
  int height,
  List<int> colors,
  List<GifImage> images, {
  int? loop,
  bool header89 = true,
  bool trailer = true,
}) {
  final out = BytesBuilder();
  void u16(int v) => out.add([v & 0xFF, v >> 8 & 0xFF]);
  out.add(header89 ? 'GIF89a'.codeUnits : 'GIF87a'.codeUnits);
  u16(width);
  u16(height);
  final bits = _tableBits(colors.length ~/ 3);
  out
    ..addByte(0x80 | (bits - 1))
    ..addByte(0)
    ..addByte(0)
    ..add(_padded(colors, bits));
  if (loop != null) {
    out
      ..add([0x21, 0xFF, 11])
      ..add('NETSCAPE2.0'.codeUnits)
      ..add([3, 1, loop & 0xFF, loop >> 8, 0]);
  }
  for (final image in images) {
    if (header89) {
      out
        ..add([0x21, 0xF9, 4])
        ..addByte(
          image.disposal << 2 | (image.transparent != null ? 1 : 0),
        );
      u16(image.delayCs);
      out
        ..addByte(image.transparent ?? 0)
        ..addByte(0);
    }
    out.addByte(0x2C);
    u16(image.left);
    u16(image.top);
    u16(image.width);
    u16(image.height);
    final local = image.localColors;
    final localBits = local == null ? 0 : _tableBits(local.length ~/ 3);
    out.addByte(
      (local != null ? 0x80 | (localBits - 1) : 0) |
          (image.interlaced ? 0x40 : 0),
    );
    if (local != null) {
      out.add(_padded(local, localBits));
    }
    final tableBits = local != null ? localBits : bits;
    final minimum = tableBits < 2 ? 2 : tableBits;
    out.addByte(minimum);
    final data = _literal(image.indices, minimum);
    for (var i = 0; i < data.length; i += 255) {
      final n = data.length - i < 255 ? data.length - i : 255;
      out
        ..addByte(n)
        ..add(data.sublist(i, i + n));
    }
    out.addByte(0);
  }
  if (trailer) {
    out.addByte(0x3B);
  }
  return out.takeBytes();
}

/// The bits of the index of a table of [colors] colours (at least 1).
int _tableBits(int colors) {
  var bits = 1;
  while (1 << bits < colors) {
    bits++;
  }
  return bits;
}

List<int> _padded(List<int> colors, int bits) => [
  ...colors,
  ...List.filled((3 << bits) - colors.length, 0),
];

/// [indices] as LZW codes of [minimum] bits plus one, a clear code before
/// each run short enough that the code size does not grow.
List<int> _literal(List<int> indices, int minimum) {
  final clear = 1 << minimum;
  final size = minimum + 1;
  final run = (1 << minimum) - 2;
  final bytes = <int>[];
  var accumulated = 0;
  var count = 0;
  void code(int c) {
    accumulated |= c << count;
    count += size;
    while (count >= 8) {
      bytes.add(accumulated & 0xFF);
      accumulated >>= 8;
      count -= 8;
    }
  }

  for (var i = 0; i < indices.length; i += run) {
    code(clear);
    for (var j = i; j < i + run && j < indices.length; j++) {
      code(indices[j]);
    }
  }
  code(clear + 1);
  if (count > 0) {
    bytes.add(accumulated & 0xFF);
  }
  return bytes;
}
