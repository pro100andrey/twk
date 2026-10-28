/// Widgets that keep the mouse from a subtree: [IgnorePointer] lets it
/// through to what is under it, [AbsorbPointer] stops it there.
library;

import 'package:twk_core/twk_core.dart'
    show
        BoxConstraints,
        DiagnosticPropertiesBuilder,
        HitTestBehavior,
        HitTestResult,
        PaintContext,
        RenderObject,
        RenderObjectWithChildMixin;

import '../framework/framework.dart';
import '../layout/one_child.dart';

/// Shows [child], which the mouse does not reach while [ignoring], going
/// to what is under it instead.
///
/// A hit test passes it by, so presses, releases, motion and the wheel over
/// it go to what is under it, as if it were not there, and so does the
/// hover: a `MouseRegion` inside is left, and one under it entered, when
/// [ignoring] turns on under a mouse that stays put (at the end of that
/// frame). A press made before goes on to the `Listener`s it was hit in
/// until its last button is released. A `DragTarget` inside is not found
/// either.
///
/// The `Listener`s and `MouseRegion`s inside stay mounted, and the
/// terminal goes on reporting what they need.
///
/// As Flutter's `IgnorePointer`.
///
/// A label drawn over a list that the clicks go through, to the list:
///
/// ```dart
/// Stack(
///   children: [
///     ListView(children: const [Text('one'), Text('two')]),
///     const Positioned(
///       right: 0,
///       top: 0,
///       child: IgnorePointer(child: Text('2 items')),
///     ),
///   ],
/// )
/// ```
final class IgnorePointer extends SingleChildRenderObjectWidget {
  /// Keeps the mouse from [child] while [ignoring], by default.
  const IgnorePointer({super.key, this.ignoring = true, super.child});

  /// Whether the mouse passes [child] by.
  final bool ignoring;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderIgnorePointer(ignoring);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderIgnorePointer).ignoring = ignoring;
}

/// Shows [child], which takes the mouse while [absorbing] and gives it to
/// nothing in it nor under it.
///
/// A hit test stops at its bounds, so presses, releases, motion and the
/// wheel there reach neither [child] nor what is under it, nor the app's
/// `InputListener`s; a press there keeps what follows it, wherever the
/// mouse goes, until its last button is released. The `MouseRegion`s
/// inside and under it are left, when [absorbing] turns on under a mouse
/// that stays put (at the end of that frame).
///
/// The `Listener`s around it are hit as around any child they have: a
/// press there goes to them, and the wheel to a scrolling view around
/// it, as in Flutter's `AbsorbPointer`.
///
/// A form whose buttons the mouse cannot press while it is being sent:
///
/// ```dart
/// final sending = ValueNotifier(false);
/// final form = ValueListenableBuilder(
///   valueListenable: sending,
///   builder: (context, busy, child) =>
///       AbsorbPointer(absorbing: busy, child: child),
///   child: Button('Send', onPressed: () => sending.value = true),
/// );
/// ```
final class AbsorbPointer extends SingleChildRenderObjectWidget {
  /// Stops the mouse at [child] while [absorbing], by default.
  const AbsorbPointer({super.key, this.absorbing = true, super.child});

  /// Whether the mouse stops at it.
  final bool absorbing;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderAbsorbPointer(absorbing);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as RenderAbsorbPointer).absorbing = absorbing;
}

/// What [IgnorePointer] and [AbsorbPointer] put in the render tree: their
/// child, as big as the child is; hit as each says.
abstract base class _RenderPointerGate extends RenderObject
    with RenderObjectWithChildMixin {
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

final class _RenderIgnorePointer extends _RenderPointerGate {
  _RenderIgnorePointer(this.ignoring);

  /// See [IgnorePointer.ignoring].
  bool ignoring;

  @override
  HitTestBehavior get hitTestBehavior => HitTestBehavior.deferToChild;

  @override
  bool hitTestChildren(HitTestResult result, int x, int y) =>
      !ignoring && super.hitTestChildren(result, x, y);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add('ignoring', ignoring);
  }
}

/// What [AbsorbPointer] puts in the render tree; the app's `MouseTracker`
/// takes an event that hits one while it is [absorbing].
final class RenderAbsorbPointer extends _RenderPointerGate {
  /// The render object of an [AbsorbPointer], stopping the mouse while
  /// [absorbing].
  RenderAbsorbPointer(this.absorbing);

  /// See [AbsorbPointer.absorbing].
  bool absorbing;

  @override
  HitTestBehavior get hitTestBehavior => HitTestBehavior.deferToChild;

  @override
  bool hitTestChildren(HitTestResult result, int x, int y) =>
      !absorbing && super.hitTestChildren(result, x, y);

  @override
  bool hitTestSelf(int x, int y) => absorbing;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add('absorbing', absorbing);
  }
}
