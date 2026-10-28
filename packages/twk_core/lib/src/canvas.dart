/// Drawing onto a [Surface]: translation, clipping, text with Unicode
/// segmentation, pre-shaped glyph runs, rectangle fills and lines merged
/// with those already drawn.
///
/// Invariants maintained by every primitive (they are what the encoder
/// relies on to never leave half glyphs on screen):
///  * a two-column glyph is a `kWide` cell followed by a `kCont` cell with the
///    same style; overwriting either half blanks the other half;
///  * a two-column glyph is never cut by a clip edge or the surface edge:
///    the visible half is drawn as a blank instead;
///  * every written cell (and any partner cell blanked) is added to the row
///    damage span.
///
/// @docImport 'presenter.dart';
/// @docImport 'screen.dart';
library;

import 'dart:typed_data';

import 'fill.dart';
import 'graphics.dart';
import 'style.dart';
import 'surface.dart';
import 'unicode/unicode.dart';

/// Text segmented once and drawn many times (what a retained text layout
/// keeps between frames). Each entry is a glyph word: glyph id plus
/// [kWide]/[kUncertain] flags.
///
/// [Canvas.shape] makes one, [Canvas.run] draws it.
final class GlyphRun {
  /// A run of [glyphs], [width] columns in all.
  GlyphRun(this.glyphs, this.width);

  /// The glyph words, one per cluster, in the order they are drawn: a
  /// glyph id with [kWide] for one two columns wide and [kUncertain]
  /// where terminals may disagree about it.
  final Uint32List glyphs;

  /// Total columns.
  final int width;
}

/// Draws on a [Surface]: text, fills, pre-shaped runs, lines merged where
/// they meet, and images, under a translation and a clip.
///
/// Coordinates are cells, relative to the origin [translate] moves; what
/// falls outside the clip ([clipRect]) is not drawn, and [save] and
/// [restore] keep and bring back both. A pen is a [Pen]'s id in [styles]
/// ([StyleTable.pen]): each cell drawn takes the style it makes over the
/// cell's own. Text is segmented into clusters as the terminal shows them
/// ([segmenter]), the clusters of more than one code point interned in
/// [glyphs]. Every cell written is damaged on the surface, so the
/// presenter compares only those.
///
/// A blue panel with a title, drawn in a 2-cell margin:
///
/// ```dart
/// final styles = StyleTable();
/// final canvas = Canvas(Surface(40, 10), styles, GlyphTable());
/// final panel = styles.pen(const Pen(bg: Color.blue));
/// final title = styles.pen(const Pen(fg: Color.brightWhite));
/// canvas
///   ..save()
///   ..translate(2, 1)
///   ..clipRect(0, 0, 36, 8)
///   ..fill(0, 0, 36, 8, panel)
///   ..text(1, 0, 'Status', title)
///   ..restore();
/// ```
///
/// See also:
///
///  * [Screen.canvas], the canvas of a screen.
final class Canvas {
  /// A canvas on [surface], with its origin at the surface's first cell
  /// and the whole surface as its clip.
  ///
  /// [styles] holds the pens it paints with and the styles the cells get,
  /// [glyphs] the clusters it interns; [segmenter] measures and splits
  /// text, by default in [TextMode.graphemes] with ambiguous characters
  /// one cell wide.
  Canvas(this.surface, this.styles, this.glyphs, {TextSegmenter? segmenter})
    : segmenter = segmenter ?? TextSegmenter() {
    reset();
  }

  /// The surface drawn on. Set to another, [reset] makes the clip that
  /// surface's.
  Surface surface;

  /// The pens the canvas paints with, and the styles the cells take.
  final StyleTable styles;

  /// The clusters of more than one code point drawn, interned.
  final GlyphTable glyphs;

  /// How text is split into clusters and measured: as the terminal does.
  final TextSegmenter segmenter;
  final _scan = ClusterScan();

  var _ox = 0;
  var _oy = 0;
  var _cx0 = 0;
  var _cy0 = 0;
  var _cx1 = 0;
  var _cy1 = 0;
  // what save kept, six ints a save, [_saved] of them used; kept from
  // frame to frame, so a frame allocates only when it nests deeper than
  // any before (a growable list cleared gives its storage back)
  var _stack = Int32List(6 * 16);
  var _saved = 0;

