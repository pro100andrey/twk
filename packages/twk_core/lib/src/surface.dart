/// The cell grid, [Surface], and the table of glyphs of more than one code
/// point, [GlyphTable].
///
/// A cell is two 32-bit words in parallel typed arrays:
///
/// ```text
/// cells[i]  = glyph id (bits 0..23) | flags (bits 24..28)
/// styles[i] = interned style id (see StyleTable)
/// ```
///
/// Glyph ids below 0x110000 *are* the Unicode scalar value of a
/// single-code-point cluster (no table lookup, no allocation); larger ids
/// index interned multi-code-point clusters (combining sequences, emoji ZWJ
/// sequences, flags, ...). All values stay below 2^29, so they are Smis on
/// every Dart VM configuration.
///
/// @docImport 'canvas.dart';
/// @docImport 'presenter.dart';
/// @docImport 'style.dart';
library;

import 'dart:convert';
import 'dart:typed_data';

import 'fill.dart';
import 'graphics.dart';
import 'unicode/unicode.dart';

/// The bits of a cell that hold its glyph id: `cell & kGlyphMask`; the
/// bits above it are flags ([kWide], [kCont], [kUncertain], [kSkip]).
const kGlyphMask = 0x00FFFFFF;

/// Leading cell of a two-column glyph.
const int kWide = 1 << 24;

/// Trailing (continuation) cell of a two-column glyph; glyph bits are 0.
const int kCont = 1 << 25;

/// Terminals disagree about this glyph's width, or a code point printed
/// right after it could join it into one cluster: the encoder positions the
/// cursor explicitly after it (see [Presenter]).
const int kUncertain = 1 << 26;

/// Owned by something drawn outside the cell model (inline images, ...):
/// never emitted and never compared.
const int kSkip = 1 << 27;

/// Front-buffer sentinel: "terminal content unknown", differs from anything.
const int kInvalid = 1 << 28;

/// A blank cell (space).
const kBlank = 0x20;

/// The first glyph id of an interned cluster ([GlyphTable.intern]): one
/// past the last Unicode code point, so an id below it is a code point.
const kFirstInterned = 0x110000;

/// Interned multi-code-point clusters with their UTF-8 bytes.
///
/// A glyph of one code point is that code point and needs no entry; a
/// cluster of more (a letter and its combining marks, an emoji sequence,
/// a flag) gets an id from [kFirstInterned] up, the same for the same text
/// for the table's lifetime. [stringOf] reads any glyph id back.
///
/// ```dart
/// final glyphs = GlyphTable();
/// final family = glyphs.intern('👨‍👩‍👧', 0, 8);
/// print(glyphs.stringOf(family)); // 👨‍👩‍👧
/// print(glyphs.stringOf(0x41)); // A, a code point needs no entry
/// ```
final class GlyphTable {
  /// A table with no glyphs interned yet.
  GlyphTable();

  final _strings = <String>[];
  final _bytes = <Uint8List>[];
  final _maxWidth = <int>[];
  var _slots = Int32List(1024)..fillRange(0, 1024, -1);

  /// How many clusters are interned.
  int get length => _strings.length;

