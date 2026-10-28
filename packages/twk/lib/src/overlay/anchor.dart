/// Placing what an overlay shows by a widget under it: an [AnchorTarget]
/// around the widget and an [AnchorFollower] in the overlay's entry, joined
/// by an [AnchorLink]; and the arithmetic of it, which the menus place by
/// too ([offsetIn], [placeAlong]).
///
/// @docImport 'layer.dart';
/// @docImport 'popover.dart';
library;

import 'dart:typed_data' show Int32List;

import 'package:twk_core/twk_core.dart'
    show
        BoxConstraints,
        Canvas,
        HitTestResult,
        PaintContext,
        PipelineOwner,
        RenderObject,
        RenderObjectWithChildMixin;

import '../framework/framework.dart';
import '../layout/one_child.dart';

// Examples can assume:
// import 'package:twk/src/overlay/anchor.dart';

/// Where [target] is from [from], both as laid out last: the cell of
/// [from] that the top left of [target] is at; null when they are in no
/// tree together.
(int, int)? offsetIn(RenderObject from, RenderObject target) {
  if (from.owner == null || target.owner == null) {
    return null;
  }
  var a = from;
  var b = target;
  var ax = 0;
  var ay = 0;
  var bx = 0;
  var by = 0;
  var da = a.depth;
  var db = b.depth;
  for (; da > db; da--) {
    ax += a.parentData.dx;
    ay += a.parentData.dy;
    a = a.parent!;
  }
  for (; db > da; db--) {
    bx += b.parentData.dx;
    by += b.parentData.dy;
    b = b.parent!;
  }
  while (!identical(a, b)) {
    final pa = a.parent;
    final pb = b.parent;
    if (pa == null || pb == null) {
      return null;
    }
    ax += a.parentData.dx;
    ay += a.parentData.dy;
    bx += b.parentData.dx;
    by += b.parentData.dy;
    a = pa;
    b = pb;
  }
  return (bx - ax, by - ay);
}

/// Where a box [size] cells long goes on a line of [room] cells, by
/// something it is placed beside: at [after], past its end, when it fits
/// there; else on the side with more room, at [after] or ending at
/// [before], its start; moved in as far as it has to.
int placeAlong(int after, int before, int size, int room) {
  if (after >= 0 && after + size <= room) {
    return after;
  }
  return within(room - after >= before ? after : before - size, room - size);
}

/// [at] moved into 0..[most], or 0 when [most] is below 0.
int within(int at, int most) =>
    at > most ? (most < 0 ? 0 : most) : (at < 0 ? 0 : at);

/// What joins an [AnchorFollower] to the [AnchorTarget] it is placed by.
///
/// One link is given to one target and one follower, and kept by the
/// state that builds them:
///
/// ```dart
/// final link = AnchorLink();
/// final target = AnchorTarget(link: link, child: Text('File'));
/// final entry = OverlayEntry(
///   builder: (context) => AnchorFollower(link: link, child: Text('Open…')),
/// );
/// ```
final class AnchorLink {
  RenderAnchorTarget? _target;
  RenderAnchorFollower? _follower;

  /// Whether the cell [x], [y] of the follower is in what it shows or in
  /// the target, as placed last.
  bool covers(int x, int y) => _follower?._covers(x, y) ?? false;
}

/// [child], which the [AnchorFollower] of [link] is placed by: as big as
/// the child, and as small as the constraints allow without one.
///
/// See [AnchorLink] for the two in use; a [Popover] is the usual way to
/// show a widget by another.
final class AnchorTarget extends SingleChildRenderObjectWidget {
  /// Makes [child] the target of [link].
  const AnchorTarget({required this.link, super.child, super.key});

  /// What joins the target to its follower.
  final AnchorLink link;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderAnchorTarget createRenderObject(BuildContext context) =>
      RenderAnchorTarget(link);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderAnchorTarget renderObject,
  ) => renderObject.link = link;
}

