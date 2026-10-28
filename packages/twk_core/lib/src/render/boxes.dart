part of 'render.dart';

// ------------------------------------------- padding, alignment, sizing --

/// Fills its bounds with [pen] and paints [child] inside them, [padX]
/// columns in from the left and right and [padY] rows in from the top and
/// bottom.
///
/// It is as big as its constraints allow ([sizedByParent]), and lays its
/// child out with no minimum, at most as big as the box less the padding.
/// A repaint boundary when [boundary] is set: [pen] then needs an opaque
/// background.
///
/// A panel two rows by four columns larger than its text:
///
/// ```dart
/// final styles = StyleTable();
/// final panel = RenderBox(
///   pen: styles.pen(const Pen(bg: Color.rgb(30, 30, 60))),
///   padX: 2,
///   padY: 1,
///   child: RenderText('Ready', styles.pen(const Pen())),
/// );
/// ```
///
/// See also:
///
///  * [RenderPadding], which insets a child without a fill and is as big
///    as the child.
///  * [RenderDecoratedBox], a box with a border and titles.
final class RenderBox extends RenderObject with RenderObjectWithChildMixin {
  /// A box filled with [pen] around [child], if any, inset by [padX] and
  /// [padY]; a repaint boundary when [boundary] is set.
  RenderBox({
    required this._pen,
    RenderObject? child,
    this.padX = 0,
    this.padY = 0,
    this.boundary = false,
  }) {
    if (child != null) {
      this.child = child;
    }
  }

  int _pen;

  /// The id of the pen every cell of the box is filled with, in the style
  /// table it is painted with; a new one only repaints it.
  int get pen => _pen;
  set pen(int p) {
    if (p != _pen) {
      _pen = p;
      markNeedsPaint();
    }
  }

  /// The columns between each side of the box and its child; 0 by
  /// default.
  final int padX;

  /// The rows between the top and bottom of the box and its child; 0 by
  /// default.
  final int padY;

  /// Whether the box is a repaint boundary ([isRepaintBoundary]): what
  /// changes inside it repaints the box alone. False by default.
  final bool boundary;

  @override
  bool get isRepaintBoundary => boundary;

  @override
  bool get sizedByParent => true;

  /// Opaque: it fills all of its cells.
  @override
  HitTestBehavior get hitTestBehavior => HitTestBehavior.opaque;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add('pen', _pen)
      ..add('padX', padX, defaultValue: 0)
      ..add('padY', padY, defaultValue: 0);
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
    final ch = _child;
    if (ch != null) {
      final w = width - 2 * padX < 0 ? 0 : width - 2 * padX;
      final h = height - 2 * padY < 0 ? 0 : height - 2 * padY;
      ch.layout(BoxConstraints(0, w, 0, h));
      ch.parentData
        ..dx = padX
        ..dy = padY;
    }
  }

  // what the child asks for inside the padding, plus the padding

  @override
  int computeMinIntrinsicWidth(int height) =>
      2 * padX + (_child?.getMinIntrinsicWidth(_less(height, 2 * padY)) ?? 0);

  @override
  int computeMaxIntrinsicWidth(int height) =>
      2 * padX + (_child?.getMaxIntrinsicWidth(_less(height, 2 * padY)) ?? 0);

  @override
  int computeMinIntrinsicHeight(int width) =>
      2 * padY + (_child?.getMinIntrinsicHeight(_less(width, 2 * padX)) ?? 0);

  @override
  int computeMaxIntrinsicHeight(int width) =>
      2 * padY + (_child?.getMaxIntrinsicHeight(_less(width, 2 * padX)) ?? 0);

  @override
  void paint(PaintContext ctx) {
    assert(!boundary || _opaqueBackground(ctx, pen), _translucentBoundary);
    ctx.canvas.fill(0, 0, width, height, pen);
    if (_child != null) {
      paintChild(ctx, _child!);
    }
  }
}

/// Empty cells on each side of a box: [left], [top], [right] and
/// [bottom], each 0 or more.
///
/// ```dart
/// const insets = EdgeInsets.only(left: 2, top: 1);
/// assert(insets.horizontal == 2 && insets.vertical == 1);
/// assert(const EdgeInsets.x(1) == const EdgeInsets.only(left: 1, right: 1));
/// ```
///
/// See also:
///
///  * [RenderPadding] and [RenderDecoratedBox.padding], which inset a
///    child by them.
final class EdgeInsets {
  /// [left], [top], [right] and [bottom] cells on those sides, each 0
  /// unless given.
  const EdgeInsets.only({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  }) : assert(
         left >= 0 && top >= 0 && right >= 0 && bottom >= 0,
         'insets of 0 cells or more',
       );