  /// The id of the cluster `s.substring(start, end)`, interned on its
  /// first sighting, which is the only one that allocates.
  ///
  /// Throws a [StateError] when the ids would run into the cell's flag
  /// bits: past 15 million distinct clusters.
  int intern(String s, int start, int end) {
    var h = 0x811C9DC5;
    for (var i = start; i < end; i++) {
      h = ((h ^ s.codeUnitAt(i)) * 0x01000193) & 0x3FFFFFFF;
    }
    var mask = _slots.length - 1;
    var slot = h & mask;
    final len = end - start;
    while (true) {
      final idx = _slots[slot];
      if (idx < 0) {
        break;
      }
      final cand = _strings[idx];
      if (cand.length == len) {
        var eq = true;
        for (var k = 0; k < len; k++) {
          if (cand.codeUnitAt(k) != s.codeUnitAt(start + k)) {
            eq = false;
            break;
          }
        }
        if (eq) {
          return kFirstInterned + idx;
        }
      }
      slot = (slot + 1) & mask;
    }
    final idx = _strings.length;
    if (kFirstInterned + idx > kGlyphMask) {
      // the id would run into the flag bits
      throw StateError('more distinct clusters than glyph ids');
    }
    final str = s.substring(start, end);
    _strings.add(str);
    _bytes.add(utf8.encode(str));
    _maxWidth.add(maxRenderWidth(str, 0, str.length));
    if (_strings.length * 2 > _slots.length) {
      _slots = Int32List(_slots.length * 2)
        ..fillRange(0, _slots.length * 2, -1);
      mask = _slots.length - 1;
      for (var i = 0; i < _strings.length; i++) {
        var hh = 0x811C9DC5;
        final t = _strings[i];
        for (var k = 0; k < t.length; k++) {
          hh = ((hh ^ t.codeUnitAt(k)) * 0x01000193) & 0x3FFFFFFF;
        }
        var sl = hh & mask;
        while (_slots[sl] >= 0) {
          sl = (sl + 1) & mask;
        }
        _slots[sl] = i;
      }
    } else {
      _slots[slot] = idx;
    }
    return kFirstInterned + idx;
  }

  /// UTF-8 bytes of an interned glyph id (>= [kFirstInterned]).
  @pragma('vm:prefer-inline')
  Uint8List bytesOf(int glyph) => _bytes[glyph - kFirstInterned];

  /// The widest any terminal may render [glyph] (an uncertain glyph can
  /// overflow its cells up to this many columns).
  int maxWidthOf(int glyph) {
    final g = glyph & kGlyphMask;
    if (g < kFirstInterned) {
      return 2;
    }
    return _maxWidth[g - kFirstInterned];
  }

  /// The text of any glyph id.
  String stringOf(int glyph) {
    final g = glyph & kGlyphMask;
    if (g < kFirstInterned) {
      return String.fromCharCode(g);
    }
    return _strings[g - kFirstInterned];
  }
}

/// A grid of cells plus per-row damage (the span of columns written since
/// the last present). Damage is recorded by the drawing primitives
/// themselves, so a frame is diffed in O(changed area) without the widget
/// layer having to compute dirty rectangles correctly.
///
/// A [Canvas] draws on it; the [Presenter] compares its damaged spans with
/// what the terminal shows, writes the difference, and clears the damage
/// ([clearDamage]). Cells are indexed `y * width + x`.
///
/// ```dart
/// final surface = Surface(10, 2);
/// final styles = StyleTable();
/// final pen = styles.pen(const Pen());
/// Canvas(surface, styles, GlyphTable()).text(0, 1, 'hi', pen);
/// print(surface.cells[1 * surface.width + 0] & kGlyphMask); // 104, 'h'
/// print(surface.dirtyHi[1]); // 10: every cell is damaged when made
/// ```
final class Surface {
  /// A surface [width] x [height] cells, blank in style 0 and damaged
  /// whole.
  Surface(int width, int height)
    : width = width,
      height = height,
      cells = Uint32List(width * height),
      styles = Uint32List(width * height),
      dirtyLo = Int32List(height),
      dirtyHi = Int32List(height) {
    cells64 = view64(cells);
    styles64 = view64(styles);
    fillU32(cells, 0, cells.length, kBlank);
    markAllDirty();
  }

  /// How many cells wide the surface is; [resize] changes it.
  int width;

  /// How many rows tall the surface is; [resize] changes it.
  int height;

  /// The glyph and flags of each cell, row after row: the glyph id
  /// (`& kGlyphMask`) with [kWide], [kCont], [kUncertain] or [kSkip].
  Uint32List cells;

  /// The style id of each cell in a [StyleTable], as [cells] is ordered.
  Uint32List styles;

  /// [cells] seen two cells to a word, for fast scans.
  late Uint64List cells64;

