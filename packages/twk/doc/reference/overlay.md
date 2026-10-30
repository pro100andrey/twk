# twk reference: `overlay`

[The reference](README.md) · `lib/src/overlay/`, `test/overlay/`

## `Overlay`

`Overlay(child:)`, which an app places itself, as a rule around all of it
and under its `Theme`, so that what goes in it sees the theme: `Theme(data:
…, child: Overlay(child: Home()))`; the binding places none.

## `Overlay.of`

`Overlay.of(context)` (`maybeOf`) finds the nearest;

## `OverlayState.insert`

`OverlayState.insert(entry, above:, below:)`, from outside a build (input, a
timer, a future), shows an `OverlayEntry(builder:)` over the entries shown
(`entries`, the bottom one first), or right above or below one of them. The
overlay is as big as its child, which it lays out as if it were not there;
an entry's widget fills it unless it is a `Positioned`, which places it as
in a `Stack`. An entry is built when inserted and on its `markNeedsBuild`,
and no other entry with it; it fades in from what is under it over its
`fadeIn` (160 ms) as it is inserted, and `remove()` fades it out over its
`fadeOut` (120 ms), then takes it away, the others not built again
(`Duration.zero` for either: at once); it may be inserted again. Where an
entry is not hit, the mouse reaches what is under it.

## `ModalBarrier`

