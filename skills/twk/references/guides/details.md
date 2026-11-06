---
title: "Details and pitfalls"
about: "How an app runs, what the tester does, the debug aids, and the mistakes that bite, in full."
order: 14
---
# Details and pitfalls

What [Coming from Flutter](coming-from-flutter.md), [Testing](testing.md) and
the other guides leave out, from the notes written for coding agents.

## How it works

- Widgets, elements and `State` behave as in Flutter. `setState` asks for
  a frame; a frame builds what changed, at most 60 a second (`maxFps`),
  and writes only the cells that changed. An app that changes nothing
  draws nothing.
- `runApp(app)` runs full screen, on the alternate screen.
  `runApp(app, mode: .inline)` runs in rows below the shell's prompt, as
  many as the app asks for (its intrinsic height), and leaves them on the
  screen when it ends. Only full screen gets the mouse; inline, the
  terminal keeps it.
- `Static(items:, builder:)` is output that is finished once shown (a
  chat's history, a build log). Inline, each new item is written once to
  the terminal's scrollback above the app's rows and takes no rows itself;
  full screen, the items show in place, one below another. Items are told
  apart by index: only append.
- A key goes to the focused widget first, then to the layers above it
  (`KeyBindings`, `Shortcuts`), nearest first, until one takes it. Tab and
  Shift+Tab move the focus. Ctrl+C that nobody takes quits (unless
  `runApp(..., exitOnCtrlC: false)`); `AppBinding.of(context).quit()`
  quits.
- `print` and `log()` inside the app go to the app's log, not to the
  screen: the log console shows them (see Debug), and the warnings and
  errors are printed to stderr once the app has ended. `log`, `LogLevel`,
  `LogRecord` and `LogSink` are in `package:twk/log.dart`, which an app that
  logs imports besides `twk.dart` (`log` is also a name in `dart:math` and
  `dart:developer`: import those with a prefix).
- A build that throws shows a white-on-red box with the error in its place
  and logs it; the app goes on. An error thrown by a key binding, an
  `InputListener` or a mouse callback ends the app with a `WidgetError`
  that names the widget path (`KeyBindings → Focus`).
- Without a `Theme`, widgets use twk's own theme of the terminal's
  brightness: `ThemeData.dark` on a dark terminal, `ThemeData.light` on a
  light one (RGB, brought down to 256 or 16 colors where the terminal has
  no more); on a terminal that does not say its background, as
  `testTwk`'s unless `pumpWidget(backgroundRgb:)` gives one, the
  terminal's own colors. `Theme.terminal(child:)` gives the terminal's own colors
  instead (`ThemeData.terminal`: `primary` is `Color.blue`, `muted` is
  dim, `selection` the grey 237 of the 256 colors, 253 on a light
  terminal), `Theme(data: ThemeData.nord, child:)` a preset.
- The marks widgets draw (check, cross, cursor bar, expanders, a
  scrollbar's thumb and track, a gauge's line, the spinner) are the
  theme's `Glyphs`, named by meaning: `Glyphs.unicode` by default,
  `Glyphs.ascii` for a terminal or a font without them,
  `ThemeData.dark.copyWith(glyphs: Glyphs.ascii)` for the whole app, a
  `Theme` around a part for that part, `Glyphs.unicode.copyWith(check:
  '✔')` for a mark of one's own. A widget's own parameter (`Spinner.frames`,
  `RadioGroup.mark`, `StatusMessage.icon`, `LineGauge.type`) is above the
  set. Borders are in it: `Border`, `Divider`, `SplitView`, `Callout` and a
  border scrollbar with no `type` draw `Glyphs.lines`, and `Glyphs.ascii`
  makes every type ASCII (`rounded` too), so one `glyphs:` switches the app;
  charts, images and the core's `…` are not in it. A mark is one column and one
  code point wherever it is drawn, in a cell (a thumb, a gauge) or as text
  in a row (a radio, a switch, a button's edges, a chip's close, a pager's
  arrows); one that is not (an emoji, a letter and an accent) is
  `Glyphs.ascii`'s in its place, with one warning in the log. The rule is
  `ThemeMarks` (`ThemeMarks.of(context).text(Marks.close)` in a widget of
  your own; `Marks` has a descriptor per field). The checkbox pair must be
  of one width or `[x]` and `[ ]` are drawn; an empty mark is none (an
  empty edge is no edge), but a blank for a track, `switchKnob`, `previous`
  and `next`. ASCII lines beat a widget's own `BorderType`.
- The code uses Dart's dot shorthands (`.inline`, `.all(type: .rounded)`,
  `.stretch`); the packages need SDK 3.13.5 or later.
