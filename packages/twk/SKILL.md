---
name: twk-apps
description: Build, test and debug terminal UI apps in Dart with the twk widgets (Flutter-like StatelessWidget and StatefulWidget, Column, Row, Box, ListView, Table, TextField, KeyBindings, dialogs) and twk_test (testTwk, type, press, pump, matchesScreen, find). Use when writing or changing an app that imports package:twk/twk.dart, or its tests; also a command-line tool on twk_cli (prompts that collapse into their answer, spinners and task progress, widgets printed in the output) instead of runApp.
---

# Terminal apps with twk

twk is Flutter's widget model on a terminal. An app imports
`package:twk/twk.dart`, and besides it `package:twk/provider.dart` or
`package:twk/hooks.dart` where it uses them; its tests add
`package:twk_test/twk_test.dart`. Everything is measured in cells: sizes,
paddings and offsets are whole columns and rows.

Paths in `packages/` and `tool/` are in the twk repository; `lib/`,
`bin/` and `test/` are the app's. The reference is
`packages/twk/doc/reference.md`, a row per topic naming every widget,
parameter, key and default; `packages/twk_test/README.md` for the tester;
`packages/twk_dev/README.md` for the `twk` command;
`packages/twk_cli/README.md` for a command-line tool. Whole apps to copy
from: `packages/twk/example/` (`counter.dart`; `interactive.dart`, a chat
with lists, a field and focus; `settings.dart`, menus, tabs, a form, a
dialog and toasts; `monitor.dart`, a sorted table and a tree;
`dashboard.dart`, a grid of live figures, a chart, a heatmap and a log), each with its test in
`packages/twk/test/example/`. Every widget live, with its options and
the Dart that builds it: the gallery, `packages/gallery` (`dart run
packages/gallery/bin/gallery.dart`).

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
  errors are printed to stderr once the app has ended. `log` is also a
  name in `dart:math` and `dart:developer`: import those with a prefix.
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
- The code uses Dart's dot shorthands (`.inline`, `.all(type: .rounded)`,
  `.stretch`); the packages need SDK 3.13.5 or later.

## Set up

Depend on the packages by path, and override twk and twk_core with the
checkout's: twk and twk_test take the packages under them by version,
the others by path, and pub takes one source of a package.

```yaml
# pubspec.yaml; <twk> is where the twk repository is checked out
name: my_app
publish_to: none
environment:
  sdk: ^3.13.5
dependencies:
  twk:
    path: <twk>/packages/twk
  # only for a command-line tool (below)
  twk_cli:
    path: <twk>/packages/twk_cli
dev_dependencies:
  test: ^1.33.0
  twk_dev:
    path: <twk>/packages/twk_dev
  twk_test:
    path: <twk>/packages/twk_test
dependency_overrides:
  twk:
    path: <twk>/packages/twk
  twk_core:
    path: <twk>/packages/twk_core
```

`dart pub get`, then an app (`dart run bin/main.dart`): type a task and
Enter adds it, Tab goes to the list, Space marks the task done there.

```dart
// lib/todo.dart
import 'package:twk/twk.dart';

/// A to-do list: Enter adds the task typed, Tab goes to the list, Space
/// marks a task done there, Ctrl+Q quits.
final class TodoApp extends StatefulWidget {
  const TodoApp({super.key});

  @override
  State<TodoApp> createState() => _TodoAppState();
}

final class _TodoAppState extends State<TodoApp> {
  final _tasks = <String>[];
  final _text = TextEditingController();
  // the tasks done, by index
  final _done = SelectionController<int>(multiple: true);

  @override
  void dispose() {
    _text.dispose();
    _done.dispose();
    super.dispose();
  }

  void _add(String task) {
    if (task.trim().isEmpty) {
      return;
    }
    setState(() => _tasks.add(task.trim()));
    _text.clear();
  }

  @override
  Widget build(BuildContext context) => KeyBindings(
    // not 'q': the focused field would take it as text
    {'ctrl+q': () => AppBinding.of(context).quit()},
    hints: const {'ctrl+q': 'quit'},
    child: Column(
      crossAxisAlignment: .stretch,
      children: [
        // a list takes all the room it gets: Expanded bounds it
        Expanded(
          child: Box(
            border: const .all(type: .rounded),
            titles: const [BorderTitle(' To do ')],
            child: SelectionList<int>(
              itemCount: _tasks.length,
              keyOf: (i) => i,
              itemBuilder: (context, i) => Text(_tasks[i]),
              controller: _done,
            ),
          ),
        ),
        TextField(
          controller: _text,
          placeholder: 'a task, Enter adds it',
          onSubmitted: _add,
          autofocus: true,
        ),
        // the keys hinted where the focus is: Space on the list, Ctrl+Q
        const KeyHintsBar(),
      ],
    ),
  );
}
```

