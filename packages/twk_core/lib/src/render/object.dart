part of 'render.dart';

/// The sizes a parent lets a child take in [RenderObject.layout]: a width
/// from [minW] to [maxW] and a height from [minH] to [maxH], in cells.
///
/// Constraints go down the tree and sizes come up, as in Flutter: a parent
/// lays each child out within constraints, the child sets its
/// [RenderObject.width] and [RenderObject.height] within them, and the
/// parent places it. A limit of [unbounded] limits nothing (a child of a
/// [RenderViewport] along its axis); [isTight] constraints leave the child
/// one size, which makes it a relayout boundary.
///
/// ```dart
/// const c = BoxConstraints(0, 40, 1, 10);
/// assert(c.constrainW(60) == 40 && c.constrainH(0) == 1);
/// assert(const BoxConstraints.tight(80, 24).isTight);
/// ```
///
/// See also:
///
///  * [RenderConstrainedBox], which lays its child out within constraints
///    of its own.
final class BoxConstraints {
  /// Constraints from [minW] to [maxW] wide and from [minH] to [maxH]
  /// tall, each minimum at most its maximum.
  const BoxConstraints(this.minW, this.maxW, this.minH, this.maxH);

  /// Exactly [w] wide and [h] tall.
  const BoxConstraints.tight(int w, int h) : this(w, w, h, h);

  /// Exactly [width] wide and [height] tall where given, any size along an
  /// axis left out.
  const BoxConstraints.tightFor({int? width, int? height})
    : minW = width ?? 0,
      maxW = width ?? unbounded,
      minH = height ?? 0,
      maxH = height ?? unbounded;

  /// An extent no screen reaches: a limit that limits nothing, as Flutter's
  /// infinity does.
  static const int unbounded = 1 << 30;

  /// The fewest columns the child may be wide.
  final int minW;

  /// The most columns the child may be wide; [unbounded] for any number.
  final int maxW;

  /// The fewest rows the child may be tall.
  final int minH;

  /// The most rows the child may be tall; [unbounded] for any number.
  final int maxH;

  /// The width nearest to [w] these constraints allow: [w] held between
  /// [minW] and [maxW].
  int constrainW(int w) => w < minW ? minW : (w > maxW ? maxW : w);

  /// The height nearest to [h] these constraints allow: [h] held between
  /// [minH] and [maxH].
  int constrainH(int h) => h < minH ? minH : (h > maxH ? maxH : h);

  /// Only one size fits.
  bool get isTight => minW >= maxW && minH >= maxH;

  @override
  bool operator ==(Object other) =>
      other is BoxConstraints &&
      other.minW == minW &&
      other.maxW == maxW &&
      other.minH == minH &&
      other.maxH == maxH;
  @override
  int get hashCode => Object.hash(minW, maxW, minH, maxH);
}

/// What a frame paints with: the canvas a [RenderObject.paint] draws on,
/// the surface under it and the presenter that turns it into bytes.
///
/// A frame hands one to [PipelineOwner.flushPaint]; a `Screen` has all
/// three:
///
/// ```dart
/// final screen = Screen(80, 24);
/// final ctx = PaintContext(screen.canvas, screen.surface, screen.presenter);
/// ```
final class PaintContext {
  /// What a frame paints with: [canvas] over [surface], which [presenter]
  /// presents.
  PaintContext(this.canvas, this.surface, this.presenter);

  /// What [RenderObject.paint] draws on, its origin at the object being
  /// painted and clipped to its bounds.
  final Canvas canvas;

  /// The cells [canvas] writes to, which keep what was painted between
  /// frames: an object that scrolls shifts its rows here
  /// ([Surface.scrollRect]), and the terminal scrolls them in hardware.
  final Surface surface;

  /// What turns the surface's changes into bytes for the terminal.
  final Presenter presenter;
}

/// What a parent keeps on each child: where the child is, and whatever
/// else its layout needs per child (a fixed height, a flex factor). The
/// parent sets it up when it adopts the child
/// ([RenderObject.setupParentData]) and fills it in its layout.
class ParentData {
  /// The data of a child not laid out yet, at the origin.
  ParentData();

  /// The column of the child's left edge inside the parent, set by the
  /// parent's layout.
  var dx = 0;

  /// The row of the child's top edge inside the parent, set by the
  /// parent's layout.
  var dy = 0;

  /// Adds what the parent's layout keeps here besides the offset (a flex
  /// factor, the edges a child is pinned to) to the description of the
  /// child ([RenderObject.describe]).
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {}
}

/// What a [ContainerRenderObjectMixin] keeps on each child besides its
/// offset: the children before and after it.
mixin ContainerParentDataMixin on ParentData {
  /// The child before this one; null for the first.
  RenderObject? previousSibling;

  /// The child after this one; null for the last.
  RenderObject? nextSibling;
}

/// The children of a render object that has any number of them, in order,
/// linked through their [ContainerParentDataMixin]s: inserting after a
/// sibling, moving and removing take the same time at any position, and
/// walking the list allocates nothing. The object gives each child it
/// adopts a [P] in [setupParentData].
mixin ContainerRenderObjectMixin<P extends ContainerParentDataMixin>
    on RenderObject {
  var _childCount = 0;
  RenderObject? _firstChild;
  RenderObject? _lastChild;

  /// How many children this object has.
  int get childCount => _childCount;

  /// The first child, painted first and hit tested last; null without
  /// children.
  RenderObject? get firstChild => _firstChild;

  /// The last child, painted last (over the others) and hit tested first;
  /// null without children.
  RenderObject? get lastChild => _lastChild;

  /// The child before [child]; null for the first.
  RenderObject? childBefore(RenderObject child) {
    assert(identical(child.parent, this), '$child is not a child of $this');
    return (child.parentData as P).previousSibling;
  }

  /// The child after [child]; null for the last.
  RenderObject? childAfter(RenderObject child) {
    assert(identical(child.parent, this), '$child is not a child of $this');
    return (child.parentData as P).nextSibling;
  }

  /// Adopts [child] and puts it after [after], one of the children, or
  /// first when [after] is null.
  void insert(RenderObject child, {RenderObject? after}) {
    assert(!identical(child, this), 'a render object is not its own child');
    assert(child.parent == null, '$child already has a parent');
    assert(
      after == null || identical(after.parent, this),
      '$after is not a child of $this',
    );
    adopt(child);
    assert(child.parentData is P, 'setupParentData gives each child a $P');
    _link(child, after);
  }

  /// Adopts [child] and puts it last.
  void add(RenderObject child) => insert(child, after: _lastChild);

  /// Adds [children] in order.
  void addAll(List<RenderObject>? children) {
    if (children != null) {
      for (var i = 0; i < children.length; i++) {
        add(children[i]);
      }
    }
  }

  /// Takes [child] out of the list and drops it.
  void remove(RenderObject child) {
    assert(identical(child.parent, this), '$child is not a child of $this');
    _unlink(child);
    drop(child);
  }

  /// Drops every child.
  void removeAll() {
    var child = _firstChild;
    while (child != null) {
      final at = child.parentData as P;
      final next = at.nextSibling;
      at
        ..previousSibling = null
        ..nextSibling = null;
      drop(child);
      child = next;
    }
    _firstChild = null;
    _lastChild = null;
    _childCount = 0;
  }

  /// Puts [child], one of the children, after [after], another one, or
  /// first when [after] is null.
  void move(RenderObject child, {RenderObject? after}) {
    assert(identical(child.parent, this), '$child is not a child of $this');
    assert(
      after == null || identical(after.parent, this),
      '$after is not a child of $this',
    );
    if (identical(child, after) ||
        identical((child.parentData as P).previousSibling, after)) {
      return;
    }
    _unlink(child);
    _link(child, after);
    markNeedsLayout();
  }

  void _link(RenderObject child, RenderObject? after) {
    final at = child.parentData as P;
    final next = after == null
        ? _firstChild
        : (after.parentData as P).nextSibling;
    at
      ..previousSibling = after
      ..nextSibling = next;
    if (after == null) {
      _firstChild = child;
    } else {
      (after.parentData as P).nextSibling = child;
    }
    if (next == null) {
      _lastChild = child;
    } else {
      (next.parentData as P).previousSibling = child;
    }
    _childCount++;
  }

  void _unlink(RenderObject child) {
    final at = child.parentData as P;
    final previous = at.previousSibling;
    final next = at.nextSibling;
    if (previous == null) {
      _firstChild = next;
    } else {
      (previous.parentData as P).nextSibling = next;
    }
    if (next == null) {
      _lastChild = previous;
    } else {
      (next.parentData as P).previousSibling = previous;
    }
    at
      ..previousSibling = null
      ..nextSibling = null;
    _childCount--;
  }

  @override
  void visitChildren(void Function(RenderObject child) visit) {
    var child = _firstChild;
    while (child != null) {
      final next = (child.parentData as P).nextSibling;
      visit(child);
      child = next;
    }
  }

  /// Defers to the children.
  @override
  HitTestBehavior get hitTestBehavior => HitTestBehavior.deferToChild;

  /// From the last child back: a later child is painted over an earlier
  /// one.
  @override
  bool hitTestChildren(HitTestResult result, int x, int y) {
    for (var child = _lastChild; child != null;) {
      final at = child.parentData as P;
      if (child.hitTest(result, x - at.dx, y - at.dy)) {
        return true;
      }
      child = at.previousSibling;
    }
    return false;
  }
}

