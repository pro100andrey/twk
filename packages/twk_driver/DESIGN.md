# twk_driver: driving a live twk app from outside

twk_driver runs a twk app as a real process in a real pseudo-terminal. It
types real bytes into the app, reads the screen through a terminal
emulator, and reads the widget tree through the app's VM service. Tests,
coding agents (`twk mcp`), `twk tape` and the VS Code extension all use
it. It covers the half of testing that `testTwk` cannot reach: the real
`main`, the real terminal, the exit code, and the terminal handed back
when the app ends.

This document was written by task `drv-design` (2026-11-12). It is based
on a read of the code at `5e520a4`, with file:line references to that
commit. It is the design the later slices build on (part 10). Nothing
described here is built yet. The user made the decisions in part 1;
everything else is this document's proposal, and a slice that finds it
wrong says so and changes it here.

## 1. Decisions

Made with the user on 2026-11-12, after a review of precedents (part 11):

1. **Time is a port of the core, and the driven clock lives in twk.**
   twk_core gets a `Clock` interface: monotonic `elapsed`, one-shot and
   periodic timers. This is the shape of .NET's `TimeProvider`, not of
   `java.time.Clock`, which only tells the time. twk_core also gets a
   system implementation. `TwkApp` and `AppBinding` take the clock
   explicitly, replacing today's `Stopwatch` and the timers they make
   through a captured zone. The clock the driver moves, `DrivenClock`,
   is a runtime capability of twk, because `runApp` uses it in the
   app's own process. That makes it like tokio's `time::pause` or Go's
   `synctest` rather than like a test fake. twk_test's `FakeClock` is
   rebuilt on `DrivenClock`, so there is one implementation of timer
   order and elapse.
2. **Driven mode is turned on at start by `TWK_DRIVEN`.** `runApp`
   reads it before it makes a timer. Its value is `1`, or an ISO-8601
   instant that becomes the app's start time. There is no generated
   entry point and no install over the VM service after start: every
   precedent installs the clock before the app's code runs.
3. **Layers: `twk_test → twk_driver ← twk_dev`.** twk_driver does not
   depend on package:test. `driverTest` lives in
   `package:twk_test/driver.dart`. `twk mcp` is a thin layer in twk_dev.
   twk_dev's VM service client moves into twk_driver.
4. **Finders are data, evaluated in the app by `ext.twk.find`.** The
   matching code lives in twk, and twk_test's `find.*` uses the same
   code in-process.
5. **`twk mcp` speaks JSON-RPC of its own** over stdio. No new
   dependency (`dart_mcp` is not taken).
6. **`waitFor` moves driven time itself, within a budget.** A quiet
   app whose condition is false fails at once as "never". Waiting on
   real IO needs an explicit guard (part 4.6).

## 2. Layers, ports, adapters

```
 front ends     twk_test driver.dart   twk mcp   twk tape   VS Code (reads traces)
                         \              |          /
 driver core    Session · CausalSync · ClockControl · Finders (JSON) · TapCheck
 (twk_driver)   · Trace · FailureReport
                         |              |              |             |
 ports          TerminalPort       ScreenPort     AppServicePort   ProcessPort
                (pty bytes,        (feed, cells,  (ext.twk.*,      (spawn, signal,
                 resize, oflag)     encode keys)   events)          exit code)
                         |              |              |             |
 adapters       twk_term Pty   twk_term TerminalEmulator  VmAppClient   Pty spawn of
                               (+ twk_test Vt checker)    (vm_service)  `dart run` / kernel
                         \______ bytes through the pty ___/   JSON over the VM service
 app            AppBinding: ext.twk.* (+ find, hitTest, clock), twk.frame / twk.input,
                DrivenClock under TWK_DRIVEN; TwkApp/Terminal: byte counters
```

**The core is pure Dart.** It sees only the ports. Each port has a fake
for the core's unit tests, and the adapters are tested in process tests
(`@Tags(['process'])`).