  // per-draw-call state (fields so the hot helpers stay small)
  var _row = 0;
  var _y = 0;
  var _pen = 0;
  var _opaque = -1;
  var _lastIn = -1;
  var _lastOut = 0;
  var _dmgLo = 0;
  var _dmgHi = 0;

  /// Origin (0, 0), clip = whole surface, empty save stack.
  void reset() {
    _ox = 0;
    _oy = 0;
    _cx0 = 0;
    _cy0 = 0;
    _cx1 = surface.width;
    _cy1 = surface.height;
    _saved = 0;
  }

  /// Keeps the origin and the clip, for [restore] to bring back.
  ///
  /// Saves nest: each [restore] brings back the last kept.
  void save() {
    var n = _saved;
    if (n + 6 > _stack.length) {
      _stack = Int32List(_stack.length * 2)..setRange(0, n, _stack);
    }
    final st = _stack;
    st[n++] = _ox;
    st[n++] = _oy;
    st[n++] = _cx0;
    st[n++] = _cy0;
    st[n++] = _cx1;
    st[n++] = _cy1;
    _saved = n;
  }

  /// Brings back the origin and the clip the last [save] kept.
  ///
  /// Asserts there is one.
  void restore() {
    final n = _saved;
    assert(n >= 6, 'restore() without a matching save()');
    final st = _stack;
    _cy1 = st[n - 1];
    _cx1 = st[n - 2];
    _cy0 = st[n - 3];
    _cx0 = st[n - 4];
    _oy = st[n - 5];
    _ox = st[n - 6];
    _saved = n - 6;
  }

  /// Moves the origin [dx] cells right and [dy] down; the clip stays
  /// where it is on the surface.
  void translate(int dx, int dy) {
    _ox += dx;
    _oy += dy;
  }

  /// Intersects the clip with the rectangle (local coordinates).
  void clipRect(int x, int y, int w, int h) {
    final x0 = x + _ox;
    final y0 = y + _oy;
    if (x0 > _cx0) {
      _cx0 = x0;
    }
    if (y0 > _cy0) {
      _cy0 = y0;
    }
    if (x0 + w < _cx1) {
      _cx1 = x0 + w;
    }
    if (y0 + h < _cy1) {
      _cy1 = y0 + h;
    }
    if (_cx1 <= _cx0 || _cy1 <= _cy0) {
      _cx0 = _cx1 = _cy0 = _cy1 = 0; // empty clip
    }
  }

  /// The column of the surface the origin is at, as [translate] moved it.
  int get originX => _ox;

  /// The row of the surface the origin is at, as [translate] moved it.
  int get originY => _oy;

  /// Clip in surface coordinates: (x0, y0, x1, y1).
  (int, int, int, int) get clipBounds => (_cx0, _cy0, _cx1, _cy1);

  /// Whether the clip contains the surface rectangle [x0, x1) x [y0, y1).
  bool clipContains(int x0, int y0, int x1, int y1) =>
      _cx0 <= x0 && _cy0 <= y0 && _cx1 >= x1 && _cy1 >= y1;

  // ---------------------------------------------------------------- fills --

