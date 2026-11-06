# Changelog

## Unreleased

Breaking:

- `Actions` and `Shortcuts` take `actions:` and `shortcuts:` by name, as
  Flutter's do, where they took the map positionally. `Shortcuts.combos` still
  takes its map first.
- `showDialog`, `showToast` and `showContextMenu` take their `context` by name,
  as Flutter's `showDialog` does, with `builder` (`showDialog`), `message`
  (`showToast`) and `items` (`showContextMenu`), where they took them
  positionally: `showDialog(context: context, builder: (context) => ...)`.
- `GestureDetector` and `Pressable`: `onTap`, and `GestureDetector`'s
  `onDoubleTap` and `onLongPress`, are `VoidCallback`s, as Flutter's, where
  they took the `PointerEvent`. `onTapDown` takes `TapDownDetails`, and the
  new `onTapUp` (on `Pressable` too, told before `onTap`) `TapUpDetails`, each
  with `localPosition` and `globalPosition` in cells (`CellOffset`, `dx` and
  `dy`) and the `event` for the button and the modifiers: where a tap, a double
  tap or a long press was, and with which button, is `onTapUp`'s now. Flutter's
  `kind` of the details is not there: a terminal reports none. `onLongPressEnd`
  still takes the `PointerEvent`.
- `DragDetails` is Flutter's `DragStartDetails`, `DragUpdateDetails` and
  `DragEndDetails`: `onPanStart`, `onPanUpdate` and `onPanEnd` take one each,
  and `DragListener` is `GestureDragStartCallback`, `GestureDragUpdateCallback`
  and `GestureDragEndCallback`. Each has `localPosition` and `globalPosition`
  in cells, a `CellOffset` (`dx`, `dy`), where it had `x` and `y`; the update
  has `delta` for `dx` and `dy`, and the end no move. They keep `event` for the
  button and the modifiers. Flutter's `sourceTimeStamp`, `kind`, `primaryDelta`,
  `velocity` and `primaryVelocity` are not there: a terminal gives none.
- `PopScope.onPopInvoked` is removed, as it is in Flutter:
  `onPopInvokedWithResult` is told the same, with the result.
- `debugDumpTree` is `debugDumpApp`, as Flutter names the function that prints
  the element tree; it still takes a `BuildContext`.
- `Scrollbar` takes `timeToFade`, as Flutter names it, where it took
  `hideAfter`.
- `DragTarget` takes `onWillAcceptWithDetails` and `onAcceptWithDetails`, as
  Flutter names them, where it took `onWillAccept` and `onAccept`; they take the
  same `DragTargetDetails`.
- `showDialog` takes `barrierDismissible`, as Flutter names it, where it took
  `dismissible`.
- `Listener` takes `onPointerDown` and `onPointerUp`, as Flutter names them,
  where it took `onDown` and `onUp`. Its `onMove` stays: it is motion with no
  button held, which is Flutter's `onPointerHover`, where Flutter's
  `onPointerMove` is motion with one held, `onDrag` here.
- `GestureDetector` takes `onPanStart`, `onPanUpdate` and `onPanEnd`, as Flutter
  names them, where it took `onDragStart`, `onDragUpdate` and `onDragEnd`.
- `ScrollMetrics` and `ScrollPosition` have `pixels`, `maxScrollExtent` and
  `viewportDimension`, as Flutter names them, where they had `offset`,
  `maxOffset` and `viewportExtent`; `ScrollController.offset` stays.
  `ScrollController`, `ListController` and `useScrollController` take
  `initialScrollOffset`, not `initialOffset`.
- `TabView` is `TabBarView`, as Flutter names the content of a `TabBar`.
- `Text`, `Text.rich`, `Text.line` and `Text.richLine` take `textAlign`, as
  Flutter names it, where they took `align`; `RenderParagraph` keeps `align`.
- `BoxConstraints` has `minWidth`, `maxWidth`, `minHeight` and `maxHeight`, and
  `constrainWidth` and `constrainHeight`, as Flutter names them: they were
  `minW`, `maxW`, `minH`, `maxH`, `constrainW` and `constrainH`.