  /// [styles] seen two cells to a word, for fast scans.
  late Uint64List styles64;

  /// The first damaged column of each row: the damage is
  /// `[dirtyLo, dirtyHi)`, none when `dirtyLo >= dirtyHi`.
  Int32List dirtyLo;

  /// The column after the last damaged one of each row (see [dirtyLo]).
  Int32List dirtyHi;

  /// Moves recorded by [scrollRows] / [scrollRect] since the last present,
  /// as flat (top, bottom, n, x0, x1) tuples. The presenter replays them as
  /// hardware scrolls; if it can't, it re-diffs the moved rows instead.
  final pendingScrolls = <int>[];

  /// The images shown in reserved cells ([Canvas.image]), oldest first.
  /// They move with [scrollRows] and [scrollRect] (one the move cuts
  /// through is dropped), and go with [resize] and [clear]; the presenter
  /// drops one whose cells were drawn over.
  final images = <ImagePlacement>[];

  /// Adds [p]: one of [images] of the same image in the same cells takes
  /// in the cells [p] shows (an image painted piece by piece, as a scroll
  /// view paints the rows a scroll exposed), others it is drawn over go.
  void place(ImagePlacement p) {
    for (var i = images.length - 1; i >= 0; i--) {
      final q = images[i];
      if (identical(q.image, p.image) &&
          q.x == p.x &&
          q.y == p.y &&
          q.cols == p.cols &&
          q.rows == p.rows) {
        p
          ..left = q.left < p.left ? q.left : p.left
          ..top = q.top < p.top ? q.top : p.top
          ..right = q.right > p.right ? q.right : p.right
          ..bottom = q.bottom > p.bottom ? q.bottom : p.bottom;
        images.removeAt(i);
      } else if (q.overlaps(p)) {
        images.removeAt(i);
      }
    }
    images.add(p);
  }

  /// Makes the surface [w] x [h] cells, blank and damaged whole, with no
  /// moves or images; does nothing when that is its size.
  void resize(int w, int h) {
    if (w == width && h == height) {
      return;
    }
    width = w;
    height = h;
    cells = Uint32List(w * h);
    fillU32(cells, 0, w * h, kBlank);
    styles = Uint32List(w * h);
    cells64 = view64(cells);
    styles64 = view64(styles);
    dirtyLo = Int32List(h);
    dirtyHi = Int32List(h);
    pendingScrolls.clear();
    images.clear();
    markAllDirty();
  }

  /// Blank every cell with [styleId] and damage everything.
  void clear([int styleId = 0]) {
    fillU32(cells, 0, cells.length, kBlank);
    fillU32(styles, 0, styles.length, styleId);
    pendingScrolls.clear();
    images.clear();
    markAllDirty();
  }

  /// Damages every cell, so the next present compares them all.
  void markAllDirty() {
    fillI32(dirtyLo, 0, height, 0);
    fillI32(dirtyHi, 0, height, width);
  }

  /// Damages columns [x0, x1) of row [y]: the row's damage grows to span
  /// them and what it had.
  @pragma('vm:prefer-inline')
  void markDirty(int y, int x0, int x1) {
    final lo = dirtyLo[y];
    final hi = dirtyHi[y];
    if (lo >= hi) {
      dirtyLo[y] = x0;
      dirtyHi[y] = x1;
      return;
    }
    if (x0 < lo) {
      dirtyLo[y] = x0;
    }
    if (x1 > hi) {
      dirtyHi[y] = x1;
    }
  }

  /// Clears the damage of every row and forgets the recorded moves, as
  /// the presenter does once a frame is written.
  void clearDamage() {
    // one copy of as many zeros each, where filling them (fillI32) takes
    // 16 stores and a copy per doubling: this runs for every frame
    final h = height;
    var zeros = _zeros;
    if (zeros.length < h) {
      zeros = _zeros = Int32List(h);
    }
    dirtyLo.setRange(0, h, zeros);
    dirtyHi.setRange(0, h, zeros);
    pendingScrolls.clear();
  }

