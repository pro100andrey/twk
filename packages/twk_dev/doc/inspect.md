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
object, a render object's element) selected. `g` opens the place where the selected widget was made in the editor: twk keeps no
creation locations, so the inspector looks in the app's code, through its VM
service, for it: the `build` methods above the element, nearest first, for a call
of its type's constructor (`Text(`, `const Text(`, `Text.rich(`, in code, not in
comments or strings), the one at the element's place among those of its type that
build made. Several calls where the build made as many elements are matched by
place; otherwise the status says "one of several". The editor is `TWK_EDITOR`
(`code -g {file}:{line}:{column}`), else `VISUAL`, else `EDITOR` (`editorCommand`):
a terminal editor runs in the inspector's terminal, which waits for it, any other
apart. Nothing opens for a render object (`t` back to the widgets first), for a
widget no build above calls the constructor of (a call in a function or a
`build` of another package's, a generated one), or without an editor set; the
status says which. The VS Code extension finds the same places with the same steps
(`source_find.ts`), a copy of `source_find.dart`: the extension runs without twk_dev
installed.

The tree is loaded as the app
comes, on `r`, when this terminal gets the focus back (a focus report) and
after a pick, again shortly while the app has drawn no frame; nodes are kept
expanded and selected by id, those not seen before expanded. `q` quits, the
pick and the outline taken off the app.
