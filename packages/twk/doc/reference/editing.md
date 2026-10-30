# twk reference: `editing`

[The reference](README.md) · `lib/src/editing/`, `test/editing/`

## `TextField`

`TextField(controller:, placeholder:, obscureText:, obscuringCharacter: '•',
maxLength:, onChanged:, onSubmitted:, onEditingComplete:, onPaste:,
readOnly: false, enabled: true, textAlign: TextAlign.left, focusNode:,
autofocus:, canRequestFocus:, style:, focusedStyle:, placeholderStyle:,
selectionStyle:, disabledStyle:, cursorShape: CursorShape.bar, keyHints:
true, decoration:)`, a line of text the user edits (on the
`DefaultTextStyle`'s colors over the theme's text, with no background of its
own: it paints over what is under it, a page, a dialog, a selected row, a
gradient, as the gauges, `Sparkline`, `BarChart` and `TextArea` do
(`RenderObject.keepsUnderlay`: the core keeps the styles of the cells under
a repaint boundary that asks, and puts back those of the rows it repaints on
its own; a `TextArea`, which keeps rows and moves them, puts them back
itself under the rows it repaints, `putsUnderlayBack` false and
`putUnderlayBack`, and moves rows only over rows alike, `underlayRowsAlike`;
`Chart`, `DotCanvas` and `Heatmap` paint their background, part of what they
draw); a `Box` around it its edge; `NumberInput`, `DatePicker`,
`TextFormField` and `FilePicker`, fields without a box, sink theirs in the
theme's `well`, underlined in the border's color where the well is the
background): one row as wide as its constraints allow (in a `Row`,
`Expanded` gives it the room left), or, where they leave its width unbounded
and when asked its intrinsic width, as wide as its text or its placeholder
and a column for the caret. While it has the focus a character typed goes in
at the caret, in place of the selection; Left and Right move a character (a
grapheme cluster), with Ctrl or Alt a word, as Alt+B and Alt+F do; Home,
End, Ctrl+A and Ctrl+E to the ends; each of those with Shift selects;
Backspace and Delete delete a character, with Ctrl or Alt a word, as Alt+D
does; Ctrl+W back to a blank, Ctrl+U and Ctrl+K to the ends, Ctrl+D the
character after the caret, each the selection instead when there is one;
Ctrl+Z undoes the last change, a word of typing at a time, and Ctrl+Y (and
Ctrl+Shift+Z) makes it again; Enter calls `onSubmitted` with the text; a
paste goes in as typed, its lines joined by blanks, without the line break
at its end and other control characters. The keys it does not take go up to
the nodes above it: Tab, Escape, Up and Down, Enter without `onSubmitted`,
Ctrl+D with nothing after the caret, Ctrl+Z and Ctrl+Y with nothing to undo
or redo, and the other keys with Ctrl or Alt. While it has the focus, those
it takes that do more than edit are among a `KeyHintsBar`'s, unless
`keyHints` is false: Enter `submit` with `onSubmitted`, Ctrl+Z `undo` while
there is a change to undo; an `Autocomplete`'s before them while its
suggestions show. `onChanged` gets the text after each change the user
makes; `maxLength` limits, in characters, what the user types and pastes,
not a text the controller is given. `onEditingComplete` is called on Enter,
before `onSubmitted` (given alone, it makes Enter submit, hinted `submit`),
and as the focus leaves after a change the user made since it was last
called, as Flutter's is; `onPaste` sees a paste before it goes in and takes
it by returning true, nothing inserted then. While it has something
selected, Ctrl+C copies it to the system clipboard (OSC 52, wrapped for tmux
or GNU screen, as a `SelectionArea` copies) and Ctrl+X cuts it, both hinted
(`copy`, `cut`); with nothing selected the keys go on as before, Ctrl+C
quitting the app, so a user who wants to quit with a selection collapses it
first, and while one exists a sequence that starts with Ctrl+X goes to the
cut instead. `readOnly` lets the caret move and select by the keys and the
mouse, and Ctrl+C copy, but nothing the user does changes the text: the keys
that would edit go up to the nodes above (Enter still submits), the undo
hint is left out, and `onPaste` is still asked. `enabled: false` makes it a
disabled control: it cannot take the focus (Tab passes it by, one focused
loses it), the mouse is ignored, it shows in `disabledStyle` (the theme's
`muted`) over `style`, and a screen reader reads it `disabled`. An obscured
field copies and cuts nothing. A text shorter than the field is placed by
`textAlign` (`start` and `end` by the direction of its paragraph, `justify`
as `start`), the caret's column after it; a longer one scrolls as at the
left. The terminal's cursor, in `cursorShape` (a steady bar by default; a
block or an underline, steady or blinking, or `CursorShape.terminalDefault`,
the shape the user set in the terminal), is at the caret of the focused
field only, so that the terminal's input method composes text there: kept
while the rest of the app repaints, hidden once the field loses the focus or
leaves the tree, and where the caret is cut off. While it has the focus it
is in `focusedStyle` too, over `style` (a field without a box around it
shows the focus so, on the theme's `selection`). The selection shows in
`selectionStyle` (the theme's `selection` by default), the controller's
composing range underlined; the text scrolls sideways to keep the caret in
view, a wide character whole. Empty, it shows `placeholder` (in the theme's
`muted`); with `obscureText` each character shows as `obscuringCharacter`.
`style` goes over the theme's `surface` and `text`. A repaint boundary: a
keystroke repaints nothing else, unless the field takes its width from its
text. It measures and draws its whole text at each change: for a text of
many thousand characters, a `TextArea`. It puts its text together from the
controller's pieces once a change, to draw it, and `onChanged` gets that
text: it costs no join of its own.

## `TextEditingController`

`TextEditingController` (a `ValueNotifier` of a `TextEditingValue`: the
`text`, a `TextSelection` from `baseOffset` to `extentOffset`, the caret,
and the `composing` `TextRange`; offsets in UTF-16 code units, kept within
the text) with `insert`, `replace`, `moveCaret(offset, extend:)`,
`deleteTo`, `selectAll` and `clear`, an edit ending the composing;
`reset([text])` puts a text in, the caret at its end, that is no step to
undo, the history started afresh, for a text the app puts in rather than one
typed (a `FilePicker` sets its paths so, and Ctrl+Z takes back only what was
typed since); `undo` and `redo` (`canUndo`, `canRedo`) take a change back
and make it again, its text as it was and the selection as it was before or
after it, the last `TextEditingController.undoLimit` (100) changes kept:
edits of a character each, one after the other, are one change a word at a
time (typing a word and the blanks after it, Backspace over a word and the
blanks before it, Delete over a word and the blanks after it), a change ends
where the caret is moved and at an undo or a redo, a paste, a word deleted
or a text set (as the part it changes; the same text is none) is one of its
own, and an edit drops the changes undone. The controller keeps its text in
pieces an edit shares with the value before it, so an edit costs its own
size: a keystroke in a megabyte of text is as quick as in a line. `text`
(and `value.text`) is put together from the pieces once after each change,
when asked for, which for a large text is a copy: a listener that does not
need the text does not ask for it.

## `TextBoundaries`

`TextBoundaries` on `String`, where a caret stops: `characterCount`,
`characterIndexAt`, `characterOffset`, `characterStartBefore` and
`characterEndAfter` by grapheme cluster, and `wordStartBefore` and
`wordEndAfter`, a word a run of letters, digits, marks and emoji or a run of
other characters that are not blanks, or with `blankDelimited` what lies
between blanks; the ends of a character or a word are found from the
characters around the offset, as far as the word goes, while counting
characters goes through the text.

## `TextArea`

`TextArea(controller:, placeholder:, minLines: 1, maxLines:, onChanged:,
onEdited:, onSubmitted:, onEditingComplete:, onPaste:, readOnly: false,
enabled: true, focusNode:, autofocus:, canRequestFocus:, style:,
placeholderStyle:, selectionStyle:, disabledStyle:, cursorShape:
CursorShape.bar)`, lines of text the user edits: each line broken by word
into rows as wide as the area (after blanks, which hang past the edge, and
between two wide characters; a word longer than a row between characters; a
wide character that does not fit goes on to the next row), as many rows tall
as its text takes, at least `minLines` and at most `maxLines`, beyond which
it scrolls to keep the caret in view, with no blank rows after the text; the
caret after a line takes a column of its own, on a row of its own after a
full one. As wide as its constraints allow, or, where they leave its width
to it and asked for its intrinsic width, as wide as its widest line and a
column for the caret. The keys edit as in a `TextField`, with the ends of
the caret's line for Home, End, Ctrl+A, Ctrl+E, Ctrl+U and Ctrl+K (Ctrl+U
and Ctrl+K at the start and the end of a line join the lines); Up and Down
move the caret a row, wrapped or not, to the column it had before the first
of them, from the first row to the start of the text and from the last to
its end, and there go up to the nodes above; Page Up and Page Down move it
and the text as many rows as the area shows; Ctrl+Home and Ctrl+End move it
to the ends of the text; with Shift each of them selects. Enter breaks the
line, or with `onSubmitted` calls it with the text, Alt+Enter (Shift+Enter
where the terminal tells it apart) breaking the line then; among a
`KeyHintsBar`'s (`keyHints: true`), Enter `new line`, or `submit` and
Alt+Enter `new line`, and Ctrl+Z `undo` while there is a change to undo; a
paste goes in as typed, its line breaks and tabs too, without its other
control characters. Empty, it shows `placeholder`; the selection shows a
line break in it as a cell, the composing range is underlined, and the
terminal's cursor, in `cursorShape` (a steady bar by default), is at the
caret while it has the focus; its styles are a `TextField`'s, and so are
`onPaste`, `readOnly` (Enter that would break a line goes up), `enabled`,
`disabledStyle` and copying and cutting by Ctrl+C and Ctrl+X;
`onEditingComplete` is called on an Enter that submits and as the focus
leaves after a change. A repaint boundary that lays out and paints the rows
in view and those it counts for its height only, and of those the rows whose
text or selection changed (a scroll, or a line break typed or deleted, moves
the other rows on the screen and paints those that came into view), reading
its text in the controller's pieces: an edit breaks into rows again the rows
from the one before it on, until one starts where one started before, so a
keystroke costs as much in a megabyte of text, of many lines or of one, as
in a line; a line is broken into rows from its start as far as is shown,
once, so moving to the end of a line of a megabyte, or above it from the
line after it, takes as long as that. `onChanged` gets the text put together
from the pieces, for a large text a copy each keystroke, which `onEdited`
and a listener of the controller do not pay for: `onEdited` gets the
controller's value after each change the user makes, before `onChanged`, its
text put together only when it is read.

## `Autocomplete`

`Autocomplete(controller:, suggestions:, child:, trigger:, onSelected:,
rows: 8, popupLook: PanelLook.raised, popupFadeIn: 120 ms)` suggests what to
put in the `TextField` or `TextArea` in `child` that edits `controller`: the
query is the text before the caret, or with a `trigger` (`/`, `@`) the text
after it up to the caret, where the trigger starts a word (at the start of
the text or after a blank, at most 256 characters before the caret) and no
blank follows it. Each time the query changes, `suggestions(query)` gives
the `Suggestion(text, label:, detail:)`s that go with it, at once or in a
future, shown under the field in a `Popover` (`overlay`), at most `rows` at
once, the first highlighted and the characters of the query in each label
standing out (`fuzzyMatch`); with no trigger an empty query asks for
nothing, and an answer that comes after the query changed again does not
show. While they show, the keys that reach the field go to them first: Up
and Down highlight the one before and after; Enter puts the highlighted
one's `text` in place of the query and calls `onSelected` with it (a field's
`onSubmitted` is not called then); Tab puts in the start their texts share
where that is longer than the query and starts as it does, ignoring case,
and does what Enter does where not; Escape hides them. While they show,
those keys are among a `KeyHintsBar`'s, before the field's, unless
`keyHints` is false: `choose` for Up and Down, `put in` for Enter,
`complete` for Tab, the popover's Escape `close` after them; the field's
Enter is left out meanwhile. Hidden or chosen, they show again once the text
changes, not when the caret moves; they hide when the focus leaves the field
and the popover, and when a button is pressed outside both. Without a
trigger the query is put together from the controller's pieces at each
change: for a `TextArea` of a large text, a trigger. Where the app's owner
draws text in visual order (`text`), a `TextField` and a `TextArea` show a
row that holds right-to-left text as it reads (UAX #9; each row of a
`TextArea` in the direction of its line, by its first strong character),
each row starting at the left either way. Left and Right, with Shift too,
move the caret a cell at a time as it is drawn, on past a row's edge in the
direction of its line (a `TextField` stops there), and with Ctrl or Alt a
word, swapped in a right-to-left paragraph; the other keys move and delete
as the text is stored (Home, End, Backspace, Delete, the word and line
deletes), Up and Down keep the column drawn, and a selection is a range of
the text as stored, painted where its pieces are drawn. The caret shows at
the edge of the character beside it whose level is higher, so each offset
has a cell edge of its own. `showCaret(ctx, object, x, y, shape:
CursorShape.bar)` and `hideCaret(ctx, object)` place the terminal's cursor
at the caret of a render object of an app's own, as the fields do theirs
(`twk_term`'s `TerminalView` too): in `shape`, at the cell `x`, `y` of
`object` as it is painted with `ctx`, kept while the rest of the app
repaints, hidden where an ancestor cuts the cell off; one object holds it at
a time, the last to show it, and only that one hides it, so of objects that
show it while they have the focus and hide it otherwise, the one with the
focus keeps it as the focus moves within a frame, whichever paints last. An
object that leaves the tree hides it in its `detach`, with the context it
was painted with last. While no caret shows it, the hidden cursor rests on
what has the focus, once each frame is painted (`TwkApp.run`'s
`beforePresent`): on the focused widget's first cell, or on the cell
`restCursor(ctx, object, x, y)` gave last, where `object` is the focused
widget's or in it and the cell is not cut off (a list's selected row: the
gallery's page list puts it on the page chosen; `clearRestCursor(ctx,
object)` gives it back to the first cell when there is none), so that a
terminal that marks the cursor's row (iTerm2's cursor guide) or follows it
(macOS zoom) shows the focus.
