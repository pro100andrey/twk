/// Images in cells: what a render object hands the presenter (a
/// [TerminalImage] shown by [Canvas.image], kept on the surface as an
/// [ImagePlacement]) and the sequences of the protocols terminals show
/// them with ([GraphicsProtocol]).
///
/// @docImport 'canvas.dart';
/// @docImport 'presenter.dart';
/// @docImport 'surface.dart';
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'byte_sink.dart';
import 'terminal/sequences.dart';

// Examples can assume:
// import 'dart:typed_data';
// late Uint8List png;
// late Uint8List red;
// late Uint8List blue;
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
  /// [protocol]; for kitty with [animation], [data] is its first frame.
  TerminalImage(
    this.protocol,
    this.data, {
    required this.pixelWidth,
    required this.pixelHeight,
    this.animation,
    this.keep,
  }) : assert(
         animation == null || protocol == GraphicsProtocol.kitty,
         'only kitty plays an animation itself',
       );

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

  /// kitty: the frames after the first, which a terminal that plays them
  /// ([TerminalCaps.kittyAnimation]) is sent once with the image and plays
  /// on its own clock; another shows [data], the first. Null for a still
  /// image.
  final ImageAnimation? animation;

  /// kitty: while it is [ImageKeep.kept], the terminal keeps this image
  /// when no placement shows it, so that, shown again, it is placed and not
  /// sent: the frames of an animation drawn one by one on a terminal that
  /// does not play them, each sent once. Null: deleted once not shown.
  final ImageKeep? keep;

  /// Whether the terminal plays [animation]: false stops it at the frame
  /// it shows, true goes on from there. The presenter writes a change with
  /// its next frame, so whoever sets it asks for one.
  var playing = true;

  /// [data] in base64, encoded once.
  late final Uint8List _base64 = ascii.encode(base64.encode(data));
}

/// The frames of an animated kitty image after its first
/// ([TerminalImage.data]), each a PNG file of the whole image as it looks
/// while the frame shows, the time each frame shows, the first's too, and
/// how many times they play. They are there from the start, or come as
/// they are made ([ImageAnimation.loading]).
///
/// Two frames, red then blue (`red` and `blue`, PNG files of 64 x 32
/// pixels), half a second each, for ever:
///
/// ```dart
/// final image = TerminalImage(
///   GraphicsProtocol.kitty,
///   red,
///   pixelWidth: 64,
///   pixelHeight: 32,
///   animation: ImageAnimation(
///     [blue],
///     const [Duration(milliseconds: 500), Duration(milliseconds: 500)],
///   ),
/// );
/// ```
final class ImageAnimation {
  /// [frames] after the first, shown for [delays] (one more than [frames],
  /// the first frame's first), played [loops] times; 0, the default, for
  /// ever.
  ImageAnimation(
    List<Uint8List> frames,
    List<Duration> delays, {
    this.loops = 0,
  }) : assert(frames.isNotEmpty, 'an animation has a second frame'),
       assert(
         delays.length == frames.length + 1,
         'a delay for each frame, the first too',
       ),
       assert(loops >= 0, 'loops is 0 (for ever) or more'),
       _frames = [...frames],
       _delays = [...delays],
       _complete = true;

  /// One whose frames after the first come as they are made ([add]), until
  /// [finish]: a terminal plays those it has been sent, and waits at the
  /// last for more (kitty's loading mode), so that a long animation shows
  /// before all of it is made. The first frame shows for [firstDelay].
  ImageAnimation.loading(Duration firstDelay, {this.loops = 0})
    : assert(loops >= 0, 'loops is 0 (for ever) or more'),
      _frames = [],
      _delays = [firstDelay],
      _complete = false;

  final List<Uint8List> _frames;
  final List<Duration> _delays;
  bool _complete;

  /// The PNG files of the frames after the first, so far.
  List<Uint8List> get frames => UnmodifiableListView(_frames);

  /// How long each frame shows, the first frame's first.
  List<Duration> get delays => UnmodifiableListView(_delays);

  /// How many times the frames play; 0 for ever. The last frame stays.
  final int loops;

  /// Whether all the frames are there: from the start, or since [finish].
  bool get complete => _complete;