- Where the names differ from Flutter's, as code brought over trips on:
  `BoxConstraints` has `minWidth`, `maxWidth`, `minHeight`, `maxHeight` (in
  cells, as in Flutter), and `BoxConstraints.tight(w, h)` and `loose(w, h)` take
  two ints, not one object (`biggest` and `smallest` are
  `({int width, int height})` records); `DefaultTextStyle(style:)` merges onto
  the style above, as `DefaultTextStyle.merge` does, where Flutter's plain
  constructor replaces it; the `Future` of `AnimationController.forward`,
  `reverse`, `animateTo` and `repeat` completes when something stops the run
  too (Flutter's stays pending; `dispose` leaves it pending in both), so an
  `await` does not hang;
  a position is in cells, a record `(dx:, dy:)` of whole numbers where Flutter
  has an Offset: `GestureDetector`'s `onTapDown` and `onTapUp` take it in their
  details (`localPosition`, `globalPosition`; `event.button` says which
  button), and `onPanStart`, `onPanUpdate` (`delta`) and `onPanEnd` too, while
  `onTap`, `onDoubleTap` and `onLongPress` take none, as Flutter's;
  `Listener` has `onPointerDown`, `onPointerUp`, `onPointerHover` (no button
  held) and `onPointerMove` (one held); `Semantics` takes `checked`,
  `selected`, `expanded` and `enabled` flat (`enabled: false` reads
  `disabled`); `TweenAnimationBuilder` takes `tween:` a `Tween`, as Flutter's;
  the words twk writes itself are `TwkLocalizations`' (`strings:`);
  `LineGauge` and `Gauge` show no percentage unless `showPercentage: true`.

## The tester

`testTwk` runs the real app on a terminal in memory under a fake clock:
input goes in as the bytes a terminal sends, and the screen is rebuilt
from the bytes the app wrote. `dart test` runs it.

- Input draws nothing by itself: `await t.pump()` (a frame's time) after
  `type`, `press` or a click, before reading the screen.
  `t.pump(duration)` moves the clock on by that much, running the app's
  timers, frames and animations due by then.
- Keys sent with no pump between them are handled before the next build,
  as a burst from a real terminal is (Escape excepted: its wait moves the
  clock). Pump before a key that needs what the keys before it built
  (Space on the row Enter added).
- `type('text')` sends the text as one read. `press('enter')`,
  `press('tab space')`, `press('ctrl+x ctrl+s')` send each key as a read
  of its own, the keys named as `KeyBindings` names them, in lower case
  (`escape`, or `esc` as the hints show it). Without the kitty protocol `press('escape')`
  waits out the 30 ms after which a lone ESC is the Escape key; a key with
  no bytes of its own without the kitty protocol (Ctrl+Shift and a
  letter, Ctrl+Enter) throws unless `pumpWidget(..., kittyKeyboard: true)`.
- `pumpWidget(app, size: (columns, rows))` starts the app, 80 × 24 by
  default; `mode: ScreenMode.inline` with `history:` lines above it. A
  later `pumpWidget` shows another widget, the state kept where they
  match. `click(x, y)`, `clickOn(finder)` and
  `mouse(MouseKind.wheelUp, x, y)` work full screen only;
  `resize(columns, rows)`.
- The screen: `t.lines` (rows without their trailing blanks),
  `t.scrollback` (inline), `t.cell(x, y)`, `t.cursor`. Matchers:
  `containsLine`, `hasTextAt(x, y, text)`, `styleAt(x, y, hasFg(Color.red))`
  (`hasAttr`, `hasBg`), `cursorAt(x, y)`, `matchesScreen('''…''')` (the
  snapshot's lines start in column 0; `styles: true` compares
  `[bold]…[/]` runs too), `matchesScreenFile('test/goldens/x.txt')` (a
  golden written with `TWK_UPDATE_GOLDENS=1`, styles too unless `styles:
  false`; the path is from the root of the test's package, and it throws
  where that is not found).
- One widget's part of the screen, not the whole: `t.linesOf(finder)`,
  `t.linesIn(t.rect(finder))` (its rows, from its first column), and
  `containsLine(line, within: finder)`, `hasTextAt(x, y, text, within:
  finder)` with `x`, `y` from its first cell, for a row that two panes both
  show.
- Finders: `find.text`, `find.byType`, `find.byKey`, `find.descendant`,
  with `findsOneWidget`, `findsNothing`, `findsNWidgets(n)`;
  `t.state<S>(finder)`, `t.widget<W>(finder)`, `t.rect(finder)` (its
  cells, for `styleAt`). `find` is global; `find.text` matches a `Text`'s
  whole string, and a `Button`'s label is no `Text`:
  `find.byWidgetPredicate((w) => w is Button && w.label == 'save')`.
- One `t.pump()` after the input also draws what a future of it changed
  that waits for no timer (the tester runs the app's microtasks first);
  one on a timer needs `t.pump(duration)` past it, a load the next frame
  starts (`initState`, `didUpdateWidget`) a pump more, and so is what a
  `LayoutBuilder` changes in the keys and the hints (built in the frame
  after its layout: a pump more after a `resize`). What arrives in
  real time (a file, a process): `waitUntil(condition, what, between:
  t.pump)`.
- `t.logs.records` holds what the app printed and logged, a build that
  failed and a layout that overflowed among them; a test that fails
  prints its last 20, after its last frames. `t.isRunning` turns false
  once it quit.
- `pumpUntilIdle()` pumps until no frame and no timer waits; it fails
  after 10 s on the clock for an app with a periodic timer or a spinner:
  pump those by a duration. It runs out a toast's and a highlight's
  timers too, so what they show is gone when it returns.
- Only the app's timers and frames are fake: `DateTime.now()` and
  `Stopwatch()` read real time. A widget reads the time from
  `AppBinding.of(context).now()`: the app's start moved on by its clock,
  which a test fixes with `pumpWidget(startTime:)` (1 January 2026 by
  default) and moves by pumping; a `Calendar`, a `DatePicker` and a
  `Heatmap` take today from it. A `CalendarController()` given no cursor
  still reads `DateTime.now()`: give it one (or `Calendar(today: …)`).
- The app as `runApp` runs it, in a real terminal: a test that runs the
  program in twk_term's pseudo-terminal, reads its screen through the
  emulator and waits with `waitUntil` and `waitFor`, never a sleep;
  the testing guide of the twk repository, `doc/guides/testing.md`, has the recipe;
  how `runApp` ends and behaves with no tty (`TWK_PLAIN=1` for plain output)
  is `doc/guides/running.md`. To look at an app by hand or
  script it, twk_dev's `twk record`, `twk play` and `twk tape`.
- A failing matcher shows the screen as text (`styleAt` with styles),
  the widget tree with each widget's size, and the render tree; a failing
  test prints its last 3 frames and the app's log; a failing
  `pumpUntilIdle` lists the timers that wait and where each started.

## Debug

- `TWK_DEBUG=overlay,console dart run bin/main.dart` turns debug aids on
  from the start: `overlay` (frame times and bytes), `console` (the log),
  `rainbow` (what repaints), `relayout`, `keys` (the keys below, also on
  with any of those four), `logs` (serve the log to `twk logs`), `frames`
  (each frame as text below the last). An app can turn the keys on
  itself: `AppBinding.of(context).debug.keys = true`.
- With the keys on, Ctrl+G and then: `o` the overlay, `c` the console
  (Up and Down select a record, `y` copies it, `s` saves the log to a
  file, Escape), `r` the rainbow, `l` the relayout highlight; under
  `twk run`, `h` hot reloads and `H` restarts.
- `TWK_LOG=/tmp/app.log` appends every record of the log to that file.
- `dart run twk_dev:twk run bin/main.dart`: hot reload as the files of
  `lib/` and `bin/main.dart` change, each `State` kept; `main` runs again
  only on Ctrl+G H. The debug keys are on.
- `dart run twk_dev:twk inspect` in a second terminal, in the same
  directory: the widget tree of the app `twk run` runs, the selected
  node's properties and layout, the node outlined on the app's screen;
  `s`, then a click in the app picks the node there.
- `TWK_DEBUG=logs dart run bin/main.dart`, and `dart run twk_dev:twk logs`
  in another terminal, tails the log.
- `debugDumpApp(context)` and `debugDumpRenderTree(context)` print the
  trees, to the log inside an app.
- End to end in a pseudo-terminal, with the repository's tools:
  `python3 <twk>/tool/pty_run.py --size 80x24 --input '2:milk,2.5:\r,3:\x11' --out /tmp/app.bin -- dart run bin/main.dart`
  types into the app at those seconds after its first output, saves what
  it wrote, and fails unless it exits with 0 and leaves the terminal as
  it found it; `dart run <twk>/tool/replay.dart --fullscreen /tmp/app.bin 80 24`
  prints the last screen and exits with 1 for a sequence the emulator
  does not know or text that wraps.

## Pitfalls

- Before writing a widget of your own that twk has, read what it already
  sets (its catalog page, `doc/widgets/`): the authors who copied these
  had not.
  - `LineGauge`: `type: .heavy` is `━` over `─`, `.ascii` too; with
    `type` null the marks are `glyphs.gaugeFilled`/`gaugeEmpty`;
    `segmented`; colour by level is a `filledStyle` picked from the
    ratio; its width is the room it gets.
  - `Callout`: `kind` (colour and icon), `icon: ''` for none, `title`,
    `actions`, `style`, `borderType` (`.rounded`), `titleStyle`;
    `onDismissed` null draws no close mark (`[${glyphs.close}]`: `[×]`,
    `[x]` in ASCII).
  - `Button`: chip, `.outlined`, `.filled`, `tall`, the state styles; a
    flat clickable word is `canRequestFocus: false` with a style without
    a chip; `Button.rich([key, caption])` a label of spans (a key in its
    colour, the caption in another).
  - `RadioGroup`'s marks are the theme's `glyphs.radioOn`/`radioOff`
    between `radioBrackets` (`●`/` ` in `(`, `)`; `radioOn: '◉'`,
    `radioOff: '○'`, `radioBrackets: ('', '')` for `◉ ○`), `mark` over
    `radioOn` for one group; `SegmentedButton`'s `caps`, `showSelectedIcon`; `Select`'s
    `popupLook`, `arrowStyle`, `inline`, `rows`; `‹ x ›` is
    `ValueStepper`, chips are `Chip` and `ChipList`.
  - `Dialog`: `title`, `trailing`, `look`, `shadow`, `padding`,
    `maxWidth`, `scrollable`; `showDialog`'s `alignment` and
    `barrierAlpha: 0` for no dimming; a bare palette is a `Box` of the
    app's own in `showDialog`. A menu at a cell is a `ContextMenu` opened
    with `at:`, a panel by a widget a `Popover`.
  - `CommandPalette`: `look`, `width`, `rows`, `prompt`, `placeholder`,
    `rule`, `bar`, `thumb`, `barrierAlpha`, `hintedKeys`; its ranking is
    the exported `fuzzyMatch`.
- A mark drawn by hand (`Text('✓ done')`, `Span('▸ ')`) stays Unicode
  whatever the theme says: take it from `Theme.of(context).glyphs.check`,
  `.collapsed` and the rest, or from the widget that draws it
  (`StatusMessage`, `TreeView`), so that an app in `Glyphs.ascii` is ASCII
  all through.
- `package:twk/twk.dart` exports all of twk, as Flutter's `material.dart`
  does, generic names among them (`Step`, `Gauge`, `Table`, `Chip`,
  `Window`, `Callout`). Keep the app's own names and hide twk's
  where both are imported: `import 'package:twk/twk.dart' hide
  Gauge;` (or a prefix on the app's own import); do not rename the
  app's types around twk.
- Give generic widgets their type argument: `Table<Entry>(rows:,
  columns: [TableColumn(cell: (e) => …)])`. Columns written inside the
  call get no type from `rows`, and `e.name` does not analyze.
- A list row, a label cut with `…` and something fixed after it, is
  `Row(children: [Expanded(child: Text.line(label)), Text(size)])`;
  columns are `SizedBox(width: n, child: Text.line(…))`; no `LayoutBuilder`
  or `stringWidth`. A list loads more near its end with a
  `NotificationListener<ScrollUpdateNotification>` above it reading
  `metrics.extentAfter` (`doc/guides/layout.md`, "A row of a list").
- A space at the end of a `Text` is lost with the default `wrap:
  TextWrap.word`: it hangs past the line, uncounted and undrawn, so
  `Text('◐ ')` in a `Row` is one cell and the next child touches the mark.
  `Text('◐ ', wrap: .none)` keeps it (two cells). Cell text for a
  `String`: `fitText(segmenterOf(context), s, n)` cuts to `n` cells with `…` (`overflow:` ellipsisStart, ellipsisMiddle or clip; `segmenterOf(context)` is the terminal's `TextSegmenter`, for `.width` too; never a plain `TextSegmenter()`, which counts ambiguous-wide letters one column);
  pad with `padCells(segmenter, s, n)` (`alignment:` right or center; `fitText`'s `overflow:` cuts the start or the middle, `breakLines(segmenter, text, n)` gives the ranges of the lines a text breaks into); a row's background across its
  width is a `ColoredBox` (a `Span`'s paints only its text); a bar on
  every wrapped line is a `Box(border: Border(left: Style()))`
  (`doc/guides/layout.md`, "Text in cells").
- `ListView`, `Table`, `TreeView`, `SelectionList` and `Navigator` take
  all the room they get. In a `Column` put them in `Expanded`, or they
  take the whole height and push the rest off the screen (a
  `RenderFlex overflowed` warning in the log). Inline, a list asks for no
  rows and shows nothing: give it a height (`SizedBox(height: 16, …)`). In debug, a debug-level log record says where the room went.
- Dialogs, toasts, menus, popovers, tooltips, `Select` (not `inline`),
  `DatePicker`, `Autocomplete` and `CommandPalette` need an `Overlay`
  above them (a `Navigator` holds one); without one they fail with a
  `StateError` that says where to put it (a widget, in its error box).
  `runApp` places none: `App(theme:, child:)` at the root places the
  theme, under it the `Overlay`, under that the app (above `App` go the
  providers its dialogs read). The context must be below it: the
  `context` of the build that creates the `Overlay` is above it, so the
  app's root widget is its own, below `App`, or what opens them is in a
  `Builder` below it. The app's root `KeyBindings` go below the
  `Overlay`, in that widget: the keys a dialog leaves go up from it to
  what is above the overlay, so the app's `s` and `q` do not act while
  the dialog is open. A `Navigator` below them changes nothing: a dialog,
  menu, palette, popover or any entry in the navigator's own `Overlay`
  skips the bindings between the navigator and `App`'s overlay, and a
  page pushed on it still gets them. Keys that are to
  work over a dialog too (`ctrl+q`) go above `App`.
- A dialog fades in over 160 ms (`showDialog(fadeIn:)`), a tooltip over
  100 ms (`Tooltip(fadeIn:)`) and a toast slides in over 200 ms, with no
  `fadeIn`: in a test one `t.pump()` shows them at the start, not yet
  drawn. Pump past it (`t.pump(const Duration(milliseconds: 200))`), or
  show the dialog and the tooltip with `fadeIn: Duration.zero`.
- A focused `TextField` takes the characters typed, so `KeyBindings({'q':
  quit})` above it never sees `q`. It lets Tab, Escape, Up, Down, Enter
  without `onSubmitted` and the Ctrl and Alt keys it does not edit with
  go up: `ctrl+s` reaches a binding above it, `ctrl+a` (to the start)
  does not.
- The keys of one read (fast typing, a terminal's burst, `t.type('\t ')`)
  are handled one after another with no build between them. A handler
  reads the state it changes (the `State`'s fields, a controller), not
  what a build or a layout made of it. A widget whose bindings work while
  it has the focus puts its `KeyBindings` inside its `Focus`, always
  built: one built only while `Focus.of(context).hasFocus` misses the key
  right after Tab. Test such keys typed together.
- A `State` disposes what it made: controllers, focus nodes, timers,
  subscriptions.
- `Column` and `Row` centre their children across unless
  `crossAxisAlignment` says otherwise (`.stretch`, `.start`).
- `Column` and `Row` are as long as their room along the axis
  (`mainAxisSize: .max`), also inside another `Column`: a header made of
  a `Column` above an `Expanded` list takes the whole height and leaves
  the list no rows. Give what is to be as big as its children
  `mainAxisSize: .min`.
- `Align` and `Center` with no factor are as big as the room they get, so
  in a `Row` that has a height they take all of it; `heightFactor: 1`
  makes `Align` as tall as its child. Often no `Align` is needed to keep
  a child to the left: `crossAxisAlignment: .start`. Where the axis has no
  end (a scroll view, a list's row) they take the child's size.
- A key hint that is true in one layout only: a `KeyBindings` below the
  `LayoutBuilder` with the binding null in the other layout, not one
  above it; `KeyHintsBar` leaves out a key bound to null.
  The layout guide of the twk repository, `doc/guides/layout.md`, has the recipe.
- Do not cut by hand what twk cuts: `Breadcrumbs` collapses a path to what
  fits (the middle as `…`), and `fuzzyMatch(query, text)` gives the
  `positions` a match highlights, which `Option(label, marks:)` shows in
  an `OptionList`.
- Write nothing to stdout or stderr while the app runs; `print` and
  `log()` already go to the log.
- In the twk repository itself, a new public widget of `packages/twk`
  also needs a row in its README, a build in
  `packages/twk/test/sample_app/<topic>.dart` and a gallery page in
  `packages/gallery/lib/src/pages/<group>.dart`, without which
  `test/exports_test.dart` and `packages/gallery/test/widgets_test.dart`
  fail. An app outside needs none of it.

## Where to look

Paths in `packages/` and `tool/` are in the twk repository; `lib/`,
`bin/` and `test/` are the app's. The reference is
`packages/twk/doc/reference/`, a page per topic (`layout.md`,
`controls.md`, …) and a section per widget naming every parameter, key
and default; `packages/twk_test/doc/guide.md` and `screen.md` for the tester;
`packages/twk_dev/doc/commands.md` for the `twk` command;
`packages/twk/doc/reference/cli.md` for a command-line tool. Whole apps to copy
from: `packages/twk/example/` (`counter.dart`; `interactive.dart`, a chat
with lists, a field and focus; `settings.dart`, menus, tabs, a form, a
dialog and toasts; `monitor.dart`, a sorted table and a tree;
`dashboard.dart`, a grid of live figures, a chart, a heatmap and a log), each with its test in
`packages/twk/test/example/`. Every widget live, with its options and
the Dart that builds it: the gallery, `packages/gallery` (`dart run
packages/gallery/bin/gallery.dart`).

To set an app up outside the repository, depend on the packages by path and override twk and twk_core with the checkout's: twk and twk_test take the packages under them by version, the others by path, and pub takes one source of a package.
