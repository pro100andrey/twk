# twk reference: `controls`

[The reference](README.md) · `lib/src/controls/`, `test/controls/`

## `TabController`

`TabController(length:, initialIndex:)`, the selected tab (`index`) that a
`TabBar(controller:, tabs:, …)` sets and a `TabView(controller:, children:)`
shows. The bar is a row of the labels, the selected one marked: a tab
clicked is selected, and while the bar has the focus Left and Right select
the tab before and after (the first after the last), Home and End the first
and the last; when the tabs do not fit, it scrolls to show the selected one
whole, `‹` and `›` at the edges where tabs are cut off. The view shows the
selected tab's child and keeps the others mounted, with their state, but
neither laid out, painted, hit nor focusable; a tab selected while the focus
is in the view gets it back where it was when the tab was left, or on its
first node. The controller's `length` may be set (one at least), the last
tab selected where the index is past it; while the children are fewer than
the index, as before the controller is told of a tab gone, the view shows
the last (none without any), and a child with a key keeps its state and its
focus as the children before it come and go. The bar marks its last label
for an index past them.

## `KeyHintsBar`

`KeyHintsBar(…)`, the keys that can be pressed now, each before its hint, in
a row (`ctrl+s save   q quit`: the keys bold in the theme's `text`, three
blanks apart; `keyStyle:` and `separator:` change them):
`FocusManager.activeKeys`, followed as the focus moves and the layers change
(`keysChanged`); keys without a hint left out unless `showUnhinted`; a
sequence whole (`ActiveKey.label`: `ctrl+x ctrl+s save`), each key named by
`keyLabel`, `KeyHintsBar.signs` by default (the arrows and Escape by their
signs, `↑` and `esc`, Page Up and Down `pgup` and `pgdn`, after the
modifiers too: `alt+↓`), and with `joinKeys: true`, the default, keys of one
family that share a hint shown as one (`↑↓←→ move`, `pgup pgdn a page`,
`home end ends`: single keys without modifiers only; `keyLabel: (c) => '$c',
joinKeys: false` names each key as `KeyCombo.toString` does, apart), and
while a layer holds its first keys what can follow them (`ctrl+s save` once
Ctrl+X is pressed).

## `StatusMessage`

`StatusMessage(message, kind:, title:, icon:, …)`, a message after the icon
of its `StatusKind` (`info`, `success`, `warning`, `error`) in that kind's
color of the theme;

## `Badge`

`Badge(label, kind:, style:)`, a short label reversed in a kind's color, or
the theme's `primary`;

## `Link`

`Link(url, text:, style:)`, text linked to a URL as an OSC 8 hyperlink, in
the theme's `primary` underlined by default.

## `StatusBar`

`StatusBar(left:, center:, right:, gap: 1, style:)`, one row of three
sections, `left` at its left edge, `right` at its right edge and `center` in
its middle, at least `gap` columns between two, each as wide as it likes
while they all fit; when they do not, `right` keeps its width first, as far
as it fits, then `left` takes what it leaves, then `center` goes in the
middle of the room between them, cut to that room or gone without one. A
section cut is laid out that narrow: a `Text(…, wrap: TextWrap.none,
overflow: TextOverflow.ellipsis)` ends with `…`. As wide as it may be, or
along an unbounded axis as its sections and gaps; filled with `style` over
the theme's `surface` and `text`, which the sections' `Text`s are drawn in
under their own style.

## `ListTile`

`ListTile(title:, leading:, subtitle:, trailing:, onTap:, selected: false,
enabled: true, focusNode:, autofocus:)`, a row of a list as Flutter's:
leading, the title over the subtitle (muted), trailing at the right end, a
column apart; the title `primary` in bold where `selected`; with `onTap` it
takes the focus and the mouse, on `selection` while focused and on `hover`
under the mouse, tapped by a click, Enter or Space; disabled, muted and
passed by Tab.

## `Button.outlined`

`Button.outlined(label, onPressed:, focusNode:, autofocus:, style:, tall:
false)` and `Button.filled(…)` are a row as wide as the label and two blanks
either side, or as wide as an `Expanded` makes them, the label in the
middle: between two edges (`▕` `▏`) in `border` (the text's color under the
mouse, `primary` with the label while focused), or on a fill of `primary`
(`theme.fill`; a step towards its text under the mouse, a fill of the text's
color, bold, while focused), `style`'s text color the edges' or the fill's;
`tall: true` three rows, a box drawn around the label or a fill a row above
and below it;

