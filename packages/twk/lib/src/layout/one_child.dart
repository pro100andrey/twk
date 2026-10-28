/// The element the layout widgets with one child share: [OneChildElement].
library;

import 'package:twk_core/twk_core.dart'
    show RenderObject, RenderObjectWithChildMixin;

import '../framework/framework.dart';

/// The element of a widget whose render object has at most one child
/// ([RenderObjectWithChildMixin]): puts the render object of its child
/// in it, and takes it out with the child.
///
/// A one-child widget of an app's own, over a render object with that
/// mixin, returns one from its `createElement`. Its child is never moved:
/// a move throws [UnsupportedError].
final class OneChildElement extends SingleChildRenderObjectElement {
  /// The element of [widget].
  OneChildElement(super.widget);

  @override
  RenderObjectWithChildMixin get renderObject =>
      super.renderObject as RenderObjectWithChildMixin;

  @override
  void insertRenderObjectChild(RenderObject child, Object? slot) =>
      renderObject.child = child;

  @override
  void moveRenderObjectChild(
    RenderObject child,
    Object? oldSlot,
    Object? newSlot,
  ) => throw UnsupportedError('one child does not move: $this');

  @override
  void removeRenderObjectChild(RenderObject child, Object? slot) {
    assert(identical(renderObject.child, child), '$child is not the child');
    renderObject.child = null;
  }
}
