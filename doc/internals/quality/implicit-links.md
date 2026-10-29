# Implicit links between parts

The rule (2026-10-23): a link between two parts is explicit, a parameter
or an object passed at the edge, unless the ambient form is the point.
This is the audit of `lib/`, `packages/*/lib` and `tool/*/lib` against
it, as of 49258a8. That commit removed the two links that started it: the
`#twk.clock` zone value FakeClock set for ProgressTracker to read, and
ProgressList's `_adopt` putting the app's clock in place of a tracker's
own stopwatch.

Searched for: `zoneValues`, `Zone.current[`, `runZoned`, `Zone.root`,
`IOOverrides`; static and top-level mutable fields; `??=` defaults;
`Platform.environment` and `environment[` reads; Symbol and string keys;
type checks on another package's concrete classes; and widgets writing
to an object they were handed. Each line number below was read in the
code. Each count comes from `rg`.

Three are to change. The rest are kept, each for the reason given.

| # | item | ends (set → read) | verdict | cost |
| --- | --- | --- | --- | --- |
| 1 | `TWK_*` environment read inside the app and binding | the shell → `packages/twk_core/lib/src/app.dart:38-39, 196, 199-201, 232-233`; `packages/twk/lib/src/binding/app_binding.dart:292/298, 1189, 1687` | **done in 34df707**: an `environment` given to `TwkApp` and `AppBinding`, `const {}` from the tester | 2 optional parameters (no break); the tester changes 1 line; `DebugAids.editorEnvironment` goes (4 test lines) |
| 2 | the library's own warnings reach the log through `log()`'s zone | `packages/twk_core/lib/src/app.dart:464` → `packages/twk_core/lib/src/log.dart:273`, called from `packages/twk_core/lib/src/render/flex.dart:444`, `wrap.dart:347`, `grid.dart:452` | **done in ead30e0**: a log route on `PipelineOwner` next to its `onError` | 1 field on `PipelineOwner` (no break); 3 calls in the core; 1 line each in `TwkApp` and in the console's `widgetLines` |
| 3 | window title and notifications go through a type switch on two core classes | `packages/twk/lib/src/binding/app_binding.dart:521-526`, `terminal_status.dart:180-185` → `Terminal` / `HeadlessTerminal` | **done in f311194**: a core capability interface, checked as `TerminalStateBackend` is | 1 interface added to the core API; 2 switches in twk; no callers change |
| 4 | `log()` called by app code finds its app's sink | `packages/twk_core/lib/src/app.dart:464` → `packages/twk_core/lib/src/log.dart:273` | keep | — |
| 5 | `Cli.current` | `packages/twk/lib/src/cli/cli.dart:149, 176` → `:97` | keep | — |
| 6 | `runningTester` | `packages/twk_test/lib/src/tester.dart:63` → `:89`, read at `finders.dart:89, 159` | keep | — |
| 7 | fake time: FakeClock and SyncClock zones | `packages/twk_test/lib/src/fake_clock.dart:46`, `tool/alloc/lib/sync_clock.dart:24` | keep | — |
| 8 | the tester's stderr through `IOOverrides` | `packages/twk_test/lib/src/tester.dart:121` → `packages/twk_core/lib/src/platform/io.dart:43` (via `packages/twk_core/lib/src/app.dart:971`) | keep | — |
| 9 | test seams kept in statics: `DebugAids.runEditor`, `AppBinding.postEvent` | the tests → `app_binding.dart:1655`, `:668` | keep | — |
| 10 | the service extensions' registry of running apps | `app_binding.dart:684-685` | keep | — |
| 11 | `TWK_UPDATE_GOLDENS` and `updateScreenFilesOverride` | the shell → `packages/twk_test/lib/src/screen_file.dart:24, 33` | keep | — |
| 12 | state kept in an `Expando` beside the object it belongs to | `framework.dart:199`, `gesture_detector.dart:266`, `terminal_status.dart:59`, `packages/twk_core/lib/src/render/text.dart:184-185` | keep | — |
| 13 | statics private to one file, set and read in that file | `hooks/hook.dart:228`, `provider/inherited_provider.dart:479`, `framework.dart:1007, 2685`, `packages/twk_core/lib/src/render/object.dart:1517-1519` | keep | — |
| 14 | Symbol keys `#pointerShape`, `#progress` | `terminal_status.dart:155-156` → `TerminalStateBackend.setTerminalState` (`packages/twk_core/lib/src/terminal/terminal.dart:631`) | keep | — |
| 15 | counters a test reads: `TextBuffer.joins`, `LogView.renderVisits`, `comparedUnits`, `qrEncodes` | lib increments, tests read | keep | — |
| 16 | the gallery pages' top-level state | `packages/gallery/lib/src/pages/app.dart:1059`, `rich.dart:1137`, `overlays.dart:764, 968-969, 1254-1255` | keep (app code) | — |