/// The child of a render object that has at most one.
mixin RenderObjectWithChildMixin on RenderObject {
  RenderObject? _child;

  /// The one child of this object; null for none.
  ///
  /// Setting it drops the child there was and adopts the new one, which
  /// lays this object out again.
  RenderObject? get child => _child;

  /// Drops the child there was and adopts [c].
  set child(RenderObject? c) {
    final old = _child;
    if (identical(c, old)) {
      return;
    }
    _child = c;
    if (old != null) {
      drop(old);
    }
    if (c != null) {
      adopt(c);
    }
  }

  @override
  void visitChildren(void Function(RenderObject child) visit) {
    final c = _child;
    if (c != null) {
      visit(c);
    }
  }

  /// Defers to the child.
  @override
  HitTestBehavior get hitTestBehavior => HitTestBehavior.deferToChild;

  @override
  bool hitTestChildren(HitTestResult result, int x, int y) {
    final c = _child;
    if (c == null) {
      return false;
    }
    final at = c.parentData;
    return c.hitTest(result, x - at.dx, y - at.dy);
  }
}

// the kinds of intrinsic size, as RenderObject caches them
const _minWidth = 0;
const _maxWidth = 1;
const _minHeight = 2;
const _maxHeight = 3;

// until when a render object shows the error it threw in its place
const _shownNot = 0;
// until it lays out without throwing
const _shownUntilLayout = 1;
// until it is marked for paint, or laid out again
const _shownUntilPaint = 2;

// what a render object is to repaint of itself (RenderObject._paintMarks):
// the rows it covers in its boundary; all of it, a boundary or the root
const _markedBelow = 1;
const _markedWhole = 2;

/// What a render object was doing when it threw ([PipelineOwner.onError]).
enum RenderPhase {
  /// [RenderObject.performLayout].
  layout,

  /// [RenderObject.paint], or what a parent paints over a child
  /// ([RenderObject.paintsOver], [RenderObject.paintOver]).
  paint,
}

/// What a hit test does with a render object in whose bounds the cell is
/// ([RenderObject.hitTest]).
enum HitTestBehavior {
  /// It is hit only where a child of it is.
  deferToChild,

  /// It is hit anywhere in its bounds: what it covers is not tested.
  opaque,

  /// It is added anywhere in its bounds, but hit only where a child of it
  /// is: what it covers is tested too, unless that child was hit.
  translucent,
}

/// The render objects at a cell, as a hit test finds them
/// ([PipelineOwner.hitTest]), each with the cell in its own coordinates:
/// an object after those hit inside it, so that a path reads from the
/// deepest object up to the root; one that lets what it covers be hit
/// ([HitTestBehavior.translucent]) before what is hit under it.
///
/// Kept and reused between events: [reset] empties it and keeps its
/// storage, which grows only for more objects than it has held so far
/// ([capacity]), so a hit test allocates nothing once warmed up.
final class HitTestResult {
  /// An empty result with room for [capacity] objects, 16 unless given,
  /// before it grows.
  HitTestResult({int capacity = 16})
    : assert(capacity > 0, 'room for 1 object or more'),
      _targets = List.filled(capacity, null),
      _xs = Int32List(capacity),
      _ys = Int32List(capacity);

  List<RenderObject?> _targets;
  Int32List _xs;
  Int32List _ys;
  var _length = 0;

  /// The objects hit.
  int get length => _length;

  /// Whether no object was hit.
  bool get isEmpty => _length == 0;

  /// The objects it holds before it grows.
  int get capacity => _targets.length;

  /// The object hit [i]th, from 0: the deepest first.
  RenderObject operator [](int i) {
    RangeError.checkValidIndex(i, this, 'i', _length);
    return _targets[i]!;
  }

  /// The column of the cell in the coordinates of object [i].
  int xAt(int i) {
    RangeError.checkValidIndex(i, this, 'i', _length);
    return _xs[i];
  }

  /// The row of the cell in the coordinates of object [i].
  int yAt(int i) {
    RangeError.checkValidIndex(i, this, 'i', _length);
    return _ys[i];
  }

  /// Adds [target], hit at [x], [y] of its own, after the objects added
  /// before it.
  void add(RenderObject target, int x, int y) {
    final n = _length;
    if (n == _targets.length) {
      _grow();
    }
    _targets[n] = target;
    _xs[n] = x;
    _ys[n] = y;
    _length = n + 1;
  }

  /// Empties it for the next hit test; it keeps its storage, and lets go
  /// of the objects it held.
  void reset() {
    for (var i = 0; i < _length; i++) {
      _targets[i] = null;
    }
    _length = 0;
  }

  /// Doubles the storage.
  void _grow() {
    final n = 2 * _targets.length;
    _targets = List<RenderObject?>.filled(n, null)
      ..setRange(0, _length, _targets);
    _xs = Int32List(n)..setRange(0, _length, _xs);
    _ys = Int32List(n)..setRange(0, _length, _ys);
  }
}