## `Button`

`Button(label, onPressed:, focusNode:, autofocus:, style:, focusedStyle:,
hoverStyle:, disabledStyle:)`, ` label `, a blank on either side, calls
`onPressed` when it is pressed: clicked, the release over it (the press
gives it the focus), or Enter or Space while it has the focus, Enter hinted
(`enter press`). It is a chip: `primary` bold on the theme's `surface` at
rest, filled with the color of its text and the label in `onPrimary` while
it has the focus, a step towards that color while the mouse is over it, and
a flash fading in 260 ms as it is pressed (`style: theme.primary.merge(const
Style(attrs: Attr.bold))` with `focusedStyle: const Style(attrs:
Attr.reverse)` gives a plain look, the label bold in `primary` and reversed
while it has the focus).

## `Pressable`

`Pressable(builder: (context, focused) => …, enabled:, bindings:, hints:,
onKeyEvent:, onTap:, focusNode:, autofocus:)` is what the controls are made
of, for one of an app's own: a node of the focus tree that takes the focus
while `enabled` (disabled, Tab passes it by), `bindings` the keys it takes
while it has it (as `KeyBindings` takes them, with their `hints`), a press
of the left button over it focusing it and a tap calling `onTap`.

## `Checkbox`

`Checkbox(value:, onChanged:, label:)`, `[x]` or `[ ]` before its label, and
`Switch(…, pill: true)`, a pill `▐ ● ▌` whose knob runs to the right end as
it turns on and to the left as it turns off, in 140 ms, its track `primary`
while on and `border` while off, `Switch.pillSpans(theme, at:, enabled:)`
its spans for a painter of one's own (`pill: false`: `[on ]` or `[off]`):
clicked, or Space (hinted) or Enter pressed while it has the focus, it calls
`onChanged` with the value it is to take, with which the app builds it
again.

## `RadioGroup<T>`

`RadioGroup<T>(choices:, value:, onChanged:, direction: Axis.vertical)`
shows its `Choice(value, label, enabled:)`s one below another or side by
side, `(●)` before the one whose value is `value` (`mark:` between the
parentheses, `'●'` by default) and `( )` before the others: one stop of Tab,
where Up and Left choose the enabled choice before the one chosen and Down
and Right the one after, from the last to the first and back (hinted along
its axis), Home and End the first and the last, Space and Enter the one that
shows the focus (the first enabled one while none is chosen); a choice
clicked is chosen, and one not enabled is passed by and cannot be clicked.
Choosing calls `onChanged` with the value.

## `SelectionList<K>`

`SelectionList<K>(itemCount:, keyOf:, itemBuilder:, controller:,
onSubmitted:, itemEnabled:, enabled: true, itemExtent:, focusNode:,
autofocus:, style:, selectedStyle:, cursorStyle:, idleStyle:,
disabledStyle:, bracketStyle:, bar: true)` builds its items as a
`ListView.builder` does and selects them by their keys (`keyOf`) in a
`SelectionController<K>(multiple: false, selected:, cursor:)` (`select`,
`selectAll`, `deselect`, `toggle`, `clear`, `isSelected`; `selected` in the
order selected; its listeners told of each change), so what is selected and
the cursor stay with their items as items are added, removed and moved, the
cursor going to the item at its place when its own goes. While the list has
the focus, Up and Down move the cursor to the enabled item before and after,
Page Up and Page Down a window of rows, Home and End to the first and the
last, the list scrolling to show it; in a single selection the item the
cursor moves to is selected, in a multiple one Space (hinted) selects or
deselects it, each item after `[x]` or `[ ]`; Enter calls `onSubmitted` with
its key; an item clicked takes the cursor and is selected (selected or
deselected in a multiple selection), and the wheel scrolls the list. Without
a controller it has a single selection of its own; it takes all the room it
is given, which must be bounded.

## `Select<T>`