  /// [cells] on every side.
  const EdgeInsets.all(int cells)
    : this.only(left: cells, top: cells, right: cells, bottom: cells);

  /// [cells] on the left and on the right.
  const EdgeInsets.x(int cells) : this.only(left: cells, right: cells);

  /// [cells] above and below.
  const EdgeInsets.y(int cells) : this.only(top: cells, bottom: cells);

  /// No cells on any side.
  static const zero = EdgeInsets.only();

  /// The columns on the left.
  final int left;

  /// The rows above.
  final int top;

  /// The columns on the right.
  final int right;

  /// The rows below.
  final int bottom;

  /// The cells on the left and on the right together.
  int get horizontal => left + right;

  /// The cells above and below together.
  int get vertical => top + bottom;

  @override
  bool operator ==(Object other) =>
      other is EdgeInsets &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;
  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

/// Where a child goes in the cells its parent leaves around it, along each
/// axis: at the start (-1), in the middle (0) or at the end (1). In the
/// middle the odd cell goes after the child; a child bigger than its parent
/// sticks out by the odd cell more after it than before.
///
/// ```dart
/// // 3 columns left over: the child is 1 in from the left, 2 from the right
/// assert(Alignment.center.dx(3) == 1);
/// assert(Alignment.bottomRight.dy(4) == 4);
/// ```
///
/// See also:
///
///  * [RenderPositionedBox], [RenderStack] and [RenderFractionallySizedBox],
///    which place a child by one.
final class Alignment {
  /// Along the columns at [x] and along the rows at [y], each -1 for the
  /// start, 0 for the middle or 1 for the end.
  const Alignment(this.x, this.y)
    : assert(x >= -1 && x <= 1 && y >= -1 && y <= 1, '-1, 0 or 1');

  /// Where the child goes across: -1 at the left, 0 in the middle, 1 at
  /// the right.
  final int x;

  /// Where the child goes down: -1 at the top, 0 in the middle, 1 at the
  /// bottom.
  final int y;

  /// At the top left corner.
  static const topLeft = Alignment(-1, -1);

  /// At the top, in the middle across.
  static const topCenter = Alignment(0, -1);

  /// At the top right corner.
  static const topRight = Alignment(1, -1);

  /// At the left, in the middle down.
  static const centerLeft = Alignment(-1, 0);

  /// In the middle both ways.
  static const center = Alignment(0, 0);

  /// At the right, in the middle down.
  static const centerRight = Alignment(1, 0);

  /// At the bottom left corner.
  static const bottomLeft = Alignment(-1, 1);

  /// At the bottom, in the middle across.
  static const bottomCenter = Alignment(0, 1);

  /// At the bottom right corner.
  static const bottomRight = Alignment(1, 1);

  /// The columns left of a child when [free] columns are left over around
  /// it (fewer than 0 when the child is the wider one).
  int dx(int free) => free * (x + 1) ~/ 2;

  /// The rows above a child when [free] rows are left over around it.
  int dy(int free) => free * (y + 1) ~/ 2;

