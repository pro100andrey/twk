# Changelog

## Unreleased

Breaking:

- `LogView` wraps by default (`wrap: true`): `wrap: false` keeps a line a
  row, cut off and scrolled across by Left and Right.
- `LogController.followFile`: `fromEnd` is `backlog`, the bytes before the
  end read too: `0` (the default) for `fromEnd: true`, `null` for
  `fromEnd: false`, and a number of bytes for the whole lines among the last
  of them, the line they begin within left out.

Added:

- `LogController.addOutput` and `followFile` take `map`, which gives each
  line's spans back, changed, or null to leave the line out.
- `LogController.where`, which lines are shown by a test of each, beside
  `level` and `filter`; set, the view stays on the lines it shows.
- `showKeyHelp(extra:)`: what no binding in force tells, as pairs of what
  is done and what it does (`('right click', 'menu')`), listed after the
  keys.
- `Table(rowMenu:)`, the entries of a row's menu: a right click on a row
  selects it and opens the menu at the mouse, Shift+F10 the selected row's
  under it.
- `LogView`: `w` turns the wrapping over (`w wrap` in a `KeyHintsBar`).
- `ListController.jumpToIndex(rows:)`: the item at the top part way into
  it, `rows` of it above the window.
- `runApp(onError:)` and `AppBinding(onError:)`, an `ErrorReporter` told
  of every error the binding reports (build, layout, paint, an input
  handler, uncaught: `ErrorOrigin`) with the widget path where there is
  one, besides what happens to the error.
- `debugAssertsEnabled`, whether asserts are on; `AppBinding` logs one
  info line when a program runs with them off.
- `DisposalTracker`, an opt-in debug record of the controllers and
  notifiers made and never disposed (`testTwk(trackDisposables: true)`
  reports them); `ValueNotifier`, `ScrollController`, `FocusNode` and
  `AnimationController` join it.
- `overflowIntended` on `Flex`, `Row`, `Column`, `Wrap` and `Grid`: a
  layout that cuts its children off on purpose shows no overflow marker
  and logs no warning.
- The debug aids' overflow marker: a hatch with the cells cut off, at the
  edge of a flex, wrap or grid whose children do not fit
  (`TWK_DEBUG=overflow`, Ctrl+G then `w`, `DebugAids.overflow`,
  `ext.twk.flags`), on while asserts are.
- `ControllerHost(mounted:)`, whether a host that is no `State` is still
  in the tree.

Changed:

- `LogView(wrap: true)` wraps a line's text in a column of its own right
  of its time and level, not back under them at the left edge.
- Debug runs assert, with a hint, on what was lost or wrong without a
  word: `setState` of an element inside its own `build` (the update was
  dropped); a lookup of an inherited widget or an ancestor from an element
  out of the tree, in `dispose` or after an await (it gave null or a
  default; keep the value from `didChangeDependencies`); a `State`
  disposed with a `Ticker` still active, naming both (a controller it did
  not dispose); a controller served by two widgets in the tree at once,
  checked after the build; two choices with one value in `Select`,
  `MultiSelect` and `SegmentedButton`, two items with one key in
  `SelectionList`, two rows with one `rowKey` in `Table`; `requestFocus`
  on a disposed `FocusNode`; `StepperController.next`, `back` or `goTo`
  after its dispose (a validator that resolves after it stays silent); a
  negative `duration`, `reverseDuration`, `animateTo` duration or
  `repeat` period of an `AnimationController` (`Duration.zero` jumps).
- Tree warnings (a flex, wrap or grid overflow, a viewport or list given
  no room) name the widget path of the render object that raised them.

Fixed:

- `State.setState` asserts, in a debug run, on a callback that returns a
  `Future` (an `async` closure), whose changes after the first await had
  no rebuild after them.
- `LogView` scrolled across and its controller cleared: the lines added
  next show from their start, not scrolled out of view.
