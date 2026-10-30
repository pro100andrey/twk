# twk_lints performance: what the plugin costs, and where

What each rule, fix and assist costs in time and allocations, what the
plugin costs before any rule runs, and how that was measured. The aim of
the code is to run as fast and allocate as little as it can, and to use the
analyzer's own API where it has one.

**In short.** Enabling the plugin makes the root's `dart analyze` about
21 s slower (7.4 s to 28.3 s). The rules are not where that time goes:
all nine together cost about 0.12 s of work over the whole workspace, and a
plugin with one rule that does nothing is as slow as the real one (29.5 s).
The 21 s is analysis_server_plugin resolving every library of the workspace
again in its own isolate, from source, with no disk cache, and twice per
library. That is upstream code, which twk_lints cannot change from inside
itself. The assists cost 0.14 ms per code-action request, all 19 together.

## How it was measured

- **Code**: the pub workspace (one context root, 1069 libraries, 1107
  units, 384,292 lines), in a scratch worktree, with
  `dart pub get --offline`.
- **Machine**: 24 hardware threads. Everything ran under
  `taskset -c 0-10,12-22`, off CPU 23 and its sibling 11 (the benchmark's),
  at a load average of 2 to 15, given with each figure.
- **`dart analyze`** (Dart 3.13.7, analysis server built AOT), timed
  wall-clock and traced with `strace -f -e trace=execve`, which shows each
  `dart pub upgrade` and `dart compile aot-snapshot` the server starts for
  a plugin. Each was run three to six times, warm (`~/.dartServer`
  populated), in three configurations: the plugin as it is; no `plugins:`
  section anywhere; and a no-op twk_lints whose only rule registers
  nothing. The no-op still needs its one rule, because with no rule needing
  resolution the plugin server reads parsed units only
  (`PluginServer._canUseParsedResult`).
- **Rules**: a harness that does what analysis_server_plugin's
  `PluginServer._computeDiagnosticsFromPlugin` does. For each library it
  builds a `RuleContextWithResolvedResults`, gives a new
  `RuleVisitorRegistryImpl` to each rule's `registerNodeProcessors`, and
  runs an `AnalysisRuleVisitor` over each unit. It uses analyzer's
  `AnalysisContextCollectionImpl` with the plugin's own byte store
  (`MemoryCachingByteStore(NullByteStore(), 256 MB)`) and options
  (`warning = false`, `lint = false`). Each run starts from a fresh
  resolution, so no rule reuses an AST that another run has analysed
  (`MountedFlow` keeps its result in an `Expando` per body). Timing comes
  from the harness compiled AOT, as the plugin is. Each rule's callbacks
  were timed with the analyzer's per-rule stopwatches
  (`RuleVisitorRegistryImpl(enableTiming: true)`, `analysisRuleTimers`) and
  its `registerNodeProcessors` with a stopwatch around each call. The
  upstream figures were taken with analyzer 14.5.0 and
  analysis_server_plugin 0.3.24; the code they name was read again in
  analyzer 14.7.0 and analysis_server_plugin 0.3.26, which the workspace
  resolves, and works the same.
- **Allocations**: the same harness in JIT with the VM service
  (`getAllocationProfile`), measured around the rules' run only, as the
  total of each pass above the pass with no rule, the median of three
  passes. After `reset: true` the VM's accumulated counters start from the
  bytes live at the reset, not from zero, so allocation = accumulated -
  `bytesCurrent` at the reset. Noise is about +-50 KiB for a total, and the
  per-class figures vary by up to 400 KiB in `_List` and `_Uint32List`
  between two passes of the same code, so only totals are given.
- **Assists**: each of the 19 producers run as `AssistProcessor` runs them
  (a producer from `CorrectionProducerContext.createResolved`, `compute`
  into a `ChangeBuilder`) at 6,676 cursor positions in `packages/gallery`:
  every widget creation's constructor name, every class name and every 7th
  identifier. The files were priority files, as an open editor makes them.
  Without that, `ChangeBuilder.addDartFileEdit` resolves the library again
  for each edit, and the assists come to 49 ms a request, an artifact of
  the harness.
- **Hot-path counts** (the same resolution): 389,003 `SimpleIdentifier`
  callbacks, 146,118 of them reads of a local variable or parameter;
  99,356 method invocations; 28,707 instance creations (9,363 of a
  widget); 2,456 classes (337 `State`s); 26,887 function bodies (3,883
  async).

## The plugin before any rule: `dart analyze` with and without it

Warm, workspace; ranges in brackets.

| what is analyzed | no plugin | twk_lints | no-op twk_lints | load |
|---|---|---|---|---|
| root | 7.4 s (6.9-8.6) | 28.3 s (27.7-29.5) | 29.5 s (26.7-32.9) | 3-11 |
| `packages/twk` | 2.6 s (2.6-2.8) | 12.6 s (11.9-13.5) | 12.6 s (12.4-13.3) | 8-14 |

The first run on a new checkout, and the first after any edit to
twk_lints' sources, also compiles the plugin's AOT snapshot, about 26 s.

What the time goes to, from the traces and from analysis_server_plugin,
analyzer and the SDK's analysis_server:

1. **`dart pub upgrade` for the plugin at every start**: 0.6-0.75 s, once
   per shared plugin folder (the plugin manager runs `pubCommand:
   'upgrade'` for new plugins).
2. **One plugin isolate per context root**: the server makes a shared
   plugin folder under `~/.dartServer/.plugin_manager/<md5 of the context
   root>` and starts one isolate per folder. The workspace is one context
   root, so there is one folder, one `pub upgrade`, one isolate and one
   snapshot.
3. **An AOT snapshot of the plugin per folder**: `dart compile
   aot-snapshot`, about 26 s, kept while no file in its depfile is newer.
   Each edit to twk_lints' sources makes the snapshot stale, so the next
   `dart analyze` (and `handover`'s root analyze) pays one compile.
4. **The plugin isolate resolves the whole context root again, from
   source**: about 20 s of the 21. The plugin server's byte store is
   `MemoryCachingByteStore(NullByteStore(), 256 MB)`, and the
   `byteStorePath` the server sends in `plugin.versionCheck` is never read
   (`handlePluginVersionCheck` reads only `sdkPath`). So nothing of the
   server's disk cache is used. The harness's cold resolution of the
   workspace takes 14.8-15.0 s (AOT); with linked libraries already in
   memory it takes 7.0-7.7 s.
5. **Twice per library**: the plugin adds every file to its driver
   (`_analyzeAllFilesInContextCollection`). The driver resolves each
   library to produce its `ResolvedUnitResult` events.
   `_handleResolvedUnit` then asks `getResolvedLibrary` for the same
   library, and the driver keeps resolved libraries only for priority files
   (`isLibraryWithPriorityFile` in the driver), which `dart analyze` has
   none of. So it resolves the library again. 15 s plus 7 s is the 21 s
   measured.

The rules run inside step 5, and their whole cost is the next section's
0.12 s.

**Not in twk_lints' reach.** The rule API offers
`AbstractAnalysisRule.canUseParsedResult`, which lets the plugin server skip
resolution, but every rule of twk_lints needs elements and types. What
would change the 21 s lies upstream (dart-lang/sdk,
`pkg/analysis_server_plugin`): using the `ResolvedLibraryResult` the
driver has just produced would save the second resolution, about 7 s of
28.3 s, and a disk byte store from `byteStorePath` would bring the first
towards what the server itself takes warm (7.4 s for everything), about
14 s more. A patched analysis_server_plugin can be put in through the
`plugins:` section's `dependency_overrides` (`AnalysisOptionsFile.
dependencyOverrides`, passed through by the plugin package generator) at
the cost of keeping a fork in step with the SDK.

## Per rule: time and allocations over the workspace

AOT, one pass over the 1069 libraries; medians of two runs of five; load
2-6. "register" is `registerNodeProcessors` summed over the libraries;
"callbacks" is the time in the rule's visitor, as the analyzer's rule
timers measure it. The walk itself, an `AnalysisRuleVisitor` over every
unit, takes 290-380 ms. It is paid once whatever rules are on, and once any
rule is on. Allocations are JIT, above the walk's.

| rule | register | callbacks | allocated | where the time goes |
|---|---|---|---|---|
| `context_after_await` | 14.4-15.1 ms | 32.1 ms | 90 KiB | a callback for each of the 389,003 identifiers, each filtered by one type test first; `MountedFlow` only for bodies that can have a gap |
| `dispose_controllers` | 0.2 ms | 18.5-25.6 ms (min 16.2-16.5) | 1,050 KiB | a recursive scan of each of the 337 `State` bodies; `lookUpMethod('dispose')` for each field created (the analyzer's `Name`s) |
| `key_names` | 0.3 ms | 14.1-14.3 ms | ~0 | a callback for every creation and invocation, a name switch first; parsing only key-name literals (0.37-0.47 ms for 433 literals) |
| `unnamed_control` | 0.1 ms | 2.3 ms | ~0 | `isTwkClass` for every creation |
| `wall_time_in_tests` | 0.3 ms | 8.2-8.6 ms | ~0 | `_isProgram`'s look at the declarations; constant evaluation only on candidates |
| `set_state_after_dispose` | 0.1 ms | 11.3-11.6 ms | ~0 | a callback for every method invocation (the name is checked first) |
| `missing_key_in_children` | 0.2 ms | 7.4-7.6 ms (min 6.1-6.3) | - | each of the 15,310 list literals |
| `prefer_key_bindings` | 0.1 ms | 2.4 ms | - | - |
| `untyped_table` | 0.1 ms | 2.5 ms | - | - |
| **all nine** | **17.1-17.3 ms** | **99 ms** | **980 KiB** | the walk with all nine on: 357-366 ms (minimums) |

The allocations are small: about 1 MB over a pass that resolves 384,000
lines, which allocates gigabytes.

## Design facts the figures rest on

- **`inTestDirectory(context)`** (`lib/src/test_directory.dart`) keeps
  `RuleContext.isInTestDirectory` per context in an `Expando<bool>`. The
  analyzer checks four folder names (`test`, `integration_test`,
  `test_driver`, `testing`), each a `getFolder` and an `isWithin`, about
  11 us a call and not kept; the plugin passes one `RuleContext` to every
  rule of a library, so four rules ask once, the first to ask paying.
- **`MountedFlow.of`** gives one shared flow with no gap for a body that
  is not `async` and is no `Future`'s callback (`FunctionBody.
  isAsynchronous` and `_entryGap`). A gap is an `await` or the start of a
  `Future`'s callback, so such a body cannot have one: 1,084 of the 1,111
  bodies `context_after_await` asks about, and 390 of the 407 that
  `set_state_after_dispose` does, are such bodies.
- **`twk_types.dart`** finds twk's classes by name and package, as the Dart
  linter does for Flutter's (name and library URI; the plugin may not
  import twk, so a type checker by element is not available).
  `isFromPackage` reads the library URI's text (`uri.toString()`), as a
  `_SimpleUri`'s `pathSegments` builds a list and a string per segment on
  every call. `isTwkSubtype` looks the name up in a set kept per
  `InterfaceElement` (an `Expando`), built from the class's own name and
  its direct supertypes' sets (`supertype`, `mixins`, `interfaces`, a
  mixin's `superclassConstraints`); a class whose twk names all come from
  one supertype shares that supertype's set. The sets agree with
  `allSupertypes` at each of 462,983 lookups over the workspace. The memo
  costs about 170 KiB a pass and saves about 10 ms of `context_after_await`
  (without it, 42.6 ms against 32); a set for every class instead of
  sharing came to 1.36 MB.
- **`context_after_await` tests the type first**: `isTwkSubtype(node.
  staticType, 'BuildContext')` ahead of the declaration and setter tests. A
  read of `State.context` or of a variable of a twk `BuildContext` type has
  that type (promotion only narrows it), so nothing the rule reports is
  filtered out. The registration (`addSimpleIdentifier`) is not narrowed;
  registering as the linter's `use_build_context_synchronously` does
  (method invocations, creations, prefixed identifiers, looking only at
  targets, prefixes and arguments) would report fewer uses, and its
  per-use walk up the ancestors does not cost less than `MountedFlow`,
  which walks a body once for all its uses. pkg/linter is not on pub.dev,
  and its `isBuildContext` knows Flutter's only.
- **`dispose_controllers`** builds `disposed` once after the scan and reads
  the only positional argument in place; it makes a `_DisposeOf` visitor
  per loop. Most of its allocation is the analyzer's
  `InterfaceType.lookUpMethod` (its `Name` objects), which is the right
  API.
- **`prefer_key_bindings`** finds a named handler from its element's
  `firstFragment.nameOffset`, when the element's library fragment is this
  unit's `declaredFragment`, with `CompilationUnit.nodeCovering(offset:)`
  and a walk up to the declaration. A local function written in a method
  is not followed, though the rule's documentation says "a function or
  method of the same file"; no test covers it either way.
- **`key_names`** ports twk's key grammar (`parseKeys`, `withoutKitty` in
  `lib/src/key_names.dart`), held to twk's parser by
  `test/key_names_test.dart`. No analyzer API parses twk's key names and
  the plugin may not import twk. Its callbacks' time is the dispatch on
  every creation and invocation, not the parsing.
- **Assists** use the analyzer's API where it has one: `startWithComments`
  takes the unit's `LineInfo` and `CorrectionUtils.getLineContentStart`;
  `convert_to_stateful_widget` tests membership with `asInstanceOf`; the
  `RegExp`s are top-level `final`s. `convert_to_stateless_widget`'s
  `_memberNames` walks the members by hand because the analyzer's
  `interfaceMembers` and `inheritedMembers` hold instance members only,
  and the walk counts a static member of `State` or of the widget's
  superclasses as a name taken. `fixes/dispose_field.dart` walks the
  method for a local of the same name, as the analyzer has no public scope
  of a function body (the `LibraryFragment.scope` is the library's).

### The analyzer's node lookup: `nodeCovering`

Use `CompilationUnit.nodeCovering({required int offset, int length = 0})`
for the minimal node covering an offset, as `prefer_key_bindings` does.
In analyzer 14.7.0 (the workspace's lock) it is marked
`@V1Ast('The V2 counterpart is nodeCovering2.')`
(`lib/src/dart/ast/ast.dart:10053`, implemented at :10254), and
`V1Ast`'s doc comment (:62041) says it "remains supported for clients"; it
is the analyzer's stable API, and the one the analyzer's test utilities use for
resolved units. `nodeCovering2` (:10064) is `@experimental` and is the
V2 AST's counterpart. Earlier analyzer releases (14.5.0, `ast.dart:9117`)
marked `nodeCovering` `@ToBeDeprecated('Use nodeCovering2 instead')`; that
marker is not in 14.7.0. Move to `nodeCovering2` when it stops being
experimental; until then `nodeCovering` stays, and `NodeLocator` /
`NodeLocator2` (`lib/src/dart/ast/utilities.dart:24`, :175) are the older
visitor-based lookups, not what to reach for.

## Assists and fixes

The 19 assists run on every code-action request, at the cursor. AOT,
priority file, per request, medians over 6,676 positions:

| assist | us/request | offered at |
|---|---|---|
| each of the 9 `WrapIn...` / `WrapWith...` but Expanded and Flexible | 12.5-14.3 | 1,435-1,469 |
| `WrapWithExpanded`, `WrapWithFlexible` | 4.0-4.1 | 382 |
| `ExtractWidget` | 12.7 | 1,084 |
| `RemoveWidget` | 5.1 | 449 |
| `SwapWithChild`, `SwapWithParent`, `MoveWidgetUp`, `MoveWidgetDown` | 2.3-2.6 | 130-227 |
| `ConvertToStatelessWidget` | 3.2 | 0 |
| `ConvertToStatefulWidget` | 1.2 | 16 |
| **all 19** | **141.7** | |

Most of a wrap assist's time is building its edit where it is offered
(about 58 us each time). In JIT the same run allocated 0.1-0.8 MB per
assist over all 6,676 positions, under 120 bytes a request. Nothing here
needs work for speed.

The fixes run only when the user asks for a fix of a reported diagnostic.
Each builds one edit with `ChangeBuilder` and `CorrectionUtils`
(`getLinePrefix`, `endOfLine`, `oneIndent`, `getLineThis`), as the
analyzer's own fixes do. They were read, not benchmarked; they cost
nothing until invoked.

## What holds in the rules

- No rule walks whole units with a `RecursiveAstVisitor` from its
  registration. All of them register narrow node types
  (`addMethodInvocation`, `addInstanceCreationExpression`,
  `addClassDeclaration`, `addListLiteral`); the one broad registration is
  `context_after_await`'s `addSimpleIdentifier`. `dispose_controllers`'
  recursive scan is of `State` bodies only, which is what it checks.
- No regex or string building on a rule's hot path. The only regex in a
  rule, `unnamed_control._letterOrDigit`, is a `static final` used on
  `Button` labels.
- No flow analysis of the analyzer's that `MountedFlow` could use instead:
  `ExitDetector` is not in analyzer 14.5.0 or later, and the analyzer's
  flow analysis (`FlowAnalysis` of `_fe_analyzer_shared`) runs inside
  resolution and keeps no state a rule can read. `MountedFlow`'s loops go
  round until the flow stays the same, at most 16 times; nested loops are
  walked again per level, which happens only in the 27 async bodies that
  use a context.
- A change to a rule is held to its diagnostics: compare the sorted
  `file:line:column:length:code: message` lines of the whole workspace
  for each rule alone and for all nine, and the rules' tests, which
  compare each fixture's diagnostics with the exact list expected. The
  workspace has 30 diagnostics with all nine on (9 `key_names`, 8
  `wall_time_in_tests`, 6 `missing_key_in_children`, 3
  `prefer_key_bindings`, 3 `untyped_table`, 1 `unnamed_control`).
