part of 'render.dart';

/// Lays out and paints a tree of [RenderObject]s from its [root], a frame
/// at a time: what was marked since the last frame, and nothing else.
///
/// A frame is [flushLayout] at the screen size, then [flushPaint] onto the
/// screen's canvas, whose surface the presenter then turns into bytes.
/// [RenderObject.markNeedsLayout] and [RenderObject.markNeedsPaint] queue
/// work here and call [onNeedFrame], which schedules the next frame;
/// [hasWork] says whether there is any. [hitTest] finds the objects at a
/// cell, and [onError] hears what an object's layout or paint throws.
///
/// A tree on a screen, one frame:
///
/// ```dart
/// final screen = Screen(20, 1);
/// final pen = screen.styles.pen(const Pen());
/// final owner = PipelineOwner(() {}, segmenter: screen.canvas.segmenter)
///   ..root = RenderText('Hello', pen);
/// final ctx = PaintContext(screen.canvas, screen.surface, screen.presenter);
/// owner
///   ..flushLayout(20, 1)
///   ..flushPaint(ctx);
/// final bytes = screen.render(); // what to write to the terminal
/// ```
///
/// See also:
///
///  * `TwkApp`, which owns one and runs its frames in a terminal.
///  * `renderToString`, one frame of a tree as text.
final class PipelineOwner {
  /// An owner with no root yet, which calls [onNeedFrame] when something
  /// is marked; text is measured with [segmenter], a [TextSegmenter] of
  /// its own when left out.
  PipelineOwner(this.onNeedFrame, {TextSegmenter? segmenter})
    : segmenter = segmenter ?? TextSegmenter();

  /// Called each time a render object is marked for layout or paint, and
  /// when [root] is set: the next frame has work to do. Called again for
  /// each mark, so it schedules a frame, not runs one.
  final void Function() onNeedFrame;

  /// What layout measures text with: the segmenter of the canvas the tree
  /// is painted with (`screen.canvas.segmenter`), so that text is given
  /// the columns it is drawn in.
  final TextSegmenter segmenter;

  /// Reports an exception a render object threw, and in which phase; the
  /// object shows it in its place (see [RenderObject]), and is not
  /// reported again while it throws the same one. Unset, the first such
  /// exception of a [flushLayout] or [flushPaint] is thrown once the flush
  /// has ended, and one thrown outside a flush is thrown right away.
  void Function(
    RenderObject object,
    RenderPhase phase,
    Object error,
    StackTrace stack,
  )?
  onError;

  /// Where the tree's own warnings go, such as a [RenderFlex] whose
  /// children overflow it (in debug): the sink of the app or of the tool
  /// that lays the tree out. Unset, they go to [log].
  void Function(LogRecord record)? onLog;

  /// Each repaint of a repaint boundary, or of the root on its own, blends
  /// the next tint of a cycle over the background of the cells it covered
  /// (its bounds, cut off where its ancestors cut it off), keeping their
  /// glyphs, text colours and attributes: what repaints changes colour,
  /// what keeps its colour did not repaint. Meanwhile a boundary repaints
  /// all of its cells ([RenderObject.invalidatePaintCache]), so that none
  /// is tinted twice. Off by default; turned on or off, everything is
  /// repainted.
  bool get debugRepaintRainbow => (_debug & _debugRainbow) != 0;
  set debugRepaintRainbow(bool on) => _setDebug(_debugRainbow, on);

  /// Each repaint outlines the objects in what it covered that were laid
  /// out since the last one: the background of the cells along their
  /// edges, where they are painted, blended with the tint of that frame,
  /// the next of a cycle of its own on each frame that lays anything out.
  /// An outline stays until its cells are repainted. Off by default;
  /// turned on or off, everything is repainted, and on, nothing laid out
  /// before is outlined. Meanwhile a boundary repaints all of its cells,
  /// as under [debugRepaintRainbow].
  bool get debugRelayoutHighlight => (_debug & _debugRelayout) != 0;
  set debugRelayoutHighlight(bool on) => _setDebug(_debugRelayout, on);

  // the debug paints on (_debugRainbow, _debugRelayout); where each one's
  // cycle of tints is; the flushPaint that outlined last, and the pen it
  // outlined with
  var _debug = 0;
  var _rainbowAt = 0;
  var _relayoutAt = 0;
  var _outlinedIn = 0;
  var _outlinePen = 0;

