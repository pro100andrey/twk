# twk reference: `navigation`

[The reference](README.md) · `lib/src/navigation/`, `test/navigation/`

## `Navigator`

`Navigator(home:, routes:, initialRoute:, onGenerateRoute:, onUnknownRoute:,
backKey: 'escape', observers:)` shows a stack of `Route`s, the last pushed
in front: its first, which `initialRoute` names
(`Navigator.defaultRouteName`, `/`, by default), and those pushed on it
until they are popped. A name is made a route by `home` for `/`, by `routes`
(a `PageRoute` of the builder there), by `onGenerateRoute`, then by
`onUnknownRoute`; a `StateError` when none makes it.

## `Navigator.of`

`Navigator.of(context, rootNavigator:)` (`maybeOf`) finds its
`NavigatorState`, whose methods but `removeRoute` are statics of `Navigator`
too: `push` a route, or `pushNamed` one by name with `arguments` (which its
widgets read as `Route.of(context).settings.arguments`), each returning a
future of the result the route is popped with, null when it is popped
without one or the navigator leaves the tree; `pop` the route in front with
a result (a `StateError` for the first route, which stays: `canPop`),
`maybePop` it, put another in its place (`pushReplacement`,
`pushReplacementNamed`), `popUntil` a predicate holds
(`Route.withName('/')`), and `removeRoute` one wherever it is. Routes under
an `opaque` one keep their state but are not laid out, painted or hit by the
mouse. A route pushed takes the focus, in a focus scope of its own, and
popped gives it back to what had it when it was pushed (outside the
navigator too), else to the route in front; none under the one in front can
take it. `backKey` (none when null) pops the route in front when it is not
the first and pops on back (`Route.popsOnBack`), bound in a layer above the
routes (hinted `back`): a route's own bindings take the key first, and with
no route to pop it goes on past the navigator, as to a binding that quits. A
route of one's own subclasses `Route<T>` (`build`, `opaque`, `popsOnBack`);
a `PageRoute(builder:, settings:, transitionDuration: Duration.zero,
reverseTransitionDuration:)` is a screen, there at once, or with a
`transitionDuration` sliding in from the right over the routes under it,
which stay painted and dim in the theme's `shade`, and out again to the
right as it is popped, over `reverseTransitionDuration` (the same where
null), the route under it in front and with the focus at once and the mouse
going past the route as it goes; its own background is the theme's while it
moves, and one that replaces another (`pushReplacement`) slides in over it.
The navigator fills the room it gets (in a `Column`, put it in an
`Expanded`; along an unbounded axis it is as long as the first route it
shows) and holds an `Overlay` over its routes, which their toasts and
tooltips find, so an app with a navigator needs no other; built again, it
builds its routes again. Its `NavigatorObserver`s are told of each route
pushed (`didPush`, the first too, with no route before it), popped
(`didPop`, one for each route `popUntil` pops), replaced
(`didReplace(newRoute:, oldRoute:)`) and removed (`didRemove`, with the
route under it); an observer is given to one navigator at a time, its
`navigator` set while it is.

## `PopScope<T>`

`PopScope<T>(canPop: true, onPopInvokedWithResult:, onPopInvoked:, child:)`
refuses or intercepts a pop of the route it is in: while one in the route in
front cannot pop, the back key and `maybePop` leave the route, even the
first one, whose back key otherwise goes on past the navigator, take the
key, and tell it it did not pop (`onPopInvokedWithResult(false, result)`),
so an app asks before a form that was edited is left; a pop that goes ahead
(`pop`, which `canPop` does not stop, or the back key while it can) tells it
it did. A route's `popDisposition` (`RoutePopDisposition.pop`, `doNotPop`,
`bubble`) is what the back key and `maybePop` do with it, which returns
whether a route was popped or kept.

## `Scaffold`

`Scaffold(body:, header:, sidebar:, statusBar:, keyHints: true,
sidebarWidth: 24, sidebarSide: SidebarSide.left, resizableSidebar: false,
collapsedBelow:, onSidebarResized:, controller:)` is the frame of a
full-screen app: header rows on top, a sidebar beside the body under them,
the status bar and, with `keyHints`, a `KeyHintsBar` at the bottom, each but
the body optional; the header, the sidebar and the hints on the theme's
`chrome`, the header and the hints two columns in from the sides, the body
on its background. Each part but the hints is a zone of the focus, a
`FocusScope`: Tab and Shift+Tab stay within a zone, which gets the focus
back where it had it when it is left; F6 and Shift+F6 move to the next and
the previous zone that has a node to focus, in the order they are on the
screen, and Ctrl+B goes to the sidebar and back to the zone the focus came
from (hinted `f6 next pane`, `ctrl+b sidebar`, `ctrl+b back`), the keys
bound only where they apply, those the nodes of its parts bind coming first.
Below `collapsedBelow` columns the sidebar is collapsed: no columns, not
painted, hit or focusable, its state kept; Ctrl+B shows it and going back
hides it again, the header's `≡` shows or hides it at any width, and the
width crossing `collapsedBelow` puts it back as the width has it. With
`resizableSidebar` a divider between the sidebar and the body, dragged with
the left button, makes the sidebar wider or narrower, between
`Scaffold.minSidebarWidth` (4) columns and all but `Scaffold.minBodyWidth`
(10) of the screen's, the pointer a resize over it and the divider in the
theme's `primary` while hovered or dragged, and while the sidebar has the
focus Alt+, and Alt+. move it a column (hinted `narrower`, `wider`; not the
arrows with Ctrl or Alt, which move a field's caret by words, nor Alt+[ and
Alt+], whose bytes start a CSI and an OSC); `onSidebarResized` is told the
width a drag leaves and each a key makes. A
`ScaffoldController(sidebarOpen:, sidebarWidth: 24)` given as `controller:`
shows, hides and toggles the sidebar (`sidebarOpen`, `toggleSidebar()`) and
sets its width (`sidebarWidth`, a `RangeError` below 0), which the toggle,
Ctrl+B, a drag and the keys set too, for an app to listen to and keep (a
change the width crossing `collapsedBelow` makes told at the start of the
next frame); `focusedZone` is the `ScaffoldZone` (`header`, `sidebar`,
`body`, `statusBar`) that has the focus, and `focusZone(zone)` moves the
focus to one as F6 does, showing a hidden sidebar as Ctrl+B does. With
nothing focused after the first frame, it focuses the first node of the
body, else of the sidebar, the header or the status bar; a node that asked
for the focus (`autofocus`), in it or anywhere else in the app, gets it
instead.

