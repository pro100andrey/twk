# Implicit links between parts

The rule: a link between two parts is explicit, a parameter or an object
passed at the edge, unless the ambient form is the point. This is the list
of the links in `packages/*/lib` and `tool/*/lib` that are not explicit:
zone values, `IOOverrides`, the process's environment, static and
top-level mutable fields, Expandos and Symbol keys. For each it says where
the link is set and where it is read, and the reason it is the ambient
form. A new one is added here with its reason, or made a parameter.

Paths are under `packages/` unless they start with `tool/`.

| # | link | set → read | why it is ambient |
| --- | --- | --- | --- |
| 1 | the `TWK_*` environment | the shell → `TwkApp` (`twk_core/lib/src/app.dart:40-41, 244`), `AppBinding` (`twk/lib/src/binding/app_binding.dart:343-344`, `1384`, `1912`) | read at the edge, given as a parameter |
| 2 | `log()` finds its app's sink | `twk_core/lib/src/app.dart:556` → `twk_core/lib/src/log.dart:305` | like `print` |
| 3 | `Cli.current` | `twk/lib/src/cli/cli.dart:156, 183` → `:99-100` | an accessor for a program's own helpers |
| 4 | `runningTester` | `twk_test/lib/src/tester.dart:63` → `:89`, read at `finders.dart:89, 159` | a `Matcher` gets no tester |
| 5 | fake time: FakeClock and SyncClock zones | `twk_test/lib/src/fake_clock.dart:50`, `tool/alloc/lib/sync_clock.dart:24` | replacing timers is what a zone is for |
| 6 | the tester's stderr through `IOOverrides` | `twk_test/lib/src/tester.dart:121` → `twk_core/lib/src/platform/io.dart:47` (via `twk_core/lib/src/app.dart:1063`) | catches the app's own `stderr` |
| 7 | test seams kept in statics | the tests → `twk/lib/src/binding/app_binding.dart:1885` (`DebugAids.runEditor`), `:797` (`AppBinding.postEvent`) | stand in for process-wide things |
| 8 | the service extensions' registry of running apps | `twk/lib/src/binding/app_binding.dart:557-559, 813-814` | the service is global |
| 9 | `TWK_UPDATE_GOLDENS` and `updateScreenFilesOverride` | the shell → `twk_test/lib/src/screen_file.dart:16, 24, 31` | package:test passes no flags |
| 10 | state kept in an `Expando` beside its object | see the entry | same package, visible API |
| 11 | statics private to one file, set and read there | see the entry | a hooks API, guards, speed |
| 12 | Symbol keys `#pointerShape`, `#progress` | `twk/lib/src/binding/terminal_status.dart:177-178` → `TerminalStateBackend.setTerminalState` (`twk_core/lib/src/terminal/terminal.dart:730, 740`) | the caller owns the key |
| 13 | counters a test reads | lib increments, tests read | never read by the library |
| 14 | the gallery pages' top-level state | `gallery/lib/src/pages/overlays.dart:761-764, 968-969, 1253-1255`, `rich.dart:1415` | app code |

## The entries

- **1, the `TWK_*` environment.** `TwkApp` and `AppBinding` take
  `Map<String, String>? environment`; null is the process's, with the
  terminal's settings over it (`TwkApp.environment`, `app.dart:307-311`,
  `_environmentOn` at `:288`). `TwkApp` reads `TWK_DEBUG` once into
  `TwkApp.debugNames` (`:40-41`, `:299` for `debugNamesRead`) and
  `TWK_LOG` (`:244`). `AppBinding` reads `TWK_SCREEN_READER`
  (`_readerAsked`, `:343-344`), the rest of `TWK_DEBUG` through
  `DebugAids` (`:1384`, `:1394`) and the editor's variables from
  `twkApp.environment` (`:1912`), so the one map decides all of them.
  `runApp` and the console's session pass nothing and read the process's.
  `TwkTester.pumpWidget` and `tool/alloc` (`tool/alloc/lib/app_run.dart:38`)
  pass `const {}`, so a variable the developer exported changes no test.
  Variables of the terminal layer are read there from the environment it
  is given: `TWK_GRAPHICS` (`twk_core/lib/src/terminal/terminal.dart:587`),
  `TWK_PLAIN` (`twk_core/lib/src/terminal/plain.dart:25`), the trace
  variables (`terminal.dart:1039-1040`). `twk_dev` reads `TWK_DEBUG` and
  `TWK_SCREEN_READER` from the process because it is an edge
  (`twk_dev/lib/src/run.dart:235`, `inspect.dart:93`). The core's own
  tests that make a `TwkApp` directly give no `environment` and read the
  process's.
- **2, `log()` for app code.** `log()` is a top-level function like
  `print`, called with no handle. The zone that catches `print`
  (`ZoneSpecification(print: _print)`, `app.dart:557`) catches its
  records, under `logSinkKey` (`twk_core/lib/src/log.dart:125`), which
  the core does not export. The library's own warnings are not this link:
  a render object reports through `PipelineOwner.onLog`
  (`twk_core/lib/src/render/pipeline.dart:64`, `object.dart:568-575`), set
  by `TwkApp` (`app.dart:278, 447`), by `HeadlessTerminal`'s tree
  (`twk_core/lib/src/headless.dart:431-438`) and by the console's
  `widgetLines` (`twk/lib/src/cli/lines.dart:134, 161`; `cli.dart:412`),
  and fall back to `log()` only where no route is set.
