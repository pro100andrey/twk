part of 'render.dart';

// ----------------------------------------------------------------- stack --

/// How a [RenderStack] lays out the children it places by its alignment.
enum StackFit {
  /// Each as big as it wants, up to as big as the stack may be.
  loose,

  /// Each as big as the stack may be.
  expand,

  /// Within the stack's own constraints.
  passthrough,
}

/// What a [RenderStack] keeps on a child: its offset, its siblings, and
/// where it is pinned, in cells. A child with any of these set is
/// *positioned*; an edge may be negative, putting the child partly
/// outside the stack.
final class StackParentData extends ParentData with ContainerParentDataMixin {
  /// The data of a child not laid out yet: not positioned, at the origin.
  StackParentData();

  /// Columns from the stack's left edge to the child's.
  int? left;

  /// Rows from the stack's top edge to the child's.
  int? top;

  /// Columns from the child's right edge to the stack's.
  int? right;

  /// Rows from the child's bottom edge to the stack's.
  int? bottom;

  /// The child's width; unused when [left] and [right] are both set.
  int? width;

  /// The child's height; unused when [top] and [bottom] are both set.
  int? height;

  /// Whether any edge or size is set.
  bool get isPositioned =>
      left != null ||
      top != null ||
      right != null ||
      bottom != null ||
      width != null ||
      height != null;

  /// The edges and sizes that are set.
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add('left', left, defaultValue: null)
      ..add('top', top, defaultValue: null)
      ..add('right', right, defaultValue: null)
      ..add('bottom', bottom, defaultValue: null)
      ..add('width', width, defaultValue: null)
      ..add('height', height, defaultValue: null);
  }
}