- **TerminalPort.** Owns the pty master: write bytes, resize (TIOCSWINSZ
  plus SIGWINCH, as `Pty.resize` does), and the stream of output. Its
  adapter is twk_term's `Pty` (`packages/twk_term/lib/src/pty/pty.dart`;
  `Pty.start` at :192). It also reports the slave's output flags (part
  3.4). Pty is POSIX only, so the driver runs on Linux and macOS.
- **ScreenPort.** Takes the output bytes and keeps the screen's cells. It
  encodes keys, the mouse and pastes in the modes the app has turned on,
  and answers the app's queries: `TerminalEmulator.sendKey`, `sendMouse`,
  `sendPaste` (`packages/twk_term/lib/src/emulator/emulator.dart:800-851`).
  The emulator's answers are part of what the driver writes and count
  as input bytes (part 3). A terminal profile (the extension's presets:
  colours, answers, kitty keyboard, synchronized output) configures the
  emulator for a session. `driverTest` feeds the same bytes to twk_test's
  strict `Vt` too, as a checker: an unknown sequence fails the test, as
  the e2e checks do. The checker is an optional port, so twk_driver never
  imports twk_test.
- **AppServicePort.** Calls `ext.twk.*` and streams the Extension
  events. Its adapter is `VmAppClient`, moved from
  `packages/twk_dev/lib/src/app_client.dart` into twk_driver. twk_dev's
  `twk inspect` and `twk run` take it from there, so there is still one
  client.
- **ProcessPort.** Spawns the program in the pty with
  `--enable-vm-service=0 --write-service-info=<file>`, reads the URI as
  `twk run` does (`packages/twk_dev/lib/src/run.dart:335-387`), and
  reports the exit code. A kernel cache like twk_test's
  `compiledProgram` (`packages/twk_test/lib/src/program.dart:73-142`)
  moves into twk_driver too, and twk_test re-exports it. compiledProgram
  depends on package:test only for `fail`, which becomes the driver's
  own error.

**Package graph.** twk_core is the Clock port plus the counters. twk adds
DrivenClock, the driven `runApp`, the new extensions and the finder
data. twk_term (already on twk), plus vm_service, gives twk_driver.
twk_test and twk_dev both depend on twk_driver. twk_dev still does not
depend on twk_test. The cost is that twk_test now pulls in vm_service
and twk_term transitively. `package:twk_test/driver.dart` is a library
of its own, so `testTwk` users do not load it.

## 3. Causal sync: the frame that consumed the input

The driver never waits for "idle". It waits for the frame that the app
itself says was built after the input was read.

### 3.1 Counters (twk_core)

A new optional backend interface, `CountingBackend`, follows the pattern
of `SuspendableBackend` and the others in
`packages/twk_core/lib/src/terminal/terminal.dart` (from :755). `Terminal`
and `HeadlessTerminal` implement it.

- **`bytesRead`.** Bytes taken from `link.input` whose events have been
  delivered. Input has one subscription (`terminal.dart:1110`) and two
  data handlers: the probe's (around :1309) and the session's `_onBytes`
  (:1852). Both count. A byte the parser still holds (a lone ESC waiting
  for its timeout, an open paste) is counted when the parse that
  resolves it delivers. So the probe's answers are counted as well.
- **`inputPending`.** True while the parser holds bytes
  (`InputParser.hasPending`, `inPaste`).
- **`bytesWritten`.** Bytes accepted for the tty: the probe's direct
  `link.add` calls (:1421, :1432), plus everything given to the
  `Outbox`. They are counted when the Outbox accepts them (`add` and
  `frame` in `terminal/outbox.dart`), not when they reach `link.add`.
  The difference matters: the Outbox holds a write back while a flush
  runs (`_queued`), so a frame written then would otherwise be missed at
  the moment the frame is posted. Every accepted byte reaches the tty
  without a further flush.

Each counter costs one integer add per read or write call, not per
byte. This is on the frame path, so `bench` is owed (part 10).

### 3.2 What the app posts (twk)

All events are gated twice: on `ext.twk.flags frameEvents=true` (a new
flag, like `treeEvents`) and on `extensionStreamHasListener`
(`app_binding.dart:908-920`). With either off, the cost is one test of
the flag.

