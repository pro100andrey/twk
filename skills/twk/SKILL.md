---
name: twk
description: Write, test and debug terminal UI apps in Dart with twk, which has Flutter's widget model (StatelessWidget, StatefulWidget, Column, Row, Expanded) on a grid of character cells, with its own widgets (Box, ListView, Table, TextField, KeyBindings, dialogs) and tests (testTwk, type, press, pump, matchesScreen). Use when writing or changing code that imports package:twk/twk.dart, package:twk/cli.dart or package:twk_test, before writing any Flutter-style widget code for a terminal: twk's names, units and defaults differ from Flutter's in ways memory gets wrong.
---

# Terminal apps with twk

twk is Flutter's widget model on a terminal: `State`, `setState`,
`BuildContext`, keys, constraints down and sizes up, `Navigator`,
`Overlay`, `Focus` behave as in Flutter. The unit, the catalog and the
input do not. Do not write Flutter's API from memory: there is no Material,
no TextStyle, no MediaQuery, no pixels. Look a widget up (References) before using it.

An app imports `package:twk/twk.dart`, and besides it `package:twk/provider.dart`
(`ChangeNotifierProvider`), `package:twk/hooks.dart` (`HookWidget`) or
`package:twk/log.dart` where it uses them; a command-line tool that prints,
asks and shows progress, instead of drawing a screen, uses
`package:twk/cli.dart` (`Cli`) and no `runApp`; its tests add
`package:twk_test/twk_test.dart` (and `package:twk_test/cli.dart`,
`FakeCliTerminal`). The code uses Dart's dot shorthands (`.stretch`,
`.inline`); the SDK is 3.13.5 or later.

## Where twk differs from Flutter

Each pair is the line a model writes from memory (`-`) and the one that is
right (`+`).

```diff
# sizes are whole cells, ints; BoxConstraints.tight takes two ints
- SizedBox(width: 20.5, height: 10.0)
- BoxConstraints.tight(Size(20, 3))
+ SizedBox(width: 20, height: 10)
+ BoxConstraints.tight(20, 3)
# a style has colors and attributes, no font; spans are strings with a Style
- Text('x', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
- Text.rich(TextSpan(children: [TextSpan(text: 'x')]))
+ Text('x', style: Style(fg: .red, attrs: Attr.bold))
+ Text.rich(['error: '.bold.fg(.red), 'disk full'.dim])
# no Material: App is the root, Scaffold the screen
- MaterialApp(home: Scaffold(appBar: AppBar(), body: Card()))
+ App(theme: ThemeData.nord, child: Scaffold(body: Box(border: .all())))
# the room is in the constraints, there is no MediaQuery
- MediaQuery.of(context).size.width
+ LayoutBuilder(builder: (context, constraints) => Text('${constraints.maxWidth}'))
# a Column centres across; a list takes all the room it gets
- Column(children: [ListView(children: rows)])
+ Column(crossAxisAlignment: .stretch, children: [Expanded(child: ListView(children: rows))])
# keys are strings, in lower case
- RawKeyboardListener(onKey: onKey, child: child)
+ KeyBindings({'ctrl+s': save, 'g g': top}, hints: {'ctrl+s': 'save'}, child: child)
# the generic widgets are given their type argument
- Table(rows: entries, columns: [TableColumn(cell: (e) => TableCell(e.name))])
+ Table<Entry>(rows: entries, columns: [TableColumn(cell: (e) => TableCell(e.name))])
# marks come from the theme, so that Glyphs.ascii switches the app
- Text('✓ done')
+ Text('${Theme.of(context).glyphs.check} done')
# tests: testTwk, not flutter_test
- await tester.tap(find.byType(Button)); await tester.pumpAndSettle();
+ await t.press('enter'); await t.pump();
```

- `DefaultTextStyle(style:)` merges onto the style above (Flutter's plain
  constructor replaces it). The `Future` of `AnimationController.forward`,
  `reverse`, `animateTo` and `repeat` completes when something stops the
  run too, so an `await` does not hang.
- `package:twk/twk.dart` exports all of twk, `Step`, `Gauge`, `Table`,
  `Chip`, `Window` among them: `import 'package:twk/twk.dart' hide Gauge;`
  where an app defines the same name, not a rename of the app's types.
- `print` and `log()` go to the app's log, never the screen; write nothing
  to stdout or stderr while the app runs. A build that throws shows a
  red box and the app goes on; a throw in a key binding ends it with a
  `WidgetError` naming the widget path.
