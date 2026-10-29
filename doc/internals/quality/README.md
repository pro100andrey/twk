# Docs and tests: the standard

What a public declaration's doc comment says and how a package's tests
cover it, in the core and in every package; and the reports that say
where each package stands against it.

- [The reports](#the-reports): what is missing, per package, and how to
  read them again after a change.
- [Doc comments](#doc-comments): the rules, each with an example, and a
  whole widget written to them.
- [Examples in doc comments](#examples-in-doc-comments): how the
  ` ```dart ` blocks are analyzed, and what an example can assume.
- [Tests](#tests): how a coverage gap is filled.

## Where it stands

From the first reports (e347734) to the last (36972df), after the docs and
tests work package by package. `public_member_api_docs` is now on in the
core and in every library package ([below](#the-reports)), so the first
column stays at 0. twk_hooks and twk_provider have since become libraries
of twk, `package:twk/hooks.dart` and `package:twk/provider.dart`, and
their rows are what they were as packages; their lines are counted in
twk's reports from then on. So with twk_image, now
`package:twk_rich/image.dart`: its row is the package's, its lines are
counted in twk_rich's reports from then on.

| package | undocumented | covered | public gaps | examples |
| --- | ---: | ---: | ---: | ---: |
| twk_core | 557 → 0 | 94.9 → 99.1 % | 171 → 15 | 0 → 60 |
| twk | 748 → 0 | 94.0 → 96.7 % | 228 → 5 | 4 → 261 |
| twk_bloc | 29 → 0 | 95.0 → 100.0 % | 1 → 0 | 0 → 12 |
| twk_dev | 87 → 0 | 64.6 → 97.5 % | 47 → 5 | 1 → 6 |
| twk_hooks (since `package:twk/hooks.dart`) | 7 → 0 | 92.6 → 95.3 % | 4 → 0 | 0 → 24 |
| twk_image (since `package:twk_rich/image.dart`) | 38 → 0 | 93.7 → 99.9 % | 26 → 0 | 0 → 7 |
| twk_lints | 21 → 0 | 92.8 → 94.4 % | 4 → 0 | 0 → 17 |
| twk_provider (since `package:twk/provider.dart`) | 35 → 0 | 94.6 → 97.3 % | 3 → 0 | 0 → 22 |
| twk_rich | 120 → 0 | 95.4 → 97.9 % | 64 → 0 | 1 → 16 |
| twk_riverpod | 9 → 0 | 92.7 → 100.0 % | 4 → 0 | 0 → 6 |
| twk_term | 108 → 0 | 93.0 → 94.3 % | 19 → 3 | 0 → 6 |
| twk_test | 48 → 0 | 84.4 → 90.7 % | 22 → 1 | 0 → 13 |
| twk_web | 11 → 0 | 100.0 → 100.0 % | 5 → 0 | 0 → 3 |
| **library packages** | **1818 → 0** | | **598 → 29** | **6 → 453** |
| gallery (an app) | 149 → 149 | 91.6 → 91.6 % | 43 → 43 | 1 → 1 |
| the four templates | 12 → 12 | 98.3–100 % | 0 → 0 | 0 → 0 |

Examples are the ` ```dart ` blocks of `///` comments in `lib/`, each of
them analyzed by `doc-snippets`. A public gap counted at the start may
have been a constant, which the coverage tool no longer counts (three in
twk_rich, one in twk_image). twk_web's five were the browser's
(`runWebApp` and the xterm.js bindings, which no VM test loads), which
the report now lists as browser-only rather than as gaps; many others ran
only in a test's child process or pseudo-terminal, which the report now
measures (below). What is left runs only on another platform, in a
process that ends by `exit()` or a signal, or in a grandchild (the apps
`twk run` and `twk record` start); each is in its package's report.

The model is Flutter's framework documentation (its
[style guide](https://github.com/flutter/flutter/blob/main/docs/contributing/Style-guide-for-Flutter-repo.md#documentation-dartdocs-javadocs-etc)):
every public member documented, a summary sentence that stands alone, then
what the reader needs to use it, and a sample for every widget. This
repository's voice stays its own: short sentences that say what a thing
is and does, with `[references]` instead of restating them.

## The reports

Three tools, run through xtask (CONTRIBUTING.md). Each reads every package of the
repository: each package under `packages/`, the core (`twk_core`) among
them, and the templates under `packages/twk_dev/templates/`.

| task | what it does | where it writes | in a gate |
| --- | --- | --- | --- |
| `doc-snippets` | analyzes every ` ```dart ` block of every `///` comment in `lib/`, in its package | stdout: `file:line:column: severity code: message` | `handover`, `ci` |
| `undocumented` | the public members without a doc comment (the analyzer's `public_member_api_docs`) | [`undocumented/<package>.md`](undocumented/README.md) | no, on demand; the lint itself is on in `analyze` (below) |
| `coverage` | `dart test --coverage` in each package; the lines of `lib/` no test runs, and the public declarations they are in | [`coverage/<package>.md`](coverage/README.md) | no, on demand (minutes) |

```sh
dart run tool/xtask.dart doc-snippets
dart run tool/xtask.dart undocumented              # every package
dart run tool/xtask.dart undocumented -- twk       # twk's report only
dart run tool/xtask.dart coverage -- twk twk_rich  # those two only
```

Each report starts with the commit it was made at (`+` after it: with
changes to the package's files not committed yet) and its count; the
`README.md` of each directory has every package's count in one table.

- **undocumented/&lt;package&gt;.md** lists each member as
  `` `file:line` kind `Type.member` ``, grouped by file, the file with the
  most first. A setter whose getter is documented, and a member that
  overrides one (`@override`), need no comment of their own, and are not
  listed. A public name in `lib/src/` is listed whether or not a library
  exports it: it is public to the analyzer, and documented all the same.
- **coverage/&lt;package&gt;.md** first lists the public declarations
  (members, constructors, top-level functions and variables) with lines no
  test runs: `` `line` kind `Type.member`: 3 of 8 lines (12-14) ``, under
  their file, the file with the most such lines first. Then the files no
  test loads at all, with their public declarations that have code. Then
  every file with a line no test runs, by how many. A line counts when the
  VM compiled code for it; a declaration without a body (a type, an
  abstract or external member, a field without an initializer, a
  constant, whose value the compiler makes) has none and is never
  listed. A file that imports `dart:js_interop`, `dart:html` or
  `package:web`, which no test on the VM can load, is listed under
  *Browser-only files* instead, not as a gap: the `browser-test` task
  (in `ci`) runs twk_web's, unmeasured.

  The Dart processes the tests start (`Platform.resolvedExecutable`: a
  script in a pseudo-terminal, `dart run` of an executable, a fixture
  under a low descriptor limit) are measured too. The test runner is
  told its `dart` is that of a copy of the SDK made of links, whose
  `bin/dart` is a script starting the real one with its VM service on,
  silent, and its isolates paused on exit; the tool connects to each
  such process, collects its coverage of the package when it pauses,
  lets it end, and merges it with the runner's. A process that ends by
  `exit()` or a signal does not pause and is not measured, one started
  with VM service flags of its own runs as it would, and one still
  running ten seconds after the tests is let go unmeasured; the tool
  says how many it measured (`tool/coverage/lib/children.dart`). Linux
  only: elsewhere only the test process is measured.

  The tests run four files at once, as a dozen at once can leave
  `dart test --coverage` spinning for good (`coverageConcurrency` in
  `tool/coverage` says why); a run that writes no file's coverage for five
  minutes is stopped and the files not measured yet run again.

When a package's work is done, its reports are made again and committed
with the work: `dart run tool/xtask.dart undocumented -- <package>` and
`coverage -- <package>`. A package is done when its `undocumented` report
says every public member has a comment, `doc-snippets` passes, and its
coverage report lists no public declaration whose lines a test of its
behaviour could reach.

The analyzer's `public_member_api_docs` is on in the `analysis_options.yaml`
of the core and of every library package, so `dart analyze --fatal-infos`
in `handover` fails on a public member without a comment. It is off where
the public names are no API: in the gallery, an app; in the templates under
`packages/twk_dev/templates/`, the apps `twk create` writes, which are
their authors' to document; and in the tools under `tool/`, packages of
their own with options of their own, used by this repository only.

## Doc comments

### 1. Every public declaration has one

A class, mixin, enum and each of its values, extension, typedef, top-level
function and variable, and every public member: constructors, fields,
getters, methods, operators. A setter is documented on its getter. An
override says nothing unless it does more than the member it overrides
says: then it says what.

```dart
// Bad: a constructor and a field the reader has to guess at.
final class Padding extends SingleChildRenderObjectWidget {
  const Padding({required this.padding, super.key, super.child});

  final EdgeInsets padding;
}

// Good
/// Insets [child] by [padding]: as big as the child and the padding.
final class Padding extends SingleChildRenderObjectWidget {
  /// Insets [child] by [padding].
  const Padding({required this.padding, super.key, super.child});

  /// The empty cells on each side of the child.
  final EdgeInsets padding;
}
```

### 2. The first sentence is a summary that stands alone

dartdoc shows the first sentence alone, in the package's index and in the
IDE's completion list, so it has to make sense there: it says what the
declaration is or does, not how; it does not start with "This" or repeat
the name. A type, field or variable gets a noun phrase; a function, method
or constructor a verb in the third person. One sentence, then a blank
line.

```dart
// Bad: says nothing the name does not, and leans on the next sentence.
/// The ScrollController class.
///
/// It controls scrolling.

// Bad: the summary runs on to the details.
/// Shows [builder]'s widget for whether the focus is in this subtree, and
/// takes no focus itself, so that Tab does not stop at it, nor a press …

// Good
/// Shows what [builder] returns for whether the focus is in this widget's
/// subtree, built again when the focus enters or leaves it.
///
/// It takes no focus itself: Tab does not stop at it, nor does a press
/// focus it.
```

### 3. Then what it does, its parameters and defaults, its neighbours

After the summary, in this order where it applies:

- **What it does**, in the cases a caller meets: what it shows, what it
  returns, when it rebuilds, what it does with too little room, what an
  empty input gives.
- **Its parameters, as `[name]` references**, each with its default and
  what null means: "[maxLines] lines at most, the rest cut off with `…`;
  null, the default, for as many as the text has". Not a list of
  `@param` tags; a sentence per parameter that needs one, in the class
  comment for a widget's fields or on the field itself.
- **How it works with its neighbours**: the widget it has to be under
  (`Overlay`, `Navigator`), the controller it reads, what its parent
  decides for it, what it hands its builder.
- **What it throws, or asserts**, and when.
- **`See also:`** where another declaration is the one the reader may have
  wanted, a list of references, each with a short reason:

```dart
/// See also:
///
///  * [ListenableBuilder], the same for any [Listenable].
///  * [ValueListenableBuilder], which hands [builder] the value too.
```

A reference to a declaration is `[Name]` or `[Name.member]`, which dartdoc
links and the analyzer checks; code that is not a declaration of this
package (a CLI flag, an escape sequence, a file name) is in backticks.

### 4. A ` ```dart ` example for every widget and every entry point

Every widget, and every main entry point of a package (its controllers,
`runApp`, the tester `testTwk`), shows itself in use in a ` ```dart `
block: small (under twenty lines), complete (it compiles: the
`doc-snippets` check of the handover analyzes it), and the common case, not
the clever one. The text before it says what it shows.

````dart
/// A box around [child]: [style] fills it, [border] lines its sides,
/// [titles] sit on its top and bottom edges, and [padding] is between the
/// border and the child.
///
/// It is as big as the child and what surrounds it, and as wide as its
/// titles, as far as the constraints allow; without a child, as big as
/// they allow. A title too long for its edge is cut off with "…".
///
/// A rounded panel with a title, one cell between its border and the text:
///
/// ```dart
/// Box(
///   border: const Border.all(type: .rounded),
///   titles: const [BorderTitle(' Status ')],
///   padding: const .all(1),
///   child: Text('All systems go'),
/// )
/// ```
///
/// See also:
///
///  * [Padding], for the space without the border.
///  * [Divider], a line across without the box.
final class Box extends SingleChildRenderObjectWidget {
  /// A box around [child]; with every parameter left out, an empty one
  /// that fills nothing.
  const Box({
    super.key,
    this.style,
    this.border,
    this.titles = const [],
    this.padding = EdgeInsets.zero,
    super.child,
  });

  /// What the box is filled with: its background, and the colors its
  /// border, titles and child take where theirs are unset; null leaves
  /// what is under the box.
  final Style? style;
  …
}
````

An entry point's example is the shortest whole use of it:

````dart
/// Runs [app] in the terminal until it quits, and restores the terminal.
///
/// ```dart
/// Future<void> main() => runApp(const Counter());
/// ```
````

````dart
/// Runs [body] as a test of package:test named [description], with a
/// [TwkTester] for an app it starts with [TwkTester.pumpWidget].
///
/// ```dart
/// testTwk('Up counts', (t) async {
///   await t.pumpWidget(const Counter());
///   await t.press('up');
///   expect(t.lines.join('\n'), contains('Count: 1'));
/// });
/// ```
````

### 5. Only what is true now

A doc comment describes the code as it is. It says nothing of how it came
to be: no "now", "no longer", "used to", "was fixed", "previously", "new",
"changed to"; no task names or aliases, commit hashes, review rounds,
agent names, "the review found", "after the refactor". What was wrong
before and why it changed belong in the commit message and the tracker.

```dart
// Bad
/// Now also scrolls horizontally (was vertical only before the
/// scroll-axis task); fixed in round 2 after the review found the
/// off-by-one.

// Good
/// Scrolls along [scrollDirection], vertically by default.
```

### 6. No TODOs

A doc comment is what a user reads; an open question about the code is not
for them. A known limit is described as a limit ("Right-to-left text is
shown in the order it is stored"); work still to do is a task in the
tracker.

### 7. Consistent with the package's README

The README and the doc comments name things the same way, and the
README's examples use the API as the doc comments describe it. A change
to one that the other contradicts changes both.

### Libraries

A library (each file in `lib/`, with `library;`) starts with a doc comment
saying what it holds, with references to its main declarations, as the
files of this repository do:

```dart
/// Boxes drawn around a child and lines across: [Box], with a background,
/// a [Border] with [BorderTitle]s on its edges and padding; [Divider] and
/// [VerticalDivider].
library;
```

## Examples in doc comments

`doc-snippets` (`tool/doc_snippets/`) writes each ` ```dart ` block of a
`///` comment under `lib/` to a Dart file of its own, which imports every
public library of the block's package (the files directly in its `lib/`),
and analyzes them all in one run, resolved as the package is. Any error,
warning or info fails it, at the line and column of the doc comment; the
analyzer's strict modes are on, and these are not reported: unused local
variables, elements, fields, imports and shown names, and dead code.

- **The shape of a block** is found by parsing it: declarations or a
  whole program (with `main`) stay at the top level; statements become
  the body of an `async` function, so `await` works; anything else is
  taken as one expression (a widget, say: `Box(child: Text('hi'))`, with
  no semicolon).
- **What an example can assume**: names it uses and does not declare (a
  `context`, a `controller`, the `theme`) are declared once per file in a
  plain `//` comment at the top level, after the imports, whose first line
  is `// Examples can assume:`. Each line after it, to the first line that
  is not a `//` comment, is Dart: an `import` is added to every example's
  imports, anything else is declared at the top level beside every example
  of the file. `late` variables keep them short:

  ```dart
  // Examples can assume:
  // import 'package:test/test.dart';
  // late BuildContext context;
  // late AnimationController controller;
  // void askToDiscard(BuildContext context) {}
  ```

- **A block that is not to be analyzed** (an excerpt that cannot stand
  alone, a sketch of an API that does not exist, an error shown on
  purpose) is tagged ` ```dart-nocheck `, or its first line is
  `// not analyzed`. Use it rarely: an example that does not compile is
  one a reader cannot copy.
- **Code elided** inside an example is a comment, `// ...`, so the
  example still parses.
- **Other languages** are tagged as what they are (` ```text `,
  ` ```sh `, ` ```yaml `) and are not analyzed.

`dart run tool/doc_snippets/bin/doc_snippets.dart --keep [PACKAGE...]`
keeps the generated files and names their directory, to see what an
example was analyzed as.

## Tests

A coverage gap is filled with a test of behaviour: what a user of the API
sees, through the public API (`testTwk`, `t.pumpWidget`, `t.press`,
`t.lines`), not a call that runs a line to make it count.

- **Named for what it checks**, as a sentence about the behaviour: "a
  title too long for its edge is cut off with an ellipsis", not "Box
  test 3" or "covers _layoutTitles".
- **One behaviour per test**, its expectation on what the behaviour
  decides (the screen's lines, the value returned, the callback called),
  so that it fails when the behaviour breaks: break the code it covers,
  see the test fail, put it back.
- **No line padding**: a test that calls a getter or builds a widget
  without checking what came of it covers lines and tests nothing.
- **A line no test can reach** is a finding, not a gap to fill: code
  that cannot run is removed; a defensive branch that should not run is
  left uncovered, and is not tested by reaching into private state.
- **In the package's `test/`**, beside the tests of its neighbours, with
  the package's own helpers (`twk_test` for widgets).

### Time in tests

No test waits on the wall clock: a fixed wait guesses how long is long
enough, and on a loaded machine the guess is wrong.

- **An app or a timer runs on a fake clock that the test moves**:
  twk_test's tester (`testTwk`, `t.pump(duration)`), or, where the
  tester does not fit, a `FakeClock` handed to the app explicitly
  (`AppBinding(term, clock: clock.stopwatch).run(app)` in
  `clock.run`), moved with `clock.elapse` and `clock.elapseUntil(future)`.
- **What real time brings is awaited**: the output line, the exit, the
  file of a real process, pty, socket or file system, through twk_test's
  `waitFor(event, what)` or `waitUntil(condition, what)`, whose bound
  fails with a message instead of hanging. Never a sleep, and no timeout
  raised or retry added to make a test pass.
- **Enforced** by twk_lints' `wall_time_in_tests` (README of
  `packages/twk_lints`), enabled in every package's and tool's
  `analysis_options.yaml`, so the analyze steps of handover fail on a
  `Future.delayed` of a non-zero duration, a `sleep`, a `Timer`, a
  `Timer.periodic` or a `Stream.periodic` in a file under `test/`
  (timers made in `FakeClock.run`, `TwkTester.act` or app code are on a
  fake clock and not reported; nor is a program the tests start).
- **The only exceptions** are `// ignore: twk_lints/wall_time_in_tests`,
  with the reason on the comment above it: where real time is what is
  measured or an absence is checked (nothing happens for half a second),
  in the tests of twk_test's wait helpers, and where a timer is on the
  fake clock in a way the rule cannot see.

## Renames and moves

A public member of a released package renamed or moved comes, in the
same commit, with an entry in its package's `lib/fix_data.yaml` (data-driven fixes,
https://dart.dev/go/data-driven-fixes, which `dart fix --apply` and the
IDE's quick fixes read) and a case in the package's `test_fixes/`: a
`.dart` file that uses the old API, and its `.dart.expect`, the file as
dart fix leaves it, checked by `dart fix --compare-to-golden
test_fixes` in the package. The package's `analysis_options.yaml`
excludes `test_fixes/**`, whose inputs are errors on purpose;
`test_fixes/analysis_options.yaml` makes the directory a context of its
own, where dart fix still sees them. An entry's `uris` are the public
libraries that export the element now.

Nothing has been released yet, so there is no fix data: a change before
a package's first release needs none, nobody having code against it.
The first entry brings back to xtask.yaml, with it, the set of the
packages that have a `test_fixes/` (`packages/*/test_fixes/analysis_options.yaml`)
and a `pkg-fix-data` task over it in `handover` and `ci` (the `ci`
benchmark's `needs` too), running that compare.

An entry can say: a class, function, field, getter or method renamed
(`rename`); a named parameter renamed (`renameParameter`); a parameter
added or removed (`addParameter`, `removeParameter`); a constructor,
function or static member replaced by another, also in another library
(`replacedBy` with `newElement`); a deprecated library replaced by
another (`library:` with `replacedBy` and `newLibrary`). It cannot say
three things:

- an import of a package the app no longer depends on (a package
  renamed, or merged into another): the import resolves to nothing, and
  a fix runs only on a diagnostic of a library that resolves (a
  `library:` transform needs the old library present and deprecated);
- the name in a `show` or `hide` combinator;
- a name in a type test (`o is OldName`).

A case pins the last two as dart fix leaves them, so that an SDK that
starts fixing them fails the compare; the release notes say what an app
changes by hand.