**`twk.frame`** is posted from `AppBinding._afterPresent`
(`app_binding.dart:1296`). That runs for every frame, including one
whose `screen.render()` wrote nothing (`app.dart:1277-1293`). Payload:

```json
{"version": 1, "frame": 41, "drawn": true,
 "inputRead": 1093, "outputWritten": 58211, "inputPending": false,
 "scheduled": false, "time": 3016000, "nextDue": null}
```

- `frame` counts the frames run, drawn or not.
- `inputRead` is `bytesRead` as it was when this frame's build began
  (`_beforeLayout`, `app_binding.dart:1223`). There is one exception:
  in the first frame the input subscription is still paused
  (`app.dart:626`, resumed at :1255 after the build), so the first frame
  reports only the bytes the probe read.
- `outputWritten` is `bytesWritten` after this frame's write.
- `scheduled` is true when another frame is already due: `_again`,
  `owner.hasWork`, or a pending commit (`app.dart:1310`). TwkApp exposes
  this as a public getter; today `_scheduled`, `_inFrame` and `_again`
  are private (`app.dart:430-433`).
- `time` is the app clock in µs. `nextDue` is the next timer of the
  driven clock, and is null when the app is not driven.

**`twk.input`** acknowledges input that does not, or does not yet, lead
to a frame. A key that changes nothing never calls `requestFrame`, so
without this event the driver would wait forever. After a read's events
are dispatched, TwkApp arms one root-zone `Timer.run`. It fires after
the microtask queue has drained, so every event of every read so far has
been dispatched. It then posts the same payload as `twk.frame`, with
`frame` set to the last frame run. Several reads in one turn of the
event loop get one post.

The `inputRead` in both events is exact for one reason: the input
events reach TwkApp through an asynchronous `StreamController`
(`terminal.dart:907`), so they are dispatched in microtasks. A frame
starts from a timer, which runs only after the microtask queue has
drained. So at a frame's start, every byte read has been dispatched,
apart from what the parser holds or the first frame's pause keeps back.

### 3.3 `press()`

1. The driver writes the key's bytes, encoded by the ScreenPort. Its
   running total of written bytes becomes `W`, and includes the
   emulator's answers.
2. It waits for a `twk.input` or `twk.frame` event with
   `inputRead >= W` and `!inputPending`. A lone ESC stays pending for
   the escape timeout (30 ms, or 500 ms for a sequence that was cut,
   `terminal.dart:1860-1873`). That timer runs on real time, even when
   the app is driven (part 4.4).
3. If that event is a `twk.frame`, it is the input's frame. If it is a
   `twk.input` with `scheduled`, the driver waits for the next
   `twk.frame` with `inputRead >= W`. When the app is driven, the driver
   first moves the clock to `nextDue`: input frames are spaced by
   `1/maxInputFps`, 8.3 ms of app time at most (`app.dart:1205-1231`).
   This is the only time `press` moves the clock. If the event is a
   `twk.input` without `scheduled`, nothing will be drawn for the input.
4. The driver feeds the emulator until it has taken `outputWritten`
   bytes of the app's output (part 3.4). Then it returns the frame
   number and the screen.

The output is buffered, so the driver can stop the emulator at any
frame's `outputWritten`. It sees every frame's screen, including a state
that lasts one frame, even when the app runs on real time. Nothing is
polled, so nothing is missed between polls.

A corrective frame that the input's frame requests is not part of
`press`. One example is the focus settling a frame late (the KeyHintsBar
lag recorded in tm). `waitFor` covers it, because it checks every frame.

### 3.4 Line discipline: why the driver counts LFs

Dart's raw mode leaves the tty's output processing on: `lineMode` and
`echoMode` change only lflag, and twk's `PosixTty.enterRaw` changes only
iflag and lflag (`packages/twk_core/lib/src/terminal/posix_tty.dart:108-124`).
So OPOST|ONLCR stays set, and every LF the app writes reaches the pty
master as CR LF. The presenter does write bare LFs: inline line feeds
(`presenter.dart:1394`, :1123), and plain output (`app.dart:1029`).