/// A render object of the tree a [PipelineOwner] lays out and paints.
///
/// A subclass sets its [width] and [height] within the constraints it is
/// given in [performLayout], laying out its children there first
/// ([layout]) and placing each by its [parentData]; and draws itself in
/// [paint], at the canvas origin and clipped to its bounds, its children
/// with [paintChild]. A change to what it shows marks it: [markNeedsLayout]
/// for one that may change its size or its children's, [markNeedsPaint]
/// for one that only changes how it looks. An object with children mixes
/// in [RenderObjectWithChildMixin] or [ContainerRenderObjectMixin], which
/// keep them, visit them and hit test them.
///
/// A label as wide as its text, one row tall:
///
/// ```dart
/// final class RenderLabel extends RenderObject {
///   RenderLabel(this._label, this.pen);
///
///   final int pen;
///   String _label;
///   set label(String l) {
///     _label = l;
///     markNeedsLayout();
///   }
///
///   @override
///   void performLayout(BoxConstraints c) {
///     width = c.constrainW(_label.length);
///     height = c.constrainH(1);
///   }
///
///   @override
///   void paint(PaintContext ctx) => ctx.canvas.text(0, 0, _label, pen);
/// }
/// ```
///
/// An exception its [performLayout] or [paint] throws stays in it: the
/// object shows the error's message in white on red in its place, clipped
/// to its bounds, and the owner reports it ([PipelineOwner.onError]). After
/// a layout that threw, the object is as big as the message within its
/// constraints, and shows it until it lays out without throwing; after a
/// paint that threw, until it is marked for paint ([markNeedsPaint]) or
/// laid out again, which paints it again.
abstract class RenderObject {
  /// An object with no parent, no owner and no size yet, for a subclass
  /// to construct.
  RenderObject();

  RenderObject? _parent;

  /// The object this one is a child of; set by the parent ([adopt],
  /// [drop]).
  RenderObject? get parent => _parent;
  set parent(RenderObject? p) {
    final was = _parent;
    if (identical(p, was)) {
      return;
    }
    final n = _cutOffPainters;
    final wholes = _wholesBelow;
    if (n != 0 || wholes != 0) {
      for (var o = was; o != null; o = o._parent) {
        o
          .._cutOffPainters -= n
          .._wholesBelow -= wholes;
      }
    }
    _parent = p;
    if (p != null) {
      if (n != 0 || wholes != 0) {
        for (RenderObject? o = p; o != null; o = o._parent) {
          o
            .._cutOffPainters += n
            .._wholesBelow += wholes;
        }
      }
      if (_mayKeepPaint) {
        _listIn(p);
        p._keepsPaint();
      }
    }
  }

  /// The pipeline this object is attached to ([attach]); null while it is
  /// detached, when nothing in it is laid out or painted.
  PipelineOwner? owner;

  // a warning of the tree itself, to where its owner routes them
  // (PipelineOwner.onLog), and to log() where it routes none
  void _warn(String message) {
    final route = owner?.onLog;
    if (route == null) {
      log(message, level: LogLevel.warning);
    } else {
      route(LogRecord(DateTime.now(), LogLevel.warning, message));
    }
  }

  /// What the parent keeps on this object: its offset and whatever else
  /// the parent's layout needs. Set up by the parent when it adopts this
  /// object ([setupParentData]) and filled in by the parent's layout.
  var parentData = ParentData();

  /// How many columns this object takes, set by its [performLayout] within
  /// the constraints it was given.
  var width = 0;

  /// How many rows this object takes, set by its [performLayout] within
  /// the constraints it was given.
  var height = 0;
  BoxConstraints? _constraints;
  var _needsLayout = true;

  // laid out last so that its size can't change the parent's layout: a
  // layout mark stops here, and this subtree is laid out on its own
  var _relayoutBoundary = false;

  // the owner's paint bookkeeping: queued for the next flushPaint, and the
  // flushPaint generation that last painted this object
  var _queued = false;
  var _paintedIn = 0;

  // what is to be repainted of it on the next flushPaint: marked below its
  // boundary, so its rows are (_markedBelow); a boundary or the root, all
  // of it (_markedWhole)
  var _paintMarks = 0;

  // while a flushPaint resolves what its boundaries repaint: the flush
  // that has this boundary in its list (its _paintGen), and its place there
  var _slotIn = 0;
  var _slot = 0;

  // this object or one inside it painted since it was last told to forget
  // what it painted (_forgetPaint): set on an object, it is set on all
  // above it, and the object is in its parent's _keepers
  var _mayKeepPaint = false;

  // the children that may keep paint, for _forgetPaint and _forgetCut to
  // visit in place of all of them: each child that painted since this
  // object last forgot, listed once while it says it is listed here
  // (_listedIn); an entry of a child dropped since, or the second of one
  // moved away and back, is passed over. _listIn drops those when the list
  // grows to _keepersCap, then at twice what it kept.
  List<RenderObject>? _keepers;
  var _keepersCap = 16;
  RenderObject? _listedIn;

  // the objects in this subtree, this one included, painted however they
  // are cut off (paintedWhenCutOff)
  var _cutOffPainters = 0;
  var _paintedWhenCutOff = false;

  // the objects in this subtree, this one included, repainted whole with
  // their boundaries (repaintedWhole)
  var _wholesBelow = 0;

  /// Whether this object is painted even where the clip of its parent
  /// leaves none of it, and so are the objects above it: its paint does
  /// more than paint its cells (it shows the terminal's cursor, or hides
  /// it), which has to happen however it is cut off. Its cells are not
  /// painted then: the clip it paints in is empty. Off by default: a child
  /// the clip leaves no cell of is not painted, nor anything inside it
  /// ([paintChild]).
  bool get paintedWhenCutOff => _paintedWhenCutOff;
  set paintedWhenCutOff(bool on) {
    if (on == _paintedWhenCutOff) {
      return;
    }
    _paintedWhenCutOff = on;
    final d = on ? 1 : -1;
    for (RenderObject? o = this; o != null; o = o._parent) {
      o._cutOffPainters += d;
    }
  }

  var _repaintedWhole = false;

  /// Whether all of this object is repainted whenever a repaint boundary
  /// it is in repaints any of its rows: what it paints depends on more
  /// than itself and what is inside it (where another object is now), so
  /// a change elsewhere in the boundary may change it without marking it.
  /// Off by default: a boundary repaints only the rows of the objects
  /// marked for paint in it ([markNeedsPaint]).
  bool get repaintedWhole => _repaintedWhole;
  set repaintedWhole(bool on) {
    if (on == _repaintedWhole) {
      return;
    }
    _repaintedWhole = on;
    final d = on ? 1 : -1;
    for (RenderObject? o = this; o != null; o = o._parent) {
      o._wholesBelow += d;
    }
  }

  /// Which of its rows this object, [repaintedWhole], has repainted with a
  /// repaint boundary it is in that repaints any rows: [rows] holds 0 and
  /// its height when asked, and is left holding the first of them, in its
  /// own coordinates, and the row after the last; none when the first is
  /// not before the other. All of them unless it says otherwise: one that
  /// paints by where other objects are may answer the rows it showed in
  /// last joined with those it shows in now, and none when they are the
  /// same. Asked as a flushPaint settles the rows its boundaries repaint,
  /// after layout and before anything is painted, once for each boundary
  /// around it that repaints any rows: the same answer every time in one
  /// flush.
  void wholeRows(Int32List rows) {}

  var _checkedBeforePaint = false;

  /// Whether [beforePaint] is called while this object is attached. Off by
  /// default.
  bool get checkedBeforePaint => _checkedBeforePaint;
  set checkedBeforePaint(bool on) {
    if (on == _checkedBeforePaint) {
      return;
    }
    _checkedBeforePaint = on;
    final o = owner;
    if (o != null) {
      if (on) {
        o._checkedBeforePaint.add(this);
      } else {
        o._checkedBeforePaint.remove(this);
      }
    }
  }