/// As big as its child, which it lays out and paints as its own: what the
/// follower of [link] is placed by.
final class RenderAnchorTarget extends RenderObject
    with RenderObjectWithChildMixin {
  /// The target of [link] while it is attached.
  RenderAnchorTarget(this._link);

  AnchorLink _link;

  /// What joins it to its follower; set, it is the target of the new link
  /// and no longer of the old one, and the followers of both are placed
  /// again in the next frame.
  AnchorLink get link => _link;
  set link(AnchorLink l) {
    if (identical(l, _link)) {
      return;
    }
    final old = _link;
    if (identical(old._target, this)) {
      old._target = null;
    }
    _link = l;
    if (owner != null) {
      l._target = this;
    }
    old._follower?.markNeedsPaint();
    l._follower?.markNeedsPaint();
  }

  @override
  void attach(PipelineOwner o) {
    super.attach(o);
    _link._target = this;
  }

  @override
  void detach() {
    if (identical(_link._target, this)) {
      _link._target = null;
    }
    super.detach();
  }

  @override
  void performLayout(BoxConstraints c) {
    final child = this.child;
    if (child == null) {
      width = c.minW;
      height = c.minH;
      return;
    }
    child.layout(c, parentUsesSize: true);
    width = child.width;
    height = child.height;
    // a follower as wide as it at least is laid out again, in this frame
    final follower = _link._follower;
    if (follower != null &&
        follower._matchTargetWidth &&
        follower._targetWidth != width) {
      follower.markNeedsLayout();
    }
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
  void paint(PaintContext ctx) {
    final child = this.child;
    if (child != null) {
      paintChild(ctx, child);
    }
  }
}

/// Places [child] by the [AnchorTarget] of [link], over all of an overlay:
/// see [RenderAnchorFollower].
///
/// See [AnchorLink] for the two in use.
final class AnchorFollower extends SingleChildRenderObjectWidget {
  /// Places [child] by the target of [link], from its left edge or, when
  /// [centred], centred on it.
  const AnchorFollower({
    required this.link,
    super.child,
    super.key,
    this.centred = false,
    this.matchTargetWidth = false,
  });

  /// What joins the follower to its target.
  final AnchorLink link;

  /// Whether the child is centred on the target across, rather than from
  /// its left edge.
  final bool centred;

  /// Whether the child is at least as wide as the target: a list under a
  /// field.
  final bool matchTargetWidth;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderAnchorFollower createRenderObject(BuildContext context) =>
      RenderAnchorFollower(
        link,
        centred: centred,
        matchTargetWidth: matchTargetWidth,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderAnchorFollower renderObject,
  ) => renderObject
    ..link = link
    ..centred = centred
    ..matchTargetWidth = matchTargetWidth;
}

/// As big as it may be: lays its child out as small as it likes and places
/// it by the target of [link], from where the target is as this object
/// paints: under the target, or where it does not fit there on the side
/// with more room, above it; from its left edge, or where it does not fit
/// there on the side with more room, ending at its right edge; or, when
/// [centred], centred on it. It is moved in as far as it has to. Shows
/// nothing while the target is in no tree with it.
///
/// It places the child where the target is when it paints, in the frame
/// the target moves in, wherever that is: a target moves without marking
/// it. Before a frame paints, it marks the child when the target has moved
/// it ([RenderObject.beforePaint]); with any rows of its repaint boundary,
/// it repaints the rows the child was on and those it goes to, and only
/// those ([RenderObject.wholeRows]). Where a frame paints it without
/// repainting all of the rows the child goes to, the child stays where it
/// was until the next frame, which repaints all of this object.
final class RenderAnchorFollower extends RenderObject
    with RenderObjectWithChildMixin {
  /// The follower of [link], placing its child from the target's left
  /// edge or, when [centred], centred on it; with [matchTargetWidth] at
  /// least as wide as the target.
  RenderAnchorFollower(
    this._link, {
    required this._centred,
    this._matchTargetWidth = false,
  }) {
    repaintedWhole = true;
    checkedBeforePaint = true;
  }

  AnchorLink _link;

  /// What joins it to its target; set, it follows the target of the new
  /// link.
  AnchorLink get link => _link;
  set link(AnchorLink l) {
    if (identical(l, _link)) {
      return;
    }
    if (identical(_link._follower, this)) {
      _link._follower = null;
    }
    _link = l;
    if (owner != null) {
      l._follower = this;
    }
    markNeedsLayout();
  }

  bool _centred;

  /// Whether the child is centred on the target across, rather than from
  /// its left edge.
  bool get centred => _centred;
  set centred(bool c) {
    if (c != _centred) {
      _centred = c;
      markNeedsLayout();
    }
  }

  bool _matchTargetWidth;

  /// Whether the child is laid out at least as wide as the target (as far
  /// as this object is): the target laid out at another width lays it out
  /// again, in the same frame.
  bool get matchTargetWidth => _matchTargetWidth;
  set matchTargetWidth(bool m) {
    if (m != _matchTargetWidth) {
      _matchTargetWidth = m;
      markNeedsLayout();
    }
  }

  // the target's width the child was laid out by last; null for none
  int? _targetWidth;

  // where the target is from this object, as the child was placed last;
  // null while it is not
  (int, int)? _targetAt;

  // where _where puts the child
  var _whereX = 0;
  var _whereY = 0;

  @override
  void attach(PipelineOwner o) {
    super.attach(o);
    _link._follower = this;
  }

  @override
  void detach() {
    if (identical(_link._follower, this)) {
      _link._follower = null;
    }
    super.detach();
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW < BoxConstraints.unbounded ? c.maxW : c.minW;
    height = c.maxH < BoxConstraints.unbounded ? c.maxH : c.minH;
    final target = _link._target;
    final targetWidth = _matchTargetWidth && target != null
        ? target.width
        : null;
    _targetWidth = targetWidth;
    final least = targetWidth == null
        ? 0
        : (targetWidth < width ? targetWidth : width);
    child?.layout(
      BoxConstraints(least, width, 0, height),
      parentUsesSize: true,
    );
    _place();
  }

  /// Places the child by where the target is now.
  void _place() {
    final at = _targetAt = _where();
    if (at != null) {
      child!.parentData
        ..dx = _whereX
        ..dy = _whereY;
    }
  }

  /// Where the target is now from this object, and the child goes by it at
  /// [_whereX], [_whereY]; null when it is not shown.
  (int, int)? _where() {
    final child = this.child;
    final target = _link._target;
    final at = child == null || target == null ? null : offsetIn(this, target);
    if (child == null || target == null || at == null) {
      return null;
    }
    final (tx, ty) = at;
    final w = child.width;
    final h = child.height;
    _whereX = _centred
        ? within(tx + (target.width - w) ~/ 2, width - w)
        : placeAlong(tx, tx + target.width, w, width);
    _whereY = placeAlong(ty + target.height, ty, h, height);
    return at;
  }

  /// Marks the child, where it was placed last, when the target has moved
  /// it: the boundary repaints rows of it, and with them those of
  /// [wholeRows].
  @override
  void beforePaint() {
    final child = this.child;
    if (child == null) {
      return;
    }
    final shown = _where() != null;
    final p = child.parentData;
    if (shown != (_targetAt != null) ||
        (shown && (p.dx != _whereX || p.dy != _whereY))) {
      child.markNeedsPaint();
    }
  }

  /// The rows the child was placed on last, joined with those it goes to
  /// now, as far as it is shown on either.
  @override
  void wholeRows(Int32List rows) {
    final child = this.child;
    var top = 0;
    var bottom = 0;
    if (child != null) {
      if (_targetAt != null) {
        top = child.parentData.dy;
        bottom = top + child.height;
      }
      if (_where() != null) {
        final t = _whereY;
        final b = t + child.height;
        if (top >= bottom) {
          top = t;
          bottom = b;
        } else {
          top = t < top ? t : top;
          bottom = b > bottom ? b : bottom;
        }
      }
    }
    rows
      ..[0] = top
      ..[1] = bottom;
  }

  bool _covers(int x, int y) {
    final at = _targetAt;
    final target = _link._target;
    final child = this.child;
    if (at == null || target == null || child == null) {
      return false;
    }
    final (tx, ty) = at;
    final p = child.parentData;
    return _inside(x - p.dx, y - p.dy, child.width, child.height) ||
        _inside(x - tx, y - ty, target.width, target.height);
  }

  static bool _inside(int x, int y, int w, int h) =>
      x >= 0 && y >= 0 && x < w && y < h;

  @override
  bool hitTestChildren(HitTestResult result, int x, int y) =>
      _targetAt != null && super.hitTestChildren(result, x, y);

  @override
  void paint(PaintContext ctx) {
    final child = this.child;
    if (child == null) {
      return;
    }
    final was = _targetAt;
    final p = child.parentData;
    final dx = p.dx;
    final dy = p.dy;
    _place();
    if (_targetAt != null &&
        (was == null || p.dy != dy) &&
        !_repainted(ctx.canvas, p.dy, child.height)) {
      // moved to rows this frame leaves as they are: where it was until
      // the next frame
      _targetAt = was;
      p
        ..dx = dx
        ..dy = dy;
      markNeedsPaint();
    }
    if (_targetAt != null) {
      paintChild(ctx, child);
    }
  }

  /// Whether the rows [dy] to [dy] + [h] of this object are all in the
  /// clip of [canvas], as far as this object has them: whether the frame
  /// repaints what is under them.
  bool _repainted(Canvas canvas, int dy, int h) {
    var y = 0;
    for (RenderObject? o = this; o != null; o = o.parent) {
      y += o.parentData.dy;
    }
    final top = y + (dy < 0 ? 0 : dy);
    final bottom = y + (dy + h > height ? height : dy + h);
    final (_, y0, _, y1) = canvas.clipBounds;
    return top >= bottom || (y0 <= top && y1 >= bottom);
  }
}
