# `twk inspect`

The inspector is an app of its own, made of twk's widgets, in a second
terminal; it inspects the app over the binding's service extensions
(`ext.twk.*`, twk's `AppBinding.callServiceExtension`), as a client of the
app's VM service (`package:vm_service`):

```bash
dart run packages/twk_dev/bin/twk.dart run packages/twk/example/counter.dart  # one terminal
dart run packages/twk_dev/bin/twk.dart inspect                                # another, same directory
```

Without an address it reads `.dart_tool/twk/run` of the project (`twk run`
above), waits while no app is there, and once one has gone waits for the next,
so it follows `twk run`'s restarts. With `<vm-service-uri>`, the address the
VM prints (`http://127.0.0.1:8181/token=/`, as `dart run --observe` says) or
its WebSocket one (`ws://…/token=/ws`), it inspects that app alone: nothing
answering there exits with 1, as does no terminal (its output piped or in CI
included: it takes no [plain
output](../../twk_core/doc/design/terminal.md#plain-output)); more than one
address with 64. The app is the isolate that registered `ext.twk.tree`, its
first `runApp`; one answering in another version of the extensions' JSON than
this twk's (`AppBinding.serviceExtensionsVersion`) is said so.

The screen: the widget tree in a `TreeView` on the left, from the app's widget
(the binding's own nodes above it left out), each node's type, key and first
unnamed property (a text's string), `error` and `overflow` flags in red; on
the right the selected node's properties (`ext.twk.properties`: id, key, its
render object or element, the properties, flags) and layout (`ext.twk.layout`:
constraints as `w 0..80, h 24`, size, offset in its parent, place on the
screen); a status row and the keys (`KeyHintsBar`) below, in a `SplitView`
whose divider drags. The arrows, the mouse and the tree's keys select; the
node selected is outlined on the app's screen (`ext.twk.highlight`) until `h`
turns that off. `s` has the app pick a node (`ext.twk.flags` `select`, twk's
`DebugAids.select`): the app's terminal reports the mouse, the node under it
outlined; a click there selects that node here (`ext.twk.select`), its
ancestors expanded, and Escape there, or `s` here again, cancels; an app that
runs inline, whose terminal keeps the mouse, cannot pick. `t` shows the render
tree from its root, and back, the node's counterpart (an element's render
object, a render object's element) selected. The tree is loaded as the app
comes, on `r`, when this terminal gets the focus back (a focus report) and
after a pick, again shortly while the app has drawn no frame; nodes are kept
expanded and selected by id, those not seen before expanded. `q` quits, the
pick and the outline taken off the app.