  /// Adds the next [frame], a PNG file, shown for [delay]; the presenter
  /// sends it with its next frame, so whoever adds it asks for one.
  void add(Uint8List frame, Duration delay) {
    assert(!_complete, 'an animation that is complete takes no frame');
    _frames.add(frame);
    _delays.add(delay);
  }

  /// All the frames are there: the terminal plays them through, as many
  /// times as [loops] says.
  void finish() => _complete = true;

  /// What the terminal was last sent of it ([kittyAnimate]): how many of
  /// [frames], and whether it plays: 0 nothing said, 1 stopped, 2 playing
  /// what it has and waiting for more, 3 playing them all.
  var _sent = 0;
  var _state = 0;
}

/// What keeps kitty images on the terminal while no placement shows them
/// ([TerminalImage.keep]), for as long as [kept] is true: the images of an
/// animation's frames share one, which its owner lets go of when the
/// animation goes (another source, another size, out of the tree). The
/// presenter deletes the images of one let go of with its next frame.
final class ImageKeep {
  /// Kept from the start.
  ImageKeep();

  /// Whether the images are kept; false lets them go, true again keeps
  /// those the terminal still has.
  var kept = true;
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
  if (!transmit && multiplexer == Multiplexer.none) {
    _kittyPlaceDirect(out, p, id: id, placement: placement);
    return;
  }
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
  _kittyData(out, '$sb', p.image._base64, multiplexer);
}

/// [kittyPlace] of an image the terminal has, outside a multiplexer: the
/// command written as it goes, no string made for it (a placement each
/// frame of an animation drawn one frame at a time).
void _kittyPlaceDirect(
  ByteSink out,
  ImagePlacement p, {
  required int id,
  required int placement,
}) {
  out
    ..ascii('\x1b_Ga=p,i=')
    ..decimal(id)
    ..ascii(',p=')
    ..decimal(placement)
    ..ascii(',c=')
    ..decimal(p.right - p.left)
    ..ascii(',r=')
    ..decimal(p.bottom - p.top);
  if (!p.whole) {
    final image = p.image;
    final x0 = image.pixelWidth * (p.left - p.x) ~/ p.cols;
    final x1 = image.pixelWidth * (p.right - p.x) ~/ p.cols;
    final y0 = image.pixelHeight * (p.top - p.y) ~/ p.rows;
    final y1 = image.pixelHeight * (p.bottom - p.y) ~/ p.rows;
    out
      ..ascii(',x=')
      ..decimal(x0)
      ..ascii(',y=')
      ..decimal(y0)
      ..ascii(',w=')
      ..decimal(x1 - x0)
      ..ascii(',h=')
      ..decimal(y1 - y0);
  }
  out.ascii(',C=1,q=2\x1b\\');
}

/// kitty command [keys] with [data] (base64) in chunks of at most 4096
/// bytes, all but the last with `m=1`, the keys on the first alone.
void _kittyData(
  ByteSink out,
  String keys,
  Uint8List data,
  Multiplexer multiplexer,
) {
  const chunk = 4096;
  for (var i = 0; i < data.length || i == 0; i += chunk) {
    final end = i + chunk < data.length ? i + chunk : data.length;
    final more = end < data.length ? 'm=1' : (i == 0 ? '' : 'm=0');
    final head = i == 0 ? (more.isEmpty ? keys : '$keys,$more') : more;
    putImageData(out, '\x1b_G$head;', data, i, end, '\x1b\\', multiplexer);
  }
}

/// The bytes that give kitty image [id], just sent with its first frame,
/// the first frame's time (`a=a,r=1`) and then what [kittyAnimationUpdate]
/// writes of [animation]: the terminal has none of the rest yet.
void kittyAnimate(
  ByteSink out,
  ImageAnimation animation, {
  required int id,
  required bool playing,
  Multiplexer multiplexer = Multiplexer.none,
}) {
  animation
    .._sent = 0
    .._state = 0;
  _put(
    out,
    '\x1b_Ga=a,i=$id,r=1,z=${_gap(animation._delays.first)},q=2\x1b\\',
    multiplexer,
  );
  kittyAnimationUpdate(
    out,
    animation,
    id: id,
    playing: playing,
    multiplexer: multiplexer,
  );
}

