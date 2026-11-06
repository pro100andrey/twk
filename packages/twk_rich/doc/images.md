# Images: `package:twk_rich/image.dart`

Images for apps on twk_core and twk, in a library of their own that
`package:twk_rich/twk_rich.dart` does not export, so that an app which shows
no image compiles none of it, nor carries the licences the
[README](../README.md#license) names: PNG and JPEG
files decoded, scaled to a box of cells, and encoded for the terminal's
graphics protocol — PNG for kitty and iTerm2, sixel — or drawn with block
characters in coloured cells where there is none; the `Image` widget shows one
in an app. The decoders and encoders use nothing but the Dart SDK (dart:io's
zlib inflates and deflates PNG on the VM; on the web, which has no dart:io, an
inflater of the package's own, and stored deflate blocks, so that a PNG
decodes in a browser too, where `Image.memory` takes the bytes and
`Image.file` throws); the widget depends on twk_core and twk, and its tests on
twk_test, as the rest of twk_rich does. The core places what it encodes: its
`TerminalImage` takes an `EncodedImage`'s `data`, `pixelWidth` and
`pixelHeight` for the protocol it was encoded for. Still images only: an
animated GIF is not read, and an APNG shows its default image.

`lib/image.dart` exports one library per part, `lib/src/image/<part>.dart`;
its tests are in `test/image/`, its examples in `example/image/`.

## `bitmap`

`Bitmap(width, height)`, 8-bit RGBA pixels row by row, alpha not premultiplied
(`pixels`; `pixel(x, y)` and `setPixel` as `0xAARRGGBB`; `isOpaque`);
`Bitmap.fromRgba` over bytes of one's own

## `png`

`decodePng(bytes)`: every colour type at every bit depth PNG allows (grey 1,
2, 4, 8 and 16 bits, RGB 8 and 16, palette 1 to 8, grey and RGB with alpha 8
and 16), interlaced (Adam7) or not, with a tRNS chunk's transparency (alpha
for palette entries, a grey or RGB colour key compared at the full depth); a
16-bit sample keeps its high byte. Gamma and colour space chunks (gAMA, cHRM,
sRGB, iCCP) are ignored, the samples taken as they are, and so are the other
ancillary chunks: an APNG decodes to its default image. Each chunk's CRC is
checked; an unknown critical chunk, a file cut short or one that is not a PNG
is a `FormatException`. `encodePng(image, level: 1)`: 8-bit RGB where the
image is opaque, else RGBA, each row filtered with the filter whose bytes sum
the least (libpng's choice), deflated at zlib `level`, by default 1, the
fastest, since a terminal decodes the file at once. `isPng(bytes)`

## `jpeg`

`decodeJpeg(bytes)`: baseline, extended sequential (16-bit quantization
tables) and progressive JPEG with restart intervals, of one component (grey),
three (YCbCr, or RGB where an Adobe marker says so or the components are named
R, G and B) or four (CMYK and YCCK, the inks inverted as Adobe stores them),
any sampling factors from 1 to 4. Its samples are libjpeg's: the integer IDCT
and colour conversion are libjpeg's own, so that it decodes as `djpeg -dct int
-nosmooth` does, byte for byte; subsampled chroma is replicated, not
interpolated. Not read: arithmetic coding, lossless, hierarchical and 12-bit
JPEG, a height given by a DNL marker (each a `FormatException`); the Exif
orientation and colour profiles are not applied. Entropy-coded data cut short
decodes as zeros. `isJpeg(bytes)`

## `image_file`

`decodeImage(bytes)`, a PNG or JPEG file by its first bytes
(`ImageFormat.of`); `imageSize(bytes)`, its `(width:, height:)` from its
header (IHDR, the frame's SOF) without decoding it

## `scale`

`CellSize(width, height)`, a cell's pixels; `CellSize.reported(w, h)` the size
a terminal reports (the core's `TerminalCaps.cellPixelWidth` and
`cellPixelHeight`), `CellSize.fallback` (10 × 20) where it reports none (0).
`CellFit(imageWidth, imageHeight, columns:, rows:, cell:, fit:, bandHeight:
1)`: where an image goes in a box of cells — `ImageFit.contain` (all of it, as
large as fits, aspect kept), `cover` (the box covered, aspect kept, as much
cut from either side), `fill` (stretched), `scaleDown` (contained, never
enlarged); its `columns` and `rows` are the cells it takes from the box's top
left, `width` and `height` the pixels it is scaled to, `cropX`, `cropY`,
`cropWidth`, `cropHeight` the part of the image shown, `scale(image)` the
image so scaled; the box's height is taken down to a multiple of `bandHeight`.
`resize(image, width, height, cropX:, cropY:, cropWidth:, cropHeight:)`:
shrinking, each pixel the mean of those under it, weighed by how much of each
is; growing, bilinear; alpha premultiplied, so that a transparent pixel's
colour does not bleed

## `sixel`

`encodeSixel(image, colors: 256, dither: true, background:)`: the bytes a
terminal takes between `ESC P` and `ESC \` — `0;1;0` (pixels not drawn keep
what is under them), `q`, the raster attributes `"1;1;W;H`, the palette in
percent, the bands of six rows a colour at a time, runs of four or more `!n`.
The palette is the image's own colours where it has no more than `colors`,
else median cut's (5 bits a channel, the box with the most pixels times its
longest side split at its median), Floyd–Steinberg dithered where `dither`
says. A pixel whose alpha is below 128 is not drawn; where `background` is
given, every pixel is blended over it

