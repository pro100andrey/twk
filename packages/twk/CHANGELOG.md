# Changelog

## Unreleased

Breaking:

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
