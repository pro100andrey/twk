---
title: "Widgets by need"
about: "The widgets grouped by what an app needs, with the options that are easy to miss."
order: 13
---
# Widgets by need

The widgets by what an app needs of them, with the options and rules of each
that a first look at the catalog misses. Each is described, with every
parameter, in [the widget catalog](../widgets.md).

## Layout

`Column`, `Row` (`spacing:`; `crossAxisAlignment` is `.center` unless set), `Expanded`, `Flexible`, `Spacer`, `Padding`, `SizedBox`, `Center`, `Align`, `Box` (`border:`, `titles:`, `padding:`, `style:` fills it; `scrollbar: .always` (or `.onScroll`) draws the bar of the outermost scrollable inside on the border, in the border type's own line, at the right for a vertical scrollable and at the bottom for a horizontal one, which asserts under a bottom title), `Divider`, `Grid` + `GridPlacement`, `Stack` + `Positioned`, `Wrap`, `SplitView` (panes with draggable dividers), `ExpansionTile` + `Accordion` (sections that fold; `ExpansionController`), `Container` (Flutter's: `padding:`, `margin:`, `color:`, `decoration: BoxDecoration(…)`, `width:`, `height:`), `ColoredBox`, `DecoratedBox`, `ConstrainedBox(constraints: BoxConstraints(minWidth: minWidth, maxWidth: maxWidth, minHeight: minHeight, maxHeight: maxHeight))`, `LimitedBox`, `OverflowBox`, `SizedOverflowBox`, `Transform.translate` (whole cells; no rotation or scale), `Offstage` and `Visibility` (hide, keeping state; the tickers below are muted, an animation's time going on, as under `TickerMode(enabled: false)`), `RepaintBoundary` (isolate a part that changes often), `CustomPaint` + `CellPainter` (cells painted by hand)

## Text and style

`Text(text, style:, wrap:, overflow:, maxLines:)`, `Text.rich([spans])`, `Text.line(text)` and `Text.richLine([spans])` (one line cut with `…`: a row's or a panel's label), `'x'.bold.fg(.green)` (a `Span`), `'task bl-42'.underline.tap(onTap)` (a click on a phrase of a `Text.rich` that is no URL), `Style(fg:, bg:, attrs:)`, `Theme(data: ThemeData.nord, child:)`, `Theme.adaptive` (dark or light by the terminal), `Theme.of(context).primary`, `Hyperlink`

## Keys

`KeyBindings({'ctrl+s': save, 'g g': top}, hints: {'ctrl+s': 'save'}, child:)`, `Shortcuts` + `Actions` + `Intent`, `KeyHintsBar`, `InputListener` (keys nobody took, pastes, resizes)

## Focus

`autofocus: true`, `FocusNode` (`requestFocus()`, `hasFocus`), `AppBinding.of(context).focusManager.primaryFocus` (the node that has the focus now, or null), `Focus`, `FocusScope`, `ExcludeFocus` (keep the focus out of a part)

## Mouse (full screen)

`GestureDetector(onTap:, onDoubleTap:, onLongPress:, onPanUpdate:)`, `Listener`, `MouseRegion`, `Draggable` + `DragTarget` (`GestureDetector`s nested: the deepest one with a callback for the gesture takes the press, the outer one gets nothing of it), `SelectionArea` (select and copy text; `SelectionAreaController`; a render object of your own mixes in `Selectable`), `Tooltip` (also on focus; `TooltipController`), `IgnorePointer`, `AbsorbPointer`

## Lists and data

`ListView`, `ListView.builder` (lazy; `stickToBottom`; `ListController`; `reverse: true` for a chat, item 0 at the bottom; keyed items stay in place as items are inserted above), `ListView.separated`, `ScrollController(stickToEnd: true)` (follow the end of any scrollable), `LogView` + `LogController` (a log that follows its tail, with levels, a filter and search), `SingleChildScrollView` (`physics: NeverScrollableScrollPhysics()` leaves the wheel to the scrollable around it, and the view is then no Tab stop and has no key hints; `ListView`, `Scrollable` and `TreeView` take `physics` too, `SelectionList`, `Table` and `LogView` do not; `TreeView` with `NeverScrollableScrollPhysics` leaves the wheel to the list around, its own keys and Tab stop stay), `Scrollbar`, `SelectionList<K>`, `Table<T>`, `Table<T>.source` (a million rows), `TreeView<T>` (`separateRoots`, `maxIndent`, `gutter` + `gutterWidth` for a mark of your own at the row's start), `TreeTable<T>` (a tree with columns), `DirectoryTree` (a file tree for a side panel; `DirectoryTreeController`), `TaskList`, `DescriptionList` + `DescriptionItem` (terms and their values, aligned), `Heatmap`, `ActivityHeatmap` (counts by day over weeks), `Sparkline`, `Gauge`, `LineGauge`, `BarChart`, `Chart`, `Calendar`, `DotCanvas`

## Text input

`TextField` + `TextEditingController` (`onSubmitted`, `onChanged`, `obscureText`, `readOnly`, `enabled`, `onPaste`; Ctrl+C and Ctrl+X copy and cut a selection; `decoration: InputDecoration(icon:, labelText:, helperText:, errorText:, prefixIcon:, prefixText:, suffixIcon:, suffixText:, border: OutlineInputBorder() / UnderlineInputBorder() / InputBorder.none, filled:)`), `InputDecorator` (a decoration around any control), `TextArea` (lines), `Autocomplete`

## Controls and forms

`Button`, `Checkbox`, `Switch`, `RadioGroup<T>`, `Select<T>`, `MultiSelect<T>` (`decoration:` a label and a border, as a field's), `Slider`, `NumberInput`, `DatePicker`, `ConfirmInput`, `FilePicker` (`showFilePicker`; `FilePickerController`), `PopupController` (open a `Select`'s or a `DatePicker`'s popup from code), `Form` + `FormField<T>` + `TextFormField`, `TabBar` + `TabBarView` + `TabController`, `SegmentedButton<T>` (a compact choice on one row), `StatusBar`, `StatusMessage`, `Callout` (a boxed notice of a `StatusKind`, dismissible), `Badge`

## Over the app (need an `overlay`)

`showDialog` + `Dialog` + `closeDialog`, `showConfirm` (the question wraps on its own lines above the answers; `yes:`/`no:` label them, Delete and Keep say, default Yes and No; the keys stay `y`/`n`), `showToast`, `MenuBar` + `Menu` + `MenuItem`, `ContextMenu` (both with a `MenuController`), `Popover` (its content in a focus scope of its own: `autofocus` inside takes the focus; Tab leaves it past its last node to the node after the child, closing it, Shift+Tab from its first to the child's last node, keeping it open: `FocusScopeNode.leaveTo`, null by default, is what a scope's Tab leaves to), `CommandPalette` (`CommandPaletteController`, `commandsFor:`), `ModalBarrier`, `AnimatedModalBarrier`

## Screens

`Scaffold` (header, sidebar, body, status bar and key hints, a focus zone each; `ScaffoldController`), `Navigator` (`push`, `pop`, named routes; Escape pops; holds an `Overlay`; `observers:`; `PageRoute(transitionDuration:)` slides in), `PopScope` (refuse or intercept a pop), `Stepper` + `Step` (a wizard whose steps validate; `StepperController`), `Breadcrumbs`, `Pagination`

## Built inline

`Builder` (a context of its own), `StatefulBuilder` (a state of its own: `builder: (context, setState) => …`), `LayoutBuilder` (`builder: (context, constraints) => …`, `constraints.maxWidth` and `maxHeight` the room in cells; `doc/guides/layout.md`), `FocusBuilder` (by whether the focus is in it)

## Async and time

`FutureBuilder`, `StreamBuilder`, `ListenableBuilder`, `ValueListenableBuilder`, `AnimatedBuilder`, `Spinner`, `ProgressBar`, `ProgressList` + `ProgressTracker` (many tasks with bars, rate and time left), `Skeleton` and `Skeletonize` (placeholders that shimmer while content loads), `AnimationController` + `TickerProviderStateMixin`, `Tween`, `Curves`

## State over the tree, hooks

`package:twk/provider.dart`, Provider's API: `Provider`, `ChangeNotifierProvider`, `MultiProvider`, `context.read<T>()`, `context.watch<T>()`, `context.select`, `Consumer`, `Selector` (twk_bloc builds on it); `package:twk/hooks.dart`, flutter_hooks': `HookWidget`, `HookBuilder`, `useState`, `useEffect`, `useMemoized`, `useTextEditingController`. Each is imported besides `package:twk/twk.dart`, and has its page in `packages/twk/doc/reference/` (`provider.md`, `hooks.md`)

## Inline output

`Static`

## Other

`AppBinding.of(context).notify(title, body)` (a desktop notification), `AppBinding.of(context).now()` (the time to show: the app's start moved on by its clock, which a test fixes; not `DateTime.now()`), `AppBinding.of(context).addPostFrameCallback((time) { … })` (once, at the end of the frame, when sizes are laid out; one that throws ends the app, `runApp` throwing it), `AppBinding.of(context).attachRootWidget(widget)` (replace the whole app from the next frame on, the old root's states disposed; from a callback, not a build; `doc/guides/state.md`), `debugDumpApp(context)`, `Console`, `Semantics(hint:)` and `ExcludeSemantics` (what a screen reader reads)
