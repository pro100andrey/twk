import 'dart:typed_data';

import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show TerminalImage;

import 'bitmap.dart';
import 'blocks.dart';
import 'files_io.dart' if (dart.library.js_interop) 'files_web.dart';
import 'image_file.dart';
import 'protocols.dart';
import 'scale.dart';
import 'sixel.dart';

// Examples can assume:
// import 'package:twk/twk.dart';

/// Where the pixels of an [Image] come from. Two sources are equal when
/// they are the same bytes, the same path or the same bitmap: an image
/// given an equal one keeps what it decoded and encoded.
sealed class ImageSource {
  const ImageSource();

  /// A PNG or JPEG file's [bytes].
  const factory ImageSource.memory(Uint8List bytes) = _Memory;

  /// The PNG or JPEG file at [path], read when the image is first laid out.
  const factory ImageSource.file(String path) = _File;

  /// Pixels made in memory.
  const factory ImageSource.bitmap(Bitmap bitmap) = _Pixels;
}

final class _Memory extends ImageSource {
  const _Memory(this.bytes);

  final Uint8List bytes;

  @override
  bool operator ==(Object other) =>
      other is _Memory && identical(other.bytes, bytes);

  @override
  int get hashCode => identityHashCode(bytes);

  @override
  String toString() => 'memory(${bytes.length} bytes)';
}

final class _File extends ImageSource {
  const _File(this.path);

  final String path;

  @override
  bool operator ==(Object other) => other is _File && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'file($path)';
}

final class _Pixels extends ImageSource {
  const _Pixels(this.bitmap);

  final Bitmap bitmap;

  @override
  bool operator ==(Object other) =>
      other is _Pixels && identical(other.bitmap, bitmap);

  @override
  int get hashCode => identityHashCode(bitmap);

  @override
  String toString() => 'bitmap(${bitmap.width} × ${bitmap.height})';
}

/// An image in a box of cells, shown with the terminal's graphics protocol
/// (`TerminalCaps.graphics`: kitty, sixel or iTerm2) and drawn in block
/// characters ([blockMode]) where it has none, or always with
/// [forceBlocks]. Still images only: an animated GIF is not read, and an
/// APNG shows its default image.
///
/// The box is [width] × [height] cells where given, within the
/// constraints; along an axis left out it follows from the other by the
/// image's aspect, at the size in pixels the terminal reports for a cell
/// (`TerminalCaps.cellPixelWidth` and `cellPixelHeight`; 10 × 20 where it
/// reports none). Without either, it is as many cells as the image's
/// pixels take, made smaller or larger within the constraints with its
/// aspect kept. The image fills the box as [fit] says, placed in the cells
/// it leaves by [alignment]; a covering image is cut as much from either
/// side.
///
/// Cut off by a clip (a scroll view's edge), a kitty image shows what is
/// left of it, a sixel or iTerm2 one is not shown, its cells blank. A file
/// that can't be read or decoded is an error the image shows in its place.
///
/// A photo 40 cells wide, as tall as its aspect makes it, above its name:
///
/// ```dart
/// Column(
///   children: [
///     Image.file('photo.jpg', width: 40),
///     Text('photo.jpg'),
///   ],
/// )
/// ```
///
/// See also:
///
///  * [BlockImage], the block characters an image is drawn in where the
///    terminal shows none, to print without an app.
///  * [kittyImage], [iterm2Image] and [sixelImage], a file encoded for a
///    protocol without a widget.
final class Image extends LeafRenderObjectWidget {
  /// The image of [source].
  const Image(
    this.source, {
    super.key,
    this.width,
    this.height,
    this.fit = ImageFit.contain,
    this.alignment = Alignment.center,
    this.blockMode = BlockMode.half,
    this.forceBlocks = false,
  });

  /// The PNG or JPEG file [bytes].
  Image.memory(
    Uint8List bytes, {
    super.key,
    this.width,
    this.height,
    this.fit = ImageFit.contain,
    this.alignment = Alignment.center,
    this.blockMode = BlockMode.half,
    this.forceBlocks = false,
  }) : source = ImageSource.memory(bytes);

  /// The PNG or JPEG file at [path], read when first laid out.
  Image.file(
    String path, {
    super.key,
    this.width,
    this.height,
    this.fit = ImageFit.contain,
    this.alignment = Alignment.center,
    this.blockMode = BlockMode.half,
    this.forceBlocks = false,
  }) : source = ImageSource.file(path);

