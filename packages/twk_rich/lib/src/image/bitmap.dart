import 'dart:typed_data';

/// An image in memory: [width] × [height] pixels of 8-bit red, green, blue
/// and alpha, row by row from the top left, alpha not premultiplied.
final class Bitmap {
  /// A bitmap of transparent black pixels.
  Bitmap(this.width, this.height)
    : assert(width > 0 && height > 0, 'a bitmap has pixels'),
      pixels = Uint8List(width * height * 4);

  /// A bitmap over [pixels], 4 bytes (RGBA) for each pixel, not copied.
  Bitmap.fromRgba(this.width, this.height, this.pixels)
    : assert(width > 0 && height > 0, 'a bitmap has pixels'),
      assert(pixels.length == width * height * 4, 'RGBA for every pixel');

  /// How many pixels each row has.
  final int width;

  /// How many rows of pixels it has.
  final int height;

  /// The RGBA bytes of the pixels, 4 for each, `(y * width + x) * 4` the
  /// first of (x, y).
  final Uint8List pixels;

  /// The pixel at ([x], [y]) as `0xAARRGGBB`.
  int pixel(int x, int y) {
    final i = (y * width + x) * 4;
    return pixels[i + 3] << 24 |
        pixels[i] << 16 |
        pixels[i + 1] << 8 |
        pixels[i + 2];
  }

  /// Sets the pixel at ([x], [y]) to [argb], `0xAARRGGBB`.
  void setPixel(int x, int y, int argb) {
    final i = (y * width + x) * 4;
    pixels[i] = argb >> 16 & 0xFF;
    pixels[i + 1] = argb >> 8 & 0xFF;
    pixels[i + 2] = argb & 0xFF;
    pixels[i + 3] = argb >> 24 & 0xFF;
  }

  /// Whether every pixel's alpha is 255.
  bool get isOpaque {
    final pixels = this.pixels;
    for (var i = 3; i < pixels.length; i += 4) {
      if (pixels[i] != 255) {
        return false;
      }
    }
    return true;
  }

  @override
  String toString() => 'Bitmap($width × $height)';
}