  void _setDebug(int flag, bool on) {
    final debug = on ? _debug | flag : _debug & ~flag;
    if (debug == _debug) {
      return;
    }
    _debug = debug;
    if (on && flag == _debugRelayout && _root != null) {
      _forgetLayout(_root!);
    }
    markAllDirty();
  }

  // a flush runs; what it is to throw when it ends (no onError); a paint
  // threw since the boundary being painted was entered
  var _flushing = false;
  (Object, StackTrace)? _thrown;
  var _paintThrew = false;

  // the boundary flushPaint paints on its own, while it paints: under it
  // the surface holds what it painted last, not what its parent painted
  // (RenderEffect)
  RenderObject? _alone;

  RenderObject? _root;

  // boundaries to repaint; swapped with _painting for the duration of a
  // flushPaint, so marks made while painting go to the next frame
  var _dirty = <RenderObject>[];
  var _painting = <RenderObject>[];
  var _paintGen = 0;
  // a flushPaint is under way
  var _paintFlushing = false;
  // the objects marked for paint below their boundaries since a
  // flushPaint settled the rows its boundaries repaint
  // (RenderObject._markedBelow), the first _markedCount of _marked: a
  // list that keeps its storage, which a growable one cleared does not
  var _marked = List<RenderObject?>.filled(16, null);
  var _markedCount = 0;
  // per slot of a boundary a flushPaint repaints (RenderObject._slot): the
  // first of the rows it repaints, in its own coordinates, and the row
  // after the last; none when the first is not before the other
  var _rows = Int32List(64);
  // what _addWholes walks: the slot of the boundary it walks, the rows of
  // it the object whose children it visits shows, and that object's row
  var _wholeSlot = 0;
  var _wholeTop = 0;
  var _wholeBottom = 0;
  var _wholeAt = 0;
  late final void Function(RenderObject) _visitWhole = _addWholesIn;
  // the attached objects whose beforePaint each flushPaint calls
  // (RenderObject.checkedBeforePaint)
  final _checkedBeforePaint = <RenderObject>[];
  // what an object repainted whole answers which of its rows it has
  // repainted with (RenderObject.wholeRows)
  final _wholeRows = Int32List(2);
  // the boundaries a flushPaint repainted rows of in place of one inside
  // them under a wide glyph cut (_repaintAbove), the first _aboveCount of
  // _above; per each in _aboveRows, the first of those rows and the row
  // after the last
  var _above = List<RenderObject?>.filled(4, null);
  var _aboveRows = Int32List(8);
  var _aboveCount = 0;
  // the root is to be laid out at the screen size
  var _layoutDirty = true;
  // relayout boundaries to lay out again; swapped with _layingOut for the
  // duration of a pass of flushLayout, so marks made while laying out go to
  // the next pass
  var _layoutRoots = <RenderObject>[];
  var _layingOut = <RenderObject>[];
  // the most passes a flushLayout makes, each over the boundaries the last
  // one marked: more than layout callbacks are nested in any tree
  static const _layoutPasses = 100;
  // laid out by intrinsic sizes a layout callback has changed since: marked
  // for the next frame when the flushLayout ends
  final _relayoutNext = <RenderObject>[];
  // the boundaries that keep what is under them (keepsUnderlay) and have
  // kept some: a scroll that moves their cells moves what they keep
  final _underlays = <RenderObject>[];

  /// The tree's root, laid out at the size [flushLayout] is given; set
  /// before the first frame.
  ///
  /// Setting it detaches the root there was, attaches the new one and
  /// marks it to be laid out and painted whole.
  RenderObject get root => _root!;

  set root(RenderObject r) {
    if (_root != null && !identical(_root, r)) {
      _root!.detach();
    }
    _root = r;
    r
      ..attach(this)
      .._paintMarks |= _markedWhole;
    _layoutDirty = true;
    _addDirty(r);
  }

  void _addLayoutRoot(RenderObject b) {
    _layoutRoots.add(b);
    onNeedFrame();
  }

  void _addDirty(RenderObject b) {
    if (!b._queued) {
      b._queued = true;
      _dirty.add(b);
    }
    onNeedFrame();
  }

  /// Marks the whole tree to be repainted, and the root to be laid out:
  /// for when nothing painted before is on the surface any more (the
  /// screen resized, the terminal's contents lost).
  void markAllDirty() {
    final r = _root;
    if (r != null) {
      r
        ..invalidatePaintCache()
        .._paintMarks |= _markedWhole;
      _addDirty(r);
    }
    _layoutDirty = true;
  }