  /// Fills a rectangle with code point [cp] (default: blank) using [pen].
  /// A two-column [cp] is laid out every other column. A [cp] that can't
  /// stand in a cell of its own (a control, a mark, or one a terminal
  /// would join with its neighbours) fills with blanks.
  void fill(int x, int y, int w, int h, int pen, [int cp = kBlank]) {
    final ax = x + _ox;
    var x0 = ax;
    var y0 = y + _oy;
    var x1 = x0 + w;
    var y1 = y0 + h;
    if (x0 < _cx0) {
      x0 = _cx0;
    }
    if (y0 < _cy0) {
      y0 = _cy0;
    }
    if (x1 > _cx1) {
      x1 = _cx1;
    }
    if (y1 > _cy1) {
      y1 = _cy1;
    }
    if (x0 >= x1 || y0 >= y1) {
      return;
    }
    final cpWidth = codePointWidth(cp, segmenter.ambiguousWidth);
    // controls, marks and code points a terminal joins with their
    // neighbours into one cluster can't fill cells: blanks instead
    final alone = cpWidth > 0 && _fillsAlone(cp);
    final c = alone ? cp : kBlank;
    final cw = alone ? cpWidth : 1;
    final glyph = codePointUncertain(c) ? c | kUncertain : c;
    if (cw == 2) {
      _fillWide(ax, x0, y0, x1, y1, pen, glyph);
      return;
    }
    final cells = surface.cells;
    final sty = surface.styles;
    final width = surface.width;
    final opaque = styles.opaqueStyleOf(pen);
    if (x0 == 0 && x1 == width) {
      // whole rows: one contiguous block, and no wide glyph can be cut
      final a = y0 * width;
      final b = y1 * width;
      fillU32(cells, a, b, glyph);
      if (opaque >= 0) {
        fillU32(sty, a, b, opaque);
      } else {
        _composeRuns(a, b, pen);
      }
      for (var yy = y0; yy < y1; yy++) {
        surface.markDirty(yy, 0, width);
      }
      return;
    }
    for (var yy = y0; yy < y1; yy++) {
      final row = yy * width;
      _breakEdges(row, x0, x1);
      final lo = _edgeLo;
      final hi = _edgeHi;
      fillU32(cells, row + x0, row + x1, glyph);
      if (opaque >= 0) {
        fillU32(sty, row + x0, row + x1, opaque);
      } else {
        _composeRuns(row + x0, row + x1, pen);
      }
      surface.markDirty(yy, lo, hi);
    }
  }

  /// Hands the rectangle to something drawn outside the cell model (an
  /// inline image): its cells are marked [kSkip], which the presenter never
  /// writes, erases or compares, until something is drawn over them again.
  /// Wide glyphs cut by its edges are broken up, as by [fill].
  void reserve(int x, int y, int w, int h) {
    final r = _clipped(x, y, w, h);
    if (r == null) {
      return;
    }
    final (x0, y0, x1, y1) = r;
    for (var yy = y0; yy < y1; yy++) {
      final row = yy * surface.width;
      _breakEdges(row, x0, x1);
      fillU32(surface.cells, row + x0, row + x1, kSkip);
      surface.markDirty(yy, _edgeLo, _edgeHi);
    }
  }

  /// Shows [image] in the [cols] x [rows] cells from (x, y), scaled to fill
  /// them: the cells are reserved as by [reserve], and the presenter draws
  /// the image over blanks in the styles they have (a transparent image
  /// shows the background painted there first). What the clip cuts off is
  /// not shown; of a sixel or iTerm2 image then none is, its cells stay
  /// blank. The image takes the place of those it is drawn over, and goes
  /// once anything is drawn over its cells (see [Surface.images]): kitty's
  /// from all of them, sixel and iTerm2 pixels from those written over.
  void image(int x, int y, int cols, int rows, TerminalImage image) {
    final r = _clipped(x, y, cols, rows);
    if (r == null) {
      return;
    }
    final (x0, y0, x1, y1) = r;
    reserve(x, y, cols, rows);
    surface.place(
      ImagePlacement(image, x + _ox, y + _oy, cols, rows, x0, y0, x1, y1),
    );
  }

  /// The rectangle in surface coordinates, clipped; null when empty.
  (int, int, int, int)? _clipped(int x, int y, int w, int h) {
    var x0 = x + _ox;
    var y0 = y + _oy;
    var x1 = x0 + w;
    var y1 = y0 + h;
    if (x0 < _cx0) {
      x0 = _cx0;
    }
    if (y0 < _cy0) {
      y0 = _cy0;
    }
    if (x1 > _cx1) {
      x1 = _cx1;
    }
    if (y1 > _cy1) {
      y1 = _cy1;
    }
    return x0 >= x1 || y0 >= y1 ? null : (x0, y0, x1, y1);
  }

  // columns to damage after _breakEdges (fields: no allocation per row)
  var _edgeLo = 0;
  var _edgeHi = 0;

