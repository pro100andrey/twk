# twk reference: `framework`

[The reference](README.md) · `lib/src/framework/`, `test/framework/`

## `Widget`

`Widget`, `StatelessWidget`, `StatefulWidget` and `State`;

## `InheritedWidget`

`InheritedWidget`, found by its type in constant time, which rebuilds the
elements that depend on it when it changes;

## `ParentDataWidget`

`ParentDataWidget`, which puts the data a parent keeps on a child (a flex
factor and fit, where a stack pins it, the cells a grid puts it in) on the
render object below it;

## `ProxyWidget`

`ProxyWidget`;

## `Notification`

`Notification`, which `dispatch` bubbles up from a context to the
`NotificationListener`s of its type above it, the nearest first, until one
returns true; render object widgets (`LeafRenderObjectWidget`,
`SingleChildRenderObjectWidget`, `MultiChildRenderObjectWidget`) and their
elements;

## `BuildContext`

`BuildContext`; keys (`ValueKey`, `ObjectKey`, `UniqueKey`, and `GlobalKey`,
which finds its element and state, the element moving with its widget from
one place in the tree to another within a frame, state and render objects
kept: `deactivate`, then `activate`), by which children keep their elements
wherever they move among their siblings;

## `Builder`

`Builder`, which builds its child with a context of its own (a
`WidgetBuilder`), and `StatefulBuilder`, which builds it again when the
`setState` it hands its `builder` (a `StatefulWidgetBuilder`) is called, its
state kept as the widget above rebuilds (a `StateSetter` called after it
left the tree asserts);

## `LayoutBuilder`

`LayoutBuilder`, which builds its child in the layout of a frame with the
constraints it is laid out within (its `builder`, a `LayoutWidgetBuilder`,
runs at its first layout, when the constraints differ from those of its last
build, when it is replaced or an inherited widget the builder depends on
changes, and at no other layout), lays it out in the same frame, rebuilds
the dirty elements below it in that layout (those elsewhere wait for the
next build scope, which the owner asks for), is as big as its child and
answers the intrinsic sizes of the child it built last (none before its
first layout: a parent laid out by sizes its next build changed is laid out
again on the next frame);

## `BuildOwner`

`BuildOwner` (build scopes, unmounting at the end of a frame, the widget its
`onBuildError` returns shown in place of a build that threw (a
`LayoutBuilder`'s `builder` too), and by the nearest component element or
`LayoutBuilder` at or above an element that threw as it was created or
updated (`createRenderObject`, `updateRenderObject`, `initState`,
`didUpdateWidget`, `didChangeDependencies`) in place of its child, what was
mounted for that child leaving the tree; an exception out of a build scope
leaving the elements it did not rebuild to the next one; a `GlobalKey` on
two widgets at once failing an assert; `rebuilds`, how many times its
elements have built, a frame's the difference) and `RootWidget`;

## `Element.describe`

`Element.describe()`, the element and those below it as the core's
`DiagnosticsNode`s
([§1.8](../../../twk_core/doc/design/render.md)), built only
when called: its widget's type and key (`Element.toString`, `Type-key`), the
properties of its widget and its state (`Widget.debugFillProperties`,
`State.debugFillProperties`), for a render object element those of its
render object and of what the render object's parent keeps on it, the size
of its render object or the nearest one below, and flags: ◆ repaint
boundary, ⟳ needs layout, ✎ needs paint, ✱ to be rebuilt, ✗ it shows an
error in place of what it builds, or its render object shows one. The
library re-exports the core's diagnostics API. Named slots that plugins
fill: a `SlotRegistry` (a `ChangeNotifier`) of `SlotEntry(slot:, id:,
builder:, order: 0)`s, `register`ed (one of the same id in that slot
replaced in its place) and `unregister`ed, `entriesOf(slot)` in `order`,
then as registered;

## `SlotScope`

`SlotScope(registry:, child:)` puts it above the tree (`SlotScope.of`,
`maybeOf`), and `Slot(name, layout: (context, children) => Row(children:
children), placeholder:)` shows the entries of its name, or `placeholder`
without any, built again only when they change, each under a key of its id
so that it keeps its state as they move, what an entry's builder throws
shown in its place only; without a `SlotScope` above, a slot has no entries