  /// Whether the next frame has anything to lay out or paint: the root at
  /// a new size or not laid out yet, a relayout boundary marked for
  /// layout, or a repaint boundary marked for paint.
  bool get hasWork =>
      _layoutDirty || _layoutRoots.isNotEmpty || _dirty.isNotEmpty;

  /// How many repaint boundaries, the root among them, are marked for
  /// paint: the next [flushPaint] repaints each, on its own or with one
  /// marked around it.
  int get dirtyBoundaries => _dirty.length;

  /// Lays the root out at the screen size when that is new, then the
  /// relayout boundaries marked since, outermost first; a boundary an
  /// ancestor laid out on the way is skipped. Then, the same way, those
  /// that layout callbacks marked meanwhile, until none is marked: what it
  /// paints next has all been laid out. Allocation-free once warmed up, like
  /// [flushPaint].
  void flushLayout(int w, int h) {
    _flushing = true;
    try {
      if (_layoutDirty && _root != null) {
        _root!.layout(BoxConstraints.tight(w, h));
        _layoutDirty = false;
      }
      final list = _layoutRoots;
      if (list.isNotEmpty) {
        _layoutRoots = _layingOut;
        _layingOut = list;
        if (list.length > 1) {
          list.sort(_byDepth);
        }
        for (var i = 0; i < list.length; i++) {
          final b = list[i];
          // still dirty, and not detached since it was marked
          if (b._needsLayout && identical(b.owner, this)) {
            b._relayout();
          }
        }
        list.clear();
        if (_layoutRoots.isNotEmpty) {
          _layOutMarkedMeanwhile();
        }
      }
      if (_relayoutNext.isNotEmpty) {
        _markRelayoutNext();
      }
    } finally {
      _flushing = false;
    }
    _throwFirst();
  }

  /// Lays out the relayout boundaries marked while [flushLayout] laid out
  /// others (by layout callbacks, [RenderObject.invokeLayoutCallback]), a
  /// pass at a time, until a pass marks none. When the flush has made
  /// [_layoutPasses] passes, what is marked waits for the next frame, and
  /// the boundary whose layout marked it last shows an error that says so.
  void _layOutMarkedMeanwhile() {
    RenderObject? marking;
    for (var pass = 2; _layoutRoots.isNotEmpty; pass++) {
      if (pass > _layoutPasses) {
        final m = marking!;
        final error = StateError(
          'layout does not settle: after $_layoutPasses passes, laying out '
          '${m.runtimeType} still marks relayout boundaries',
        );
        m
          .._errorShown = _shownUntilLayout
          ..markNeedsPaint()
          .._failed('$error', RenderPhase.layout, error, StackTrace.current);
        return;
      }
      final list = _layoutRoots;
      _layoutRoots = _layingOut;
      _layingOut = list;
      if (list.length > 1) {
        list.sort(_byDepth);
      }
      for (var i = 0; i < list.length; i++) {
        final b = list[i];
        if (b._needsLayout && identical(b.owner, this)) {
          final marked = _layoutRoots.length;
          b._relayout();
          if (_layoutRoots.length != marked) {
            marking = b;
          }
        }
      }
      list.clear();
    }
  }

  /// Marks for the next frame those laid out in this flush by intrinsic
  /// sizes a layout callback changed after ([RenderObject.
  /// invokeLayoutCallback]).
  void _markRelayoutNext() {
    final stale = _relayoutNext;
    for (var i = 0; i < stale.length; i++) {
      if (identical(stale[i].owner, this)) {
        stale[i].markNeedsLayout();
      }
    }
    stale.clear();
  }