  /// Called, while this object is [checkedBeforePaint], by each
  /// [PipelineOwner.flushPaint] that has anything to paint: after layout,
  /// before the flush settles the rows its boundaries repaint. What it marks
  /// for paint here ([markNeedsPaint]) that flush paints. One that paints by
  /// where other objects are, which may move in another repaint boundary
  /// without marking it, marks itself here when they moved: in the same
  /// frame. What it throws, it shows, marked for paint.
  void beforePaint() {}

  /// Notes that this object paints: it, and the objects above it, may keep
  /// something of it until they are told to forget it.
  void _keepsPaint() {
    for (RenderObject? o = this; o != null && !o._mayKeepPaint;) {
      o._mayKeepPaint = true;
      final p = o._parent;
      if (p != null) {
        o._listIn(p);
      }
      o = p;
    }
  }

  /// Lists this object, which may keep paint, among the children of [p],
  /// its parent, that do ([_keepers]), unless it is listed there.
  void _listIn(RenderObject p) {
    if (identical(_listedIn, p)) {
      return;
    }
    final list = p._keepers ??= [];
    if (list.length >= p._keepersCap) {
      var live = 0;
      for (var i = 0; i < list.length; i++) {
        final c = list[i];
        if (identical(c._listedIn, p) && identical(c._parent, p)) {
          // the first of its entries; the next ones are dropped
          c._listedIn = null;
          list[live++] = c;
        } else if (identical(c._listedIn, p)) {
          c._listedIn = null;
        }
      }
      list.length = live;
      for (var i = 0; i < live; i++) {
        list[i]._listedIn = p;
      }
      p._keepersCap = live < 8 ? 16 : 2 * live;
    }
    _listedIn = p;
    list.add(this);
  }

  // laid out since the relayout highlight last looked
  // (PipelineOwner.debugRelayoutHighlight)
  var _laidOut = false;

  // the last answer of each kind of intrinsic size: the argument at
  // [2 * kind], the answer at [2 * kind + 1]; bit `kind` of
  // _intrinsicsCached says the pair holds
  Int64List? _intrinsics;
  var _intrinsicsCached = 0;

  // the message of what its layout or paint threw last, until it paints
  // without throwing: the same error again is not reported again; and until
  // when it shows it in its place (_shownNot, _shownUntilLayout or
  // _shownUntilPaint)
  String? _error;
  int _errorShown = _shownNot;

  /// Whether this object is a repaint boundary, repainted on its own over
  /// what it painted before when something inside it is marked
  /// ([markNeedsPaint]); false by default.
  ///
  /// A boundary paints every cell of its bounds with an opaque background:
  /// a translucent one would blend with itself on every repaint, not with
  /// what is under it.
  bool get isRepaintBoundary => false;

  /// Whether this repaint boundary paints over what is under it, with no
  /// background of its own: a field, a gauge over a dialog, a selected
  /// row, a gradient; false by default.
  ///
  /// A boundary repaints on its own over what it painted before, so one
  /// without a background would keep its old cells' colors. One that
  /// keeps an underlay has the owner keep the styles of the cells under it
  /// as its parent leaves them, each time the parent paints it, and put
  /// back those of the rows it repaints before it repaints them on its
  /// own: it paints over what is there. A cell its parent has not painted
  /// since the boundary moved or was resized is not put back; moved by a
  /// scroll that moves its cells ([Surface.scrollRect], a
  /// [RenderViewport]'s, a [RenderList]'s), what it keeps moves with
  /// them.
  ///
  /// Put back by the owner ([putsUnderlayBack]), it is for a boundary
  /// that paints every cell of the rows it repaints on its own; one that
  /// keeps cells and moves them, a text area, puts it back itself under
  /// the cells it paints ([putUnderlayBack]), and moves rows only where
  /// they have the same underlay ([underlayRowsAlike]). It costs a copy of
  /// its rows' styles each time its parent paints it, and of those it
  /// repaints each time it repaints alone, and a pen over what is under
  /// each cell rather than one that covers it.
  bool get keepsUnderlay => false;

  /// Whether the owner puts back the underlay of the rows this boundary
  /// repaints on its own, before it repaints them ([keepsUnderlay]); true
  /// by default. False for one that keeps cells it does not repaint,
  /// which puts it back itself ([putUnderlayBack]).
  bool get putsUnderlayBack => true;

  /// Puts back the styles of the cells under this boundary
  /// ([keepsUnderlay]) in its rectangle at [x], [y] of [w] × [h] cells
  /// (in its own coordinates, within the clip of [canvas]): what it then
  /// paints there is over what its parent left. A cell its parent has not
  /// painted since it moved is left as it is. For a boundary that puts
  /// it back itself ([putsUnderlayBack] false), before it paints the cells.
  void putUnderlayBack(Canvas canvas, int x, int y, int w, int h) {
    canvas
      ..save()
      ..clipRect(x, y, w, h);
    _restoreUnderlay(canvas);
    canvas.restore();
  }

  /// Whether every row of the underlay of this boundary is the same
  /// ([keepsUnderlay]): rows of it moved up or down on the surface then
  /// show over what is under their new place; false where its parent has
  /// not painted all of it since it moved, or keeps none.
  bool get underlayRowsAlike {
    final u = _underlay;
    if (u == null || _uPartial) {
      return false;
    }
    final known = _uAlike;
    if (known != null) {
      return known;
    }
    final w = _uw;
    for (var y = 1; y < _uh; y++) {
      for (var x = 0; x < w; x++) {
        if (u[y * w + x] != u[x]) {
          return _uAlike = false;
        }
      }
    }
    return _uAlike = true;
  }

  // underlayRowsAlike, worked out once a capture; null until asked
  bool? _uAlike;

  // the styles under it, a cell a word over its whole rectangle at
  // (_uox, _uoy); _unknown where its parent has not painted since it moved
  Uint32List? _underlay;
  var _uox = 0;
  var _uoy = 0;
  var _uw = 0;
  var _uh = 0;

  // whether a cell of it is still _unknown: put back cell by cell then,
  // row by row once its parent has painted all of it
  var _uPartial = false;

  static const _unknown = 0xFFFFFFFF;

  void _keepUnderlay(Canvas canvas) {
    final ox = canvas.originX;
    final oy = canvas.originY;
    final w = width;
    final h = height;
    if (w <= 0 || h <= 0) {
      return;
    }
    var u = _underlay;
    if (u == null) {
      owner?._underlays.add(this);
    }
    if (u == null || ox != _uox || oy != _uoy || w != _uw || h != _uh) {
      u = _underlay = Uint32List(w * h)..fillRange(0, w * h, _unknown);
      _uPartial = true;
      _uox = ox;
      _uoy = oy;
      _uw = w;
      _uh = h;
    }
    final (x0, y0, x1, y1) = canvas.clipBounds;
    if (x0 >= x1) {
      return;
    }
    final styles = canvas.surface.styles;
    final stride = canvas.surface.width;
    for (var y = y0; y < y1; y++) {
      final at = (y - oy) * w + (x0 - ox);
      u.setRange(at, at + x1 - x0, styles, y * stride + x0);
    }
    _uAlike = null;
    if (_uPartial && x0 == ox && y0 == oy && x1 == ox + w && y1 == oy + h) {
      _uPartial = false;
    }
  }

