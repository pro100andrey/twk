# twk_lints — lints and assists for twk apps

An analyzer plugin for apps built on [twk](../twk/README.md): warnings
and lints that `dart analyze` and the editor report, and assists that
the editor offers at the cursor. It is a plugin of the analysis server's
own plugin system (Dart 3.10 and later), on `analysis_server_plugin`
0.3 and `analyzer` 14, the analyzer that version of the plugin package
pins; it does not depend on twk, and knows twk's classes by name
and package (`package:twk`, `package:twk_core`); its tests alone depend
on twk, to hold what it ports of twk to twk.

## Enabling it

The recommended set, `lib/recommended.yaml`, is the plugin with every
rule on. An app that takes twk_lints as a dev dependency includes it
from its `analysis_options.yaml`, alone or in a list beside other sets:

```yaml
include:
  - package:pro_lints/recommended.yaml
  - package:twk_lints/recommended.yaml
```

The templates of `twk create` (twk_dev) do so. The file names the plugin
by `path: ..`, which the analyzer reads relative to the file that says
it, so it is twk_lints wherever its package resolves. Checked from a
scratch app on the SDK of this repository (3.13.7): an included file
carries the `plugins` section and its `diagnostics`, `dart analyze`
reporting the warnings and the lints it turns on, and none with an
included file that has no `plugins`. An app's own `plugins` section
does not merge with the included one: one that names `twk_lints` with
its path takes its place whole, so only what it turns on is on, and one
that names it without a path is ignored, without a word. To turn a rule
off, an app names the plugin itself, as below, with every lint it keeps.
The dev dependency brings the plugin's own dependencies into the app's
resolution: `analysis_server_plugin`, and the `analyzer` it pins.

An app names the plugin in the top-level `plugins` section of its
`analysis_options.yaml` (not under `analyzer:`, where the old plugin
system had them), and turns on the lints it wants under `diagnostics`;
the warnings are on unless turned off there:

```yaml
plugins:
  twk_lints:
    path: /path/to/twk/packages/twk_lints
    diagnostics:
      missing_key_in_children: true
      untyped_table: true
      prefer_key_bindings: true
      wall_time_in_tests: true
      unnamed_control: true
      # dispose_controllers: false
```

The analysis server makes a package that depends on the plugin, resolves
it with `dart pub upgrade` and runs the plugin in an isolate of its own:
the first analysis after a change to the section compiles it (half a
minute here), and an editor's analysis server picks up a change only when
it restarts. Only the `analysis_options.yaml` at the root of a package or
workspace can enable plugins, itself or by a file it includes.

A diagnostic is ignored as the analyzer's are, with the plugin's name
before its own: `// ignore: twk_lints/untyped_table`,
`// ignore_for_file: twk_lints/set_state_after_dispose`.

## Warnings and lints