  /// Repaints dirty boundaries, outermost first; boundaries inside a dirty
  /// boundary, or inside an object that shows an error, are covered by it.
  /// A boundary repaints the rows of the objects marked for paint in it
  /// ([RenderObject.markNeedsPaint]), as they are laid out now, and those
  /// of the boundaries inside it it covers: all of them when it was marked
  /// itself, laid out, or under a debug paint. First the objects
  /// [RenderObject.checkedBeforePaint] mark what they need repainted
  /// ([RenderObject.beforePaint]). Allocation-free once warmed up: the
  /// lists are reused and "covered" is a generation mark on the objects.
  void flushPaint(PaintContext ctx) {
    if (_dirty.isEmpty) {
      return;
    }
    if (_checkedBeforePaint.isNotEmpty) {
      _beforePaint();
    }
    final list = _dirty;
    _dirty = _painting;
    _painting = list;
    final gen = ++_paintGen;
    final debug = _debug;
    _flushing = true;
    _paintFlushing = true;
    try {
      _settleRows(list, gen, whole: debug != 0);
      if (list.length > 1) {
        list.sort(_byDepth);
        _gatherRows(list, gen);
      }
      _addWholes(list, gen);
      final rows = _rows;
      for (var i = 0; i < list.length; i++) {
        final b = list[i].._queued = false;
        // marked whole while this flush painted others: its rows were
        // settled before
        final markedSince = (b._paintMarks & _markedWhole) != 0;
        var top = 0;
        var bottom = b.height;
        if (!markedSince && b._slotIn == gen) {
          top = rows[2 * b._slot];
          bottom = rows[2 * b._slot + 1];
        }
        var covered = false;
        for (var p = b.parent; p != null; p = p.parent) {
          if (p._paintedIn == gen || p._errorShown != _shownNot) {
            covered = true;
            break;
          }
        }
        if (!covered && _aboveCount != 0 && debug == 0) {
          covered = _heldAbove(b, top, bottom);
        }
        if (covered) {
          if (markedSince) {
            // what covered it may have painted it before the mark: on the
            // next frame
            _addDirty(b);
          }
          continue;
        }
        b
          .._paintMarks &= ~_markedWhole
          .._paintedIn = gen;
        if (top < bottom || b._cutOffPainters != 0) {
          _repaint(ctx, b, top, bottom);
          if (top > 0 || bottom < b.height) {
            _forgetCut(b, top, bottom);
          }
        }
        while (_paintThrew) {
          // what threw may have left the canvas saved, moved or clipped:
          // all of it is painted again, what threw showing its error
          _paintThrew = false;
          b.invalidatePaintCache();
          _repaint(ctx, b, 0, b.height);
        }
        if (debug != 0) {
          _debugPaint(ctx, b, debug);
        }
      }
    } finally {
      _flushing = false;
      _paintFlushing = false;
      _paintThrew = false;
      for (var i = 0; i < _aboveCount; i++) {
        _above[i] = null;
      }
      _aboveCount = 0;
    }
    list.clear();
    ctx.canvas.reset();
    _throwFirst();
  }

  /// Calls [RenderObject.beforePaint] on the objects
  /// [RenderObject.checkedBeforePaint]: what they mark goes to the flush
  /// about to begin.
  void _beforePaint() {
    final checked = _checkedBeforePaint;
    for (var i = 0; i < checked.length; i++) {
      final o = checked[i];
      try {
        o.beforePaint();
      } on Object catch (error, stack) {
        o
          ..markNeedsPaint()
          .._failed('$error', RenderPhase.paint, error, stack)
          .._errorShown = _shownUntilPaint;
      }
    }
  }

  /// Gives each boundary in [list], the boundaries flushPaint [gen]
  /// repaints, its slot of [_rows] and the rows it repaints: all of them
  /// when it was marked itself, or when [whole]; otherwise the rows the
  /// objects marked in it cover, cut off where the objects above them cut
  /// them off. A boundary that holds a marked object but is not in [list]
  /// (it became one since) is added, to repaint all of it.
  void _settleRows(List<RenderObject> list, int gen, {required bool whole}) {
    final n = list.length;
    _slotsFor(n);
    var rows = _rows;
    for (var i = 0; i < n; i++) {
      final b = list[i];
      final all = whole || (b._paintMarks & _markedWhole) != 0;
      b
        .._slotIn = gen
        .._slot = i
        .._paintMarks &= ~_markedWhole;
      rows[2 * i] = 0;
      rows[2 * i + 1] = all ? b.height : 0;
    }
    final marked = _marked;
    final count = _markedCount;
    for (var i = 0; i < count; i++) {
      final o = marked[i]!;
      if (!identical(o.owner, this)) {
        continue;
      }
      // its rows in the object above it, up to its boundary or the root
      var top = 0;
      var bottom = o.height;
      var c = o;
      var inMarked = false;
      while (!c.isRepaintBoundary) {
        final p = c._parent;
        if (p == null) {
          break;
        }
        if ((p._paintMarks & _markedBelow) != 0) {
          // the rows of the one above hold its rows
          inMarked = true;
          break;
        }
        final dy = c.parentData.dy;
        top = top + dy < 0 ? 0 : top + dy;
        bottom = bottom + dy > p.height ? p.height : bottom + dy;
        c = p;
      }
      if (inMarked || top >= bottom) {
        continue;
      }
      if (c._slotIn != gen) {
        // not to be repainted, as far as this flush knew: all of it
        final s = list.length;
        list.add(c);
        _slotsFor(s + 1);
        rows = _rows;
        c
          .._queued = true
          .._slotIn = gen
          .._slot = s;
        rows[2 * s] = 0;
        rows[2 * s + 1] = c.height;
        continue;
      }
      _addRows(c._slot, top, bottom);
    }
    for (var i = 0; i < count; i++) {
      marked[i]!._paintMarks &= ~_markedBelow;
      marked[i] = null;
    }
    // what is marked while this flush paints is for the next one
    _markedCount = 0;
  }