- `LogView` scrolled up into a wrapped line stays on its row as lines are
  dropped past `maxLines`, not moved to the line's start at each one added.
- What `map` throws in `LogController.addOutput` or `followFile` ends the
  source, its `done` completing with it, the lines before it added and the
  listeners told; it was thrown uncaught, the rest of the lines lost.
- `NumberInput` and `DatePicker` give `onChanged` the text typed on a key
  they leave to the bindings above, before it goes on, where it is a value
  within the bounds, and leave the text as typed: a dialog's Ctrl+S that
  saves, pressed with 45 typed over 30, found 30. Text that is no value
  yet (`-`) stays for Enter or the focus leaving to take, and Escape gives
  back the value from before the typing.
- A CLI on a pseudo-terminal of no size (one `script` opens with no
  terminal around it: a background job, CI) takes it for a terminal, its
  width `COLUMNS` or none; it wrote to it as to a file, without colours or
  a progress line written over. A stdout a test puts in (`IOOverrides`)
  that says it is a terminal by `hasTerminal` still is one, and `/dev/null`
  is none.
- A focus change a mouse event made is told before the next mouse event
  is handled: a click whose press and release came in one frame pressed a
  button before the field it took the focus from had taken its text (a
  `NumberInput` with 45 typed over 30 saved 30).
- A click on a `LogView` writes the text a selection selects in anew only
  where the lines changed: at 10000 lines a click took 2 ms, now 0.3 ms.
- `Scrollbar` and a bar on a `Box` border dispose their track's notifier;
  `SelectionList` and `Table` dispose the list controller they made when
  they are refused for duplicate keys; a route removed before a frame
  built it disposes its focus nodes; the window layer disposes its move
  ticker.
- A scrollable first built in a `LayoutBuilder` while a scrollbar's frame
  lays its child out no longer marks the frame for layout inside its own
  layout: the frame takes the axis into that layout.
- `Popover` and an overlay entry make their fade ticker in `initState`,
  not first in `dispose`; `DragTarget` keeps its `MouseTracker` from
  `didChangeDependencies`.
- A `showFilePicker` dialog no longer overflows by a row, and a window
  narrower than its title buttons logs no overflow.
- `example/hooks/search.dart` loads its list from an effect that cancels
  its timer, so quitting leaves no timer pending.
- `showFilePicker` fits a terminal shorter than its `height`: Cancel and
  Open stay on screen.
- `Table` keeps its state (rows, selection, scroll) when `rowMenu` is
  given or taken away.
- `SelectionList` checks its keys for duplicates again only when the count
  or `keyOf` changed, not at every rebuild; the `MultiSelect` duplicate
  check names `MultiSelect`.
- `OptionList` no longer fails its paint (a negative clip width) when its
  detail is wider than the list.
- The "asserts are off" log line is written only in a debug run, not in
  profile or release builds; `LogView.selectionLines`, a test counter,
  counts only when asserts are on.
- `LogController.where` keeps the predicate it had when a new one throws,
  instead of leaving every later line to throw.
- `SelectionList` skips its duplicate-key check for a `keyOf` that is
  `==` to the last, a method tear-off included.
- The Ctrl+G hint line shows copy and save at 80 columns again.
- The `setState` Future assert names the arrow form too
  (`setState(() => _future = fetch())`) and the fix, a block body.
- Removing a focused field together with the sibling before it in one
  frame no longer fails the build in a debug run: the focus order walked
  an element already out of the tree.
- A controller served by two widgets both in the tree is logged as an
  error after a 2 s grace on the app's clock instead of ending the app;
  an old host kept in the tree by a fade-out is no mistake.
- `LogController.level` and `filter` keep their old value, and tell no
  listener, when `where` throws during the refilter, as `where` does.
- `NumberInput` and `DatePicker` keep a number typed until the parent
  takes it or gives another value; a rebuild with the old value no longer
  clears it. A value handed over that the parent never took is given up
  when the focus leaves, the field showing the parent's value again, even
  where the text was edited into no value meanwhile.