  /// Breaks wide glyphs cut by the edges of columns [x0, x1) of the row at
  /// [row]; the columns to damage go to `_edgeLo`/`_edgeHi`. A partner
  /// blanked at either edge may lie on either side (a one column write over
  /// a leading half blanks the trailing one).
  @pragma('vm:prefer-inline')
  void _breakEdges(int row, int x0, int x1) {
    var lo = x0;
    var hi = x1;
    for (var k = 0; k < 2; k++) {
      final p = surface.breakWideAt(row, k == 0 ? x0 : x1 - 1);
      if (p >= 0 && p < lo) {
        lo = p;
      }
      if (p >= hi) {
        hi = p + 1;
      }
    }
    _edgeLo = lo;
    _edgeHi = hi;
  }

  var _aloneCp = -1;
  var _alone = false;
  final _aloneScan = ClusterScan();

  /// Whether copies of [cp] side by side stay clusters of their own, each
  /// as wide as [cp] alone (a fill writes one per cell).
  bool _fillsAlone(int cp) {
    if (cp < 0xA0) {
      return true;
    }
    if (cp != _aloneCp) {
      final two = String.fromCharCodes([cp, cp]);
      segmenter.scan(two, 0, _aloneScan);
      _aloneCp = cp;
      _alone =
          _aloneScan.end * 2 == two.length &&
          _aloneScan.width > 0 &&
          !_aloneScan.joinsNext;
    }
    return _alone;
  }

  /// Restyles cells [a, b) with [pen] over their own styles: one compose
  /// and one block fill per run of equal underlying styles.
  void _composeRuns(int a, int b, int pen) {
    final sty = surface.styles;
    final sty64 = surface.styles64;
    var i = a;
    while (i < b) {
      final s = sty[i];
      final j = runEndU32(sty, sty64, i + 1, b, s);
      fillU32(sty, i, j, styles.compose(s, pen));
      i = j;
    }
  }

  /// Wide glyphs every other column from [ax] (the unclipped start), so a
  /// clip doesn't shift them: a glyph cut by the clip leaves a blank.
  void _fillWide(int ax, int x0, int y0, int x1, int y1, int pen, int cp) {
    for (var yy = y0; yy < y1; yy++) {
      _begin(yy, pen);
      var x = x0;
      if ((x0 - ax).isOdd) {
        _putNarrow(x, kBlank);
        x++;
      }
      for (; x + 1 < x1; x += 2) {
        _putWide(x, cp);
      }
      if (x < x1) {
        _putNarrow(x, kBlank);
      }
      _end();
    }
  }

  // ----------------------------------------------------------------- text --

  /// Draws [s] at (x, y) with [pen]; returns the columns it advanced (0 when
  /// the row is clipped out). Tabs draw as one blank, controls and lone
  /// combining marks are dropped.
  int text(int x, int y, String s, int pen) {
    final ay = y + _oy;
    if (ay < _cy0 || ay >= _cy1 || s.isEmpty) {
      return 0;
    }
    var ax = x + _ox;
    final startX = ax;
    _begin(ay, pen);
    final scan = _scan;
    final seg = segmenter;
    final len = s.length;
    final graphemes = seg.mode == TextMode.graphemes;
    for (var i = 0; i < len;) {
      if (ax >= _cx1) {
        break;
      }
      final cu = s.codeUnitAt(i);
      // ---- run of printable ASCII: written in one tight loop ----------------
      if (cu >= 0x20 && cu < 0x7F) {
        final room = _cx1 - ax;
        final lim = len - i < room ? len : i + room;
        var j = i + 1;
        while (j < lim) {
          final c = s.codeUnitAt(j);
          if (c < 0x20 || c >= 0x7F) {
            break;
          }
          j++;
        }
        // the last one may take a combining mark: leave it to the scanner
        if (j < len && s.codeUnitAt(j) >= 0x300) {
          j--;
        }
        if (j > i) {
          _asciiRun(s, i, j, ax);
          ax += j - i;
          i = j;
          continue;
        }
      } else if (cu >= 0x80 && (cu < 0xD800 || cu > 0xDFFF)) {
        // ---- one BMP code point that can't join its neighbour --------
        final single = graphemes
            ? _standsAloneG(s, i, cu)
            : _standsAloneL(s, i, cu);
        if (single) {
          final w = codePointWidth(cu, seg.ambiguousWidth);
          i++;
          if (w == 0) {
            continue;
          }
          _place(ax, w, codePointUncertain(cu) ? cu | kUncertain : cu);
          ax += w;
          continue;
        }
      }
      final start = i;
      seg.scan(s, i, scan);
      i = scan.end;
      var w = scan.width;
      int glyph;
      if (w == 0) {
        if (scan.first != 0x09) {
          continue;
        }
        w = 1;
        glyph = kBlank;
      } else if (graphemes && isLeadingMark(scan.first)) {
        // a mark with no base: drop it, re-segment what follows
        i = start + (scan.first > 0xFFFF ? 2 : 1);
        continue;
      } else {
        glyph = scan.length == 1 ? scan.first : glyphs.intern(s, start, i);
      }
      if (scan.uncertain || scan.joinsNext) {
        glyph |= kUncertain;
      }
      _place(ax, w, glyph);
      ax += w;
    }
    _end();
    return ax - startX;
  }