  /// Notes that [o] was marked for paint below its boundary.
  void _markBelow(RenderObject o) {
    var marked = _marked;
    final n = _markedCount;
    if (n == marked.length) {
      marked = _marked = List<RenderObject?>.filled(2 * n, null)
        ..setRange(0, n, marked);
    }
    marked[n] = o;
    _markedCount = n + 1;
  }

  /// Adds the rows each boundary in [list], sorted outermost first, repaints
  /// to those of the nearest boundary above it in [list], cut off where the
  /// objects between them cut them off: a boundary that covers another
  /// repaints what that one would have. The innermost go first, so that
  /// what a boundary passes on holds what was passed to it.
  void _gatherRows(List<RenderObject> list, int gen) {
    final rows = _rows;
    for (var i = list.length - 1; i > 0; i--) {
      final b = list[i];
      if (b._slotIn != gen) {
        continue;
      }
      var top = rows[2 * b._slot];
      var bottom = rows[2 * b._slot + 1];
      var c = b;
      for (var p = b._parent; p != null && top < bottom; p = p._parent) {
        final dy = c.parentData.dy;
        top = top + dy < 0 ? 0 : top + dy;
        bottom = bottom + dy > p.height ? p.height : bottom + dy;
        if (p._slotIn == gen) {
          if (top < bottom) {
            _addRows(p._slot, top, bottom);
          }
          break;
        }
        c = p;
      }
    }
  }

  /// Adds the rows of each object repainted whole with its boundaries
  /// ([RenderObject.repaintedWhole]) to those of each boundary above it
  /// that flushPaint [gen] repaints any rows of: a walk down from each
  /// boundary in [list] that has such objects inside it, into those parts
  /// of it alone.
  void _addWholes(List<RenderObject> list, int gen) {
    final rows = _rows;
    for (var i = 0; i < list.length; i++) {
      final b = list[i];
      if (b._wholesBelow == 0 || b._slotIn != gen) {
        continue;
      }
      final slot = b._slot;
      if (rows[2 * slot] >= rows[2 * slot + 1]) {
        continue;
      }
      _wholeSlot = slot;
      if (b._repaintedWhole) {
        _addWholeRows(b, 0, 0, b.height);
      }
      if (b._wholesBelow > (b._repaintedWhole ? 1 : 0)) {
        _wholeTop = 0;
        _wholeBottom = b.height;
        _wholeAt = 0;
        b.visitChildren(_visitWhole);
      }
    }
  }

  /// [_addWholes] at [c], a child of the object it visits the children of.
  void _addWholesIn(RenderObject c) {
    if (c._wholesBelow == 0) {
      return;
    }
    final y = _wholeAt + c.parentData.dy;
    final end = y + c.height;
    final top = y > _wholeTop ? y : _wholeTop;
    final bottom = end < _wholeBottom ? end : _wholeBottom;
    if (top >= bottom) {
      // cut off: nothing inside it shows either
      return;
    }
    if (c._repaintedWhole) {
      _addWholeRows(c, y, top, bottom);
    }
    if (c._wholesBelow > (c._repaintedWhole ? 1 : 0)) {
      final at = _wholeAt;
      final t = _wholeTop;
      final bt = _wholeBottom;
      _wholeAt = y;
      _wholeTop = top;
      _wholeBottom = bottom;
      c.visitChildren(_visitWhole);
      _wholeAt = at;
      _wholeTop = t;
      _wholeBottom = bt;
    }
  }