Paths without a package are under `packages/twk/lib/src/` in rows 9, 10,
12 and 13.

## 1. The `TWK_*` environment is read inside the app and the binding

**What flows.** The developer's shell decides how every app made by
`TwkApp` or `AppBinding` behaves, a test's app too:

- `TWK_DEBUG` is read twice. The core reads it at `packages/twk_core/lib/src/app.dart:38-39`
  (`_debugging`). From there it sets the defaults of `framesInRow`,
  `timeline` and `serveLogs` (`:199-201`), and the owner's
  `debugRepaintRainbow` and `debugRelayoutHighlight` (`:232-233`), which
  have no parameter at all. twk reads it again in `DebugAids._`
  (`app_binding.dart:1189`): `overlay` and `console` are turned on there,
  and the debug keys too.
- `TWK_SCREEN_READER`: `AppBinding._readerAsked` (`app_binding.dart:298`)
  is the default of `screenReader` in the binding's constructor (`:292`)
  and in `runApp` (`:167`).
- `TWK_LOG`: the default `LogSink` of `TwkApp` (`packages/twk_core/lib/src/app.dart:196`).
- `TWK_EDITOR`, `VISUAL`, `EDITOR`: `editorEnvironment ?? environment`
  (`app_binding.dart:1687`). A test replaces that environment through the
  static `DebugAids.editorEnvironment` (`:1666`).

**Who sets it, who reads it.** Only the edges should set these: the
person's shell, and `twk run`, which passes `TWK_DEBUG` to the program it
runs (`packages/twk_dev/lib/src/run.dart:186, 202`). The parts deep in the
stack read them anyway. `TwkTester._start` makes its binding
(`packages/twk_test/lib/src/tester.dart:324-333`) without a
`screenReader`, and it cannot pass the debug flags, because `AppBinding`
has no parameter for them. `tool/alloc/lib/app_run.dart:33` is in the same
position.

**What breaks.** A shell that exports one of these changes what every
`testTwk` test shows. Run on `packages/twk_test/test/tester_test.dart` (28
tests, all passing in a clean shell):

| exported | result |
| --- | --- |
| nothing | +28 |
| `TWK_SCREEN_READER=1` | +25 -3 |
| `TWK_DEBUG=frames` | +4 -24 (`Bad state: raw control byte 0xa` from the emulator) |
| `TWK_DEBUG=overlay` | +15 -13 |
| `TWK_DEBUG=timeline` | +28 |

With `TWK_DEBUG=logs`, a test's app serves its log on a socket and writes
an address file. Every failure points at the test, not at the shell.

