/// Cells an app paints itself: [CustomPaint] and the [CellPainter]s it
/// paints under and over its child with.
library;

import 'package:twk_core/twk_core.dart'
    show
        BoxConstraints,
        Canvas,
        DiagnosticPropertiesBuilder,
        HitTestResult,
        PaintContext,
        PipelineOwner,
        RenderObject,
        RenderObjectWithChildMixin;

import '../foundation/foundation.dart';
import '../framework/framework.dart';
import 'one_child.dart';

// Examples can assume:
// late CellPainter progress;

/// What paints the cells of a [CustomPaint]: text, styles and box glyphs
/// on the [Canvas] of the frame, as a render object of an app's own does.
///
/// [paint] gets the canvas with its origin at the top left of the
/// [CustomPaint], clipped to its cells, and its size; what the painter
/// does to the canvas (moves, clips) is undone after it. It need not
/// paint every cell: those it leaves show what is under the
/// [CustomPaint]. Pens come from the canvas's styles
/// (`canvas.styles.pen(Pen(…))`, or a `Style`'s `penIn(canvas.styles)`).
/// A painter is asked to paint any rows of it again, whenever what is
/// under it or over it there repaints: it paints the same cells from the
/// same state.
///
/// It is painted again when a new one [shouldRepaint] over the one it
/// replaces, and whenever `repaint`, given, notifies its listeners: an
/// animated painter repaints on a [Listenable] it reads its state from
/// (a `ValueNotifier`, an animation), with no widget built again.
///
/// A bar as long as a notifier's percentage of the width, repainted when it
/// changes:
///
/// ```dart
/// final class Progress extends CellPainter {
///   Progress(this.percent) : super(repaint: percent);
///
///   final ValueNotifier<int> percent;
///
///   @override
///   void paint(Canvas canvas, int width, int height) {
///     final pen = canvas.styles.pen(const Pen(fg: Color.green));
///     canvas.text(0, 0, '█' * (width * percent.value ~/ 100), pen);
///   }
///
///   @override
///   bool shouldRepaint(Progress oldDelegate) =>
///       oldDelegate.percent != percent;
/// }
/// ```
abstract class CellPainter extends Listenable {
  /// A painter that repaints whenever `repaint`, given, notifies.
  const CellPainter({this._repaint});

  final Listenable? _repaint;

  /// Listens to the `repaint` it was made with: what the [CustomPaint]
  /// it paints repaints on.
  @override
  void addListener(VoidCallback listener) => _repaint?.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _repaint?.removeListener(listener);

  /// Paints the cells of a [CustomPaint] [width] wide and [height] tall
  /// on [canvas], whose origin is its top left cell.
  void paint(Canvas canvas, int width, int height);

  /// Whether this painter, which takes the place of [oldDelegate], paints
  /// anything else: true paints the [CustomPaint] again. Not asked of a
  /// painter of another type, which paints again anyway, nor of the same
  /// one.
  bool shouldRepaint(covariant CellPainter oldDelegate);

  /// Whether the cell [x], [y] of the [CustomPaint] is hit, in its own
  /// coordinates; null for what its place says: a [CustomPaint.painter]
  /// is hit in every cell (where the child is not), a
  /// [CustomPaint.foregroundPainter] in none, the mouse going through to
  /// the child.
  bool? hitTest(int x, int y) => null;
}

/// Paints cells of its own under and over [child]: [painter] first, then
/// the child, then [foregroundPainter] over it. As big as the child, or
/// without one as [size] (width, height), within the constraints.
///
/// It repaints, laying nothing out, when a new painter
/// [CellPainter.shouldRepaint] over the one before (or is of another
/// type), and when a painter's `repaint` notifies.
///
/// Hit testing asks the foreground painter first: where it is hit
/// ([CellPainter.hitTest] true), so is this widget, the child not. Then
/// the child; then, where the child is not hit, the painter, by default
/// hit in all of its cells. Without a painter that says it is hit, only
/// the child is.
///
/// A painter of the app's own, the `Progress` bar of [CellPainter]'s
/// example, on a row 20 cells wide:
///
/// ```dart
/// CustomPaint(painter: progress, size: (20, 1))
/// ```
final class CustomPaint extends SingleChildRenderObjectWidget {
  /// Paints [painter] under [child] and [foregroundPainter] over it;
  /// without a child, [size] cells, none by default.
  const CustomPaint({
    super.key,
    this.painter,
    this.foregroundPainter,
    this.size = (0, 0),
    super.child,
  });