```dart
// bin/main.dart
import 'package:my_app/todo.dart';
import 'package:twk/twk.dart';

Future<void> main() => runApp(const TodoApp());
```

## A command-line tool: twk_cli, not runApp

`runApp` is for a program whose screen is its interface: an editor, a
dashboard, a monitor, a list moved through. A command run from a shell
or a script (an installer, an `init`-style setup, a deploy, a tool with
flags) prints lines, asks a question or two and shows progress, and has
to work as well in a pipe, in a CI log and with nobody at the keyboard:
for that, depend on twk_cli (`packages/twk_cli/README.md`) and call no
`runApp`. A program does one or the other: where somebody answers at a
terminal, twk_cli runs an inline twk app of its own.

- `Cli.runWithArgs(args, (cli, rest) async { … })` runs the body with a
  console, takes `-v`, `-q`, `--no-color` and `--no-input` out of the
  arguments, and ends what the body throws with a traceback on stderr
  and exit code 1.
- `cli.info`, `cli.success`, `cli.detail` (shown with `-v`), `cli.warn`
  and `cli.err` (both to stderr) write lines; `await cli.show(widget)`
  prints any twk widget once, at the terminal's width (a `Table`, a
  `Box`, a `DescriptionList`, a `Callout`); `cli.inspect(value)` prints a
  value as a tree of JSON.
- `await cli.prompt(question)`, `cli.confirm`, `cli.chooseOne(question,
  choices:)` and `cli.chooseAny`: at a terminal, a widget that collapses
  into one committed line once answered (`✔ Target environment? prod`);
  on a terminal without escapes, a line read, choices by number; where
  nobody can answer (stdin no terminal, `CI`, `--no-input`), the
  default, or a `PromptAnswerRequiredException` without one. `confirm`
  without a default never says yes for anybody: a question that changes
  something wants a `--yes` flag.