- `runApp(app)` is full screen; `runApp(app, mode: .inline)` runs in rows
  below the prompt; only full screen gets the mouse. Dialogs, toasts, menus, popovers, `Select` and `DatePicker` need an
  `Overlay` above their context: `App(theme:, child:)` at the root places
  it (a `Navigator` holds one), and what opens a dialog is below `App`, in
  a widget of its own or a `Builder`.
- Only the focused widget gets a key first, then `KeyBindings` above it.
  A focused `TextField` takes `q` and `ctrl+a`, so bind `ctrl+q` to quit;
  it lets Tab, Escape and the Ctrl keys it does not edit with go up.

## An app

Depend on the packages by path, and override `twk` and `twk_core` with the
checkout's. `dart pub get`, then `dart run bin/main.dart`: type a task and
Enter adds it, Tab goes to the list, Space marks the task done there.

```yaml
# pubspec.yaml; <twk> is where the twk repository is checked out
name: my_app
publish_to: none
environment:
  sdk: ^3.13.5
dependencies:
  twk:
    path: <twk>/packages/twk
dev_dependencies:
  test: ^1.33.0
  twk_test:
    path: <twk>/packages/twk_test
dependency_overrides:
  twk:
    path: <twk>/packages/twk
  twk_core:
    path: <twk>/packages/twk_core
  twk_term:
    path: <twk>/packages/twk_term
```

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

## Test

`testTwk` runs the real app on a terminal in memory under a fake clock:
input goes in as the bytes a terminal sends, and the screen is rebuilt from
the bytes the app wrote. `dart test` runs it.

```dart
// test/todo_test.dart
import 'package:my_app/todo.dart';
import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk('Enter adds the task typed, Space in the list marks it done', (
    t,
  ) async {
    await t.pumpWidget(const TodoApp(), size: (30, 6));
    await t.type('buy milk');
    await t.press('enter');
    // pump: Space needs the row that Enter's frame builds
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
    expect(find.text('buy milk'), findsOneWidget);
  });
}
```

- Input draws nothing by itself: `await t.pump()` after `type`, `press` or a
  click, before reading the screen. `t.pump(duration)` moves the fake clock;
  a dialog fades in over 160 ms and a toast over 200 ms: pump past them.
- `type('text')` sends text as one read; `press('tab space')` sends each
  key as a read of its own, named as `KeyBindings` names them. Read the screen with `t.lines`, `containsLine`, `matchesScreen('''...''')`,
  `styleAt`; find widgets with `find.text`, `find.byType`, `find.byKey`.
  `t.logs.records` holds what the app printed. A test never sleeps: it pumps
  the clock, or `waitUntil`s a real event.

## Pitfalls

- A list (`ListView`, `Table`, `TreeView`, `SelectionList`, `Navigator`)
  takes all the room it gets. In a `Column` put it in `Expanded`, or it
  takes the whole height and pushes the rest off the screen (a
  `RenderFlex overflowed` warning in the log). Inline, a list asks for no
  rows and shows nothing: give it a height (`SizedBox(height: 16, ...)`).
- Keys typed together (a burst, `t.type('\t ')`) are handled one after
  another with no build between them. A widget whose bindings work while
  it has the focus puts its `KeyBindings` inside its `Focus`, always built:
  one built only while `Focus.of(context).hasFocus` misses the key right
  after Tab.
- `pumpUntilIdle()` fails for an app with a periodic timer or a spinner:
  pump those by a duration.
- A test's `pumpWidget` puts nothing above what it is given: a widget that
  opens a dialog or a toast is pumped as `App(child: ...)`, which has the
  `Overlay`.
- The state may be gone when `await showDialog(...)` returns: `if (status !=
  null && mounted)` before `setState`. Children made in a loop take a key,
  `Button(key: ValueKey(s), ...)`. twk_lints says both.

## References

Read the one that matches the widget, not all of them. `references/`, next
to this file, is written from the widget catalog and the guides:

- `references/widgets.md`: every widget, one line each, by group.
- `references/widgets/<group>.md`: the group's widgets with every option,
  and the Dart that builds them.
- `references/guides/`: the guides (layout, input and focus, theming,
  state, testing, screen modes, running, performance), and in them
  `recipes.md` (a dialog, a table, a log, an inline prompt, a
  command-line tool), `widgets-by-need.md` (which widget for which need)
  and `details.md` (the debug aids and pitfalls in full).

Whole apps to copy are in the twk repository, `packages/twk/example/`, each
with its test; `dart run packages/gallery/bin/gallery.dart` there shows
every widget live.

If `references/` is not next to this file, the skill was copied short:
`dart run twk_dev:twk agents` in the project writes the whole of it, or
copy `skills/twk/` of the twk repository (github.com/pro100andrey/twk)
whole, SKILL.md and `references/`, to `.agents/skills/twk` or
`.claude/skills/twk`.