  /// Scratch for [shape]: at most one glyph per UTF-16 unit.
  var _shapeBuf = Uint32List(64);

  /// Segments [s] once (for retained text layout); see [run].
  GlyphRun shape(String s) {
    if (_shapeBuf.length < s.length) {
      _shapeBuf = Uint32List(s.length * 2);
    }
    final out = _shapeBuf;
    var n = 0;
    var width = 0;
    for (var i = 0; i < s.length;) {
      final start = i;
      segmenter.scan(s, i, _scan);
      i = _scan.end;
      var w = _scan.width;
      int glyph;
      if (w == 0) {
        if (_scan.first != 0x09) {
          continue;
        }
        w = 1;
        glyph = kBlank;
      } else if (segmenter.mode == TextMode.graphemes &&
          isLeadingMark(_scan.first)) {
        i = start + (_scan.first > 0xFFFF ? 2 : 1);
        continue;
      } else {
        glyph = _scan.length == 1 ? _scan.first : glyphs.intern(s, start, i);
      }
      if (_scan.uncertain || _scan.joinsNext) {
        glyph |= kUncertain;
      }
      if (w == 2) {
        glyph |= kWide;
      }
      out[n++] = glyph;
      width += w;
    }
    return GlyphRun(out.sublist(0, n), width);
  }

  /// Draws a pre-shaped run; same semantics as [text] without segmentation.
  @pragma('vm:prefer-inline')
  int run(int x, int y, GlyphRun r, int pen) =>
      runRange(x, y, r.glyphs, 0, r.glyphs.length, pen);

  /// Draws glyph words [start, end) of [g] as [run] draws a run of them:
  /// a piece of a buffer that holds several (what a retained layout keeps
  /// for all its lines), drawn without copying it out.
  int runRange(int x, int y, Uint32List g, int start, int end, int pen) {
    assert(0 <= start && start <= end && end <= g.length, 'range in g');
    final ay = y + _oy;
    if (ay < _cy0 || ay >= _cy1) {
      return 0;
    }
    var ax = x + _ox;
    final startX = ax;
    _begin(ay, pen);
    for (var i = start; i < end; i++) {
      if (ax >= _cx1) {
        break;
      }
      final word = g[i];
      final w = (word & kWide) != 0 ? 2 : 1;
      _place(ax, w, word & ~kWide);
      ax += w;
    }
    _end();
    return ax - startX;
  }

