# twk_lints performance: what the plugin costs, and where

The person asked (2026-10-24) that twk_lints run as fast as it can,
allocate as little as it can, and use the analyzer's own API where it
has one. This is the audit: what each rule, fix and assist costs in
time and allocations, what the plugin costs before any rule runs, and
where the code rebuilds what the analyzer already offers. The audit
changed nothing in the repository; the harness and the prototypes were
in scratch. The person approved findings 3 to 10 for `lp-fix`, and
"[After lp-fix](#after-lp-fix)" says what it changed and measured.

**In short.** Enabling the plugin makes the root's `dart analyze` about
21 s slower (7.4 s to 28.3 s). The rules are not where that time goes:
all nine together cost about 0.19 s of work over the whole workspace,
and a plugin with one rule that does nothing is as slow as the real one
(29.5 s). The 21 s is analysis_server_plugin resolving every library of
the workspace again in its own isolate, from source, with no disk cache,
and twice per library. That is upstream code, which twk_lints cannot
change from inside itself. Inside twk_lints the measured savings come to
about 50 ms a pass: `context_after_await` (60 ms, the most expensive
rule), the `isInTestDirectory` four rules each ask for (46 ms), and the
type checks of `twk_types.dart`. The assists cost 0.16 ms per code-action
request, all 19 together.

**After lp-fix.** The nine rules' own work over the workspace went from
about 170 ms a pass to about 116 ms (register 45 to 17 ms, callbacks
125 to 99 ms), measured back to back on the same machine. The
diagnostics are the same, one by one. Allocations stay about 1 MB a
pass. That does not change the 21 s: findings 1 and 2 are where it goes.

## How it was measured

- **Code**: the workspace at `61b7fae` (the commit that made one pub
  workspace), in a scratch worktree, with `dart pub get --offline`. For
  the layout before it, `2a8e4a1` in another. twk_lints is the same in
  both.
- **Machine**: 24 hardware threads. Everything ran under
  `taskset -c 0-10,12-22`, off CPU 23 and its sibling 11, while other
  agents of the fleet worked. The load average is given with each
  number; it was between 2 and 15.
- **`dart analyze`** (Dart 3.13.7, analysis server built AOT), timed
  wall-clock and traced with `strace -f -e trace=execve`, which shows
  each `dart pub upgrade` and `dart compile aot-snapshot` the server
  starts for a plugin. Each was run three to six times, warm
  (`~/.dartServer` populated), and compared in three configurations:
  the plugin as it is; no `plugins:` section anywhere; and a no-op
  twk_lints whose only rule registers nothing. The no-op still needs
  its one rule, because with no rule needing resolution the plugin
  server reads parsed units only (`_canUseParsedResult`,
  plugin_server.dart:516).
- **Rules**: a harness that does what analysis_server_plugin 0.3.24's
  `PluginServer._computeDiagnosticsFromPlugin` does
  (plugin_server.dart:550–622). For each library it builds a
  `RuleContextWithResolvedResults`, gives a new
  `RuleVisitorRegistryImpl` to each rule's `registerNodeProcessors`,
  and runs an `AnalysisRuleVisitor` over each unit. It uses analyzer
  14.5.0's `AnalysisContextCollectionImpl`, with the plugin's own byte
  store (`MemoryCachingByteStore(NullByteStore(), 256 MB)`) and its
  options (`warning = false`, `lint = false`). The workspace comes to
  1069 libraries, 1107 units and 384,292 lines. Each run starts from a
  fresh resolution, so no rule reuses an AST that another run has
  already analysed: `MountedFlow` keeps its result in an `Expando` per
  body. Timing comes from the harness compiled AOT, as the plugin is.
  Each rule's callbacks were timed with the analyzer's own per-rule
  stopwatches (`RuleVisitorRegistryImpl(enableTiming: true)`,
  `analysisRuleTimers`) and its `registerNodeProcessors` with a
  stopwatch around each call. Each figure is a median of 5–7 runs.
- **Allocations**: the same harness in JIT with the VM service
  (`getAllocationProfile`), measured around the rules' run only. One
  detail matters: after `reset: true`, the VM's accumulated counters
  start from the bytes that are live at the reset, not from zero (a
  probe showed this), so allocation = accumulated − `bytesCurrent` at
  the reset. Each rule is shown above the run with no rule, per class.
  The noise is about ±40 KiB.
- **Assists**: each of the 19 producers run as `AssistProcessor` runs
  them (a producer from `CorrectionProducerContext.createResolved`,
  `compute` into a `ChangeBuilder`) at 6,676 cursor positions in
  `packages/gallery`. The positions are every widget creation's
  constructor name, every class name and every 7th identifier. The files
  were priority files, as an open editor makes them. Without that,
  `ChangeBuilder.addDartFileEdit` resolves the library again for each
  edit (`getResolvedLibraryContaining`, change_builder_core.dart:393),
  and the assists came to 49 ms a request, an artifact of the harness.