The driver therefore counts the app's bytes as
`received - LFs received while ONLCR is set`. The inserted CR always
comes right before its LF. The driver sets the slave's termios itself
before it spawns the app: OPOST and ONLCR on (what a real terminal
gives), TAB0, no OCRNL, ONOCR or ONLRET. Nothing in twk changes oflag.
`drv-frame-event`'s process test holds the two counts equal over inline,
fullscreen and plain apps.

Input needs no such correction. In non-canonical mode with ISIG, IXON
and ICRNL cleared (by `enterRaw`), the line discipline passes bytes
through unchanged. The driver writes nothing until it has seen the
probe's queries, which come after `enterRaw` (`terminal.dart:1104-1106`),
so no key goes in while the tty is still cooked.

## 4. Time

### 4.1 The port (twk_core)

```dart
abstract interface class Clock {
  Duration get elapsed;                       // monotonic, since the clock began
  Timer timer(Duration after, void Function() callback);
  Timer periodic(Duration every, void Function(Timer) callback);
}
final class SystemClock implements Clock { ... }  // Stopwatch + Zone timers
```

- `TwkApp({Clock? clock})` replaces `Stopwatch? clock` (`app.dart:223`,
  :258). `requestFrame` calls `clock.timer(wait, _zone.bindCallback(_runFrame))`
  instead of `_zone.createTimer` (:1227), so frames still run in the
  app's zone, and its errors still go to `runZonedGuarded`.
- `AppBinding` takes the same clock. `startTimer` and `startPeriodic`
  (`app_binding.dart:416-422`) and `_dueTimer` (:1199) go through it.
  `now()` (:726) is `startTime + clock.elapsed`, and a driven app always
  has a `startTime`.
- `_statsClock` (`app.dart:448`) stays a real `Stopwatch`: it measures
  cost, not app time. Log records keep `DateTime.now()`.
- This is a breaking change to `clock:` and a change to the frame path.
  Early in the project, breaking is acceptable; `bench` is owed.

### 4.2 DrivenClock (twk)

`DrivenClock implements Clock`:

- a queue of timers ordered by due time, then by creation order;
- `advance(by)`, `advanceTo(t)` and `advanceToNext()`;
- `pendingTimers` and `nextDue`;
- `describeTimers()`, which gives each timer's due time, whether it is
  periodic, and where it was made (the creation stack trace, as
  FakeClock records it at `fake_clock.dart:332`);
- a cap on how many timers one advance may fire, as a guard against a
  periodic timer firing in a loop (fake_async and Jest do the same).

It does not queue microtasks: in the app's process they run as they
normally do. twk_test's `FakeClock` becomes `DrivenClock`, plus its
zone, plus the microtask queue that tests need for a synchronous
`elapse`. Its public API (`run`, `elapse`, `elapseUntil`,
`pendingTimers`, `describeTimers`) stays. `stopwatch` gives way to
`clock`. `TestFailure` stays in twk_test's wrapper.

### 4.3 `TWK_DRIVEN` (runApp)

When `runApp` is given no `clock:` and `TWK_DRIVEN` is set, it does the
following:

1. Opens the terminal on real time, as today (`app_binding.dart:196-205`).
2. Makes a `DrivenClock`. The start time is the variable's ISO-8601
   instant, or the real time at start for `1`.
3. Runs the binding and the app in a zone forked from the current one
   whose `createTimer` and `createPeriodicTimer` go to that clock. This
   zone adapter is how a raw `Timer` or `Future.delayed` in the app's
   own code is driven as well. The adapter is made from the clock that
   `runApp` holds, and the binding is given the clock as an argument,
   so no zone value carries it anywhere.
4. Registers `ext.twk.clock` (part 4.5).

In product mode the variable is ignored. Without a VM service,
`runApp` throws at start: nothing could move the clock. The variable is
read by `runApp` only, and `AppBinding`'s constructor never reads it. An
explicit `clock:` wins over it.

### 4.4 What stays on real time

All of it is I/O, not app time:

- the terminal's own timers: the probe's timeout (`terminal.dart:1424`),
  the late probe (:1843), the late cursor (:2075), escape and paste
  (:1858, :1872). The terminal is opened before the driven zone exists,
  so they are made in its zone. The late cursor timer is the exception:
  it is created on resume, in the app's zone. `drv-clock` moves it to
  the terminal's own zone, captured at open;
- `posix_output`'s drain retry (`posix_output.dart:141`), which today
  is created in the writer's zone, that is, the frame's. Under the
  driven zone it would wait for the clock while the frame waits on the
  flush. `drv-clock` makes it use the zone captured when the link is
  made;
- `tailFile` (`packages/twk/lib/src/platform/io.dart:254`, :289, both
  in `Zone.root`), the log server's token timeout, and the socket
  terminal's hello timeout.

Known escapes that remain:

- **Timers made in `main` before `runApp`.** The precedents agree on
  this one: install comes first or the clock is not in charge.
  Documented.
- **`ProgressTracker`'s default `Stopwatch`**
  (`packages/twk/lib/src/animation/progress_list.dart:141`; the tm
  reflection on it). `drv-clock` gives it the binding's clock.
- **The terminal status refresh** (`terminal.dart:1730`, a 10 s
  periodic timer while progress shows). It is the app's timer and is
  driven like any other.

### 4.5 `ext.twk.clock`

Params: `op=status|advance|advanceTo|next`, `by` / `to` in µs, and
`describe=true`.

Answer:

```json
{"version": 1, "driven": true, "time": 3016000, "timers": 2,
 "nextDue": 3033333, "quiet": false, "frame": 41,
 "inputRead": 1093, "outputWritten": 58211, "inputPending": false,
 "describe": [{"due": 3033333, "periodic": false, "created": "lib/spinner.dart:40"}]}
```

`advance` does the following:

- fires the timers in due order up to the target;
- after each one, awaits a root-zone zero timer, so the microtasks the
  timer started run to the end;
- waits for a frame that is running and awaiting its flush to end
  (TwkApp exposes this as a future);
- leaves the app's time at the target.

A second call while one runs is refused. The handlers run in
`Zone.root` (`app_binding.dart:892-897`). Each fired timer runs its
callback in the zone where it was made.

### 4.6 Quiet, `waitFor` and "never"

`ext.twk.clock status` answers between tasks of the event loop, so the
microtask queue is empty when it answers. The app is quiet when all of
these hold:

- the clock has no timers (frame timers included);
- nothing is pending in the input parser;
- no frame is scheduled or running;
- on the driver's side, `inputRead` equals the bytes the driver wrote,
  and the emulator has taken `outputWritten` bytes.

An animation keeps a timer going: a `Ticker` asks for every frame
(`ticker.dart:162-178`), and `Steps` arms `_dueTimer`. So an app that
animates is never quiet, and that is correct.

`waitFor(condition, {budget = 10 s of app time, io})` works as follows:

1. It checks the condition on every frame's screen and, when the
   condition needs the tree, on `ext.twk.find`. A match ends the wait.
2. When the app is driven:
   - **not quiet:** `advance next`, and go on until the time advanced
     passes `budget`. The failure then is "not within 10 s of app
     time", followed by `describeTimers`;
   - **quiet:** fail at once with "never". The failure names the frame
     and the closest line or node.
3. When the app is not driven, it waits for frames on real time up to
   `io`, which is then required.

Real I/O in flight (a socket, a file, a process) is invisible to the
clock and to the zone; Dart has no API for it. A quiet app that is
waiting for such I/O would get a false "never". So a wait that involves
I/O passes `io: Duration`. Then a quiet app is waited on in real time
for up to `io`, for frames that might still arrive, before the wait
fails. Go treats such I/O as not "durably blocked", and CDP has
`pauseIfNetworkFetchesPending`. twk asks the caller instead, because the
app cannot tell. Every "never" failure says that the app was quiet and
that I/O cannot be seen, so a false "never" explains itself.

## 5. Finders as data (`ext.twk.find`)