  /// Adds the rows [o], repainted whole with its boundaries, at row [y] of
  /// the boundary [_addWholes] walks, has it repaint ([RenderObject.
  /// wholeRows]) to those of the boundary, cut off at [top] and [bottom].
  /// What it throws, it shows, with all of its rows.
  void _addWholeRows(RenderObject o, int y, int top, int bottom) {
    final rows = _wholeRows;
    rows[0] = 0;
    rows[1] = o.height;
    try {
      o.wholeRows(rows);
    } on Object catch (error, stack) {
      rows[0] = 0;
      rows[1] = o.height;
      o._paintFailed(error, stack);
    }
    final t = y + rows[0] > top ? y + rows[0] : top;
    final b = y + rows[1] < bottom ? y + rows[1] : bottom;
    if (t < b) {
      _addRows(_wholeSlot, t, b);
    }
  }

  /// Adds rows [top] to [bottom] to those of [slot].
  void _addRows(int slot, int top, int bottom) {
    final rows = _rows;
    final t = rows[2 * slot];
    final b = rows[2 * slot + 1];
    if (t >= b) {
      rows[2 * slot] = top;
      rows[2 * slot + 1] = bottom;
    } else {
      if (top < t) {
        rows[2 * slot] = top;
      }
      if (bottom > b) {
        rows[2 * slot + 1] = bottom;
      }
    }
  }

  /// Makes [_rows] hold [n] slots, those it held kept.
  void _slotsFor(int n) {
    if (_rows.length < 2 * n) {
      var len = _rows.length;
      while (len < 2 * n) {
        len *= 2;
      }
      _rows = Int32List(len)..setRange(0, _rows.length, _rows);
    }
  }

  /// Empties [result] and adds what the tree has at [x], [y] of the root
  /// ([RenderObject.hitTest]) as it was laid out last: the deepest object
  /// first, the root last. Allocates nothing once [result] has held as
  /// many objects as the tree is deep.
  void hitTest(HitTestResult result, int x, int y) {
    result.reset();
    _root?.hitTest(result, x, y);
  }

  /// Paints rows [top] to [bottom] of [b], a dirty boundary or the root,
  /// on its own; those rows of the boundary above it, or of the root,
  /// when what covers it has a wide glyph its sides cut there.
  void _repaint(PaintContext ctx, RenderObject b, int top, int bottom) {
    final canvas = ctx.canvas;
    _enter(canvas, b);
    if (top > 0 || bottom < b.height) {
      canvas.clipRect(0, top, b.width, bottom - top);
    }
    final overlapped = _overlapped(b);
    if (overlapped) {
      // its cells hold what covers it too: they can't be moved as its
      // own (a log's scroll)
      b.invalidatePaintCache();
      if (_cutsWide(canvas)) {
        // painted again over its cells only, the glyph would be cut in
        // two: the rows are painted across as a whole paint paints them
        _repaintAbove(ctx, b, top, bottom);
        return;
      }
    }
    if (!b.isRepaintBoundary) {
      // the root repaints on its own without promising to paint every
      // cell: start from blank cells
      canvas.fill(0, 0, b.width, b.height, _blankPenOf(ctx));
    }
    if (b.keepsUnderlay && b.putsUnderlayBack && b.isRepaintBoundary) {
      // the rows it repaints, as its parent left them, to paint over
      b._restoreUnderlay(canvas);
    }
    _alone = b;
    b._paint(ctx);
    _alone = null;
    if (overlapped) {
      _paintOver(canvas, ctx, b);
    }
  }

  /// Throws what the flush that has just ended was to throw, if anything.
  void _throwFirst() {
    final thrown = _thrown;
    if (thrown != null) {
      _thrown = null;
      Error.throwWithStackTrace(thrown.$1, thrown.$2);
    }
  }

  static int _byDepth(RenderObject a, RenderObject b) => a.depth - b.depth;

  /// Whether a wide glyph crosses a side of the cells [canvas] is clipped
  /// to, on any of their rows: one column of it inside them, the other
  /// outside.
  static bool _cutsWide(Canvas canvas) {
    final (x0, y0, x1, y1) = canvas.clipBounds;
    if (x0 >= x1) {
      return false;
    }
    final surface = canvas.surface;
    final cells = surface.cells;
    final w = surface.width;
    for (var y = y0; y < y1; y++) {
      final row = y * w;
      if ((x0 > 0 && (cells[row + x0] & kCont) != 0) ||
          (x1 < w && (cells[row + x1 - 1] & kWide) != 0)) {
        return true;
      }
    }
    return false;
  }

