# Lint candidates: which twk-specific rules hold up

Five rules were proposed for `packages/twk_lints`. Each one was checked
against the twk code it concerns, and a prototype of it was run over the
code apps are written in. This file gives a verdict for each, and for
three more rules that came up while reading. Nothing here is built. The
person decides which become tasks.

## How it was measured

The prototypes were one analyzer visitor (analyzer 14.5.0, the plugin's
version), in scratch and not committed. It resolved two sets of code:

- **apps**: `packages/gallery` (76 files, its tests included), every
  `packages/*/example` (21) and `packages/twk_dev/templates/*` (12), 109
  files in all;
- **twk**: the `lib/` of twk, twk_rich, twk_term, twk_dev,
  twk_bloc, twk_riverpod and twk_web, 313 files. This is widget code
  written by the people who know twk best, a second check on noise.

Every hit was read by hand. A *false alarm* is a hit where the code is
right as written.

## Summary

| # | candidate | what it would report | blind spots | false alarms measured | fix | verdict |
|---|---|---|---|---|---|---|
| 1 | ambiguous-width glyphs reaching a Text | a string literal holding an East Asian Ambiguous character that reaches a twk widget or `Span` | glyphs from variables and other files; the width the terminal really has | apps: 61 literals reach a widget and all 61 are fine, because twk measures them. The narrow `'─' * n` form has 3 hits outside tests, 1 of them a minor real defect | none general: `Divider` for lines, `canvas.segmenter` in a painter | **don't**; test at `ambiguousWidth: 2` instead |
| 2 | hard-coded colours in `build` | `Color.rgb`, `Color.indexed`, `Color.<ansi name>` written in a `build` | builds written as closures in fields (the gallery's style), helpers called from `build` | apps: 2 in `build`, both debatable; 61 more outside `build` are deliberate (demos, chart series, decoders). twk: 3 in `build`, all deliberate | ANSI name → slot is a guess (`red` → `error`?); `Dataset.color` has no slot | **don't** (an assist at most) |
| 3 | key conflicts between KeyBindings | the same key in an inner and an outer layer of one expression, the outer never firing | layers in different classes (the usual case); `Shortcuts` whose action may be disabled; maps that are not literals | 3 nested pairs in all the code; 1 shares keys, and it is an intentional pass-on demo | none | **don't** (but see 6) |
| 4 | interactive widget with no label | `TextField`/`TextArea` with neither `semanticsLabel` nor `placeholder`, `TextFormField` with no `placeholder`, `Slider` with no `semanticsLabel`, `Checkbox`/`Switch` with neither label, `Button` whose literal label has no letter or digit | labels from variables; custom controls built from `Focus`/`Pressable` | 5 hits (3 in apps, 2 in twk), 0 false alarms | insert `semanticsLabel: ''`; `TextFormField` needs the parameter first | **done in 57dc0c0** (`unnamed_control`) |
| 5 | `BuildContext` used after an `await` | a use of `State.context` or of a `BuildContext` variable after an `await` (or in a `Future` callback) with no `mounted` check since | contexts kept in fields; guards of the app's own (`if (!cancelled)`) | with `set_state_after_dispose`'s logic copied: 12 hits, 12 false alarms; with two easy fixes, 5, all false alarms needing flow analysis | `if (!mounted) return;` / `if (!context.mounted) return;` before the statement | **done in d7f8208** (`context_after_await`, on the flow analysis of `mounted_flow.dart`) |
| 6 | (new) key names that fire only with the kitty protocol | literal key names twk documents as never arriving on other terminals (`ctrl+i`, `ctrl+shift+s`, `super+…`, `shift+enter`), and names that fail the build (typos, duplicates, hints for keys not bound) | names built at run time; parameters not on the list | 87 literal names in apps, 31 in twk: 0 hits in code, 1 in a doc example | per name: the key it arrives as | **done in 938acdc** (`key_names`, a warning; the parser ported and held to twk's by a test) |
| 7 | (new) inherited lookups in `initState` | `X.of(context)` in `initState` | n/a | 4 hits, all `getInheritedWidgetOfExactType` reads, which are correct | n/a | **don't**: twk asserts it at run time |
| 8 | (new) `set_state_after_dispose`'s own false alarms | a fix to the existing warning, not a new rule | n/a | the branch pattern of 5(b), reproduced with the real plugin; and 2 warnings on twk's own `FutureBuilder` (`foundation/async.dart:427`, `:437`), guarded by a token of its own | the same flow analysis as 5; for the token, `mounted &&` in the guard | **done in d7f8208** (`set_state_after_dispose` on the same flow analysis; `mounted &&` in `FutureBuilder`'s and `FutureProvider`'s guards) |

## 1. Ambiguous-width glyphs in literals that reach a Text

**What twk does already.** The terminal's width for East Asian Ambiguous
characters is measured when the app starts
(`packages/twk_core/lib/src/terminal/terminal.dart`, `_ambiguousProbe`; `ambiguous = x >= 2
? 2 : 1`). It goes into the `TextSegmenter` that both layout and painting
use. `codePointWidth(cp, ambiguousWidth)` in `packages/twk_core/lib/src/unicode/unicode.dart`
gives an ambiguous character `ambiguousWidth` columns.
`packages/twk_core/lib/src/render/text.dart` shapes text again when `seg.ambiguousWidth`
changes, and measures its own `…` by it. `packages/twk_core/lib/src/canvas.dart` draws with
the same width. twk's own widgets switch to fallbacks where a glyph must be
one column: `ChartGlyphs` (`packages/twk/lib/src/data/chart_glyphs.dart`,
not exported) uses braille and `BorderType.ascii`, borders and `Divider`
use ascii (`packages/twk_core/lib/src/render/decoration.dart`, `use(type, ambiguous)`), and
so do `Split`, `Menu` and `Table`.

So `Text('a │ b')` on a CJK terminal is measured as 6 columns, laid out as
6 and drawn as 6. It is wider, but nothing is cut or misplaced.

**What a rule would report.** A `SimpleStringLiteral` or
`StringInterpolation` holding a code point for which
`stringWidth(c, ambiguousWidth: 2) > stringWidth(c)`, sorted by where the
literal goes:

- *reaches a widget*: an enclosing `InstanceCreationExpression` or
  `MethodInvocation` in the same expression whose type is a twk `Widget`
  or `Span`. Apps: 61 hits. twk: 21.
- *repeated*: the left operand of `*` (`'─' * width`). This is the one
  form that assumes one column per glyph. Apps: 7 hits, 4 of them in
  tests. twk: 0.
- *other*: constants, maps, the gallery's Code-tab strings, test
  expectations. Apps: 317. twk: 116.

The glyphs found most were `…` `×` `│` `─` `↑↓←→` `●` `█` `•` `·`. Greek
and Cyrillic letters are East Asian Ambiguous too: `π` and `Δ` reached
widgets, and Cyrillic appeared in tests. A rule on these characters would
flag any Russian or Greek UI text.

**False alarms.** All 61 widget hits are correct as written, because twk
measures them. The 3 repetitions outside tests:

- `packages/twk_dev/example/tally.dart:82`: `Text('■' * count)`. At
  ambiguous width 2 the bar is twice as long and clipped by its row. This
  is a real defect, but a minor one.
- `packages/gallery/lib/src/pages/debugging.dart:1502`:
  `canvas.text(0, 0, '·' * width, …)` in a painter. Half as many dots,
  still across the width. Cosmetic.
- `packages/gallery/lib/src/pages/editing.dart:459`:
  `'•' * characterCount`. This mirrors an obscured field, whose own `•` is
  measured the same way. Correct.

The 4 in tests run at ambiguous width 1, which is fixed, so they are
correct.

**Blind spots.** The rule cannot see glyphs that come from variables,
other files or data. It also cannot tell what the terminal will measure.
The defect is not "an ambiguous glyph" but "code that assumes it is one
column": a fixed `SizedBox(width: 1)`, `padRight`, or hit positions
computed from `.length`. The prototype found none of these.

**Fix.** There is no general fix. Lines are `Divider` and
`VerticalDivider`, which fall back to ascii. A painter can read
`canvas.segmenter.ambiguousWidth`. A widget's `build` has no public way to
read the ambiguous width: `segmenterOf` in `text/hit_row.dart` is
internal.

**Verdict: don't.** Nearly every hit would be noise. The defect this rule
is after is caught by running the screen at ambiguous width 2. twk_test's
`Shot(…, ambiguousWidth: 2)` and `HeadlessTerminal(ambiguousWidth: 2)`
already exist, and `packages/twk/test/text/ambiguous.dart` (`WideApp`)
does exactly this for twk's own widgets.

## 2. Hard-coded colours in `build`

**What twk has.** `Color` is an extension type in `packages/twk_core/lib/src/style.dart`,
with `Color.rgb`, `Color.indexed` and the ANSI constants. The analyzer sees
it as an `InterfaceElement`, so `isTwkClass` finds it. `ThemeData`
(`packages/twk/lib/src/style/theme.dart`) has twelve `Style` slots
(`primary`, `error`, `success`, …) and derived tokens. `ThemeData.terminal`
itself is made of the ANSI colours.

**What a rule would report.** A
`Color.rgb(…)`/`Color.indexed(…)` `InstanceCreationExpression`, or a
`PrefixedIdentifier` naming a `Color` constant other than `defaultColor`,
inside a `build` method. Hits inside a `ThemeData(…)` or a
`ThemeData.copyWith(…)` are exempt.

**Measured.**

- Apps: 2 in `build`.
  - `tally.dart:82`, `Style(fg: Color.green)`: a judgement call;
    `theme.success` would follow the theme.
  - `templates/dashboard/lib/dashboard_template.dart:118`,
    `Dataset(color: Color.cyan)`: `Dataset.color` is a `Color`, not a
    `Style`, so the themed form is the awkward
    `theme.info.fg ?? Color.defaultColor`.
- Apps, outside `build`: 61 more. 44 are in top-level or field
  declarations, which is where the gallery writes its pages (closures in
  fields): colour and gradient demos, the fruit colours of the mouse
  page, chart series. 17 are in functions and methods, such as decoders
  (`Color.rgb(v >> 16 & 0xFF, …)`) and lerps.
- twk: 3 in `build`, all deliberate: the press flash mixes towards white
  or black (`controls/pressable.dart:352`), and a dialog's shade is black
  (`overlay/dialog.dart:368`). 60 are in `ThemeData` presets (exempt). The
  rest are SGR decoders in twk_rich and twk_term.

**Blind spots.** Builds written as closures in fields, which is the
gallery's whole style. Helpers that `build` calls. Colours passed in from
elsewhere.

**Fix.** Turning `Color.red` into `theme.error.fg` guesses at intent, and
needs a `Theme.of(context)` in reach. Chart series have no slot.

**Verdict: don't.** Two debatable hits in 109 files, and every other
colour in the code is deliberate. If anything, this is an assist ("use the
theme's slot") rather than a lint.

## 3. Key conflicts between KeyBindings

**What twk does.** `KeyBindings` and `Shortcuts`
(`packages/twk/lib/src/focus/shortcuts.dart`) are layers of the focus
tree. A key goes to the layer nearest the focus first, and a layer around
part of the app does not get keys pressed elsewhere. Shadowing is the
design: "one key does what the part of the app with the focus says". A key
bound to `null` passes on, and so does a `Shortcuts` intent with no enabled
action. Inside one layer, two names for the same keys, or a hint for a key
that is not bound, already fail the build (`_parse`: `twice(…)`,
`FormatException('… has a hint but is not bound')`).

**What a rule would report.** Inside one expression, a `KeyBindings`
nested in another layer's `child:` through single-child arguments only
(no list, builder or `Focus` in between), where both bind the same
canonical key and the inner binding is not `null`. Only then does the
outer binding never fire.

**Measured.** There are 43 literal layers in all the code (35 in apps, 7
in twk) and 20 whose map is not a literal (1 in apps, 19 in twk). Only 3
pairs are nested in one expression, and 1 of them shares keys:
`packages/gallery/lib/src/pages/focus.dart:835/852`. That is a `Shortcuts`
inside a `KeyBindings`, both binding `up`/`down`. The page exists to show
the outer layer getting the key when the inner action is disabled, so the
hit is intentional. True positives: 0.

**Blind spots.** In real apps the layers are in different classes: the
app's `KeyBindings` sits around a page whose `build` has its own. The tree
between them is dynamic (routes, overlays, conditionals). Controls also
take keys in their own `onKeyEvent`, for example a `TextField` takes the
printable characters. A static rule sees none of this.

**Verdict: don't.** Shadowing is what twk means layers to do, the case
the rule can prove is rare, and the one example measured was intended.
The part of this idea that holds up is rule 6.

## 4. Interactive widgets a screen reader cannot name

**What twk does.** The screen-reader mode reads the semantics tree as
lines (`packages/twk/lib/src/semantics/semantics.dart`,
`SemanticsNode.line`: the role's word, then the label, then the value).

- `Button` is a `button` of its `label` (`controls/button.dart:169`).
- `TextField` and `TextArea` are a `textbox` of `semanticsLabel`, else of
  `placeholder` (`editing/text_field.dart:556`, `text_area.dart:545`).
- `Slider` is a `slider` of `semanticsLabel` (`controls/slider.dart:310`).
- `Checkbox` and `Switch` are read by `label`, else by `semanticsLabel`
  (`controls/toggle.dart:361`).

With neither, the line is just `textbox` or `slider 0.5`.

**What a rule would report.** An `InstanceCreationExpression` of:

- `TextField` or `TextArea` with neither a `semanticsLabel` nor a
  `placeholder` argument (or both null or `''`);
- `TextFormField` with no `placeholder`;
- `Slider` with no `semanticsLabel`;
- `Checkbox` or `Switch` with neither `label` nor `semanticsLabel`;
- `Button` whose literal label has no letter or digit (`'×'`, `'▶'`).

**Measured: 5 hits, 0 false alarms.** Each one really is read without a
name.

- `packages/gallery/lib/src/pages/navigation.dart:1098`:
  `TextField(controller: _name)` in a `Step(title: 'Name')`. The title is
  read on its own line, as a list item, and is not tied to the field.
- `packages/twk/example/files.dart:1154`: a `TextFormField` below
  `Text('… to')`. **`TextFormField` has no `semanticsLabel` parameter**
  (`controls/form.dart:496`), so the only way to name it is
  `placeholder`. Wrapping it in `Semantics(label:)` does not name it: the
  field is a node of its own below that one.
- `packages/gallery/lib/src/pages/controls.dart:1709`: a `Slider` with no
  `semanticsLabel`, read as `slider 0.5`.
- In twk itself: the command palette's query field
  (`overlay/command_palette.dart:713`) and the file picker's path field
  (`controls/file_picker.dart:1158`).

There were no glyph-only `Button`s and no unlabelled toggles.

**Blind spots.** Labels from variables (`Button(label)`) are not checked.
Neither are custom controls built from `Focus(onKeyEvent:)` or
`Pressable` with no `Semantics`. A class-level check for that found 2
classes in apps (the gallery shell, the debugging page's aids) and 10 in
twk: `Table`, `TreeView`, `TreeTable`, `Calendar`, `Scrollable`,
`Pressable`, the console's prompt views and twk_term's `TerminalView`. None
of their files has a `Semantics` (no role, no structure). That is an
audit item for twk, not a lint: `Pressable` is a building block, and the
shell's keys are not a control.

**Fix.** Insert `semanticsLabel: ''` with the cursor between the quotes.
Where a `Text` literal sits right before the widget, as in two of the
five hits, offer that text. `TextFormField` first needs a `semanticsLabel`
passed through to its `TextField`, which is a change to twk.

**Verdict: build with limits.** Precise, and it found real gaps,
including two in twk. Literal arguments only, as a lint (opt-in), not a
warning.

**Done in 57dc0c0** (`unnamed_control`, with the fix *Add
'semanticsLabel'*).

## 5. A BuildContext used after an `await`

**What happens in twk.** After `dispose`, `State.context` asserts (`the
context of … used after dispose()`, `framework/framework.dart:379`).
`deactivate` clears `_inheritedElements` and `_parent`
(`framework.dart:1015`, `:968`). So with a context held from before:

- `Theme.of` and other inherited lookups find nothing;
- `Navigator.of` finds no ancestor;
- `context.widget` throws (`_widget!`).

`BuildContext.mounted` and `State.mounted` are the checks.

**What the Dart linter does.** `use_build_context_synchronously` does not
see twk. A scratch package depending on twk, with the lint on and three
plain violations (a `showToast(context, …)` and a `Theme.of(context)`
after an `await` in a `State`, and a `Theme.of(context)` after an `await`
in a button's async callback), gave "No issues found".

**What `set_state_after_dispose` covers.** Only `setState`
(`packages/twk_lints/lib/src/rules/set_state_after_dispose.dart`). Its
gap logic is the last `await` before the call by offset, or a callback of
`then`/`catchError`/`whenComplete`/`Future.delayed`. Its checks are
`if (mounted)` around the call, and `if (!mounted) return;` in an
enclosing block after the gap. A `context` rule could reuse all of it,
with the use being a `SimpleIdentifier` whose element is `State`'s
`context` getter, or a parameter or local of twk's `BuildContext` type.

**Measured with that logic copied: 12 hits (11 in apps, 1 in twk), 12
false alarms.** There were four causes:

- **(a) 6 hits: the context is an argument of the awaited call itself**
  (`await showDialog(context, …)`, `await Navigator.of(context).push(…)`),
  which is evaluated before the suspension. Examples:
  `packages/twk/example/files.dart:672`, `:735`, `:773`, `:802`,
  `settings.dart:96` and gallery `navigation.dart:647`.
  `set_state_after_dispose` has the same offset test, but nobody awaits a
  `setState`.
- **(b) 4 hits: `mounted` checked inside the branch that awaited**
  (`files.dart:685`, `:689`, `:696`, `:700`). The pattern is
  `if (ask) { final a = await …; if (a == null || !mounted) return; }`
  followed by a use. Both paths are safe, but an offset-based scan sees
  an `await` with no check in an enclosing block.
- **(c) 1 hit: a context obtained after the `await`**: an `Element` loop
  variable in `packages/gallery/tool/code_check/harness.dart:146`.
- **(d) 1 hit: a guard of the code's own**: `if (!cancelled)` in
  `packages/twk/lib/src/provider/async_provider.dart:173`.

(a) and (c) are easy to fix. The prototype did so: it skipped a use inside
the awaited expression, and a variable declared after the gap. That left 5
hits, all (b) and (d). There are no true positives: this code checks
`mounted` after every `await`.

**Verdict: build with limits.** It is worth building, because the core
lint is blind to twk and the failure is a crash or a stale theme. But
only with flow analysis that follows `if`/`else` branches, as the core
lint's must. Without it the hits here are all false alarms. The rule
would sit beside `set_state_after_dispose` and share its new flow logic
(rule 8). The core lint's source is in the SDK's `pkg/linter`. It is not
in this checkout or in the pub cache, so its flow handling was not read
for this file.

**Fix.** Insert `if (!mounted) return;` (for `State.context`) or
`if (!context.mounted) return;` (for a parameter) before the statement.
This is the correction `set_state_after_dispose` already gives.

## 6. (new) Key names that fire only with the kitty protocol

**What twk documents.** In `KeyCombo`'s doc
(`packages/twk/lib/src/focus/key_combo.dart:34`): without the kitty
keyboard protocol, `ctrl+i` arrives as `tab`, `ctrl+m` and `ctrl+j` as
`enter`, `ctrl+[` as `escape`, `ctrl+h` as backspace and `ctrl+2` as
`ctrl+space`. Ctrl, Shift and a letter arrive as Ctrl and the letter.
Ctrl or Shift with `enter` or `escape` arrive as the key alone. Super does
not arrive at all. "A binding of `ctrl+i` fires there only on the
protocol's terminals". Nothing warns at run time.

**What a rule would report.** A literal key name that is one of these,
read as `KeyCombo._parse` reads it (a capital letter is Shift; modifiers
in any order). Also two names in one map that such a terminal sends
alike (`tab` and `ctrl+i`). The same parser also catches at analysis time
what fails the build at run time: a name that is not one (`'esc'`,
`'cmd+s'`), the same keys twice in one map, and a hint for a key that is
not bound.

The places names are written:

- the map literals of `KeyBindings` and `Shortcuts`;
- `KeyCombo.parse('…')`;
- string parameters that take key names: `SelectionArea.copyKey` and
  `clearKey`, the leader of `LeaderKey`, and the key lists of `Table`,
  `TreeView`, `TreeTable` and `TerminalView`, which parse them
  (`data/table.dart:1080`, `data/tree.dart:975`,
  `twk_term/…/terminal_view.dart:211`).

**Measured.** 87 literal names in apps and 31 in twk were read, with 0
hits in code. One hit is in a doc example: `SelectionArea`'s doc
(`packages/twk/lib/src/gestures/selection.dart:91`) binds
`copyKey: 'ctrl+shift+c'`. By `KeyCombo`'s own doc that arrives as
`ctrl+c` on a terminal without the protocol. There the copy key does not
fire, and Ctrl+C goes on to the app's quit when nothing else takes it. The
gallery lists `ctrl+shift+s` and `ctrl+h` in an option list
(`pages/overlays.dart:571`, `:574`), but those are labels, not bindings,
and the rule would rightly leave them alone.

**Blind spots.** Names built at run time, maps that are not literals (19
of twk's layers), and parameters missing from the list.

**Fix.** The message names what the key arrives as. Changing the key is
the author's call, so the rule needs no quick fix.

**Verdict: build with limits.** It cannot raise a false alarm about
behaviour, because it states what twk documents. It is cheap: one parser
port, with `KeyCode`'s names. It is silent on this repository's code,
except for a doc example worth fixing. Make it one lint (`key_names`) with
two messages: "fires only with the kitty protocol" and "fails the build".

**Done in 938acdc** (`key_names`). A warning rather than an opt-in lint,
as both of what it says are facts of twk, not taste: "fires only with the
kitty protocol" a warning, "fails the build" an error. The plugin does
not import twk, so the parser is ported, and `test/key_names_test.dart`
holds it to twk's own (the names, every message, and what arrives,
through twk_test's xterm bytes and twk_core's input parser). On this
repository it found no key that fires only with the protocol, and 9
names that fail the build, all in twk's tests of that failure, which
ignore it with the reason. `SelectionArea`'s doc example now binds
`alt+c`, and its `copyKey` says why not `ctrl+shift+c`. Table, TreeView
and TreeTable take no key names (the lists cited above are their own), so
the rule reads twk_term's `TerminalView.ignoredKeys` alone of those.

## 7. (new) Inherited lookups in `initState`

A `Theme.of(context)` in `initState` would be read once and never again.
twk already asserts on this (`framework.dart:1325`: "depends on … in
initState(), which is not called again when it changes"), so every test
that mounts the widget catches it. The prototype found 4 `of`/`maybeOf`
calls in `initState`: `example/dashboard.dart:55` (`AppBinding.of`),
`binding/terminal_status.dart:237` and `:294`, and
`binding/app_binding.dart:1861`. All four read through
`getInheritedWidgetOfExactType`, which registers no dependency, so they
are correct. **Verdict: don't.** The run-time assert does the job, and a
static rule would have to tell depending lookups from reading ones by
looking inside each `of`.

## 8. (new) `set_state_after_dispose` warns on safe code

The branch pattern of 5(b) also trips the existing warning. A scratch
package with the plugin enabled and this code:

```
Future<void> go(bool ask) async {
  if (ask) {
    final ok = await showDialog<bool>(context, (_) => const Text('?'));
    if (ok == null || !mounted) {
      return;
    }
  }
  setState(() => _n++);
}
```

got `warning - lib/b.dart:18:5 - 'setState' may run after 'dispose': it
follows an 'await', with no check of 'mounted'.` Both paths are safe. The
cause is that `_gapBefore` takes the last `await` by offset, and
`_checkedSince` looks for the check only in the blocks that enclose the
call, not in the branch that holds the `await`. The repository's own code
avoids the pattern. `files.dart:685–700` would hit it if it called
`setState` there.

**A second false alarm, in twk itself.** The plugin's warnings are on
wherever it is enabled. Turned on for `packages/twk` (the
`wall_time_in_tests` work does that), it reports
`lib/src/foundation/async.dart:427:13` and `:437:13`: "'setState' may run
after 'dispose': it is in a callback of a Future, with no check of
'mounted'". These are `FutureBuilder`'s `then` callbacks. They guard with
a token of their own, `if (_waitingOn == token)`, and `dispose` clears
`_waitingOn`. So they are safe, the same kind of guard as 5(d). Both
warnings fail `dart analyze --fatal-infos`. The simple fix is in
`async.dart`: `if (mounted && _waitingOn == token)`, which the rule
already accepts. The rule cannot learn guards like this one in general. **Fix**, with the flow analysis of 5. As a smaller step,
an `if` statement whose branches each either contain no `await` or end
the `await`-holding path with a `mounted` exit could count as a check.