  /// Moves what the boundaries inside [scroller] keep under them as
  /// [scroller] moved the cells of the rectangle [x0]..[x1], [y0]..[y1]
  /// [shift] rows up (down where below 0) with the surface's scrollRect:
  /// the cells under them went with them, kept rather than painted again.
  /// One wider than the rectangle (a field in a row that scrolls
  /// sideways) moves too: [scroller] clips what is inside it to the
  /// rectangle, so its columns out of it keep nothing put back there.
  static void _shiftUnderlays(
    RenderObject scroller,
    int x0,
    int x1,
    int y0,
    int y1,
    int shift,
  ) {
    final list = scroller.owner?._underlays;
    if (list == null || list.isEmpty) {
      return;
    }
    for (var i = 0; i < list.length; i++) {
      final b = list[i];
      if (b._uox + b._uw <= x0 || b._uox >= x1) {
        continue;
      }
      if (b._uoy + b._uh <= y0 || b._uoy >= y1) {
        continue;
      }
      var p = b.parent;
      while (p != null && !identical(p, scroller)) {
        p = p.parent;
      }
      if (p != null) {
        b._uoy -= shift;
      }
    }
  }

  void _restoreUnderlay(Canvas canvas) {
    final u = _underlay;
    if (u == null ||
        canvas.originX != _uox ||
        canvas.originY != _uoy ||
        width != _uw ||
        height != _uh) {
      return;
    }
    final (x0, y0, x1, y1) = canvas.clipBounds;
    if (x0 >= x1) {
      return;
    }
    final w = _uw;
    final styles = canvas.surface.styles;
    final stride = canvas.surface.width;
    if (!_uPartial) {
      for (var y = y0; y < y1; y++) {
        final at = (y - _uoy) * w + (x0 - _uox);
        styles.setRange(y * stride + x0, y * stride + x1, u, at);
      }
      return;
    }
    for (var y = y0; y < y1; y++) {
      final at = (y - _uoy) * w + (x0 - _uox);
      final to = y * stride + x0;
      for (var i = 0; i < x1 - x0; i++) {
        final st = u[at + i];
        if (st != _unknown) {
          styles[to + i] = st;
        }
      }
    }
  }

  /// Whether this object's size depends on its constraints alone; false by
  /// default. Whatever changes inside it, its parent sees the same size,
  /// so the object is a relayout boundary.
  bool get sizedByParent => false;

  /// Calls [visit] with each child of this object, in paint order; none by
  /// default. An object with children overrides it, which the pipeline
  /// walks the tree by ([attach], [detach], [describe]).
  void visitChildren(void Function(RenderObject child) visit) {}

  /// Gives [child], about to be adopted, the kind of [parentData] this
  /// object's layout keeps on it. A container that keeps more than the
  /// offset replaces data of any other kind.
  void setupParentData(RenderObject child) {}

  /// Makes [child], which has no parent, a child of this object: gives it
  /// [parentData] ([setupParentData]), attaches it to this object's owner,
  /// if any, and lays this object out again. The parent's own list of
  /// children holds it too ([RenderObjectWithChildMixin.child],
  /// [ContainerRenderObjectMixin.insert]).
  void adopt(RenderObject child) {
    setupParentData(child);
    child.parent = this;
    if (owner != null) {
      child.attach(owner!);
    }
    markNeedsLayout();
  }

  /// Removes [child] from this object (the parent's own list of children
  /// must no longer hold it): it is detached from the pipeline, and this
  /// object is laid out and repainted without it.
  void drop(RenderObject child) {
    child
      ..parent = null
      ..detach();
    markNeedsLayout();
  }

  /// Joins the pipeline of [o], with everything inside it: the owner lays
  /// out and paints what is marked in it. A relayout boundary marked while
  /// detached is laid out on the next frame, and the intrinsic sizes
  /// worked out before are forgotten, since [o] measures text with its own
  /// segmenter. The parent attaches what it adopts ([adopt]), and the
  /// owner its root ([PipelineOwner.root]).
  void attach(PipelineOwner o) {
    if (_checkedBeforePaint && !identical(owner, o)) {
      owner?._checkedBeforePaint.remove(this);
      o._checkedBeforePaint.add(this);
    }
    owner = o;
    // text is measured with the new owner's segmenter
    _intrinsicsCached = 0;
    // a boundary marked while detached reached no owner: an ancestor laid
    // out with the same constraints wouldn't lay it out
    if (_needsLayout && _relayoutBoundary) {
      o._addLayoutRoot(this);
    }
    // the owner handed down in a static, not in a closure, which makes a
    // closure and a context at each object
    final outer = _attaching;
    _attaching = o;
    try {
      visitChildren(_attachChild);
    } finally {
      _attaching = outer;
    }
  }

  /// The owner [attach] attaches the children it visits to.
  static PipelineOwner? _attaching;

  static void _attachChild(RenderObject c) => c.attach(_attaching!);

  /// Leaves the pipeline: nothing in this subtree is painted until it is
  /// attached again.
  void detach() {
    final o = owner;
    if (_queued) {
      o?._dirty.remove(this);
      _queued = false;
    }
    if (_checkedBeforePaint) {
      o?._checkedBeforePaint.remove(this);
    }
    if (_underlay != null) {
      o?._underlays.remove(this);
      _underlay = null;
    }
    owner = null;
    visitChildren(_detachChild);
  }

  static void _detachChild(RenderObject c) => c.detach();

  /// Lays this object out on the next frame, with the ancestors whose
  /// layout uses its size: the mark climbs to the nearest relayout
  /// boundary, and the owner lays that boundary's subtree out. Forgets the
  /// intrinsic sizes worked out so far; when any was asked for, the parent
  /// is marked too, boundary or not, since its layout may have used them.
  void markNeedsLayout() {
    if (_intrinsicsCached != 0) {
      _intrinsicsCached = 0;
      final p = parent;
      if (p != null) {
        _needsLayout = true;
        p.markNeedsLayout();
        return;
      }
    }
    if (_needsLayout) {
      return;
    }
    _needsLayout = true;
    final p = parent;
    if (p != null && !_relayoutBoundary) {
      p.markNeedsLayout();
    } else {
      owner?._addLayoutRoot(this);
    }
  }

  /// Repaints this object on the next frame, with the nearest repaint
  /// boundary at or above it; a boundary above it forgets what it painted
  /// before ([invalidatePaintCache]). Of that boundary only the rows this
  /// object covers then are repainted, all of them across: what its
  /// ancestors paint there, then what is inside them there, in order. A
  /// boundary marked itself repaints all of it.
  void markNeedsPaint() {
    if (_errorShown == _shownUntilPaint) {
      // its paint is tried again
      _errorShown = _shownNot;
    }
    var b = this;
    while (!b.isRepaintBoundary && b.parent != null) {
      b = b.parent!;
    }
    final o = owner;
    if (identical(b, this)) {
      _paintMarks |= _markedWhole;
    } else {
      b.invalidatePaintCache();
      if (o != null &&
          (b._paintMarks & _markedWhole) == 0 &&
          (_paintMarks & _markedBelow) == 0) {
        if (o._paintFlushing && b._queued) {
          // the flush under way, or the next one, paints it: the rows this
          // flush repaints are settled, so all of it
          b._paintMarks |= _markedWhole;
        } else {
          _paintMarks |= _markedBelow;
          o._markBelow(this);
        }
      }
    }
    o?._addDirty(b);
  }