- The duplicate checks read every key or value when the widget is made,
  and at most the first 1000 when it is rebuilt.
- A controller with two hosts in the tree and no app above them fails in
  a debug run again, where it was only logged; the grace runs on the
  app's clock. A `State` host finds that clock above it by itself, so
  `ControllerHost(timerOf:)` is only for a host that is no `State`, and a
  `MenuController` handed to a new menu while the old one fades out no
  longer fails.
- A widget leaving ends only the two-hosts graces it is in, not those of
  other hosts still in the tree.
- `LogController` tells its listeners after a refilter is whole, outside
  the undo of a `where` that throws.
- The duplicate checks of `Select`, `MultiSelect`, `SegmentedButton`,
  `SelectionList` and `Table` read at most the first 1000 values or keys,
  so a huge list rebuilt with an inline `keyOf` no longer costs a pass
  over all of it in a debug run.
- `Cli.show` writes no overflow marker over its output; the warning still
  goes to the console's log.
- `NumberInput` and `DatePicker` forget a value handed over once the
  parent took it: Escape after that keeps the parent's value. A key of the
  field's own at an edge of the text (a caret key, a deletion, a
  character) hands nothing over to the bindings above.
- `Table` binds Shift+F10 only while a row is selected, so with none it
  goes on to the bindings above; one `Listener` over the rows instead of
  one per row.
- A route's focus nodes are made and disposed by the navigator's state,
  once, however the route is removed; a click on a `LogView` finds its
  line without making a list.
- The debug console shows an overflow report's text once, not again as
  its error.
- `NumberInput` and `DatePicker` keep a value handed over that the parent
  has not taken across a rebuild for another reason: Escape still gives
  back the value from before the typing, and the focus leaving gives it
  up.
- A `ControllerHost` whose `timerOf` answers null has no clock, as its
  doc says, a `State` host too; the app's clock is a `State`'s default
  only where no `timerOf` is given.

## 0.3.0

Breaking:

- Renamed:

  | Was | Is |
  | --- | --- |
  | `Localizations` | `TwkLocalizations` |
  | `TabView` | `TabBarView` |
  | `WindowTitle` | `TerminalTitle` |
  | `TaskStatus` | `TaskItemStatus` |
  | `Link` | `Hyperlink` |
  | `Mark` | `GlyphMark` |
  | `debugDumpTree` | `debugDumpApp` |
  | `DragDetails` | `DragStartDetails`, `DragUpdateDetails`, `DragEndDetails` |
  | `DragListener` | `GestureDragStartCallback`, `GestureDragUpdateCallback`, `GestureDragEndCallback` |
  | `GestureDetector`: `onDragStart`, `onDragUpdate`, `onDragEnd` | `onPanStart`, `onPanUpdate`, `onPanEnd` |
  | `Listener`, `RenderListener`: `onDown`, `onUp`, `onMove`, `onDrag` | `onPointerDown`, `onPointerUp`, `onPointerHover`, `onPointerMove` |
  | `ScrollMetrics`, `ScrollPosition`: `offset`, `maxOffset`, `viewportExtent` | `pixels`, `maxScrollExtent`, `viewportDimension` |
  | `ScrollController`, `ListController`, `useScrollController`: `initialOffset` | `initialScrollOffset` |
  | `Text`, `Text.rich`, `Text.line`, `Text.richLine`: `align` | `textAlign` |
  | `StatusBar`, `DescriptionList`: `gap` | `spacing` |
  | `Scrollbar`: `hideAfter` | `timeToFade` |
  | `DragTarget`: `onWillAccept`, `onAccept` | `onWillAcceptWithDetails`, `onAcceptWithDetails` |
  | `showDialog`: `dismissible` | `barrierDismissible` |
  | `PopScope`: `onPopInvoked` | `onPopInvokedWithResult` |