/// Lays its children out on top of each other and paints them in order: a
/// later child covers an earlier one where they overlap.
///
/// The children that are not positioned ([StackParentData.isPositioned])
/// are laid out first, within the constraints [fit] gives them, and
/// [alignment] places them; the stack is as big as the biggest of them,
/// within its constraints, or with none as big as its constraints allow
/// (as small along an axis they leave [BoxConstraints.unbounded]). Then
/// each positioned child, along each axis: with both edges set, exactly as
/// long as the cells between them; with its size set, that long;
/// otherwise as long as it wants, up to the stack's length less the edge
/// set. It goes where its edge says, or with neither edge set where
/// [alignment] puts it.
/// Whatever sticks out of the stack is cut off at its bounds.
///
/// A repaint boundary in a child that repaints on its own has the children
/// after it that reach its cells painted again over it ([paintOver]).
///
/// It asks for what the biggest of the children that are not positioned
/// asks for.
///
/// A badge pinned to the top right corner of a panel:
///
/// ```dart
/// final badge = RenderParagraph([(' 3 ', const Pen())]);
/// final stack = RenderStack(
///   fit: StackFit.expand,
///   children: [RenderBox(pen: StyleTable().pen(const Pen())), badge],
/// );
/// (badge.parentData as StackParentData)
///   ..top = 0
///   ..right = 0;
/// ```
final class RenderStack extends RenderObject
    with ContainerRenderObjectMixin<StackParentData> {
  /// A stack of [children], the first at the bottom; those not positioned
  /// at the top left and as big as they want, unless given.
  RenderStack({
    List<RenderObject>? children,
    this._alignment = Alignment.topLeft,
    this._fit = StackFit.loose,
  }) {
    addAll(children);
  }

  Alignment _alignment;

  /// Where the children not positioned go in the stack, and a positioned
  /// child along an axis it has neither edge set on.
  Alignment get alignment => _alignment;
  set alignment(Alignment a) {
    if (a != _alignment) {
      _alignment = a;
      markNeedsLayout();
    }
  }

  StackFit _fit;

  /// The constraints the children not positioned are laid out within.
  StackFit get fit => _fit;
  set fit(StackFit f) {
    if (f != _fit) {
      _fit = f;
      markNeedsLayout();
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    if (_alignment != Alignment.topLeft) {
      properties.addMessage('alignment', describeAlignment(_alignment));
    }
    properties.add('fit', _fit, defaultValue: StackFit.loose);
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! StackParentData) {
      child.parentData = StackParentData();
    }
  }

  @override
  void performLayout(BoxConstraints c) {
    // the children placed by the alignment first: the stack is as big as
    // the biggest
    var w = c.minW;
    var h = c.minH;
    var placed = false;
    for (var child = _firstChild; child != null;) {
      final at = child.parentData as StackParentData;
      if (!at.isPositioned) {
        placed = true;
        switch (_fit) {
          case StackFit.loose:
            _layoutChild(child, 0, c.maxW, 0, c.maxH);
          case StackFit.expand:
            _layoutChild(child, c.maxW, c.maxW, c.maxH, c.maxH);
          case StackFit.passthrough:
            _layoutChild(child, c.minW, c.maxW, c.minH, c.maxH);
        }
        w = child.width > w ? child.width : w;
        h = child.height > h ? child.height : h;
      }
      child = at.nextSibling;
    }
    if (placed) {
      width = c.constrainW(w);
      height = c.constrainH(h);
    } else {
      width = c.maxW < BoxConstraints.unbounded ? c.maxW : c.minW;
      height = c.maxH < BoxConstraints.unbounded ? c.maxH : c.minH;
    }
    for (var child = _firstChild; child != null;) {
      final at = child.parentData as StackParentData;
      if (at.isPositioned) {
        _layoutPositioned(child, at);
      } else {
        at
          ..dx = _alignment.dx(width - child.width)
          ..dy = _alignment.dy(height - child.height);
      }
      child = at.nextSibling;
    }
  }

  /// Lays a positioned [child] out and places it, as [at] pins it.
  void _layoutPositioned(RenderObject child, StackParentData at) {
    final left = at.left;
    final right = at.right;
    final top = at.top;
    final bottom = at.bottom;
    final int minW;
    final int maxW;
    if (left != null && right != null) {
      minW = maxW = _less(width - left, right);
    } else if (at.width != null) {
      minW = maxW = at.width!;
    } else {
      minW = 0;
      maxW = _less(width, left ?? right ?? 0);
    }
    final int minH;
    final int maxH;
    if (top != null && bottom != null) {
      minH = maxH = _less(height - top, bottom);
    } else if (at.height != null) {
      minH = maxH = at.height!;
    } else {
      minH = 0;
      maxH = _less(height, top ?? bottom ?? 0);
    }
    _layoutChild(child, minW, maxW, minH, maxH);
    at
      ..dx =
          left ??
          (right != null
              ? width - right - child.width
              : _alignment.dx(width - child.width))
      ..dy =
          top ??
          (bottom != null
              ? height - bottom - child.height
              : _alignment.dy(height - child.height));
  }

  // what the biggest child placed by the alignment asks for

  @override
  int computeMinIntrinsicWidth(int height) => _biggest(_minWidth, height);

  @override
  int computeMaxIntrinsicWidth(int height) => _biggest(_maxWidth, height);

  @override
  int computeMinIntrinsicHeight(int width) => _biggest(_minHeight, width);

  @override
  int computeMaxIntrinsicHeight(int width) => _biggest(_maxHeight, width);

  int _biggest(int kind, int extent) {
    var most = 0;
    for (var child = _firstChild; child != null;) {
      final at = child.parentData as StackParentData;
      if (!at.isPositioned) {
        final a = child._intrinsic(kind, extent);
        most = a > most ? a : most;
      }
      child = at.nextSibling;
    }
    return most;
  }

  @override
  void paint(PaintContext ctx) {
    for (var child = _firstChild; child != null;) {
      paintChild(ctx, child);
      child = (child.parentData as StackParentData).nextSibling;
    }
  }

  /// Whether a child after [child] reaches the cells.
  @override
  bool paintsOver(RenderObject child, int x, int y, int w, int h) =>
      _laterReaches(child, x, y, w, h);

  /// Paints the children after [child] that reach the cells, in order.
  /// They paint only those cells: whatever they keep of what they painted
  /// is forgotten.
  @override
  void paintOver(
    PaintContext ctx,
    RenderObject child,
    int x,
    int y,
    int w,
    int h,
  ) => _paintLater(this, ctx, child, x, y, w, h);
}
