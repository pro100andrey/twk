# twk_driver: driving a live twk app from outside

twk_driver runs a twk app as a real process in a real pseudo-terminal. It
types real bytes into the app, reads the screen through a terminal
emulator, and reads the widget tree through the app's VM service. Tests,
coding agents (`twk mcp`), `twk tape` and the VS Code extension all use
it. It covers the half of testing that `testTwk` cannot reach: the real
`main`, the real terminal, the exit code, and the terminal handed back
when the app ends.

This document was written by task `drv-design` (2026-11-12) and revised
by `drv-design-fixes` after a review of it found 15 defects (part 13). It
is based on a read of the code at `5e520a4`, with file:line references to
that commit. Nothing described here is built yet. The user made the
decisions in part 1; everything else is this document's proposal, and a
slice that finds it wrong says so and changes it here. The plan of work
lives in tm, not here (part 10).

## 1. Decisions

Made with the user on 2026-11-12, after a review of precedents (part 11):

1. **Time is a port of the core, and the driven clock lives in twk.**
   twk_core gets a `Clock` interface: monotonic elapsed microseconds,
   one-shot and periodic timers. This is the shape of .NET's `TimeProvider`, not of
   `java.time.Clock`, which only tells the time. twk_core also gets a
   system implementation. `TwkApp` and `AppBinding` take the clock
   explicitly, replacing today's `Stopwatch` and the timers they make
   through a captured zone; it also replaces the `Cli`'s own time port,
   `CliClock` (part 4.1). The clock the driver moves, `DrivenClock`,
   is a runtime capability of twk, because `runApp` uses it in the
   app's own process. That makes it like tokio's `time::pause` or Go's
   `synctest` rather than like a test fake. twk_test's `FakeClock` is
   rebuilt on `DrivenClock`, so there is one implementation of timer
   order and elapse.
2. **Driven mode is turned on at start by `TWK_DRIVEN`.** `runApp` and
   the `Cli`'s system terminal read it before they make a timer. Its
   value names the driving process, so a child the app starts does not
   take it (part 4.3), and may carry an ISO-8601 instant that becomes
   the app's start time. There is no generated entry point and no
   install over the VM service after start: every precedent installs
   the clock before the app's code runs.
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
 app            AppBinding: ext.twk.* (+ find, hitTest, clock), twk.frame / twk.input / twk.scheduled,
                DrivenClock under TWK_DRIVEN; TwkApp/Terminal: byte counters