  /// Zeros, as many as the tallest surface has rows, that [clearDamage]
  /// copies.
  static var _zeros = Int32List(0);

  /// Breaks the wide glyph that cell [x] (on the row starting at [rowBase])
  /// is a half of, by blanking the *other* half. Returns the column of the
  /// modified partner, or -1.
  @pragma('vm:prefer-inline')
  int breakWideAt(int rowBase, int x) {
    final i = rowBase + x;
    final c = cells[i];
    if ((c & kCont) != 0) {
      if (x > 0 && (cells[i - 1] & kWide) != 0) {
        cells[i - 1] = kBlank;
        return x - 1;
      }
    } else if ((c & kWide) != 0) {
      if (x + 1 < width && (cells[i + 1] & kCont) != 0) {
        cells[i + 1] = kBlank;
        return x + 1;
      }
    }
    return -1;
  }

  /// Moves the content of rows [rowTop, rowBottom) up by [n] rows (down
  /// when negative); exposed rows become blank with [styleId]. This is how a
  /// scrolling view avoids repainting content that only moved: the damage
  /// moves with the rows, only the exposed rows are damaged, and the move is
  /// recorded so the presenter scrolls the terminal in hardware too.
  void scrollRows(int rowTop, int rowBottom, int n, [int styleId = 0]) {
    final top = rowTop < 0 ? 0 : rowTop;
    final bottom = rowBottom > height ? height : rowBottom;
    if (n == 0 || top >= bottom) {
      return;
    }
    final w = width;
    final k = n.abs();
    if (images.isNotEmpty) {
      _scrollImages(0, w, top, bottom, n);
    }
    if (k >= bottom - top) {
      fillU32(cells, top * w, bottom * w, kBlank);
      fillU32(styles, top * w, bottom * w, styleId);
      for (var y = top; y < bottom; y++) {
        markDirty(y, 0, w);
      }
      return; // nothing survives: a plain repaint, not a scroll
    }
    if (n > 0) {
      cells.setRange(top * w, (bottom - k) * w, cells, (top + k) * w);
      styles.setRange(top * w, (bottom - k) * w, styles, (top + k) * w);
      dirtyLo.setRange(top, bottom - k, dirtyLo, top + k);
      dirtyHi.setRange(top, bottom - k, dirtyHi, top + k);
      fillU32(cells, (bottom - k) * w, bottom * w, kBlank);
      fillU32(styles, (bottom - k) * w, bottom * w, styleId);
      for (var y = bottom - k; y < bottom; y++) {
        dirtyLo[y] = 0;
        dirtyHi[y] = w;
      }
    } else {
      for (var y = bottom - 1; y >= top + k; y--) {
        cells.setRange(y * w, y * w + w, cells, (y - k) * w);
        styles.setRange(y * w, y * w + w, styles, (y - k) * w);
        dirtyLo[y] = dirtyLo[y - k];
        dirtyHi[y] = dirtyHi[y - k];
      }
      fillU32(cells, top * w, (top + k) * w, kBlank);
      fillU32(styles, top * w, (top + k) * w, styleId);
      for (var y = top; y < top + k; y++) {
        dirtyLo[y] = 0;
        dirtyHi[y] = w;
      }
    }
    pendingScrolls
      ..add(top)
      ..add(bottom)
      ..add(n)
      ..add(0)
      ..add(width);
  }

