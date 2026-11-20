import 'dart:typed_data';

import 'bitmap.dart';
import 'image_file.dart';
import 'png.dart';
import 'scale.dart';
import 'sixel.dart';

// Examples can assume:
// import 'dart:io';
// import 'package:twk_core/twk_core.dart';
// late Canvas canvas;

/// An image encoded for a terminal's graphics protocol: [data] as the
/// core's `TerminalImage` takes it for that protocol, and its size in
/// pixels.
final class EncodedImage {
  /// [data] for a protocol, an image of [pixelWidth] × [pixelHeight]
  /// pixels.
  const EncodedImage(
    this.data, {
    required this.pixelWidth,
    required this.pixelHeight,
  });

  /// The bytes the protocol takes: a PNG or JPEG file, or sixel.
  final Uint8List data;

  /// The image's width in pixels.
  final int pixelWidth;

  /// The image's height in pixels.
  final int pixelHeight;

  @override
  String toString() =>
      'EncodedImage($pixelWidth × $pixelHeight, ${data.length} bytes)';
}

/// The PNG, JPEG or GIF file [bytes] for kitty's graphics protocol, which
/// takes PNG: the file as it is where it is a PNG, else decoded and encoded
/// as one ([encodePng]); of an animated GIF or APNG, its first frame (the
/// `Image` widget plays one on kitty by frames of its own). The terminal
/// scales it to the cells it is placed in.
///
/// Throws a [FormatException] for a file of none of the formats, or one
/// that does not decode.
///
/// Placed by the core in a box of 40 × 20 cells:
///
/// ```dart
/// final encoded = kittyImage(File('photo.jpg').readAsBytesSync());
/// final image = TerminalImage(
///   GraphicsProtocol.kitty,
///   encoded.data,
///   pixelWidth: encoded.pixelWidth,
///   pixelHeight: encoded.pixelHeight,
/// );
/// canvas.image(0, 0, 40, 20, image);
/// ```
EncodedImage kittyImage(Uint8List bytes) {
  if (ImageFormat.of(bytes) == ImageFormat.png) {
    final size = imageSize(bytes);
    return EncodedImage(
      bytes,
      pixelWidth: size.width,
      pixelHeight: size.height,
    );
  }
  return pngImage(decodeImage(bytes));
}

/// The PNG, JPEG or GIF file [bytes] for iTerm2's inline images, which
/// decode all three: the file as it is, its size read from its header. An
/// animated GIF goes as it is: iTerm2 plays it itself.
///
/// Throws a [FormatException] for a file of none of the formats.
EncodedImage iterm2Image(Uint8List bytes) {
  final size = imageSize(bytes);
  return EncodedImage(bytes, pixelWidth: size.width, pixelHeight: size.height);
}

/// [image] as a PNG file ([encodePng]), for kitty or iTerm2: an image made
/// or changed in memory, such as one cut to the part a [CellFit] shows.
EncodedImage pngImage(Bitmap image) => EncodedImage(
  encodePng(image),
  pixelWidth: image.width,
  pixelHeight: image.height,
);

/// [image] scaled to a box of [columns] × [rows] cells of [cell]'s size as
/// [fit] says, and encoded as sixel ([encodeSixel]); [colors], [dither]
/// and [background] as there.
///
/// It is no taller than the box in whole bands of six pixels
/// (`CellFit(bandHeight: 6)`), so that its last band does not scroll the
/// terminal. The cells it takes are the `columns` and `rows` of that fit.
EncodedImage sixelImage(
  Bitmap image, {
  required int columns,
  required int rows,
  CellSize cell = CellSize.fallback,
  ImageFit fit = ImageFit.contain,
  int colors = 256,
  bool dither = true,
  int? background,
}) {
  final fitted = CellFit(
    image.width,
    image.height,
    columns: columns,
    rows: rows,
    cell: cell,
    fit: fit,
    bandHeight: 6,
  );
  return EncodedImage(
    encodeSixel(
      fitted.scale(image),
      colors: colors,
      dither: dither,
      background: background,
    ),
    pixelWidth: fitted.width,
    pixelHeight: fitted.height,
  );
}
