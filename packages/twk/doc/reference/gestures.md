# twk reference: `gestures`

[The reference](README.md) · `lib/src/gestures/`, `test/gestures/`

The mouse by a hit test of the last frame.

## `Listener`

`Listener(onDown:, onUp:, onMove:, onDrag:, onScroll:, behavior:, child:)`
(`RenderListener`) gets a press, a release, motion with no button held and
with one, and the wheel, each a `PointerEvent`: its `kind`, the cell (`x`,
`y`) in the coordinates of the widget and on the screen (`screenX`,
`screenY`), the `button` (0 left, 1 middle, 2 right, 8 to 11 the side
buttons), the `modifiers` (`shift`, `alt`, `ctrl`) and what the wheel
scrolls (`scrollY`, `scrollX`). It is hit where its child is
(`HitTestBehavior.deferToChild`; anywhere in it when `opaque`). A press,
release, move or drag goes to every `Listener` hit there with a callback for
it, the deepest first; once a button is pressed, drags and releases go to
the `Listener`s the press was hit in, wherever the mouse goes, until the
last button is released; the wheel goes only to the deepest `Listener` hit
there with an `onScroll`, so of two scrolling views one inside the other
only the inner one scrolls; what no `Listener` takes goes to the
`InputListener`s.

## `MouseRegion`