The finders are values in twk: `toJson`, `fromJson`, and an `evaluate`
over the element tree. twk_test's `find.*`
(`packages/twk_test/lib/src/finders.dart`) builds these values, and in
`testTwk` evaluates them in-process with the same code. Over the wire,
`ext.twk.find` evaluates them in the app on the live widgets. The tree
JSON is not enough: it cuts text off at 24 columns
(`packages/twk_core/lib/src/render/diagnostics.dart:304-317`) and gives
keys only by `toString`.

| JSON | matches |
|---|---|
| `{"text": "Save"}` | a `Text` whose whole text (data or joined spans) is equal |
| `{"textContaining": "Sav"}` | substring |
| `{"textMatches": {"source": "^Sa", "caseSensitive": true}}` | RegExp |
| `{"type": "Button"}` | `runtimeType` by name, type arguments ignored |
| `{"key": {"value": "save"}}`, `{"key": {"value": 3}}` | `ValueKey<String>` / `ValueKey<int>` by `==` |
| `{"node": 44}` | a node id from an earlier answer; refused if it left the tree |
| `{"descendant": F, "of": G, "matchRoot": false}`, `{"ancestor": F, "of": G}` | as twk_test's |
| `{"at": 2, "of": F}`, `{"first": F}`, `{"last": F}` | index |

- Other keys (`ObjectKey`, `GlobalKey`, `UniqueKey`) cannot cross the
  wire. They are reached by `node`.
- `byWidgetPredicate` stays in-process only. Its `toJson` throws an
  error that names it and suggests the data kinds.
- **Strict by default.** An action on a finder that matches more than
  one node fails with the count and the first five matches. `first`,
  `last` and `at` have to be explicit, as in Playwright, Detox and
  Espresso.

Answer:

```json
{"version": 1, "frame": 41, "count": 1,
 "matches": [{"id": 44, "type": "Button", "key": null, "text": "Save",
              "rect": {"x": 40, "y": 9, "width": 8, "height": 1},
              "shown": {"x": 40, "y": 9, "width": 8, "height": 1}}]}
```

`shown` is the rectangle clipped by every ancestor. It is the private
`_shownOf` (`packages/twk/lib/src/debug/inspector.dart:303-324`) made
public, and null when no cell shows. `ext.twk.layout` gets `shown` too.

## 6. The tap check (`ext.twk.hitTest`)

`ext.twk.select` already runs the real hit test
(`inspector.dart:165-195`, through `PipelineOwner.hitTest`). It answers
a different question, though: which deepest element owns a render
object there. A click goes somewhere else:

- to the `RenderListener`s in the result (`mouse.dart:715-796`);
- not to `listenOver` listeners, which are not in the result at all
  (`mouse.dart:1132-1166`);
- not even into the tree when the console panel or the pick mode takes
  the event first (`app_binding.dart:1485`, :1497).

So there is a new method, `MouseTracker.targetsAt(x, y)`. It runs the
hit test and reads the listeners and their callbacks
(`_listenersHit`, `_callbackFor`, `_absorbed`). It calls nothing and
fires no enter or exit: `dispatch` calls `_moveTo`, so it cannot be
reused. `ext.twk.hitTest` is built on it.

Params: `x`, `y`, and `cursorY` as `ext.twk.select` takes it.

```json
{"version": 1, "frame": 41, "cell": {"x": 44, "y": 9}, "takenBy": null,
 "path": [{"id": 57, "type": "Text", "render": 58}, {"id": 51, "type": "Dialog", "render": 52}],
 "listeners": [{"render": 53, "type": "GestureDetector", "callbacks": ["down", "up"]}],
 "absorbedBy": null}
```

`path` lists the elements that own the hit render objects, deepest
first. `takenBy` is `"console"` or `"pick"` when the binding takes the
event before the tree sees it.

**`tap(finder)` in the driver** proceeds as follows:

1. Resolve the finder strictly to its target T. If T's `shown` is
   null, fail with "not visible".
2. Take the middle cell of `shown`. For a wide glyph, that is its
   leading cell.
