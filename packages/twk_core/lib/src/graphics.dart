/// Images in cells: what a render object hands the presenter (a
/// [TerminalImage] shown by [Canvas.image], kept on the surface as an
/// [ImagePlacement]) and the sequences of the protocols terminals show
/// them with ([GraphicsProtocol]).
///
/// @docImport 'canvas.dart';
/// @docImport 'presenter.dart';
/// @docImport 'surface.dart';
library;

import 'dart:convert';
import 'dart:typed_data';

import 'byte_sink.dart';
import 'terminal/sequences.dart';

// Examples can assume:
// import 'dart:typed_data';
// late Uint8List png;
// late Canvas canvas;

/// How a terminal shows images.
enum GraphicsProtocol {
  /// It shows none: the cells of an image stay blank.
  none,

  /// kitty's graphics protocol (kitty, Ghostty, WezTerm, Konsole): an
  /// image is sent once, under an id, and placed by a placement id, which
  /// a scroll or a move places again without sending the image.
  kitty,

  /// DEC sixel (xterm, foot, mlterm, WezTerm, Windows Terminal, tmux 3.4):
  /// the image's pixels are its cells', sent again whenever they move.
  sixel,

  /// iTerm2's inline images (OSC 1337 `File`; iTerm2, WezTerm): as
  /// [sixel].
  iterm2,
}

/// An image encoded for [protocol], shown in a rectangle of cells
/// ([Canvas.image]) and scaled to fill it.
///
/// The same object is the same image from frame to frame: one made anew is
/// sent anew. A terminal whose [TerminalCaps.graphics] is another protocol
/// shows nothing of it; `package:twk_rich/image.dart` decodes PNG and JPEG
/// and encodes them for the terminal's protocol.
///
/// A PNG file's bytes (`png`, 64 x 32 pixels) for kitty, drawn in the 8 x 4
/// cells at the canvas's origin:
///
/// ```dart
/// final image = TerminalImage(
///   GraphicsProtocol.kitty,
///   png,
///   pixelWidth: 64,
///   pixelHeight: 32,
/// );
/// canvas.image(0, 0, 8, 4, image);
/// ```
final class TerminalImage {
  /// An image of [pixelWidth] x [pixelHeight] pixels, [data] encoded for
  /// [protocol].
  TerminalImage(
    this.protocol,
    this.data, {
    required this.pixelWidth,
    required this.pixelHeight,
  });

  /// The protocol [data] is encoded for.
  final GraphicsProtocol protocol;

  /// What is sent: for [GraphicsProtocol.kitty] PNG file bytes, for
  /// [GraphicsProtocol.iterm2] an image file iTerm2 decodes (PNG, JPEG),
  /// for [GraphicsProtocol.sixel] the bytes between `ESC P` and `ESC \`:
  /// the parameters, `q`, the raster attributes (`"1;1;W;H`), the palette
  /// and the sixels, no taller than the cells (or the terminal scrolls).
  final Uint8List data;

  /// The image's width in pixels; kitty shows the part of it that a clip
  /// leaves by this and [pixelHeight].
  final int pixelWidth;

  /// The image's height in pixels (see [pixelWidth]).
  final int pixelHeight;

  /// [data] in base64, encoded once.
  late final Uint8List _base64 = ascii.encode(base64.encode(data));
}

/// An image on a surface: [image] fills the [cols] x [rows] cells from
/// ([x], [y]), of which those from ([left], [top]) to ([right], [bottom]),
/// reserved, are shown; the rest is off the surface or cut off by a clip.
///
/// [Canvas.image] makes one and puts it on its surface ([Surface.place]);
/// a scroll of the surface moves it ([Surface.scrollRows]), and the
/// presenter writes it with the protocol of its image.
final class ImagePlacement {
  /// [image] filling the [cols] x [rows] cells from ([x], [y]), the cells
  /// from ([left], [top]) to ([right], [bottom]) of them shown.
  ImagePlacement(
    this.image,
    this.x,
    this.y,
    this.cols,
    this.rows,
    this.left,
    this.top,
    this.right,
    this.bottom,
  );

  /// The image placed.
  final TerminalImage image;

  /// The surface column of the image's first column, which may be left of
  /// the surface.
  int x;

  /// The surface row of the image's first row, which may be above the
  /// surface; a scroll moves it.
  int y;

  /// How many columns the whole image fills.
  final int cols;

  /// How many rows the whole image fills.
  final int rows;

  /// The first column shown.
  int left;

  /// The first row shown.
  int top;

  /// The column after the last shown.
  int right;

  /// The row after the last shown.
  int bottom;

  /// All of the image is shown.
  bool get whole =>
      left == x && top == y && right == x + cols && bottom == y + rows;

  /// [p] is the same image in the same cells.
  bool sameAs(ImagePlacement p) =>
      identical(image, p.image) &&
      x == p.x &&
      y == p.y &&
      cols == p.cols &&
      rows == p.rows &&
      left == p.left &&
      top == p.top &&
      right == p.right &&
      bottom == p.bottom;

  /// The cells shown meet those of [p].
  bool overlaps(ImagePlacement p) =>
      left < p.right && p.left < right && top < p.bottom && p.top < bottom;

  @override
  String toString() =>
      '${image.protocol.name} ${cols}x$rows at ($x, $y), shown '
      '($left, $top)-($right, $bottom)';
}