/// The bytes that bring kitty image [id]'s [animation] up to date on the
/// terminal: the frames added since it was last sent (`a=f`, each with the
/// time it shows), then, where it changed, whether it plays: stopped where
/// it is (`s=1`) without [playing], else run, waiting at the last frame for
/// more (`s=2`) until the animation is complete, then through them all as
/// many times as it plays (`s=3`). Nothing where nothing changed.
void kittyAnimationUpdate(
  ByteSink out,
  ImageAnimation animation, {
  required int id,
  required bool playing,
  Multiplexer multiplexer = Multiplexer.none,
}) {
  final frames = animation._frames;
  while (animation._sent < frames.length) {
    final k = animation._sent++;
    _kittyData(
      out,
      'a=f,i=$id,f=100,t=d,z=${_gap(animation._delays[k + 1])},q=2',
      ascii.encode(base64.encode(frames[k])),
      multiplexer,
    );
  }
  final state = !playing ? 1 : (animation._complete ? 3 : 2);
  if (state == animation._state) {
    return;
  }
  animation._state = state;
  _put(
    out,
    switch (state) {
      1 => '\x1b_Ga=a,i=$id,s=1,q=2\x1b\\',
      2 => '\x1b_Ga=a,i=$id,s=2,q=2\x1b\\',
      // v: 1 for ever, else one more than the plays
      _ =>
        '\x1b_Ga=a,i=$id,s=3,'
            'v=${animation.loops == 0 ? 1 : animation.loops + 1},q=2\x1b\\',
    },
    multiplexer,
  );
}

/// [delay] in whole milliseconds as kitty takes a frame's gap, at least 1.
int _gap(Duration delay) => delay.inMilliseconds < 1 ? 1 : delay.inMilliseconds;

/// The bytes that delete placement [placement] of kitty image [id]; with
/// [placement] 0 every placement of it, and the image itself.
void kittyDelete(
  ByteSink out, {
  required int id,
  int placement = 0,
  Multiplexer multiplexer = Multiplexer.none,
}) {
  if (multiplexer == Multiplexer.none) {
    // written as it goes, no string made for it
    if (placement == 0) {
      out
        ..ascii('\x1b_Ga=d,d=I,i=')
        ..decimal(id);
    } else {
      out
        ..ascii('\x1b_Ga=d,d=i,i=')
        ..decimal(id)
        ..ascii(',p=')
        ..decimal(placement);
    }
    out.ascii(',q=2\x1b\\');
    return;
  }
  _put(
    out,
    placement == 0
        ? '\x1b_Ga=d,d=I,i=$id,q=2\x1b\\'
        : '\x1b_Ga=d,d=i,i=$id,p=$placement,q=2\x1b\\',
    multiplexer,
  );
}

/// The bytes that draw the sixel image of [p] at the cursor and put the
/// cursor back (DECSC, DECRC), with the cursor left to the right of the
/// image meanwhile (DEC mode 8452), so that an image on the last row
/// doesn't scroll the screen. Without [saveCursor] (the terminal has one
/// saved cursor, which the caller may be using) neither is written, and
/// the cursor is left where the image ends.
void sixelDraw(
  ByteSink out,
  ImagePlacement p, {
  Multiplexer multiplexer = Multiplexer.none,
  bool saveCursor = true,
}) {
  out.ascii(saveCursor ? '\x1b7\x1b[?8452h' : '\x1b[?8452h');
  final data = p.image.data;
  putImageData(out, '\x1bP', data, 0, data.length, '\x1b\\', multiplexer);
  out.ascii(saveCursor ? '\x1b[?8452l\x1b8' : '\x1b[?8452l');
}

/// The bytes that draw the iTerm2 image of [p] at the cursor, scaled to
/// its cells, the cursor kept where it is (`doNotMoveCursor`, and DECSC,
/// DECRC where that is not known; neither without [saveCursor], for a
/// caller that uses the one saved cursor itself).
void iterm2Draw(
  ByteSink out,
  ImagePlacement p, {
  Multiplexer multiplexer = Multiplexer.none,
  bool saveCursor = true,
}) {
  final image = p.image;
  if (saveCursor) {
    out.ascii('\x1b7');
  }
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
  if (saveCursor) {
    out.ascii('\x1b8');
  }
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
