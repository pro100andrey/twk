# twk reference: `semantics`

[The reference](README.md) · `lib/src/semantics/`, `test/semantics/`

What the widgets of an app are to a screen reader.

## `Semantics`

`Semantics(role:, label:, value:, state:, hint:, nodes:, child:)` gives what
is below it a `SemanticsRole` (`alert`, `button`, `checkbox`, `dialog`,
`heading`, `link`, `list`, `listItem`, `menu`, `menuBar`, `menuItem`,
`progressBar`, `radio`, `slider`, `status`, `tab`, `tabList`, `textBox`, and
`toggle`, read as `switch`; a container, a dialog, list, menu, menu bar or
tab list, has a line of its own, label or not, before those of the nodes in
it), a label, a value, a `SemanticsState` (`checked`, `selected`,
`expanded`, `disabled`) and a hint, what more there is to say of it, read
last (`button Save, disabled, Writes the file`; a `Tooltip`'s message is its
child's); without a role it is its label alone, one with only a hint giving
it to the first node below it that has a line, after any hint that node has,
and `nodes` stand for what a render object paints itself, item by item.

## `BlockSemantics`

`BlockSemantics(child:)` leaves out what was read before it in its node, as
a dialog's barrier does the page under it.

## `ExcludeSemantics`

`ExcludeSemantics(excluding: true, child:)` leaves out what is below it, as
though it were not there: its `Semantics` and its texts, the label a
`Semantics` above takes of the texts below it read without them, a node
focused there read as the nearest above it with a line; an `Offstage`, and a
`Visibility` that keeps the state of a child it does not show, is one around
the child, and a `ListView.separated` puts its separators in one.

## `SemanticsNode.of`

`SemanticsNode.of(context, focus:)` reads the tree of them below a context,
with the text of the `Text`s among them and without what is not laid out (a
covered route, a hidden tab): each node its `role`, `label`, `value`,
`state`, whether it is `focused`, and its `children`; its `line` (`button
OK`, `checkbox Remember me, checked`, `textbox Name: anna`), `lines`, depth
first, and `focusedLine`. The node focused is the nearest with a line at or
above the primary focus, or the focused one of its `nodes`, else the first
below it. The controls say what they are: `Button`, `Checkbox`, `Switch`,
`RadioGroup` (a radio a choice), `Slider`, `Link`, `ListView` (a list of `N
items`, an item a row), `MenuBar` and its menus (the entries with their
keys, checked, expanded or disabled, the highlighted one focused),
`ModalBarrier` (a `BlockSemantics`), `Dialog` (a dialog of its title), the
windows of a `WindowLayer` (a dialog of the title, `maximised` its value
while it is; a minimised one as its chip, `button Notes: minimised`),
`TabBar` (a tab list, the selected tab `selected`), `TextField` and
`TextArea` (a text box, its text the value, a line each for a text area's
lines; with `obscureText` always `protected`, never its characters or how
many) and `ProgressBar` (`progressbar 40%` as far as it is filled, without a
value while it is not known). Where a control shows no label,
`semanticsLabel:` gives it one: `ProgressBar` (`progressbar Upload: 40%`),
`Slider` (`slider Volume: 0.25`), `TextField` and `TextArea`, where it wins
over the placeholder, and `Checkbox` and `Switch`, where a `label` shown
wins over it, so that what is read is what is seen. In the screen-reader
mode, `runApp(screenReader: true)` (by default where `TWK_SCREEN_READER` is
`1`, as for `AppBinding(screenReader:)`), the terminal is opened inline, or
on the normal screen with a `viewport`, and the app's lines are shown in its
place as plain text, in the viewport with one, the focused one in reverse
video with the cursor at its end, a long line broken at a blank, the region
as tall as the lines and, where there are more, those around the focused
one; each frame lays the app out first, so that what its layout builds is
read too, and the presenter writes only the lines that changed. The terminal
keeps the mouse.

## `AppBinding.screenReader`

`AppBinding.screenReader` turns it on and off while the app runs (off, the
app is laid out and painted again), and `AppBinding.semantics` gives the
tree, as a test reads it. Text a render object of an app's own paints is not
read unless a `Semantics` gives it