`Select<T>(choices:, value:, onChanged:, hint:, inline: false, rows: 8,
decoration:, …)` and `MultiSelect<T>(choices:, values:, onChanged:,
decoration:, …)` (with a `decoration:`, Flutter's DropdownButtonFormField:
drawn in an `InputDecorator`, the field without its chip, as wide as the
decoration leaves it, `▾` at its right edge in `primary` while focused, the
focus the border's rather than a primary fill, the list right under the
border, from its left edge and as wide as it (`Popover(matchAnchorWidth:
true)`), over the helper) are a field, a blank, the label of the choice
chosen (of a `MultiSelect`, the labels of those selected apart by commas;
`hint`, `muted`, while none is) and `▾`, as wide as the widest label, which
Enter (hinted), Space, Up, Down, typing or a click opens on a list of the
enabled choices, in a `Popover` under it (`overlay`) or, `inline`, always
below it; the popover fades in from what is under it over `popupFadeIn` (120
ms, easing out; zero: at once), as a `DatePicker`'s calendar and an
`Autocomplete`'s suggestions do. Typing filters them, the query shown in the
field: those whose labels have its characters in order, best first
(`fuzzyMatch`), the characters standing out, or `no match`; Backspace takes
its last character off. Up and Down highlight the choice before and after,
from the last to the first and back, Page Up and Page Down a window before
and after; Enter or a click on a choice chooses it and closes the list; in a
`MultiSelect` Space (hinted) or a click selects or deselects one, calling
`onChanged` with the values selected then, the list staying open, Enter
closing it, and Space is typed only in a `Select`. Escape, the focus leaving
the field and a press outside it close the list; inline, Escape clears the
query. At most `rows` choices show, the one highlighted in the theme's
`selection`.

## `ConfirmInput`

`ConfirmInput(prompt, onConfirmed:, defaultValue: true, yes: 'Yes', no:
'No', …)` shows its prompt and the answers (`Delete?  Yes   No `), one
highlighted, `defaultValue`'s at first: while it has the focus `y` answers
yes and `n` no, in either case (both hinted), Enter the one highlighted,
Left and Right highlight yes and no, and an answer clicked is given too;
each calls `onConfirmed` with true for yes and false for no, and highlights
it. A control without its callback (a `SelectionList` with `enabled: false`)
is disabled: in `disabledStyle` (the theme's `muted`), passed by Tab and
deaf to the mouse. Their styles merge over the theme's text: `style` (a
`Button`'s the theme's `primary` bold unless given); the box checked, the
switch on, the mark of the choice chosen and the answer highlighted in
`primary` bold; `focusedStyle` while one has the focus (a group's on its
choice chosen), unless given the theme's `selection` for a `Checkbox`, a
`Switch` and a `RadioGroup`, a fill of the chip's text color with the text
in `onPrimary` for a `Button` and the answer a `ConfirmInput` highlights
(its answers chips of the `surface`), and as each one's documentation says
for the others; a `SelectionList`'s `selectedStyle` (bold in a single
selection) and, while it has the focus, its `cursorStyle` (`selection`, a
`primary` bar `▎` in a column before the items), while it has not, the item
selected in its `idleStyle` (`selectionIdle`, the bar `muted`), the brackets
of its marks in `bracketStyle` (`muted`, the `x` `primary` bold); a
`Select`'s field a chip of the theme's `surface`, filled with `primary`, its
text bold in `onPrimary`, while it has the focus, its `▾` in `arrowStyle`
(`muted`) and kept when the text is cut off, its list a panel of the
`surface` (`popupLook: PanelLook.bordered` for a border in `border`).

## `Slider`