`ModalBarrier(color:, alpha:, onDismiss:)` covers the room it gets and dims
what is under it: each cell keeps its glyph and its attributes, its
background and its text color blended with `color`, `alpha` of 255 of it,
the theme's `shade` at its `shadeAlpha` where they are null (black at half
on a dark theme, at 28 % on a light one) (the core's alpha blending, with
the terminal's default colors where a cell has them), and text in the
default color is drawn faint while the terminal has not told that color (OSC
10); what repaints on its own under it is dimmed again. The mouse does not
reach what is under it, and a click on it calls `onDismiss`.

## `AnimatedModalBarrier`

`AnimatedModalBarrier(animation:, curve: Curves.linear, color:, alpha:,
opacity:, onDismiss:)` is one whose shade follows an animation (a
`ValueListenable<double>` from 0 to 1, along `curve`, times `opacity`),
fading in and out as its animation runs, each tick repainting it with no
build. `showDialog<T>(context, builder, dismissible: true, alignment:
Alignment.center, barrierColor:, barrierAlpha:, fadeIn: 160 ms,
useRootNavigator: true)` shows what `builder` builds over a barrier (the
theme's shade where `barrierColor` and `barrierAlpha` are null), both fading
in over `fadeIn` (160 ms; zero: at once), so that the dialog is not seen at
its first frame: with a `Navigator` above, as a route pushed on it (the root
one, the furthest above, or the nearest with `useRootNavigator: false`), not
opaque, which `Navigator.pop` closes too, as the navigator's back key does
when it is `dismissible`; without one, in an entry of the overlay above. It
returns a future of the result `closeDialog(context, [result])` gives, null
when it is dismissed or leaves the tree with its overlay or navigator. The
dialog is a `FocusScope` that takes the focus as it is shown (a node in it
with `autofocus` gets it), keeps Tab in it, and gives the focus back to the
node that had it when it is closed, also to a dialog it was shown over; the
keys go to the node focused in it and then to the nodes above the overlay or
the navigator, not to the widgets under it; when `dismissible`, Escape and a
click on the barrier close it with null: with a navigator they pop its route
as the back key pops a page (`maybePop`), so a `PopScope` in it that cannot
pop keeps it open, told it did not pop, and the navigator's observers see it
popped (removed, when another route is in front of it), while `closeDialog`
closes it regardless.

## `Dialog`

`Dialog(title:, padding:, shadow:, look: PanelLook.raised, child:)` is the
box it is usually drawn in: a raised panel of the theme's `surface` and
`text`, a cell of room around `padding` and no outline, the title bold on
the first row inside, over the child, and a `BoxShadow` cast beside it where
`shadow` gives one (`Shadow`, `layout`); with `look: PanelLook.bordered`, a
border in the theme's `border` where the room is and the title on its top
edge.

## `Panel`

`Panel(child:, look: PanelLook.raised, padding:, shadow: true, style:)` is
that panel for what floats over the app: the theme's `surface` and `text`
(`style` over them), a cell of room around `padding`, or a border in the
theme's `border` with `PanelLook.bordered` (as big either way), and with
`shadow` the theme's panel shadow to its right and below it
(`Panel.shadowOf(theme)`, black at 55 % on a dark theme, 18 % on a light
one).

## `OptionList`

`OptionList(options:, highlighted: -1, rows: 8, bar: true, thumb: true,
onHighlight:, onSelected:)` is the list of options an autocomplete, a
`Select` and the command palette show: each `Option(label, marks:, detail:)`
its label after a blank, the characters at `marks` (as
`FuzzyMatch.positions` gives them) in `primary` bold and its `detail` in
`muted` at the right edge; the highlighted one in the `selection` with a
`primary` `▎` in its first column (`bar`), at most `rows` shown, moved on to
keep the highlighted one among them, a `▐` in the theme's `border` down the
last column saying where while not all show (`thumb`). The mouse moved onto
a row calls `onHighlight` with it, as the wheel does with the one after or
before, and a click calls `onSelected`; the app highlights.
`showToast(context, message, duration: 3 s, alignment:
Alignment.bottomRight, style:, icon:, look: PanelLook.raised)`: the toasts
of an overlay show in the order they came, three at a time, the others
waiting, each for its `duration` from when it shows, one under another a
cell in from the edges where `alignment` puts them, each a raised panel of
the theme's `surface` with a bar `▌` down its left edge and an icon before
the message in the color of `style` (by default `✓` for the theme's
`success`, `ℹ` its `info`, `⚠` its `warning`, `✗` its `error`), a row of
room above and below and the panel shadow; it slides in from its edge over
200 ms, so that it is not in place at its first frame, and fades out over
the last 260 ms of its time (`look: PanelLook.bordered`: a bordered box
shown and taken away at once).

## `Tooltip`

`Tooltip(message:, wait: 500 ms, look: PanelLook.raised, fadeIn: 100 ms,
showOnHover: true, showOnFocus: true, controller:, child:)` shows its
message, on a chip fading in over `fadeIn` (`look: PanelLook.bordered` and
no `fadeIn`: a bordered box shown at once), once the mouse has rested on the
child for `wait` (a `MouseRegion`), with `showOnHover`, until it leaves, and
once the keyboard focus has been on the child or below it for `wait`, with
`showOnFocus`, until it leaves, whichever of the two holds it keeping it
while the other goes; Escape hides a tooltip that shows, taking the key, and
goes on to the page when none does. A `TooltipController` shows it from the
app at once and until `hide()` or Escape (`show()`; shown before the tooltip
is built, it shows after its first build), and `isShown` tells, its
listeners told, also when the mouse or the focus showed it; with
`showOnHover` and `showOnFocus` false it is the only way. A screen reader
reads the message as the child's hint (`button Help, Opens help`,
`semantics`), whether it shows or not, the chip itself not read. It shows
centred under the child, above it when there is no room below, and moved in
from the sides as far as it fits; it goes with its child in the same frame;
the mouse shows none in the inline mode, where the terminal keeps it.

## `MenuBar`

`MenuBar(menus:, child:, keyLabel:, style:, openStyle:, look:
PanelLook.raised, controller:)` is a row of the titles of its `Menu`s over
its child, which fills the rest of the room it gets, and opens a menu under
its title in an entry of the `Overlay` above: `Overlay(child: MenuBar(menus:
[Menu('&File', items: [MenuItem('&Save', intent: const SaveIntent()),
MenuDivider(), MenuItem('&Quit', onSelected: quit)])], child: body))`. A
`MenuItem(label, onSelected:, intent:, checked:, enabled:)` calls
`onSelected`, or does its `intent` as a key `Shortcuts` binds to it would,
from the node the keys went to first as the menus opened (the nearest
enabled `Action` above that node; with none it is muted and cannot be
chosen), a check mark before it while `checked` is true; a `Menu` opens a
menu of its own beside the one it is in (on the right, else on the side with
more room, moved up where it does not fit below; one of the bar under its
title, ending at its right edge where it does not fit on the right); a
`MenuDivider` is a line between groups. A label marks its mnemonic with `&`
(`&File`, `Save &as`; `&&` is an `&`), drawn underlined: pressed while its
menu is open, in either case, it chooses its entry, or highlights the next
that has it when more than one does, and Alt with the mnemonic of a menu of
the bar opens that menu. The bar is a layer of the focus tree around its
child: F10 opens the first menu or closes those open (hinted `f10 menu`).
Open, the menus take the keys: Up and Down highlight the entry before and
after, of those that can be chosen, from the last to the first and back,
Home and End the first and the last; Enter or Space chooses the entry, or
opens its menu, as Right does; Left closes a menu opened beside another; at
a menu of the bar Right and Left open the next and the previous one; Escape
closes the innermost menu and F10 them all; other letters are taken too. The
mouse: a click on a title opens its menu, and while one is open, moving over
another title opens that one; moving over an entry highlights it and opens
its menu, a click chooses it, a press on a title held down to an item and
released there chooses the item, and a click outside the menus and the bar
closes them, reaching nothing under them. An item shows the first key
`FocusManager.activeKeys` lists for that node as the menus open bound to its
`onSelected` (the same function, a tear-off such as `save`, not a closure
made for the binding) or to an intent `==` its `intent`
(`ActiveKey.binding`), a sequence whole (`ActiveKey.label`: `ctrl+x
ctrl+s`), each key named by `keyLabel` (`KeyCombo.toString` by default); the
focus goes back to that node as the menus close. The menus are raised
panels: the theme's `surface` and `text`, a cell of room around the rows and
no outline, the panel shadow, a divider a quiet line, the entry highlighted
in the `selection` with a `primary` `▎` at its left, the first menu fading
in over 90 ms as they open (`look: PanelLook.bordered`: a border in `border`
with the dividers joining it, the highlighted entry in the `selection`
alone, no shadow and no fade).

## `ContextMenu`

`ContextMenu(items:, child:, keyLabel:, look:, controller:)` opens a menu at
the mouse on a right click and under the focused widget on Shift+F10 (hinted
`shift+f10 menu`), and `showContextMenu(context, items, at:, keyLabel:,
look:)` at a cell of a widget or under the focused one, kept on the overlay:
where it does not fit on the right or below, on the side with more room, and
moved in as far as it has to; a `ContextMenu`'s open menu follows the items
it is built with and closes as it leaves the tree. A `MenuController` given
as `controller:` to a `MenuBar` or a `ContextMenu` opens its menus from the
app, the first entry of the innermost highlighted as the keys do it:
`open()` the first menu of a bar that can open (as F10), `open([0, 2])` its
first menu and the submenu of that menu's third entry (dividers counted; a
context menu's path its rows alone), a context menu `open(null, (x, y))` at
a cell of its child as a right click does or, without `at`, under the
focused widget in it as Shift+F10 does; menus that cannot open stop the
path. `close()` closes them; `isOpen` and `path` say which are open, however
they opened, its listeners told of each change but not of the highlight
moving (a `RangeError` for an index past the entries, an `ArgumentError` for
an entry that is no `Menu` or `at` on a bar, a `StateError` for `open` with
no widget). The entries are values the app builds again: `MenuItem.enabled`,
`MenuItem.checked` and `Menu.enabled` show at once in menus that are open.
F10 reaches the app on the terminals that send it, most of them (GNOME
Terminal takes it until told not to), Alt and a letter where the terminal
sends Alt as Escape before the key (macOS Terminal and iTerm2 once Option is
set to); Alt alone and the Menu key are no keys the app gets. In the inline
mode the menus have the app's rows alone, cut off where they go past them,
and the mouse is the terminal's.

## `Popover`

`Popover(open:, popover:, child:, onDismiss:, fadeIn:, fadeOut:,
matchAnchorWidth: false)` shows `popover` by `child` while `open` (with
`matchAnchorWidth` at least as wide as `child`, following it in the frame
its width changes: `AnchorFollower(matchTargetWidth:)`, which its target
lays out again as its width changes), fading in and out over `fadeIn` and
`fadeOut` (zero, at once, by default), in an entry of the `Overlay` above:
under the child from its left edge; where it does not fit there, on the side
with more room, above the child, ending at its right edge; moved in from the
edges of the overlay as far as it has to. It follows the child as that is
laid out somewhere else, from the frame it moves in, or the next one where
the child moves inside a repaint boundary that repaints on its own.
`onDismiss` is called when it is to close: the focus went from a node in the
child or the popover to one in neither, Escape was pressed while the focus
was in either, or a button was pressed outside both, the press still
reaching what is under it; the app closes it by building it with `open:
false`. It takes no focus: the keys go where the focus is, and those its
nodes leave go to the nodes above the overlay. Its entry is inserted once it
is first built, so one built open shows from the frame after.

## `CommandPalette`

`CommandPalette(child:, commands:, commandsFor:, controller:, openKey:
'ctrl+p', keyLabel:, rows: 10, width: 60, look: PanelLook.raised)` opens, at
`openKey` wherever the focus is in `child` (hinted `ctrl+p commands`), a
dialog at the top of the `Overlay` above (`showDialog`): a field over what
can be done from the node the keys went to first, each `Command(label,
onSelected:)` or `Command(label, intent:)` that calls its callback or whose
intent an enabled `Action` there does, then each key `activeKeys` lists
there with a hint, the hint its label, unless it is bound to what a command
does; each with the first of those keys bound to the same callback or an
equal intent on its right, a sequence whole, named by `keyLabel`. What is
typed filters them by their labels (`fuzzyMatch`), the characters found
standing out: the best match first, then the one run last, then in the order
above; with nothing typed, those run before first, the one run last first.
Up and Down highlight the one before and after, Enter (`enter run`) runs the
highlighted one once the palette is closed and the focus is back where it
was, its callback or its intent from that node as a key bound to it would,
and Escape (`escape close`) and a click outside close it; at most `rows`
show, in a box `width` columns wide or as wide as the overlay: a raised
panel with the panel shadow and no barrier, fading in over 140 ms, the count
of what matches at the right of the field (`3 of 12`, in the theme's `dim`),
the highlighted command in the `selection`; the mouse moved onto a command
highlights it, a click runs it, the wheel moves the highlight (`look:
PanelLook.bordered`: a bordered box, no count, no shadow, shown at once).
`commandsFor(query)` is asked for more commands as it opens and as the query
changes (files to go to, symbols, anything searched), at once or in a
future: they are listed after the palette's own that match, in its order,
not filtered by the match but its characters standing out where they match,
those whose intent nothing does there left out; a future's commands show
when it ends, the answer before showing meanwhile, and an answer to a query
typed over, or that comes after the palette closed, is dropped. A
`CommandPaletteController` given as `controller:` opens the palette from the
app with a query typed, the caret at its end (`open(query: 'git ')`; open
already, it sets the query; given to no palette, a `StateError`), closes it
running nothing (`close()`), and says whether it is open and what is typed
(`isOpen`, `query`), its listeners told as it opens, as the query changes
and as it closes, by the controller, the keys or the mouse.
`fuzzyMatch(query, text)` gives a `FuzzyMatch` (`score`, `positions`) when
each character of the query is in the text, in order with any gaps, ignoring
case (a character a grapheme cluster, two alike when their first code points
are in lower case), null when not; an empty query scores 0. Of the ways the
characters can be found it takes the best: each scores 1, 8 more where it
starts a word (the first character of the text, one after a blank or an
ASCII punctuation mark, a capital after a small letter) and 4 more right
after the one found before it, so `of` scores 18 in `Open file` and 6 in
`Profile`; ways that score alike are told apart the same way each time.
Without an `Overlay` above, `showToast`, `showContextMenu`, `Overlay.of` and
the builds of a `Tooltip`, a `MenuBar`, a `ContextMenu`, a `Draggable`, a
`Popover`, a `CommandPalette`, an `Autocomplete` (`editing`), a `Select` or
a `MultiSelect` that is not `inline`, a `DatePicker` and a `FilePicker`
(`controls`) fail with a `StateError` that says where to place one, as
`showDialog` does without a `Navigator` either.

## `WindowLayer`

`WindowLayer(windows:, child:, focusedStyle:, decorate:, margin:, frame:,
duration: 160 ms)` floats `Window`s over its child and is as big as it; the
app places it, under the `Overlay`, so that dialogs, menus and toasts go
over the windows: `Overlay(child: WindowLayer(windows: […], child:
Home()))`.

## `Window`

`Window(title:, child:, key:, controller:, onClose:, resizable:,
minimisable:, maximisable:, minWidth: 12, minHeight: 3, shadow:,
pointerShapes: true)` is told apart from the others by its `key`, else by
its index; its `WindowController(left:, top:, width: 40, height: 12,
minimised:, maximised:)` (`moveTo`, `resizeTo`), its own where none is
given, holds where it asks to be. The windows are shown inside the layer,
moved in and shrunk as it shrinks and back as it grows. The one in front is
the one the focus went into, pressed in, restored or added last; Tab goes
through them in the order of the list after the child, a window's title bar
first, whatever is in front; a press in a window the focus is not in focuses
its title bar. The mouse drags the title bar to move a window and its edges
and corners to resize it (within `minWidth` and `minHeight` and the layer);
a double click on the title bar maximises or restores it, and the buttons `─
□ ×` (` _ □ × ` in a bordered frame, `▣` while maximised) at its top right
minimise, maximise and close it (`onClose`). With the title bar focused the
arrows move it, Shift and the arrows resize it, Enter maximises or restores
it, `m` minimises and `x` closes it (hinted). A maximised window neither
moves nor resizes. With `pointerShapes`, where the terminal shows the
pointer's shape, the pointer shows what a press does: `grab` over the title
bar and `grabbing` while it moves the window, `ewResize` over the left and
right edges, `nsResize` over the bottom one, `nwseResize` and `neswResize`
over the corners, none of them over a maximised window; the terminal then
reports all motion. False leaves the pointer to the regions around it. A
minimised one keeps its state, out of view and of the focus, as a chip in a
strip on the layer's bottom row (in the order minimised, after the windows
in Tab order), which a click, Enter or Space restores and focuses; the
windows are shown above the strip. Maximising, restoring and minimising a
window take `duration`: it grows or shrinks from where it was to where it
goes, minimised into its chip and restored out of it (`Duration.zero`: at
once). A window is drawn as `frame` says, in the theme's `surface` and
`text`: `WindowFrame.raised` (where they are RGB colors) has no border, its
title bar the surface a step towards the text color, the title bold in
`muted`, merged with `focusedStyle` (the theme's `primary`) while the focus
is in the window, the bar in the `selection` with a `primary` `▎` at its
left while it has the focus, an edge or a corner lit in `primary` while the
mouse is over it or drags it, and `×` in the `error` color under the mouse;

## `WindowFrame.bordered`

`WindowFrame.bordered` (where they are not, as in `ThemeData.terminal`) is a
plain frame, a border in the theme's `border`, that of the one the focus is
in merged with `focusedStyle` and its focused title in `selection`. `shadow`
casts a `BoxShadow` outside the cells the window asks for, painted with it
under the windows in front; `decorate(context, window)` builds what each
window, in its frame, is shown in, taking `margin` cells around it