  /// Moves the content of the rectangle columns [left, right) x rows
  /// [rowTop, rowBottom) up by [n] rows (down when negative), like
  /// [scrollRows] but for a scroll view that doesn't span the whole width (a
  /// side panel, a list inside a border). Wide glyphs cut by the rectangle's
  /// left/right edges are broken (both halves blanked) first. The move is
  /// recorded; the presenter replays it with DECSLRM margins where the
  /// terminal has them.
  void scrollRect(
    int left,
    int right,
    int rowTop,
    int rowBottom,
    int n, [
    int styleId = 0,
  ]) {
    final x0 = left < 0 ? 0 : left;
    final x1 = right > width ? width : right;
    final top = rowTop < 0 ? 0 : rowTop;
    final bottom = rowBottom > height ? height : rowBottom;
    if (x0 == 0 && x1 == width) {
      scrollRows(top, bottom, n, styleId);
      return;
    }
    if (n == 0 || top >= bottom || x0 >= x1) {
      return;
    }
    final w = width;
    final k = n.abs();
    if (images.isNotEmpty) {
      _scrollImages(x0, x1, top, bottom, n);
    }
    for (var y = top; y < bottom; y++) {
      _breakEdge(y, x0);
      _breakEdge(y, x1);
    }
    if (k >= bottom - top) {
      for (var y = top; y < bottom; y++) {
        fillU32(cells, y * w + x0, y * w + x1, kBlank);
        fillU32(styles, y * w + x0, y * w + x1, styleId);
        markDirty(y, x0, x1);
      }
      return;
    }
    // the damage inside the rectangle moves with its cells (each row's
    // read before it is written over: rows in the order they are
    // written), that beside it stays, and the exposed rows are damaged
    if (n > 0) {
      for (var y = top; y < bottom - k; y++) {
        cells.setRange(y * w + x0, y * w + x1, cells, (y + k) * w + x0);
        styles.setRange(y * w + x0, y * w + x1, styles, (y + k) * w + x0);
        _moveDamage(y, y + k, x0, x1);
      }
      for (var y = bottom - k; y < bottom; y++) {
        fillU32(cells, y * w + x0, y * w + x1, kBlank);
        fillU32(styles, y * w + x0, y * w + x1, styleId);
        _moveDamage(y, -1, x0, x1);
      }
    } else {
      for (var y = bottom - 1; y >= top + k; y--) {
        cells.setRange(y * w + x0, y * w + x1, cells, (y - k) * w + x0);
        styles.setRange(y * w + x0, y * w + x1, styles, (y - k) * w + x0);
        _moveDamage(y, y - k, x0, x1);
      }
      for (var y = top; y < top + k; y++) {
        fillU32(cells, y * w + x0, y * w + x1, kBlank);
        fillU32(styles, y * w + x0, y * w + x1, styleId);
        _moveDamage(y, -1, x0, x1);
      }
    }
    pendingScrolls
      ..add(top)
      ..add(bottom)
      ..add(n)
      ..add(x0)
      ..add(x1);
  }

  /// Row [y]'s damage after columns [x0, x1) of row [from] moved into it
  /// (-1: they were blanked, all damage): the span over what of its own
  /// lies beside the columns and what of [from]'s lies inside them.
  @pragma('vm:prefer-inline')
  void _moveDamage(int y, int from, int x0, int x1) {
    var lo = dirtyLo[y];
    var hi = dirtyHi[y];
    if (lo < hi && lo >= x0 && hi <= x1) {
      lo = hi = 0; // all of it inside: moved away
    }
    // beside: what of [lo, hi) is outside [x0, x1), as one span
    else if (lo < hi) {
      if (lo >= x0) {
        lo = lo > x1 ? lo : x1; // only the part right of it
      } else if (hi <= x1) {
        hi = hi < x0 ? hi : x0; // only the part left of it
      }
    }
    int a;
    int b;
    if (from < 0) {
      a = x0;
      b = x1;
    } else {
      a = dirtyLo[from];
      b = dirtyHi[from];
      if (a < x0) {
        a = x0;
      }
      if (b > x1) {
        b = x1;
      }
    }
    if (a < b) {
      if (lo >= hi) {
        lo = a;
        hi = b;
      } else {
        if (a < lo) {
          lo = a;
        }
        if (b > hi) {
          hi = b;
        }
      }
    }
    dirtyLo[y] = lo;
    dirtyHi[y] = hi;
  }