```

**The core is pure Dart.** It sees only the ports. Each port has a fake
for the core's unit tests, and the adapters are tested in process tests
(`@Tags(['process'])`).

- **TerminalPort.** Owns the pty master: write bytes, resize (TIOCSWINSZ
  plus SIGWINCH, as `Pty.resize` does), and the stream of output. Its
  adapter is twk_term's `Pty` (`packages/twk_term/lib/src/pty/pty.dart`;
  `Pty.start` at :192). Pty is POSIX only, so the driver runs on Linux
  and macOS. Today `Pty.start` opens the slave, sets only IUTF8 on it
  and spawns, all in one call (:255-271); nothing lets a caller set the
  output flags before the program runs, and setting them after
  `Pty.start` returns races the program's first output. So twk_term
  changes, in `drv-core`: `Pty.start` takes the output flags to set on
  the slave beside IUTF8, and `Pty` reports whether the slave maps NL to
  CR NL, from the termios it already reads (`modes()`, :900) (part 3.4).
- **ScreenPort.** Two emulators fed from one byte log (part 3.3):
  - the **answering** emulator takes every byte as it arrives, as a real
    terminal does. It answers the app's queries at once and keeps the
    modes the app turned on, by which keys, the mouse and pastes are
    encoded: `TerminalEmulator.sendKey`, `sendMouse`, `sendPaste`
    (`packages/twk_term/lib/src/emulator/emulator.dart:800-851`). Its
    answers are part of what the driver writes and count as input bytes
    (part 3);
  - the **frame** emulator answers nothing and is fed only up to the
    boundary of the last frame the app has posted. Its screen is the
    one `press`, `waitFor` and the trace see.

  A terminal profile (the extension's presets: colours, answers, kitty
  keyboard, synchronized output) configures the answering emulator for
  a session. `driverTest` feeds the frame emulator's bytes to twk_test's
  strict `Vt` too, as a checker: an unknown sequence fails the test, as
  the e2e checks do. The checker is an optional port, so twk_driver
  never imports twk_test.
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

**Composition: a session is its ports (decided 2026-11-17).** `Session` is
built from ports a caller gives; `Session.start` is the convenience that
makes the adapters of a twk app. Three entries, one engine:

- `Session.start(spec, ports:)`: `dart <program>` in a pty
  (`PtyProcessPort`), `EmulatorScreen`, `VmAppClient`, driven time. It
  calls `compose`.
- `Session.compose(spec, process:, screen:, connect:, clock:, ...)`:
  spawns with the caller's `ProcessPort`, drives with the caller's
  `ScreenPort` (themed as it likes; the session assumes nothing of it
  beyond the port) and times its timeouts on the caller's `Clock` (a
  test's, a recorder's). `connect` null: no app service.
- `Session.attach(launched, screen:, service:, ...)`: the same over a
  program running already.

Where tape fits: a recorder is a `TerminalPort` wrapped around the
terminal of the `Launched` its `ProcessPort` returns. Its `output` passes
each chunk on, noting the time of its own clock; its `write` notes the
bytes. The driver needs nothing more of the port for recording and
depends on no recorder; the chunk times are the recorder's. `PtyCommandPort`
starts any command (`sh`) in a pty with no VM service.

Two modes, by whether there is an app service:

| | with `AppServicePort` | without |
|---|---|---|
| `press`/`type`/`paste`/`resize` | return at the frame that took the input in | return when the bytes are written |
| waits | on frames (part 3.3), `waitFor` drives the app's time (4.6) | on the screen as the `ScreenPort` has it after each chunk of output, not while it is inside a synchronized update (`ScreenView.updating`), within `timeout` (`io` for `waitFor`) on the given clock |
| `find`, `tap`, `clock` | the app's | `DriverError` "not a twk app (no app service)" |
| `driven` | the app runs on the driver's time | meaningless: `compose(driven: true)` is an `ArgumentError`, `Session.driven` false |
| end, `exitCode`, `close` | as ever | as ever (the app never says it is quitting, so an end the driver did not ask for is an `AppEnded`) |

Without a service both emulators take every chunk, so `Session.screen` is
what the terminal shows; a wait on the cursor line reads
`session.screen.line(session.screen.cursorY)` in its test.

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

- **`bytesRead`.** Every byte taken from `link.input`. Input has one
  subscription (`terminal.dart:1110`) and two data handlers: the
  probe's (around :1309) and the session's `_onBytes` (:1852). Both
  count, at the end of the handler, once the read is parsed and its
  events are added to `_events`. Bytes the Terminal keeps to itself
  count too: the probe's answers, a cursor report a resume asked for
  (`_deliver`, :1909-1916), a late reply it drops.
- **`bytesReadAtOpen`.** What `bytesRead` was when `Terminal.open`
  returned: the probe's bytes.
- **`inputPending`.** True while the parser holds bytes
  (`InputParser.hasPending`, `inPaste`): a lone ESC waiting for its
  timeout, an open paste.
- **`onRead`.** Called at the end of each data handler, so that TwkApp
  can acknowledge a read that gave it no event (part 3.2).
- **`bytesWritten`.** Bytes accepted for the tty: the probe's direct
  `link.add` calls (:1421, :1432), plus everything given to the
  `Outbox`. They are counted when the Outbox accepts them (`add` and
  `frame` in `terminal/outbox.dart`), not when they reach `link.add`.
  The difference matters: the Outbox holds a write back while a flush
  runs (`_queued`), so a frame written then would otherwise be missed at
  the moment the frame is posted. Every accepted byte reaches the tty
  without a further flush.

Each counter costs one integer add per read or write call, not per
byte. This is on the frame path, so `bench` is owed.

**What TwkApp reports is not `bytesRead`.** The Terminal counts a read
when its events are added to `_events`, an asynchronous
`StreamController` (`terminal.dart:907`). TwkApp gets them later, and
not at all while its subscription is paused: from `run` until the first
frame's build is done (`app.dart:626`, resumed at :1255), and while the
app is suspended. A key read during such a pause is counted by the
Terminal but has not reached the app. So TwkApp keeps its own
**`inputRead`**:

- it is a sample of `bytesRead`, taken at the boundaries of the event
  loop where it is read: the start of a frame, the acknowledgement's
  timer, an extension's handler. While the subscription is live the
  sample is exact there: the controller delivers its events in
  microtasks, and the microtask queue is empty at a boundary;
- while the subscription is paused, the sample is not taken, and
  `inputRead` keeps the last one. Before the first frame it starts at
  the bytes the Terminal read while it opened, the probe's, which the
  Terminal reports apart (`bytesReadAtOpen`). A key read after the open
  waits in `_events` until TwkApp's subscription is live, so it is not
  in that number. After a resume, the sample catches up at the first
  boundary, once the buffered events have been dispatched.

### 3.2 What the app posts (twk)

All events are gated twice: on `ext.twk.flags frameEvents=true` (a new
flag, like `treeEvents`) and on `extensionStreamHasListener`
(`app_binding.dart:908-920`). With either off, the cost is one test of
the flag.

**`twk.frame`** is posted from `AppBinding._afterPresent`
(`app_binding.dart:1296`). That runs for every frame, including one
whose `screen.render()` wrote nothing (`app.dart:1277-1293`). Payload:

```json
{"version": 1, "frame": 41, "drawn": true, "size": {"width": 80, "height": 24},
 "inputRead": 1093, "outputWritten": 58211, "inputPending": false,
 "scheduled": false, "frameDue": null, "time": 3016000, "nextDue": null}