  /// Draws [r], pieces of line one column each, as [run] does, but merged
  /// with the line already in each cell: the cell gets the piece that
  /// reaches out wherever either of them does, an arm both have in the
  /// weight of the new one. Light (single and rounded), heavy and double
  /// lines keep their own weights where Unicode has a piece for the mix —
  /// light and heavy always, light and double where the arms across share
  /// a weight and so do those down; elsewhere every arm takes the weight of
  /// the new piece. The piece drawn, or the one in the cell where the new
  /// one adds nothing to it, is kept as it is: a round corner stays round.
  /// Dashed lines merge as solid ones. ASCII pieces (`-`, `|`, and `+`,
  /// which reaches out all four ways) merge only with each other, box
  /// drawing only with box drawing, a piece of one drawn over one of the
  /// other as [run] draws it. A cell that holds text (any glyph but a
  /// blank or a piece of line, a wide one whole) keeps it and its style:
  /// a line merged over the edge of a box joins its lines and leaves its
  /// titles. A glyph in [r] that is no piece of line is drawn as [run]
  /// draws it.
  ///
  /// Where its cell holds a line to merge with, the first piece drops the
  /// arms [trimFirst] and the last one those of [trimLast] (up 1, right 2,
  /// down 4, left 8): the end of a line meets one in a joint rather than
  /// crossing it (`├`, not `┼`). With [under] each cell is painted with
  /// that pen first, under the line or the text it keeps, keeping its
  /// glyph.
  int mergeRun(
    int x,
    int y,
    GlyphRun r,
    int pen, {
    int under = -1,
    int trimFirst = 0,
    int trimLast = 0,
  }) {
    final ay = y + _oy;
    if (ay < _cy0 || ay >= _cy1) {
      return 0;
    }
    var ax = x + _ox;
    final startX = ax;
    _begin(ay, pen);
    final g = r.glyphs;
    final last = g.length - 1;
    final cells = surface.cells;
    final sty = surface.styles;
    for (var i = 0; i <= last; i++) {
      if (ax >= _cx1) {
        break;
      }
      assert((g[i] & kWide) == 0, 'pieces of line one column wide');
      if (ax >= _cx0) {
        final at = _row + ax;
        final trim = (i == 0 ? trimFirst : 0) | (i == last ? trimLast : 0);
        final glyph = _mergedLine(g[i], cells[at], trim);
        if (under >= 0) {
          sty[at] = styles.compose(sty[at], under);
        }
        if (glyph >= 0) {
          _putNarrow(ax, glyph);
        } else if (under >= 0) {
          _touch(ax, ax + 1);
        }
      }
      ax++;
    }
    _end();
    return ax - startX;
  }

  // -------------------------------------------------------------- helpers --

  /// Grapheme mode: [cu] (at [i]) is a cluster on its own. True when it is
  /// Grapheme_Cluster_Break=Other (not a control, mark, Prepend, Hangul jamo
  /// or regional indicator) and the next code point is not Extend, ZWJ or
  /// SpacingMark - exactly the UAX #29 rules for such a code point.
  @pragma('vm:prefer-inline')
  static bool _standsAloneG(String s, int i, int cu) {
    if ((segmentationProperty(cu) & 0x0F) != gcbOther) {
      return false;
    }
    if (i + 1 >= s.length) {
      return true;
    }
    final g = segmentationProperty(_cpAfter(s, i)) & 0x0F;
    return g != gcbExtend && g != gcbZWJ && g != gcbSpacingMark;
  }

  /// Legacy mode: [cu] is not a control and the next code point doesn't
  /// attach to it (zero-width, non-control code points attach).
  @pragma('vm:prefer-inline')
  static bool _standsAloneL(String s, int i, int cu) {
    final g = segmentationProperty(cu) & 0x0F;
    if (g == gcbControl || g == gcbCR || g == gcbLF) {
      return false;
    }
    if (i + 1 >= s.length) {
      return true;
    }
    final n = _cpAfter(s, i);
    if (codePointWidth(n) != 0) {
      return true;
    }
    final ng = segmentationProperty(n) & 0x0F;
    return ng == gcbControl || ng == gcbCR || ng == gcbLF;
  }

  /// Code point at i + 1 (a lone surrogate is returned as is).
  @pragma('vm:prefer-inline')
  static int _cpAfter(String s, int i) {
    final n = s.codeUnitAt(i + 1);
    if (n >= 0xD800 && n <= 0xDBFF && i + 2 < s.length) {
      final lo = s.codeUnitAt(i + 2);
      if (lo >= 0xDC00 && lo <= 0xDFFF) {
        return 0x10000 + ((n - 0xD800) << 10) + (lo - 0xDC00);
      }
    }
    return n;
  }