- `BoxConstraints`, `Flex`, `Row`, `Column`, `Wrap` and `Terminal`:
  [twk_core's changelog](../twk_core/CHANGELOG.md).
- `TweenAnimationBuilder` takes a `Tween`: `tween: IntTween(begin: 0, end: total)`
  in place of `value:`, `from:` and a constructor. A `Tween` of an app's own
  overrides the new `Tween.withEnds`.
- `Action.invoke` returns `Object?` and `CallbackAction.onInvoke` is an
  `Object? Function(T)`: `onInvoke: (_) {}` is `(_) => null`.
- `Semantics` and `SemanticsNode` take `checked`, `selected`, `expanded` and
  `enabled` in place of `state:`; `SemanticsState` is removed. `disabled: !x` is
  `enabled: x`. `Semantics.child` is optional.
- `Actions` and `Shortcuts` take `actions:` and `shortcuts:` by name.
  `Shortcuts.combos` still takes its map first.
- `showDialog`, `showToast` and `showContextMenu` take `context` by name, with
  `builder`, `message` and `items`:
  `showDialog(context: context, builder: (context) => ...)`.
- `GestureDetector` and `Pressable`: `onTap`, `onDoubleTap` and `onLongPress` are
  `VoidCallback`s. `onTapDown` takes `TapDownDetails` and the new `onTapUp`
  `TapUpDetails`, with `localPosition` and `globalPosition` in cells (`CellOffset`,
  `dx` and `dy`) and the `event`. `onLongPressEnd` still takes the `PointerEvent`.
- The drag details have `localPosition` and `globalPosition`, the update `delta`,
  and keep `event`.
- `log`, `LogLevel`, `LogRecord` and `LogSink` moved to `package:twk/log.dart`;
  `formatBytes`, `formatTook` and `ByteUnits` to `package:twk/format.dart`.
- `twk.dart` no longer exports `ModeReport`, `KeyboardFlagsReport`,
  `DeviceAttributes`, `ColorReport`, `CursorReport` and `UnknownSequence`:
  `package:twk_core/terminal.dart` has them.
- The wheel goes through `ScrollBehavior` and `ScrollConfiguration`:
  `App(scrollBehavior:)` for the app, `ScrollConfiguration` for a subtree. A
  `Scrollable` applies it once a frame, dense events a cell each with an
  acceleration, sparse ones 3. `ScrollBehavior.fixed(3)` is a plain step.
  `wheelStep`, `wheelAcceleration` and `WheelAcceleration` are gone.
- `Popover.onDismiss` is required.
- `Ticker.binding` and `Steps.binding` take what they use of it, not `AppBinding?`;
  twk_test's `FakeFrameClock` is one.
- `Cli.current` is gone: `Cli.run` gives the body its `cli` as a parameter.
- `ThemeData.pointerMode`, `PointerMode.off`, `.auto` or `.on`, replaces
  `ThemeData.handPointer`, `HandPointer` and the `pointerShapes` of `Window`,
  `SplitView`, `Table`, `TreeTable` and `Draggable`. `PointerMode.auto`, the
  default, shows the hand in a local session and asks a terminal that shows
  pointer shapes for the mouse's motion (mode 1003), and for none in a remote one.
  `TerminalStatus.handAsksMotion` is the rule.
- A press on a cell a `GestureDetector`'s `tapAt` refuses goes to the detectors
  around it.
- `runApp` while a `Cli` session has the terminal throws a `TerminalException`:
  `Cli.suspend` around it, or `Cli.close` first.

Added:

- `TwkStrings`, the words twk writes itself and `decimalSeparator`:
  `TwkLocalizations(strings:, child:)` and `TwkStrings.of(context)` for widgets,
  `Cli(strings:)`, `Cli.run` and `Cli.runWithArgs` for a console.
  `formatBytes`, `formatTook` and `ProgressTask.summary` take `decimalSeparator:`.
- `runApp` and `AppBinding` take `maxInputFps`.
- `Table` and `TreeTable` take `marks:`, a `SelectionController<Object>(multiple:
  true)` that marks rows by key, with a checkbox column.
- `ListView(padding:)`, `Table(padding:)` and `SingleChildScrollView(padding:)`,
  which scroll with the content.
- `Cli.session()`, `CliTerminal.promptShown(question)`.
- `AnsiStream.reset()`.
- `Text.line` and `Text.richLine` take `align` and `overflow`.
- `MenuItem(shortcut:)`.
- `copyToClipboard(context, text)`.
- `RadioGroup` and `ValueStepper` take `canRequestFocus`.
- `Pressable(behavior:)`, and `GestureDetector`'s `cursor` and `tapAt`.
- `FocusManager.autofocusPending`.
- `ValueChanged`, `ValueGetter`, `ValueSetter`, `kReleaseMode`, `kDebugMode`.
- `Style.copyWith`, `SizedBox.square(dimension:)`, `DefaultTextStyle.merge` (which
  merges onto the style above, unlike Flutter's).
- `Focus(onFocusChange:)`, `FocusScope(onFocusChange:)`,
  `FocusScopeNode.requestFocus([node])`.
- `SingleTickerProviderStateMixin`. `AnimationController.forward`, `reverse`,
  `animateTo` and `repeat` return a `Future<void>` that completes when the run ends
  or is stopped; `dispose` leaves it pending. `AnimationController.toggle`,
  `isCompleted` and `isDismissed` (also on `AnimationStatus`).
- The rest of Flutter's `Curves`.
- `Navigator.pushAndRemoveUntil`, `pushNamedAndRemoveUntil` and `popAndPushNamed`,
  static and on `NavigatorState`.
- `Slider(onChangeStart:, onChangeEnd:)`.
- `BlockSemantics(blocking:)`, `State.reassemble`, `Element.reassemble` and
  `AppBinding.reassemble`.

Changed:

- A `Text` of eight rows or more that is edited without changing its size repaints
  only the rows that changed.
- The pointer follows the press: a `GestureDetector` with `onTap` shows the hand by
  `ThemeData.pointerMode`, over all that a click presses. Rows of a list keep the
  arrow.
- A confirmation takes the first letters of `TwkStrings.yes` and `no` too.
  `Cli.confirm` says `(y/n)`, Tab moves the highlight, and Enter with no answer
  highlighted says `answer y or n`.
- Esc cancels a prompt of `package:twk/cli.dart`, exit 130; with suggestions open
  it hides them first.
- `Cli.show` of a `Table`, `TreeTable` or `ListView` with items and no height warns.
- A closing dialog, menu or popover gives the focus back to the node that had it,
  and Escape closes the layer the focus is in. A dialog or menu opened from a
  `Popover` no longer dismisses it.
- `twk shell` ignores and logs a frame of a type it does not know, as the VS Code
  extension's shell does.
- A row `SelectionList.itemEnabled` refuses, in a multiple list, has a blank for its
  mark; a selected one keeps its `[x]`.
- A row a `ListView` keeps out of its window builds as it comes back.
- What is dirty below a `LayoutBuilder` given a new widget waits for its build.
- A key flushes an `autofocus` still waiting.
- A `SelectionArea` copies a blank line where rows lie between two `Text`s.
- `GestureDetector.onTapDown` is told only of a press the detector takes part in.

Fixed:

- `tailFile` reads a look through one handle: a rename over the name loses no
  lines, and a look with nothing to read opens nothing.
- A widget that watched a provider and later only selects is told of what it
  selects.
- `Semantics.nodes` keep their hints while the `Semantics` is not focused.
- A popover closes when a layer over it gives the focus elsewhere.
- A `ProgressList` lays out again when `TwkStrings.eta` and `moreTasks` change.
- A row a `ListView` kept can be marked again before the next build.

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