```

- `frame` counts the frames run, drawn or not.
- `size` is the screen's size the frame was laid out at.
- `inputRead` is TwkApp's `inputRead` (part 3.1) as it was when this
  frame's build began (`_beforeLayout`, `app_binding.dart:1223`).
- `outputWritten` is `bytesWritten` after this frame's write.
- `scheduled` is true when a frame is already asked for: `_scheduled`,
  `_again`, `owner.hasWork`, or a pending commit (`app.dart:430-433`,
  :1310). TwkApp exposes this as a public getter; today these fields
  are private.
- `frameDue` is when that frame is due, in µs of the app clock:
  TwkApp's `_frameDue` (`app.dart:455`), made public. Null when no frame
  is asked for.
- `time` is the app clock in µs. `nextDue` is the earliest timer of the
  driven clock, whatever it is for, and null when the app is not driven.
  `nextDue` is never what the driver moves the clock to for a frame:
  that is `frameDue`.

**`twk.input`** acknowledges what does not, or does not yet, lead to a
frame. A key that changes nothing never calls `requestFrame`, and an
answer the Terminal keeps to itself never reaches TwkApp, so without
this event the driver would wait forever. TwkApp arms one root-zone
`Timer.run` when the Terminal's `onRead` fires and when it dispatches an
event, resize events included. The timer fires after the microtask
queue has drained, and then posts the same payload as `twk.frame`, with
`frame` set to the last frame run. Several reads in one turn of the
event loop get one post.

`scheduled: false` in a `twk.input` means only that no frame was asked
for by the time the event loop drained. Work that a handler deferred
with zero delay (`Future(...)`, `Timer.run`, `scheduleMicrotask`) has
run by then: it was queued before the acknowledgement's timer, and
timers of equal delay run in order. Work deferred longer, a timer with
a delay or a wait on real I/O, may still draw. `press` does not wait for
it; `waitFor` does.

**`ext.twk.clock`** is registered in every app with a VM service,
driven or not (part 4.5). Its `status` gives the same counters and
`frame`, so a driver that attaches has a baseline. It sets
`frameEvents` first and reads `status` after that, so no frame falls
between the two.

### 3.3 Acting and waiting

**Keys, text, pastes, the mouse.** `press`, `type`, `paste` and the
clicks of `tap`:

1. The driver writes the bytes, encoded by the answering emulator. Its
   running total of written bytes becomes `W`. The total includes the
   emulator's answers, written as soon as the queries arrive.
2. It waits for a `twk.input` or `twk.frame` event with
   `inputRead >= W` and `!inputPending`. A lone ESC stays pending for
   the escape timeout (30 ms, or 500 ms for a sequence that was cut,
   `terminal.dart:1860-1873`). That timer runs on real time, even when
   the app is driven (part 4.4).
3. If that event is a `twk.frame`, it is the input's frame. If it is a
   `twk.input` with `scheduled`, the driver waits for the next
   `twk.frame` with `inputRead >= W`. When the app is driven, the driver
   first moves the clock to the event's `frameDue`. Input frames are
   spaced by `1/maxInputFps` (`app.dart:1205-1231`). That is 8.3 ms at
   the default 120. It is `maxFps` (16.7 ms at the default 60) on a
   remote terminal or below 60 frames a second (`_inputFps`,
   :352-355). If the event is a `twk.input` without `scheduled`, no
   frame was asked for (part 3.2).
4. The driver feeds the frame emulator up to the frame's `outputWritten`
   bytes of the app's output (part 3.4). Then it returns the frame
   number and the screen.

**Actions that put no bytes in.** `resize`, the app's first frame, and
a hot reload's `ext.twk.reassemble` do not move `inputRead`.

- **Resize.** It comes by SIGWINCH (`Terminal._checkSize`) as a
  `ResizeEvent`. TwkApp dispatches it like any event, so `resize` waits
  for a `twk.input` or `twk.frame` whose `size` is the new size, then
  goes on from step 3.
- **Start.** The first frame needs nothing: a driven clock runs timers
  that are due at its current time without being moved (part 4.2), and
  the first frame is due at once (`_lastFrameAt` starts a second back,
  `app.dart:452`). `start` sets `frameEvents`, reads `ext.twk.status` (the same fields
  as `twk.frame`, nothing changed; `ext.twk.clock` adds the clock later), and when
  no frame has run yet, waits for the first `twk.frame`.
- **Reassemble.** `ext.twk.reassemble` answers with the last frame run
  and the `frameDue` of the frame it asked for (two fields added to its
  answer, which is `{version}` today, `app_binding.dart:969-971`). The driver moves a
  driven clock there and waits for a `twk.frame` past that frame.

**Every wait also ends on these:**

- the process exits;
- the pty reaches its end;
- the VM service closes;
- an error nothing caught in a frame: it ends the app through `_fail`
  (`app.dart:1163`), and it is the exit that is seen. An error in a
  widget's build, layout or paint is reported and the frame goes on, so
  it posts as usual.

A wait that ends so reports the exit code, the screen, and the log's
last records. It is not a timeout. An app that quits says so: `quitting`
in `twk.input`, `twk.frame` and `ext.twk.status` (`TwkApp.quitting`, set
by `quit`, and posted before the terminal is handed back). A step whose
acknowledgement says `quitting` waits for the process to exit, the VM
service closing meanwhile being no error, and returns it as `Step.exit`
(code, last screen): `press('q')` is answered "the app exited (0)", and
every call after it returns the same result. An exit with no such
acknowledgement is "exited unexpectedly (N)", an `AppEnded` with the
screen and log, thrown by every call after it.

**Every frame is seen.** The driver keeps a log of the bytes it
received. The answering emulator takes them as they come, so a query in
them is answered when a terminal would answer it, never held back
behind a frame boundary. The frame emulator moves only from one posted
frame's boundary to the next, and the boundaries only grow. So the
driver has every frame's screen, including a state that lasts one frame,
even when the app runs on real time. Nothing is polled, so nothing is
missed between polls.

A corrective frame that the input's frame asks for is not part of
`press`. One example is the focus settling a frame late: the KeyHintsBar
lag, tm reflection `01a19391-6c5d-796e-891d-aee1847aec20`. `waitFor`
covers it, because it checks every frame.

### 3.4 Line discipline: why the driver counts LFs

Dart's raw mode leaves the tty's output processing on: `lineMode` and
`echoMode` change only lflag, and twk's `PosixTty.enterRaw` changes only
iflag and lflag (`packages/twk_core/lib/src/terminal/posix_tty.dart:108-124`).
So OPOST|ONLCR stays set, and every LF the app writes reaches the pty
master as CR LF. The presenter does write bare LFs: inline line feeds
(`presenter.dart:1394`, :1123), and plain output (`app.dart:1029`).

The driver therefore counts the app's bytes as
`received - LFs received while ONLCR is set`; the inserted CR always
comes right before its LF. The slave's output flags are set by
`Pty.start` before the program runs (the twk_term change of part 2):
OPOST and ONLCR on, which is what a real terminal gives, TAB0, and no
OCRNL, ONOCR or ONLRET. `Pty` reports ONLCR from the termios it
reads. Nothing in twk changes oflag. `drv-frame-event`'s process test
holds the two counts equal over inline, fullscreen and plain apps.

Input needs no such correction. In non-canonical mode with ISIG, IXON
and ICRNL cleared (by `enterRaw`), the line discipline passes bytes
through unchanged. The driver writes nothing until it has seen the
probe's queries, which come after `enterRaw` (`terminal.dart:1104-1106`),
so no key goes in while the tty is still cooked.

## 4. Time

### 4.1 The port (twk_core)

```dart
abstract interface class Clock {
  int get elapsedMicroseconds;                 // monotonic, since the clock began
  Timer timer(Duration after, void Function() callback);
  Timer periodic(Duration every, void Function(Timer) callback);
}
final class SystemClock implements Clock { ... }  // Stopwatch + Zone timers
```

- **An int, not a `Duration`.** The reads on the frame path are ints
  today: `clock.elapsedMicroseconds` in `requestFrame` and `_frame`
  (`app.dart:1223`, :1244), and in `AppBinding`'s frame callbacks and
  `_dueTimer` (`app_binding.dart:1069`, :1198). `_beforeLayout` reads
  `clock.elapsed` (:1225) and turns it into microseconds; it reads the
  int instead. The port keeps them ints, and `elapsed` as a `Duration`
  is an extension on it. The frame path
  has paid for a call it did not inline before: `2a73619` measured 10 %
  on typing into 40k characters. So `drv-clock-port`'s bench report
  looks at `type-40k`, `wrap` and `ellipsis`.
- `TwkApp({Clock? clock})` replaces `Stopwatch? clock` (`app.dart:223`,
  :258). `requestFrame` calls `clock.timer(wait, _zone.bindCallback(_runFrame))`
  instead of `_zone.createTimer` (:1227), so frames still run in the
  app's zone, and its errors still go to `runZonedGuarded`.
- `AppBinding` takes the same clock. `startTimer` and `startPeriodic`
  (`app_binding.dart:416-422`) and `_dueTimer` (:1199) go through it.
  `now()` (:726) is `startTime + clock.elapsed`, and a driven app always
  has a `startTime`.
- **`CliClock` goes.** `CliClock` (`packages/twk/lib/src/cli/terminal.dart:18-37`)
  is a second time port: `stopwatch()` and `run(body)`, with a fake in
  twk_test (`_FakeCliClock` and `_ClockStopwatch`,
  `packages/twk_test/lib/src/cli/fake_cli_terminal.dart:361-400`). The
  `Cli`'s terminal carries a `Clock` instead. `CliSession.open`
  (`packages/twk/lib/src/cli/session.dart:64-80`) gives it to
  `AppBinding`, and the `Cli`'s progress (`cli/progress.dart:86`, :308)
  takes it. `ProgressTracker(clock:)`
  (`packages/twk/lib/src/animation/progress_list.dart:139-148`) takes a
  `Clock` and defaults to the binding's when it is made inside an app
  (its real `Stopwatch` leaked real time into tests: tm reflection
  `01a16660-4ba6-7ea7-843c-cbd89fad290d`).
  That removes the Stopwatch fakes, so timer order and elapse have one
  implementation.
- These stay real `Stopwatch`es: `_statsClock` (`app.dart:448`), the
  frame overlay's cost watches (`frame_overlay.dart:250`, :366-367),
  `doctor`'s probe timing (`packages/twk_dev/lib/src/doctor.dart:347`),
  and the trace writer's (`terminal/trace.dart:228`). They measure cost
  or real I/O, not app time. Log records keep `DateTime.now()`.
- This is a breaking change to `clock:` and a change to the frame path.
  Early in the project, breaking is acceptable; `bench` is owed.

### 4.2 DrivenClock (twk)

`DrivenClock implements Clock`:

- a queue of timers ordered by due time, then by creation order;
- **timers due now run without a move.** A timer due at or before the
  clock's current time runs on its own: the clock wakes itself with a
  zero timer in `Zone.root`. Time does not move, so this costs nothing
  in determinism. It is what lets the first frame (due at once), a
  `Future(...)` and a `Timer.run` happen without the driver. The driver
  owns time, not the running of what is due now. Go's `synctest` runs
  what is ready at the bubble's current time in the same way;
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
`elapse`. In a test, the due-now rule is FakeClock's: due timers run
when the test flushes or elapses, as now. Its public API (`run`,
`elapse`, `elapseUntil`, `pendingTimers`, `describeTimers`) stays.
`stopwatch` gives way to `clock`. `TestFailure` stays in twk_test's
wrapper.

### 4.3 `TWK_DRIVEN`

The variable is read by one function in twk. It is called by the two
places that make a binding for the process when they are given no
clock: `runApp`, and the `Cli`'s system terminal
(`packages/twk/lib/src/cli/terminal.dart:115`, where it answers
`CliClock.system()` today). `AppBinding`'s constructor never reads it,
and an explicit `clock:` wins over it.

**The value names the driver.** It is `<pid>` or `<pid>@<ISO-8601
instant>`. `<pid>` is the driving process, and the instant becomes the
app's start time; without one, the start time is the real time at
start. The variable is taken only when the process's parent is that
pid (`getppid`, which twk_core's libc bindings already have,
`posix_tty.dart`). A program the driven app starts (a nested twk app, a
`twk run`, a shell in a `TerminalView`) inherits the environment, but
its parent is the app, so it runs on real time. Without that rule it
would wait forever for a driver that is not there. If `dart run` puts a
process between the driver and the app, the app is not driven. The
driver sees `driven: false` in `status` and fails at once, saying why;
it never runs a test on real time thinking it is driven.

When the variable is taken:

1. The terminal opens on real time, as today (`app_binding.dart:196-205`).
2. A `DrivenClock` is made.
3. The binding and the app run in a zone forked from the current one
   whose `createTimer` and `createPeriodicTimer` go to that clock. This
   zone adapter is how a raw `Timer` or `Future.delayed` in the app's
   own code is driven as well. The adapter is made from the clock the
   caller holds, and the binding is given the clock as an argument, so
   no zone value carries it anywhere.

In product mode the variable is ignored. Without a VM service, it
throws at start: nothing could move the clock.

### 4.4 What stays on real time

The rule: **an I/O adapter makes its timers in a zone it captured when
it was made, or in `Zone.root` when the app makes it.** Its timers are
then never driven, whichever zone calls into it. The list below comes
from a grep of `Timer(`, `Timer.periodic(`, `Timer.run(`, `.timeout(`,
`Future.delayed(` and `Stopwatch()` in the `lib/` of twk_core, twk and
twk_term at `5e520a4`. `drv-clock` turns it into a test, so that a new
one cannot slip in unclassified.

| where | what | today made in | under the driven zone |
|---|---|---|---|
| `terminal.dart:1424`, :1843, :1858, :1872 | probe timeout, late probe, paste, escape | the zone `Terminal.open` ran in | real: the terminal opens before the zone exists |
| `io.dart` (`tmuxFormat`) | the probe's question to tmux, whether its pane allows passthrough | the zone `Terminal.open` ran in | real: as the probe timeout |
| `dbus.dart`, `desktop_dbus.dart` (`openDesktopNotifications`) | the probe's connection to the session bus and its notification service | the zone `Terminal.open` ran in | real: as the probe timeout |
| `desktop_dbus.dart` (`close`) | close's wait for the notifications asked for | the root zone | real: a guard, as close's own |
| `terminal.dart:2067`, :2075 | resume's cursor timeout, late cursor | the app's zone (resume) | **driven: move to the terminal's captured zone** |
| `terminal.dart:2202`, :2208 | close's flush guards | the zone `TwkApp.run` awaits close in | **driven: same fix**. Unfixed, exit hangs on a terminal that stops reading |
| `terminal.dart:1730` | terminal state refresh, 10 s periodic | the app's zone | driven, on purpose: the app's own refresh, and the app is not quiet while it runs |
| `posix_output.dart:141` | drain retry | the writer's zone, the frame's | **driven: capture the link's zone** |
| `socket.dart:255`, :493, :666, :717 | socket terminal: welcome, close, refusal, hello | open, or the caller's zone (close) | **:493 driven: same fix**; the others open before the zone |
| `log_server.dart:83` | token timeout | the zone `serveLogs` runs in, inside `TwkApp.run` | **driven: capture at the server's start** |
| `trace.dart:264` | `TWK_TRACE_*` writer's drain, `Timer.run` | the writer's zone | zero delay: runs as a due-now timer either way; captured too, for clarity |
| `twk_term pty.dart:644`, :706, :870 | hosted `Pty`: hang-up grace, 10 ms reader polls | the app's zone (`TerminalView` makes it) | **driven: `Zone.root`**. Unfixed, a hosted shell's output waits for the clock and the app is never quiet |
| `twk_term render_terminal.dart:172` | `TerminalView`'s synchronized-update timeout | the app's zone | driven, on purpose: a view's own timeout is app time |
| `twk platform/io.dart:254`, :289 | `tailFile`'s looks and watch | `Zone.root` already | real |

Known escapes that remain:

- **Timers made in `main` before `runApp`.** The precedents agree on
  this one: install comes first or the clock is not in charge.
  Documented.
- **Other isolates.** The terminal's own input isolate is I/O
  (`posix_input.dart:67`). An app's isolates are outside the clock
  (part 12).

### 4.5 `ext.twk.clock`

It is registered in every app with a VM service, beside the other
`ext.twk.*` (`AppBinding.serviceExtensions`, `app_binding.dart:782-791`),
driven or not. A client tells the two apart by `driven`.

Params: `op=status|advance|advanceTo|next`, `by` / `to` in µs, and
`describe=true`.

```json
{"version": 1, "driven": true, "time": 3016000, "timers": 2,
 "nextDue": 3033333, "frameDue": 3024999, "scheduled": true, "quiet": false,
 "frame": 41, "size": {"width": 80, "height": 24},
 "inputRead": 1093, "outputWritten": 58211, "inputPending": false,
 "describe": [{"due": 3033333, "periodic": false, "created": "lib/spinner.dart:40"}]}
```

- **Not driven.** `status` answers the counters, `frame`, `scheduled`,
  `frameDue` and `time` (the system clock), with `driven: false`, and
  `timers`, `nextDue` and `quiet` null. The other ops are refused:
  "the app is not driven".
- **Driven.** `advance` does the following:
  - fires the timers in due order up to the target;
  - after each one, awaits a root-zone zero timer, so the microtasks
    the timer started run to the end;
  - waits for a frame that is running and awaiting its flush to end
    (TwkApp exposes this as a future);
  - leaves the app's time at the target.

  A second call while one runs is refused.

The handlers run in `Zone.root` (`app_binding.dart:892-897`). Each
fired timer runs its callback in the zone where it was made.

### 4.6 Quiet, `waitFor` and "never"

`ext.twk.clock status` answers between tasks of the event loop, so the
microtask queue is empty when it answers. The app is quiet when all of
these hold:

- the clock has no timers (frame timers included);
- nothing is pending in the input parser;
- no frame is scheduled or running;
- on the driver's side, `inputRead` equals the bytes the driver wrote,
  and the frame emulator has taken `outputWritten` bytes.

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
4. Like every wait (part 3.3), it also ends when the app exits, the pty
   ends or the service closes, and says so.

Real I/O in flight (a socket, a file, a process) is invisible to the
clock and to the zone; Dart has no API for it. A quiet app that is
waiting for such I/O would get a false "never". So a wait that involves
I/O passes `io: Duration`. Then a quiet app is waited on in real time
for up to `io`, for frames that might still arrive, before the wait
fails. Go treats such I/O as not "durably blocked", and CDP has
`pauseIfNetworkFetchesPending`. twk asks the caller instead, because the
app cannot tell. Every "never" failure says that the app was quiet and
that I/O cannot be seen, so a false "never" explains itself.

What comes in from outside asks for a frame the app's clock does not reach:
a child's answer calls `setState`, and the frame is due a gap after the
last, on a clock that stands. The app says so: it posts `twk.scheduled`
(the payload of `twk.input`) when, with `frameEvents` on and a driven
clock, a timer of the clock is started or cancelled (a frame asked for is
one) outside a move of the clock and outside input, once per turn of the
event loop (a root-zone timer, as for `twk.input`; `DrivenClock.onChange`).
A quiet app that is waited on with `io` waits for an event, up to the io
time on the driver's clock: no poll, no timer of the driver's. The event
ends that wait, and once the app is not quiet (a frame is asked for) the
wait goes on as for any app, advancing to what is due. An app that is not
driven, or has `frameEvents` off, posts none and pays nothing.

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
| `{"type": "DropDown<String>"}` | `runtimeType.toString()` equal: exactly the type, with its type arguments, as `find.byType` (`finders.dart:46-47`) |
| `{"key": {"value": "save"}}`, `{"key": {"value": 3}}` | `ValueKey<String>` / `ValueKey<int>` by `==` |
| `{"node": 44}` | a node id from an earlier answer; refused if it left the tree |
| `{"descendant": F, "of": G}`, `{"ancestor": F, "of": G}` | as twk_test's (`finders.dart:328-380`): strictly below or above, never the node itself |
| `{"at": 2, "of": F}`, `{"first": F}`, `{"last": F}` | index |

- Other keys (`ObjectKey`, `GlobalKey`, `UniqueKey`) cannot cross the
  wire. They are reached by `node`.
- **One semantics, in and out of process.** In `testTwk`, `byType`
  keeps comparing `Type`s. Over the wire it compares the type's name,
  which is the same answer unless two classes of one name from two
  libraries are in the tree. Then the name matches both, and strictness
  fails the action, naming both matches. A Dart program cannot learn a
  `Type`'s library without mirrors, so the name is as far as the wire
  goes.
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

`shown` is the rectangle clipped by every ancestor, null when no cell
shows. Two copies of that computation exist today: the inspector's
private `_shownOf` (`packages/twk/lib/src/debug/inspector.dart:303-324`)
and the loop in twk_test's `clickOn` (`finders.dart:286-309`). One
public function in twk takes their place, and both call it.
`ext.twk.layout` gets `shown` too.

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

A session writes a trace when it is given `trace: TraceOptions(path)`
(`Session.start`, `compose`, `attach`; `Session.trace` says where the files
are). twk_test's `driverTest` gives every app one under
`.dart_tool/twk_test/traces/`, keeps it for a failed test and deletes it for
a passing one, and its failure report names the path.

- **`<name>.cast`.** The pty's output as asciicast v2 (`CastWriter`, in
  `src/cast.dart`; `CastWriter` and `Cast` moved from twk_dev into
  twk_driver, and twk_dev re-exports them: one implementation), with a
  marker for each step, written when the step starts. `twk play`, the
  extension's player and twk_test's `screenFrames` already read the format.

  The driver writes the output events from the frame emulator's feed: one
  event for the bytes up to each posted event's boundary (`twk.frame`, and
  the `twk.input` and `twk.scheduled` that carry bytes: what came between
  two frames). So every frame boundary is an event boundary. The bytes
  are as the pty gave them, the CRs of ONLCR included, which is what a
  player needs. The app writes each frame whole, so a boundary never falls
  inside a UTF-8 sequence. A resize of the frame emulator is an `r` event.
  What the app wrote after the last boundary is written when the session
  ends.
- **`<name>.trace.jsonl`.** One JSON line each, told by `type`:
  - `header`: `{version, program, size, profile, driven, start}`;
  - `frame`, the frames table, a line for each frame posted:
    `{frame, castEvent, outputWritten, raw}`, where `castEvent` is the
    index of the cast event the frame's bytes ended in, `raw` counts the
    bytes as the pty gave them and `outputWritten` the app's, without the
    CRs of part 3.4. (Without an app service each chunk of output is a
    frame, numbered from 1; the screen before any output is frame 1.)
  - `step`, one for each action (`press`, `type`, `paste`, `resize`,
    `tap`, `find`, `findOne`, `waitFor`, `waitForScreen`, the moves of
    the clock `clock.advance`, `clock.advanceTo`, `clock.next`; one
    inside another is part of it): `{step, action, args, finder, target
    (id, type, shown), hit (the hitTest answer, for a tap, kept when the
    tap fails), frameBefore, frame, castEvent (index of the step's
    marker), appTime (microseconds of the app's clock), realTime
    (microseconds of the driver's clock since the start), result: "ok" |
    "error", error, tree (a key into the trees), log}`;
  - `tree`: `{key, frame, text}`, the widget tree as `treeText` writes it,
    kept once, in the step that first saw it (a tree the same as the last
    one is not kept again). The tree is read at the end of each step, within
    2 s of the driver's clock; none is kept for an app that ended.

  `log` is the records the app logged during the step, as text lines (the
  app posts them as `twk.log` with `frameEvents`, before the frame the
  step waits for), then what `TraceOptions.log` returns, where given. The
  last 50 are `Session.log`, `ExitResult.log` and the failure report's.

  A step's screens before, at and after are the cast replayed to the end of
  `frameBefore`'s and `frame`'s `castEvent`. No offset into a chunk is
  ever needed.

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

## 10. The plan

The work is planned in tm, under the root task `driver`
(`01a1c046-42c4-722e-91de-df45730de60f`). Its children are the slices,
and its links are their order (`get_tree`, `get_graph`). This document
gives no order of its own, so it cannot go stale against the tracker.
Each slice's description names the parts of this document it builds.

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

## 13. The design review, and what changed

A review of the first version (`19d8b15`) found 15 defects. Each was
checked against the code, and each is fixed:

| # | defect | fixed in |
|---|---|---|
| 1 | the first frame's `inputRead` contradicted `bytesRead`, counted while TwkApp's subscription is paused | 3.1: TwkApp's own `inputRead`, frozen while paused |
| 2 | waits raced nothing: an app that exits or throws hangs the call | 3.3: every wait also ends on exit, pty end, service close |
| 3 | the clock was moved to `nextDue`, any timer, not the frame's; the input gap is not always 8.3 ms | 3.2: `frameDue`; 3.3: the gap by `_inputFps` |
| 4 | resize, the first frame, reassemble: no byte to acknowledge, and a zero-delay timer never fires on a driven clock | 3.2: `size`, acks on every event; 3.3: actions without bytes; 4.2: due-now timers run |
| 5 | `TWK_DRIVEN` reaches the app's children, which freeze | 4.3: the value names the driver's pid, checked against `getppid` |
| 6 | an emulator stopped at a frame's boundary cannot answer the queries past it | 2, 3.3: an answering emulator fed at once, a frame emulator fed by boundaries |
| 7 | `CliClock` is a second time port; `Cli` builds its binding without `runApp` | 4.1: `CliClock` goes; 4.3: the `Cli`'s system terminal reads `TWK_DRIVEN` too |
| 8 | `ext.twk.clock` registered in the driven path only, yet used for the baseline | 3.2, 4.5: in every app, `driven` tells which |
| 9 | the finders' `type` dropped type arguments; `matchRoot` is not twk_test's; `shown` duplicated `clickOn`'s clipping | 5 |
| 10 | the real-time inventory was by hand and missed the close guards, resume's timeout, the hosted `Pty` | 4.4: a rule and a table from a grep, turned into a test |
| 11 | `Pty.start` gives no way to set the slave's output flags before spawn | 2, 3.4: a twk_term change in `drv-core` |
| 12 | "`scheduled: false`, nothing will be drawn" overclaimed | 3.2: what zero-delay work it covers, and what only `waitFor` does |
| 13 | trace frames by `outputWritten` against a cast of raw pty bytes | 8: one cast event per frame, a `frames` table with both counts |
| 14 | the port's `Duration` would cost a call and an object per read on the frame path | 4.1: `int elapsedMicroseconds` |
| 15 | part 10 kept a plan beside tm's; references to tm had no id | 10; ids in 3.3 and 4.1 |