/// The bytes that place [p] at the cursor as placement [placement] of
/// kitty image [id], in the cells shown and of the image what they show;
/// with [transmit] the image is sent first, in the same command. The
/// cursor stays where it is (`C=1`), and the terminal answers nothing
/// (`q=2`).
void kittyPlace(
  ByteSink out,
  ImagePlacement p, {
  required int id,
  required int placement,
  required bool transmit,
  Multiplexer multiplexer = Multiplexer.none,
}) {
  final sb = StringBuffer(transmit ? 'a=T,f=100,t=d,' : 'a=p,')
    ..write('i=$id,p=$placement,c=${p.right - p.left},r=${p.bottom - p.top}');
  if (!p.whole) {
    final image = p.image;
    int at(int cell, int cells, int pixels) => pixels * cell ~/ cells;
    final x0 = at(p.left - p.x, p.cols, image.pixelWidth);
    final x1 = at(p.right - p.x, p.cols, image.pixelWidth);
    final y0 = at(p.top - p.y, p.rows, image.pixelHeight);
    final y1 = at(p.bottom - p.y, p.rows, image.pixelHeight);
    sb.write(',x=$x0,y=$y0,w=${x1 - x0},h=${y1 - y0}');
  }
  sb.write(',C=1,q=2');
  if (!transmit) {
    _put(out, '\x1b_G$sb\x1b\\', multiplexer);
    return;
  }
  // chunks of at most 4096 bytes of base64, all but the last with m=1
  const chunk = 4096;
  final data = p.image._base64;
  for (var i = 0; i < data.length || i == 0; i += chunk) {
    final end = i + chunk < data.length ? i + chunk : data.length;
    final more = end < data.length ? 'm=1' : (i == 0 ? '' : 'm=0');
    final keys = i == 0 ? (more.isEmpty ? '$sb' : '$sb,$more') : more;
    putImageData(out, '\x1b_G$keys;', data, i, end, '\x1b\\', multiplexer);
  }
}

/// The bytes that delete placement [placement] of kitty image [id]; with
/// [placement] 0 every placement of it, and the image itself.
void kittyDelete(
  ByteSink out, {
  required int id,
  int placement = 0,
  Multiplexer multiplexer = Multiplexer.none,
}) => _put(
  out,
  placement == 0
      ? '\x1b_Ga=d,d=I,i=$id,q=2\x1b\\'
      : '\x1b_Ga=d,d=i,i=$id,p=$placement,q=2\x1b\\',
  multiplexer,
);

/// The bytes that draw the sixel image of [p] at the cursor and put the
/// cursor back (DECSC, DECRC), with the cursor left to the right of the
/// image meanwhile (DEC mode 8452), so that an image on the last row
/// doesn't scroll the screen.
void sixelDraw(
  ByteSink out,
  ImagePlacement p, {
  Multiplexer multiplexer = Multiplexer.none,
}) {
  out.ascii('\x1b7\x1b[?8452h');
  final data = p.image.data;
  putImageData(out, '\x1bP', data, 0, data.length, '\x1b\\', multiplexer);
  out.ascii('\x1b[?8452l\x1b8');
}

/// The bytes that draw the iTerm2 image of [p] at the cursor, scaled to
/// its cells, the cursor kept where it is (`doNotMoveCursor`, and DECSC,
/// DECRC where that is not known).
void iterm2Draw(
  ByteSink out,
  ImagePlacement p, {
  Multiplexer multiplexer = Multiplexer.none,
}) {
  final image = p.image;
  out.ascii('\x1b7');
  putImageData(
    out,
    '\x1b]1337;File=inline=1;size=${image.data.length};width=${p.cols};'
        'height=${p.rows};preserveAspectRatio=0;doNotMoveCursor=1:',
    image._base64,
    0,
    image._base64.length,
    '\x07',
    multiplexer,
  );
  out.ascii('\x1b8');
}

/// [s] (ASCII), wrapped for [multiplexer].
void _put(ByteSink out, String s, Multiplexer multiplexer) =>
    out.ascii(passthroughSequence(s, multiplexer));

/// [head], bytes [start, end) of [data] and [tail], wrapped for
/// [multiplexer] as [passthroughSequence] wraps them: the data (base64,
/// sixel: ASCII without ESC) written as it is, not copied into a string.
/// Not exported; public for its test.
void putImageData(
  ByteSink out,
  String head,
  Uint8List data,
  int start,
  int end,
  String tail,
  Multiplexer multiplexer,
) {
  switch (multiplexer) {
    case Multiplexer.none:
      out
        ..ascii(head)
        ..bytes(Uint8List.sublistView(data, start, end))
        ..ascii(tail);
    case Multiplexer.tmux:
      out
        ..ascii('\x1bPtmux;${head.replaceAll('\x1b', '\x1b\x1b')}')
        ..bytes(Uint8List.sublistView(data, start, end))
        ..ascii('${tail.replaceAll('\x1b', '\x1b\x1b')}\x1b\\');
    case Multiplexer.screen:
      // pieces of 252 bytes of the whole, one byte a character
      final h = head.replaceAll('\x1b\\', '\x07');
      final t = tail.replaceAll('\x1b\\', '\x07');
      final dataEnd = h.length + end - start;
      final length = dataEnd + t.length;
      for (var at = 0; at < length; at += 252) {
        final to = at + 252 < length ? at + 252 : length;
        out.ascii('\x1bP');
        if (at < h.length) {
          out.ascii(h.substring(at, to < h.length ? to : h.length));
        }
        if (to > h.length && at < dataEnd) {
          final from = at > h.length ? at : h.length;
          final until = to < dataEnd ? to : dataEnd;
          out.bytes(
            Uint8List.sublistView(
              data,
              start + from - h.length,
              start + until - h.length,
            ),
          );
        }
        if (to > dataEnd) {
          out.ascii(
            t.substring((at > dataEnd ? at : dataEnd) - dataEnd, to - dataEnd),
          );
        }
        out.ascii('\x1b\\');
      }
  }
}