3. Call `hitTest`:
   - T, or a node under T, is in `path`: T is reached;
   - otherwise fail "covered". The failure names the top node at the
     cell and its nearest ancestor that is a route or overlay entry,
     for example "covered by Dialog 'Discard changes?' (node 51)";
   - T is reached but no listener on its path has `down` or `up`: fail
     with "reaches Text 'Save', but nothing there takes a click";
   - `takenBy` set: fail and say which.
4. Send the down and the up as mouse bytes through the ScreenPort. If
   the app has not turned on mouse reporting, fail with "the app does
   not track the mouse". An inline app without a viewport has no mouse
   at all (`mouse.dart:164-167`).
5. Wait for the frame causally, as `press` does.

When the app is driven, nothing moves between the check and the click,
so the check is exact. On real time a frame can come between them; the
check is made at the last frame the driver saw.

## 7. Protocol versions

- `Inspector.version` (`inspector.dart:36`, now 1) changes only when an
  answer or event changes in a way that breaks a client. Adding an
  extension, a field or an event does not change it. A client finds the
  extensions it needs in the isolate's `extensionRPCs`, as
  `app_client.dart:67-91` already does for `ext.twk.tree`.
- Everything this design adds is additive: `find`, `hitTest`, `clock`,
  `layout.shown`, the `frameEvents` flag, and the `twk.frame` and
  `twk.input` events. So it stays version 1.
- Every new answer and event carries `version`, as the existing ones
  do (`app_binding.dart:871`).
- Clients that read events without checking the version:
  - twk_dev reads `twk.select` without checking (`app_client.dart:113-123`);
  - VS Code reads `twk.treeChanged` without checking
    (`editors/vscode/src/app/inspector.ts:174`).

  `drv-frame-event` adds the check to both, since its event is the
  first one a client relies on for correctness.

## 8. The trace

A session can write a trace. A failed test keeps it by default, and the
failure report gives its path.

- **`<name>.cast`.** The pty's output as asciicast v2, with a marker for
  each step (`CastWriter.marker`, `packages/twk_dev/lib/src/cast.dart:293`).
  `CastWriter` and `Cast` move from twk_dev into twk_driver, and twk_dev
  re-exports them. `twk play`, the extension's player and twk_test's
  `screenFrames` already read the format.
- **`<name>.trace.jsonl`.** A header line: `{version, program, size,
  profile, driven, start}`. Then one line per step:
  - `{step, action, args, finder, target (id, type, shown)}`;
  - `{hit (the hitTest answer, for a tap), frameBefore, frame,
    castEvent (index of the step's marker)}`;
  - `{appTime, realTime, result: "ok"|"error", error,
    tree (a key into the trees), log (records since the last step)}`.

  The trees are kept once per frame they changed in. A step's
  screens before, at and after are cut from the cast at the frames'
  `outputWritten`.

The VS Code extension reads both files. It needs nothing from Dart.

## 9. What each front end takes

- **twk_test** (`package:twk_test/driver.dart`):
  - `driverTest(name, (d) async {...})`; `d.start(program, size:,
    profile:, env:, driven: true)` returns an `App`;
  - on `App`: `press`, `type`, `paste`, `tap`, `resize`, `waitFor`,
    `clock.advance`, `screen`, `tree`, `find`, `exitCode`;
  - the matchers and finders of `testTwk`. Remote finders go through
    `ext.twk.find`;
  - the failure report: screen, tree, log, last frames, and the
    trace's path;
  - the strict `Vt` checker, on by default;
  - after exit, the e2e checks: the tty cooked, the alternate screen
    left, the cursor visible.
- **twk mcp** (twk_dev, JSON-RPC over stdio):
  - tools: `start_app`, `screen`, `tree`, `find`, `press`, `type`,
    `tap`, `wait_for`, `elapse`, `hot_reload`, `logs`, `stop_app`;
  - each action answers with the screen as text and a line saying the
    frame, the input read and whether the app is quiet;
  - a failure is a tool result that gives its reason (covered by,
    never, not within budget);
  - hot reload uses the `reloadSources` and `ext.twk.reassemble` of
    `twk run` (`run.dart:567-579`).