  /// Writes s[i, j) (printable ASCII) at column [ax] of the current row,
  /// honouring the left clip (the caller bounded it by the right clip).
  void _asciiRun(String s, int i, int j, int ax) {
    var x = ax;
    var k = i;
    if (x < _cx0) {
      k += _cx0 - x;
      x = _cx0;
      if (k >= j) {
        return;
      }
    }
    final row = _row;
    final cells = surface.cells;
    final sty = surface.styles;
    final x0 = x;
    for (; k < j; k++, x++) {
      final idx = row + x;
      if ((cells[idx] & (kWide | kCont)) != 0) {
        final p = surface.breakWideAt(row, x);
        if (p >= 0) {
          _touch(p, p + 1);
        }
      }
      sty[idx] = _styleFor(idx);
      cells[idx] = s.codeUnitAt(k);
    }
    _touch(x0, x);
  }

  @pragma('vm:prefer-inline')
  void _begin(int y, int pen) {
    _y = y;
    _row = y * surface.width;
    _pen = pen;
    _opaque = styles.opaqueStyleOf(pen);
    _lastIn = -1;
    _dmgLo = 1 << 30;
    _dmgHi = -1;
  }

  @pragma('vm:prefer-inline')
  void _end() {
    if (_dmgHi > _dmgLo) {
      surface.markDirty(_y, _dmgLo, _dmgHi);
    }
  }

  /// Places a glyph of width [w] at absolute column [ax], honouring clip.
  @pragma('vm:prefer-inline')
  void _place(int ax, int w, int glyph) {
    if (w == 1) {
      if (ax >= _cx0) {
        _putNarrow(ax, glyph);
      }
      return;
    }
    if (ax >= _cx0 && ax + 1 < _cx1) {
      _putWide(ax, glyph);
    } else if (ax + 1 == _cx0 && ax + 1 < _cx1) {
      _putNarrow(ax + 1, kBlank); // left half clipped
    } else if (ax >= _cx0 && ax < _cx1) {
      _putNarrow(ax, kBlank); // right half clipped
    }
  }

  @pragma('vm:prefer-inline')
  int _styleFor(int i) {
    if (_opaque >= 0) {
      return _opaque;
    }
    final s = surface.styles[i];
    if (s != _lastIn) {
      _lastIn = s;
      _lastOut = styles.compose(s, _pen);
    }
    return _lastOut;
  }

  @pragma('vm:prefer-inline')
  void _touch(int x0, int x1) {
    if (x0 < _dmgLo) {
      _dmgLo = x0;
    }
    if (x1 > _dmgHi) {
      _dmgHi = x1;
    }
  }

  void _putNarrow(int x, int glyph) {
    final i = _row + x;
    final cells = surface.cells;
    if ((cells[i] & (kWide | kCont)) != 0) {
      final p = surface.breakWideAt(_row, x);
      if (p >= 0) {
        _touch(p, p + 1);
      }
    }
    surface.styles[i] = _styleFor(i);
    cells[i] = glyph;
    _touch(x, x + 1);
  }

  void _putWide(int x, int glyph) {
    final i = _row + x;
    final cells = surface.cells;
    if ((cells[i] & kCont) != 0) {
      final p = surface.breakWideAt(_row, x);
      if (p >= 0) {
        _touch(p, p + 1);
      }
    }
    if ((cells[i + 1] & kWide) != 0) {
      final p = surface.breakWideAt(_row, x + 1);
      if (p >= 0) {
        _touch(p, p + 1);
      }
    }
    final st = _styleFor(i);
    final sty = surface.styles;
    sty[i] = st;
    sty[i + 1] = st;
    cells[i] = glyph | kWide;
    cells[i + 1] = kCont;
    _touch(x, x + 2);
  }
}

// ---------------------------------------------------------- line merging --

// A piece of line as merging sees it: the weight of each arm in two bits
// (0 none, 1 light, 2 heavy, 3 double), up in bits 0-1, right 2-3, down
// 4-5 and left 6-7; ASCII pieces with [_ascii] set, their arms light.
const _ascii = 0x100;