  /// Moves the images shown in columns [x0, x1) of rows [top, bottom) up
  /// by [n] rows (down when negative), as their cells move: what leaves the
  /// rows is no longer shown, and one shown across their edges goes.
  @pragma('vm:never-inline')
  void _scrollImages(int x0, int x1, int top, int bottom, int n) {
    for (var i = images.length - 1; i >= 0; i--) {
      final p = images[i];
      if (p.right <= x0 || p.left >= x1 || p.bottom <= top || p.top >= bottom) {
        continue;
      }
      if (p.left < x0 || p.right > x1 || p.top < top || p.bottom > bottom) {
        images.removeAt(i);
        continue;
      }
      p
        ..y -= n
        ..top = p.top - n < top ? top : p.top - n
        ..bottom = p.bottom - n > bottom ? bottom : p.bottom - n;
      if (p.top >= p.bottom) {
        images.removeAt(i);
      }
    }
  }

  /// A wide glyph whose halves are on both sides of the column boundary
  /// [x] (between x - 1 and x) is blanked entirely.
  void _breakEdge(int y, int x) {
    if (x <= 0 || x >= width) {
      return;
    }
    final i = y * width + x;
    if ((cells[i] & kCont) != 0) {
      cells[i - 1] = kBlank;
      cells[i] = kBlank;
      markDirty(y, x - 1, x + 1);
    }
  }

  /// Copies the rectangle of [src] at (sx, sy, w, h) to (dx, dy) of this
  /// surface (layer compositing). Wide glyphs cut by the rectangle edges are
  /// replaced by blanks. [src] may be this surface, rectangles overlapping.
  void blit(Surface src, int sx, int sy, int w, int h, int dx, int dy) {
    if (identical(src, this)) {
      // rows are copied one by one and wide glyphs at the destination are
      // broken before the source is read: copy the source rectangle (the
      // part on the surface) first
      final sx0 = sx < 0 ? 0 : sx;
      final sy0 = sy < 0 ? 0 : sy;
      final sx1 = sx + w > width ? width : sx + w;
      final sy1 = sy + h > height ? height : sy + h;
      if (sx0 >= sx1 || sy0 >= sy1) {
        return;
      }
      final part = Surface(sx1 - sx0, sy1 - sy0)
        ..blit(this, sx0, sy0, sx1 - sx0, sy1 - sy0, 0, 0);
      blit(part, 0, 0, part.width, part.height, dx + sx0 - sx, dy + sy0 - sy);
      return;
    }
    for (var row = 0; row < h; row++) {
      final ty = dy + row;
      final syy = sy + row;
      if (ty < 0 || ty >= height || syy < 0 || syy >= src.height) {
        continue;
      }
      var x0 = 0;
      var x1 = w;
      if (dx + x0 < 0) {
        x0 = -dx;
      }
      if (dx + x1 > width) {
        x1 = width - dx;
      }
      if (sx + x0 < 0) {
        x0 = -sx;
      }
      if (sx + x1 > src.width) {
        x1 = src.width - sx;
      }
      if (x0 >= x1) {
        continue;
      }
      final tb = ty * width;
      final sb = syy * src.width;
      var lo = dx + x0;
      var hi = dx + x1;
      // a partner blanked at either edge may lie on either side
      for (var k = 0; k < 2; k++) {
        final p = breakWideAt(tb, k == 0 ? dx + x0 : dx + x1 - 1);
        if (p >= 0 && p < lo) {
          lo = p;
        }
        if (p >= hi) {
          hi = p + 1;
        }
      }
      cells.setRange(tb + dx + x0, tb + dx + x1, src.cells, sb + sx + x0);
      styles.setRange(tb + dx + x0, tb + dx + x1, src.styles, sb + sx + x0);
      // halves cut by the copy edges
      if ((cells[tb + dx + x0] & kCont) != 0) {
        cells[tb + dx + x0] = kBlank;
      }
      if ((cells[tb + dx + x1 - 1] & kWide) != 0) {
        cells[tb + dx + x1 - 1] = kBlank;
      }
      markDirty(ty, lo, hi);
    }
  }
}
