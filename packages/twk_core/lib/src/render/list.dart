part of 'render.dart';

// ------------------------------------------------------------------ list --

/// What a [RenderList] keeps on each of its items: the item's index,
/// besides its offset in the list's window.
final class ListParentData extends ParentData with ContainerParentDataMixin {
  /// The data of an item not laid out yet: index 0, at the origin.
  ListParentData();

  /// The index of the item.
  var index = 0;

  // the row it was at when the list last painted, and whether the list
  // painted it as it is laid out now
  var _paintedDy = 0;
  var _painted = false;

  /// The index of the item.
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add('index', index);
  }
}

/// What builds the items of a [RenderList] as they come into its window
/// and drops them as they leave it (a widget layer's element). The list
/// calls it in its layout callbacks ([RenderObject.invokeLayoutCallback]).
abstract interface class ListItemManager {
  /// Builds item [index] and puts its render object into the list
  /// ([RenderList.insertItem]).
  void buildItem(int index);

  /// Takes [item], one of the list's, out of it
  /// ([ContainerRenderObjectMixin.remove]).
  void dropItem(RenderObject item);
}

/// A list of [itemCount] items one below another, each as wide as the list
/// and as tall as it likes, or [itemExtent] rows: only those in its window
/// and [cacheExtent] rows past either edge of it exist, which [items]
/// builds as they come into the window and drops as they leave it, in the
/// list's layout. Near either end, the items up to a window past the edge
/// are built.
///
/// The height of an item is measured when it is laid out, and remembered
/// until the list's width changes; the items never laid out are taken to
/// be as tall as those measured are on average. So [scrollOffset], the
/// rows of the items above the window, and the extent of the content,
/// which [onMetrics] gets each layout with the window's, are estimates
/// where the list has not been, which change as it measures items.
///
/// It scrolls from the item at the top of its window. Setting
/// [scrollOffset] moves the window in the next layout: by at most a
/// window's height, exactly, the items it passes laid out; further, to
/// where the estimate puts the offset; to 0, or to the end of the content
/// as the last layout had it, to the start or the end. [jumpToIndex] and
/// [showIndex] move it to an item. While [stickToBottom] is set and the
/// window shows the end, it keeps showing the end as items are added or
/// grow; such a list starts at the end.
///
/// It takes all the room it is given, which must be bounded, and is its own
/// repaint boundary, filled with [background] under the items, which needs
/// an opaque background. When its window moved since it last painted, by
/// less than its height, all of it on the surface and nothing painted over
/// it, it shifts its rows on the surface and declares the scroll
/// ([Surface.scrollRect]), so that the terminal scrolls in hardware; then
/// it paints the rows the scroll exposed and those of the items built,
/// laid out again or moved otherwise since, and the repaint boundaries
/// inside it marked for paint repaint on their own. Anything inside marked
/// for paint other than by its layout has it paint all of it.
///
/// A thousand lines, of which the list builds only those it shows:
///
/// ```dart
/// final class Lines implements ListItemManager {
///   late final RenderList list;
///
///   @override
///   void buildItem(int i) =>
///       list.insertItem(RenderParagraph([('Line $i', const Pen())]), i);
///
///   @override
///   void dropItem(RenderObject item) => list.remove(item);
/// }
///
/// void main() {
///   final lines = Lines();
///   lines.list = RenderList(items: lines, itemCount: 1000, itemExtent: 1)
///     ..jumpToIndex(500);
/// }
/// ```
///
/// See also:
///
///  * [RenderViewport], a window onto one child laid out whole.
///  * [RenderLog], lines of text kept at their end as they are added.
final class RenderList extends RenderObject
    with ContainerRenderObjectMixin<ListParentData> {
  /// A list of [itemCount] items built by [items], 0 unless given, each
  /// [itemExtent] rows tall or as tall as it likes; [cacheExtent] rows, 3
  /// unless given, built past each edge; [scrollOffset] rows of the content
  /// above the window. [background] is the terminal's own colors unless
  /// given.
  RenderList({
    required this.items,
    this._itemCount = 0,
    this._itemExtent,
    this._cacheExtent = 3,
    this._stickToBottom = false,
    this._background = _defaultColors,
    int scrollOffset = 0,
    this.onMetrics,
  }) : assert(_itemCount >= 0, 'a count of 0 items or more'),
       assert((_itemExtent ?? 1) > 0, 'an item extent of 1 row or more'),
       assert(_cacheExtent >= 0, 'a cache of 0 rows or more'),
       assert(scrollOffset >= 0, 'an offset of 0 rows or more'),
       _stuck = _stickToBottom,
       _target = scrollOffset > 0 ? scrollOffset : null;

  /// Builds the items as they come into the window, and drops them.
  ListItemManager items;

  int _itemCount;

  /// How many items the list has, 0 or more; a new count lays it out
  /// again.
  int get itemCount => _itemCount;
  set itemCount(int n) {
    assert(n >= 0, 'a count of 0 items or more');
    if (n != _itemCount) {
      _itemCount = n;
      markNeedsLayout();
    }
  }

  int? _itemExtent;

  /// The rows of every item, laid out that tall, 1 or more; null for items
  /// as tall as they like. A new one forgets the heights measured and lays
  /// the list out again.
  int? get itemExtent => _itemExtent;
  set itemExtent(int? e) {
    assert((e ?? 1) > 0, 'an item extent of 1 row or more');
    if (e != _itemExtent) {
      _itemExtent = e;
      _forget(0);
      markNeedsLayout();
    }
  }

  int _cacheExtent;

  /// The rows past either edge of the window whose items are built too, 0
  /// or more.
  int get cacheExtent => _cacheExtent;
  set cacheExtent(int rows) {
    assert(rows >= 0, 'a cache of 0 rows or more');
    if (rows != _cacheExtent) {
      _cacheExtent = rows;
      markNeedsLayout();
    }
  }

  bool _stickToBottom;

  /// Whether the list keeps showing the end, as items are added or grow,
  /// while the window shows it; off by default. A list made with it on
  /// starts at the end.
  bool get stickToBottom => _stickToBottom;
  set stickToBottom(bool on) {
    if (on != _stickToBottom) {
      _stickToBottom = on;
      _stuck = on && _atEnd;
    }
  }

  Pen _background;

  /// What the list is filled with under the items, with an opaque
  /// background; a new one repaints all of it.
  Pen get background => _background;
  set background(Pen p) {
    if (p != _background) {
      _background = p;
      _penIn = null;
      _fullRepaint = true;
      markNeedsPaint();
    }
  }

  /// Called by each layout with the window's extent, the content's (partly
  /// estimated) and the offset the window settled at, which may differ
  /// from the one set: the estimate changed, it went to an item or to the
  /// end.
  void Function(int viewport, int content, int offset)? onMetrics;

  // the item at the top of the window, and its rows above the window
  var _anchor = 0;
  var _anchorOffset = 0;

  // a move asked for since the last layout: to an offset, or to an item,
  // at the top of the window or where it shows with the least move
  int? _target;
  int? _targetIndex;
  var _indexAtTop = false;

  // what the last layout settled at
  var _offset = 0;
  var _content = 0;
  int _maxOffset = BoxConstraints.unbounded;
  var _atEnd = false;
  var _stuck = false;

  // the items' extents as measured at _measuredAt columns, plus one (0 for
  // an item not measured); their sum and how many there are, and the same
  // of the items before _anchor; the item count they are kept for
  var _extents = Int32List(0);
  var _measuredAt = -1;
  var _sum = 0;
  var _known = 0;
  var _sumBefore = 0;
  var _knownBefore = 0;
  var _counted = 0;

  // what the items are laid out within; an item moved to another index
  // since the last layout; the list is laying its items out
  BoxConstraints? _itemConstraints;
  var _unsorted = false;
  var _inLayout = false;

  // the id of the background's pen in _penIn
  StyleTable? _penIn;
  var _penId = 0;

  // what is on the surface from the last paint: its size, and the row the
  // items ended at; the rows to paint, reused
  var _paintedWidth = 0;
  var _paintedHeight = 0;
  var _paintedEnd = 0;
  var _fullRepaint = true;
  var _dirtyRows = Uint8List(0);

  /// The rows of the content above the window: the offset set since the
  /// last layout, or the one it settled at.
  int get scrollOffset => _target ?? _offset;

  /// Moves the window to [offset] rows of the content in the next layout,
  /// within 0 and the end, in place of a move to an item asked for since
  /// the last layout, even to the offset it is at; the items move by as
  /// much at once, so that hit tests see them where they will be.
  set scrollOffset(int offset) {
    final from = scrollOffset;
    final to = offset < 0 ? 0 : (offset > _maxOffset ? _maxOffset : offset);
    if (to == from && _targetIndex == null) {
      return;
    }
    _target = to;
    _targetIndex = null;
    for (var c = firstChild; c != null;) {
      final at = c.parentData as ListParentData..dy -= to - from;
      c = at.nextSibling;
    }
    markNeedsLayout();
  }

  /// Moves the window in the next layout to show item [index] at its top.
  void jumpToIndex(int index) => _toIndex(index, atTop: true);

  /// Moves the window in the next layout the least that shows item
  /// [index]: its top when it is taller than the window.
  void showIndex(int index) => _toIndex(index, atTop: false);

  void _toIndex(int index, {required bool atTop}) {
    assert(index >= 0, 'an index of 0 or more');
    _targetIndex = index;
    _indexAtTop = atTop;
    _target = null;
    markNeedsLayout();
  }

  /// Puts [item], a render object of no parent, among the items as item
  /// [index], in order: what [items] does as it builds one.
  void insertItem(RenderObject item, int index) {
    RenderObject? after;
    for (var c = lastChild; c != null;) {
      final at = c.parentData as ListParentData;
      if (at.index < index) {
        after = c;
        break;
      }
      c = at.previousSibling;
    }
    insert(item, after: after);
    (item.parentData as ListParentData)
      ..index = index
      .._painted = false;
  }

  /// Makes [item], one of the items, item [index]; the next layout puts it
  /// in order.
  void moveItem(RenderObject item, int index) {
    assert(identical(item.parent, this), '$item is not an item of $this');
    final at = item.parentData as ListParentData;
    if (at.index != index) {
      at
        ..index = index
        .._painted = false;
      _unsorted = true;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! ListParentData) {
      child.parentData = ListParentData();
    }
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  /// Opaque: it fills all of its cells.
  @override
  HitTestBehavior get hitTestBehavior => HitTestBehavior.opaque;

  /// The items, the offset, the item extent and the cache where they are
  /// not the defaults, whether it sticks to the bottom, and the background.
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add('itemCount', _itemCount)
      ..add('scrollOffset', scrollOffset, defaultValue: 0)
      ..add('itemExtent', _itemExtent, defaultValue: null)
      ..add('cacheExtent', _cacheExtent, defaultValue: 3);
    if (_stickToBottom) {
      properties.addTag('stickToBottom');
    }
    properties.add('background', _background, defaultValue: _defaultColors);
  }

  // what its own layout marks inside it is told by the items it laid out
  @override
  void invalidatePaintCache() {
    if (!_inLayout) {
      _fullRepaint = true;
    }
  }

  @override
  void performLayout(BoxConstraints c) {
    if (c.maxW >= BoxConstraints.unbounded ||
        c.maxH >= BoxConstraints.unbounded) {
      throw StateError(
        'a list takes all the room it is given, which must be bounded, not '
        '${describeConstraints(c)}',
      );
    }
    width = c.maxW;
    height = c.maxH;
    assert(_debugReportNoRows(), 'reports a list given no rows');
    // once more when onMetrics moved it; a third time on the next frame
    for (var pass = 0; pass < 2; pass++) {
      _inLayout = true;
      try {
        _layOutItems();
      } finally {
        _inLayout = false;
      }
      onMetrics?.call(height, _content, _offset);
      if (_target == null && _targetIndex == null) {
        return;
      }
    }
    final o = owner;
    if (o != null && o._flushing) {
      o._relayoutNext.add(this);
    }
  }

  void _layOutItems() {
    final w = width;
    final h = height;
    final count = _itemCount;
    final fixed = _itemExtent;
    final minH = fixed ?? 0;
    final maxH = fixed ?? BoxConstraints.unbounded;
    var ic = _itemConstraints;
    if (ic == null || ic.maxW != w || ic.minH != minH || ic.maxH != maxH) {
      ic = _itemConstraints = BoxConstraints(w, w, minH, maxH);
    }
    if (w != _measuredAt) {
      _measuredAt = w;
      _forget(0);
    }
    if (count < _counted) {
      _forget(count);
    }
    _counted = count;
    if (_unsorted) {
      _sort();
    }
    final target = _target;
    final index = _targetIndex;
    _target = null;
    _targetIndex = null;
    if (count == 0) {
      _dropOutside(0, -1);
      _moveAnchor(0);
      _anchorOffset = 0;
      _offset = 0;
      _content = 0;
      _maxOffset = 0;
      _atEnd = true;
      _stuck = _stickToBottom;
      return;
    }
    if (_anchor >= count) {
      // the items it showed are gone: the last one is at the top, which the
      // fill below takes to the end
      _moveAnchor(count - 1);
      _anchorOffset = 0;
    }
    var toEnd = false;
    if (index != null) {
      _showItem(index < count ? index : count - 1, ic, h);
    } else if (target != null) {
      if (target <= 0) {
        _moveAnchor(0);
        _anchorOffset = 0;
      } else if (target >= _maxOffset) {
        toEnd = true;
      } else if ((target - _offset).abs() <= h) {
        _walk(target - _offset, count, ic);
      } else {
        _seek(target, count);
      }
    } else if (_stuck) {
      toEnd = true;
    }
    if (toEnd) {
      _alignBottom(count - 1, ic, h);
    }
    _fill(count, ic, h);
  }

  /// Fills the window from the item at its top, with the cache past
  /// either edge of it, places the items and takes the measure of where it
  /// settled; drops the items outside.
  void _fill(int count, BoxConstraints ic, int h) {
    final e = _itemAt(_anchor, ic);
    if (_anchorOffset >= e) {
      _anchorOffset = e > 0 ? e - 1 : 0;
    }
    // the items in the window; the end in it with rows left below: as far
    // down as the items above allow
    var y = e - _anchorOffset;
    var i = _anchor + 1;
    while (i < count && y < h) {
      y += _itemAt(i++, ic);
    }
    if (y < h && (_anchor > 0 || _anchorOffset > 0)) {
      y = _alignBottom(count - 1, ic, h);
    }
    final offset = _anchorStart + _anchorOffset;
    final near = h > _cacheExtent ? h : _cacheExtent;
    // past the bottom: the cache, or a window when the end is a window
    // away or less, so that a move of a window stops at the end exactly
    final below = _contentExtent - offset - h <= h ? near : _cacheExtent;
    while (i < count && y < h + below) {
      y += _itemAt(i++, ic);
    }
    // past the top likewise
    final above = offset <= h ? near : _cacheExtent;
    var top = -_anchorOffset;
    var j = _anchor - 1;
    while (j >= 0 && top > -above) {
      top -= _itemAt(j--, ic);
    }
    _dropOutside(j + 1, i - 1);
    for (var c = firstChild; c != null;) {
      final at = c.parentData as ListParentData
        ..dx = 0
        ..dy = top;
      top += c.height;
      c = at.nextSibling;
    }
    _offset = _anchorStart + _anchorOffset;
    _content = _contentExtent;
    _maxOffset = _content - h > 0 ? _content - h : 0;
    _atEnd = _offset >= _maxOffset;
    _stuck = _stickToBottom && _atEnd;
  }

  /// Moves the window [delta] rows down (up when negative), the items it
  /// passes laid out, up to the first item or the last.
  void _walk(int delta, int count, BoxConstraints ic) {
    var rows = _anchorOffset + delta;
    if (delta > 0) {
      for (var e = _itemAt(_anchor, ic); rows >= e && _anchor < count - 1;) {
        rows -= e;
        _moveAnchor(_anchor + 1);
        e = _itemAt(_anchor, ic);
      }
    } else {
      while (rows < 0 && _anchor > 0) {
        _moveAnchor(_anchor - 1);
        rows += _itemAt(_anchor, ic);
      }
    }
    _anchorOffset = rows < 0 ? 0 : rows;
  }

  /// Moves the window to [offset] as the estimate has it, building nothing.
  void _seek(int offset, int count) {
    if (_anchorStart <= offset) {
      while (_anchor < count - 1) {
        _moveAnchor(_anchor + 1);
        if (_anchorStart > offset) {
          _moveAnchor(_anchor - 1);
          break;
        }
      }
    } else {
      while (_anchor > 0 && _anchorStart > offset) {
        _moveAnchor(_anchor - 1);
      }
    }
    _anchorOffset = offset - _anchorStart;
  }

  /// Puts the bottom of item [last] at the bottom of the window, or item 0
  /// at the top when the items up to [last] are not as tall as the window;
  /// returns the row the items up to [last] end at.
  int _alignBottom(int last, BoxConstraints ic, int h) {
    var bottom = h;
    for (var i = last; i >= 0; i--) {
      final e = _itemAt(i, ic);
      if (e >= bottom) {
        _moveAnchor(i);
        _anchorOffset = e - bottom;
        return h;
      }
      bottom -= e;
    }
    _moveAnchor(0);
    _anchorOffset = 0;
    return h - bottom;
  }

  /// Moves the window to item [index]: to its top when asked, or when it
  /// is above the window or taller than it; to its bottom when it is below.
  void _showItem(int index, BoxConstraints ic, int h) {
    if (!_indexAtTop &&
        (index > _anchor || (index == _anchor && _anchorOffset == 0))) {
      // the rows down to its top, as far as the window reaches
      var y = -_anchorOffset;
      var i = _anchor;
      while (i < index && y < h) {
        y += _itemAt(i++, ic);
      }
      final e = _itemAt(index, ic);
      if (i == index && y + e <= h) {
        return;
      }
      if (e < h) {
        _alignBottom(index, ic, h);
        return;
      }
    }
    _moveAnchor(index);
    _anchorOffset = 0;
  }

  /// Item [index] laid out, built first when the list has no such item;
  /// returns its height.
  int _itemAt(int index, BoxConstraints ic) {
    final child = _childAt(index) ?? _build(index);
    if (child == null) {
      return 0;
    }
    if (child._needsLayout || child._constraints != ic) {
      (child.parentData as ListParentData)._painted = false;
    }
    child.layout(ic, parentUsesSize: true);
    _measure(index, child.height);
    return child.height;
  }

  /// Has [items] build item [index]; returns it, if it did. Apart from
  /// [_itemAt], which then makes no closure, nor a context for one, for an
  /// item the list has.
  RenderObject? _build(int index) {
    invokeLayoutCallback(() => items.buildItem(index));
    return _childAt(index);
  }

  /// The item [index], if the list has it.
  RenderObject? _childAt(int index) {
    final first = firstChild;
    if (first == null) {
      return null;
    }
    final last = lastChild!;
    final firstIndex = (first.parentData as ListParentData).index;
    final lastIndex = (last.parentData as ListParentData).index;
    if (!_unsorted && (index < firstIndex || index > lastIndex)) {
      // past either end, as an item about to be built is: no walk to learn
      return null;
    }
    final fromEnd = lastIndex - index < index - firstIndex;
    for (RenderObject? c = fromEnd ? last : first; c != null;) {
      final at = c.parentData as ListParentData;
      if (at.index == index) {
        return c;
      }
      c = fromEnd ? at.previousSibling : at.nextSibling;
    }
    return null;
  }

  /// Has [items] drop the items before [first] and after [last].
  void _dropOutside(int first, int last) {
    for (var c = firstChild; c != null;) {
      final at = c.parentData as ListParentData;
      final next = at.nextSibling;
      if (at.index < first || at.index > last) {
        _drop(c);
      }
      c = next;
    }
  }

  /// Has [items] drop [item]. Apart from [_dropOutside], which then makes
  /// no context for its closure when it drops nothing.
  void _drop(RenderObject item) {
    invokeLayoutCallback(() => items.dropItem(item));
    if (identical(item.parent, this)) {
      remove(item);
    }
  }

  /// Puts the items back in the order of their indices.
  void _sort() {
    _unsorted = false;
    for (var c = firstChild; c != null;) {
      final at = c.parentData as ListParentData;
      final next = at.nextSibling;
      var after = at.previousSibling;
      while (after != null &&
          (after.parentData as ListParentData).index > at.index) {
        after = (after.parentData as ListParentData).previousSibling;
      }
      if (!identical(after, at.previousSibling)) {
        move(c, after: after);
      }
      c = next;
    }
  }

  // ------------------------------------------------- measures and estimates

  /// The rows of [n] items not measured.
  int _est(int n) {
    final fixed = _itemExtent;
    if (fixed != null) {
      return n * fixed;
    }
    final k = _known;
    return k == 0 ? n : (n * _sum + k ~/ 2) ~/ k;
  }

  /// The rows of the content above item [_anchor].
  int get _anchorStart => _sumBefore + _est(_anchor - _knownBefore);

  /// The rows of the content.
  int get _contentExtent => _sum + _est(_itemCount - _known);

  var _noRowsReported = false;

  /// Logs a warning the first time the list is given no rows with items
  /// to show, which then shows none of them.
  bool _debugReportNoRows() {
    if (height == 0 && width > 0 && _itemCount > 0 && !_noRowsReported) {
      _noRowsReported = true;
      _warn(
        'A RenderList of $_itemCount items was given 0 rows and shows none '
        'of them: in a Column the children beside it took every row (put '
        'it in an Expanded); inline, a list asks for no rows (give it a '
        'height with a SizedBox).',
      );
    }
    return true;
  }

  /// Makes item [index] the one at the top, keeping the measures of the
  /// items above it.
  void _moveAnchor(int index) {
    final e = _extents;
    final n = e.length;
    if (index > _anchor) {
      for (var i = _anchor; i < index && i < n; i++) {
        if (e[i] != 0) {
          _sumBefore += e[i] - 1;
          _knownBefore++;
        }
      }
    } else {
      for (var i = index; i < _anchor && i < n; i++) {
        if (e[i] != 0) {
          _sumBefore -= e[i] - 1;
          _knownBefore--;
        }
      }
    }
    _anchor = index;
  }

  /// Takes [extent] as item [index]'s; nothing with an [itemExtent].
  void _measure(int index, int extent) {
    if (_itemExtent != null) {
      return;
    }
    var e = _extents;
    if (index >= e.length) {
      var n = e.length < 32 ? 64 : 2 * e.length;
      if (n <= index) {
        n = index + 1;
      }
      e = _extents = Int32List(n)..setRange(0, e.length, e);
    }
    final old = e[index];
    if (old == extent + 1) {
      return;
    }
    e[index] = extent + 1;
    final d = old == 0 ? extent : extent - old + 1;
    _sum += d;
    if (old == 0) {
      _known++;
    }
    if (index < _anchor) {
      _sumBefore += d;
      if (old == 0) {
        _knownBefore++;
      }
    }
  }

  /// Forgets the measures of the items from [from] on.
  void _forget(int from) {
    final e = _extents;
    for (var i = from; i < e.length; i++) {
      final x = e[i];
      if (x != 0) {
        e[i] = 0;
        _sum -= x - 1;
        _known--;
        if (i < _anchor) {
          _sumBefore -= x - 1;
          _knownBefore--;
        }
      }
    }
  }

  // ------------------------------------------------------------------ paint

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final styles = canvas.styles;
    if (!identical(styles, _penIn)) {
      _penIn = styles;
      _penId = styles.pen(_background);
    }
    final pen = _penId;
    assert(_opaqueBackground(ctx, pen), _translucentBoundary);
    final w = width;
    final h = height;
    // the rows the items moved up since the last paint: those of the first
    // one in the window painted then and not laid out since
    int? shift;
    if (!_fullRepaint && w == _paintedWidth && h == _paintedHeight) {
      for (var c = firstChild; c != null;) {
        final at = c.parentData as ListParentData;
        if (at._painted && at.dy < h && at.dy + c.height > 0) {
          shift = at._paintedDy - at.dy;
          break;
        }
        c = at.nextSibling;
      }
      if (shift != null && shift != 0) {
        final (gx, gy) = globalOffset;
        // the surface can move only rows it has: a list partly off it (or
        // cut by an ancestor) paints all that shows instead
        if (shift.abs() < h && canvas.clipContains(gx, gy, gx + w, gy + h)) {
          ctx.surface.scrollRect(gx, gx + w, gy, gy + h, shift);
          RenderObject._shiftUnderlays(this, gx, gx + w, gy, gy + h, shift);
        } else {
          shift = null;
        }
      }
    }
    var end = 0;
    for (var c = firstChild; c != null;) {
      final at = c.parentData as ListParentData;
      end = at.dy + c.height;
      c = at.nextSibling;
    }
    end = end < 0 ? 0 : (end > h ? h : end);
    if (shift == null) {
      _paintRows(ctx, pen, 0, h);
    } else {
      _paintChanged(ctx, pen, shift, end);
    }
    for (var c = firstChild; c != null;) {
      final at = c.parentData as ListParentData;
      at
        .._painted = true
        .._paintedDy = at.dy;
      c = at.nextSibling;
    }
    _paintedWidth = w;
    _paintedHeight = h;
    _paintedEnd = end;
    _fullRepaint = false;
  }

  /// Paints the rows that do not show what they showed after a shift of
  /// [shift] rows: those it exposed, those of items not painted where the
  /// shift took them, and those below the items, [end] on, that showed
  /// items before.
  void _paintChanged(PaintContext ctx, int pen, int shift, int end) {
    final h = height;
    var dirty = _dirtyRows;
    if (dirty.length < h) {
      dirty = _dirtyRows = Uint8List(h);
    } else {
      dirty.fillRange(0, h, 0);
    }
    if (shift > 0) {
      _mark(h - shift, h);
    } else {
      _mark(0, -shift);
    }
    for (var c = firstChild; c != null;) {
      final at = c.parentData as ListParentData;
      if (!at._painted || at._paintedDy - at.dy != shift) {
        _mark(at.dy, at.dy + c.height);
      }
      c = at.nextSibling;
    }
    _mark(end, _paintedEnd - shift);
    var kept = false;
    for (var from = 0; from < h;) {
      var to = from + 1;
      while (to < h && dirty[to] == dirty[from]) {
        to++;
      }
      if (dirty[from] != 0) {
        _paintRows(ctx, pen, from, to);
      } else {
        kept = true;
      }
      from = to;
    }
    if (kept) {
      // the rows it kept show the boundaries inside it as they were: those
      // marked for paint since repaint on their own, all that is inside
      // painting all of its cells, since they were cut off here
      _paintedIn = 0;
      for (var c = firstChild; c != null;) {
        _forgetPaint(c);
        c = (c.parentData as ListParentData).nextSibling;
      }
    }
  }

  /// Marks rows [from] to [to] of the window to paint.
  void _mark(int from, int to) {
    final a = from < 0 ? 0 : from;
    final b = to > height ? height : to;
    if (a < b) {
      _dirtyRows.fillRange(a, b, 1);
    }
  }

  /// Paints rows [from] to [to]: the background, and the items there.
  void _paintRows(PaintContext ctx, int pen, int from, int to) {
    final canvas = ctx.canvas
      ..save()
      ..clipRect(0, from, width, to - from)
      ..fill(0, from, width, to - from, pen);
    for (var c = firstChild; c != null;) {
      final at = c.parentData as ListParentData;
      if (at.dy < to && at.dy + c.height > from) {
        paintChild(ctx, c);
      }
      c = at.nextSibling;
    }
    canvas.restore();
  }
}