- `Flex`, `Row`, `Column` and `Wrap` take `spacing` and `runSpacing`, and
  `RenderFlex` and `RenderWrap` have them, as Flutter names them: they were
  `gap` and `runGap`.
- `log`, `LogLevel`, `LogRecord` and `LogSink` are in `package:twk/log.dart`, out
  of `twk.dart`, so that `twk.dart` beside `dart:math` no longer clashes over
  `log`: an app that logs imports `log.dart`, and one that had `hide log` or
  prefixed `dart:math` for it drops that where it does not import `log.dart`;
  an app that imports both `log.dart` and `dart:math` still needs a prefix or a
  `hide`.
- `formatBytes`, `formatTook` and `ByteUnits` are in `package:twk/format.dart`,
  out of `twk.dart`: an app that writes a size or a time, or sets a widget's
  `byteUnits:`, imports it.
- `Mark`, the base of `CellMark` and `TextMark`, is `GlyphMark`.
- `WindowTitle` is `TerminalTitle`, as `TerminalProgress` is named: it sets the
  terminal's title.
- `TaskStatus` is `TaskItemStatus`, the status of a `TaskItem`.
- `Link` is `Hyperlink`: an app that wrote `hide Link` for dart:io's `Link` drops it.
- `twk.dart` no longer exports `ModeReport`, `KeyboardFlagsReport`,
  `DeviceAttributes`, `ColorReport`, `CursorReport` and `UnknownSequence`, the
  terminal's answers an app seldom reads: `package:twk_core/terminal.dart` has
  them. A `switch` over `InputEvent` that named them ends in `_ => ...` instead.