  /// Lays this object out within [c]. A parent whose layout reads this
  /// object's size passes [parentUsesSize]. Otherwise, or when [c] is tight
  /// or the object is [sizedByParent], its size can't change the parent's
  /// layout: the object is a *relayout boundary*, where [markNeedsLayout]
  /// inside it stops.
  void layout(BoxConstraints c, {bool parentUsesSize = false}) {
    // decided by every call, even one that has nothing to lay out
    _relayoutBoundary =
        !parentUsesSize || c.isTight || sizedByParent || parent == null;
    if (!_needsLayout && c == _constraints) {
      return;
    }
    _constraints = c;
    _layOut(c);
    _needsLayout = false;
    // children may have moved, resized or been replaced: what was painted
    // before can't be trusted
    markNeedsPaint();
  }

  /// Lays this relayout boundary out again within the constraints its
  /// parent gave it last.
  void _relayout() {
    final w = width;
    final h = height;
    _layOut(_constraints!);
    _needsLayout = false;
    markNeedsPaint();
    // a size the parent doesn't use may still change: the cells this
    // object no longer covers are the parent's to repaint
    if ((width != w || height != h) && parent != null) {
      parent!.markNeedsPaint();
    }
  }

  /// Sets [width] and [height] within [c], laying out and placing the
  /// children first; [layout] calls it, when the constraints are new or
  /// the object was marked ([markNeedsLayout]).
  ///
  /// A child is laid out with [layout], `parentUsesSize: true` when the
  /// size it comes out at decides this object's layout, and placed by its
  /// [ParentData.dx] and [ParentData.dy]. An object that is
  /// [sizedByParent] takes its size from [c] alone. What this throws, the
  /// object shows in its place (see [RenderObject]).
  void performLayout(BoxConstraints c);

  /// Runs [callback] in this object's [performLayout], before it lays its
  /// children out: the callback may adopt, replace and drop children of
  /// this object and of those below it (a widget layer builds them there).
  /// The marks that makes stop at this object, which is being laid out, or
  /// at relayout boundaries, which the owner lays out after it in the same
  /// flush ([PipelineOwner.flushLayout]): what changed is laid out before
  /// anything is painted. When an intrinsic size this object
  /// answered before comes out different afterwards, its parent may have
  /// laid it out by the old one: the parent is laid out again on the next
  /// frame, or the object itself when it is the root (whose owner's frame
  /// may size an inline region by it).
  void invokeLayoutCallback(void Function() callback) {
    final asked = _intrinsicsCached;
    // forgotten, so that marks from below stop here
    _intrinsicsCached = 0;
    _needsLayout = true;
    callback();
    if (asked != 0 && _intrinsicsChanged(asked)) {
      final asker = parent ?? this;
      final o = owner;
      if (o != null && o._flushing) {
        o._relayoutNext.add(asker);
      } else {
        asker.markNeedsLayout();
      }
    }
  }

  /// Whether an intrinsic size of the kinds in [kinds] (a bit per kind),
  /// worked out again at the extent it was last asked at, differs from the
  /// answer given then.
  bool _intrinsicsChanged(int kinds) {
    final cache = _intrinsics!;
    var changed = false;
    for (var kind = _minWidth; kind <= _maxHeight; kind++) {
      if ((kinds & 1 << kind) != 0) {
        final answer = cache[2 * kind + 1];
        changed |= _intrinsic(kind, cache[2 * kind]) != answer;
      }
    }
    return changed;
  }

  /// Runs [performLayout] within [c]; what it throws, this object shows.
  void _layOut(BoxConstraints c) {
    _laidOut = true;
    try {
      performLayout(c);
    } on Object catch (error, stack) {
      _layoutFailed(c, error, stack);
      return;
    }
    if (_errorShown != _shownNot) {
      _errorShown = _shownNot;
    }
  }

  /// [performLayout] threw [error]: this object shows its message, as big
  /// as the message is within [c].
  void _layoutFailed(BoxConstraints c, Object error, StackTrace stack) {
    final message = '$error';
    _errorShown = _shownUntilLayout;
    width = c.constrainW(_messageWidth(this, message));
    height = c.constrainH(_messageLines(this, message, width).length);
    _failed(message, RenderPhase.layout, error, stack);
  }

  /// [paint], [paintsOver] or [paintOver] threw [error]: this object shows
  /// its message, and the owner paints what was being painted again, since
  /// [paint] may have left the canvas saved, moved or clipped.
  void _paintFailed(Object error, StackTrace stack) {
    _errorShown = _shownUntilPaint;
    owner?._paintThrew = true;
    _failed('$error', RenderPhase.paint, error, stack);
  }

  /// Reports [error], whose message is [message], unless it was reported
  /// last and this object has not painted without an error since. Without
  /// [PipelineOwner.onError], it is thrown when the owner's flush ends, or
  /// now outside one.
  void _failed(
    String message,
    RenderPhase phase,
    Object error,
    StackTrace stack,
  ) {
    final reported = message == _error;
    _error = message;
    final o = owner;
    if (o != null) {
      final report = o.onError;
      if (report != null) {
        if (!reported) {
          report(this, phase, error, stack);
        }
        return;
      }
      if (o._flushing) {
        o._thrown ??= (error, stack);
        return;
      }
    }
    Error.throwWithStackTrace(error, stack);
  }

  /// The narrowest this object can be at [height] without cutting its
  /// content off (for text, the widest piece no line break can split).
  /// What a parent asks before laying the object out; answered once per
  /// argument until [markNeedsLayout] (see [computeMinIntrinsicWidth]).
  int getMinIntrinsicWidth(int height) => _intrinsic(_minWidth, height);

  /// The width beyond which this object has no use for more at [height]
  /// (for text, its widest line unbroken).
  int getMaxIntrinsicWidth(int height) => _intrinsic(_maxWidth, height);

  /// The fewest rows this object can have at [width] without cutting its
  /// content off.
  int getMinIntrinsicHeight(int width) => _intrinsic(_minHeight, width);

  /// The height beyond which this object has no use for more at [width].
  int getMaxIntrinsicHeight(int width) => _intrinsic(_maxHeight, width);

  /// What [getMinIntrinsicWidth] answers, worked out without laying
  /// anything out. A container asks its children through their `get`
  /// methods, so their answers are cached too; text is measured with the
  /// owner's [PipelineOwner.segmenter], as the canvas draws it. An object
  /// asks for nothing (0) unless it overrides these.
  int computeMinIntrinsicWidth(int height) => 0;

  /// What [getMaxIntrinsicWidth] answers; see [computeMinIntrinsicWidth].
  int computeMaxIntrinsicWidth(int height) => 0;

  /// What [getMinIntrinsicHeight] answers; see [computeMinIntrinsicWidth].
  int computeMinIntrinsicHeight(int width) => 0;

  /// What [getMaxIntrinsicHeight] answers; see [computeMinIntrinsicWidth].
  int computeMaxIntrinsicHeight(int width) => 0;

  /// The intrinsic size of [kind] at [extent] on the other axis; the
  /// cached answer when the last question of that kind had the same
  /// [extent].
  int _intrinsic(int kind, int extent) {
    assert(extent >= 0, 'an intrinsic size is asked at an extent of 0 or more');
    final cache = _intrinsics ??= Int64List(8);
    final bit = 1 << kind;
    final at = 2 * kind;
    if ((_intrinsicsCached & bit) != 0 && cache[at] == extent) {
      return cache[at + 1];
    }
    final answer = switch (kind) {
      _minWidth => computeMinIntrinsicWidth(extent),
      _maxWidth => computeMaxIntrinsicWidth(extent),
      _minHeight => computeMinIntrinsicHeight(extent),
      _ => computeMaxIntrinsicHeight(extent),
    };
    cache[at] = extent;
    cache[at + 1] = answer;
    _intrinsicsCached |= bit;
    return answer;
  }