## `Breadcrumbs`

`Breadcrumbs(items:, onSelected:, current:, separator: ' › ', keepLeading:
1, focusNode:, style:, currentStyle:)` is the path to where a screen is,
root first, on one row, each item but the `current` one (the last when null,
in bold: `currentStyle`) a link that calls `onSelected(index)`. Where the
row does not fit, the middle collapses into `…`: the first `keepLeading`
kept, then as many of the last as fit (`Root › … › src › widgets`), then the
leading ones go too (`… › widgets`) and the last is cut off; never wrapped.
One stop of Tab: a crumb is highlighted, at first the one before the
current, Left and Right move it, Home and End to the first and the last,
Enter selects it (Left, Right and Enter hinted); Enter or a click on the `…`
opens a `Menu` of the items it hides, and a click on a link selects it, the
mouse over one underlining it. Links and the `…` are in `style` (the theme's
`primary`), the separators `muted`; with no `onSelected` it is shown only,
taking neither the focus nor the mouse. A screen reader reads a list of
every item, the hidden ones too, each a link, the current one `selected`.

## `Pagination`

`Pagination(page:, pageCount:, onChanged:, itemCount:, pageSize:, siblings:
1, showFirstLast: true, showPrevNext: true, focusNode:, style:,
currentStyle:)` is the `pageCount` pages of a list loaded a page at a time
on one row, `« First ‹ Prev 1 [2] 3 4 5 … 42 Next › Last »  (21–40 of 840)`:
the first and the last page, the current one (`page`, from 0) in brackets
with `siblings` pages on either side, `…` between them and the ends (a gap
of one page shows that page), the arrows (`showFirstLast`, `showPrevNext`)
muted where there is nowhere to go, and with `itemCount` and `pageSize` the
items shown. Where it does not fit, the words of the arrows go first, then
the siblings one by one, then the range, then it is cut off at the right;
never wrapped. `onChanged` gets the new page and the app builds the row with
it; null, all of it is muted and takes neither the focus nor the mouse. One
stop of Tab: Left and Right go a page back and on, PageUp and PageDown ten,
Home and End to the first and the last, and digits typed show after the row
(`→ 12`) until Enter goes to that page (Backspace takes one back, Escape or
another key drops them), Left, Right, the digits and, while some are typed,
Enter hinted; a click on a page or an arrow goes there. A screen reader
reads a list of buttons, `Page 2` and `Next page`.

## `Stepper`

`Stepper(steps:, controller:, direction: Axis.horizontal, linear: true,
onFinished:, onStepChanged:, backLabel: 'Back', nextLabel: 'Next',
finishLabel: 'Finish', showControls: true)` is a wizard: one step shown at a
time under the headers of all of them, its Back and Next under it. Each
`Step(title:, content:, subtitle:, state:, validate:)` has a header of its
number and title after the mark of its `StepState` (`indexed` `○`, `editing`
`●` and its title bold, `complete` `✔`, `error` `✗` in the theme's `error`,
`disabled` muted; by default those before the current one complete and those
after it indexed), `✔ 1. Project Info ── ● 2. Dependencies ── ○ 3.
Confirmation`, a row that does not fit giving way to `Step 2 of 3 ·
Dependencies`;

## `Axis.vertical`

`Axis.vertical` puts the headers in a column, the current content and the
buttons under its own, two columns in. Next, or PageDown (which comes up
from the content, so a field keeps Enter), validates the step and moves on:
`validate` answers null, or a refusal shown under the content, at once or in
a future, while which a `Spinner` is in the button and the stepper ignores
the keys (Ctrl+C aside) and the mouse; on the last step it is `finishLabel`
and calls `onFinished` once the step is taken. Back, or PageUp, goes back at
once; both keys are hinted. A click on a header goes to that step, on a
`linear` stepper only to one before the current, otherwise to any but a
disabled one, validating nothing. Only the current step's content is built,
so what it holds is the app's (a `TextEditingController`); as the step
changes, a focus that was in the stepper goes to the new content's first
stop, Next where it has none, and `onStepChanged` gets the step. A
`StepperController(initialStep: 0)`, one of its own when none is given,
holds the `current` step, the last refusal (`error`) and whether a
validation is waited for (`validating`), and moves the stepper from the app:
`next()` and `goTo(step)` past the steps that validate, completing with
whether it moved, `back()` at once; with `showControls` false the app shows
its own buttons, the keys still there. A screen reader reads the headers as
a list, the current one `selected`