- **Hot-path counts** (the same resolution): 389,003 `SimpleIdentifier`
  callbacks, 146,118 of them reads of a local variable or parameter;
  99,356 method invocations; 28,707 instance creations (9,363 of a
  widget); 2,456 classes (337 `State`s); 26,887 function bodies (3,883
  async).

## The plugin before any rule: `dart analyze` with and without it

| what is analyzed (warm) | no plugin | twk_lints | no-op twk_lints | load |
|---|---|---|---|---|
| root, workspace (`61b7fae`) | 7.4 s (6.9–8.6) | 28.3 s (27.7–29.5) | 29.5 s (26.7–32.9) | 3–11 |
| `packages/twk`, workspace | 2.6 s (2.6–2.8) | 12.6 s (11.9–13.5) | 12.6 s (12.4–13.3) | 8–14 |
| root, before the workspace (`2a8e4a1`) | — | 32.1 s, 36.8 s (20.3 s at load 4) | — | 4–9 |
| root, before the workspace, first run | — | 348 s, 158 s | — | 2–5 |

What the time goes to, from the traces and from analysis_server_plugin
0.3.24, analyzer 14.5.0 and the SDK's analysis_server at the SDK's
revision (`416e33b`):

1. **`dart pub upgrade` for each plugin at every start**: 0.6–0.75 s,
   once per shared plugin folder (plugin_manager.dart:346–351,
   `pubCommand: 'upgrade'` for the new plugins).
2. **One plugin isolate per context root**: the server makes a shared
   plugin folder under `~/.dartServer/.plugin_manager/<md5 of the
   context root>` and starts one isolate per folder
   (plugin_watcher.dart:126–164). Before the workspace there were 16
   context roots, so 16 `pub upgrade`s one after the other (about
   10 s) and 16 isolates, each resolving twk and everything else its
   package imports. Since `61b7fae` there is one of each. The
   CONTRIBUTING.md figures (packages 5 s to 49 s) were from that layout.
3. **An AOT snapshot of the plugin per folder**: `dart compile
   aot-snapshot`, about 26 s, kept while no file in its depfile is newer
   (plugin_manager.dart:815–852). On a new checkout, and after every
   edit to twk_lints, the next analyze compiles it again: 12 compiles,
   one after the other, were 305 s of the 348 s first run before the
   workspace. Now it is one compile.
4. **The plugin isolate resolves the whole context root again, from
   source**: about 20 s of the 21. The plugin server's byte store is
   `MemoryCachingByteStore(NullByteStore(), 256 MB)`
   (plugin_server.dart:79–82), and the `byteStorePath` the server sends
   in `plugin.versionCheck` is never read
   (`handlePluginVersionCheck`, plugin_server.dart:323–332, reads only
   `sdkPath`). So nothing of the server's disk cache is used. The
   harness's cold resolution of the workspace takes 14.8–15.0 s (AOT);
   with linked libraries already in memory it takes 7.0–7.7 s.
5. **Twice per library**: the plugin adds every file to its driver
   (`_analyzeAllFilesInContextCollection`, plugin_server.dart:364–381).
   The driver resolves each library to produce its `ResolvedUnitResult`
   events. `_handleResolvedUnit` (plugin_server.dart:1117–1149) then
   asks `getResolvedLibrary` for the same library, and the driver keeps
   resolved libraries only for priority files (`_resolvedLibraryCache`,
   driver.dart:1523–1525), which `dart analyze` has none of. So it
   resolves the library again. 15 s plus 7 s is the 21 s measured.

The rules run inside step 5, and their whole cost is the next section's
0.19 s.

## Per rule: time and allocations over the workspace

AOT, one pass over the 1069 libraries; medians of 5–7 runs; load 3–8.
"register" is `registerNodeProcessors` summed over the libraries;
"callbacks" is the time in the rule's visitor, as the analyzer's rule
timers measure it. The walk itself, an `AnalysisRuleVisitor` over every
unit, takes 290–380 ms. It is paid once whatever rules are on, and once
any rule is on. Allocations are JIT, above the walk's.