`Slider(value:, onChanged:, min: 0, max: 1, divisions:, focusNode:,
autofocus:, style:, focusedStyle:, trackStyle:, disabledStyle:)` chooses a
value along a track, a line with a thumb a cell wide on it, placed in
eighths of a cell with a block element as a `Scrollbar`'s thumb is (in whole
cells where those are two columns wide), the line before it in its color:
with `divisions` the values of that many even steps, without any between.
While it has the focus Right and Up step it up and Left and Down down (Left
and Right hinted), a division or a hundredth of the range, Page Up and Page
Down a tenth of the range (a division at least), Home and End to `min` and
`max`; the wheel steps it while it has the focus and goes to the views
around it while not. A press of the left button on the thumb grabs it,
elsewhere on the track moves the thumb there and grabs it, and the thumb
dragged moves as many cells as the mouse; a `GestureDetector` around it gets
nothing of the press. It is as wide as it may be and a repaint boundary, the
thumb and the line before it in `style` (the theme's text) or while it has
the focus `focusedStyle` (`primary`), the line after it in `trackStyle`
(`muted`).

## `NumberInput`

`NumberInput(value:, onChanged:, min:, max:, step: 1, decimals: 0,
focusNode:, autofocus:, style:, focusedStyle:, arrowStyle:, errorStyle:)` is
a `TextField` (the keys that edit text are its) with `▴▾` after it (the
field on the theme's `selection` while it has the focus, `focusedStyle`, its
selection a step towards `primary`; `▴▾` `primary` then and `muted` at rest,
`arrowStyle`; a `DatePicker`'s, a `TextFormField`'s and a `FilePicker`'s
field the same): the text typed is taken on Enter, which goes on to the
nodes above (a `Form` moves to the next field), and as the focus leaves it,
rounded to `decimals` digits and kept within the bounds, and text that is no
number gives way to the value then; meanwhile such text shows in
`errorStyle` (the theme's `error`), and Escape puts the value back. Up and
Down (hinted) step the value by `step`, Page Up and Page Down ten steps,
from the number typed if one is, and so do a click on `▴` or `▾` and the
wheel while it has the focus.

## `DatePicker`

`DatePicker(value:, onChanged:, firstDate:, lastDate:, showTime: false,
today:, firstWeekday: DateTime.monday, focusNode:, autofocus:, style:,
focusedStyle:, arrowStyle:, errorStyle:, popupLook: PanelLook.raised,
popupFadeIn: 120 ms, cursorStyle:, controller:)` holds a date, or null, in
such a field with `▾` after it: typed as `yyyy-mm-dd` (`yyyy-mm-dd hh:mm`
with `showTime`), a month or a day of one digit or two, empty for null (the
format shown in `muted`), and taken as a number is, one out of `firstDate`
and `lastDate` as that bound's day at the same time. Up and Down (and the
wheel) step the part of it the caret is in, a year, a month (to the same day
or the last of a shorter month), a day, an hour or a minute, and put the
caret at that part's end; with no date they give `today`. Alt+Down (hinted)
or a click on `▾` opens a `Calendar` under the field in a `Popover`
(`overlay`), on a raised `Panel` (`popupLook`), the date selected, the
cursor filled with `primary` (`cursorStyle`) and the days out of the bounds
muted, which has the focus, its keys hinted as a picker's (`←↑↓→ day   pgup
pgdn month   enter pick`): Enter, Space or a click on a day within the
bounds takes it, at the time the value has, the wheel shows the month before
or after, and Escape, the focus leaving it and the field, and a press
outside both close it, the field getting the focus back. Each of the three
calls `onChanged` with the value it is to take, once that is another, keys
that come before the app builds it again going on from the value the last
one gave; without `onChanged` it is disabled, as a control without its
callback is above. A `Select`, a `MultiSelect` and a `DatePicker` take a
`PopupController` (`controller:`): `open()`, `close()` and `isOpen` drive
the popup from outside, its listeners told of every open and close, the
widget's own keys and mouse too; `open()` gives the widget the focus as well
(a `Select`'s field, a `DatePicker`'s calendar, the field getting it back on
close), a disabled one staying closed, and an inline `Select` only says it
is open; built with the controller open, the widget opens on that build.

## `Form`

`Form(child:, onSubmitted:, onChanged:, autovalidateMode:
AutovalidateMode.disabled)` keeps the `FormField`s below it together. Its
`FormState` (`Form.of(context)`, `maybeOf`, with no dependency; a
`StateError` without a form) validates them (`validate`, each showing its
error), saves them (`save`, each value to its field's `onSaved`, in the
order of the tree), resets them (`reset`, then `onChanged`), and submits
them (`submit`: where one is not valid, the first such that takes the focus
gets it and it returns false; else they are saved, `onSubmitted` is called
and it returns true); `onChanged` is called at each change of a field's
value too. While a field has the focus, Enter that what edits it leaves to
the nodes above moves the focus to the next field that takes it, in the
order of the tree, and from the last submits the form, hinted `next` and
`submit`; a control that takes Enter itself (a `Checkbox`, a `Select`) keeps
it, and Tab moves on.

## `FormField<T>`

`FormField<T>(builder:, initialValue:, validator:, onSaved:,
autovalidateMode:, errorStyle:)` holds a value: `builder` builds what shows
and edits it from the field's `FormFieldState<T>` (`value`, `errorText`,
`hasError`, `isValid`, `hasFocus`, `didChange(value)`, `validate()`,
`save()`, `reset()`, and `focus()`, which focuses the first node below it
that Tab stops at). So a control of a value and a callback plugs in as it
is: `FormField<bool>(initialValue: false, validator: (v) => v! ? null :
'accept the terms', builder: (f) => Checkbox(value: f.value!, onChanged:
f.didChange, label: 'I accept'))`, a `Slider` or a `NumberInput` in a
`FormField<double>`, a `DatePicker` in a `FormField<DateTime>` (`value:
f.value`). `validator` gives the error for a value, null for a valid one,
shown wrapped below what the builder built, in `errorStyle` over the theme's
text (`error` by default); the value starts as `initialValue`, which a reset
gives back with no error. A field validates when its form does and on its
own as its `AutovalidateMode` says, the form's when null: `disabled` never,
`always` at each build, `onUserInteraction` at each change, `onUnfocus` as
the focus leaves it; in every mode a field validated once validates again at
each change until a reset, so its error goes once the value is right and
comes back when it is wrong.

## `TextFormField`

`TextFormField(controller:, initialValue:, validator:, onSaved:,
autovalidateMode:, errorStyle:, …)` is a field of the text a `TextField`
edits, given the `TextField`'s other parameters but `onSubmitted`, so that
Enter goes to the form: its value follows the controller's text, the app's
changes of it too, and a reset puts back the text it started with; with a
`decoration:` its error is the decoration's `errorText`, in place of its own
line under the field, and the field has neither the well nor the selection
of a field without a box.

## `InputDecoration`

`InputDecoration(icon:, labelText:, helperText:, errorText:, counterText:,
counter:, prefixIcon:, prefixText:, suffixIcon:, suffixText:, border:
UnderlineInputBorder(), filled: false, fillStyle:)`, Flutter's, is what a
`TextField`'s `decoration:` draws around it, by an
`InputDecorator(decoration:, child:, enabled: true)` (around any one-row
control too): `icon` before the field outside its border on the row of its
text, a cell apart; the label on the top edge of an
`OutlineInputBorder(type: BorderType.rounded)` (the row in a box, a cell
from its sides) or on a row above the field for an
`UnderlineInputBorder(type: BorderType.single)` (a line under the row) and
`InputBorder.none`, never floating; `prefixIcon` and `suffixIcon` a cell
from the field inside the border, `prefixText` and `suffixText` right
against it, the field `Expanded` between them; `filled` fills the row inside
the border, a cell before and after it, with `fillStyle` (the theme's
`well`); under it the `helperText`, or the `errorText` in its place, and at
the right the `counter` or `counterText` (a `TextField` with a `maxLength`
counts its characters there, `3/40`, without either). The border is in the
theme's `border`, `primary` while the focus is in the child (a
`FocusBuilder`), `error` with an `errorText`; the label `muted`, `primary`,
`error` alike; the icons `muted`, `primary` with the focus; the affixes, the
helper and the counter `muted`; with `enabled` false, `muted` and `border`
whatever the focus and the error, the error's message still shown in
`error`. A `TextField` without a `semanticsLabel` is read by its
decoration's label before its placeholder. `copyWith` gives another with
some parts in place.

## `FilePicker`

`FilePicker(onPicked:, onCancelled:, mode: FilePickerMode.open, directory:,
name:, filters:, showHidden:, multiple:, fileSystem:, autofocus:, bar: true,
cursorStyle:, idleStyle:, fieldStyle:, fieldFocusedStyle:, controller:)`
picks files to open, a name to save as (`save`) or a directory
(`directory`): a field holding the path of the directory shown (the working
directory by default) and the name typed; below it the directory's entries
(`../` but in a root, then the directories, bold, a separator after each,
then the files, each group by name in any case; files of a dot with Alt+H,
hinted, or the `hidden` check; the files of the filter chosen in a `Select`
where `filters` gives more than one, as `[FileFilter('Dart', ['dart']),
FileFilter('All files')]`, by their extensions in any case; no files in the
`directory` mode; `listing` while it is listed, `cannot list:` and why where
it can't be); and on the last row the filter, the check, what was refused or
how many are marked, Cancel (with `onCancelled`) and Open, Save or Choose.
Up, Down, Page Up and Page Down move the selected entry from the list and
from the field, Home and End from the list; Enter, Right on a directory and
a double click take the entry; Left and Backspace go up, the directory left
selected; a name typed is kept as it goes into directories. With `multiple`
(`open` only) Space, hinted, marks files, in any directory, all taken
together in the order marked. Enter in the field and the last button take
the path typed, from the directory shown, absolute or from `~`, with `.` and
`..` resolved: a directory is gone into, a file picked (not in the
`directory` mode), and in the `save` mode a new name in a directory there;
anything else is refused in the theme's `error` (`not found`, `no such
directory`, `not a directory`) until the text changes. The field completes
the name after its last separator from the entries of the directory typed
that the list would show (`Autocomplete`): Tab inserts what they share, and
Enter on a directory goes into it. `onPicked` gets absolute paths.
`fileSystem` is what it lists and finds paths in, a `PickerFileSystem`:
`PickerFileSystem.local` by default, or `PickerFileSystem.memory(paths,
currentDirectory:, homeDirectory:)`, a fixed tree on no disk, a path ending
in a separator a directory (`FileKind` and `DirectoryEntry` are what it
lists); one of an app's own extends it, its `read(file)`, `sizeOf(file)` and
`watch(directory)` (a `DirectoryTree`'s) reading nothing by default, and
`InMemoryFileSystem(paths, contents:, unreadable:)`, the memory one, holds
files' texts and directories that fail to list (`permission denied`), and
`add`, `write` and `remove` change it, telling those who `watch` the
directory. It takes all the room it gets and needs an `Overlay` above. A
`FilePickerController` given as `controller:` reads from outside the
`directory` shown, the entry `highlighted` (the directory above for `../`,
null while it is listed) and the files `selected` (marked with `multiple`,
in the order marked), its listeners told as any of them changes;
`goTo(path)` shows another directory, resolved as the field resolves a path
(a file's directory with the cursor on the file; given before a picker has
it, the directory it starts in), and `refresh()` lists it again, the cursor
kept on its entry and the entries shown meanwhile. `showFilePicker(context,
mode:, directory:, name:, filters:, showHidden:, multiple:, fileSystem:,
title:, width: 60, height: 20)` shows one in a `Dialog` titled `Open`, `Save
as` or `Choose a directory`, its field focused, and completes with the
paths, or with null on Cancel, Escape or a click outside.

## `Callout`

`Callout(child:, kind: StatusKind.info, title:, icon:, onDismissed:,
actions: const [], style:)` (`Callout.text(message, …)` for a string) is a
notice in a box lined in the color of its kind (`StatusKind.styleIn`), what
a command-line tool prints for `a newer version is available`: the kind's
icon (or `icon`) and `title` (by default the kind's name: Info, Success,
Warning, Error) bold in its color in the top edge, the child inside a blank
in from either side, its text wrapping, and the `actions`, buttons, below it
at the right; as wide as what it holds, within its constraints. With
`onDismissed`, `[×]` at the right of the top edge calls it when clicked, as
Escape does while the focus is on one of its actions (hinted); the app then
builds it no more. On plain output there is no box: `ℹ Info: A newer version
is out.`, the actions below it and no `[×]`. A screen reader reads a status
of its title, an alert for a warning or an error, then what is in it.

## `SegmentedButton<T>`

`SegmentedButton<T>(segments:, selected:, onSelectionChanged:,
multiSelectionEnabled: false, emptySelectionAllowed: false,
showSelectedIcon: false, caps: ('[', ']'), focusNode:, autofocus: false,
style:)` joins its `segments`, `Choice`s, into one control on one row, `[
All │ Errors (3) │ Warnings │ Info ]`, those whose values are in `selected`
on: a filter, a view or a mode, where a `TabBar` is too big. One is on at a
time, or any number with `multiSelectionEnabled`; the last one on is turned
off only with `emptySelectionAllowed`; a press that changes something calls
`onSelectionChanged` with the values on then, a new set, and the app builds
the control with it. One stop of Tab: a segment is highlighted, at first the
first one on, Left and Right move it (from the last to the first and back),
Home and End to the ends, Space and Enter press it and 1 to 9 the segment of
that number; a click presses the one clicked. A segment on is in the theme's
`primary`, bold, after `✓ ` with `showSelectedIcon` (always on plain
output), the highlighted one in its `selection` while focused, one that
cannot be pressed (`Choice.enabled`) `muted`, the caps and the `│` in its
`border`, and the mouse over one lights it as a `Button`'s; where the row
does not fit, the labels are cut off with `…` evenly, the longest first.
Disabled with no `onSelectionChanged` or no enabled segment, it takes
neither the focus nor the mouse. A screen reader reads each segment as a
radio button, or a checkbox in a multiple choice.