- **twk tape:**
  - `Wait` waits for frames, not on a poll;
  - a new `Wait`/`Click` takes a finder, and the click is checked like
    `tap`;
  - `Sleep` stays only for pacing the recorded output;
  - existing tapes keep working.
- **VS Code:** the trace viewer reads the `.cast` file and the sidecar.

## 10. Slices, in order

1. **`drv-clock-port`** (new):
   - the `Clock` port in twk_core;
   - TwkApp and AppBinding take it;
   - DrivenClock in twk;
   - twk_test's FakeClock rebuilt on DrivenClock, and every
     `clock: fakeClock.stopwatch` call changed;
   - frame path: `bench`.
2. **`drv-frame-event`:**
   - counters (3.1);
   - the public `scheduled` getter and the frame-done future on TwkApp;
   - `twk.frame`, `twk.input` and the `frameEvents` flag;
   - the version checks of part 7;
   - frame path: `bench`.
3. **`drv-hittest`:** `MouseTracker.targetsAt`, `ext.twk.hitTest`, and
   `layout.shown`.
4. **`drv-find`** (new): the finder values in twk, `ext.twk.find`, and
   twk_test's `find.*` on them.
5. **`drv-clock`:**
   - `TWK_DRIVEN` in `runApp`, with the zone adapter;
   - `ext.twk.clock`;
   - the real-time fixes of part 4.4;
   - quiet.
6. **`drv-core`:**
   - the twk_driver package: ports, adapters, `press`, `waitFor`,
     `tap`;
   - `VmAppClient`, `compiledProgram` and the termios setting moved
     into it.
7. **`drv-test-api`**, **`drv-trace`**, **`drv-mcp`**, **`tape-on-driver`**,
   **`vsx-trace-viewer`**: in that order, as the user's priorities
   allow.

## 11. Precedents

**Checked by a fetch while this was designed:**

- Playwright's clock: <https://playwright.dev/docs/clock>. Install
  before any other clock call. A start time is given to `install`.
- `dart_mcp`: <https://pub.dev/packages/dart_mcp>. It is experimental,
  and was not taken (decision 5).
- `@playwright/mcp`: <https://github.com/microsoft/playwright-mcp>. A
  thin layer over Playwright.
- Flutter integration tests:
  <https://docs.flutter.dev/testing/integration-tests>.

**Cited from memory, to be checked before they are quoted elsewhere:**

- .NET `TimeProvider` (in the BCL) and `FakeTimeProvider` (in
  Microsoft.Extensions.TimeProvider.Testing);
- Go's `testing/synctest` ("durably blocked");
- tokio's `time::pause` and auto-advance;
- CDP's `Emulation.setVirtualTimePolicy` (`pauseIfNetworkFetchesPending`,
  budget);
- `flutter_driver`'s `SerializableFinder` and
  `enableFlutterDriverExtension`;
- Detox's synchronization and its "never idle" trouble;
- Playwright's actionability check ("intercepts pointer events");
- WebDriver's `ElementClickIntercepted`;
- testing-library's query priority.

**What the precedents taught:**

- install time control before the app's code runs;
- a port that only tells the time is half a port;
- syncing on global idle hangs on animations;
- serialize finders and match them strictly;
- check the hit target at the in-view center of the target;
- say plainly how quiet treats real I/O.

As far as the research found, no tool acknowledges input against frames
causally.

## 12. Limits

- **No VM service, no driver.** An AOT executable or a product build has
  no VM service. Version 1 refuses to start such a program: no
  screen-only mode.
- **Linux and macOS only.** Windows is not supported, since `Pty` is
  POSIX only.
- **Real I/O is outside the clock.** See part 4.6.
- **Other isolates.** The driven clock sees no other isolate's timers.
- **Ids do not outlive the app.** Node ids are per binding, so after a
  hot restart the driver finds its targets again.
- **Suspend.** While the app is suspended (`stopForShell`, an editor),
  the counters do not describe the screen. The driver refuses actions
  until the app resumes.
