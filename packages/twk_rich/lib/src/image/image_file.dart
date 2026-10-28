import 'dart:typed_data';

import 'bitmap.dart';
import 'jpeg.dart';
import 'png.dart';

// Examples can assume:
// import 'dart:io';

/// The formats of image files this package reads.
enum ImageFormat {
  /// PNG ([decodePng]).
  png,

  /// JPEG ([decodeJpeg]).
  jpeg;

  /// The format of the file [bytes] by its first bytes; null for neither.
  static ImageFormat? of(List<int> bytes) => isPng(bytes)
      ? png
      : isJpeg(bytes)
      ? jpeg
      : null;
}

/// Decodes a PNG or JPEG file, the format told by its first bytes
/// ([decodePng], [decodeJpeg]).
///
/// Throws a [FormatException] for a file of neither format, or one that
/// does not decode.
///
/// ```dart
/// final image = decodeImage(File('photo.jpg').readAsBytesSync());
/// print('${image.width} × ${image.height}, opaque: ${image.isOpaque}');
/// ```
Bitmap decodeImage(Uint8List bytes) => switch (ImageFormat.of(bytes)) {
  ImageFormat.png => decodePng(bytes),
  ImageFormat.jpeg => decodeJpeg(bytes),
  null => throw const FormatException('Neither a PNG nor a JPEG file'),
};

/// The size in pixels of the PNG or JPEG file [bytes], read from its
/// header (IHDR, or the first frame's SOF) without decoding it.
///
/// Throws a [FormatException] for a file of neither format, or one whose
/// header is cut short.
({int width, int height}) imageSize(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  switch (ImageFormat.of(bytes)) {
    case ImageFormat.png:
      if (bytes.length < 24 || data.getUint32(12) != 0x49484452) {
        throw const FormatException('PNG file does not start with IHDR');
      }
      return (width: data.getUint32(16), height: data.getUint32(20));
    case ImageFormat.jpeg:
      var pos = 2;
      while (pos + 4 <= bytes.length) {
        if (bytes[pos] != 0xFF) {
          pos++;
          continue;
        }
        final marker = bytes[pos + 1];
        if (marker == 0xFF) {
          pos++;
          continue;
        }
        if (marker == 0x01 || marker >= 0xD0 && marker <= 0xD8) {
          pos += 2;
          continue;
        }
        final isFrame =
            marker >= 0xC0 &&
            marker <= 0xCF &&
            marker != 0xC4 &&
            marker != 0xC8 &&
            marker != 0xCC;
        if (isFrame) {
          if (pos + 9 > bytes.length) {
            break;
          }
          return (
            width: data.getUint16(pos + 7),
            height: data.getUint16(pos + 5),
          );
        }
        pos += 2 + data.getUint16(pos + 2);
      }
      throw const FormatException('JPEG file without a frame');
    case null:
      throw const FormatException('Neither a PNG nor a JPEG file');
  }
}