- `ScrollBehavior` and `ScrollConfiguration`, as Flutter has them, say what the
  wheel does: `App(scrollBehavior:)` for the app, `ScrollConfiguration` for a
  subtree. A `Scrollable` gathers the wheel's events into whole cells once a frame,
  dense events a cell each with an acceleration, sparse ones 3 as before. Dense is
  told by the events' timing, so it takes a mouse wheel too where a terminal sends
  a notch as a burst: a notch is reported to move 3 rows where it moved 9 (kitty,
  alacritty, Apple's Terminal) and 9 where it moved 27 (Ghostty, Warp).
  `ScrollBehavior.fixed(3)` is a plain step an event. `wheelStep`,
  `wheelAcceleration` and `WheelAcceleration` are gone, and a wheel moves the view
  at the next frame, not in the event.
- `Popover.onDismiss` is required: `null` for a popover the app never closes this
  way.
- `Ticker.binding` and `Steps.binding` are typed by what they use of it, the
  time of the frame and frame callbacks, not `AppBinding?`: an `AppBinding` goes
  in as before, and a test without an app gives twk_test's `FakeFrameClock`. Code
  that read another member through them keeps its own `AppBinding`.
- `Cli.current` is gone, with the zone value `Cli.run` set: the body gets its
  `cli` as a parameter, and a program passes it to the helpers that use it. A
  program that made its own `Cli()` closes it itself, as before. Nothing in
  the packages read it.
- `PointerMode.auto`, the default, shows the hand everywhere in a local session,
  where a control had it on one screen and not on another: an app that sets
  nothing now asks a terminal that shows pointer shapes for the mouse's motion
  (mode 1003). In a remote session (`TerminalInfo.remote`) it asks for none, as
  before. `PointerMode.off` asks for none anywhere, in a `Theme` around one
  widget or the whole app. `TerminalStatus.handAsksMotion` is the rule.
- A press on a cell a `GestureDetector`'s `tapAt` refuses goes to the detectors
  around it, where the sites that moved to `tapAt` took it and did nothing: a
  click on a `Stepper`'s step that can't be chosen, a `Calendar`'s day out of its
  range or a `Select`'s empty row reaches what wraps them.
- `ThemeData.handPointer`, `HandPointer` and the `pointerShapes` of `Window`,
  `SplitView`, `Table`, `TreeTable` and `Draggable` are gone, see below.
- `runApp` while a `Cli` session has the terminal throws a `TerminalException`,
  where it drew and never got a key: `Cli.suspend` around it, or `Cli.close` first
  ([twk_core's changelog](../twk_core/CHANGELOG.md)).

Changed:

- `TwkStrings`, a const class with English defaults, holds the words twk writes
  itself (`ETA`, ` in 3.1 s`, `+3 more`, `Y/n`, refusals, prompts, filter hints)
  and `decimalSeparator`. `Localizations(strings:, child:)` and
  `TwkStrings.of(context)` give them to widgets, `Cli(strings:)`, `Cli.run` and
  `Cli.runWithArgs` to a console. A guide shows it with slang.
- `formatBytes`, `formatTook` and `ProgressTask.summary` take `decimalSeparator:`.
- A confirmation also takes the first letters of `TwkStrings.yes` and `no`, after
  `y` and `n`; a letter both words start with asks again.
- `runApp` and `AppBinding` take `maxInputFps`
  ([twk_core's changelog](../twk_core/CHANGELOG.md)).
- A `Text` of eight rows or more that is edited without changing its size
  repaints only the rows that changed, by itself: nothing to set.
- `tailFile` reads a look through one handle: a file renamed over the name
  between its length and its read is no longer read at the old range, its first
  lines lost. A look with nothing to read opens nothing, so Windows does not
  refuse the writer a rename, and `cancel` ends with the handle closed.
- A widget that watched a provider in one build and only selects in a later one
  is told of what it selects, where it stayed told of every change.
- `Semantics.nodes` keep their hints while the `Semantics` is not focused.
- A popover closes when a layer over it gives the focus elsewhere as it closes,
  where it stayed open without the focus.
- A `ProgressList` that takes the room it needs takes that of its words, in
  `TwkStrings.eta` and `moreTasks`, and lays out again when they change.
- `Table` and `TreeTable` take `marks:`, a `SelectionController<Object>(multiple:
  true)` that marks rows by key, beside the row selected. A checkbox column comes
  before the columns; Space and a click on a checkbox toggle a mark, and marks
  stay with their rows as they are sorted. A tree's node marks itself alone.
- A dialog or menu opened from a `Popover` no longer dismisses it. A closing
  dialog, menu or popover gives the focus back to the node that had it as it
  opened, and Escape closes the layer the focus is in.
- `twk shell` no longer drops an app that sends a frame of a type it does not
  know: it is ignored and logged. The VS Code extension's shell does the same.
- `AnsiStream.reset()` starts it over: the line, a character or an escape
  sequence cut short, the style. A followed file that starts over uses it.
- A row `SelectionList.itemEnabled` refuses, in a multiple list, has a blank for
  its mark, where it drew a muted `[ ]`: such a row can be a group's header. One
  that is selected, an option locked on, keeps its `[x]`.
- `Cli.session()` is public: a program mounts a live widget, a `TaskList` with its
  steps, below what it logs. A session a program closed is forgotten, the next one
  asked for a new one.
- `Cli.show` of a `Table`, `TreeTable` or `ListView` with items and no height for
  them warns, in a pipe and in a live session, in a release build too, where the
  rows went missing without a word.
- The docs of `Cli` say what `Cli.suspend` is for around `runApp`, what Ctrl+C
  reaches, and that what scrolls needs a height in `Cli.show`.
- A row a `ListView` kept, rebuilt as it comes back, can be marked again before
  the next build, where that failed an assert and ended the app with asserts on.
- `GestureDetector.onTapDown` is told only of a press the detector takes part in,
  not of a left press while another button is held, which no tap comes of.

- `CliTerminal.promptShown(question)`, told as a prompt takes its answer: nothing
  on the process's terminal, what a test's terminal answers by.
- `Text.line` and `Text.richLine` take `align` and `overflow`: a line set right or
  cut at its start needs the long form of `Text` no more.
- `Cli.confirm` says what to press: `(y/n)` after the question, Tab moves the
  highlight as Left and Right do, and Enter with no answer highlighted says
  `answer y or n`, where a question with no default looked stuck.
- A row a `ListView` keeps out of its window no longer rebuilds there: it builds
  as it comes back. A `SelectionList`'s cursor moving rebuilt the kept rows too,
  which asked `itemEnabled` and the like about an index the list no longer had.
- What is dirty below a `LayoutBuilder` given a new widget waits for its build,
  as in Flutter. It was rebuilt first, with the old widget above it, so a row
  of a list could read a list that had shrunk with the old `itemCount` and
  throw a `RangeError`.
- A key flushes an `autofocus` still waiting, one a layout built, so it comes to
  that node and not to the one that had the focus. `FocusManager.autofocusPending`
  says one waits.
- `copyToClipboard(context, text)` is exported: an app copies as a
  `SelectionArea` and a `TextField` do, by OSC 52, wrapped inside tmux or GNU
  screen.
- `RadioGroup` and `ValueStepper` take `canRequestFocus`, as `Button` and
  `Pressable` do: false for a control of the mouse only, which Tab passes by
  and a click leaves the focus where it was.
- A `SelectionArea` copies a blank line where rows lie between two `Text`s, as
  between the paragraphs of a `MarkdownView`, which ran together; those
  side by side or right under each other are joined by a line break, as
  they were.
- `MenuItem(shortcut:)`, a key of the item's own: shown on its right and
  pressed while its menu is open, where a key had to be bound to the same
  function to show and a letter in the label to be pressed.
- `ThemeData.pointerMode`, `PointerMode.off`, `.auto` or `.on`, is the one setting
  of the shapes the widgets set: it replaces `ThemeData.handPointer` and
  `HandPointer`, and the `pointerShapes` of `Window`, `SplitView`, `Table`,
  `TreeTable` and `Draggable`, which a `Theme` around them does now. Breaking.
- The pointer follows the press. A `GestureDetector` with `onTap` shows the
  hand by `ThemeData.pointerMode`, with nothing else to write; `cursor` puts
  a `PointerShape` of its own in its place, `PointerShape.arrow` for a click
  that presses nothing, and `tapAt` says which cells of a row a tap is on,
  for the hand and the tap at once. `onTapDown` answers as the button goes
  down.
- The hand shows over everything a click presses, `RadioGroup`, `ConfirmInput`,
  `Calendar`, `Heatmap`, `Window`'s buttons, `NumberInput`'s arrows and
  `DatePicker`'s among them, which showed none. Rows of a list keep the arrow.
- `Pressable(behavior:)`: `HitTestBehavior.opaque` takes a press on its empty
  cells too.

## 0.2.0

- After a Ctrl+C ended the inline session, a program that handles SIGINT
  and goes on gets a new session for its next prompt or progress. The
  prompt was cancelled at once with `PromptCancelReason.endOfInput`, and a
  progress was written as lines, because stdin was taken for closed.
  `Cli.close()` still ends the console for good. `FakeCliTerminal` opens
  its inline terminal again once the last one is closed.
- `Cli.suspend(run)` hands the terminal to another program while `run`
  runs, one that reads the terminal itself (`sudo` asking for a password, a
  package manager, a pager, an editor), and takes it back after. The inline
  session's region stays with the cursor on the line below it, raw mode is
  off and the session's input paused, and the session is drawn again below
  what was printed. Such a program used to print in the middle of the
  region and never get what was typed.
- Each pipeline that draws a theme mark the terminal can't draw one column
  wide (`Glyphs.cursor: '日'`) is warned once in its own log, where only
  the first of the pipelines sharing a segmenter was: the verdict is kept
  for the segmenter, and the warning came only with measuring it.
- `Cli.close()` closes the terminal when the inline session failed to
  open, where it threw the open's error again and left the terminal open.
- A line `Cli` logs or writes while its inline session is still opening
  (`cli.info` right after `cli.progress`) goes above the session once it is
  open. It was written to stdout while the opening session flushed it, and
  threw "StreamSink is bound to a stream".
- In visual order the rest of the user's text a widget paints itself reads
  as a `Text` draws it, each label through a `TextPainter` the render
  object keeps: the labels of a `ProgressList`, the messages and lines of
  the `Console`, the labels of `Gauge` and `LineGauge`, of `BarChart` and
  `Heatmap` (their legend too), the axis titles, labels and dataset names
  of a `Chart`, the labels a `DotCanvas`'s draw function sets, the month
  and weekday names of a `Calendar` and the key labels of the entries of
  menus. They drew `שלום עולם` where `Text` draws `םלוע םולש`. A label too
  long is cut at its end, where it was, in the same columns. Marks, digits
  and box glyphs stay on `Canvas.text`, in stored order.

- An `OptionList` row's label too long for the row is laid out at the room
  it has and cut at its end with the theme's ellipsis, as a `Text` with
  `TextOverflow.ellipsis` is; it was laid out at its natural width and the
  canvas clipped its right edge, so in visual order a right-to-left label
  lost its start, which is on the right.

- In visual order, where a right-to-left label is drawn as it reads, the
  rows of an `OptionList` (its label with its marks, which are now spans
  of one run in the mark style and no longer split it, and its detail),
  the tabs of a `TabBar` and the titles and entries of a `MenuBar`'s and
  a context menu's menus read as a `Text` draws them: they drew
  `שלום עולם` where `Text` draws `םלוע םולש`. Each paints its labels
  through a `TextPainter` it keeps while the label is the same, laid out
  again only when it, the segmenter or the text order changes. Their
  cuts, widths and the columns a click finds are those of stored order, as
  before.

- In visual order, where a row of right-to-left text is drawn as it reads,
  a click finds the target drawn under it: the crumb of `Breadcrumbs`, the
  segment of `SegmentedButton`, the page of `Pagination`, the step of
  `Stepper`, the arrow of `ValueStepper`, the key of a pressable
  `KeyHintsBar`, and a `ChipList` chip's `×`, which a click on the label
  took for it while the `×` was drawn on the left. They found it in a table
  of columns summed in stored order; they now ask the row's paragraph which
  text it drew there (`RenderParagraph.cellAt`). The hidden cursor rests
  on the active one where it is drawn too: `ActiveItem(text: (start, end))`
  rests it on the first cell its child `Text` draws of that text, found at
  each layout, as `column` gives a fixed one.

- The drawn mark of a theme field is one module: `Marks` (a `CellMark` or
  `TextMark` descriptor for each mark of `Glyphs`) and `ThemeMarks`
  (`ThemeMarks.of(context).text(Marks.close)`; in a render object
  `ThemeMarks.ofObject(this, canvas.segmenter).cell(Marks.cursor, glyphs)`),
  which keeps the one width rule (a mark is used only where it is one column
  and one code point, else it is `Glyphs.ascii`'s), a cache for each
  segmenter and the one warning for each (field, glyph). `Glyphs` stays
  plain strings. The helpers `cellRune`, `optionalCellRune`, `textMark`,
  `checkboxMarks`, `switchMarks`, `radioMarks`, `buttonEdgeMarks` and
  `lineMark` (internal, hidden from the exports) and `rampOf` are gone, as
  are the private copies of the rule in the charts, the dot grid, the
  skeleton, the scrollbar, the menu, the split, the window and twk_rich.
  Behaviour that the one rule changes:
  - a mark in text is checked wherever it is drawn: the close of a `Chip`,
    `Callout` and `Window`, the arrows of a `ValueStepper`, a `Pagination`
    (`previous`, `next`), the `separator` and `check` of a
    `SegmentedButton`, the `up` and `down` of a `NumberInput`, a `Select`
    and a `DatePicker`, the kind icons of a `StatusMessage`, a `Callout` and
    a toast, the `cursor` of a list and a file picker, the `expanded` and
    `collapsed` of an `ExpansionTile`, the `next` of `Breadcrumbs`, the
    `bullet` mask of a `TextField`, the radio brackets, and the marks of
    twk_rich's markdown (bullets, checkboxes, quote bar, table borders and
    lines) and diff; one that is two columns wide is the ASCII one, with one
    warning, where it was drawn as it was and shifted the row;
  - the dash drawn as text in a row (a `Stepper`, a `Callout`'s title, a
    raised `Window`'s minimise) is ASCII where the line is not one column;
  - a `Window`'s focus mark with an empty `cursor` draws nothing, where it
    drew `>`; a `Slider` with an empty `trackHorizontal` draws a blank, where
    it drew `-`, as a `Scrollbar` does;
  - a `SkeletonTheme(glyph:)` or a light shade that is not one column wide is
    the ASCII shade `.` (with one warning), where the skeleton drew a blank
    in reverse video;
  - `LineGauge(type:)` under `Glyphs.ascii` (lines ASCII) is ASCII, as the
    docs of `Glyphs` said: the ASCII theme beats a widget's `BorderType`;
  - a `Split` and a menu keep a border type whose pieces are all one column
    (as the charts do), where they kept it by the terminal's ambiguous
    width.
- `FocusNode.takesText` (and `Focus(takesText:)`) says that a node takes the
  keys that are characters as text: `TextField` and `TextArea` say it unless
  read-only. `FocusManagerKeys.activeKeys`, so a `KeyHintsBar` and
  `showKeyHelp`, no longer list a binding of a layer above such a node on a
  character key (`q`), which the field takes, and a click on a hint cannot
  type it into the field; keys with Ctrl or Alt stay.
- `KeyBindings(unmatched: UnmatchedKeys.replay)` replays the held first keys
  to the nodes a key walks, past what a dialog's `keysSkip` skips, where it
  gave them to the app's bindings between the navigator and the dialog.
- A cell's style id is a `StyleId` (package:twk_core, exported by
  package:twk), apart from a pen id, which stays an int: the effect cell's
  `EffectCell.style`, `childStyle` and `underStyle` are one, and so are
  the style arguments of a `RenderEffect`'s `effectCell`.

Breaking:

- A `Dialog` keeps to 72 columns by default (`Dialog.maxWidth`), where it
  took the width of its child. What is wider is cut on the right, with no
  error; a dialog that sets its own width gives `maxWidth: null`.
- `Gauge` and `LineGauge` show no percentage unless `showPercentage: true`;
  they showed it by default.
- A `Sparkline` with fewer values than columns ends at the right edge
  (`fromRight`, true by default), where it started at the left;
  `fromRight: false` keeps that.
- `Scrollbar` and the bar of `Box` read the axis from the scrollable
  inside, as Flutter's `Scrollbar` does. `Scrollbar(axis:)` is nullable and
  null by default: the outermost scrollable of either axis, where it was
  vertical by default. So `Scrollbar()` around content whose outermost
  scrollable is horizontal now shows that one, in a row at the bottom; to
  keep the column around content that scrolls both ways, give
  `axis: Axis.vertical`. A given axis picks that axis's scrollable, the
  bar to each axis of content that scrolls both. An inner scrollable of the
  other axis never takes the bar of an outer one.
- `Box(scrollbar:)` takes a `ScrollbarVisibility?`, as `LogView` does,
  where it took an `Axis?`: `.always`, `.onScroll` (the border's own line
  shows while the thumb is hidden) or `.never`; null for none. The bar is on
  the right side for a vertical scrollable and on the bottom for a
  horizontal one; the border must have that side and a bottom title cannot
  share it with a horizontal bar, as asserted.

New:

- `App`, the root that puts the theme over the `Overlay` over the app.
- `Glyphs`, the marks widgets draw by meaning, in `ThemeData.glyphs`, with
  the presets `Glyphs.unicode` and `Glyphs.ascii`.
- `ThemeData.handPointer`: `HandPointer.off`, `.auto` (the default) or `.on`
  for the hand over what a click presses.
- `AppBinding.addPostFrameCallback`, called once at the end of a frame;
  `AppBinding.pressKey`, a press of a key from code, as if the terminal had
  sent it; `AppBinding.now`, the app's wall time on its clock, which a
  test's fake clock moves; `AppBinding.startTimer` and `startPeriodic`,
  timers on the app's clock.
- `showConfirm`, a yes-or-no dialog; `Dialog.trailing` and
  `Dialog.scrollable`; `showKeyHelp`, a dialog of the keys in force.
- `Chip`, `ChipList` and `ValueStepper`.
- `Text.line` and `Text.richLine`, one line cut with an ellipsis;
  `Button.rich`; `Span.tap`, a click on a piece of text;
  `Callout(borderType:, titleStyle:)`.
- `KeyHintsBar.fromPairs`, a bar of fixed pairs, and
  `KeyHintsBar(pressable: true)`, a click on a hint presses its key.
- `canRequestFocus` on `Button` and `Pressable`, for a control of the mouse
  only.
- `TickerMode`, set by `Offstage` and `Visibility`, mutes the tickers below
  it; `useInterval`, a hook called every period on the app's clock.
- `LogController.listen`, `addSpans`, and `addOutput` and `followFile`, which
  return a `LogSource`.
- `ScrollPhysics` and `NeverScrollableScrollPhysics`, taken by a `ListView`,
  `Scrollable`, `SingleChildScrollView` and `TreeView`, which leave the wheel
  and the keys to what is around them.
- `TreeView(separateRoots:, maxIndent:, gutter:, gutterWidth:)`.
- From package:twk: `fitText`, `padCells`, `breakLines`, `segmenterOf` and
  `formatBytes` with `ByteUnits`, which `DirectoryTree`, `ProgressList` and
  `Cli.tasks` take as `byteUnits`.
- `'esc'` names the Escape key in a binding, as `'escape'` does.

## 0.1.0

The first release.

- The framework: `Widget`, `StatelessWidget`, `StatefulWidget` and
  `State`, `InheritedWidget`, keys and `GlobalKey`, `LayoutBuilder`,
  `BuildContext`; `ChangeNotifier`, `ValueNotifier` and `Listenable`.
- `runApp`: fullscreen, inline below the shell's history (`Static`
  commits finished lines into the scrollback) or in a fixed viewport;
  `AppBinding` with frame callbacks, notifications, the window title and
  hot reload through `twk run`.
- Style and text: `Style` with colors, attributes, underline colors and
  links; `Text` and `Text.rich`, wrapping, ellipsis and bidirectional
  text; `Theme` with built-in dark and light themes, the default ones
  picked by the terminal's background, `Theme.adaptive` to choose them
  and `Theme.terminal` for the terminal's own colors.
- Layout: `Row`, `Column`, `Flex`, `Stack`, `Grid`, `Wrap`, `Box` with
  borders that merge, `Padding`, `Align`, `SizedBox`, `SplitView`.
- Focus and input: the focus tree, `Focus`, `KeyBindings`, `Shortcuts`
  and hinted keys; the mouse by hit test (`Listener`, `MouseRegion`).
- Scrolling and data: `ListView`, `Scrollbar`, `Table` (also over a data
  source), `TreeView`, `DirectoryTree`, charts, sparklines and gauges.
- Editing: `TextField`, `TextArea`, `Form` and `FormField`.
- Overlays: dialogs, menus, `MenuBar`, `ContextMenu`, toasts, tooltips,
  `CommandPalette`.
- Navigation and controls: `Navigator` and routes, tabs, buttons,
  switches, checkboxes, radio groups, sliders, `Stepper`, progress bars
  and spinners.
- Animation: tickers, `AnimationController`, implicit animations.
- Semantics and a screen-reader mode; debug aids: the frame overlay, the
  repaint rainbow, the log console, tree dumps and VM service extensions.
- Program output with ANSI sequences as styled text: `parseAnsi`,
  `AnsiStream` as it arrives, and `stripAnsi`.
- `package:twk/hooks.dart`, hooks in the flutter_hooks style, and
  `package:twk/provider.dart`, Provider's API.
- `package:twk/cli.dart`, the console of a command-line tool that is no
  app: messages by level, any widget printed, prompts, progress and a
  traceback, as a terminal, a pipe or CI takes them.
- A dart2wasm build for the web.