| name | kind | reports | fix |
|------|------|---------|-----|
| `set_state_after_dispose` | warning | A `setState` of a `State` that may run once the state was disposed, which fails twk's assert: one in `dispose`; one that some path reaches after an `await` (also one round of a loop to the next, and each element of an `await for`), or in a callback of a `Future` (`then`, `catchError`, `whenComplete`, `Future.delayed`), with no check of `mounted` since on that path. The paths are followed through `if`/`else`, `? :`, `&&`/`\|\|`/`!`, loops, `switch`, `try`/`catch` and `return`/`throw`/`break`/`continue`, so a check is `if (mounted)` (also `context.mounted`, and it `&&` more) around the call, `if (!mounted) return;` (also `\|\|` more) before it, or a check in each branch of an `if` that awaited. A guard of the code's own (a token, a flag) is not seen: add `mounted &&` to it. | *Add 'if (!mounted) return;'* before the statement, where the function returns nothing, for one after an `await` or in a callback; none for one in `dispose`, where what the change does instead of `setState` is the author's call. |
| `context_after_await` | warning | A `State`'s `context`, or a variable or parameter of twk's `BuildContext` type, used on a path from an `await` (or in a callback of a `Future`) with no check of `mounted` since, the paths and checks as for `set_state_after_dispose`; by then the widget may have left the tree, `State.context` asserts and a context kept from before finds no inherited widget or ancestor. The Dart linter's `use_build_context_synchronously` does not know twk's `BuildContext`. Not reported: a context passed to the awaited call itself, a variable assigned after the `await`, one that a function written beside it assigns (a builder keeping its context, which may run during any `await`), and, in a file under `test/`, code outside a class (a test's body awaits its tester and knows what is mounted). A context kept in a field and a guard of the code's own are not followed, and a state's `mounted` counts as a check of any context. | *Add 'if (!mounted) return;'* (`if (!name.mounted) return;` for a variable) before the statement, where the function returns nothing. |
| `dispose_controllers` | warning | A field of a `State` that the state creates — in its initializer, also with a cascade, or by assigning it a new object anywhere in the class, as `initState` does — of a type with a `dispose()` method (the controllers, `FocusNode`, any `ChangeNotifier`), and that nothing in the class disposes (`x.dispose()`, `x?.dispose()`, `x..dispose()`, `this.x.dispose()`). A loop disposes the fields it goes over when it calls `dispose()` on its variable: a `for`-in or a `forEach` whose function does, over a list or set written in place that names them (`for (final n in [a, b]) n.dispose()`, `[a, b].forEach((n) => n.dispose())`, spreads in it aside), or over a collection field they are in, by its initializer (`late final _all = [a, b]`) or by `add` or `addAll` of a list written in place anywhere in the class. Still reported: a field disposed through a collection the rule can't see the elements of, such as the list a method or getter returns (`for (final n in _nodes()) n.dispose()`). | *Dispose of '_x' in 'dispose'*: `_x.dispose();` (`_x?.dispose();` for a nullable field) on a line of its own before the `super.dispose();` of the state's `dispose`, or, where it has none, an override that does so and calls `super.dispose()`, before `build` (after the last member where there is no `build`). Not offered where `dispose` has no `super.dispose();` statement in its block, or declares a variable of the field's name. |
| `key_names` | warning | A key name, a string written in place, that a terminal without the kitty keyboard protocol never sends as that key, so that a binding of it fires only on the protocol's terminals (a warning): `ctrl+i` arrives as `tab`, `ctrl+m` and `ctrl+j` as `enter`, `ctrl+[` as `escape`, `ctrl+h` as `ctrl+backspace`, `ctrl+@` and `ctrl+2` as `ctrl+space`, Ctrl, Shift and a letter as Ctrl and the letter, Ctrl or Shift with `enter` or `escape` as the key alone, Super not at all, and keys xterm has no bytes of their own for (`ctrl+1`, `ctrl+tab`, `alt+shift+1`) as no key of its own; the message says which. And a name that fails the build (an error): one twk's parser rejects, with its message (`'esc'`, `'cmd+s'`, `'ctlr+s'`, a sequence where one key is meant), two names of one map's entries that are the same keys (`'A'` and `'shift+a'`), a hint for keys the bindings beside it, a map written in place without `if`, `for` or spreads, do not bind. Read where twk reads names: the keys of `KeyBindings`' and `Shortcuts`' maps and of their `hints`, `LeaderKey`'s leader, `SelectionArea`'s `copyKey` and `clearKey`, `KeyCombo.parse`, `KeyCombo.parseSequence` (`leader` only with a `leader:`), and twk_term's `TerminalView.ignoredKeys`. In a file under `test/` only what fails the build is reported (a test says which terminal it is on). The parser is twk's `KeyCombo`'s ported, as the plugin does not import twk (a twk that does not compile while it is edited would take every rule down, in every package); `test/key_names_test.dart` holds the port to twk itself: the names to `KeyCode`'s, every name and message to `KeyCombo.parseSequence`'s, and what arrives to the bytes twk_test sends for an xterm, read by twk_core's input parser. Blind spots: names built at run time or kept in variables, maps that are not written in place, and APIs not on the list (twk_test's `sendKeys`). | None: which key to take instead is the author's call. |
| `missing_key_in_children` | lint | A `StatefulWidget` made for each item of a list without a key, when its constructor takes one: the body of a `for` element (through `if` elements, conditional expressions and nested `for`s), or what the function of a spread `items.map(...)` (or `.map(...).toList()`) returns. Without a key, the states stay where they were when an item is added, removed or moved. | *Add 'key: ValueKey(item)'*, `item` the variable of the loop, before the widget's first named argument (after its last argument where it has no named one), its `const` dropped. Only where that variable is a key of its item: the one variable of a `for`-in element of the list (not of a loop inside another) or the one parameter of the function a spread `.map` calls, of type `String`, `int` or an enum; an object is equal to itself alone, and which of its fields names it (`item.id`) is the author's call. Also offered for every such widget of the file at once. |
| `untyped_table` | lint | A `Table` without its type argument whose row type is inferred as `dynamic`, `Object`, `Never` or a nullable type. A list of `TableColumn`s written in place is inferred apart from the rows, its closures' rows `Object?`, so `Table(rows: todos, columns: [TableColumn(cell: (todo) => ...)])` is a table of `Object?`: the columns read their rows untyped. | *Write the row type 'Todo'*: the element type of the `rows:` list as the type argument, `Table<Todo>(...)`, an import added where its library is not imported. Only where that type is not one the rule reports and can be named here (a class or the like, its type arguments too, or a type parameter in scope; not a private type of another library, a function type or a record). Also offered for every table of the file at once. |
| `prefer_key_bindings` | lint | An `InputListener` whose `onEvent` only matches keys, which `KeyBindings` does nearer the focus while listing its keys and their hints: it tests for no event but `KeyEvent` (with `is`, an object pattern or a typed variable pattern), compares a key's `code` or `char` with a constant (`==`, `!=`, a field of an object pattern, a `switch`), reads no `KeyKind` but `press`, and passes the event to nothing. The handler is a function written in place, or a function or method of the same file named there. | *Convert to KeyBindings*, the same keys and handlers, `child` and `key` kept: `KeyBindings({'q': quit, 'enter': () => send()}, child: app)`, on lines of their own where it does not fit in 80 columns. For one shape only: an `onEvent` written in place whose block is a run of `if`s without `else`, each `if (event is KeyEvent && event.char == 'q') { ...; return true; }` (`event.code == KeyCode.enter`, several tests joined by `\|\|`, the `is` test also once before them as `if (event is! KeyEvent) return false;`), then `return false;`; a handler that is a call without arguments becomes its tear-off, one other expression `() => ...`, more statements `() { ... }`. Not offered where a handler reads the event or returns, where several keys share a handler that is not a tear-off, where two `if`s test one key, or where the listener takes more than `onEvent`, `child` and `key`. `KeyBindings` takes a key without modifiers, as its name says, where the comparison took the character or code with any: Ctrl and `q` no longer matches `'q'`. |
| `wall_time_in_tests` | lint | In a file under the package's `test/`: a wait on the wall clock — a `Future.delayed` of a duration that is not the constant zero, a `sleep`, a `Timer` of such a duration, a `Timer.periodic` or a `Stream.periodic` (of `dart:async` and `dart:io`). A test that waits a fixed time for a frame, a timer or another process guesses how long is long enough, and on a loaded machine the guess is wrong: the tester's `pump` or a `FakeClock`'s `elapse` moves a fake clock instead, `elapseUntil` waits for a future on that clock, and twk_test's `waitFor` and `waitUntil` await, with a bound, what a real process, socket or file does. Not reported: a timer made in a function written in place as the argument of twk_test's `FakeClock.run` or `TwkTester.act`, and app code (a member of a `State`, a function written in place in a widget's arguments), whose timers are on the clock the app runs on; nor a program the tests start (a library with a `main` in a file not named `_test.dart`). A `sleep` is reported in app code too. Where real time is the point (a pace measured, an absence checked), `// ignore: twk_lints/wall_time_in_tests` with the reason above it. | *Use 'clock.elapse'*: `await Future<void>.delayed(d)` becomes `await clock.elapse(d)`, where exactly one variable or parameter of twk_test's `FakeClock` is named in scope there (a local declared before it in a block around it, a parameter of a function around it, a top-level variable). Not offered for a `Future.delayed` that is not awaited or has a computation, for a `TwkTester` alone (its `pump`, which draws a frame, or its clock: the author's call), nor for a `sleep`, a `Timer` or a periodic, which `elapse` does not stand for one to one. Also offered for every such wait of the file at once. |
| `unnamed_control` | lint | A twk control written with nothing a screen reader can call it by, so that the screen-reader mode reads its role alone (`textbox`, `slider 0.50`) or a glyph (`button ×`): a `TextField`, `TextArea` or `TextFormField` with neither `semanticsLabel` nor `placeholder`; a `Slider` with no `semanticsLabel`; a `Checkbox` or `Switch` with neither `label` nor `semanticsLabel`; a `Button` whose label, a string written in place, has no letter or digit. An argument `null` or `''` counts as none. Not reported in a file under the package's `test/`. Blind spots: a label from a variable or any other expression counts as a name, unread (`Button(label)`, `semanticsLabel: name`); a control of the app's own built from `Focus` or `Pressable` without a `Semantics` is not seen. A `Text` beside a field, or a `Semantics(label:)` around it, does not name it (the field is a node of its own), so it is reported all the same. | *Add 'semanticsLabel'*, `semanticsLabel: ''` before the first argument (or in place of the `null` or `''` there), the cursor between the quotes; not for a `Button`, which takes none: its label is what is read. |