  /// Paints rows [from] to [to] of [b], which has a wide glyph of what
  /// covers it cut by its sides there, as rows of the nearest boundary
  /// above it, or of the root: all across, as they would be in a whole
  /// paint of it, which keeps the glyph whole.
  void _repaintAbove(PaintContext ctx, RenderObject b, int from, int to) {
    var top = from;
    var bottom = to;
    var c = b;
    var p = b.parent!;
    while (true) {
      final dy = c.parentData.dy;
      top = top + dy < 0 ? 0 : top + dy;
      bottom = bottom + dy > p.height ? p.height : bottom + dy;
      final up = p.parent;
      if (p.isRepaintBoundary || up == null) {
        break;
      }
      c = p;
      p = up;
    }
    if (top >= bottom) {
      return;
    }
    _noteAbove(p, top, bottom);
    _repaint(ctx, p, top, bottom);
    if (top > 0 || bottom < p.height) {
      _forgetCut(p, top, bottom);
    }
  }

  /// Notes that rows [top] to [bottom] of [p] are repainted in place of a
  /// boundary inside it ([_repaintAbove]): a boundary inside [p] that this
  /// flush has yet to paint, whose rows they hold, is not painted again.
  void _noteAbove(RenderObject p, int top, int bottom) {
    final n = _aboveCount;
    if (n == _above.length) {
      _above = List<RenderObject?>.filled(2 * n, null)..setRange(0, n, _above);
      _aboveRows = Int32List(4 * n)..setRange(0, 2 * n, _aboveRows);
    }
    _above[n] = p;
    _aboveRows[2 * n] = top;
    _aboveRows[2 * n + 1] = bottom;
    _aboveCount = n + 1;
  }

  /// Whether rows [top] to [bottom] of [b] are held by rows this flush
  /// repainted of a boundary above it in place of another ([_noteAbove]),
  /// cut off where the objects between them cut them off.
  bool _heldAbove(RenderObject b, int top, int bottom) {
    for (var k = 0; k < _aboveCount; k++) {
      final p = _above[k]!;
      var t = top;
      var bt = bottom;
      var c = b;
      for (var q = b._parent; q != null; q = q._parent) {
        final dy = c.parentData.dy;
        t = t + dy < 0 ? 0 : t + dy;
        bt = bt + dy > q.height ? q.height : bt + dy;
        if (identical(q, p)) {
          // none of it shows, or what shows was repainted
          if (t >= bt ||
              (t >= _aboveRows[2 * k] && bt <= _aboveRows[2 * k + 1])) {
            return true;
          }
          break;
        }
        c = q;
      }
    }
    return false;
  }

  /// Whether any ancestor of [b] paints over its cells
  /// ([RenderObject.paintsOver]).
  static bool _overlapped(RenderObject b) {
    var x = 0;
    var y = 0;
    var child = b;
    for (var p = b.parent; p != null; p = p.parent) {
      x += child.parentData.dx;
      y += child.parentData.dy;
      if (p._paintsOver(child, x, y, b.width, b.height)) {
        return true;
      }
      child = p;
    }
    return false;
  }

  /// Has each ancestor of [b], which has just repainted on its own, paint
  /// again what it paints over [b]'s cells ([RenderObject.paintOver]), the
  /// nearest first, as a whole paint would; the canvas stays clipped as
  /// [_enter] left it.
  static void _paintOver(Canvas canvas, PaintContext ctx, RenderObject b) {
    var x = 0;
    var y = 0;
    var child = b;
    for (var p = b.parent; p != null; p = p.parent) {
      final at = child.parentData;
      x += at.dx;
      y += at.dy;
      canvas.translate(-at.dx, -at.dy);
      p._paintOverChild(ctx, child, x, y, b.width, b.height);
      child = p;
    }
  }