  @override
  bool operator ==(Object other) =>
      other is Alignment && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
}

/// [c] as a description shows it: the widths, `×`, the heights, each as
/// `min..max` or one number where they agree, [BoxConstraints.unbounded]
/// as `∞` (`80×24`, `0..80×1`, `0..∞×0..24`).
String describeConstraints(BoxConstraints c) =>
    '${_range(c.minW, c.maxW)}×${_range(c.minH, c.maxH)}';

String _range(int min, int max) =>
    min >= max ? _extent(min) : '${_extent(min)}..${_extent(max)}';

String _extent(int cells) => cells >= BoxConstraints.unbounded ? '∞' : '$cells';

/// [e] as a description shows it: the cells above, right, below and left,
/// as CSS writes them, those that repeat the opposite side's left out
/// (`1`, `0 1`, `1 2 0`, `1 2 0 3`).
String describeInsets(EdgeInsets e) => e.left != e.right
    ? '${e.top} ${e.right} ${e.bottom} ${e.left}'
    : e.top != e.bottom
    ? '${e.top} ${e.right} ${e.bottom}'
    : e.top != e.right
    ? '${e.top} ${e.right}'
    : '${e.top}';

/// [a] as a description shows it: the name of the constant it equals,
/// `topLeft`, `center` and the rest.
String describeAlignment(Alignment a) => const [
  'topLeft',
  'topCenter',
  'topRight',
  'centerLeft',
  'center',
  'centerRight',
  'bottomLeft',
  'bottomCenter',
  'bottomRight',
][3 * (a.y + 1) + a.x + 1];

/// Lays its child out inside [padding]: it is as big as the child and the
/// padding, within its constraints, and the child is [EdgeInsets.left]
/// columns in and [EdgeInsets.top] rows down. Without a child it is as big
/// as the padding.
final class RenderPadding extends RenderObject with RenderObjectWithChildMixin {
  /// Insets [child], if any, by [padding].
  RenderPadding({required this._padding, RenderObject? child}) {
    this.child = child;
  }

  EdgeInsets _padding;

  /// The empty cells on each side of the child; a new one lays the box out
  /// again.
  EdgeInsets get padding => _padding;
  set padding(EdgeInsets p) {
    if (p != _padding) {
      _padding = p;
      markNeedsLayout();
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.addMessage('padding', describeInsets(_padding));
  }

  @override
  void performLayout(BoxConstraints c) {
    final p = _padding;
    final h = p.horizontal;
    final v = p.vertical;
    final child = _child;
    if (child == null) {
      width = c.constrainW(h);
      height = c.constrainH(v);
      return;
    }
    _layoutChild(
      child,
      _less(c.minW, h),
      _less(c.maxW, h),
      _less(c.minH, v),
      _less(c.maxH, v),
    );
    width = c.constrainW(child.width + h);
    height = c.constrainH(child.height + v);
    child.parentData
      ..dx = p.left
      ..dy = p.top;
  }

  // what the child asks for inside the padding, plus the padding

  @override
  int computeMinIntrinsicWidth(int height) =>
      _padding.horizontal +
      (_child?.getMinIntrinsicWidth(_less(height, _padding.vertical)) ?? 0);

  @override
  int computeMaxIntrinsicWidth(int height) =>
      _padding.horizontal +
      (_child?.getMaxIntrinsicWidth(_less(height, _padding.vertical)) ?? 0);

  @override
  int computeMinIntrinsicHeight(int width) =>
      _padding.vertical +
      (_child?.getMinIntrinsicHeight(_less(width, _padding.horizontal)) ?? 0);

  @override
  int computeMaxIntrinsicHeight(int width) =>
      _padding.vertical +
      (_child?.getMaxIntrinsicHeight(_less(width, _padding.horizontal)) ?? 0);

  @override
  void paint(PaintContext ctx) {
    final c = _child;
    if (c != null) {
      paintChild(ctx, c);
    }
  }
}

/// Places its child inside itself as [alignment] says, the child laid out
/// within the box's own constraints with no minimum. Along an axis with a
/// factor ([widthFactor], [heightFactor]) the box is that many times as
/// long as its child, within its constraints; along one without, as long as
/// they allow. Without a child, an axis with a factor is as short as the
/// constraints allow.
final class RenderPositionedBox extends RenderObject
    with RenderObjectWithChildMixin {
  /// Places [child], if any, as [alignment] says, in the middle unless
  /// given; [widthFactor] and [heightFactor], 0 or more, null unless given.
  RenderPositionedBox({
    this._alignment = Alignment.center,
    this._widthFactor,
    this._heightFactor,
    RenderObject? child,
  }) : assert(
         (_widthFactor ?? 0) >= 0 && (_heightFactor ?? 0) >= 0,
         'a factor of 0 or more',
       ) {
    this.child = child;
  }

  Alignment _alignment;

  /// Where the child goes in the cells the box leaves around it.
  Alignment get alignment => _alignment;
  set alignment(Alignment a) {
    if (a != _alignment) {
      _alignment = a;
      markNeedsLayout();
    }
  }

  int? _widthFactor;

  /// How many times as wide as its child the box is, within its
  /// constraints; null, as wide as they allow.
  int? get widthFactor => _widthFactor;
  set widthFactor(int? f) {
    assert((f ?? 0) >= 0, 'a factor of 0 or more');
    if (f != _widthFactor) {
      _resized();
      _widthFactor = f;
    }
  }

  int? _heightFactor;

  /// How many times as tall as its child the box is, within its
  /// constraints; null, as tall as they allow.
  int? get heightFactor => _heightFactor;
  set heightFactor(int? f) {
    assert((f ?? 0) >= 0, 'a factor of 0 or more');
    if (f != _heightFactor) {
      _resized();
      _heightFactor = f;
    }
  }

  /// Without factors it is as big as the constraints allow.
  @override
  bool get sizedByParent => _widthFactor == null && _heightFactor == null;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..addMessage('alignment', describeAlignment(_alignment))
      ..add('widthFactor', _widthFactor, defaultValue: null)
      ..add('heightFactor', _heightFactor, defaultValue: null);
  }

