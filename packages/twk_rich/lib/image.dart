/// Images for the terminal: PNG and JPEG files decoded to a `Bitmap`,
/// scaled to a box of cells (`CellFit`), and encoded for a graphics
/// protocol (`kittyImage`, `iterm2Image`, `sixelImage`) or drawn with block
/// characters where there is none (`BlockImage`); the `Image` widget shows
/// one in an app, with the terminal's protocol or in blocks.
///
/// A library of its own, which `package:twk_rich/twk_rich.dart` does not
/// export: an app that shows no image compiles none of it. Its JPEG decoder
/// is derived in part from the Independent JPEG Group's libjpeg and from
/// jpgjs (pdf.js, package:image), whose licences the package's NOTICE and
/// README.ijg carry for an executable that imports this library.
library;

export 'src/image/bitmap.dart';
export 'src/image/blocks.dart';
export 'src/image/image_file.dart';
export 'src/image/jpeg.dart';
export 'src/image/png.dart';
export 'src/image/protocols.dart';
export 'src/image/scale.dart';
export 'src/image/sixel.dart';
export 'src/image/widget.dart';