  /// Sets [canvas] up for painting [b] on its own: clipped by [b] and every
  /// ancestor (a child they cut off stays cut off, as when the parent paints
  /// it), origin at [b].
  static void _enter(Canvas canvas, RenderObject b) {
    var gx = 0;
    var gy = 0;
    for (RenderObject? o = b; o != null; o = o.parent) {
      gx += o.parentData.dx;
      gy += o.parentData.dy;
    }
    canvas.reset();
    var ax = gx;
    var ay = gy;
    for (RenderObject? o = b; o != null; o = o.parent) {
      canvas.clipRect(ax, ay, o.width, o.height);
      ax -= o.parentData.dx;
      ay -= o.parentData.dy;
    }
    canvas.translate(gx, gy);
  }

  // the blank pen's id, looked up once per style table
  StyleTable? _blankPenTable;
  var _blankPen = 0;

  int _blankPenOf(PaintContext ctx) {
    final styles = ctx.canvas.styles;
    if (!identical(styles, _blankPenTable)) {
      _blankPenTable = styles;
      _blankPen = styles.pen(
        const Pen(fg: Color.defaultColor, bg: Color.defaultColor),
      );
    }
    return _blankPen;
  }

  /// Tints what [b], a boundary or the root, has just repainted, as the
  /// debug paints on in [debug] say.
  void _debugPaint(PaintContext ctx, RenderObject b, int debug) {
    final canvas = ctx.canvas;
    final surface = canvas.surface;
    final styles = canvas.styles;
    _enter(canvas, b);
    final (x0, y0, x1, y1) = canvas.clipBounds;
    if ((debug & _debugRainbow) != 0) {
      final tint = styles.pen(
        Pen(bg: _debugTints[_rainbowAt], bgAlpha: _rainbowAlpha),
      );
      _rainbowAt = (_rainbowAt + 1) % _debugTints.length;
      if (x0 < x1) {
        _tint(surface, styles, tint, x0, y0, x1, y1);
      }
    }
    if ((debug & _debugRelayout) != 0) {
      final (x, y) = b.globalOffset;
      _outline(surface, styles, b, x, y, x0, y0, x1, y1);
    }
    // what it keeps from this paint would be tinted twice: whatever in it
    // repaints on its own next repaints all of its cells
    _forgetPaint(b);
  }

  /// Outlines [o], at [x], [y] on [surface], when it was laid out since the
  /// relayout highlight last looked, then the objects inside it; [cx0],
  /// [cy0], [cx1], [cy1] is the clip its ancestors cut it off at. Whatever
  /// was laid out counts as seen, painted or cut off.
  void _outline(
    Surface surface,
    StyleTable styles,
    RenderObject o,
    int x,
    int y,
    int cx0,
    int cy0,
    int cx1,
    int cy1,
  ) {
    // cut off at its own bounds too, as its paint is
    final right = x + o.width;
    final bottom = y + o.height;
    final x0 = x > cx0 ? x : cx0;
    final y0 = y > cy0 ? y : cy0;
    final x1 = right < cx1 ? right : cx1;
    final y1 = bottom < cy1 ? bottom : cy1;
    if (o._laidOut) {
      o._laidOut = false;
      if (_outlinedIn != _paintGen) {
        // the first outline of this frame: far round the wheel from the
        // last one's
        _outlinedIn = _paintGen;
        _relayoutAt = (_relayoutAt + 5) % _debugTints.length;
        _outlinePen = styles.pen(
          Pen(bg: _debugTints[_relayoutAt], bgAlpha: _relayoutAlpha),
        );
      }
      final tint = _outlinePen;
      if (x0 < x1 && y0 < y1) {
        if (y0 == y) {
          _tint(surface, styles, tint, x0, y0, x1, y0 + 1);
        }
        if (y1 == bottom && bottom - 1 > y) {
          _tint(surface, styles, tint, x0, y1 - 1, x1, y1);
        }
        // the rows between the top and bottom edges
        final top = y0 > y ? y0 : y + 1;
        final end = y1 < bottom ? y1 : bottom - 1;
        if (top < end) {
          if (o.width <= 2) {
            _tint(surface, styles, tint, x0, top, x1, end);
          } else {
            if (x0 == x) {
              _tint(surface, styles, tint, x0, top, x0 + 1, end);
            }
            if (x1 == right) {
              _tint(surface, styles, tint, x1 - 1, top, x1, end);
            }
          }
        }
      }
    }
    o.visitChildren((c) {
      final at = c.parentData;
      _outline(surface, styles, c, x + at.dx, y + at.dy, x0, y0, x1, y1);
    });
  }
}