  /// The pixels of [bitmap].
  Image.bitmap(
    Bitmap bitmap, {
    super.key,
    this.width,
    this.height,
    this.fit = ImageFit.contain,
    this.alignment = Alignment.center,
    this.blockMode = BlockMode.half,
    this.forceBlocks = false,
  }) : source = ImageSource.bitmap(bitmap);

  /// Where the image's pixels come from: a file's bytes, a path or a
  /// bitmap.
  final ImageSource source;

  /// The box's width in cells; null, the default, for what [height] and
  /// the image's aspect make it.
  final int? width;

  /// The box's height in cells; null, the default, for what [width] and
  /// the image's aspect make it.
  final int? height;

  /// How the image fills the box: [ImageFit.contain], the default, shows
  /// all of it as large as fits.
  final ImageFit fit;

  /// Where the image goes in the cells of the box it does not take.
  final Alignment alignment;

  /// How block characters draw the image where the terminal shows none.
  final BlockMode blockMode;

  /// Draws the image in block characters even where the terminal shows
  /// images.
  final bool forceBlocks;

  @override
  RenderImage createRenderObject(BuildContext context) => RenderImage(
    source,
    boxWidth: width,
    boxHeight: height,
    fit: fit,
    alignment: alignment,
    blockMode: blockMode,
    forceBlocks: forceBlocks,
    cell: _cellOf(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderImage renderObject) {
    renderObject
      ..source = source
      ..boxWidth = width
      ..boxHeight = height
      ..fit = fit
      ..alignment = alignment
      ..blockMode = blockMode
      ..forceBlocks = forceBlocks
      ..cell = _cellOf(context);
  }

  /// The size of a cell of the terminal the app runs on.
  static CellSize _cellOf(BuildContext context) {
    final caps = AppBinding.maybeOf(context)?.twkApp.terminal.info.caps;
    return caps == null
        ? CellSize.fallback
        : CellSize.reported(caps.cellPixelWidth, caps.cellPixelHeight);
  }
}

/// What an [Image] lays out and paints. It shows the image with the
/// protocol of the presenter it is painted for (`TerminalCaps.graphics`),
/// in block characters where that is none or with [forceBlocks]. The file
/// is read and its size taken from its header when first laid out, its
/// pixels decoded when first painted; what is drawn, scaled to the box and
/// encoded, is kept until the box, the protocol or a property changes, so
/// that the presenter places the same image again without sending it.
final class RenderImage extends RenderObject {
  /// Lays out and paints the image of [_source]; the others are as
  /// [Image]'s properties of the same names, [_cell] the size of the
  /// terminal's cells.
  RenderImage(
    this._source, {
    this._boxWidth,
    this._boxHeight,
    this._fit = ImageFit.contain,
    this._alignment = Alignment.center,
    this._blockMode = BlockMode.half,
    this._forceBlocks = false,
    this._cell = CellSize.fallback,
  });

  ImageSource _source;

  /// Where the image's pixels come from ([Image.source]); another source
  /// reads and decodes them again.
  ImageSource get source => _source;
  set source(ImageSource s) {
    if (s != _source) {
      _source = s;
      _bytes = null;
      _size = null;
      _bitmap = null;
      _drawn = null;
      markNeedsLayout();
    }
  }

  int? _boxWidth;

  /// The box's width in cells ([Image.width]); not the [width] laid out.
  int? get boxWidth => _boxWidth;
  set boxWidth(int? w) {
    if (w != _boxWidth) {
      _boxWidth = w;
      markNeedsLayout();
    }
  }

  int? _boxHeight;

  /// The box's height in cells ([Image.height]).
  int? get boxHeight => _boxHeight;
  set boxHeight(int? h) {
    if (h != _boxHeight) {
      _boxHeight = h;
      markNeedsLayout();
    }
  }

  ImageFit _fit;

  /// How the image fills the box ([Image.fit]).
  ImageFit get fit => _fit;
  set fit(ImageFit f) {
    if (f != _fit) {
      _fit = f;
      _drawn = null;
      markNeedsPaint();
    }
  }

  Alignment _alignment;

  /// Where the image goes in the cells of the box it does not take
  /// ([Image.alignment]).
  Alignment get alignment => _alignment;
  set alignment(Alignment a) {
    if (a != _alignment) {
      _alignment = a;
      markNeedsPaint();
    }
  }

  BlockMode _blockMode;

  /// How block characters draw the image ([Image.blockMode]).
  BlockMode get blockMode => _blockMode;
  set blockMode(BlockMode m) {
    if (m != _blockMode) {
      _blockMode = m;
      _drawn = null;
      markNeedsPaint();
    }
  }

  bool _forceBlocks;