  /// What paints under the child.
  final CellPainter? painter;

  /// What paints over the child.
  final CellPainter? foregroundPainter;

  /// The width and height it is without a child, within the constraints;
  /// with one it is as big as the child.
  final (int, int) size;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderCustomPaint(
    painter: painter,
    foregroundPainter: foregroundPainter,
    size: size,
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderCustomPaint)
      ..painter = painter
      ..foregroundPainter = foregroundPainter
      ..size = size;
  }

  /// Adds [size] where it is not the default; the painters' types are
  /// its render object's.
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add('size', '${size.$1}×${size.$2}', defaultValue: '0×0');
  }
}

/// What a [CustomPaint] lays out and paints.
final class _RenderCustomPaint extends RenderObject
    with RenderObjectWithChildMixin {
  _RenderCustomPaint({
    required this._painter,
    required this._foregroundPainter,
    required this._size,
  });

  // markNeedsPaint once, for adding and removing it as a listener
  late final VoidCallback _repaint = markNeedsPaint;

  // listening to the painters' repaint
  var _listening = false;

  CellPainter? _painter;
  CellPainter? get painter => _painter;
  set painter(CellPainter? p) {
    final old = _painter;
    if (identical(p, old)) {
      return;
    }
    _painter = p;
    _replaced(old, p);
  }

  CellPainter? _foregroundPainter;
  CellPainter? get foregroundPainter => _foregroundPainter;
  set foregroundPainter(CellPainter? p) {
    final old = _foregroundPainter;
    if (identical(p, old)) {
      return;
    }
    _foregroundPainter = p;
    _replaced(old, p);
  }

  (int, int) _size;
  (int, int) get size => _size;
  set size((int, int) s) {
    if (s != _size) {
      _size = s;
      if (child == null) {
        markNeedsLayout();
      }
    }
  }

  /// [p] has taken the place of [old]: listened to in its place, and
  /// painted when it paints anything else.
  void _replaced(CellPainter? old, CellPainter? p) {
    if (_listening) {
      old?.removeListener(_repaint);
      p?.addListener(_repaint);
    }
    if (old == null ||
        p == null ||
        p.runtimeType != old.runtimeType ||
        p.shouldRepaint(old)) {
      markNeedsPaint();
    }
  }

  @override
  void attach(PipelineOwner o) {
    super.attach(o);
    if (!_listening) {
      _listening = true;
      _painter?.addListener(_repaint);
      _foregroundPainter?.addListener(_repaint);
    }
  }

  @override
  void detach() {
    if (_listening) {
      _listening = false;
      _painter?.removeListener(_repaint);
      _foregroundPainter?.removeListener(_repaint);
    }
    super.detach();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add('painter', _painter?.runtimeType, defaultValue: null)
      ..add(
        'foregroundPainter',
        _foregroundPainter?.runtimeType,
        defaultValue: null,
      );
  }

  @override
  void performLayout(BoxConstraints c) {
    final child = this.child;
    if (child == null) {
      width = c.constrainW(_size.$1);
      height = c.constrainH(_size.$2);
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
      child?.getMinIntrinsicWidth(height) ?? _size.$1;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      child?.getMaxIntrinsicWidth(height) ?? _size.$1;

  @override
  int computeMinIntrinsicHeight(int width) =>
      child?.getMinIntrinsicHeight(width) ?? _size.$2;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      child?.getMaxIntrinsicHeight(width) ?? _size.$2;

  @override
  void paint(PaintContext ctx) {
    final painter = _painter;
    if (painter != null) {
      _paintWith(ctx.canvas, painter);
    }
    final child = this.child;
    if (child != null) {
      paintChild(ctx, child);
    }
    final foreground = _foregroundPainter;
    if (foreground != null) {
      _paintWith(ctx.canvas, foreground);
    }
  }

  /// Has [painter] paint on [canvas], what it does to the canvas undone
  /// after it.
  void _paintWith(Canvas canvas, CellPainter painter) {
    canvas.save();
    try {
      painter.paint(canvas, width, height);
    } finally {
      canvas.restore();
    }
  }

  @override
  bool hitTestChildren(HitTestResult result, int x, int y) =>
      (_foregroundPainter?.hitTest(x, y) ?? false) ||
      super.hitTestChildren(result, x, y);

  @override
  bool hitTestSelf(int x, int y) {
    final painter = _painter;
    return painter != null && (painter.hitTest(x, y) ?? true);
  }
}