The two packages also split the flag names by hand. twk lists the core's
names in `_coreNames` (`app_binding.dart:1220`, "what the core's TwkApp
reads of TWK_DEBUG besides"). A name the core learns later makes twk log
a false warning, "TWK_DEBUG names nothing it knows", until someone adds
it there too.

**Explicit form.** Read the environment at the edge and pass it in:

- `TwkApp({Map<String, String>? environment})`: its debug defaults and
  `TWK_LOG` come from that map (null meaning the process's, read in the
  constructor once).
- `AppBinding({Map<String, String>? environment})`: it gives that map to
  its `TwkApp`, and reads `TWK_SCREEN_READER`, `TWK_DEBUG` and the
  editor's variables from it. This replaces the static `editorEnvironment`.
- `runApp` and the console's session (`packages/twk/lib/src/cli/session.dart:44`)
  pass nothing, so a real program keeps reading the process's
  environment.
- `TwkTester` and `tool/alloc` pass `const {}`. A test that wants a debug
  aid turns it on through `AppBinding.debug`, as it can now.

A better variant: the core parses `TWK_DEBUG` once into a value, and
twk's `DebugAids` reads the names it handles from that value, instead of
`_coreNames` copying the core's list.

**Cost.** Two optional named parameters, so no public API breaks.
`AppBinding(` is called in 4 places outside tests (`runApp`, the tester,
the console's session, `tool/alloc`) and 18 times in tests; only the tester
and alloc need a change, one line each. `DebugAids.editorEnvironment`,
which is `@visibleForTesting`, goes: 4 lines of
`packages/twk/test/debug/editor_test.dart` pass the map to the binding
instead.

**Done in 34df707.** `TwkApp` and `AppBinding` take
`Map<String, String>? environment`, null for the process's.
`TwkApp` reads it once, in its constructor. It keeps the map as
`TwkApp.environment` and the parsed `TWK_DEBUG` as `TwkApp.debugNames`.
`TwkApp.debugNamesRead` lists the names the core reads.
`AppBinding` gives the map to its `TwkApp`. It reads
`TWK_SCREEN_READER`, the rest of `TWK_DEBUG` and the editor's variables
from `twkApp.environment`. `DebugAids` takes `twkApp.debugNames`, and it
counts `TwkApp.debugNamesRead` as known, so `_coreNames` is gone. Before,
that list lacked `rainbow` and `relayout`; it did not warn only because
twk handles both names itself. `DebugAids.editorEnvironment` is gone.
`TwkTester.pumpWidget` takes `environment`, `const {}` by default, and
passes it to the binding. The editor tests pass theirs there.
`tool/alloc` passes `const {}`, and so does twk's binding test harness.
`runApp` and the console's session pass nothing. The probe after: tester_test
(and shot_test) pass in a clean shell and under each variable of the
table, `TWK_DEBUG=logs` too. Before, `TWK_DEBUG=logs` gave +26 -2.

Left as they are: the core's own tests that make a `TwkApp` directly
(`test/app_test.dart`, `test/terminal/`, `test/inline/` and others) give
no `environment`, so they still read the process's.

## 2. The library's own warnings reach the log through `log()`'s zone

**What flows.** The core's render objects report overflow with `log()`
in debug builds: `RenderFlex` (`packages/twk_core/lib/src/render/flex.dart:444`),
`RenderWrap` (`wrap.dart:347`) and `RenderGrid` (`grid.dart:452`), each
inside an `assert`. `log()` looks up its sink as the zone value
`logSinkKey` (`packages/twk_core/lib/src/log.dart:273`). Only `TwkApp.run` sets that value
(`packages/twk_core/lib/src/app.dart:464`). Outside it, the record is printed.

**Who sets it, who reads it.** A render tree laid out outside
`TwkApp.run` has no one to set it. the console's `widgetLines`
(`packages/twk/lib/src/cli/lines.dart:111-150`) does this whenever
`Cli.show` writes a widget outside the interactive mode
(`cli.dart:383`). The console could not route the record if it tried:
`logSinkKey` is not exported (`lib/twk_core.dart:34` shows only
`LogLevel, LogRecord, LogSink, log`).

**What breaks.** The warning lands in the program's output. A probe under
`Cli.run(..., quiet: true, input: false)`, with asserts on (as `dart test`
and debug runs have them), showed
`SizedBox(height: 2, child: Column(children: [a, b, c]))`. Its stdout was:

```
13:30:28.601 warning A RenderFlex overflowed by 1 row on the bottom.
    a
    b
```

The line went to stdout rather than the error channel, came out despite
`quiet`, and did not have the Cli's style. A test of the program on a
fake `CliTerminal` never sees it, because the line goes to the real
stdout. The binding already has the same hole: `DebugAids._` writes to
`twkApp.logs` directly because "the binding is made outside the app's
zone" (`app_binding.dart:1204`).

**Explicit form.** The render tree's owner carries the route, as it
already carries `onError` (`packages/twk_core/lib/src/render/pipeline.dart:53-59`, set by
the binding at `app_binding.dart:293`). For example,
`PipelineOwner.onLog: void Function(LogRecord)?`:

- the three render objects call it through their `owner`, and still call
  `log()` where it is unset;
- `TwkApp` sets it to `logs.add` where it makes its owner
  (`packages/twk_core/lib/src/app.dart:228`);
- `widgetLines` takes it as a parameter, and `Cli.show` passes the Cli's
  `warn`/`detail` by level.

`log()` itself does not change for app code (item 4).

**Cost.** One nullable field on `PipelineOwner`, so no break. Three
calls in the core change. One line in `TwkApp`; one parameter and one line
in `widgetLines`. twk's own 10 `log()` calls in `app_binding.dart` already
run inside the app's zone and need no change, though they could use
`twkApp.logs` directly.

## 3. Window title and notifications go through a type switch on two core classes

**What flows.** twk needs two things from the terminal that the core
offers only on concrete classes. One is the window title:
`TerminalStatus._showTitle` (`packages/twk/lib/src/binding/terminal_status.dart:180-185`)
calls `Terminal.setTitle`, or writes `titleSequence` to a
`HeadlessTerminal`. The other is desktop notifications:
`AppBinding.notify` (`app_binding.dart:521-526`) calls `Terminal.notify`
or `HeadlessTerminal.notify`, two methods with the same signature. Any
other backend gets nothing. Every other capability twk uses goes through
an interface the core declares: `SuspendableBackend`,
`TerminalStateBackend` and `MouseTrackingBackend`
(`packages/twk_core/lib/src/terminal/terminal.dart:606, 621, 647`), which twk checks at
`terminal_status.dart:69-72` and `app_binding.dart:965`.

**What breaks.** A backend that wraps a `Terminal` loses the title and
the notifications without a word, and has no way to forward them. The
gallery has one: `_Typing` (`packages/gallery/bin/gallery.dart:86`)
wraps `Terminal.open(...)` (`:42-43`) whenever a route types keys. Under
it, the gallery's `WindowTitle` (`packages/gallery/lib/gallery.dart:27`)
and the App page's `notify` (`pages/app.dart:1744`) do nothing.
twk_test's `VtTerminal` (`packages/twk_test/lib/vt_terminal.dart:29`) is
another. `packages/twk/test/binding/notify_test.dart:87` pins "nothing on
a terminal of another kind" as the behaviour. A new core backend (the web
one's link is wrapped in a `Terminal`, so it is fine today) would have to
be added to both switches in another package.

**Explicit form.** A core interface for the two, for example
`WindowBackend { void setTitle(String title); void notify(String title,
String body); }`. `Terminal` implements it as it does now.
`HeadlessTerminal` gains a `setTitle` that writes `titleSequence` (the
logic that is in twk's switch today). twk's two switches become
`case final WindowBackend t`. A wrapper such as `_Typing`, or
`VtTerminal`, can implement it and forward.

Another option for the title alone: `setTerminalState(key,
titleSequence(t), popTitle)`, the push and restore `Terminal.setTitle`
does by hand (`terminal.dart:1690-1701`).

**Cost.** One public interface added to the core, declared by `Terminal`
and `HeadlessTerminal`, plus one method on `HeadlessTerminal`. twk's two
switches change. No caller changes, because `AppBinding.notify` and
`WindowTitle` keep their signatures. `notify_test.dart:87` stays as it is
for a backend without the interface.

## The kept ones, and why the ambient form is right there

- **4, `log()` for app code.** `log()` is a top-level function like
  `print`, called with no handle. The same zone that catches `print`
  (`ZoneSpecification(print: _print)`, `packages/twk_core/lib/src/app.dart:465`) catches
  its records, which is the point. The key is private to the core
  (`log.dart:125`, not exported). Only the library's own calls are a
  link between parts (item 2).
- **5, `Cli.current`.** `Cli.run` already hands the body its `cli`
  (`cli.dart:147-150, 165-176`). Nothing in the console reads `Cli.current`
  (0 reads in `lib/`; 4 lines in `test/cli_test.dart`; 11 doc-example
  lines). It is an accessor for a program's own helpers, as `log()` is.
  Outside a run it falls back to a `Cli` on process stdio made at first
  use (`_default ??= Cli()`, `:97`) and never closed. The console's reference page
  warns about that (`:142, 219`), and it is a documented convenience
  (the `Logger()` → `Cli.current` row, `:398`), not a hidden swap.
- **6, `runningTester`.** It exists so that `expect(find.text('x'),
  findsOneWidget)` works. A `Matcher` gets no tester, and this is
  package:test's convention (flutter_test's `find` works the same way).
  Outside `testTwk`, `Finder.evaluate` throws a `StateError`
  (`finders.dart:88-92`) rather than finding nothing.
- **7, FakeClock and SyncClock.** Replacing timers and microtasks is what
  a zone is for (fake_async does the same). Neither holds a zone value
  any more. The app's clock is passed explicitly
  (`tester.dart:333`, `clock: clock.stopwatch`).
- **8, `IOOverrides` for stderr.** `TwkTester.stderrLines` is "what the
  app wrote to stderr". That includes the app's own `stderr.writeln`,
  which only an override catches. The core's report at exit goes the same
  way. A parameter would catch only the core's.
- **9, `DebugAids.runEditor` (`app_binding.dart:1655`) and
  `AppBinding.postEvent` (`:668`).** These stand in for process-wide
  things: spawning the editor and the VM service's event stream. They are
  `@visibleForTesting`, and the tests put them back in `tearDown`
  (`editor_test.dart:68-71`, `service_extensions_test.dart:522`,
  `hot_reload_test.dart:185`). `editorEnvironment` goes with item 1.
- **10, `_runningApps` and `_registered` (`app_binding.dart:684-685`).**
  VM service extensions are registered once per isolate, so the "app that
  started last" registry is global because the service is.
- **11, `TWK_UPDATE_GOLDENS`.** package:test passes no flags of ours to
  a test. An environment variable is how golden files are refreshed
  (`TWK_UPDATE_GOLDENS=1 dart test`), and `updateScreenFilesOverride` is
  its test seam.
- **12, Expandos.** These are `GlobalKey._owners`, `_Arena._arenas`,
  `TerminalStatus._ofApp` and `PipelineOwner.textOrder` (an extension
  over `_textOrders`). Each keeps the state of one object beside it, in
  the same package, read through a visible API (`currentContext`,
  `TerminalStatus.of`, `owner.textOrder`). `_anyVisual`
  (`text.dart:185`) is a fast-path latch: once true, paragraphs read the
  Expando. It changes no result.
- **13, file-private statics.** `HookElement._current` is how a hook
  finds its element, which is what a hooks API is. `_inSelector` is an
  assert guard. `_attachingAt`, `_visiting` and `_cutTop/_cutBottom/_cutAt`
  pass a value to a tear-off without a closure per element, which is a
  speed choice inside one walk.
- **14, Symbol keys.** The key belongs to the caller of
  `setTerminalState`. Nothing else reads it, so it is not a link. The only
  risk is two callers picking the same Symbol. `Object()`, as the core
  uses for its own key (`terminal.dart:1242`), would remove even that, as
  a one-line choice.
- **15, counters.** The library only increments them and never reads
  them, so a test reading them cannot change behaviour.
  `TextBuffer.joins` and `LogView.renderVisits` are
  `@visibleForTesting`. `comparedUnits` (twk_rich `src/`, not exported)
  and `qrEncodes` (the gallery) are top-level, without the annotation.
- **16, the gallery pages.** State of a demo page kept across visits of
  its route, which its Code tab reads, all in one file of an app. It is
  not a library link.