  /// Whether the image is drawn in block characters even where the
  /// terminal shows images ([Image.forceBlocks]).
  bool get forceBlocks => _forceBlocks;
  set forceBlocks(bool b) {
    if (b != _forceBlocks) {
      _forceBlocks = b;
      markNeedsPaint();
    }
  }

  CellSize _cell;

  /// The size of the terminal's cells, which the image is scaled by.
  CellSize get cell => _cell;
  set cell(CellSize c) {
    if (c != _cell) {
      _cell = c;
      _drawn = null;
      markNeedsLayout();
    }
  }

  Uint8List? _bytes;
  ({int width, int height})? _size;
  Bitmap? _bitmap;
  _Drawn? _drawn;

  /// The file's bytes, read once.
  Uint8List get _file => _bytes ??= switch (_source) {
    _Memory(:final bytes) => bytes,
    _File(:final path) => readImageFile(path),
    _Pixels() => throw StateError('a bitmap is no file'),
  };

  /// The image's size in pixels.
  ({int width, int height}) get _pixelSize => _size ??= switch (_source) {
    _Pixels(:final bitmap) => (width: bitmap.width, height: bitmap.height),
    _ => imageSize(_file),
  };

  /// The image's pixels, decoded once.
  Bitmap get _pixels => _bitmap ??= switch (_source) {
    _Pixels(:final bitmap) => bitmap,
    _ => decodeImage(_file),
  };

  @override
  int computeMinIntrinsicWidth(int height) =>
      _sizeFor(_tightFor(height: height)).$1;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      _sizeFor(_tightFor(height: height)).$1;

  @override
  int computeMinIntrinsicHeight(int width) =>
      _sizeFor(_tightFor(width: width)).$2;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      _sizeFor(_tightFor(width: width)).$2;

  /// Exactly [width] or [height] where it is less than unbounded.
  static BoxConstraints _tightFor({int? width, int? height}) =>
      BoxConstraints.tightFor(
        width: width != null && width < BoxConstraints.unbounded ? width : null,
        height: height != null && height < BoxConstraints.unbounded
            ? height
            : null,
      );

  @override
  void performLayout(BoxConstraints c) {
    final (w, h) = _sizeFor(c);
    width = w;
    height = h;
  }

  /// The box within [c]: [boxWidth] and [boxHeight] where given, the rest
  /// by the image's aspect, starting from the cells its pixels take.
  (int, int) _sizeFor(BoxConstraints c) {
    var minW = c.minW;
    var maxW = c.maxW;
    var minH = c.minH;
    var maxH = c.maxH;
    if (_boxWidth case final w?) {
      minW = maxW = c.constrainW(w);
    }
    if (_boxHeight case final h?) {
      minH = maxH = c.constrainH(h);
    }
    if (minW >= maxW && minH >= maxH) {
      return (minW, minH);
    }
    final size = _pixelSize;
    final cell = _cell;
    // columns per row
    final aspect = size.width * cell.height / (size.height * cell.width);
    var w = ((size.width + cell.width - 1) ~/ cell.width).toDouble();
    var h = ((size.height + cell.height - 1) ~/ cell.height).toDouble();
    if (w > maxW) {
      w = maxW.toDouble();
      h = w / aspect;
    }
    if (h > maxH) {
      h = maxH.toDouble();
      w = h * aspect;
    }
    if (w < minW) {
      w = minW.toDouble();
      h = w / aspect;
    }
    if (h < minH) {
      h = minH.toDouble();
      w = h * aspect;
    }
    int whole(double v, int min, int max) {
      final n = v.round() < 1 ? 1 : v.round();
      return n < min ? min : (n > max ? max : n);
    }

    return (whole(w, minW, maxW), whole(h, minH, maxH));
  }

  @override
  void paint(PaintContext ctx) {
    if (width == 0 || height == 0) {
      return;
    }
    final protocol = _forceBlocks
        ? GraphicsProtocol.none
        : ctx.presenter.caps.graphics;
    var d = _drawn;
    if (d == null ||
        d.protocol != protocol ||
        d.boxWidth != width ||
        d.boxHeight != height) {
      d = _drawn = _draw(protocol);
    }
    final canvas = ctx.canvas;
    final x = _alignment.dx(width - d.columns);
    final y = _alignment.dy(height - d.rows);
    if (d.image case final image?) {
      canvas.image(x, y, d.columns, d.rows, image);
      return;
    }
    final blocks = d.blocks!;
    final pens = d.pensIn(canvas.styles);
    for (var row = 0; row < blocks.rows; row++) {
      for (var column = 0; column < blocks.columns; column++) {
        final i = row * blocks.columns + column;
        if (pens[i] >= 0) {
          canvas.fill(
            x + column,
            y + row,
            1,
            1,
            pens[i],
            blocks.cells[i].glyph.codeUnitAt(0),
          );
        }
      }
    }
  }