  /// Lays this box out again for a factor about to change, and its parent
  /// too while the box is sized by the constraints alone: as a relayout
  /// boundary its new size would not reach the parent.
  void _resized() {
    if (sizedByParent) {
      parent?.markNeedsLayout();
    }
    markNeedsLayout();
  }

  @override
  void performLayout(BoxConstraints c) {
    final wf = _widthFactor;
    final hf = _heightFactor;
    final child = _child;
    if (child == null) {
      width = wf == null ? c.maxW : c.minW;
      height = hf == null ? c.maxH : c.minH;
      return;
    }
    _layoutChild(child, 0, c.maxW, 0, c.maxH);
    width = wf == null ? c.maxW : c.constrainW(child.width * wf);
    height = hf == null ? c.maxH : c.constrainH(child.height * hf);
    child.parentData
      ..dx = _alignment.dx(width - child.width)
      ..dy = _alignment.dy(height - child.height);
  }

  // what the child asks for, times the factors

  @override
  int computeMinIntrinsicWidth(int height) =>
      (_child?.getMinIntrinsicWidth(height) ?? 0) * (_widthFactor ?? 1);

  @override
  int computeMaxIntrinsicWidth(int height) =>
      (_child?.getMaxIntrinsicWidth(height) ?? 0) * (_widthFactor ?? 1);

  @override
  int computeMinIntrinsicHeight(int width) =>
      (_child?.getMinIntrinsicHeight(width) ?? 0) * (_heightFactor ?? 1);

  @override
  int computeMaxIntrinsicHeight(int width) =>
      (_child?.getMaxIntrinsicHeight(width) ?? 0) * (_heightFactor ?? 1);

