// The stage over the options of a narrow page: the stage keeps the rows
// its widget asks for, the options take what it leaves them.
import 'package:twk/twk.dart';

import '../page.dart';

/// [children], the stage then the options, one under the other: the
/// stage keeps the rows its widget asks for (and a row above and below
/// it), the options take what it leaves, [full] at most and [least] at
/// least, and scroll. The widget asks for [heightIn] the room the whole
/// options leave it, half the rows at least (`GalleryPage.heightIn`),
/// else for the stage's intrinsic height.
final class StageOverOptions extends MultiChildRenderObjectWidget {
  const StageOverOptions({
    required this.full,
    required this.least,
    this.heightIn,
    super.key,
    super.children,
  });

  final int full;
  final int least;
  final int Function(StageRoom room)? heightIn;

  @override
  MultiChildRenderObjectElement createElement() => ChildListElement(this);

  @override
  RenderStageOverOptions createRenderObject(BuildContext context) =>
      RenderStageOverOptions(full, least)..heightIn = heightIn;

  @override
  void updateRenderObject(
    BuildContext context,
    RenderStageOverOptions renderObject,
  ) => renderObject
    ..full = full
    ..least = least
    ..heightIn = heightIn;
}

final class _SplitData extends ParentData with ContainerParentDataMixin {}

/// What a [StageOverOptions] lays out and paints.
final class RenderStageOverOptions extends RenderObject
    with ContainerRenderObjectMixin<_SplitData> {
  RenderStageOverOptions(this._full, this._least);

  int _full;
  int get full => _full;
  set full(int v) {
    if (v != _full) {
      _full = v;
      markNeedsLayout();
    }
  }

  int _least;
  int get least => _least;
  set least(int v) {
    if (v != _least) {
      _least = v;
      markNeedsLayout();
    }
  }

  int Function(StageRoom room)? _heightIn;
  int Function(StageRoom room)? get heightIn => _heightIn;
  set heightIn(int Function(StageRoom room)? f) {
    if (f != null || _heightIn != null) {
      _heightIn = f;
      markNeedsLayout();
    }
  }

  /// The rows the options took at the last layout.
  var optionRows = 0;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _SplitData) {
      child.parentData = _SplitData();
    }
  }

  @override
  bool get sizedByParent => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW < BoxConstraints.unbounded ? c.maxW : c.minW;
    height = c.maxH < BoxConstraints.unbounded ? c.maxH : c.minH;
    final stage = firstChild;
    if (stage == null) {
      return;
    }
    final options = childAfter(stage);
    var h = 0;
    if (options != null) {
      final heightIn = _heightIn;
      // where the whole options leave a widget that fits itself to its
      // room less than half the rows, it is offered half
      final left = height - _full;
      final offered = (left > height ~/ 2 ? left : height ~/ 2) - 2;
      final want = heightIn == null
          ? stage.getMaxIntrinsicHeight(width)
          : heightIn(
                  StageRoom(
                    width - 6 < 0 ? 0 : width - 6,
                    offered < 0 ? 0 : offered,
                  ),
                ) +
                2;
      // the stage keeps them: the options take what it leaves, from
      // [least] to [full] rows, and scroll
      final room = height - want;
      h = room > _least ? room : _least;
      if (h > _full) {
        h = _full;
      }
      if (h > height) {
        h = height;
      }
    }
    optionRows = h;
    stage
      ..layout(BoxConstraints.tight(width, height - h))
      ..parentData.dx = 0
      ..parentData.dy = 0;
    if (options != null) {
      options
        ..layout(BoxConstraints.tight(width, h))
        ..parentData.dx = 0
        ..parentData.dy = height - h;
    }
  }

  @override
  void paint(PaintContext ctx) {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (child.width > 0 && child.height > 0) {
        paintChild(ctx, child);
      }
    }
  }
}