## `blocks`

`BlockImage(image, columns:, rows:, cell:, fit:, mode:, background:)`, the
fallback for a terminal without graphics: the image fitted to the box
(`CellFit`) and drawn in `BlockCell`s, a `glyph` in `fg` on `bg` (`0xRRGGBB`,
null for what is under the cell) — `BlockMode.half`, two pixels a cell, `▀` in
the upper's colour on the lower's (`▄` where only the lower is drawn), or
`quadrant`, four pixels a cell, the quadrant block that splits them best in
two colours. `BlockImage.fromPixels(bitmap, mode:)` draws a bitmap's pixels as
they are; `cells`, `cellAt(column, row)`; `toAnsi()`, the rows as text with
24-bit SGR colours, to print as they are

## `protocols`

`EncodedImage(data, pixelWidth:, pixelHeight:)`, what the core's
`TerminalImage` takes. `kittyImage(file)`: a PNG file as it is, a JPEG one
decoded and encoded as PNG. `iterm2Image(file)`: a PNG or JPEG file as it is,
which iTerm2 decodes, its size read from its header. `pngImage(bitmap)`: a
bitmap made or cut in memory, for either. `sixelImage(image, columns:, rows:,
cell:, fit:, colors:, dither:, background:)`: scaled to the box, no taller
than it in whole bands of six pixels (`CellFit(bandHeight: 6)`), so that the
last band does not scroll the terminal, and encoded with `encodeSixel`. The
core scales kitty and iTerm2 images to the cells it places them in itself;
sixel is drawn at its pixels, so it is scaled here

## `widget`

`Image(source, width:, height:, fit:, alignment:, blockMode:, forceBlocks:)`,
with `Image.memory(bytes)`, `Image.file(path)` (read when first laid out) and
`Image.bitmap(bitmap)` for the `ImageSource`s; `RenderImage` lays it out and
paints it. The box is `width` × `height` cells where given, within the
constraints; an axis left out follows from the other by the image's aspect at
the cell size the terminal reports (`TerminalCaps.cellPixelWidth`,
`cellPixelHeight`; `CellSize.fallback` where it reports none), and without
either it is the cells the image's pixels take, made smaller or larger within
the constraints with its aspect kept. The image fills it as `fit` says
(`CellFit`), placed by `alignment` in the cells it leaves. It is shown with
the protocol of the presenter it is painted for (`TerminalCaps.graphics`,
which the probe or `TWK_GRAPHICS` picks when the app starts): kitty and iTerm2
get a PNG of the fitted image as big as its cells, transparent past it, so
that the terminal does not stretch it; sixel is scaled in whole bands of six
pixels. Where the protocol is none, or with `forceBlocks`, it is drawn in
`BlockImage` cells of `blockMode`, a transparent pixel leaving the cell under
it. The file is read and its size taken from its header at the first layout,
decoded at the first paint; what is drawn is kept until the box, the protocol
or a property changes, so that the presenter places the same image again
without sending it. A file that can't be read or decoded is an error shown in
its place. Clipped, a kitty image shows what is left of it, a sixel or iTerm2
one is not shown

## Examples

`example/image/viewer.dart` shows the PNG or JPEG file it is given below its
name and above the keys: `f` cycles the fit, `p` what it is drawn with — the
terminal's protocol, half blocks, quadrants — and `q` quits. The protocol is
the terminal's for the whole run, as the probe finds it when the app starts or
as `TWK_GRAPHICS` names it (`kitty`, `sixel`, `iterm2`, `none`):

```bash
dart run example/image/viewer.dart photo.jpg
TWK_GRAPHICS=sixel dart run example/image/viewer.dart photo.png
```

`example/image/konsole_images.dart` shows a kitty image in a header above a
log that scrolls in hardware, for Konsole, which moves every image up on any
scroll up ([the core's
doc/konsole-kitty.md](../../twk_core/doc/konsole-kitty.md)): the picture must
stay in the header.