  @override
  void paint(PaintContext ctx) {
    final c = _child;
    if (c != null) {
      paintChild(ctx, c);
    }
  }
}

/// Lays its child out within [additionalConstraints] as well as its own
/// constraints: each limit of [additionalConstraints] is kept within its
/// constraints. It is as big as its child, or without one as small as the
/// two allow.
final class RenderConstrainedBox extends RenderObject
    with RenderObjectWithChildMixin {
  /// Lays [child], if any, out within [additionalConstraints] too.
  RenderConstrainedBox({
    required this._additionalConstraints,
    RenderObject? child,
  }) {
    this.child = child;
  }

  BoxConstraints _additionalConstraints;

  /// The limits the box puts on its child besides its own constraints,
  /// each held within those; a new one lays the box out again.
  BoxConstraints get additionalConstraints => _additionalConstraints;
  set additionalConstraints(BoxConstraints a) {
    if (a != _additionalConstraints) {
      _additionalConstraints = a;
      markNeedsLayout();
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.addMessage(
      'additionalConstraints',
      describeConstraints(_additionalConstraints),
    );
  }

  @override
  void performLayout(BoxConstraints c) {
    final a = _additionalConstraints;
    final minW = c.constrainW(a.minW);
    final minH = c.constrainH(a.minH);
    final child = _child;
    if (child == null) {
      width = minW;
      height = minH;
      return;
    }
    _layoutChild(child, minW, c.constrainW(a.maxW), minH, c.constrainH(a.maxH));
    width = child.width;
    height = child.height;
  }

  // what the child asks for within the additional constraints: their
  // extent when it is tight, without asking the child; the child's answer
  // when their minimum is unbounded

  @override
  int computeMinIntrinsicWidth(int height) => _width(_minWidth, height);

  @override
  int computeMaxIntrinsicWidth(int height) => _width(_maxWidth, height);

  @override
  int computeMinIntrinsicHeight(int width) => _height(_minHeight, width);

  @override
  int computeMaxIntrinsicHeight(int width) => _height(_maxHeight, width);

  int _width(int kind, int height) {
    final a = _additionalConstraints;
    if (a.minW >= a.maxW && a.maxW < BoxConstraints.unbounded) {
      return a.minW;
    }
    final w = _child?._intrinsic(kind, height) ?? 0;
    return a.minW >= BoxConstraints.unbounded ? w : a.constrainW(w);
  }

  int _height(int kind, int width) {
    final a = _additionalConstraints;
    if (a.minH >= a.maxH && a.maxH < BoxConstraints.unbounded) {
      return a.minH;
    }
    final h = _child?._intrinsic(kind, width) ?? 0;
    return a.minH >= BoxConstraints.unbounded ? h : a.constrainH(h);
  }

  @override
  void paint(PaintContext ctx) {
    final c = _child;
    if (c != null) {
      paintChild(ctx, c);
    }
  }
}

/// [extent] cells times [factor], rounded to the nearest cell, a half up;
/// [BoxConstraints.unbounded] at most.
int _fraction(int extent, double factor) {
  final cells = extent * factor;
  return cells >= BoxConstraints.unbounded
      ? BoxConstraints.unbounded
      : cells.round();
}

/// The fewest cells whose [_fraction] of [factor] is [cells] or more; 0 for
/// a factor of 0, of which no extent gives any.
int _extentFor(int cells, double factor) {
  if (cells <= 0 || factor <= 0) {
    return 0;
  }
  final at = (cells - 0.5) / factor;
  if (at >= BoxConstraints.unbounded) {
    return BoxConstraints.unbounded;
  }
  // the guess is off by a cell at most, where a product rounds the other way
  var extent = at.ceil();
  while (_fraction(extent, factor) < cells) {
    extent++;
  }
  while (extent > 0 && _fraction(extent - 1, factor) >= cells) {
    extent--;
  }
  return extent;
}

/// Lays its child out at fractions of the most room it may take:
/// [widthFactor] of its max width wide and [heightFactor] of its max height
/// tall, each rounded to the nearest cell, a half up (a third of 10 cells
/// is 3, a half of 5 is 3). Along an axis without a factor, or one its
/// constraints leave unbounded, the child is laid out within them. The box
/// is as big as its constraints allow, as long as its child along an
/// unbounded axis, and places the child as [alignment] says; a child bigger
/// than it (a factor above 1) sticks out and is cut off. Without a child it
/// is as short as the constraints allow along an unbounded axis.
final class RenderFractionallySizedBox extends RenderObject
    with RenderObjectWithChildMixin {
  /// Lays [child], if any, out at [widthFactor] and [heightFactor] of the
  /// room the box may take, each finite and 0 or more, or null; places it
  /// as [alignment] says, in the middle unless given.
  RenderFractionallySizedBox({
    this._alignment = Alignment.center,
    this._widthFactor,
    this._heightFactor,
    RenderObject? child,
  }) : assert(
         _isFactor(_widthFactor) && _isFactor(_heightFactor),
         'a finite factor of 0 or more',
       ) {
    this.child = child;
  }

  static bool _isFactor(double? f) => f == null || f >= 0 && f.isFinite;

  Alignment _alignment;

  /// Where the child goes in the box: in the cells it leaves around the
  /// child, or, for a child bigger than the box, where it sticks out.
  Alignment get alignment => _alignment;
  set alignment(Alignment a) {
    if (a != _alignment) {
      _alignment = a;
      markNeedsLayout();
    }
  }

  double? _widthFactor;

  /// The fraction of the box's max width the child is wide, rounded to the
  /// nearest cell; null, the child is laid out within the box's
  /// constraints across.
  double? get widthFactor => _widthFactor;
  set widthFactor(double? f) {
    assert(_isFactor(f), 'a finite factor of 0 or more');
    if (f != _widthFactor) {
      _widthFactor = f;
      markNeedsLayout();
    }
  }

  double? _heightFactor;

  /// The fraction of the box's max height the child is tall, rounded to
  /// the nearest cell; null, the child is laid out within the box's
  /// constraints down.
  double? get heightFactor => _heightFactor;
  set heightFactor(double? f) {
    assert(_isFactor(f), 'a finite factor of 0 or more');
    if (f != _heightFactor) {
      _heightFactor = f;
      markNeedsLayout();
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..addMessage('alignment', describeAlignment(_alignment))
      ..add('widthFactor', _widthFactor, defaultValue: null)
      ..add('heightFactor', _heightFactor, defaultValue: null);
  }

  @override
  void performLayout(BoxConstraints c) {
    const unbounded = BoxConstraints.unbounded;
    final child = _child;
    if (child == null) {
      width = c.maxW < unbounded ? c.maxW : c.minW;
      height = c.maxH < unbounded ? c.maxH : c.minH;
      return;
    }
    var minW = c.minW;
    var maxW = c.maxW;
    var minH = c.minH;
    var maxH = c.maxH;
    final wf = _widthFactor;
    if (wf != null && maxW < unbounded) {
      minW = maxW = _fraction(c.maxW, wf);
    }
    final hf = _heightFactor;
    if (hf != null && maxH < unbounded) {
      minH = maxH = _fraction(c.maxH, hf);
    }
    _layoutChild(child, minW, maxW, minH, maxH);
    width = c.maxW < unbounded ? c.maxW : c.constrainW(child.width);
    height = c.maxH < unbounded ? c.maxH : c.constrainH(child.height);
    child.parentData
      ..dx = _alignment.dx(width - child.width)
      ..dy = _alignment.dy(height - child.height);
  }

  // what the child asks for at its fraction of the extent, as the extent
  // whose fraction that is

  @override
  int computeMinIntrinsicWidth(int height) => _width(_minWidth, height);

  @override
  int computeMaxIntrinsicWidth(int height) => _width(_maxWidth, height);

  @override
  int computeMinIntrinsicHeight(int width) => _height(_minHeight, width);

  @override
  int computeMaxIntrinsicHeight(int width) => _height(_maxHeight, width);

  int _width(int kind, int height) {
    final child = _child;
    if (child == null) {
      return 0;
    }
    final hf = _heightFactor;
    final w = child._intrinsic(
      kind,
      hf == null || height >= BoxConstraints.unbounded
          ? height
          : _fraction(height, hf),
    );
    final wf = _widthFactor;
    return wf == null ? w : _extentFor(w, wf);
  }

  int _height(int kind, int width) {
    final child = _child;
    if (child == null) {
      return 0;
    }
    final wf = _widthFactor;
    final h = child._intrinsic(
      kind,
      wf == null || width >= BoxConstraints.unbounded
          ? width
          : _fraction(width, wf),
    );
    final hf = _heightFactor;
    return hf == null ? h : _extentFor(h, hf);
  }

  @override
  void paint(PaintContext ctx) {
    final c = _child;
    if (c != null) {
      paintChild(ctx, c);
    }
  }
}

/// [cells] rounded up to a multiple of [step], when given.
int _step(int cells, int? step) =>
    step == null || cells >= BoxConstraints.unbounded
    ? cells
    : (cells + step - 1) ~/ step * step;

/// Makes its child as wide as the child would like to be: its max
/// intrinsic width at the most height the box may have, rounded up to a
/// multiple of [stepWidth] when given, within the constraints (a tight
/// width stays as it is). With [stepHeight], the child is also as tall as
/// it would like to be at that width, rounded up to a multiple of it. The
/// box is as big as its child; without one, as small as the constraints
/// allow.
final class RenderIntrinsicWidth extends RenderObject
    with RenderObjectWithChildMixin {
  /// Makes [child], if any, as wide as it would like to be, rounded up to
  /// [stepWidth] and [stepHeight] where given, each 1 or more.
  RenderIntrinsicWidth({this._stepWidth, this._stepHeight, RenderObject? child})
    : assert(
        (_stepWidth ?? 1) > 0 && (_stepHeight ?? 1) > 0,
        'a step of 1 cell or more',
      ) {
    this.child = child;
  }

  int? _stepWidth;

  /// What the child's width is rounded up to a multiple of; null for no
  /// rounding.
  int? get stepWidth => _stepWidth;
  set stepWidth(int? s) {
    assert((s ?? 1) > 0, 'a step of 1 cell or more');
    if (s != _stepWidth) {
      _stepWidth = s;
      markNeedsLayout();
    }
  }

  int? _stepHeight;

  /// What the child's height, as tall as it would like to be at its width,
  /// is rounded up to a multiple of; null to lay the child out within the
  /// box's constraints down.
  int? get stepHeight => _stepHeight;
  set stepHeight(int? s) {
    assert((s ?? 1) > 0, 'a step of 1 cell or more');
    if (s != _stepHeight) {
      _stepHeight = s;
      markNeedsLayout();
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add('stepWidth', _stepWidth, defaultValue: null)
      ..add('stepHeight', _stepHeight, defaultValue: null);
  }

  @override
  void performLayout(BoxConstraints c) {
    final child = _child;
    if (child == null) {
      width = c.minW;
      height = c.minH;
      return;
    }
    var minW = c.minW;
    var maxW = c.maxW;
    var minH = c.minH;
    var maxH = c.maxH;
    if (minW < maxW) {
      minW = maxW = c.constrainW(
        _step(child.getMaxIntrinsicWidth(maxH), _stepWidth),
      );
    }
    final step = _stepHeight;
    if (step != null) {
      minH = maxH = c.constrainH(
        _step(child.getMaxIntrinsicHeight(maxW), step),
      );
    }
    _layoutChild(child, minW, maxW, minH, maxH);
    width = child.width;
    height = child.height;
  }

  // as wide as the child would like to be, and as tall as it asks to be at
  // that width when the width is unbounded; both rounded up to their steps

  @override
  int computeMinIntrinsicWidth(int height) => computeMaxIntrinsicWidth(height);

  @override
  int computeMaxIntrinsicWidth(int height) =>
      _step(_child?.getMaxIntrinsicWidth(height) ?? 0, _stepWidth);

  @override
  int computeMinIntrinsicHeight(int width) => _height(_minHeight, width);

  @override
  int computeMaxIntrinsicHeight(int width) => _height(_maxHeight, width);

  int _height(int kind, int width) {
    final child = _child;
    if (child == null) {
      return 0;
    }
    final w = width >= BoxConstraints.unbounded
        ? getMaxIntrinsicWidth(BoxConstraints.unbounded)
        : width;
    return _step(child._intrinsic(kind, w), _stepHeight);
  }

  @override
  void paint(PaintContext ctx) {
    final c = _child;
    if (c != null) {
      paintChild(ctx, c);
    }
  }
}

/// Makes its child as tall as the child would like to be: its max
/// intrinsic height at the most width the box may have, within the
/// constraints (a tight height stays as it is). So a row under it whose
/// children stretch across it is as tall as its tallest child. The box is
/// as big as its child; without one, as small as the constraints allow.
final class RenderIntrinsicHeight extends RenderObject
    with RenderObjectWithChildMixin {
  /// Makes [child], if any, as tall as it would like to be.
  RenderIntrinsicHeight({RenderObject? child}) {
    this.child = child;
  }

  @override
  void performLayout(BoxConstraints c) {
    final child = _child;
    if (child == null) {
      width = c.minW;
      height = c.minH;
      return;
    }
    var minH = c.minH;
    var maxH = c.maxH;
    if (minH < maxH) {
      minH = maxH = c.constrainH(child.getMaxIntrinsicHeight(c.maxW));
    }
    _layoutChild(child, c.minW, c.maxW, minH, maxH);
    width = child.width;
    height = child.height;
  }

  // as tall as the child would like to be; what the child asks for at that
  // height when the height is unbounded

  @override
  int computeMinIntrinsicWidth(int height) => _width(_minWidth, height);

  @override
  int computeMaxIntrinsicWidth(int height) => _width(_maxWidth, height);

  @override
  int computeMinIntrinsicHeight(int width) => computeMaxIntrinsicHeight(width);

  @override
  int computeMaxIntrinsicHeight(int width) =>
      _child?.getMaxIntrinsicHeight(width) ?? 0;

  int _width(int kind, int height) {
    final child = _child;
    if (child == null) {
      return 0;
    }
    final h = height >= BoxConstraints.unbounded
        ? child.getMaxIntrinsicHeight(BoxConstraints.unbounded)
        : height;
    return child._intrinsic(kind, h);
  }

  @override
  void paint(PaintContext ctx) {
    final c = _child;
    if (c != null) {
      paintChild(ctx, c);
    }
  }
}