A fix is offered by the editor on its diagnostic, as the analyzer's
are (an LSP client's code action of kind `quickfix.twk.fix.<id>`); one
that is also offered for the whole file applies itself to each of the
rule's diagnostics there in one edit. `dart fix` applies none of them:
checked from a scratch app on the SDK of this repository (3.13.7), with
diagnostics of the five rules that have a fix, `dart fix --dry-run` and
`dart fix --apply` answered "Nothing to fix!" and changed no file, the
fixes marked for use in bulk (`CorrectionApplicability.acrossFiles`, and
`automatically` tried too); the plugin server of `analysis_server_plugin`
0.3.24 answers `edit.getFixes`, the fixes of one place, and nothing that
fixes a project. An LSP client of `dart language-server` in that app got
each fix as a code action, its edit as its tests have it, and the
fix-all-in-file ones too. Fixing a file, the server runs a fix on every
diagnostic of the file, the other rules' too, so each fix offered so
checks that the diagnostic is its rule's.

## Assists

Offered by the editor at the cursor (VS Code's and IntelliJ's light bulb,
any LSP client's code actions, as kind `refactor.twk.assist.<id>`); the
command line has no way to apply them.

| assist | at | does |
|--------|----|------|
| Wrap with widget... | a widget: the name of its constructor, a call returning one, a variable | `widget(child: ...)`, `widget` selected to be named; on lines of its own where the widget takes more than one |
| Wrap with Padding | the same | `Padding(padding: const EdgeInsets.all(1), child: ...)` |
| Wrap with Box | the same | `Box(border: const Border.all(), child: ...)` |
| Wrap with Center | the same | `Center(child: ...)` |
| Wrap with SizedBox | the same | `SizedBox(width: 1, height: 1, child: ...)`, the width and the height linked for the editor to step through |
| Wrap with Row, Wrap with Column | the same, not of a nullable type; or a selection in a list of widgets | `Row(children: [...])` (`Column`), on lines of its own where what it takes does; of a selection, the elements it reaches, as they are written (comments between them, `if`, `for` and spread elements too) |
| Wrap with Expanded, Wrap with Flexible | a widget in the `children:` of a `Row`, `Column` or `Flex` written in place, directly or in an `if` or `for` element there | `Expanded(child: ...)` (`Flexible`). Not offered elsewhere, for a widget of a nullable type, or for a `Flexible`, `Expanded` or `Spacer`, which a flexible may not hold. |
| Wrap with Builder | a widget, not of a nullable type, outside a constant | `Builder(builder: (context) => ...)`, a new context for the widget (`context2` where it reads a `context` from around it that is not a `BuildContext`) |
| Wrap with ValueListenableBuilder | the same | `ValueListenableBuilder(valueListenable: valueListenable, builder: (context, value, child) => ...)`, `valueListenable` selected to be named; a parameter named as something the widget reads from around it takes a number (`child2`) |
| Convert to StatefulWidget | the head of a class that extends `StatelessWidget` | The class extends `StatefulWidget`, keeps its fields and constructors, and has `createState` where `build` was; its other instance members move to `_NameState` after it (`final` where the widget is, with the widget's type parameters), where they read the widget's members through `widget` (`this` becoming `widget`) and its static members qualified by its name. |
| Convert to StatelessWidget | the head of a class that extends `StatefulWidget` | The reverse: the class extends `StatelessWidget`, the members of its `State` take the place of `createState`, reading the widget's members without `widget.` (`this.x` where a local name is `x`, `widget` alone becoming `this`) and its static members without its name, and the `State` is deleted. Offered only where the `State` keeps nothing a widget cannot: it is the private class of the same file that `createState` creates (`_NameState()`, no arguments), named nowhere else; it extends twk's `State` directly, with the widget's type parameters, mixes nothing in (no `TickerProvider` and the like) and implements nothing; it has no constructor and no field that is not `final` or is `late` (no instance field at all where the widget has a `const` constructor); it overrides nothing of `State` but `build` (no `initState`, `dispose`, `didUpdateWidget`, `didChangeDependencies`, `deactivate`, `activate`); it reads nothing of `State` but `widget` (no `setState`, `mounted`, or `context` outside `build`'s parameter), no `super` and `this` only before its own members; and no name moved in is one the widget has (its members, `key` ...) or reads from outside, nor the widget's names hide one the `State` reads. |
| Extract widget | a widget that is not just a name | Moves the widget into the `build` of a new `StatelessWidget` after the declaration it is in, `NewWidget` (or `NewWidget2`, ... where the name is taken), selected where it is called, declared and constructed, to be typed over in all three at once, and puts `NewWidget(...)` in its place. What the widget reads from around it becomes a required field: a local variable or parameter, a field or getter of the class, a method torn off, each named as it is without its leading `_`s; a `BuildContext`, and a `State`'s `context`, become the new `build`'s `context`; static members are qualified by the class's name. Not offered for a widget that calls a method of the class, assigns to what is around it, uses `this` or `super`, awaits, or names a type parameter from around it. |
| Remove this widget | a widget created in place (the name of its constructor) | The widget is replaced with its `child:`; in a list of widgets, with the elements of its `children:` list, comments on the lines above them kept (an empty one takes the widget and its comma away); where one widget is taken, with a `children:` list of one widget. Offered only where what is left is of a type the place takes: a nullable `child` not where a widget is required, several children not where one is. |
| Swap with child | a widget created in place whose `child:` is one too, which has a `child:` of its own | The two change places, each keeping its other arguments (the child's `const` dropped where the parent is not constant), lines indented by their new depth; the child's child stays the innermost. Offered only where each lands in a place of a type it is. |
| Swap with parent | a widget created in place that is the `child:` of another, and has a `child:` of its own | The same change, from the child. |
| Move widget up, Move widget down | a widget, an element of a list of widgets written in place | It changes places with the element before (after) it, each with the comments on the lines above it; a comment after the end of a line stays on that line. Not offered for the first (last) element, for a widget in an `if` or `for` element, or past an `if`, `for` or spread element: which of its widgets would move is not the cursor's to say. |

The names come from `package:twk/twk.dart`, with its prefix where the file
imports it with one, and an import added where it imports none.

## What works where

`dart analyze` runs the plugin and reports its warnings and the lints
turned on, with the analyzer's own diagnostics; warnings fail it as the
analyzer's do. In an editor the analysis server reports the same as you
type and offers the assists. Checked from a scratch app on the SDK of
this repository (3.13.5): `dart analyze` reported each rule, and an LSP
client of `dart language-server` got the assists as code actions, and
the edits of the tree edits (remove, swap, move), of the wraps and of
Convert to StatelessWidget as their tests have them.
What an assist leaves to be named (Wrap with widget...'s `widget`,
SizedBox's sizes, ValueListenableBuilder's `valueListenable`, Extract
widget's `NewWidget`) the server sends as a snippet, which VS Code (with
Dart-Code 3.144, Dart 3.13.7) selects to be typed over, only when the
change is one edit of one file: with more it sends a plain edit, and the
name stays to be renamed by hand. Extract widget therefore rewrites the
text from the widget to the end of its declaration in one replacement;
where twk has to be imported for it, the import is a second edit and the
snippet is lost.
This repository enables the plugin, with `wall_time_in_tests`, in the
`analysis_options.yaml` of every package and tool (and `unnamed_control`
in twk's and the gallery's), so that the analyze
steps of its handover enforce it; each package's own `dart analyze` is
what counts there, as an analyze from a directory above several
packages left out some of the plugin's findings in the packages below
(Dart 3.13.5).
custom_lint, the other way to write such a plugin, is not used: its
last release (0.8.1, September 2025) takes analyzer 8, which knows the
language of a year ago, and runs on the old plugin system.

## Tests

`test/support.dart` holds stubs of the parts of twk and twk_core the
fixtures use, as packages the fixtures import, and the test bases: a
rule's on `analyzer_testing`'s `AnalysisRuleTest`, which analyzes a
fixture with the rule and compares the diagnostics (`lintAt` finds where
one is expected by its text), and an assist's on its
`AssistProcessorTest`, which applies the assist at the `^` of a fixture
and compares the result. `test/rules/<rule>_test.dart` and
`test/assists/<assist>_test.dart` are run by `test_reflective_loader`,
whose test methods are named `test_*`; a rule's test checks its fix
with `fixed`, which applies it to one of the rule's diagnostics of the
fixture (the analyzer's own, such as an unused variable, not counted).
`test/key_names_test.dart` holds `key_names`' port of twk's key names to
twk, twk_core and twk_test, its dev dependencies, which do not reach the
plugin. `test/plugin_test.dart` checks what the plugin registers: its warnings,
its lints, its fixes and its assists.

The checks, from this directory:

```bash
dart pub get
dart analyze
dart test
dart format --output=none --set-exit-if-changed lib test
```

## License

MIT, copyright 2026 Andrii Ivanov: [LICENSE](LICENSE).