`MouseRegion(onEnter:, onExit:, onHover:, cursor:, behavior:, child:)`
(`RenderMouseRegion`) is told when the mouse comes in, moves inside with no
button held, and goes out, and while the mouse is in it the pointer has the
shape of its `cursor` (a `PointerShape`, the core's OSC 22,
[§1.7](../../../twk_core/doc/design.md#17-terminal-and-platforms)), or of
the nearest region around it with one, the terminal's own outside them all:
written as it changes, with the mouse or with a frame that moved a region,
only where the terminal is known to show it, and the terminal's own put back
when the app ends or hands the terminal over; it is hit anywhere in it
(`opaque`, hiding what it covers; `translucent` lets that be hit too), and a
region inside another is in both. The regions the mouse is in are kept
between events: those it left are told first, the deepest first, then those
it came into, the outermost first, then the hover; a frame that moves a
region under the mouse or away from it tells it so, and a region that leaves
the tree is not told. The terminal reports the mouse only while a `Listener`
or a `MouseRegion` with a callback, or with a `cursor` the terminal shows,
is mounted, from the frame that mounts the first to the one that unmounts
the last, as little as their callbacks need (the core's `MouseTracking`):
presses, releases and the wheel (mode 1000) for `onDown`, `onUp` and
`onScroll`, motion with a button held (1002) for `onDrag`, all motion (1003)
for `onMove` and a `MouseRegion`; meanwhile the terminal's selection and
wheel work in an app that uses no mouse. In the inline mode the mouse stays
the terminal's.

## `IgnorePointer`

`IgnorePointer(ignoring: true, child:)` lets the mouse through its subtree
to what is under it: nothing in it is hit, its `MouseRegion`s are left and
those under it entered at the end of the frame that turns it on, and a press
made before keeps the `Listener`s it was hit in until its release.

## `AbsorbPointer`

`AbsorbPointer(absorbing: true, child:)` stops the mouse there: it is hit
itself and nothing in it, so neither the subtree, nor what it covers, nor
the app's `InputListener`s get the presses, motion and wheel over it, nor
the drags and the release of a press it took; the `Listener`s around it are
hit as they would be (a scroll view around it still gets the wheel).

## `GestureDetector`

`GestureDetector(onTap:, onDoubleTap:, onLongPress:, onLongPressEnd:,
onDragStart:, onDragUpdate:, onDragEnd:, buttons: {0}, doubleTapInterval:
300 ms, longPressDuration: 500 ms, behavior:, child:)`, a `Listener`
underneath, tells the gestures of the presses of the `buttons` it takes: a
press is a drag once the mouse moves to another cell with the button held
(`DragDetails`, the event and the cells moved since the drag was told last,
`dx` and `dy`: the start at the press, then each cell it moves to, the end
at the release), a long press once it is held for `longPressDuration` with
the mouse over the detector, else a tap when it is released over it. With an
`onDoubleTap` a tap waits `doubleTapInterval` for the next press: a tap of
the same button then is a double tap, else `onTap` is told of the first
before any gesture that follows. Detectors one inside another compete for a
press: each gesture goes to the deepest that recognises it (a callback for
it and, for a tap or a long press, the mouse over it), and a press is one
gesture. The intervals are timers of the app's zone, which a test moves with
`t.pump(duration)`; while it has a callback the terminal reports presses and
releases, and motion with a button held for a long press or a drag.

## `SelectionArea`

`SelectionArea(child:, style:, copyOnRelease: true, copyKey:, clearKey:
'escape', trimTrailingBlanks: true, onCopy:, copyTransform:, controller:,
multiClickInterval: 300 ms)` lets the `Text`s below it be selected with the
left button, as in a terminal: a drag from one cell to another selects the
characters between them, those of both cells too, across the Texts in the
order of the tree (each one's text in order, whatever rows it wraps to); a
double click selects the word under the mouse (or the run of blanks), a
triple click the line between its Text's line breaks, and a drag after
either goes on by words or by lines; a click is the next of a double or
triple one in the same cell within `multiClickInterval` of the release
before it, and the first press of one clears the selection, as `clearKey`
does (with nothing selected the key passes on; null for none). A press or a
drag over no Text goes to the Text nearest it, by rows first; a press in a
`TextField` or a `TextArea` is the field's, clearing the selection here. A
render object of an app's own that mixes in `Selectable` (a painted log, a
code view) is selected in as a Text is, in its place in the order of the
tree, the area walking the render tree to find it: its `selectableText` (an
empty one takes no part), the range of that text a cell is in
(`selectableRangeAt(x, y)`, cells that are not text, such as line numbers,
at the start of their row, so they are left out), and the `selection` and
`selectionStyle` it is to paint (`selectionStyleAt`), the area marking it
for paint when they change. A drag past the top or bottom of the nearest
vertical `Scrollable` around the Text or Selectable nearest the mouse,
inside the area or around it, scrolls it on every 50 ms while the mouse
stays there, by the rows it is past (3 at most), the selection going on to
what comes under the mouse, and past the left or right edge the nearest
horizontal one sideways by the columns, past a corner both; a `Selectable`
that scrolls itself does first (`scrollSelectionBy`,
`scrollSelectionAcross`); where the view starts at the screen's first row or
column or ends at its last, that one counts as past it, as a terminal
window's edge does. What scrolls under the mouse while it stays (the wheel
turned with the button held) is selected on to as well. What is selected is
drawn in `style` merged onto the text's own (the theme's `selection` by
default), only the Texts whose part changed built again; it is copied on the
release that selected it (`copyOnRelease`) and by `copyKey` (bound as
`KeyBindings` binds a key: with nothing selected it passes on), as OSC 52
(`clipboardSequence`) to the binding's terminal, wrapped for tmux or GNU
screen when the app runs inside one (the core's README, §1.11), and `onCopy`
is told the text: the Texts joined by line breaks, with `trimTrailingBlanks`
the blanks before each line break left out, and at the end of the selection
those only blanks follow to the end of its line, as xterm, VTE, kitty,
Alacritty, WezTerm and tmux copy, and `copyTransform` making of that what is
copied (what it makes empty is not copied). While something is selected,
`copyKey` and `clearKey` are among a `KeyHintsBar`'s (`copy`, `clear`). A
`SelectionAreaController` given as `controller:` lets what is outside the
area (a view showing other text, a key bound wherever the focus is) read and
clear the selection: `hasSelection`, its listeners told when that changes,
`text`, what is selected as it is copied, and `clear()`. It gets every press
over it, as a `Listener` does, and the drags no `GestureDetector` inside it
takes; mounted, it has the terminal report presses and drags, so the
terminal's own selection does not work over the app; in the inline mode
nothing is selected.

## `Draggable<T>`

`Draggable<T>(data:, feedback:, child:, childWhenDragging:, onDragStarted:,
onDragCompleted:, onDragCanceled:, behavior:, pointerShapes: true)` drags
its `data` with the left button once the mouse moves to another cell:
`feedback` follows the mouse in the `Overlay` above (without one its build
fails), placed where the child was at the press and moved as the mouse moved
since, as big as it likes, cut off at the overlay's edges and never hit, and
`childWhenDragging` shows in the child's place meanwhile. Released over a
target that accepts the data, `onDragCompleted` is told after the target got
it, elsewhere `onDragCanceled`. A drag is a gesture of the press as a
`GestureDetector`'s are: it takes the press from the detectors around it (no
tap at the release), and does not start where one inside it took the press
first as a drag or a long press. A drag whose release the terminal did not
report is canceled at the next press, or at motion with no button held; a
`Draggable` that leaves the tree while dragged ends the drag. Mounted, it
has the terminal report presses and releases, and motion with a button held
only while it is pressed. With `pointerShapes`, where the terminal shows the
pointer's shape, the pointer is `grab` over the child, `grabbing` while it
is dragged and `noDrop` while the drag is over targets none of which accepts
it, as a `MouseRegion`'s `cursor` sets it, and the terminal reports all
motion; false leaves the pointer to the regions around it.

## `DragTarget<T>`

`DragTarget<T>(builder:, onWillAccept:, onAccept:, onLeave:, onMove:,
behavior: translucent)` takes the data dropped on it: at each cell the drag
goes to, the targets there are asked, the deepest first, as the drag comes
over them, until one accepts it (its data is a `T` and `onWillAccept`, if
any, says yes); that one gets the drop (`onAccept` with `DragTargetDetails`,
the data and the event, at the release), those asked before it reject it,
those around it are not asked. A target asked is not asked again until the
drag leaves it (`onLeave`) and is told each cell the drag goes to over it
(`onMove`); `builder(context, candidate, rejected)` builds it again as a
drag comes over it and leaves, for a highlight. What its callbacks throw
ends the app, in the target. `test/gestures/drag_drop_test.dart` reorders
the rows of a `Column` by dragging them onto each other