  /// Paints this object at the canvas origin, the canvas clipped to its
  /// bounds, and its children with [paintChild]. What this throws, the
  /// object shows in its place (see [RenderObject]).
  void paint(PaintContext ctx);

  /// Forgets what this object kept of what it painted before, to paint
  /// from that: its cells were, or will be, painted over by an ancestor,
  /// or an object inside it was marked for paint ([markNeedsPaint]).
  /// Nothing by default.
  void invalidatePaintCache() {}

  /// Paints [child] at its offset, cut off at its bounds. A child the clip
  /// leaves no cell of is not painted, nor anything inside it, unless
  /// something inside it is [paintedWhenCutOff]; one not painted keeps
  /// what it kept of its paint, since its cells are as it left them.
  void paintChild(PaintContext ctx, RenderObject child) {
    final at = child.parentData;
    final canvas = ctx.canvas
      ..save()
      ..translate(at.dx, at.dy)
      ..clipRect(0, 0, child.width, child.height);
    // an empty clip is (0, 0, 0, 0)
    final (x0, _, x1, _) = canvas.clipBounds;
    if (x0 < x1 || child._cutOffPainters != 0) {
      // painted from its parent, over what the parent painted in its
      // cells: it can't rely on what it painted before
      if (child.keepsUnderlay && child.isRepaintBoundary) {
        child._keepUnderlay(canvas);
      }
      child
        ..invalidatePaintCache()
        .._paint(ctx);
    }
    canvas.restore();
  }

  /// Paints this object, or the error it shows in its place; what [paint]
  /// throws, it shows when the owner paints it again in the same flush.
  void _paint(PaintContext ctx) {
    if (!_mayKeepPaint) {
      _keepsPaint();
    }
    if (_errorShown != _shownNot) {
      _paintError(ctx);
      return;
    }
    try {
      paint(ctx);
    } on Object catch (error, stack) {
      _paintFailed(error, stack);
      return;
    }
    if (_error != null) {
      _error = null;
    }
  }

  /// Paints the error this object shows over all of it.
  void _paintError(PaintContext ctx) => _paintMessage(
    ctx,
    _messageLines(this, _error!, width),
    width,
    height,
  );

  /// Whether this object paints anything over [child] in the cells [x],
  /// [y], [w] × [h] of its own. Not by default: only children that overlap
  /// paint over each other ([RenderStack]).
  bool paintsOver(RenderObject child, int x, int y, int w, int h) => false;

  /// Paints again what this object paints over [child] in the cells [x],
  /// [y], [w] × [h] of its own ([paintsOver]), which a repaint boundary
  /// inside [child] has just repainted on its own, over whatever covered
  /// it there. The canvas is clipped to those cells, its origin at this
  /// object.
  void paintOver(
    PaintContext ctx,
    RenderObject child,
    int x,
    int y,
    int w,
    int h,
  ) {}

  /// [paintsOver], false while this object shows an error; what it
  /// throws, this object shows ([_overFailed]).
  bool _paintsOver(RenderObject child, int x, int y, int w, int h) {
    if (_errorShown != _shownNot) {
      return false;
    }
    try {
      return paintsOver(child, x, y, w, h);
    } on Object catch (error, stack) {
      _overFailed(error, stack);
      return false;
    }
  }

  /// [paintOver], nothing while this object shows an error; what it
  /// throws, this object shows ([_overFailed]).
  void _paintOverChild(
    PaintContext ctx,
    RenderObject child,
    int x,
    int y,
    int w,
    int h,
  ) {
    if (_errorShown != _shownNot) {
      return;
    }
    try {
      paintOver(ctx, child, x, y, w, h);
    } on Object catch (error, stack) {
      _overFailed(error, stack);
    }
  }

  /// [paintsOver] or [paintOver] threw [error] while a repaint boundary
  /// inside this object repainted on its own: this object shows its
  /// message, painted with its own boundary later in the owner's pass.
  void _overFailed(Object error, StackTrace stack) {
    _paintFailed(error, stack);
    var b = this;
    while (!b.isRepaintBoundary && b.parent != null) {
      b = b.parent!;
    }
    final o = owner;
    if (o != null && !b._queued) {
      b
        .._queued = true
        .._paintMarks |= _markedWhole;
      o._painting.add(b);
    }
  }

  /// What a hit test does with this object ([hitTest]): any object is
  /// [HitTestBehavior.opaque] unless it says otherwise, as one that paints
  /// all of its cells is; one with children ([RenderObjectWithChildMixin],
  /// [ContainerRenderObjectMixin]) defers to them unless it paints its own
  /// cells too.
  HitTestBehavior get hitTestBehavior => HitTestBehavior.opaque;

  /// Adds what is at [x], [y] of this object, a cell in its own
  /// coordinates, to [result]: nothing when the cell is outside its bounds
  /// (a child that sticks out of its parent is cut off there, as paint
  /// cuts it); otherwise the children hit there ([hitTestChildren]), then
  /// this object when it is hit there itself ([hitTestSelf]), a child is,
  /// or it is [HitTestBehavior.translucent]. Returns whether it is hit:
  /// then what it covers is not tested. An object that shows an error
  /// ([debugError]) is hit anywhere in its bounds, and its children not
  /// tested. Uses the last layout; allocates nothing.
  bool hitTest(HitTestResult result, int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) {
      return false;
    }
    if (_errorShown != _shownNot) {
      result.add(this, x, y);
      return true;
    }
    final hit = hitTestChildren(result, x, y) || hitTestSelf(x, y);
    if (hit || hitTestBehavior == HitTestBehavior.translucent) {
      result.add(this, x, y);
    }
    return hit;
  }

  /// Whether this object is hit at [x], [y] of its own, a cell in its
  /// bounds, where no child is: when it is [HitTestBehavior.opaque]. One
  /// that paints only some of its cells may answer for each.
  bool hitTestSelf(int x, int y) => hitTestBehavior == HitTestBehavior.opaque;

  /// Hit tests the children at [x], [y] of this object, each in its own
  /// coordinates, the one painted last (on top) first, until one is hit;
  /// returns whether one was. Nothing by default.
  bool hitTestChildren(HitTestResult result, int x, int y) => false;

  /// The constraints of the last layout; null before the first.
  BoxConstraints? get constraints => _constraints;

  /// Whether this object is to be laid out on the next frame.
  bool get debugNeedsLayout => _needsLayout;

  /// Whether this object, a repaint boundary or the root, is to be
  /// repainted on the next frame ([markNeedsPaint] inside it).
  bool get debugNeedsPaint => _queued;

  /// The message of the error this object shows in its place, which its
  /// layout or paint threw; null when it shows itself.
  String? get debugError => _errorShown == _shownNot ? null : _error;

  /// Adds what describes this object, besides its type, size and flags, to
  /// [properties], those not worth showing (a default) left out; an
  /// override calls this first. Only [describe] calls it: a frame never
  /// does.
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {}

  /// This object and those below it as a tree of descriptions, built when
  /// called: its type; the properties [debugFillProperties] adds, those its
  /// parent keeps on it ([ParentData.debugFillProperties]), its offset in
  /// the parent and the constraints of its last layout (`tight`, or what
  /// [describeConstraints] says); the error it shows in its place, if
  /// any ([debugError]); its size once laid out; and as flags whether it is
  /// a repaint boundary, a relayout boundary, to be laid out, to be
  /// repainted or showing an error.
  DiagnosticsNode describe() {
    final properties = DiagnosticPropertiesBuilder();
    debugFillProperties(properties);
    final at = parentData..debugFillProperties(properties);
    if (at.dx != 0 || at.dy != 0) {
      properties.addMessage('offset', '${at.dx},${at.dy}');
    }
    final c = _constraints;
    if (c != null) {
      properties.addMessage(
        'constraints',
        c.isTight ? 'tight' : describeConstraints(c),
      );
      if (_relayoutBoundary) {
        properties.flag(DiagnosticsFlag.relayoutBoundary);
      }
    }
    if (isRepaintBoundary) {
      properties.flag(DiagnosticsFlag.repaintBoundary);
    }
    if (_needsLayout) {
      properties.flag(DiagnosticsFlag.needsLayout);
    }
    if (_queued) {
      properties.flag(DiagnosticsFlag.needsPaint);
    }
    final error = debugError;
    if (error != null) {
      properties
        ..add('error', error)
        ..flag(DiagnosticsFlag.error);
    }
    final children = <DiagnosticsNode>[];
    visitChildren((child) => children.add(child.describe()));
    return properties.toNode(
      '$runtimeType',
      size: c == null ? null : (width, height),
      children: children,
    );
  }

  /// The column and row of this object's top left cell on the screen: its
  /// offset and its ancestors' added up, as the last layout placed them.
  (int, int) get globalOffset {
    var x = 0;
    var y = 0;
    for (RenderObject? o = this; o != null; o = o.parent) {
      x += o.parentData.dx;
      y += o.parentData.dy;
    }
    return (x, y);
  }

  /// How many ancestors this object has: 0 for the root. The owner lays
  /// out and paints what is marked outermost first, by depth.
  int get depth {
    var d = 0;
    for (var o = parent; o != null; o = o.parent) {
      d++;
    }
    return d;
  }
}

