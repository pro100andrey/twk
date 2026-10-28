/// The element the layout widgets with a list of children share:
/// [ChildListElement].
library;

import 'package:twk_core/twk_core.dart'
    show ContainerParentDataMixin, ContainerRenderObjectMixin, RenderObject;

import '../framework/framework.dart';

/// The element of a widget whose render object keeps its children in a
/// list ([ContainerRenderObjectMixin]): keeps the render objects of its
/// children in it, in order.
///
/// A layout widget of an app's own, over a render object with that mixin,
/// returns one from its `createElement`.
final class ChildListElement extends MultiChildRenderObjectElement {
  /// The element of [widget].
  ChildListElement(super.widget);

  @override
  ContainerRenderObjectMixin<ContainerParentDataMixin> get renderObject =>
      super.renderObject
          as ContainerRenderObjectMixin<ContainerParentDataMixin>;

  @override
  void insertRenderObjectChild(
    RenderObject child,
    IndexedSlot<Element?> slot,
  ) => renderObject.insert(child, after: slot.value?.renderObject);

  @override
  void moveRenderObjectChild(
    RenderObject child,
    IndexedSlot<Element?> oldSlot,
    IndexedSlot<Element?> newSlot,
  ) => renderObject.move(child, after: newSlot.value?.renderObject);

  @override
  void removeRenderObjectChild(RenderObject child, Object? slot) =>
      renderObject.remove(child);
}
