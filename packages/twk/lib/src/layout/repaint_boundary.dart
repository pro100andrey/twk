/// A part of the screen that repaints on its own: [RepaintBoundary].
library;

import 'package:twk_core/twk_core.dart' show RenderEffect, RenderObject;

import '../framework/framework.dart';
import 'one_child.dart';

/// Makes [child] a repaint boundary of the core: what is marked for paint
/// inside it repaints the child alone, over what was under it, and none
/// of what is around it; what repaints around it does not repaint the
/// child unless it paints over its cells. A part that changes often (a
/// clock, a counter, a log) under one keeps the rest of the screen from
/// being painted again with it. As big as the child.
///
/// The child need not paint every cell: what was under it is kept and put
/// back before it repaints on its own (as the core's `RenderEffect`, with
/// no effect, keeps it), so a cell it leaves shows what is under it, as
/// without the boundary.
///
/// A spinner that turns without the rest of the screen being painted
/// again:
///
/// ```dart
/// const RepaintBoundary(child: Spinner())
/// ```
final class RepaintBoundary extends SingleChildRenderObjectWidget {
  /// Makes [child] a repaint boundary.
  const RepaintBoundary({super.key, super.child});

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRepaintBoundary();
}

/// What a [RepaintBoundary] lays out and paints: the child, as a repaint
/// boundary that puts back what was under it before the child repaints.
final class _RenderRepaintBoundary extends RenderEffect {
  @override
  bool get hasEffect => false;

  @override
  void effectCell(
    int x,
    int y,
    int glyph,
    int style,
    int underGlyph,
    int underStyle,
  ) {
    effectGlyph = glyph;
    effectStyle = style;
  }
}