| rule | register | callbacks | total | allocated | where the time goes |
|---|---|---|---|---|---|
| `context_after_await` | 12.2 ms | 60.4 ms (54–63) | **72.6 ms** | 119 KiB (`_Map` 55, `MountedFlow` 13) | a callback for each of the 389,003 identifiers; `isTwkSubtype(…, 'BuildContext')` on each of the 146,118 reads of a local; `MountedFlow` built for 1,111 bodies, 1,084 of which cannot have a gap; `isInTestDirectory` |
| `dispose_controllers` | 0.2 ms | 25.2 ms (18–37) | 25.4 ms | 792 KiB (`_List` 332, `Name` 121, `_Uint32List` 145) | a recursive scan of each of the 337 `State` bodies; `lookUpMethod('dispose')` for each field created (the analyzer's `Name`s) |
| `key_names` | 10.8 ms | 13.6 ms | 24.4 ms | 14 KiB | `isInTestDirectory`; a callback for every creation and invocation, a name switch first; parsing only key-name literals |
| `unnamed_control` | 12.9 ms | 8.2 ms | 21.1 ms | ≈0 | `isInTestDirectory`; `isTwkClass(element, element.name)` for every creation, and so `isFromPackage` twice for each non-twk class |
| `wall_time_in_tests` | 10.6 ms | 8.7 ms | 19.3 ms | ≈0 | `isInTestDirectory`, and `_isProgram`'s look at the declarations; constant evaluation only on candidates |
| `set_state_after_dispose` | 0.1 ms | 12.3 ms | 12.4 ms | 10 KiB | a callback for every method invocation (the name is checked first); `MountedFlow` built for 407 bodies, 390 of which cannot have a gap |
| `missing_key_in_children` | 0.2 ms | 6.6 ms | 6.8 ms | ≈0 | each of the 15,310 list literals |
| `prefer_key_bindings` | 0.1 ms | 3.1 ms | 3.2 ms | ≈0 | — |
| `untyped_table` | 0.1 ms | 2.6 ms | 2.7 ms | ≈0 | — |
| **all nine** | **48.9 ms** | **140.7 ms** | **≈190 ms** | **≈1.07 MB** | the walk with all nine on: 456 ms against 381 ms for the walk alone |

The allocations are small: about 1 MB over a pass that resolves 384,000
lines, which allocates gigabytes. No rule's own classes appear above
the noise except `MountedFlow` (19 KiB) and its maps.

### After lp-fix

The same harness on the workspace at `15240aa` (the core moved to
`packages/twk_core`: 1069 libraries again), twk_lints at `15240aa`
against twk_lints with lp-fix, the two run one after the other, twice
each, at load 2–6. Each cell is "before → after", the medians of two
runs of 5. Allocations: JIT, the total of each pass above the pass
with no rule, the median of three passes; ±50 KiB is noise there, and
the per-class figures vary by up to 400 KiB in `_List` and
`_Uint32List` between two passes of the same code, so only totals are
given.

| rule | register | callbacks | allocated | what changed (finding) |
|---|---|---|---|---|
| `context_after_await` | 11.6–14.5 → 14.4–15.1 ms | 56.5–66.6 → **32.1 ms** | ≈0 → 90 KiB | the type is tested first (#6); no `MountedFlow` for a body with no gap (#3); the subtype test kept per class (#5); it now asks `isInTestDirectory` for all four rules (#4) |
| `dispose_controllers` | 0.2 → 0.2 ms | 16.2–19.5 → 18.5–25.6 ms (min 15.4–15.6 → 16.2–16.5) | 835 → 1,050 KiB | `disposed` built once, the argument read in place (#7): no change measurable; the per-class memo of #5 for its `State` test of every class adds the allocation |
| `key_names` | 10.6–12.1 → 0.3 ms | 13.0–13.7 → 14.1–14.3 ms | ≈0 → ≈0 | `isInTestDirectory` shared (#4); its parsing, 0.37–0.47 ms for 433 literals, left as it is (#10) |
| `unnamed_control` | 10.4–11.7 → 0.1 ms | 7.4–8.3 → **2.3 ms** | ≈0 → ≈0 | `isInTestDirectory` shared (#4); `isFromPackage` reads the URI's text (#5) |
| `wall_time_in_tests` | 10.5–11.7 → 0.3 ms | 8.3–8.6 → 8.2–8.6 ms | ≈0 → ≈0 | `isInTestDirectory` shared (#4) |
| `set_state_after_dispose` | 0.1 → 0.1 ms | 12.1–12.2 → 11.3–11.6 ms | ≈0 → ≈0 | no `MountedFlow` for a body with no gap (#3) |
| `missing_key_in_children` | 0.2 → 0.2 ms | 6.3–7.7 → 7.4–7.6 ms (min 6.0–6.1 → 6.1–6.3) | — | none |
| `prefer_key_bindings` | 0.1 → 0.1 ms | 2.9 → 2.4 ms | — | the handler found from its name's offset (#8) |
| `untyped_table` | 0.1 → 0.1 ms | 2.4–2.5 → 2.5 ms | — | none |
| **all nine** | **45.1–52.4 → 17.1–17.3 ms** | **125 → 99 ms** | **905 → 980 KiB** | the walk with all nine on: 408–412 ms → 357–366 ms (minimums) |

The diagnostics were compared one by one: for each of the eleven
configurations (no rule, each rule alone, all nine), the sorted
`file:line:column:length:code: message` lines of the whole workspace,
before against each step and against the end. All identical: 30 with
all nine (9 `key_names`, 8 `wall_time_in_tests`, 6
`missing_key_in_children`, 3 `prefer_key_bindings`, 3 `untyped_table`,
1 `unnamed_control`). The workspace has none of the other three rules'
diagnostics; for those, and for the rest, the rules' tests compare each
fixture's diagnostics with the exact list expected, and passed before
and after.

Step by step, each change added to the ones before it (one series of
runs, at load falling from 5 to 2, so the later steps are a little
flattered): #3 took `context_after_await`'s callbacks from 64.9 to
56.7 ms; #5 took `unnamed_control`'s from 8.1 to 2.5 ms and
`context_after_await`'s to 51.9 ms; #4 took all registration from
47.6 to 15.1 ms; #6 took `context_after_await`'s callbacks from 51.4
to 31.7 ms; #7 and #8 moved nothing beyond the noise but
`prefer_key_bindings`' 2.8 to 2.3 ms.

The allocations: `MountedFlow` and its maps are gone (about 70 KiB), and
#5's memo adds about 170 KiB a pass: a set of names for each class of
twk's, an `Expando` entry for each class asked about. A class of no twk
name of its own whose names come from one supertype (an app's widget,
a `State`) shares that supertype's set; a first version, a set for
every class, came to 1.36 MB against 0.99 MB before (one pass each, so
not quite comparable with the table). Without the memo at all, the
toString test of #5 alone, the total is about 805 KiB, and
`context_after_await`'s callbacks 42.6 ms (min 36.0) instead of 32: the
memo trades 170 KiB for 10 ms. It was approved as the memo, and kept.

## Assists and fixes

The 19 assists run on every code-action request, at the cursor. AOT,
priority file, per request, medians of 3 over 6,676 positions:

| assist | µs/request | offered at |
|---|---|---|
| each of the 9 `WrapIn…` / `WrapWith…` but Expanded and Flexible | 12.5–14.3 | 1,435–1,469 |
| `WrapWithExpanded`, `WrapWithFlexible` | 4.0–4.1 | 382 |
| `ExtractWidget` | 12.7 | 1,084 |
| `RemoveWidget` | 5.1 | 449 |
| `SwapWithChild`, `SwapWithParent`, `MoveWidgetUp`, `MoveWidgetDown` | 2.3–2.6 | 130–227 |
| `ConvertToStatelessWidget` | 3.2 | 0 |
| `ConvertToStatefulWidget` | 1.2 | 16 |
| **all 19** | **160** | |

Most of a wrap assist's time is building its edit where it is offered
(about 58 µs each time). In JIT the same run allocated 0.1–0.8 MB per
assist over all 6,676 positions, under 120 bytes a request. Nothing here
needs work for speed.

The fixes run only when the user asks for a fix of a reported
diagnostic. Each builds one edit with `ChangeBuilder` and
`CorrectionUtils` (`getLinePrefix`, `endOfLine`, `oneIndent`,
`getLineThis`), as the analyzer's own fixes do. They were read, not
benchmarked; they cost nothing until invoked.

## Ranked findings

Ranked by the time they would save on the root's `dart analyze`.
"Behaviour" says whether a diagnostic, an assist or twk_lints' public
API would change.

| # | finding | where | measured cost | replacement | expected gain | behaviour |
|---|---|---|---|---|---|---|
| 1 | the plugin isolate resolves every library twice, with no disk cache | analysis_server_plugin 0.3.24, plugin_server.dart:79, :323, :1136; analyzer driver.dart:1523 | ≈20 s of 28.3 s | none in twk_lints: upstream, or a patched analysis_server_plugin through the `plugins:` section's `dependency_overrides` | ≈7 s for the second resolution; up to ≈14 s more with a disk byte store | none |
| 2 | one isolate, `pub upgrade` and AOT snapshot per context root | SDK plugin_watcher.dart:126, plugin_manager.dart:351, :601 | 16× before `61b7fae`; 26 s per snapshot rebuilt after each twk_lints edit | the pub workspace, done in `61b7fae` | done: 32–37 s down to 28 s; 12–16 compiles down to 1 | none |
| 3 | `context_after_await` and `set_state_after_dispose` build `MountedFlow` for bodies that cannot have a gap | context_after_await.dart:129, set_state_after_dispose.dart:112, mounted_flow.dart:61 | 72.6 ms and 12.4 ms per pass | `FunctionBody.isAsynchronous` and the existing `_entryGap` before `MountedFlow.of` | prototype: 60.4 to 48.8 ms (with #5) | none |
| 4 | `RuleContext.isInTestDirectory` asked by four rules for every library | context_after_await.dart:83, key_names.dart:105, unnamed_control.dart:66, wall_time_in_tests.dart:74 | 10.6–12.9 ms each, 46 ms per pass | the same getter, asked once per library and shared | ≈35 ms per pass | none |
| 5 | `isTwkSubtype` walks `allSupertypes` again on every call; `isFromPackage` builds `pathSegments` | twk_types.dart:9–32 | part of #3; `unnamed_control` 8.2 ms | the same name and package test, kept per `InterfaceElement` (an `Expando`), and the package read from the URI's text | prototype: `unnamed_control` 8.2 to 2.3 ms | none |
| 6 | `context_after_await` takes a callback for every `SimpleIdentifier` | context_after_await.dart:81 | 389,003 callbacks, most of #3's remaining 49 ms | a cheap first test (`staticType` an interface type whose element is a twk `BuildContext`, cached as in #5); or the linter's narrower registration | ≈20–30 ms (estimated) | none for the first; the second reports fewer uses |
| 7 | `dispose_controllers` rebuilds `disposed` for each field, and a list for each invocation | dispose_controllers.dart:104–105, :156–159, :198–201 | part of 25 ms; 792 KiB, mostly the analyzer's `lookUpMethod` | the set built once after the scan; the positional arguments read in place | a few ms, ≈300 KiB | none |
| 8 | `prefer_key_bindings` walks the whole unit to find a named handler | prefer_key_bindings.dart:94, :114–121 | only an `InputListener` whose `onEvent` names a function; within 3.1 ms | `fragment.nameOffset` and `CompilationUnit.nodeCovering(offset:)` | <1 ms | none |
| 9 | assists: home-made versions of analyzer API | widget_tree.dart:87–100; convert_to_stateful_widget.dart:229; convert_to_stateless_widget.dart:259–269, :486; extract_widget.dart:198 | 0.16 ms per request, all 19 | `CorrectionUtils.getLineContentStart` and `LineInfo`; `InterfaceType.asInstanceOf`; `InterfaceElement.inheritedMembers`/`interfaceMembers`; `RegExp`s hoisted to `static final` | negligible; less code | none, if the member sets match |
| 10 | `key_names`' grammar port | key_names.dart (helper) | parsing is inside 13.6 ms of callbacks and only on key literals | no analyzer API parses twk's key names, and the plugin may not import twk | none | — |

lp-fix did 3 to 10, each section below saying how and what it measured;
1 is still being discussed, and 2 was done by the workspace.

## 1. The plugin isolate resolves every library twice, with no disk cache

- **Where**: analysis_server_plugin 0.3.24 `lib/src/plugin_server.dart`.
  - :79–82 `_byteStore = MemoryCachingByteStore(NullByteStore(), …)`.
  - :323–332 `handlePluginVersionCheck` takes `sdkPath` from
    `PluginVersionCheckParams` and leaves its `byteStorePath` unread.
    The server sends one: plugin_isolate.dart:459–465 throws without
    it.
  - :364–381 every analyzed `.dart` file goes to `driver.addFile`.
  - :1117–1149 `_handleResolvedUnit` takes the driver's
    `ResolvedUnitResult` of a library's defining unit and then calls
    `getResolvedLibrary(unitResult.path)`.
  - In analyzer 14.5.0, `driver.dart:1523–1525` keeps a resolved
    library only `if (isLibraryWithPriorityFile)`.
- **Cost**: 28.3 s with the plugin against 7.4 s without at the root,
  and 12.6 s against 2.6 s for `packages/twk`. The no-op plugin costs
  the same as the real one. The harness resolves the workspace in
  14.8–15.0 s cold and 7.0–7.7 s with linked libraries in memory: the
  two resolutions, about 22 s.
- **Replacement**: none from inside twk_lints. The rule API offers
  `AbstractAnalysisRule.canUseParsedResult`, which lets the plugin
  server skip resolution, but every rule of twk_lints needs elements and
  types. Options the person may choose from:
  - Ask upstream (dart-lang/sdk, `pkg/analysis_server_plugin`) to use
    the `ResolvedLibraryResult` the driver has just produced, or
    `byteStorePath`.
  - Run a patched analysis_server_plugin. The server writes the
    generated plugin package's pubspec from the `plugins:` section,
    and `dependency_overrides:` there are passed through:
    `AnalysisOptionsFile.dependencyOverrides`
    (analysis_options_file.dart:70) and `PluginPackageGenerator`
    (SDK plugin2/generator.dart). The cost is keeping a fork in step
    with the SDK.
- **Expected gain**: using the driver's result saves the second
  resolution, about 7 s of 28.3 s. A disk byte store would bring the
  first resolution towards what the server itself takes warm (7.4 s for
  everything), about 14 s more.
- **Behaviour**: none.

## 2. One plugin per context root (done by the workspace)

- **Where**: SDK `pkg/analysis_server/lib/src/plugin/plugin_watcher.dart`
  :126–164 (a shared plugin folder named by the context root's path) and
  plugin_manager.dart :346–351 (`pub upgrade` at each start), :601–650
  (an AOT compile when no snapshot is fresh) and :815–852 (a snapshot is
  stale once any file of its depfile is newer).
- **Cost before `61b7fae`**: 16 plugin folders. Warm runs did 16
  `pub upgrade`s, about 10 s one after the other, and the root took
  32–37 s (20 s at load 4). The first run compiled 12 snapshots at
  about 26 s each, one after the other: 348 s.
- **Now**: one `pub upgrade` (0.7 s), one isolate, one snapshot. What
  stays: each edit to twk_lints' sources makes its snapshot stale, so
  the next `dart analyze` (and `handover`'s root analyze) pays one
  compile of about 26 s. That is the "rebuild its plugin snapshot"
  CONTRIBUTING.md describes.
- **Behaviour**: none. Nothing for lp-fix.

## 3. `MountedFlow` for bodies that cannot have a gap

- **Where**: context_after_await.dart:124–129 and
  set_state_after_dispose.dart:108–112 call `MountedFlow.of(body)` for
  the innermost `FunctionBody` of each use. mounted_flow.dart:49–58 walks
  the whole body.
- **Why it is hot**: a gap is an `await`, which needs an `async` body,
  or the start of a Future's callback (`_entryGap`,
  mounted_flow.dart:155). A synchronous body that is no such callback
  has neither. Yet 1,084 of the 1,111 bodies walked for a context use
  (a `build` that reads `context`, an `onPressed` closure) and 390 of
  the 407 with a `setState` are such bodies, so the walk finds nothing.
- **Replacement**: `if (!body.isAsynchronous && _entryGap(body) == 0)`
  then no gap, before `MountedFlow.of`. `FunctionBody.isAsynchronous` is
  public in analyzer 14.5.0 (ast.dart:4608, :17520). The rule's
  documented semantics stay exact: a gap is only ever an `await` in this
  body or this body's entry as a callback.
- **Measured**: the prototype (with #5) took `context_after_await`'s
  callbacks from 60.4 to 48.8 ms; `set_state_after_dispose` stayed at
  about 12 ms, as `MountedFlow` was never most of its cost.
- **Behaviour**: none. The same number of diagnostics (30) over the
  workspace with and without it; their identity was not compared one
  by one.

- **Done (lp-fix)**: `MountedFlow.of` gives one shared flow with no
  gap for a body that is not `async` and is no `Future`'s callback, so
  both rules are as they were. Callbacks: `context_after_await` 64.9 to
  56.7 ms, `set_state_after_dispose` 12.8 to 12.4 ms. The diagnostics
  over the workspace are the same, one by one. Only code with an
  `await` outside an `async` body, a compile error, could differ.

## 4. `isInTestDirectory` four times per library

- **Where**: `context.isInTestDirectory` in
  context_after_await.dart:83, key_names.dart:105,
  unnamed_control.dart:66 and wall_time_in_tests.dart:74.
- **Why it costs**: analyzer 14.5.0 `RuleContextWithResolvedResults.
  isInTestDirectory` (src/analysis_rule/rule_context.dart:110) calls
  `PubPackage.isInTestDirectory`, which checks four folder names
  (`test`, `integration_test`, `test_driver`, `testing`). Each check
  is a `getFolder` (canonicalised, an `io.Directory`) and a
  `pathContext.isWithin` (workspace.dart:122–131,
  physical_file_system.dart:227, :294). That is about 11 µs per call,
  and the result is not kept.
- **Measured**: 10.6–12.9 ms per rule, 46 ms of the 49 ms that all
  registration takes.
- **Replacement**: the same getter asked once per library. The plugin
  passes one `RuleContext` to every rule of a library
  (plugin_server.dart:584–587), so a helper in twk_lints that keeps the
  answer per context (an `Expando<bool>` keyed by
  `context.definingUnit`) serves all four rules.
- **Expected gain**: about 35 ms per pass.
- **Behaviour**: none.

- **Done (lp-fix)**: `inTestDirectory(context)`
  (lib/src/test_directory.dart), an `Expando<bool>` keyed by the
  context. All registration: 47.6 to 15.1 ms; the first rule to ask
  pays the one call (in the harness's order, `context_after_await`).

## 5. `twk_types.dart`: the subtype test walks the supertypes on every call

- **Where**: `isTwkSubtype` (twk_types.dart:26–32) is
  `allSupertypes.any((t) => isTwkClass(t.element, name))`, a closure
  and an iteration for each call. `isFromPackage` (:9–15) calls
  `uri.pathSegments` twice. A library's URI is a `_SimpleUri`, and the
  SDK's `_SimpleUri.pathSegments` (dart-sdk lib/core/uri.dart:4700)
  builds a growable list, a substring per segment and an unmodifiable
  copy on every call.
- **Callers on hot paths**: `context_after_await`, for each of the
  146,118 reads of a local or parameter; `unnamed_control`, through
  `isTwkClass(element, element.name)`, for every creation and so twice
  for each non-twk class (unnamed_control.dart:80–84);
  `missing_key_in_children` and `wall_time_in_tests`, on candidates.
- **The analyzer's way**: analyzer 14.5.0 has no type checker by name
  (`TypeChecker` is source_gen's). `InterfaceType.asInstanceOf
  (InterfaceElement)` (dart/element/type.dart:162) and
  `TypeSystem.isSubtypeOf` need twk's element, which a library that does
  not import twk lacks. The Dart linter itself tests Flutter's classes
  the way twk_types does: name and library URI, with
  `allSupertypes.any` (pkg/linter `util/flutter_utils.dart`,
  `isExactly`, `isWidget`, `isState`). So matching by name is the
  analyzer team's own approach, not a home-made one. `allSupertypes` is
  cached by the element (element.dart:5819).
- **Replacement**: keep the matching, and keep its answer:
  - per `InterfaceElement` (an `Expando<Set<String>>`), the names of
    the twk classes it is or extends, so a test is one set lookup;
  - the package read from `uri.toString()`, which a `_SimpleUri`
    returns without building anything (`startsWith('package:twk/')`).
- **Measured** (prototype): `unnamed_control` 8.2 to 2.3 ms; part of
  #3's 60.4 to 48.8 ms; `missing_key_in_children` unchanged (6.6 ms).
  The same number of diagnostics.
- **Behaviour**: none; `isFromPackage`'s signature can stay.

- **Done (lp-fix)**: `isFromPackage` reads `uri.toString()`, and
  `isTwkSubtype` looks the name up in a set kept per `InterfaceElement`.
  The set is built from the class's own name and its direct supertypes'
  sets (`supertype`, `mixins`, `interfaces`, a mixin's
  `superclassConstraints`), so a class whose twk names all come from one
  supertype shares that set. Over the workspace, the sets were checked
  against `allSupertypes` at each of 462,983 lookups (a scratch copy
  that threw on a difference): none. `unnamed_control` 8.1 to 2.5 ms;
  the allocations it adds are under "After lp-fix" above.

## 6. A callback for every identifier in `context_after_await`

- **Where**: context_after_await.dart:81
  (`registry.addSimpleIdentifier`) and its filter, :116–128
  (`inDeclarationContext`, `inSetterContext`, then `mountedCheckFor`'s
  element tests).
- **Cost**: 389,003 callbacks a pass, most of the 49 ms left after #3
  and #5.
- **Replacements**:
  - With no change of behaviour: test the cheapest thing first. A use of
    a context has `node.staticType` an `InterfaceType` that is (with #5's
    cache, one lookup) a twk `BuildContext`. Of the 389,003 identifiers
    almost none pass that test, and the declaration and setter tests
    are then asked only of those. This is an estimate, not measured:
    20–30 ms.
  - With a change of behaviour: register as the linter's
    `use_build_context_synchronously` does (pkg/linter
    `rules/use_build_context_synchronously.dart`:953–964,
    `addMethodInvocation`, `addInstanceCreationExpression`,
    `addFunctionExpressionInvocation`, `addPrefixedIdentifier`, and
    looking only at targets, prefixes and arguments). A context read in
    any other place, an assignment `final c = context;` for one, would
    no longer be reported.
- **Not a replacement**: the linter's rule itself. pkg/linter is not
  on pub.dev and a plugin cannot import it. Its per-use walk up the
  ancestors (`check`, :1123–1147, a new `AsyncStateTracker` for each
  use, with no cache per body) does not cost less per use than
  `MountedFlow`, which walks a body once for all its uses. Its
  `isBuildContext` knows Flutter's `BuildContext` only.

- **Done (lp-fix)**, the first replacement: `isTwkSubtype(node.staticType,
  'BuildContext')` before anything else. A read of `State.context` or of
  a variable of a twk `BuildContext` type has that type (promotion only
  narrows it), so nothing the rule reported is filtered out. Measured:
  51.4 to 31.7 ms, about what was estimated. The registration was not
  narrowed.

## 7. `dispose_controllers`' small repeats

- **Where**:
  - dispose_controllers.dart:104–105 calls `scan.disposed` once for
    each created field, and :156–159 rebuilds the set each time.
  - :198–201 makes a list of positional arguments for every method
    invocation in a `State` body.
  - :258–265 makes a new `_DisposeOf` visitor for each loop.
- **Cost**: within 25 ms (18–37, the noisiest rule). Of its 792 KiB,
  most is the analyzer's `InterfaceType.lookUpMethod` (its `Name`
  objects), which is the right API.
- **Replacement**: build `disposed` once after the scan; read the
  argument list in place (`arguments.length`, the first positional).
- **Expected gain**: a few ms and about 300 KiB.
- **Behaviour**: none.

- **Done (lp-fix)**: `disposed` once after the scan, and the only
  positional argument read in place (`_onlyPositional`). Not measurable
  against the noise (minimums 15.4–15.6 ms before, 16.2–16.5 after);
  `_DisposeOf` per loop left as it is.

## 8. `prefer_key_bindings` finds a named handler by walking the unit

- **Where**: prefer_key_bindings.dart:94 and :114–121 (`_Find`, a
  `RecursiveAstVisitor` over the whole unit).
- **Replacement**: the element's `firstFragment.nameOffset`, when its
  `libraryFragment` is this unit's `declaredFragment`, then
  `CompilationUnit.nodeCovering(offset:)` (src/dart/ast/ast.dart:9118,
  marked `@ToBeDeprecated` for `nodeCovering2`, itself `@experimental`)
  and up to the `MethodDeclaration` or `FunctionDeclaration`.
- **Cost and gain**: only for an `InputListener` whose `onEvent` names
  a function; within the rule's 3.1 ms. Under 1 ms. Worth it only for
  tidiness.

- **Done (lp-fix)**: `nodeCovering(offset: nameOffset)` and up to the
  declaration, when the element's library fragment is this unit's.
  `prefer_key_bindings` 2.8 to 2.3 ms. As before, a local function
  written in a method is not followed (`_Find` never went into a
  method), though the rule's documentation says "a function or method
  of the same file": kept so the diagnostics stay the same; no test
  covers it either way.

## 9. Assists: analyzer API where the code has its own

None of these matter for speed (all 19 assists together: 0.16 ms per
request). They are code the analyzer already has:

- widget_tree.dart:87–100, `startWithComments`, finds the start of a
  comment's line with `lastIndexOf('\n')`, a `substring` and a `trim`.
  `CorrectionUtils.getLineContentStart` (correction_utils.dart:80) and
  the unit's `LineInfo` give the same thing.
- convert_to_stateful_widget.dart:229 tests membership with
  `widget.allSupertypes.any((t) => t.element == enclosing)`.
  `widget.thisType.asInstanceOf(enclosing) != null` is the analyzer's
  test.
- convert_to_stateless_widget.dart:259–269, `_memberNames`, collects
  the members of a type and its supertypes by hand. That is
  `InterfaceElement.inheritedMembers` / `interfaceMembers`
  (dart/element/element.dart:1879–1890, keyed by `Name`), though those
  also include private members of other libraries. Check that the sets
  agree before swapping.
- `RegExp('[A-Za-z0-9_]')` (convert_to_stateless_widget.dart:486) and
  `RegExp('^_+')` (extract_widget.dart:198) are built on each call:
  `static final`, as unnamed_control.dart:123 already does.
- fixes/dispose_field.dart:117–145 walks the method for a local of the
  same name. analyzer 14.5.0 has no public scope of a function body (the
  `LibraryFragment.scope` `freeName` uses is the library's), so the
  walk stays.

- **Done (lp-fix)**: `startWithComments` with the unit's `LineInfo` and
  `getLineContentStart`; `asInstanceOf` in `convert_to_stateful_widget`;
  both `RegExp`s top-level `final`s. `_memberNames` stays: the
  analyzer's `interfaceMembers` and `inheritedMembers` hold instance
  members only, and the walk counts a static member of `State` or of the
  widget's superclasses as a name taken, so the sets do not agree. All
  19 assists: 145.6 to 141.7 µs per request (147.7 to 138.2 in a first
  run), within the noise.

## 10. key_names' port of twk's key grammar

`parseKeys`/`withoutKitty` (lib/src/key_names.dart) run only on string
literals in twk's key positions. `key_names`' 13.6 ms of callbacks are
its dispatch on every creation and invocation (a name `switch` first),
not the parsing. The analyzer has no API for twk's key names, and the
plugin may not import twk (README). The port, held to twk's parser by
`test/key_names_test.dart`, is the cheapest way there is. No change.

- **Measured (lp-fix)**: a stopwatch around `_name` (parse and
  `withoutKitty`) in a scratch copy: 0.37–0.47 ms a pass for the 433
  key literals of the workspace, of `key_names`' 13 ms of callbacks.
  Negligible, as expected; unchanged.

## What was not found

- No rule walks whole units with a `RecursiveAstVisitor` from its
  registration. All of them register narrow node types (`addMethodInvocation`,
  `addInstanceCreationExpression`, `addClassDeclaration`,
  `addListLiteral`). The only broad one is `context_after_await`'s
  `addSimpleIdentifier` (#6). `dispose_controllers`' recursive scan is
  of `State` bodies only, which is what it checks.
- No regex or string building on a rule's hot path. The only regex in a
  rule, `unnamed_control._letterOrDigit`, is a `static final` used on
  `Button` labels.
- No flow analysis of the analyzer's that `MountedFlow` could use
  instead. `ExitDetector` is gone from analyzer 14.5.0, and the
  analyzer's flow analysis (`_fe_analyzer_shared`'s `FlowAnalysis`)
  runs inside resolution and keeps no state a rule can read.
  `MountedFlow`'s loops go round until the flow stays the same, at most
  16 times (mounted_flow.dart:288–304). Nested loops are walked again
  per level, but after #3 that happens only in the 27 async bodies that
  use a context.