- `cli.progress(message).run(work, done: …)` is a spinner, then the line
  `done` gives with the time it took; `cli.tasks((tracker) => …)` runs
  many tasks at once, each `tracker.run(label, (task) => …, total:)`
  with its bar, rate and time left (twk's `ProgressList`). Where the
  terminal does not redraw, both write lines.
- Its tests give the console a `FakeCliTerminal`
  (`package:twk_cli/testing.dart`): `.plain(lines: […])` answers the
  prompts a line each, `.interactive(input: […])` types keys into the
  widgets, and `FakeCliTerminal()` is nobody at the keyboard.

```dart
// lib/deploy.dart
import 'package:twk/twk.dart';
import 'package:twk_cli/twk_cli.dart';

/// Asks where to deploy, and again before production unless `--yes`
/// says so, deploys with a spinner and shows what it deployed.
Future<void> deploy(Cli cli, List<String> args) async {
  final target = await cli.chooseOne(
    'Target environment?',
    choices: ['dev', 'stage', 'prod'],
    // what CI gets: where nobody can answer, a prompt without a default
    // throws
    defaultValue: 'dev',
  );
  // no default: nobody's yes is assumed
  if (target == 'prod' &&
      !args.contains('--yes') &&
      !await cli.confirm('Deploy to prod?')) {
    cli.info('Nothing deployed.');
    return;
  }
  await cli
      .progress('Deploying to $target')
      .run(() => upload(target), done: (_) => 'Deployed to $target');
  await cli.show(
    DescriptionList(
      items: [
        DescriptionItem.text('Target', target),
        DescriptionItem.text('Version', '1.4.2'),
      ],
    ),
  );
}

/// Where a real tool would upload.
Future<void> upload(String target) =>
    Future<void>.delayed(const Duration(milliseconds: 100));
```

```dart
// bin/deploy.dart
import 'package:my_app/deploy.dart';
import 'package:twk_cli/twk_cli.dart';

Future<void> main(List<String> args) => Cli.runWithArgs(args, deploy);
```

```dart
// test/deploy_test.dart
import 'package:my_app/deploy.dart';
import 'package:test/test.dart';
import 'package:twk_cli/testing.dart';
import 'package:twk_cli/twk_cli.dart';

void main() {
  test('where nobody can answer, the default is taken', () async {
    final terminal = FakeCliTerminal();
    await deploy(Cli(terminal: terminal), []);
    expect(terminal.out.toString(), contains('Deployed to dev'));
  });

  test('on a plain terminal, a choice is answered by its number', () async {
    final terminal = FakeCliTerminal.plain(lines: ['3', 'n']);
    await deploy(Cli(terminal: terminal), []);
    expect(terminal.out.toString(), contains('Nothing deployed.'));
  });

  test('at a terminal, each answer collapses into its line', () async {
    final terminal = FakeCliTerminal.interactive(input: ['\x1B[B', '\r']);
    final cli = Cli(terminal: terminal);
    await deploy(cli, []);
    await cli.close();
    expect(terminal.screenLines, contains('✔ Target environment? stage'));
  });
}
```

## Widgets by need

Each is described, with every parameter, in its topic's row of
`packages/twk/doc/reference.md`.

| need | widgets |
|------|---------|
| layout | `Column`, `Row` (`gap:`; `crossAxisAlignment` is `.center` unless set), `Expanded`, `Flexible`, `Spacer`, `Padding`, `SizedBox`, `Center`, `Align`, `Box` (`border:`, `titles:`, `padding:`, `style:` fills it), `Divider`, `Grid` + `GridPlacement`, `Stack` + `Positioned`, `Wrap`, `SplitView` (panes with draggable dividers), `ExpansionTile` + `Accordion` (sections that fold; `ExpansionController`), `Container` (Flutter's: `padding:`, `margin:`, `color:`, `decoration: BoxDecoration(…)`, `width:`, `height:`), `ColoredBox`, `DecoratedBox`, `LimitedBox`, `OverflowBox`, `SizedOverflowBox`, `Transform.translate` (whole cells; no rotation or scale), `Offstage` and `Visibility` (hide, keeping state), `RepaintBoundary` (isolate a part that changes often), `CustomPaint` + `CellPainter` (cells painted by hand) |
| text and style | `Text(text, style:, wrap:, overflow:, maxLines:)`, `Text.rich([spans])`, `'x'.bold.fg(.green)` (a `Span`), `Style(fg:, bg:, attrs:)`, `Theme(data: ThemeData.nord, child:)`, `Theme.adaptive` (dark or light by the terminal), `Theme.of(context).primary`, `Link` |
| keys | `KeyBindings({'ctrl+s': save, 'g g': top}, hints: {'ctrl+s': 'save'}, child:)`, `Shortcuts` + `Actions` + `Intent`, `KeyHintsBar`, `InputListener` (keys nobody took, pastes, resizes) |
| focus | `autofocus: true`, `FocusNode` (`requestFocus()`, `hasFocus`), `Focus`, `FocusScope`, `ExcludeFocus` (keep the focus out of a part) |
| mouse (full screen) | `GestureDetector(onTap:, onDoubleTap:, onLongPress:, onDragUpdate:)`, `Listener`, `MouseRegion`, `Draggable` + `DragTarget`, `SelectionArea` (select and copy text; `SelectionAreaController`; a render object of your own mixes in `Selectable`), `Tooltip` (also on focus; `TooltipController`), `IgnorePointer`, `AbsorbPointer` |
| lists and data | `ListView`, `ListView.builder` (lazy; `stickToBottom`; `ListController`; `reverse: true` for a chat, item 0 at the bottom; keyed items stay in place as items are inserted above), `ListView.separated`, `ScrollController(stickToEnd: true)` (follow the end of any scrollable), `LogView` + `LogController` (a log that follows its tail, with levels, a filter and search), `SingleChildScrollView`, `Scrollbar`, `SelectionList<K>`, `Table<T>`, `Table<T>.source` (a million rows), `TreeView<T>`, `TreeTable<T>` (a tree with columns), `DirectoryTree` (a file tree for a side panel; `DirectoryTreeController`), `TaskList`, `DescriptionList` + `DescriptionItem` (terms and their values, aligned), `Heatmap`, `ActivityHeatmap` (counts by day over weeks), `Sparkline`, `Gauge`, `LineGauge`, `BarChart`, `Chart`, `Calendar`, `DotCanvas` |
| text input | `TextField` + `TextEditingController` (`onSubmitted`, `onChanged`, `obscureText`, `readOnly`, `enabled`, `onPaste`; Ctrl+C and Ctrl+X copy and cut a selection; `decoration: InputDecoration(icon:, labelText:, helperText:, errorText:, prefixIcon:, prefixText:, suffixIcon:, suffixText:, border: OutlineInputBorder() / UnderlineInputBorder() / InputBorder.none, filled:)`), `InputDecorator` (a decoration around any control), `TextArea` (lines), `Autocomplete` |
| controls and forms | `Button`, `Checkbox`, `Switch`, `RadioGroup<T>`, `Select<T>`, `MultiSelect<T>` (`decoration:` a label and a border, as a field's), `Slider`, `NumberInput`, `DatePicker`, `ConfirmInput`, `FilePicker` (`showFilePicker`; `FilePickerController`), `PopupController` (open a `Select`'s or a `DatePicker`'s popup from code), `Form` + `FormField<T>` + `TextFormField`, `TabBar` + `TabView` + `TabController`, `SegmentedButton<T>` (a compact choice on one row), `StatusBar`, `StatusMessage`, `Callout` (a boxed notice of a `StatusKind`, dismissible), `Badge` |
| over the app (need an `Overlay`) | `showDialog` + `Dialog` + `closeDialog`, `showToast`, `MenuBar` + `Menu` + `MenuItem`, `ContextMenu` (both with a `MenuController`), `Popover`, `CommandPalette` (`CommandPaletteController`, `commandsFor:`), `ModalBarrier`, `AnimatedModalBarrier` |
| screens | `Scaffold` (header, sidebar, body, status bar and key hints, a focus zone each; `ScaffoldController`), `Navigator` (`push`, `pop`, named routes; Escape pops; holds an `Overlay`; `observers:`; `PageRoute(transitionDuration:)` slides in), `PopScope` (refuse or intercept a pop), `Stepper` + `Step` (a wizard whose steps validate; `StepperController`), `Breadcrumbs`, `Pagination` |
| built inline | `Builder` (a context of its own), `StatefulBuilder` (a state of its own: `builder: (context, setState) => …`), `LayoutBuilder` (by the constraints), `FocusBuilder` (by whether the focus is in it) |
| async and time | `FutureBuilder`, `StreamBuilder`, `ListenableBuilder`, `ValueListenableBuilder`, `AnimatedBuilder`, `Spinner`, `ProgressBar`, `ProgressList` + `ProgressTracker` (many tasks with bars, rate and time left), `Skeleton` and `Skeletonize` (placeholders that shimmer while content loads), `AnimationController` + `TickerProviderStateMixin`, `Tween`, `Curves` |
| state over the tree, hooks | `package:twk/provider.dart`, Provider's API: `Provider`, `ChangeNotifierProvider`, `MultiProvider`, `context.read<T>()`, `context.watch<T>()`, `context.select`, `Consumer`, `Selector` (twk_bloc builds on it); `package:twk/hooks.dart`, flutter_hooks': `HookWidget`, `HookBuilder`, `useState`, `useEffect`, `useMemoized`, `useTextEditingController`. Each is imported besides `package:twk/twk.dart`, and has its section in `packages/twk/doc/reference.md` |
| inline output | `Static` |
| other | `AppBinding.of(context).notify(title, body)` (a desktop notification), `debugDumpTree(context)`, `Console`, `Semantics(hint:)` and `ExcludeSemantics` (what a screen reader reads) |

## Recipes

Each stands on its own; `test/recipes_test.dart` below tests them.

```dart
// lib/recipes.dart
import 'dart:async';

import 'package:twk/twk.dart';

/// The root of an app with dialogs: the Overlay under the Theme, so what
/// it shows sees the theme, and the screens below it, so their contexts
/// find it.
final class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => const Theme(
    data: ThemeData.nord,
    child: Overlay(child: Home()),
  );
}

final class Home extends StatelessWidget {
  const Home({super.key});

  Future<void> _delete(BuildContext context) async {
    final sure = await showDialog<bool>(
      context,
      (context) => Dialog(
        title: 'Delete the file?',
        child: Row(
          mainAxisSize: .min,
          gap: 2,
          children: [
            Button('Delete', onPressed: () => closeDialog(context, true)),
            Button(
              'Cancel',
              autofocus: true,
              onPressed: () => closeDialog(context, false),
            ),
          ],
        ),
      ),
    );
    if ((sure ?? false) && context.mounted) {
      showToast(context, 'Deleted.');
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Button(
      'Delete…',
      autofocus: true,
      onPressed: () => unawaited(_delete(context)),
    ),
  );
}

final class Entry {
  const Entry(this.name, this.size);

  final String name;
  final int size;
}

/// [entries] in columns: a click on a title or `s` sorts, Up and Down
/// select a row, Enter logs it. The type argument is needed: the columns'
/// closures get no type from `rows`.
Widget entryTable(List<Entry> entries) => Table<Entry>(
  rows: entries,
  columns: [
    TableColumn(
      title: 'name',
      cell: (e) => TableCell(e.name),
      compare: (a, b) => a.name.compareTo(b.name),
    ),
    TableColumn(
      title: 'size',
      width: const .fixed(8),
      align: .right,
      cell: (e) => TableCell('${e.size}'),
      compare: (a, b) => a.size.compareTo(b.size),
    ),
  ],
  onActivated: (e) => log('open ${e.name}'),
  autofocus: true,
);

/// A log that follows its newest line while it shows the end; only the
/// lines in view are built.
Widget logView(List<String> lines) => Scrollbar(
  child: ListView.builder(
    itemCount: lines.length,
    itemBuilder: (context, i) => Text(lines[i]),
    stickToBottom: true,
  ),
);

/// Inline (`runApp(const Prompt(), mode: .inline)`): each line sent goes
/// to the terminal's scrollback, the field alone stays in the app's rows.
final class Prompt extends StatefulWidget {
  const Prompt({super.key});

  @override
  State<Prompt> createState() => _PromptState();
}

final class _PromptState extends State<Prompt> {
  final _sent = <String>[];
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      Static(items: _sent, builder: (context, line) => Text('> $line')),
      TextField(
        controller: _text,
        autofocus: true,
        onSubmitted: (line) {
          setState(() => _sent.add(line));
          _text.clear();
        },
      ),
    ],
  );
}

/// A spinner until [answer] completes, then its text or its error. Make
/// the future once (in `initState`, or in the caller), not in a build.
Widget answerView(Future<String> answer) => FutureBuilder<String>(
  future: answer,
  builder: (context, snapshot) => switch (snapshot) {
    AsyncSnapshot(hasError: true) => Text('failed: ${snapshot.error}'),
    AsyncSnapshot(hasData: true) => Text(snapshot.requireData),
    _ => const Spinner(),
  },
);

/// The seconds since it was shown, on a timer its state owns and cancels.
final class Uptime extends StatefulWidget {
  const Uptime({super.key});

  @override
  State<Uptime> createState() => _UptimeState();
}

final class _UptimeState extends State<Uptime> {
  var _seconds = 0;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _seconds++),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('up ${_seconds}s');
}
```

## Test

`testTwk` runs the real app on a terminal in memory under a fake clock:
input goes in as the bytes a terminal sends, and the screen is rebuilt
from the bytes the app wrote. `dart test` runs it.

```dart
// test/todo_test.dart
import 'package:my_app/todo.dart';
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk('Enter adds the task typed, Space in the list marks it done', (
    t,
  ) async {
    await t.pumpWidget(const TodoApp(), size: (30, 6));
    await t.type('buy milk');
    await t.press('enter');
    // a frame builds the task's row, which Space needs
    await t.pump();
    await t.press('tab space');
    await t.pump();
    expect(
      t,
      matchesScreen('''
╭ To do ─────────────────────╮
│▎[x] buy milk               │
│                            │
╰────────────────────────────╯
a task, Enter adds it
space toggle   ctrl+q quit
'''),
    );
    // the list's cursor is on the task: the test's terminal says no
    // background, so the app is in its own colors, the cursor on their
    // selection's grey
    expect(t, styleAt(5, 1, hasBg(const Color.indexed(237))));
    expect(find.text('buy milk'), findsOneWidget);
  });

  testTwk('the field takes q; Ctrl+Q quits', (t) async {
    await t.pumpWidget(const TodoApp());
    await t.type('q');
    await t.pump();
    expect(t, containsLine('q'));
    await t.press('ctrl+q');
    expect(t.isRunning, isFalse);
  });
}
```

```dart
// test/recipes_test.dart
import 'package:my_app/recipes.dart';
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk('a dialog asks first, a toast says it is done', (t) async {
    await t.pumpWidget(const App(), size: (40, 12));
    await t.press('enter');
    // a dialog fades in over 160 ms: at its first frame it is not seen yet
    await t.pump(const Duration(milliseconds: 200));
    expect(t, containsLine(contains('Delete the file?')));
    // Cancel has the focus: Shift+Tab goes back to Delete
    await t.press('shift+tab enter');
    // a toast slides in from the right over 200 ms
    await t.pump(const Duration(milliseconds: 300));
    expect(t, containsLine(contains('Deleted.')));
  });

  testTwk('the table sorts by a click on a title', (t) async {
    await t.pumpWidget(
      entryTable(const [Entry('b.txt', 10), Entry('a.txt', 200)]),
      size: (20, 4),
    );
    await t.clickOn(find.text('name'));
    await t.pump();
    expect(
      t,
      matchesScreen('''
name ▴     size
a.txt       200
b.txt        10
'''),
    );
    await t.press('down enter');
    expect(t.logs.records.last.message, 'open a.txt');
  });

  testTwk('inline, the lines sent go to the scrollback', (t) async {
    await t.pumpWidget(
      const Prompt(),
      size: (30, 3),
      mode: ScreenMode.inline,
      history: [r'$ my_app'],
    );
    for (final line in ['one', 'two', 'three']) {
      await t.type(line);
      await t.press('enter');
      await t.pump();
    }
    expect(t.scrollback, [r'$ my_app', '> one']);
    expect(t.lines, ['> two', '> three', '']);
  });

  testTwk('the clock moves only when the test moves it', (t) async {
    await t.pumpWidget(const Uptime());
    await t.pump(const Duration(seconds: 3));
    expect(t, containsLine('up 3s'));
  });
}
```

What to know:

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
  of its own, the keys named as `KeyBindings` names them. `press('escape')`
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
  `[bold]…[/]` runs too).
- Finders: `find.text`, `find.byType`, `find.byKey`, `find.descendant`,
  with `findsOneWidget`, `findsNothing`, `findsNWidgets(n)`;
  `t.state<S>(finder)`, `t.widget<W>(finder)`, `t.rect(finder)`.
- `t.logs.records` holds what the app printed and logged, `t.isRunning`
  turns false once it quit.
- `pumpUntilIdle()` pumps until no frame and no timer waits; it fails
  after 10 s on the clock for an app with a periodic timer or a spinner:
  pump those by a duration.
- Only the app's timers and frames are fake: `DateTime.now()` and
  `Stopwatch()` read real time. Pass dates in (`Calendar(today: …)`).
- A failing matcher shows the screen, the widget tree with each widget's
  size, and the render tree; a failing test prints its last 3 frames.

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
- `debugDumpTree(context)` and `debugDumpRenderTree(context)` print the
  trees, to the log inside an app.
- End to end in a pseudo-terminal, with the repository's tools:
  `python3 <twk>/tool/pty_run.py --size 80x24 --input '2:milk,2.5:\r,3:\x11' --out /tmp/app.bin -- dart run bin/main.dart`
  types into the app at those seconds after its first output, saves what
  it wrote, and fails unless it exits with 0 and leaves the terminal as
  it found it; `dart run <twk>/tool/replay.dart --fullscreen /tmp/app.bin 80 24`
  prints the last screen and exits with 1 for a sequence the emulator
  does not know or text that wraps.

## Pitfalls

- Give generic widgets their type argument: `Table<Entry>(rows:,
  columns: [TableColumn(cell: (e) => …)])`. Columns written inside the
  call get no type from `rows`, and `e.name` does not analyze.
- `ListView`, `Table`, `TreeView`, `SelectionList` and `Navigator` take
  all the room they get. In a `Column` put them in `Expanded`, or they
  take the whole height and push the rest off the screen (a
  `RenderFlex overflowed` warning in the log). Inline, a list asks for no
  rows and shows nothing: give it a height (`SizedBox(height: 16, …)`).
- Dialogs, toasts, menus, popovers, tooltips, `Select` (not `inline`),
  `DatePicker`, `Autocomplete` and `CommandPalette` need an `Overlay`
  above them (a `Navigator` holds one); without one they fail with a
  `StateError` that says where to put it (a widget, in its error box).
  The context must be below it: the `context` of the build that creates
  the `Overlay` is above it, so build the `Overlay` in a parent widget,
  as `App` does, or what opens them in a `Builder` below it.
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
- Write nothing to stdout or stderr while the app runs; `print` and
  `log()` already go to the log.
- In the twk repository itself, a new public widget of `packages/twk`
  also needs a row in its README, a build in
  `packages/twk/test/sample_app/<topic>.dart` and a gallery page in
  `packages/gallery/lib/src/pages/<group>.dart`, without which
  `test/exports_test.dart` and `packages/gallery/test/widgets_test.dart`
  fail. An app outside needs none of it.
