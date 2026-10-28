part of 'render.dart';

// ---------------------------------------------------------------- effects --

/// Shows its child through an effect over the cells of its bounds: each
/// cell shows what [effectCell] makes of what the child painted there and
/// what was under it. As big as the child.
///
/// A repaint boundary that keeps, for each cell of its bounds, what was
/// under it and what the child painted there, so that:
///
///  * a new frame of the effect ([markNeedsPaint] on this object) is shown
///    from what it kept, painting neither the child nor what is under it;
///  * the child repaints normally underneath: a mark in it paints the child
///    again over what was under it, and what a repaint boundary in it
///    repaints on its own (all of its cells, while there is an effect) is
///    kept and shown through the effect in those cells;
///  * without an effect ([hasEffect]) the child shows as it paints, and
///    only what is under it is kept.
///
/// It puts back what was under it before the child repaints, so the child
/// need not paint every cell with an opaque background, as that of another
/// repaint boundary must. A two-column glyph is kept whole, or blanked
/// where only half of it is left.
///
/// A wipe that shows the first `shown` columns of the child and what is
/// under it in the others; each step sets `shown` and marks it for paint
/// ([markNeedsPaint]):
///
/// ```dart
/// final class Wipe extends RenderEffect {
///   var shown = 0;
///
///   @override
///   bool get hasEffect => shown < width;
///
///   @override
///   void effectCell(
///     int x,
///     int y,
///     int glyph,
///     int style,
///     int underGlyph,
///     int underStyle,
///   ) {
///     effectGlyph = x < shown ? glyph : underGlyph;
///     effectStyle = x < shown ? style : underStyle;
///   }
/// }
/// ```
abstract base class RenderEffect extends RenderObject
    with RenderObjectWithChildMixin {
  /// An effect with no child yet, for a subclass to construct.
  RenderEffect();

  /// Whether the effect changes anything: while it does not, the child
  /// shows as it paints. A change is shown once this object is marked for
  /// paint.
  bool get hasEffect;

  /// Called before [effectCell] is called for the cells of a pass, with the
  /// styles of the canvas.
  void beginEffect(StyleTable styles) {}

  /// Sets [effectGlyph] and [effectStyle] to what the cell at [x], [y] of
  /// this object shows, where the child painted the glyph word [glyph] in
  /// [style] over [underGlyph] in [underStyle] (as [Surface.cells] and
  /// [Surface.styles] hold them).
  void effectCell(
    int x,
    int y,
    int glyph,
    int style,
    int underGlyph,
    int underStyle,
  );

  /// The glyph word [effectCell] shows in its cell.
  var effectGlyph = 0;

  /// The style [effectCell] shows in its cell.
  var effectStyle = 0;

  // what it keeps, in its own coordinates, a cell at y * width + x: what
  // was under it and what the child painted, each valid in a span of
  // columns per row, from [2 * y] to [2 * y + 1]; on _surface, at its size
  Surface? _surface;
  var _w = 0;
  var _h = 0;
  var _underCells = Uint32List(0);
  var _underStyles = Uint32List(0);
  var _underSpans = Int32List(0);
  var _childCells = Uint32List(0);
  var _childStyles = Uint32List(0);
  var _childSpans = Int32List(0);

  @override
  bool get isRepaintBoundary => true;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add('effect', hasEffect, defaultValue: false);
  }

  @override
  void performLayout(BoxConstraints c) {
    final child = this.child;
    if (child == null) {
      width = c.minW;
      height = c.minH;
      return;
    }
    child
      ..layout(c, parentUsesSize: true)
      ..parentData.dx = 0
      ..parentData.dy = 0;
    width = child.width;
    height = child.height;
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMinIntrinsicHeight(int width) =>
      child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void detach() {
    _surface = null;
    super.detach();
  }

  /// What the child painted is to be painted again.
  @override
  void invalidatePaintCache() {
    _childSpans.fillRange(0, _childSpans.length, 0);
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final surface = canvas.surface;
    final (x0, y0, x1, y1) = canvas.clipBounds;
    if (x0 >= x1 || y0 >= y1) {
      return;
    }
    if (!identical(surface, _surface) || width != _w || height != _h) {
      _reset(surface);
    }
    final (gx, gy) = globalOffset;
    final ax = x0 - gx;
    final ay = y0 - gy;
    final bx = x1 - gx;
    final by = y1 - gy;
    if (identical(owner?._alone, this) && _holds(_underSpans, ax, ay, bx, by)) {
      // repainted on its own: the surface holds what it showed last
      if (hasEffect && _holds(_childSpans, ax, ay, bx, by)) {
        // a new frame of the effect
        _show(surface, canvas.styles, gx, gy, x0, y0, x1, y1);
        // the child kept showing what it showed: the boundaries in it
        // marked for paint repaint on their own
        _paintedIn = 0;
        return;
      }
      _putBack(surface, gx, gy, x0, y0, x1, y1);
    } else {
      // what is there is what is under it
      _keepUnder(surface, gx, gy, x0, y0, x1, y1);
    }
    final child = this.child;
    if (child == null) {
      return;
    }
    paintChild(ctx, child);
    if (hasEffect) {
      _keepChild(surface, gx, gy, x0, y0, x1, y1);
      _show(surface, canvas.styles, gx, gy, x0, y0, x1, y1);
    } else {
      invalidatePaintCache();
    }
  }

  @override
  bool paintsOver(RenderObject child, int x, int y, int w, int h) => hasEffect;

  /// Keeps what a repaint boundary in the child has just repainted, the
  /// cells the canvas is clipped to, and shows them through the effect;
  /// nothing without an effect, where the child shows as it paints. The
  /// owner calls it on every ancestor of the boundary once one of them
  /// paints over it, not only on those whose [paintsOver] holds.
  @override
  void paintOver(
    PaintContext ctx,
    RenderObject child,
    int x,
    int y,
    int w,
    int h,
  ) {
    if (!hasEffect) {
      return;
    }
    final canvas = ctx.canvas;
    final surface = canvas.surface;
    final (x0, y0, x1, y1) = canvas.clipBounds;
    if (x0 >= x1 ||
        y0 >= y1 ||
        !identical(surface, _surface) ||
        width != _w ||
        height != _h) {
      return;
    }
    final (gx, gy) = globalOffset;
    if (!_holds(_underSpans, x0 - gx, y0 - gy, x1 - gx, y1 - gy)) {
      // what was under them is not known: the child stands for it
      _keepUnder(surface, gx, gy, x0, y0, x1, y1);
    }
    _keepChild(surface, gx, gy, x0, y0, x1, y1);
    _show(surface, canvas.styles, gx, gy, x0, y0, x1, y1);
  }

  /// Forgets all it kept, from now on of [surface] at its size.
  void _reset(Surface surface) {
    _surface = surface;
    _w = width;
    _h = height;
    final n = _w * _h;
    if (_underCells.length < n) {
      _underCells = Uint32List(n);
      _underStyles = Uint32List(n);
      _childCells = Uint32List(n);
      _childStyles = Uint32List(n);
    }
    if (_underSpans.length < 2 * _h) {
      _underSpans = Int32List(2 * _h);
      _childSpans = Int32List(2 * _h);
    } else {
      _underSpans.fillRange(0, _underSpans.length, 0);
      _childSpans.fillRange(0, _childSpans.length, 0);
    }
  }

  /// Whether [spans] hold the cells [ax]..[bx], [ay]..[by] of this object.
  static bool _holds(Int32List spans, int ax, int ay, int bx, int by) {
    for (var y = ay; y < by; y++) {
      if (spans[2 * y] > ax || spans[2 * y + 1] < bx) {
        return false;
      }
    }
    return true;
  }

  /// Keeps the cells [x0]..[x1], [y0]..[y1] of [surface] in [cells] and
  /// [styles], valid from then on in [spans] as well; this object is at
  /// [gx], [gy] of it.
  void _keep(
    Surface surface,
    Uint32List cells,
    Uint32List styles,
    Int32List spans,
    int gx,
    int gy,
    int x0,
    int y0,
    int x1,
    int y1,
  ) {
    final w = _w;
    final n = x1 - x0;
    final a = x0 - gx;
    final b = x1 - gx;
    for (var y = y0; y < y1; y++) {
      final from = y * surface.width + x0;
      final row = y - gy;
      final to = row * w + a;
      cells.setRange(to, to + n, surface.cells, from);
      styles.setRange(to, to + n, surface.styles, from);
      final start = spans[2 * row];
      final end = spans[2 * row + 1];
      if (start >= end || (a <= start && b >= end)) {
        spans[2 * row] = a;
        spans[2 * row + 1] = b;
      } else if (a <= end && b >= start) {
        // overlapping or next to it: one span
        spans[2 * row] = a < start ? a : start;
        spans[2 * row + 1] = b > end ? b : end;
      }
    }
  }

  void _keepUnder(
    Surface surface,
    int gx,
    int gy,
    int x0,
    int y0,
    int x1,
    int y1,
  ) => _keep(
    surface,
    _underCells,
    _underStyles,
    _underSpans,
    gx,
    gy,
    x0,
    y0,
    x1,
    y1,
  );

  void _keepChild(
    Surface surface,
    int gx,
    int gy,
    int x0,
    int y0,
    int x1,
    int y1,
  ) => _keep(
    surface,
    _childCells,
    _childStyles,
    _childSpans,
    gx,
    gy,
    x0,
    y0,
    x1,
    y1,
  );

  /// Puts what was under it back in the cells [x0]..[x1], [y0]..[y1] of
  /// [surface].
  void _putBack(
    Surface surface,
    int gx,
    int gy,
    int x0,
    int y0,
    int x1,
    int y1,
  ) {
    final n = x1 - x0;
    for (var y = y0; y < y1; y++) {
      final to = y * surface.width + x0;
      final from = (y - gy) * _w + x0 - gx;
      surface.cells.setRange(to, to + n, _underCells, from);
      surface.styles.setRange(to, to + n, _underStyles, from);
      surface.markDirty(y, x0, x1);
    }
  }

  /// Shows the cells [x0]..[x1], [y0]..[y1] of [surface], kept, through the
  /// effect.
  void _show(
    Surface surface,
    StyleTable styles,
    int gx,
    int gy,
    int x0,
    int y0,
    int x1,
    int y1,
  ) {
    beginEffect(styles);
    final cells = surface.cells;
    final sty = surface.styles;
    final width = surface.width;
    final w = _w;
    for (var y = y0; y < y1; y++) {
      final row = y * width;
      final kept = (y - gy) * w - gx;
      // the cell before is the first half of a two-column glyph
      var wide = x0 > 0 && (cells[row + x0 - 1] & kWide) != 0;
      for (var x = x0; x < x1; x++) {
        final i = row + x;
        final c = _childCells[kept + x];
        final u = _underCells[kept + x];
        if (wide) {
          wide = false;
          if (((c | u) & kCont) != 0) {
            // its second half
            cells[i] = kCont;
            sty[i] = sty[i - 1];
            continue;
          }
          if (x > x0) {
            cells[i - 1] = kBlank;
          }
        }
        effectCell(
          x - gx,
          y - gy,
          c,
          _childStyles[kept + x],
          u,
          _underStyles[kept + x],
        );
        var glyph = effectGlyph;
        if ((glyph & kCont) != 0) {
          // the second half of a glyph whose first half is not here
          glyph = kBlank;
        }
        cells[i] = glyph;
        sty[i] = effectStyle;
        wide = (glyph & kWide) != 0;
      }
      if (wide && (x1 >= width || (cells[row + x1] & kCont) == 0)) {
        cells[row + x1 - 1] = kBlank;
      }
      surface.markDirty(y, x0, x1);
    }
  }
}