- **3, `Cli.current`.** `Cli.run` hands the body its `cli`. Nothing in
  `lib/` reads `Cli.current`; it is for a program's own helpers, as
  `log()` is. Outside a run it falls back to a `Cli` on process stdio made
  at first use (`_default ??= Cli()`, `cli.dart:90, 100`) and never
  closed; its doc says so (`:94-97`).
- **4, `runningTester`.** It exists so that `expect(find.text('x'),
  findsOneWidget)` works: package:test's convention, flutter_test's `find`
  works the same way. Outside `testTwk`, `Finder.evaluate` throws a
  `StateError` rather than finding nothing.
- **5, FakeClock and SyncClock.** Neither holds a zone value. The app's
  clock is passed explicitly (`clock: clock.stopwatch`); the zone only
  replaces timers and microtasks, as fake_async does.
- **6, `IOOverrides` for stderr.** `TwkTester.stderrLines` is what the
  app wrote to stderr, including its own `stderr.writeln`, which only an
  override catches. The core's report at exit goes through `printError`
  the same way. A parameter would catch only the core's.
- **7, `DebugAids.runEditor` and `AppBinding.postEvent`.** They stand in
  for spawning the editor and for the VM service's event stream. They are
  `@visibleForTesting`, and the tests put them back in `tearDown`
  (`twk/test/debug/editor_test.dart:69-72`,
  `twk/test/binding/hot_reload_test.dart:181-188`,
  `twk/test/binding/service_extensions_test.dart:596`).
- **8, `_runningApps` and `_registered`.** VM service extensions are
  registered once per isolate, from the root zone (`Zone.root.run`,
  `app_binding.dart:782`), so the "app that started last" registry is
  global because the service is.
- **9, `TWK_UPDATE_GOLDENS`.** An environment variable is how golden files
  are refreshed (`TWK_UPDATE_GOLDENS=1 dart test`), and
  `updateScreenFilesOverride` is its test seam.
- **10, Expandos.** Each keeps the state of one object beside it, in the
  same package, read through a visible API. In `twk`: `GlobalKey._owners`
  (`framework/framework.dart:199`), `_Arena._arenas`
  (`gestures/gesture_detector.dart:266`), `TerminalStatus._ofApp`
  (`binding/terminal_status.dart:61`), `Style._penIds`
  (`style/style.dart:153`), and file-private ones in `gestures/selection.dart:259, 931`,
  `gestures/mouse.dart:1058`, `text/widgets.dart:229`,
  `overlay/toast.dart:105`, `animation/effect.dart:570`,
  `editing/caret.dart:170, 249`, `debug/inspector.dart:49`,
  `provider/inherited_provider.dart:598`, `cli/progress.dart:324`. In the core,
  `PipelineOwner.textOrder` is an extension over `_textOrders`
  (`twk_core/lib/src/render/text.dart:184, 192`); `_anyVisual` (`:185`) is
  a fast-path latch that changes no result. Elsewhere: `twk_rich`
  `bigtext/big_text.dart:463`, `markdown/markdown_view.dart:421`;
  `twk_test/lib/vt.dart:334`; `gallery/lib/src/page.dart:416`; and the
  analysis plugin's caches (`twk_lints/lib/src/test_directory.dart:13`,
  `mounted_flow.dart:71, 99`, `twk_types.dart:40`).
- **11, file-private statics.** `HookElement._current`
  (`twk/lib/src/hooks/hook.dart:228`) is how a hook finds its element,
  which is what a hooks API is. `_inSelector`
  (`twk/lib/src/provider/inherited_provider.dart:479`) is an assert guard.
  `Element._attachingAt` (`twk/lib/src/framework/framework.dart:1007`),
  `_visiting` (`:2713`), `_unmountError`/`_unmountStack` (`:2755-2756`),
  `RenderObject._attaching` (`twk_core/lib/src/render/object.dart:1049`)
  and `_cutTop`/`_cutBottom`/`_cutAt` (`object.dart:1736-1738`) pass a
  value to a tear-off without a closure per element: a speed choice inside
  one walk. Scratch buffers (`TextStops`, `GrowingInts`, segmenters) in
  `twk/lib/src/editing/` and `animation/` are reused the same way.
- **12, Symbol keys.** The key belongs to the caller of
  `setTerminalState`; nothing else reads it. The only risk is two callers
  picking the same Symbol; the core uses an `Object()` for its own key
  (`terminal.dart:1495`).
- **13, counters.** The library only increments them: `TextBuffer.joins`
  (`twk/lib/src/editing/text_buffer.dart:74`) and `LogView.renderVisits`
  (`twk/lib/src/scroll/log_view.dart:561`) are `@visibleForTesting`;
  `comparedUnits` (`twk_rich/lib/src/markdown/appended.dart:10`, not
  exported) and `qrEncodes` (`gallery/lib/src/pages/rich.dart:1415`) are
  top-level. A test reading them cannot change behaviour.
- **14, the gallery pages.** State of a demo page kept across visits of
  its route, which its Code tab reads, all in one file of an app. It is
  not a library link.

## Terminal capabilities

The window title and notifications are not an implicit link: the core
declares `WindowBackend` next to `SuspendableBackend`,
`TerminalStateBackend` and `MouseTrackingBackend`
(`twk_core/lib/src/terminal/terminal.dart:715, 730, 756, 773`), and twk
checks for the interface, not for a concrete class
(`twk/lib/src/binding/terminal_status.dart:69-70, 203`;
`app_binding.dart:639`). A backend that wraps another implements the
interface and forwards; one that does not gets nothing.