/// The box drawing piece of each set of weighted arms, a blank where
/// Unicode has none: row the weight of down plus 4× that of left, column
/// the weight of up plus 4× that of right.
const _pieceRows = [
  ' ╵╹ ╶└┖╙╺┕┗  ╘ ╚',
  '╷│╿ ┌├┞ ┍┝┡ ╒╞  ',
  '╻╽┃ ┎┟┠ ┏┢┣     ',
  '   ║╓  ╟    ╔  ╠',
  '╴┘┚╜─┴┸╨╼┶┺     ',
  '┐┤┦ ┬┼╀ ┮┾╄     ',
  '┒┧┨ ┰╁╂ ┲╆╊     ',
  '╖  ╢╥  ╫        ',
  '╸┙┛ ╾┵┹ ━┷┻     ',
  '┑┥┩ ┭┽╃ ┯┿╇     ',
  '┓┪┫ ┱╅╉ ┳╈╋     ',
  '                ',
  ' ╛ ╝        ═╧ ╩',
  '╕╡          ╤╪  ',
  '                ',
  '╗  ╣        ╦  ╬',
];

/// The box drawing piece of [line], weighted arms; a blank for none.
int _pieceOf(int line) => _pieceRows[line >> 4].codeUnitAt(line & 15);

/// The weighted arms of each code point of the box drawing block
/// (U+2500..U+257F): the dashed lines as solid ones, the round corners as
/// square ones, the diagonals none.
final Uint8List _boxArms = () {
  final arms = Uint8List(0x80);
  for (var i = 1; i < 0x100; i++) {
    final cp = _pieceOf(i);
    if (cp != kBlank) {
      arms[cp - 0x2500] = i;
    }
  }
  const like = '┄┅┆┇┈┉┊┋╌╍╎╏╭╮╯╰';
  const solid = '─━│┃─━│┃─━│┃┌┐┘└';
  for (var i = 0; i < like.length; i++) {
    arms[like.codeUnitAt(i) - 0x2500] = arms[solid.codeUnitAt(i) - 0x2500];
  }
  return arms;
}();

/// The piece of line [glyph] is, as weighted arms; 0 for none.
int _lineOf(int glyph) {
  final cp = glyph & ~kUncertain;
  if (cp >= 0x2500 && cp < 0x2580) {
    return _boxArms[cp - 0x2500];
  }
  return switch (cp) {
    0x2D => _ascii | 0x44, // -
    0x7C => _ascii | 0x11, // |
    0x2B => _ascii | 0x55, // +
    _ => 0,
  };
}

/// A bit for each arm [line] has: bits 0, 2, 4 and 6.
int _armsOf(int line) => (line | line >> 1) & 0x55;

/// [glyph], a piece of line, merged with [cell], the glyph of the cell it
/// is drawn in ([Canvas.mergeRun]), less the arms [trim] (up 1, right 2,
/// down 4, left 8) where [cell] holds a line to merge with; -1 where
/// [cell] holds text to keep: a glyph that is neither a blank nor a piece
/// of line, or either half of a wide one.
int _mergedLine(int glyph, int cell, int trim) {
  final n = _lineOf(glyph);
  if (n == 0) {
    return glyph;
  }
  final o = _lineOf(cell);
  if (o == 0) {
    return (cell & kGlyphMask) != kBlank && (cell & kSkip) == 0 ? -1 : glyph;
  }
  if (((n ^ o) & _ascii) != 0) {
    return glyph;
  }
  final spread =
      (trim & 1) | (trim & 2) << 1 | (trim & 4) << 2 | (trim & 8) << 3;
  final t = n & ~(spread * 3);
  if ((t & 0xFF) == 0) {
    return cell;
  }
  if ((t & _ascii) != 0) {
    final arms = _armsOf(t | o);
    final down = (arms & 0x11) != 0;
    final across = (arms & 0x44) != 0;
    return down && across ? 0x2B : (down ? 0x7C : 0x2D);
  }
  // the arms of the new piece, and those of the old one it lacks
  final m = t | (o & ~(_armsOf(t) * 3));
  if (m == n) {
    return glyph;
  }
  if (m == o) {
    return cell;
  }
  var cp = _pieceOf(m);
  if (cp == kBlank) {
    // no piece mixes these weights: every arm in that of the new piece
    var w = 0;
    for (var s = 0; w == 0; s += 2) {
      w = (t >> s) & 3;
    }
    cp = _pieceOf(_armsOf(m) * w);
  }
  return cp == kBlank ? glyph : cp;
}