// --------------------------------------------------------------- objects --

bool _opaqueBackground(PaintContext ctx, int pen) {
  final p = ctx.canvas.styles.penOf(pen);
  return p.bg != null && p.bgAlpha == 255;
}

const _translucentBoundary =
    'a repaint boundary needs a pen with an opaque background';

// what text is measured with while detached: what a canvas made without a
// segmenter draws with
final _detachedSegmenter = TextSegmenter();
final _widthScan = ClusterScan();

/// Columns [s] takes when the canvas of [o]'s owner draws it
/// ([Canvas.shape]): a tab is one blank, other controls take none, and in
/// grapheme mode a mark without a base is dropped. Allocates nothing.
int _textWidth(RenderObject o, String s) {
  final seg = o.owner?.segmenter ?? _detachedSegmenter;
  final scan = _widthScan;
  final graphemes = seg.mode == TextMode.graphemes;
  var w = 0;
  for (var i = 0; i < s.length;) {
    final start = i;
    seg.scan(s, i, scan);
    i = scan.end;
    if (scan.width == 0) {
      if (scan.first == 0x09) {
        w++;
      }
    } else if (graphemes && isLeadingMark(scan.first)) {
      // re-segment what follows the dropped mark
      i = start + (scan.first > 0xFFFF ? 2 : 1);
    } else {
      w += scan.width;
    }
  }
  return w;
}

/// [extent] less [cells], at least 0.
int _less(int extent, int cells) => extent - cells < 0 ? 0 : extent - cells;

/// Whether a child after [child], in the list of a
/// [ContainerRenderObjectMixin], reaches the cells [x], [y], [w] × [h] of
/// their parent.
bool _laterReaches(RenderObject child, int x, int y, int w, int h) {
  for (
    var c = (child.parentData as ContainerParentDataMixin).nextSibling;
    c != null;
  ) {
    if (_reaches(c, x, y, w, h)) {
      return true;
    }
    c = (c.parentData as ContainerParentDataMixin).nextSibling;
  }
  return false;
}

/// Has [parent] paint the children after [child] that reach the cells
/// [x], [y], [w] × [h], in order; whatever they keep of what they painted
/// is forgotten.
void _paintLater(
  RenderObject parent,
  PaintContext ctx,
  RenderObject child,
  int x,
  int y,
  int w,
  int h,
) {
  for (
    var c = (child.parentData as ContainerParentDataMixin).nextSibling;
    c != null;
  ) {
    if (_reaches(c, x, y, w, h)) {
      parent.paintChild(ctx, c);
      _forgetPaint(c);
    }
    c = (c.parentData as ContainerParentDataMixin).nextSibling;
  }
}

/// Whether [c] reaches the cells [x], [y], [w] × [h] of its parent.
bool _reaches(RenderObject c, int x, int y, int w, int h) {
  final at = c.parentData;
  return at.dx < x + w &&
      x < at.dx + c.width &&
      at.dy < y + h &&
      y < at.dy + c.height;
}

/// Has [o] and everything inside it forget what they painted before
/// ([RenderObject.invalidatePaintCache]). What did not paint since it last
/// forgot has nothing to forget, nor has anything inside it: the walk
/// stops there.
void _forgetPaint(RenderObject o) {
  if (o._mayKeepPaint) {
    o
      .._mayKeepPaint = false
      ..invalidatePaintCache();
    final list = o._keepers;
    if (list != null) {
      // the children listed since it last forgot, not all of them: the
      // others have nothing to forget
      for (var i = 0; i < list.length; i++) {
        final c = list[i];
        if (identical(c._listedIn, o)) {
          c._listedIn = null;
          if (identical(c._parent, o)) {
            _forgetPaint(c);
          }
        }
      }
      list.clear();
      o._keepersCap = 16;
    }
  }
}

// what _forgetCut walks: the rows of the boundary it is under, and the row
// of the boundary the object whose children it visits is at
var _cutTop = 0;
var _cutBottom = 0;
var _cutAt = 0;

/// Has the objects inside [b], a boundary that has just repainted rows
/// [top] to [bottom] of its own, forget what they painted where those rows
/// cut through them ([RenderObject.invalidatePaintCache]): what they kept
/// of a paint that covered all of them holds only those rows now. What the
/// rows hold whole, or miss, keeps it.
void _forgetCut(RenderObject b, int top, int bottom) {
  _cutTop = top;
  _cutBottom = bottom;
  _cutAt = 0;
  _forgetCutKeepers(b);
}

/// Has [_forgetCutChild] visit the children of [o] that may keep paint.
void _forgetCutKeepers(RenderObject o) {
  final list = o._keepers;
  if (list == null) {
    return;
  }
  for (var i = 0; i < list.length; i++) {
    final c = list[i];
    if (identical(c._listedIn, o) && identical(c._parent, o)) {
      _forgetCutChild(c);
    }
  }
}

void _forgetCutChild(RenderObject c) {
  if (!c._mayKeepPaint) {
    return;
  }
  final y = _cutAt + c.parentData.dy;
  final end = y + c.height;
  if (end <= _cutTop ||
      y >= _cutBottom ||
      (y >= _cutTop && end <= _cutBottom)) {
    return;
  }
  c.invalidatePaintCache();
  final at = _cutAt;
  _cutAt = y;
  _forgetCutKeepers(c);
  _cutAt = at;
}