  /// The image scaled to the box and encoded for [protocol], or in blocks.
  _Drawn _draw(GraphicsProtocol protocol) {
    final pixels = _pixels;
    final cell = _cell;
    CellFit fitted({int bandHeight = 1}) => CellFit(
      pixels.width,
      pixels.height,
      columns: width,
      rows: height,
      cell: cell,
      fit: _fit,
      bandHeight: bandHeight,
    );
    switch (protocol) {
      case GraphicsProtocol.none:
        final blocks = BlockImage(
          pixels,
          columns: width,
          rows: height,
          cell: cell,
          fit: _fit,
          mode: _blockMode,
        );
        return _Drawn(
          protocol,
          width,
          height,
          blocks.columns,
          blocks.rows,
          blocks: blocks,
        );
      case GraphicsProtocol.sixel:
        // whole bands of six pixels, so that the last does not scroll
        final f = fitted(bandHeight: 6);
        final image = TerminalImage(
          protocol,
          encodeSixel(f.scale(pixels)),
          pixelWidth: f.width,
          pixelHeight: f.height,
        );
        return _Drawn(protocol, width, height, f.columns, f.rows, image: image);
      case GraphicsProtocol.kitty || GraphicsProtocol.iterm2:
        // the terminal stretches the image to its cells: the pixels short
        // of them are transparent, so that it keeps its aspect
        final f = fitted();
        final padded = _padded(
          f.scale(pixels),
          f.columns * cell.width,
          f.rows * cell.height,
        );
        final encoded = pngImage(padded);
        final image = TerminalImage(
          protocol,
          encoded.data,
          pixelWidth: encoded.pixelWidth,
          pixelHeight: encoded.pixelHeight,
        );
        return _Drawn(protocol, width, height, f.columns, f.rows, image: image);
    }
  }

  /// [image] at the top left of [width] × [height] pixels, transparent
  /// where it does not reach; [image] itself where it is of that size.
  static Bitmap _padded(Bitmap image, int width, int height) {
    if (image.width == width && image.height == height) {
      return image;
    }
    final out = Bitmap(width, height);
    final row = image.width * 4;
    for (var y = 0; y < image.height && y < height; y++) {
      out.pixels.setRange(
        y * width * 4,
        y * width * 4 + row,
        image.pixels,
        y * row,
      );
    }
    return out;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
      ..add('source', _source)
      ..add('width', _boxWidth, defaultValue: null)
      ..add('height', _boxHeight, defaultValue: null)
      ..add('fit', _fit.name, defaultValue: ImageFit.contain.name)
      ..add(
        'alignment',
        describeAlignment(_alignment),
        defaultValue: describeAlignment(Alignment.center),
      )
      ..add('blockMode', _blockMode.name, defaultValue: BlockMode.half.name)
      ..add('forceBlocks', _forceBlocks, defaultValue: false)
      ..add('cell', '${_cell.width}×${_cell.height}');
  }
}

/// What a [RenderImage] painted last: for [protocol] in a box of
/// [boxWidth] × [boxHeight] cells, the [columns] × [rows] it takes, an
/// [image] for the presenter or [blocks].
final class _Drawn {
  _Drawn(
    this.protocol,
    this.boxWidth,
    this.boxHeight,
    this.columns,
    this.rows, {
    this.image,
    this.blocks,
  });

  final GraphicsProtocol protocol;
  final int boxWidth;
  final int boxHeight;
  final int columns;
  final int rows;
  final TerminalImage? image;
  final BlockImage? blocks;

  StyleTable? _styles;
  Int32List? _pens;

  /// The pen of each of [blocks]' cells in [styles], -1 where no pixel is
  /// drawn.
  Int32List pensIn(StyleTable styles) {
    final pens = _pens;
    if (pens != null && identical(styles, _styles)) {
      return pens;
    }
    Color? color(int? rgb) => rgb == null
        ? null
        : Color.rgb(rgb >> 16 & 0xFF, rgb >> 8 & 0xFF, rgb & 0xFF);
    final cells = blocks!.cells;
    final out = Int32List(cells.length);
    for (var i = 0; i < cells.length; i++) {
      final c = cells[i];
      out[i] = c == BlockCell.empty
          ? -1
          : styles.pen(Pen(fg: color(c.fg), bg: color(c.bg)));
    }
    _styles = styles;
    return _pens = out;
  }
}
