# A VS Code extension for twk

The extension is in `editors/vscode`: a terminal of its own for each twk
app you run or debug from VS Code, with switches for what that terminal
can do, hot reload and restart, a widget inspector, a log of the
sequences between the app and its terminal, recording and replay. The
first part says what the first version is and how to use it; the parts
after it are how it was found out and how it is built (the prototype's
notes, kept as they were measured), its architecture (2b) and its tests.
Everything below was run on this machine (Linux, VS Code 1.143.1, Dart
3.13.7, node 26.12, npm 12.2), unless it says it was not.

## 0. The first version, and how to use it

### What it is

- **A twk terminal per app.** Each Run and each Debug opens a panel
  beside the editor with an xterm.js terminal of the extension's own,
  titled by the file (`counter.dart · twk 80x24 · xterm.js`). The app
  finds it by `TWK_SHELL` in its environment (twk's socket terminal, the
  `twk shell` protocol), so it needs no tty: the Debug Console stays free
  of its frames, the terminal survives a hot restart, and a killed app's
  terminal is put back. Closing the panel ends its app.
- **Run, Debug, F5.** Run with `dart run` and the VM service; Debug
  through Dart-Code (its debug adapter, breakpoints and all) with the app
  on the twk terminal; F5 on a `"type": "twk"` launch configuration.
- **Hot reload and hot restart**: on save (`twk.hotReloadOnSave`, on by
  default), Ctrl+Alt+R and Ctrl+Alt+Shift+R. A reload rebuilds every
  widget with its state kept (`ext.twk.reassemble`), which Dart-Code's own
  reload does not; a compile error is shown and the app runs on.
- **What the terminal is**: a preset (`xterm.js`, `everything`,
  `256 colors`, `16 colors`, `no color`, `no synchronized output`, `bare`,
  `no answers`) and each switch of it (colours, sixel or iTerm2 images,
  the probe's answers, synchronized output, kitty's keyboard protocol, the
  cell size, notifications, progress, pointer shapes, REP, links, the
  clipboard), for the apps that connect next; the screen reader and twk's
  debug aids switched on in them.
- **The twk Inspector** (Run and Debug): the widget tree, followed as the
  app changes; the pick mode, as Flutter's Select Widget Mode: while its
  button is pressed, each click on the terminal picks the widget under it
  and opens where it was made; where a widget was made, from the tree;
  the frame overlay, the repaint rainbow, the relayout highlight.
- **The sequence log**: what the app wrote, decoded (each CSI, OSC, DCS,
  APC named, text runs, a synchronized update one frame), and what the
  terminal sent (keys, the mouse, the answers to the app's queries),
  filtered, paused, from the terminal's start.
- **Record and replay**: a session recorded as asciicast v2, the format
  of `twk record`, `twk play` and `twk tape`, its frames twk_test's
  `screenFrames`, and a
  recording (any of theirs too) played back in a terminal of its own,
  paused, a frame on or back.
- **Copy the screen** as text.

### Installing it, and updating a copy

Not on the Marketplace yet (`private`, no `vsce` package): it runs from
the repository.

```sh
cd editors/vscode
npm install
npm run compile
code --extensionDevelopmentPath=$PWD path/to/your/twk/project
```

With Dart-Code installed for Debug and F5 (Run needs only the Dart SDK).
`--user-data-dir` and `--extensions-dir` give it a profile of its own.

**Updating a copy that runs** (a window started with
`--extensionDevelopmentPath`): after a pull, in `editors/vscode`

```sh
npm install          # what package-lock.json names
npm run compile
```

then **Developer: Reload Window** in the window that runs it (the apps
it runs end with it). The inspector and the debug aids take the twk of
this repository in the app.

### Using it

Open a Dart file of a twk app and run a command (Ctrl+Shift+P, "twk"):

| command | what it does |
|---|---|
| twk: Run Dart File in twk Terminal | `dart run` it in a new twk terminal, with hot reload |
| twk: Debug Dart File in twk Terminal | debug it with Dart-Code, the app on a new twk terminal |
| F5 on `{"type": "twk", "request": "launch", "program": "${file}"}` | the same, from `launch.json` (the snippet "twk: Debug in a twk Terminal") |
| twk: Hot Reload (Ctrl+Alt+R), twk: Hot Restart (Ctrl+Alt+Shift+R) | the apps the extension runs or debugs |
| twk: Open twk Terminal for Any App | a terminal that shows the `TWK_SHELL=...` an app started anywhere takes it with |
| twk: Choose twk Terminal Capabilities | a preset, or each switch; the next app gets them (a hot restart is offered) |
| twk: Choose twk Terminal Switches | the screen reader and the debug aids, for the next app |
| twk: Show the Sequence Log of the twk Terminal | the log of the terminal (title bar button) |
| twk: Record the twk Terminal as asciicast (Start or Stop) | record the terminal to a `.cast` file; again to stop (title bar button) |
| twk: Stop Recording the twk Terminals | stop every recording (also a click on `REC` in the status bar) |
| twk: Play a Recording (asciicast) in a twk Terminal | play a `.cast` back (also the explorer's menu on a `.cast` file) |
| twk: Copy the twk Terminal's Screen as Text | the screen on the clipboard (title bar button) |
| twk: Show twk Output | the extension's log: the app's own output, reloads, errors |
| twk: Pick Widgets in the twk Terminal (the twk Inspector's $(inspect) button) | the pick mode on: each click on the app's terminal picks the widget under it, opens where it was made; the button pressed (filled) until twk: Stop Picking Widgets, or Escape in the terminal |

"The twk terminal" of a command is the active one: the panel focused, or
else the newest open (a replay among them, but recording takes an app's
terminal only). The three title bar buttons are on each twk terminal's
panel. The settings are under `twk.` (`twk.terminal.profile`,
`twk.terminal.capabilities`, `twk.terminal.screenReader`,
`twk.terminal.debugAids`, `twk.terminal.columns` and `lines` for a fixed
size, `twk.hotReloadOnSave`); keep Dart-Code's `dart.hotReloadOnSave` at
`never`, or both reload.

**The sequence log.** A panel beside the terminal, a row each: the time
(seconds since the terminal opened), the direction (`→` what the app
wrote, `←` what the terminal sent, `·` a note: an app connected or went
away, a size, the extension's own lines), the name and the bytes (ESC as
`ESC`, controls as `^M`). Names are those of the sequences
(`CUP cursor to row 3, column 5`, `SGR bold, fg green`, `DECSET 1049
alternate screen, cursor saved`, `OSC 11 query: the background colour`,
`DCS sixel image (…)`) and of what the terminal sent (`key Ctrl+Up`,
`key Escape (kitty)`, `mouse left press at column 10, row 5`,
`DECRPM answer: mode 2026 synchronized output set`, `DA1 answer: 1;2`).
What a synchronized update (DEC mode 2026) holds is one row, `frame 12:
5 CUP, 4 text, 3 SGR…, 2 ms`, a click opening it to its sequences; an app
that writes a small change outside one (twk writes one cell as it is)
shows its sequences as rows. The bar: what to show (what the app wrote,
what the terminal sent, the notes, the text runs), a word to look for in
the names and bytes, Pause (what comes meanwhile is held and counted,
shown on Resume), Clear. The log holds what came since the terminal
opened, even before the log was (its probe and modes; the last 4 MB of
bytes, decoded when it is opened, the last 20000 entries, a frame's
first 2000), one log per terminal, a replay's too.

**Recording.** twk: Record asks where (`counter.cast` in the workspace
folder by default) and records from then on: what was written to the
terminal (`o`), what it sent (`i`: the keys, and the answers to the app's
queries, which `twk play` leaves out), and its sizes (`r`), every pause
longer than 2 s cut to it (`idle_time_limit` 2, `twk record`'s default),
with a header of the terminal's size, the time, its title and its
`TERM`. The title says `● recording` and the status bar `REC`; the same
command, the status bar or closing the terminal stops it. Begun while an
app runs, the recording begins on the screen the terminal is on (the
alternate one) and the app the extension runs or debugs is asked to paint
all of itself (`ext.twk.reassemble`), so its first frame is a whole
screen; an app on the "any app" terminal is not the extension's to ask,
so start that recording before the app. The file is what twk_dev reads:
`twk play counter.cast` plays it in a terminal, and
twk_test's `screenFrames` over its `Cast.writes` makes a test of it.

**Replay.** twk: Play a Recording opens a terminal of its own at the
recording's size (`counter.cast · twk replay 80x24`) and plays what was
written, each pause cut to the recording's idle limit; what the
recording typed is not replayed, and what the replay's terminal answers
goes nowhere. Its bar, under the terminal: from the start (Home or `r`),
a frame back (Left or `,`), play or pause (Space), a frame on (Right or
`.`), and where it is (`frame 3/42 · 1.25 s / 5.20 s`). A frame is what
`screenFrames` takes for one: an output event that leaves no synchronized
update open. A frame back starts the terminal again (RIS) and writes the
frames before it at once. Played to its end, Play starts it again.

**Copy the screen**: the rows the terminal shows now, without the blanks
that end them or the blank rows at the bottom, as plain text (no colours).

### Not in the first version

Packaging (`vsce`) and the Marketplace; macOS and Windows (written for,
not run: TCP on the loopback interface on Windows); a person's use beyond
the tests (keys VS Code takes before the webview: Ctrl+P, Ctrl+Shift+P
while the panel is focused); kitty's graphics protocol (not in the image
addon for xterm.js 6.0), ambiguous width 2 and bidi (part 3); the render
tree in the inspector; the log saved to a file, or a recording's input
replayed into an app; a recording's markers (`m`) shown as places to go
to (they are read, and played over); a selection of the terminal copied
(not tried).

## 1. Debugging a twk app

Dart-Code runs the SDK's own debug adapter, `dart debug_adapter`
(`src/extension/providers/debug_adapter_descriptor_factory.ts` in
Dart-Code). A Dart CLI launch takes `"console"`: `debugConsole` (the
default), `terminal` or `externalTerminal` (Dart-Code's `package.json`, its
`dart` debugger's launch attributes, 3.146.0-dev on master; the setting
`dart.cliConsole` is the same for every launch). Attach takes
`vmServiceUri` or `vmServiceInfoFile`.

What the adapter does with it is in `dds`'s
`lib/src/dap/adapters/dart_cli_adapter.dart` (5.4.0): for `terminal` it
asks the editor to run (`runInTerminal`, kind `integrated`)

    dart --no-serve-devtools --enable-vm-service=0 -DSILENT_VM_SERVICE=true \
      --write-service-info=<file> --pause_isolates_on_exit \
      --pause_isolates_on_start --timeline_streams=... run <program>

and connects to the VM service the file names; for `debugConsole` it runs
that itself, with stdin, stdout and stderr pipes.

The three ways were run with `editors/vscode/tool/dap_check.py`, a DAP
client that does what VS Code does (initialize with
`supportsRunInTerminalRequest`, launch or attach, breakpoints, continue,
terminate) and serves `runInTerminal` with a pseudo-terminal of its own,
as VS Code's integrated terminal does. The app was
`packages/twk/example/counter.dart`, a breakpoint on `setState` in the Up
key's closure (line 25, column 19: a line breakpoint there stops in every
`build`, the map of key bindings being built there).

**A. `"console": "terminal"`: the app owns VS Code's integrated
terminal.** Works.

- The breakpoint is hit when Up is pressed (top frame
  `_CounterState.build.<anonymous closure>`, from `_KeyBindingsState._take`).
- While paused the tty stays raw (ICANON, ECHO and ISIG off), on the
  alternate screen, nothing written: the screen is frozen as it was.
- Keys typed while paused wait in the tty: Ctrl+C typed then is a key (ISIG
  is off) and quit the app as soon as it was continued (exit 0, tty back in
  cooked mode, alternate screen left).
- The stop button (DAP `terminate`) sends SIGTERM: twk restores the
  terminal (exit 143, cooked, alternate screen left).
- Not run: a SIGKILL, or a hot restart, in this mode; nothing would put
  the tty back then, as nothing but the app knows its modes.

**B. `"console": "debugConsole"` and a twk terminal elsewhere.** Works,
and is the one to build on. The app has no tty, so `Terminal.open` takes
the terminal of the `twk shell` that `TWK_SHELL` in its environment
names, or else the one serving the project
(`openOwnOrShell` in `packages/twk_core/lib/src/terminal/terminal.dart`,
the address file `.dart_tool/twk/shell`, `socket.dart`). The shell is
`twk shell` in any terminal, or the extension's terminal (below), which
speaks the same protocol and is found by `TWK_SHELL` only.

- Run with the extension's shell over a headless xterm.js
  (`tool/headless_shell.cjs`) and `dap_check.py console`: the breakpoint
  is hit on Up from the shell, the app continues and quits on `q`
  (exit 0), the shell's screen back on the normal buffer.
- The stop button: exit 143, the shell back on the normal buffer.
- `kill -9` of the app (a compiled counter, started without a tty): the
  shell writes the bytes the app left it (`Wire.lost`) and the screen is
  back on the normal buffer. This is what A can't do.
- In VS Code with Dart-Code 3.144.0 (installed in a throwaway
  `--extensions-dir`): the test "twk terminal under Dart-Code" below. The
  Debug Console stays free of the app's frames: they go over the socket.

**C. Attach: the app started in a terminal with the VM service, the
debugger attached.** Works (`dap_check.py attach`: the app started in the
pseudo-terminal with `--enable-vm-service=0 --write-service-info=<file>
--pause-isolates-on-start`, attached with `vmServiceInfoFile`, breakpoint
hit, quit, tty restored). But in attach the adapter forwards the VM's
stdout stream to the Debug Console (`_subscribeToOutputStreams`, set in
`attachRequest`): every frame's escape sequences show there as text, as
they did in the run. B has no such cost.

So: debugging works today in all three ways without a change to twk or
Dart-Code. B is the one an extension adds something to: the terminal
survives the app (restart, kill), and is the extension's to instrument.

## 2. The prototype: `editors/vscode`

A VS Code extension in TypeScript (no Marketplace publish, `private`),
whose terminals are xterm.js 6.0 in webviews, each served to its twk app
by a port of `TerminalShell` to node. No node-pty: twk's socket terminal
is the transport, so the app is started by anyone (the extension,
Dart-Code, a shell) and finds its terminal by `TWK_SHELL` in its
environment (part 4, change 1): one terminal per run or debug session,
nothing written into the project.

The code is in layers (part 2b); what each part does:

- `src/core/wire.ts`: the frames of `Wire` (`socket.dart`), protocol 1;
  it and `shell.ts` held to twk_core's golden of the wire
  (`test/unit/core/wire_golden.test.ts`, part 4, change 5).
- `src/core/shell.ts`: the shell's end: binds `shell.sock` in a new
  directory of the system's temporary one (TCP on the loopback interface
  on Windows, not run), with a token, and writes no address file: its
  address is `variable`, the value of `TWK_SHELL` for the app it serves
  (`src/core/address.ts`, the same form as twk_core's
  `LocalAddress.toVariable`); one app at a time (the newest),
  welcome with the size, the environment and what the terminal declares
  (the app's `welcome`, from the capabilities chosen), output to the
  pane as it is, flushes answered once xterm.js parsed what came before,
  input while the app is in raw mode, size changes, the lost bytes
  written when the app goes away; socket and directory removed on stop.
- `src/core/capabilities.ts`: what the terminal is (part 3): the
  presets and each switch, the settings checked, and what they make of
  the welcome's environment and `declares` and of the webview's answers;
  `src/core/emulation.ts` and `src/core/kitty_keyboard.ts`: those
  answers, an app's requests (a notification, progress, the clipboard, a
  link) and kitty's keyboard protocol as pure functions, which the
  webview's bundle takes too.
- `src/core/switches.ts`: what the terminal switches on in the app, the
  screen reader and the debug aids (part 4, change 2): the variables of
  the welcome, the settings' values checked, the pick's items.
- `src/core/vm.ts`, `hot.ts`, `runner.ts`, `process.ts`: hot reload and
  hot restart (part 2a); the run's process behind a port, node's
  `child_process` its implementation. `HotApp` is also what the
  inspector asks of an app (`AppService`): the binding's service
  extensions and the VM service's calls in its isolate, what the app
  posts, each reload done, its binding there.
- `src/core/inspect.ts`, `source_find.ts`, `locator.ts`: the inspector's
  core (part 2d): twk's answers typed and checked, where a widget was
  made looked for in the build methods above it, and the VM service
  lookups that give their sources.
- `src/app/terminal.ts`, `terminals.ts`: a twk terminal, a view served
  by a shell of its own, one per run or debug session (and one for any
  app, which shows its `TWK_SHELL`); `src/app/hot_apps.ts`: run, debug
  (a launch made for a configuration, F5), reload, restart, reload on
  save, and each app ended with its terminal; `src/app/launch.ts`: the
  debug configurations as data (a `"type": "twk"` one as Dart-Code's, what
  one asks for, a session's read back).
- `src/app/inspector.ts`: the inspector (part 2d), over the port of its
  tree view and of an opener of the code; `src/vscode/inspector_view.ts`
  is VS Code's tree view as that port.
- `src/core/sequences.ts`, `seqlog.ts`: the sequence decoder and the
  log's entries (part 2e); `src/app/log_panel.ts` the log's panel over a
  `WebviewPanelPort<ToLog>`, `src/webview/log.ts`, `log_protocol.ts` its
  webview. `src/core/cast.ts` (asciicast as twk_dev's, held to its
  golden), `cast_file.ts` (the file), `src/app/recording.ts` (a
  terminal recorded), `src/app/player.ts` (a recording played back in a
  `TerminalView`), `src/app/screens.ts` (the screen a command takes, its
  text), `src/vscode/recording.ts` (the status bar's `REC`).
- `src/app/webview_view.ts` (the view, over a `WebviewPanelPort`),
  `src/vscode/panel.ts` (VS Code's panel as that port, and the page),
  `src/webview/main.ts`, `src/webview/protocol.ts`:
  the webview: xterm.js and its fit addon, keys (`onData`, `onBinary` for
  X10 mouse) in, frames out (each write acknowledged by xterm.js's write
  callback), resize (fitted to the panel, or fixed by the settings
  `twk.terminal.columns`/`lines`), and a snapshot of the screen's rows for
  the tests; a pick of a cell (`webview/pick.ts`, the point under a
  click as a cell); the messages typed once and checked at both ends.
- `src/vscode/extension.ts`: the commands (the debugger, F5's
  configuration providers, the status bar and the settings are
  `src/vscode/debugger.ts`, `launch.ts`, `status_bar.ts`, `settings.ts`).
  Each Run and Debug opens a terminal of its own, titled by the file
  (`counter.dart · twk 80x24 · xterm.js`), its address given to the app
  as `TWK_SHELL` (Run: the process's environment; Debug: the launch's
  `env`); closing the terminal ends its app (Run: through its process;
  Debug: the session stopped), and a hot restart starts no app whose
  terminal was closed:
  - **twk: Open twk Terminal for Any App**: a terminal that shows the
    `TWK_SHELL=...` an app started anywhere (a shell, a task) takes it
    with.
  - **twk: Run Dart File in twk Terminal**: `dart run <file>` with pipes
    and the VM service on, its output in the "twk" output channel; hot
    reloaded on save, hot restarted on command.
  - **twk: Debug Dart File in twk Terminal**: Dart-Code's launch with
    `"console": "debugConsole"` (way B); hot reloaded on save too.
  - **F5**: a configuration of type `twk` in `launch.json` (the snippet
    "twk: Debug in a twk Terminal", or the first one of a new
    `launch.json`):

    ```json
    { "type": "twk", "request": "launch", "name": "twk: current file", "program": "${file}" }
    ```

    `cwd`, `args`, `env`, `toolArgs` and the rest of Dart-Code's launch
    fields are passed on. A Dart configuration with `"twkTerminal": true`
    is the same. VS Code resolves a configuration whose provider changed
    its type again by the new type, so the `twk` one becomes Dart-Code's
    (`console` `debugConsole`, marked `twkTerminal`), goes through
    Dart-Code's providers, and once its variables are substituted the
    extension's Dart provider opens its terminal and puts `TWK_SHELL`,
    `TWK_DEBUG` (with `keys`) and its `twkSession` in it: the debug
    session is Dart-Code's, with hot reload and restart (part 2a).
  - **twk: Hot Reload** (Ctrl+Alt+R) and **twk: Hot Restart**
    (Ctrl+Alt+Shift+R; Cmd for Ctrl on macOS), while an app runs or is
    debugged so, with a Dart editor or the twk terminal focused.
  - **twk: Choose twk Terminal Capabilities (Presets, Each Switch)**:
    the switch panel (part 3), in quick picks: a preset (`xterm.js`,
    `everything`, `256 colors`, `16 colors`, `no color`, `no synchronized
    output`, `bare`, `no answers`), or each switch from the preset's:
    the colours, the images (none, sixel, iTerm2), then the toggles at
    once (answers, synchronized output, kitty keyboard, cell size,
    notifications, progress, pointer shapes, REP, links, clipboard).
    Kept in `twk.terminal.profile` and `twk.terminal.capabilities` (the
    switches changed from the preset); the next app to connect gets them,
    and with apps running a Hot Restart is offered, which takes them to
    those. The terminal's title says the preset and each switch changed
    (`counter.dart · twk 80x24 · xterm.js, sixel images, kitty keyboard`).
  - **twk: Choose twk Terminal Switches (Screen Reader, Debug Aids)**:
    a pick of several (settings `twk.terminal.screenReader` and
    `twk.terminal.debugAids`: `overlay`, `console`, `frames`, `timeline`,
    `logs`, `rainbow`, `relayout`), which the next app to connect gets,
    a hot restart's too, whoever started it: the welcome's environment
    sets `TWK_SCREEN_READER=1` and `TWK_DEBUG=keys,<the aids>` (`keys`
    as the app's own TWK_DEBUG is then not read), and only those on, so
    with none on the app's own environment decides. The terminal's title
    says the switches on (`counter.dart · twk 80x24 · xterm.js + screen
    reader, overlay`).
  - **twk: Show twk Output**: the output channel (a click on the status).
  - **twk: Show the Sequence Log of the twk Terminal**, **twk: Record the
    twk Terminal as asciicast (Start or Stop)**, **twk: Stop Recording the
    twk Terminals**, **twk: Play a Recording (asciicast) in a twk
    Terminal**, **twk: Copy the twk Terminal's Screen as Text** (part 0,
    part 2e); the log, record and copy as buttons in each twk terminal's
    title bar, play in the explorer's menu of a `.cast` file.
  - **twk Inspector**, a view in Run and Debug (part 2d), with **twk:
    Pick Widgets in the twk Terminal (Pick Mode On)** (pressed: **twk:
    Stop Picking Widgets (Pick Mode Off)**), **twk: Inspector Debug Aids
    (Frame Overlay, Repaint Rainbow, Relayout, Console)** and **twk:
    Refresh the Widget Tree** in its title, **Go to Where the Widget Was
    Made** on each node (inline and in its menu) and **Go to the Build
    Method** on a node that builds.

To run it (part 0 says it for the first version):

```sh
cd editors/vscode
npm install            # node_modules here only; gitignored
npm run compile
code --extensionDevelopmentPath=$PWD ../../packages/twk
# a profile of its own, away from yours:
code --user-data-dir /tmp/twk-vscode/user --extensions-dir /tmp/twk-vscode/ext \
  --extensionDevelopmentPath=$PWD ../../packages/twk
```

then open `example/counter.dart` and run the command "Run Dart File in twk
Terminal" (or "Debug ...", or F5 on a `twk` configuration, with Dart-Code
in that extensions directory), and open Run and Debug for the twk
Inspector. A Dart-Code launch of its own (no `twk` type, no
`twkTerminal`) finds no twk terminal and runs in the Debug Console as
plain output; `twk shell` writes the project's address file and serves
such an app.
Edit and save: the app reloads; twk: Hot Restart starts it again. After a
change to the extension: `npm run compile`, then "Developer: Reload
Window" in the window that runs it (an app it runs ends with it). The
extension's entry is `out/vscode/extension.js`; the webview's script is
`out/media/webview/main.js`, beside the modules of `core/` it takes in
`out/media/core/`.

Tests:

```sh
npm run test:unit      # core/ and app/ under node: fakes for the ports, real sockets and processes where core needs them
VSCODE_EXECUTABLE=/opt/visual-studio-code/code TWK_VSCODE_TEST_DIR=/tmp/twk-vscode-test npm test
# with Dart-Code: its VSIX from Open VSX, installed into that directory's extensions first
curl -sSL -o /tmp/dart-code.vsix "$(curl -sSL https://open-vsx.org/api/Dart-Code/dart-code/latest | jq -r .files.download)"
code --user-data-dir /tmp/twk-vscode-test/user-data --extensions-dir /tmp/twk-vscode-test/extensions \
  --install-extension /tmp/dart-code.vsix
TWK_VSCODE_DART=1 VSCODE_EXECUTABLE=... TWK_VSCODE_TEST_DIR=/tmp/twk-vscode-test npm test
```

`VSCODE_EXECUTABLE` is VS Code's binary (`/opt/visual-studio-code/code`
here), not the `code` launcher on the PATH (`/usr/bin/code`, a script):
the launcher starts VS Code apart and ends at once, so `npm test` says
exit 0 with no test run, and the VS Code it left on the profile has the
next run end with "Running extension tests from the command line is
currently only supported if no other instance of Code is running" (seen
in vx-inspector, on the way to Dart-Code's tests; the run after the one
left was ended passed).

The handover runs the unit tests (`vscode-install`, `vscode-compile`,
`vscode-unit` in `xtask.yaml`; CONTRIBUTING.md) in a copy of the extension in
`.dart_tool/vscode/` at the root, with a `node_modules` of its own, so
neither `out/` nor `node_modules` here change under a running extension.
`npm test` runs VS Code (@vscode/test-electron; without
`VSCODE_EXECUTABLE` it downloads one into `.vscode-test`) on
`packages/twk` with a user-data and an extensions directory of its own.
State now:

- unit, 243 passing (the golden's frames and conversations among them;
  the inspector's below, part 2d; the log's, the recordings' and the
  replay's, 47, part 2e). Hot reload (10): `HotApp` against a VM service
  written in the test: `reloadSources`, then `ext.twk.reassemble`, then
  `ext.twk.log`; a failed reload's errors, no reassemble; one reload at
  a time, those asked meanwhile one more after it; a reload asked before
  the binding registered its extensions held until it does; the app's
  `twk.reload`/`twk.restart` events; a failed attach closes the
  connection. `HotRun` with a real Dart VM (4) and an
  app written in the test that answers the two extensions as twk's
  binding does and counts what its stdin says: a reload keeps the count
  and runs the new code, a broken file reports `Expected ';'` with the
  app counting on, a restart is a new process whose count starts again,
  the app's own `twk.reload`/`twk.restart` work, `stop` ends the app, a
  dart that can't be started ends the run.
  Seen to fail with the reassemble call taken out (3 tests) and with a
  restart that does not start the app again (2). The node process (3): a
  character split across reads, a command that can't start, a write to
  a closed stdin. The run's wait for its VM service (3, a fake process
  and clock: found as written, bounded, ended with the app). The shell
  (9): welcome, output and input, flush, resize; a wrong token
  refused; the lost bytes written when the app goes away; a newer app
  takes over with no disconnect told; a socket of its own in a new
  directory, two shells two; a failed listen leaving nothing; each
  app's welcome asked as it is taken, `declares` left out where empty;
  the app's queries passed to the terminal as they are (what is answered
  is the webview's); socket and directory gone on stop. Seen to fail with
  the lost bytes not written.
  The capabilities (8: the settings checked, the switches changed kept
  and read back, the title, the environment, the declaration in
  twk_core's order, the webview's answers, the presets, the toggles
  picked), the emulation's pure parts (6: DECRQM denied, XTVERSION and
  the cell size, colour queries, an app's requests parsed, links only to
  the web and mail, the progress's text) and kitty's keyboard protocol
  (3: the stacks, the keys encoded, those left to xterm.js); the
  emulation on @xterm/headless (7: twk's probe answered in order, DA1
  last; kitty keyboard pushed and popped per screen; off; no
  synchronized output; no answers; the requests on and off; links);
  and twk itself (`twk_probe.test.ts`, 8): twk_core's `info_app.dart` in
  a Dart VM of its own on a headless xterm.js with the emulation, served
  by core's shell and welcomed as `app/terminal.ts` welcomes, prints
  what it found for each preset and switch (colours, everything, iTerm2,
  no synchronized output, no cell size, bare, no answers), and reads
  Escape, Ctrl+C, Alt+X, Shift+Enter, a, Ctrl+Q back from kitty's
  encodings. Seen to fail: three of them with twk_core ignoring the
  declaration, three of the emulation's and the keys' with kitty's
  keyboard taken out.
  TWK_SHELL's form (2, the strings of twk_core's test). The VM service's
  messages (3) and its connect bounded (1), the webview's messages (3).
  app/ over fakes of the view, the panel, the runner, the
  debugger, the VM service, the status and the clock: the terminals (6:
  served to the app its TWK_SHELL is given to, at the view's size,
  titled by its file, input and resize on; one shell each, one closed
  forgotten; closed before it was up; a takeover with no line between;
  a view back empty: size again, app told, redraw; one for any app
  showing its TWK_SHELL), the webview's view (3: ready, keys, sizes,
  writes; a second `ready`; closed with requests in flight), the
  configurations (4: `twk` as Dart's, wanting a terminal, what one asks
  for, a launch there and back), the terminals' capabilities (3: each
  app welcomed with them then, the view told its answers before the app
  writes, and again when it comes back empty; the app's requests to the
  desktop, a link only to the web or mail, its progress taken away as it
  goes), the hot apps (22: run with TWK_SHELL in
  a terminal of its own, two runs two terminals, a run's terminal closed
  ends it, a run's terminal back empty redraws; no project, nothing to
  reload; debug launch and reload, a configuration's launch with its
  fields kept, two sessions two terminals, a session that did not start,
  a session's terminal closed ends it and no restart, closed during a
  restart, a session started after its terminal closed, a session's
  terminal back empty redraws, debug restart in the same terminal;
  reload on save debounced and off, a save elsewhere, dispose; a failed
  restart, the app's own failed restart, a session with no VM service,
  the save timer on dispose). The bugs of part 2c each seen failing
  first.
- VS Code, 14 passing with Dart-Code 3.145.20260930 (the log's, the
  recording's and the replay's in part 2e; its VSIX from Open
  VSX in the throwaway profile; on eb18101, before the inspector, all 11
  passed, its 4 Dart-Code ones among them, which vx-capabilities had
  left pending; the inspector's 2 in part 2d; the ones below, and hot
  reload's: Run, and Debug under Dart-Code, part 2a), the counter run by
  the extension drawn in a
  new webview's xterm.js titled by its file (alternate screen, Count: 0),
  Up counts, q ends it and the screen is back, no address file in the
  project; its panel closed while it runs, its process gone; F5 on a
  `"type": "twk"` configuration debugged by Dart-Code (`console`
  `debugConsole`, `TWK_SHELL` in its `env`) in a new terminal with hot
  reload, its panel closed ending the session; a Dart configuration with
  `"twkTerminal": true` the same; the webview's xterm.js answers OSC 10 and 11
  (headless xterm.js does not), so twk's probe gets the colors; with
  Dart-Code 3.144: the breakpoint hit with the app on the twk terminal,
  whose screen stays (alternate, Count: 0), continue, Count: 1, the cell
  under "Count" resolved to its widget through Dart-Code's `callService`
  (`ext.twk.select`, then `ext.twk.properties`: a Text), and the stop
  button putting the screen back. Seen to fail with the input not passed
  on, and with the debug launch in `"console": "terminal"` (the app then
  in VS Code's own terminal).
  The capabilities (2): with `everything`, twk_core's `info_app.dart`
  (`TWK_INFO_WAIT=1`) shows kitty keyboard with its flags, sixel and the
  rest declared, and a cell's size the real webview measured; its
  progress in the status bar and gone as it ends; the image addon loaded
  (it answers XTSMGRAPHICS) and the terminal drawing on after a sixel
  image; with switches changed from `xterm.js`, 16 colours, no cell size,
  no progress (its OSC 9;4 dropped), no image addon, and the title saying
  so. Seen to fail with the image addon not loaded.
- One run, the first after Dart-Code was installed, ended before any test
  ran with exit code 1 and no test output; the four runs after it passed.
- Not done: a person using it (all of it was driven by the tests),
  packaging (`vsce`), macOS and Windows, keys VS Code takes before the
  webview gets them (Ctrl+P, Ctrl+Shift+P... while the panel is focused:
  not checked; nor that Ctrl+Alt+R typed in the panel reaches the key
  binding: the tests run the commands), kitty's encodings from a real
  keyboard in the webview (its key handler: the encodings are core's,
  tested against twk itself, the handler not run by a test), the switch
  panel's quick picks (their items and results are core's, tested; the
  picks themselves not driven), a notification, the clipboard, a link
  opened and the pointer's shape in a real VS Code (each through its
  handler on @xterm/headless and the app layer's fakes only).

## 2b. Architecture

```
            vscode/  (adapters: VS Code API)          webview/ (xterm.js, browser)
   extension.ts  panel.ts  debugger.ts  launch.ts main.ts  pick.ts  answers.ts
   status_bar.ts  settings.ts  inspector_view.ts  log.ts
   recording.ts  desktop.ts  capabilities_pick.ts     |
        |   implements the ports, wires it all        |  messages of protocol.ts
        v                                             v  and log_protocol.ts
            app/  (use cases over ports)    <---------+  (typed, checked both ends)
   ports.ts  terminals.ts  terminal.ts  hot_apps.ts
   launch.ts  webview_view.ts  inspector.ts  log_panel.ts
   recording.ts  player.ts  screens.ts
        |
        v
            core/  (pure TypeScript and node, no vscode)
   wire.ts  address.ts  shell.ts  capabilities.ts  emulation.ts
   kitty_keyboard.ts  switches.ts  vm.ts  hot.ts  runner.ts
   process.ts  events.ts  project.ts  inspect.ts  source_find.ts
   locator.ts  sequences.ts  seqlog.ts  cast.ts  cast_file.ts
```

`webview/` is `main.ts` (xterm.js and its addons, the page's; a replay's
bar), `answers.ts` (the emulation: handlers on xterm.js's parser, over
the least of xterm.js it needs, so the unit tests run it on
@xterm/headless), `pick.ts` (a click's cell) and `protocol.ts`; and the
sequence log's page, `log.ts` and `log_protocol.ts`.

Dependencies point down only: `core/` imports nothing of the others,
`app/` imports `core/` (and the protocol's types), `vscode/` imports both;
`webview/` imports only itself and the modules of `core/` that import
nothing but each other (`capabilities.ts`, `emulation.ts`,
`kitty_keyboard.ts`, `sequences.ts`, `seqlog.ts`, with `.js` in their
imports, as a browser's modules need; `cast.ts` is pure too, but no page
takes it): `tsconfig.webview.json` compiles them into its bundle, with the DOM
and without node's types, so one of them that took node would not
compile. The extension side reads `protocol.ts`'s types and checks too. Nothing in `core/` or `app/`
imports `vscode`, so all of it runs under plain node in the unit tests.

The ports (`src/app/ports.ts`), what the editor gives the use cases:

- `TerminalView` (made by a `TerminalViewFactory`): a terminal on the
  screen: size, `ready`, `isActive`, `write` (settled once parsed, or at
  once when closed), `snapshot`, `fixSize`, `answer` (what to answer and
  emulate for the app taken now), `player` (a replay's bar), `setTitle`,
  `reveal`, `close`, and the events `onControl` (a button of that bar),
  `onInput`, `onRequest` (what the app asked of the editor), `onResize`,
  `onClose`, `onReload` (it came back empty: its webview loaded again,
  and is told its answers again). `app/webview_view.ts` is the
  webview's, over a `WebviewPanelPort` (`post`, `setTitle`, `reveal`,
  `dispose`, `onMessage`, `onDispose`) that `vscode/panel.ts` makes of
  VS Code's panel.
- `Debugger`: `start` a `DartLaunch`, `stop` a `DebugSession`, and the
  events `onStarted`, `onVmService`, `onTerminated`.
  `vscode/debugger.ts` is vscode.debug's, with the tracker on the
  sessions of the launches the extension made (their `twkSession`) that
  tells they started and their VM service addresses.
- `Runner` (gives a `RunHandle`): runs an app with hot reload; core's
  `HotRun` over `core/process.ts`'s `ProcessStarter`.
- `Desktop`: what the editor does for an app's requests: `notify`,
  `progress` (a status bar item per terminal, taken away as its app
  goes), `writeClipboard`, `openLink` (only http, https and mailto,
  checked in `app/terminal.ts` whatever the webview says);
  `vscode/desktop.ts` is VS Code's.
- `StatusSink`, `Log`, `Settings` (`capabilities()`: the preset and the
  switches changed), `HotContext` (the `twk.hotApp` key),
  `Clock` (`core/events.ts`: the save's debounce, the bounds of the waits
  for a VM service, the inspector's gap between askings of the tree).
- `InspectorView` (`show` a tree or a message, `reveal` a node,
  `clearSelection`, `visible`, `onVisible`, `onSelect`), `SourceOpener`
  (`open` a place, the focus kept or not), `PickingIndicator` (the pick
  mode's button, `show` on or off) and `Notice` (`say` a line in the
  status bar): the inspector's (part 2d), `vscode/inspector_view.ts`'s
  and `extension.ts`'s. A `TerminalView` also takes `pick` and tells
  `onPick` (a click's cell, with the cursor's row: `PickedCell`), and its
  snapshot may tell the cells of a background of their own.
  What the inspector asks of an app is core's `AppService`, which
  `HotApp` is.
- `ShellStarter` (`app/terminal.ts`): core's `TerminalShell.start` with
  the platform's options (the temporary directory, TCP on Windows).
- `Screen`: a terminal and its traffic as the sequence log, a recording
  and a copy of the screen take it (`name`, `view`, `onDidOutput` with
  whether the app wrote it, `onDidInput`, `onDidNote`, `onDidResize`,
  `onDidDispose`): a `TwkTerminal`, or a `Player`. `CastSink` (`write`,
  `close`): where a recording's lines go, core's `fileSink`. A
  `WebviewPanelPort<To>` is a panel spoken to in the messages `To`: a
  terminal's (`ToWebview`) or a log's (`ToLog`); `vscode/panel.ts` makes
  both of VS Code's panels. The `Clock` tells `now()` too (a recording's
  and a log's times).

Rules for new code:

- Logic that needs no editor (protocols, parsing, a model of the
  terminal or the app) goes in `core/`, with its tests under
  `src/test/unit/core/`.
- What the extension does for the person (a command's behaviour, what
  follows from a session's end) goes in `app/`, against ports; a new need
  of the editor is a new small port in `ports.ts`, faked in
  `src/test/unit/fakes.ts`, tested in `src/test/unit/app/`.
- `vscode/` only adapts: it implements ports with the VS Code API and
  binds commands to use cases, in `extension.ts`, the composition root.
  Its tests are the real VS Code ones (`src/test/suite/`), kept few.
- The webview speaks only the messages of `webview/protocol.ts`; a new
  message is added there, with its check. What it decides (which query
  is answered and how, what an app's sequence asks) is a pure function
  of `core/`, tested there; `webview/answers.ts` only hangs those on
  xterm.js's parser.
- Dependencies are passed in (constructor parameters); no module-level
  mutable state but the one `deactivate` needs (`vscode/extension.ts`'s
  `shutdown`, as VS Code's entry points are module functions); no `any`,
  no cast of what came from outside (a message, a configuration, JSON)
  without a check.

## 2c. Review of the prototype

The prototype as of da974f9 (753f30a, 7b9ef01, da974f9), file:line there.
Fixed: in the restructure (3926ed5) or with a test seen failing first
(fcfa2b8, e36055f; 16 to 20 in vx-session-terminal, each seen failing
with its fix taken out).

Bugs:

1. `src/runner.ts:117,125`: a `dart` that can't be started (ENOENT)
   gets an `error` and no `exit` from node, so the run never ended: its
   `stop`, and so `deactivate`, waited forever, and its directory stayed.
   Fixed (`core/process.ts`: `exited` settles on a start's error), tests
   "a command that can't be started" and "a dart that can't be started"
   (seen: timeouts).
2. `src/runner.ts:121-122`: output decoded chunk by chunk (`b.toString()`),
   a UTF-8 character cut by two reads became two U+FFFD in the output
   channel. Fixed (a `StringDecoder` per stream), test "a character whose
   UTF-8 bytes come in two reads" (seen: `'��\n' !== '─\n'`).
3. `src/extension.ts:66-69`: a terminal asked for again while it was
   starting was returned at once, not yet serving: a second Run in that
   moment started its app before the shell's address file was there, and
   the app found no terminal. Fixed (`app/terminals.ts`: the start shared),
   tests "asked for twice while the first is starting" and "...the first
   fails to start: both fail" (seen: the second not serving; no rejection).
   Gone since with the terminal per session: each Run waits for its own
   terminal to serve before it starts its app.
4. `src/extension.ts:241-244,262`: a debug restart whose `stopDebugging`
   failed left its terminate listener behind and cached the rejected
   promise (`restarting ??=`), so no restart of that session was tried
   again; from the app's own key (`void hot.restart()`) the rejection went
   unhandled. Fixed, tests "a restart whose stop fails" and "the app's own
   restart key ... failing" (seen: 2 listeners for 1; nothing logged).
5. `src/extension.ts:270`: a debug session whose VM service could not be
   reached stayed in the apps reloaded: `twk.hotApp` on, its reload
   answering `ended`, a save "reloading" it. Fixed (taken out), test "a
   debug session whose VM service can't be reached" (seen: one app left).
6. `src/hot.ts:41-44`: a failed `HotApp.attach` (the app gone between
   connect and `getVM`) left the VM service's WebSocket open: nobody else
   held it. Fixed, test "fails to attach" (seen: not closed).
7. `src/extension.ts:306`: the save's reload timer outlived
   `deactivate`. Fixed, test "a save's reload waits for no timer once
   disposed" (seen: 1 timer pending).
8. `src/runner.ts:117`: the app's stdin pipe had no `error` listener; a
   write after the app closed its stdin raised an EPIPE nobody listened
   to, which ends the extension host. Nothing writes there but the tests,
   so latent. Fixed, test "the broken pipe (EPIPE) ends nothing" (seen
   failing with the app closing its stdin while it runs; its first form,
   a write after the app had exited, raised nothing and did not bite).

Types, state and structure (fixed in the restructure, 3926ed5):

9. `src/extension.ts:27,42`: the terminals and the apps were module-level
   maps; now `Terminals` and `HotApps`, made in `activate`.
10. `src/panel.ts:163-171`, `media/terminal.js:51`: the webview's messages
    were cast field by field (`m.columns as number`), and the webview took
    the extension's unchecked, in plain JavaScript; now
    `webview/protocol.ts`'s unions, checked at both ends
    (`isFromWebview`, `isToWebview`; tests "the webview protocol").
11. `src/vm.ts:103-117`: the VM service's JSON was taken as a typed
    object unchecked (`m.id!`); now `parseMessage`, tested.
12. `src/hot.ts:44,48,113,121`: the VM's answers cast (`as { id: string }[]`,
    `as string[]`); now read through a check.
13. `src/extension.ts:208,213`: the debug configuration's `twkProject` and
    the adapter's messages cast; now `twkLaunch` and a check of
    `dart.debuggerUris` (`vscode/debugger.ts`).
14. `src/panel.ts:25,27`: its event emitters were never disposed; the view
    now disposes its own when the panel closes, the terminal its own.
15. `src/extension.ts`: one file of commands, state, debug tracking,
    status bar and save handling; now split by layer and responsibility.

Fixed in vx-session-terminal (16 to 20, left as they were before):

16. `src/extension.ts:157-165`: closing a terminal's panel didn't end the
    app it ran: the app lost its terminal (twk ends it, its terminal
    gone), but a hot restart then started the app again with no terminal
    to find. Now a run's terminal ends its run (`HotRun.stop`, its
    process) and a debug session's stops the session; a session that
    starts once its terminal is gone is stopped; a debug restart checks
    the terminal before it stops the session and again before it launches
    it (closed while it waited for the end: not launched). Tests "closing
    the terminal of a run ends its app...", "...of a debug session ends
    the session; a restart then starts no app", "closed while a restart
    waits...", "a session of a launch whose terminal was closed
    meanwhile..." (seen failing with each check taken out; the first
    restart check only once the fake debugger, as VS Code's, stops an
    ended session no more: the restart then waited for an end that had
    come); in VS Code: the run's panel closed, its process gone; F5's
    panel closed, its session ended.
17. `src/panel.ts:165`: a webview that loaded again (`ready` a second
    time) was taken as nothing new. Now it is the view's `onReload`
    (`app/webview_view.ts`, what the old webview was asked settled, so no
    flush waits on it); the terminal fixes its size again, tells the app
    its size, and the app is asked to paint all of itself
    (`ext.twk.reassemble` without a reload: `HotRun.redraw`,
    `HotApp.redraw`). Tests over a fake panel and fake views (seen failing
    with the second `ready` taken as the first, the terminal's handler
    emptied, and the run's and the session's redraw taken out). Not done:
    the modes the app set (alternate screen, mouse) are the new xterm.js's
    defaults until the app sets them again (a restart): twk has no "set
    your modes again" over the wire; and no real webview was reloaded in a
    test.
18. `src/shell.ts:135,141`: a `listen` that failed left the temporary
    directory made for the socket. Now removed; test "a listen that fails
    leaves no directory behind" (a path too long for a socket: EINVAL;
    seen failing without the removal).
19. `src/shell.ts:240,295`: a newer app taking the terminal over had the
    shell say "the app went away" before the new app's welcome. Now a
    takeover is no `disconnected` (the older app's lost bytes still
    written); tests in `shell.test.ts` and `terminals.test.ts` (seen
    failing with the takeover told as a disconnect).
20. `src/runner.ts:150-155`: the service-info file was polled every 50 ms
    on the wall clock, with no limit but the app's end, so a reload asked
    of an app that never named a VM service waited forever; `src/vm.ts:77`
    a connect that neither opened nor failed waited forever. Now the run's
    directory is watched (`fs.watch`) and the file read as it changes,
    the wait bounded by `serviceInfoPatience` (120 s, `dart run` compiles
    first) on the `Clock`, said so in the output; `VmClient.connect` fails
    after `connectPatience` (10 s). Tests over a fake process and a fake
    clock: the file found as it is written with no timer but the bound,
    the bound ending the wait (a reload answered `ended`), the app's end
    ending it; a server that accepts and never answers the upgrade (seen
    failing with each bound taken out).

## 2a. Hot reload and hot restart

**What Dart-Code does for a Dart CLI app** (Dart-Code master, 6f9f5f8,
2026-10-23; the SDK's debug adapter, `pkg/dap_adapters` on the SDK's
main, where it moved from `dds`'s `lib/src/dap`, and `dds` 5.4.0, the
same there):

- `dart.hotReload` (Ctrl+F5 in a Dart debug session) sends the DAP
  custom request `hotReload`; the adapter's `customRequest` answers it
  with `isolateManager.reloadSources()`, `reloadSources` in each isolate,
  and the report thrown away: a compile error says nothing. The sources
  are reloaded and nothing calls twk's `ext.twk.reassemble`, so the screen
  stays as it was until something rebuilds (seen: with the extension's
  reload replaced by that request, the counter's new text never showed).
  `dart.hotReloadOnSave` sends the same on save; its default is `never`.
- No restart: the CLI adapter has `supportsRestartRequest` false and no
  `hotRestart` custom request (`flutter.hotRestart` sends one; it is
  refused: seen, the restart went no further). VS Code's own restart of
  such a session is stop and launch again.
- The adapter tells the VM service's address (`dart.debuggerUris`) and
  each service extension an isolate adds (`dart.serviceExtensionAdded`),
  and passes `callService` on, but no `Extension` events
  (`handleExtensionEvent` does nothing).

**`twk run` (twk_dev's `HotRunner`) from the extension**: `dart run
twk_dev:twk run <file>` runs from `packages/twk`, which doesn't depend on
twk_dev (in the pub workspace every member is in the package config),
and in a project `twk create` made (twk_dev a dev dependency); in another
project it doesn't. With pipes for stdio its app takes the twk terminal.
But the extension would have no way to ask it for a reload or a restart
(it watches `lib/` and the entry itself; a restart is the app's Ctrl+G H)
and no way to know how a reload ended (it says so in the app's log
only). Not used.

**What the extension does**: the same reload as `HotRunner`, over a VM
service connection of its own (`src/core/vm.ts`: JSON-RPC over node's
WebSocket):

- `HotApp` (`src/core/hot.ts`) finds the binding's isolate, the one that
  registered `ext.twk.reassemble`, then on a reload: `reloadSources` in
  it, and if the report says success `ext.twk.reassemble` (every widget
  rebuilt, each State kept) and a line in the app's log (`ext.twk.log`);
  if not, the compiler's messages in the status and the log, the app
  running on with the code it had. The failure goes to the app's log as a
  warning where `twk run` logs an error: an error opens the app's
  console, which covers the app and takes its keys (seen in the test).
  One reload at a time. The app's own keys (Ctrl+G h, Ctrl+G H:
  `TWK_DEBUG=keys` is set for the app) post `twk.reload` and
  `twk.restart`, which it takes.
- **Run** (`HotRun`, `src/core/runner.ts`): `dart run --enable-vm-service=0
  --no-serve-devtools -DSILENT_VM_SERVICE=true --write-service-info=<a
  file of its own> <file>` with pipes and `TWK_SHELL` its terminal's,
  connects when the file names the service (the directory watched, the
  wait bounded: 2c, 20). Restart: the app it started ended through its `ChildProcess`
  (SIGTERM, which has twk put the terminal back, then SIGKILL after 5 s)
  and started again; the shell takes the new app, so the terminal stays.
- **Debug**: the launch gets `env: {TWK_DEBUG: keys, TWK_SHELL: ...}` and
  a `twkSession` field, the key of its terminal; a debug adapter tracker
  on such sessions connects to the address
  of `dart.debuggerUris` (Dart DDS takes more than one client). Reload
  as above, beside the debugger: breakpoints stay and hit after a reload.
  Restart: the session stopped (`stopDebugging`) and, once it ended,
  the same configuration launched again (its `TWK_SHELL` the same); the
  new app finds the same terminal.
- On save of a Dart file (setting `twk.hotReloadOnSave`, on by default)
  the apps of the project it is in reload, or every app when it is in
  none of theirs (a package they depend on), 100 ms after the last save.
  Leave `dart.hotReloadOnSave` at `never`, or both reload.
- The status bar: `twk: hot reload ready`, `reloading`, `reloaded (N
  libraries, T ms)`, `reload failed` (red, the errors in the tooltip and
  the output channel), `restarting`, `the app ended`.

Tests in VS Code (run in a git worktree, on a copy of the counter in
`packages/twk/.dart_tool/twk_vscode_test/`, which git ignores):

- Run: Up, `Count: 1`; `'Count: '` edited to `'Clicks: '` and saved,
  `Clicks: 1` (the new text, the count kept), status `reloaded`; the
  semicolon of `var _n = 0;` taken out and saved, status `reload failed`
  with `Expected ';'`, Up still counts (`Clicks: 2`); put right, edited
  again, `Taps: 2`; twk: Hot Reload by command; twk: Hot Restart:
  `Taps: 0` in the same terminal, the same run, Up counts; q ends it, the
  status `the app ended`. Seen to fail with the reassemble call taken out
  (no `Clicks: 1`), and, before the failure was logged as a warning, on
  `Clicks: 2` (the console open over the app).
- Debug, with Dart-Code 3.144: a breakpoint on the Up key's `setState`
  set before; `'Count: '` to `'Clicks: '` saved, `Clicks: 0`, status
  `reloaded`; Up stops at the breakpoint, continue, `Clicks: 1`; twk: Hot
  Restart: a new debug session, `Clicks: 0` in the same terminal, a save
  reloads that one too (`Taps: 0`); the stop button, the screen back.
  Seen to fail with Dart-Code's `hotReload` in place of the extension's
  reload, and with its `hotRestart` before the restart.

## 2d. The inspector

The **twk Inspector** view (Run and Debug) shows the element tree of the
app the extension runs or debugs, from the app's own element (the
binding's above it left out), over the extension's own VM service
connection to the app (`HotApp`, part 2a: Run's from its service info
file, Debug's from Dart-Code's `dart.debuggerUris`), so the same in Run
and in Debug. Its logic is `app/inspector.ts` over the ports
`InspectorView`, `SourceOpener`, `PickingIndicator` and `Notice`, and `core/`'s
`inspect.ts` (twk's answers, each checked, its `version` 1),
`source_find.ts` and `locator.ts`; `vscode/inspector_view.ts` is a
TreeView and an opener of the code. Each app is told to the inspector
as its VM service connects and goes (`HotApps.onApp`, with its
terminal); the newest is shown, or the one whose terminal a pick was
made in.

- **Following the tree.** While the view is on the screen, the app shown
  has `treeEvents` on (off again when it goes from the screen, or
  another app is shown): each `twk.treeChanged` asks for the tree again,
  at most once in 250 ms (`refreshGap`, on the `Clock`), so an app that
  builds every frame is asked four times a second. After a hot reload
  (`HotApp`'s `reloaded`), and for the new app of a restart, at once. An
  app whose binding registers its extensions after its VM service
  connected (the usual order under `dart run`) is asked once it is
  (`bound`); one that has drawn no frame is asked again.
- **A node selected** by hand is outlined on the app (`ext.twk.highlight`),
  and nothing else: the tree can be browsed without the editor jumping.
- **The pick mode** (the view's title, or the commands), a toggle as
  Flutter's Select Widget Mode: **Pick Widgets** ($(inspect)) turns it
  on in the terminal of the app shown, and the button shows pressed
  (**Stop Picking Widgets**, $(circle-large-filled), by the context key
  `twk.inspector.picking`) while it is on. Each click on the terminal
  then picks the widget under it: revealed and selected in the view,
  outlined on the app, and opened where it was made (as **Go to Where the
  Widget Was Made**, below), the focus left in the terminal for the next
  pick and for Escape; where that place is not found, the build method
  nearest above the widget (its own first) is opened, and the status bar
  says why (`twk: where _Count was made is not known (no call of _Count's
  constructor found in the build methods above it): _CountState.build
  opened`). The app picks itself (`ext.twk.flags` `select` and
  `selectMany`: the node under the mouse outlined between the presses,
  each press posted as `twk.select`, the app getting none of the mouse).
  Where the
  app can't (the inline mode, which gets no mouse) the terminal's clicks
  do: the webview's `pick` message, each click's cell (`webview/pick.ts`)
  told back as `picked` with the row the cursor is on in the screen shown
  (`cursorRowShown`, scrolled back or not), neither xterm.js nor the app
  getting the click; `ext.twk.select` takes it with `cursorY`, and twk
  finds its region by the cursor's row in it (`Presenter.cursorRow`), so
  a click on an inline app below a shell's lines picks what it is on
  (before, the screen's row was taken as the region's: the widget a few
  rows below, or none). Off (the button, or Escape in the terminal, which
  either the app or the webview tells as a pick of none), the app picks no
  more (`select` and `selectMany` false), its outline goes
  (`ext.twk.highlight` with no id) and the view selects nothing (a
  TreeView has no unselect: its items get new ids, the nodes expanded or
  collapsed by hand kept so). The mode is the terminal's: when its app
  goes the button shows off, and the app of a hot restart, in the same
  terminal, is armed again once its binding is there and the button shows
  on; a terminal closed forgets it. One terminal picks at a time: turned
  on in another, the first's ends.
- **Go to Where the Widget Was Made**: twk keeps no creation locations
  (part 4, change 4), so the widget is looked for in the code. The builds
  above the element (`build` in the tree: a stateless widget's, a
  state's), the nearest first; in each, the calls of its type's
  constructor (`Text(`, `const Text(`, `Text.rich(`, `w.Text(`, `Foo<int>(`;
  in code, not in comments or strings); the first build with one made
  it. Among several calls, the one at the element's place among the
  elements of its type that build made, in the tree's order: those
  below another build are that build's, unless its own code makes none
  of the type, when they were passed to it (a `child`) and count; the
  builds on the way to the element are looked through (a `child` passed
  down, a builder's closure). Exact where there is one call, or as many
  as elements; else the nearest, and the status bar says it is one of
  several. The sources are the VM's: `getClassList` (the classes by
  name, the app's `file:` libraries before the packages', `dart:` ones
  never), `getObject` of the class (its `build`, or its superclasses'),
  of the function (its script and token positions) and of the script
  (its source and token table, read once each), a `package:` URI as its
  file (`lookupResolvedPackageUris`); all asked when a place is wanted,
  read again after a reload. The editor opens at the call, beside the
  terminal, focused (a pick's keeps the focus in the terminal); a guess
  among several calls says so in the status bar, for a pick too. **Go to
  the Build Method** opens the `build` of a node that has one, at its
  name (after `@override`).
- **Debug aids** (the view's title): the frame overlay, the repaint
  rainbow, the relayout highlight and the log console, a pick of several
  as the app has them; kept for the terminal, and given again to the
  next app in it (a restart).

The cost: off (the default, and whenever the view is not on the screen)
`treeEvents` is a test of a flag per frame; measured on a debug JIT of
an app that rebuilds one row of 20 and of 200 every frame (twk_test's
tester, 1000 frames each, three rounds; a scratch program, not kept):
off 27-33 µs and 159-164 µs a frame, on without a client 25-32 µs and
160-161 µs, on with the post's JSON 28-30 µs and 160-161 µs, the same
within the noise. What following costs the app is the tree asked for:
`ext.twk.tree` took 0.2 ms for the 20 rows (6.8 KB of JSON) and 1.5 ms
for the 200 (57 KB), at most four times a second. A place of the code
costs nothing while the app runs: the first "go to" read the classes and
the builds' scripts in 150 ms (the counter's tree, 18 nodes, in the
unit test on twk), the next in 6 ms. The frame benchmark (`bench`) is of
twk_core's frames, which this does not change, so it was not run.

Tests (unit, under node):

- `core/inspect.test.ts` (5): the tree read, a node's fields, a version
  or a shape it doesn't read refused, the select, flags and pick answers,
  what a tree item says, the toggles' items. `core/source_find.test.ts`
  (6): the builds above an element and its place among what each made
  (a child passed through a build, a build that makes none of the type,
  a component made by the build above it), comments (nested), strings
  (raw, triple) blanked, the calls in their forms and in a range, lines
  and token positions, the call picked. `webview/pick.test.ts` (2),
  `protocol.test.ts` (the `pick` and `picked` messages).
- `app/inspector.test.ts` (17), over a fake app, view, opener, pick
  button, notice and clock, the terminals real over fake views: the tree
  of an app connected, none once it went away; followed only while on
  the screen, three events in a gap one asking; a binding after the VM
  service; no frame yet; a reload's tree and code asked again; go to
  source and to a build through a fake VM service (a `package:` URI
  resolved, the classes read once); a node selected by hand outlined and
  nothing opened; the pick mode: on (`selectMany`), two picks each
  revealed, outlined and opened with the focus kept, on again doing
  nothing, off (the app's pick, its outline and the selection gone, the
  button shown on and off); Escape told by the app; the terminal's picks
  (inline),
  `cursorY` passed, picking on until Escape, off by the button; ended
  with its app, armed again for a restart's once bound, forgotten with
  its terminal closed; a widget made in no build found: the build above
  opened and why said, none found said; a pick in another app's
  terminal; the aids given again after a restart; an answer it can't
  read said in the view.
  `core/hot.test.ts` (1 more: what the app posts and reloads passed on,
  the calls in the binding's isolate) and `app/hot_apps.test.ts` (1
  more: a run's, a debug session's and its restart's connections told).
- `app/inspector_twk.test.ts` (1, 9 s): a twk app written in the test in
  `packages/twk/.dart_tool/twk_vscode_unit/` (git ignores it), run by
  `HotApps` over core's `HotRun` (`dart run`, its VM service) in a
  terminal over a fake view: the tree as twk gives it, an Up key's change
  seen through `twk.treeChanged` alone, where three widgets were made
  (a `Text` passed through a `StatelessWidget`'s `child`, the one after
  it, a `Padding` in that widget's build) and the state's build at its
  name, twk's own `KeyBindings` build in `packages/twk/lib`, a pick made
  by an SGR press on the app's screen, a hot reload that moves the lines
  (the new place found), and a restart whose app gets the overlay again
  and is followed; the pick mode on that app: the pick opened where the
  widget was made, a second press picking again (`selectMany`), off
  leaving the app's `select` false. And (1, 3 s) an inline app below
  three lines of a shell's in a terminal over a headless xterm.js
  (`headless_view.ts`): its click, with the cursor's row as the webview
  takes it, picks the Text it is on.
- twk: `service_extensions_test.dart` (2 more): `ext.twk.select` with
  `cursorY` in the inline mode, by `Presenter.cursorRow` (and a `cursorY`
  that is no int refused); `selectMany`: two presses posted, the outline
  following the mouse between them, the mouse reported throughout, a
  press whose release was not reported picking too, Escape while held
  ending it, set off picking no more. twk_core's `inline_app_test.dart`
  (1): the cursor's row finds the region on the screen as it grows into
  the scrollback, and after text on the cursor line.

Seen failing, each with its fix taken out: the event ignored (the
follow test and the one on twk); the binding's `bound` ignored (both; it
was the first run's failure on twk, before `bound` was there); the aids
not given again (both); the terminal's pick not armed (the inline one);
the reload's refresh and forgetting taken out (the unit one; on twk the
reload's rebuilds ask for the tree anyway, so its source moves a line,
and with the code not read again the place was a line off: 23 for 25);
the builds that make none of the type not looked into (on twk: the
`Text` after the passed one went to the passed one's line); the method's
place at its metadata (on twk: the `@override` line). For the pick mode:
the open after a pick taken out (4 unit tests, the one in VS Code: no
editor at the counter's `Text.rich(` in 90 s); the selection not cleared
(3 unit; in VS Code with the explicit unoutline taken out too, the Box
selected by hand before outlined again by twk: "no the outline gone from
the screen"); a restart's app not armed, Escape not ending it (one unit
each); `cursorY` not passed (the inline test on twk: nothing picked in
90 s); twk's `_picked` ending a many pick (the mouse reporting turned
off between the presses); `select`'s `cursorY` ignored; `cursorRow`
giving the visible cursor's row (`cursorY`).

In VS Code (2, `extension.test.ts`, the view shown in Run and Debug):
Run: the counter's tree with `Counter` built by `_CounterState`; Up, and
the tree's `Count: 1` by the event; the Box selected by hand, outlined
on the screen (the webview's snapshot tells the cells of a background of
their own) and nothing opened; the pick mode on, a pick by an SGR press
on the counter's cell of the real webview: the Text selected in the
TreeView, the scratch copy shown at `Text.rich(`, the Text outlined in
place of the Box; a second press on the border: the Box, at `child:
Box(`; off: the outline gone from the screen, the TreeView selecting
nothing, the app's `select` false; "Go to Where the Widget Was Made" from
the tree at `Text.rich(`, "Go to the Build Method" at `build(`; the
overlay on (its `median` drawn) and off; a save's reload, the tree's
`Clicks: 1`; q, the view saying no app runs. Debug under Dart-Code: the
same tree, followed, two picks opened, off and the outline gone, over
the extension's own connection, and gone with the stop button. Seen failing with the view's visibility not passed on
(the tree not followed: no `Count: 1` in 90 s).

Before the pick mode, the person's "pick widget не работает переход в
код?" was run in VS Code (a worktree, Dart-Code 3.145): on
`example/counter.dart` and on a `Text` passed through a
`StatelessWidget`'s `child`, in Run and in Debug, a pick selected the
widget and opened nothing, as it was made to, and Go to Where the Widget
Was Made then opened the right line every time (the inline button and
the palette): the jump was a missing step, not a failure. The inline
mode's pick (Debug with `--inline`) selected the Box below the Text
clicked: the row bug above.

Not done: a person using it; a real click in the webview (the tests
type the SGR press the click would send; the webview's own pick, for
the inline mode, is tested in its parts: the cell's and the cursor's
arithmetic, the messages, the view's port, and against twk over a
headless xterm.js, not clicked in a real webview); the render
tree (`ext.twk.tree` `tree=render`) and `ext.twk.layout` in the view;
a node's properties beyond the tooltip.

## 2e. The sequence log, recording and replay

Part 0 says what they do for the person; here, how, and their tests
(vx-log-record).

**The decoder** (`core/sequences.ts`) cuts the bytes into text runs
(UTF-8, a character cut between reads put together), C0 controls and the
escape sequences of ECMA-48 as xterm.js parses them: ESC with
intermediates and a final byte, SS3, CSI (a private prefix `?`, `<`,
`=` or `>`, parameters, intermediates, the final byte), OSC up to BEL or
ST, DCS, APC, PM and SOS up to ST (tmux's passthrough whole, its doubled
ESCs inside). Of what the app writes a sequence cut off at the end of a
read waits for the next, as twk_test's `Vt` and xterm.js wait; of what
the terminal sends each read is whole (a lone ESC is the Escape key, `CSI
M` and three bytes an X10 mouse report). Each piece is named twice over:
as the app wrote it (`describeOutput`: the CSIs twk and the probe write,
SGR's attributes and colours, DEC modes by name, OSC by number, sixel,
kitty graphics, the queries) and as the terminal sent it (`describeInput`:
keys with their modifiers in xterm's and kitty's encodings, SGR and X10
mouse reports, focus, bracketed paste, and the answers: DA1, DA2, DECRPM,
CPR, kitty's flags, the cell size, OSC 4/10/11, XTVERSION, DECRQSS). It
was written for this, not ported: twk_test's `Vt` is an emulator, whose
parsing is bound up with the screen it keeps, and twk_core's trace
format (`trace.dart`) is raw bytes with times, which this reads as it
reads the wire. Where the two meet, a frame, it is held to twk_dev's
`screenFrames` (below).

**The log** (`core/seqlog.ts`) makes an entry of each piece, with its
time and direction, and of each synchronized update a frame entry holding
its own, its time its beginning (a frame is held until its update ends,
however many reads it takes). Each terminal's traffic is kept as bytes
from its start (`Traffic` in `app/log_panel.ts`, 4 MB at most, the oldest
dropped), so a log opened later begins with the probe; nothing is
decoded until a log is opened. `LogPanel` sends the webview everything
kept when it says `ready` (its first, or a webview that loaded again),
then what comes at most every 100 ms; the webview filters, pauses, opens
frames and tells back what it shows (`shown`, which the VS Code test
reads).

**Recording** (`app/recording.ts`, `core/cast.ts`): `CastWriter` is
cast.dart's, line for line: the header in `toJson`'s order with
`idle_time_limit` written as Dart writes a double (`2.0`), events as
`[1.234567, "o", "..."]` with Dart's `jsonEncode` escapes (JSON.stringify
writes the same: `\u001b`, `\b`, `\t`, `\n`, `\f`, `\r` and nothing else
escaped), output and input each a UTF-8 stream (a malformed byte U+FFFD
as Dart's decoder makes it), an empty read no event, a resize always one,
pauses cut. A recording begun on the alternate screen begins with `CSI ?
1049 h`, `CSI H`, `CSI 2 J`, written with the first output, and the
app's `redraw` (its run's or its debug session's `ext.twk.reassemble`)
paints the rest.

**Replay** (`app/player.ts`): `castSteps` cuts the output into steps as
`screenFrames` cuts frames (the synchronized updates followed through the
decoder, a sequence cut between events too), a resize carried with the
step after it; a step at its time on the `Clock`, the next once the view
parsed it; back is RIS and the steps before at once.

**The golden** `packages/twk_dev/test/cast.golden.json` (made by running
cast.dart on its inputs): what a `CastWriter` writes for a header and
events given as microseconds and hex bytes (a session with a pause cut,
UTF-8 cut and malformed, what JSON escapes, no idle limit), what
`Cast.parse` reads of a file or the message it throws (fields of the
wrong kind left out, each refusal), and the frames `screenFrames` shows of
a file (number, time, size, rows). twk_dev's `cast_golden_test.dart`
holds cast.dart and screenFrames to it (18), the extension's
`cast_golden.test.ts` core/cast.ts, its reader, writer and steps, the
steps played into a headless xterm.js against `Vt`'s rows (18). Seen
failing: Dart with the golden's `2.0` written `2`; the extension with
the idle limit written as JavaScript writes it (`2`) and with the
updates not followed in the steps (3 of the frame cases).

Tests (unit, 47 more):

- `core/sequences.test.ts` (8): each kind cut; a sequence and a character
  cut between reads; tmux's passthrough; the names of what an app writes
  (cursor, erase, REP, SGR in its forms, the DEC modes, the queries, OSC
  2/8/9;4/11/22/52/777, sixel, kitty graphics) and of what the terminal
  sends (keys in xterm's, SS3 and kitty's encodings, paste, SGR and X10
  mouse, DECRPM, DA1, CPR, the cell size, OSC 11, XTVERSION); where an
  update begins and ends; the bytes shown. Seen failing with a cut
  sequence not held.
- `core/seqlog.test.ts` (3): entries, a frame of an update with its own
  and its summary, one across reads, the limits. Seen failing (3) with
  frames not grouped.
- `app/log_panel.test.ts` (6, with `screens`): nothing sent before
  `ready`, then all, then at most every 100 ms; the extension's lines and
  the sizes as notes; clear; a webview loaded again; the terminal's end;
  a screen followed from its start, its log opened later beginning with
  that; one panel per screen; the active screen; the screen's text. Seen
  failing (2) with every entry sent at once.
- `app/recording.test.ts` (5): the header, output, input and sizes at
  their times, a pause cut; begun on the alternate screen; one at a time,
  the title; ended by the terminal's end; a sink that fails. Seen failing
  with the pauses kept, and (4) with the redraw not asked.
- `app/player.test.ts` (4): at its size, each frame at its time, the idle
  limit, the bar's state; pause, on, back, from the start by the bar and
  by keys, the replay's answers going nowhere; to its end and again; a
  view that came back empty. Seen failing with the idle limit ignored.
- `app/record_twk.test.ts` (1, 4 s): packages/twk's `example/counter.dart`
  run by `HotApps` over core's `HotRun` in a terminal over a headless
  xterm.js, recorded from the middle of its session with its redraw, Up
  twice: twk_test's `screenFrames` (a Dart program run in the test) shows
  the file's frames, the first a whole screen, nothing its emulator does
  not know; the player shows the same frames at the same times, each
  screen row for row the same as `Vt`'s; the log names the frames, the
  keys and the alternate screen left. Seen failing with the redraw not
  asked (the app's screen never in the file); with the updates not followed
  in the steps it passed, the counter writing each frame in one event:
  the golden is what holds that.
- `protocol.test.ts` and `webview_view.test.ts`: the player's and the
  log's messages, the bar's controls, `isActive`.

In VS Code (1, `extension.test.ts`, "the sequence log, recording and
replay, the screen copied"): the counter run; twk: Show the Sequence Log;
its webview's rows (`shown`) with `key Up` and the app's `text "1"` after
it; the log beginning with the app's start (`DECSET 1049`, a frame, the
probe's DA1 and the webview's answer); twk: Copy the Screen, the
clipboard's text the screen's (`│ Count: 1 │`); twk: Record to a file,
the title `● recording`, Up, twk: Stop Recording, the header as cast.dart
writes it, the key in it; q; twk: Play: the replay's terminal at the
recording's size, played to its end on the alternate screen
(`Count: 2`), a frame back (`Count: 1`) and on; the screen of the replay
copied. Seen failing with the log's webview showing no new rows (its
`append` taken out of the compiled `log.js`).

Not done: a person using it; the log's filter, pause and frames opened
are the webview's, run in VS Code but not driven by a test (the test
reads what it shows); the bar's buttons clicked (the test sends their
messages); a recording with Dart-Code's debug session (its redraw is
`HotApp.redraw`, the same as a run's, run in the inspector's tests); a
replay of `twk tape`'s or `twk record`'s files in VS Code (the golden and
the counter's recording are of the same format).

## 3. What a terminal can declare, and what the extension can emulate

twk decides what a terminal can do from three things only
(`Terminal._probe` in `terminal.dart`): the link's environment and what
the terminal declares (both in a shell's welcome), and the answers to
the queries the app writes first. The extension holds all three: the
capabilities chosen (`core/capabilities.ts`) make the environment
(`environmentOf`) and the welcome's `declares` (`declarationOf`), and
tell the webview what to answer and emulate (`answersOf`, an `answers`
message as each app is taken), which `webview/answers.ts` does with
handlers on xterm.js's parser, a query denied never reaching xterm.js's
own (answered "not recognised", DECRQM, or not at all).

**What a terminal declares** (part 4, change 3): `declares` in the
welcome, `{"notifications", "progressReports", "pointerShapes",
"repeatChar", "graphics"}`, each only where declared (twk_core's
`TerminalDeclaration`, `link.dart`; the golden of the wire has it). A
link whose terminal declares is a `DeclaringLink` (`SocketLink`; a
`TerminalShell` passes its own link's on); the probe takes each declared
one over its guess, the rest guessed by the environment as before, so a
real terminal, which declares nothing, is as it was. Under what the app
asks itself (`TerminalOptions.graphics`), and declaring the images, the
kitty and XTVERSION graphics queries are not sent. The twk terminal
declares all of them, being sure of itself.

What xterm.js 6.0 itself answers (headless, each query alone): DECRQM 2026
set; 2027, 2048, 69, 2031 and BDSM not recognised; DA1 `?1;2c` (no
sixel); CPR after U+2500: column 2 (ambiguous width 1); nothing to
`CSI ? u` (kitty keyboard), kitty's graphics query (no APC handler: the
query is dropped, which twk takes as no), XTVERSION, `CSI 16 t` (dropped
before any handler sees it unless `windowOptions.getCellSizePixels`),
OSC 10/11/4. In the webview it answers OSC 10 and 11 too (the VS Code
test). It does REP.

The switches, each held to what twk finds by a twk app in the unit tests
(`twk_probe.test.ts`, below):

| switch | how | twk finds |
|---|---|---|
| colours: 24-bit, 256, 16, none | environment (`COLORTERM`, `TERM`, `NO_COLOR`) | trueColor, ansi256, ansi16, none |
| answers off (`no answers`) | DECRQM denied "not recognised", OSC 10/11/4 queries and DA1 dropped, nothing of the webview's | answered false (after the probe's timeout) |
| synchronized output off | DECRQM 2026 "not recognised" | sync off |
| kitty keyboard | the webview answers `CSI ? u` with the flags in force, keeps the flags pushed, popped and set (`CSI > u`, `CSI < u`, `CSI = u`), one stack per screen, and encodes keys as disambiguation says (flag 1, what twk pushes; more is not done, the flags told back say so): Escape, Ctrl and Alt keys, modified Enter, Tab and Backspace as `CSI code ; mods u`, by the key's place for letters and digits; Meta (Cmd) left to VS Code | kittyKeyboard, flags 1; the keys read back as Escape, Ctrl+C, Alt+X, Shift+Enter, Ctrl+Q |
| images: none, sixel, iTerm2 | declared; shown by `@xterm/addon-image` 0.9.0 (sixel and IIP; the page's CSP allows its WebAssembly and blob: images) | graphics none, sixel, iterm2 |
| cell size | `CSI 16 t` answered with the screen element's size per cell | 9x18 (the test's), 0x0 off |
| notifications | declared `osc777`, else `none`; OSC 777 `notify` shown as VS Code's notification | osc777 / none |
| progress | declared; OSC 9;4 shown in a status bar item of the terminal's (`$(loading~spin) counter.dart 40%`), taken away as its app goes | progressReports |
| pointer shapes | declared; OSC 22 sets the CSS cursor over the terminal | pointerShapes |
| REP | declared (xterm.js does it) | repeatChar |
| links | OSC 8 left to xterm.js, a click opened by VS Code (http, https, mailto only); off, dropped: the text alone | (twk writes them without asking) |
| clipboard | OSC 52 put on VS Code's clipboard (never read: a query is dropped); off, dropped | (twk writes it without asking) |

XTVERSION is answered `twk-vscode(0.0.1)` wherever the terminal answers:
none of the names twk knows a terminal by. Offered, and why not:

- **kitty's graphics protocol**: `@xterm/addon-image` has it only in its
  0.10 betas (still "WIP" in its README), which need xterm.js 6.1's
  betas; 0.9.0, the release for xterm.js 6.0.0, shows sixel and iTerm2's
  inline images. The images switch has none, sixel and iTerm2.
- **Ambiguous width 2**: xterm.js's Unicode API registers a provider of
  its own (`wcwidth` and `charProperties` for every code point), but
  gives no way to wrap its own: one that made only the ambiguous ones
  wide would need all of Unicode's width tables in the webview. Not done.
- **Bidi**: xterm.js reorders nothing and doesn't know BDSM, so the only
  true answer is what twk finds anyway (the app orders right-to-left
  text); a terminal that reorders can't be emulated. Not offered.
- **Graphemes (2027), in-band resize (2048), margins (69), colour scheme
  reports (2031) on**: an answer alone would draw wrong cells; xterm.js
  has none of them.

Per capability (`TerminalInfo`, `TerminalCaps`), what else there is:

- **Screen reader** (`TWK_SCREEN_READER`) and `TWK_DEBUG`: the link's
  over the process's (part 4, change 2): a switch, for any app.
- **Size**: fixed sizes and resizes (settings; the size frame).

What the repository has for the wished features:

- **Record/replay**: done (vx-log-record, part 2e): the terminal writes
  the asciicast `twk record` writes, without a pseudo-terminal, held to
  twk_dev's golden, and plays one back in a webview of its own.
- **Sequence log**: done (part 2e), of the terminal's own traffic.
  `TWK_TRACE_INPUT`/`TWK_TRACE_OUTPUT` work over a shell's socket too
  (`openOwnOrShell` opens it as the process's terminal, by reading the
  code; not run); `twk_test`'s `Vt` is a strict oracle that fails on
  sequences it doesn't know; `twk_term`'s emulator a permissive one.
- **Widget tree, cell inspector, overlay**: `ext.twk.tree`, `properties`,
  `layout`, `select` (cell to element path), `highlight`, `flags`
  (`overlay`, the frame overlay; `console`, `rainbow`, `relayout`, `keys`,
  `select`, `treeEvents`), `reassemble`, `log`; `twk inspect` shows them
  in a terminal. The inspector (part 2d) takes them over the extension's
  own VM service connection, as Dart's debug adapter doesn't pass
  Extension events on (`handleExtensionEvent` does nothing in
  `dart.dart`). Left: a cell's colors and attributes are xterm.js's
  buffer's (`getCell`), in the webview, and no view shows them.

## 4. twk-side changes a real version needs

None for the prototype. For a real version:

1. **The shell's address by environment**: done (vx-session-terminal).
   `TWK_SHELL=unix:<path>#<token>` (or `tcp:<host>:<port>#<token>`, the
   token after the last `#`: `LocalAddress.toVariable`, `fromVariable`,
   `LocalAddress.shellVariable`), read by `SocketLink.toShell` from the
   environment `Terminal.open` passes down (`openForProcess`,
   `openOwnOrShell`), before the address file. Set, it is the only shell
   looked for: a value of no such form, or an address nobody listens at,
   is a `TerminalException` saying so (the token never in it), and plain
   output where stdout is no terminal, as with no shell; the project's
   file is not read, so an app given a terminal never lands in another
   one. Empty is unset. Tests in twk_core's `socket_test.dart` (an app
   in a process of its own takes the named shell over the project's,
   none where nobody listens, a value of no such form, empty, and
   `openOwnOrShell` reading the environment it is given only; seen
   failing with the variable ignored) and `socket_wire_test.dart` (the
   form, the same strings as the extension's `address.test.ts`).
2. **`TWK_SCREEN_READER` and `TWK_DEBUG` from the link's environment
   too**: done (vx-link-env). The rule, stated where it is read
   (`TerminalInfo.settings`, `TwkApp.new`, `AppBinding.new`, `runApp`):
   - A `Terminal` of the process's (`Terminal.open`: its own terminal,
     or the `twk shell` it found by `TWK_SHELL` or the project's file;
     `Terminal.connect`) keeps of its link's environment
     `TWK_SCREEN_READER` and `TWK_DEBUG`, where it sets them, empty
     too, as `TerminalInfo.settings` (`TerminalInfo.settingNames`). A
     terminal over a link of the program's own (`Terminal.overLink`: an
     SSH session, a browser's xterm.js) keeps none: its far end is not
     the app's to obey. The rest of the link's environment (`TWK_LOG`, a
     file to write, and `TWK_EDITOR`, a command to run, among it) is
     never read as the app's settings.
   - `TwkApp(environment:)` not given: the process's environment, in
     which the terminal's settings take the place of the process's
     values, variable by variable (the link's wins, so a terminal can
     turn the aids off too, with an empty `TWK_DEBUG`).
     `TwkApp.environment` is that map, so `AppBinding` (the screen
     reader, `DebugAids`, the editor) reads the same. Given, it is the
     whole of it: a test's `const {}`, and twk_ssh's `serveSsh`, which
     gives `const {}` so that neither the server's process nor a client
     switches the aids (its terminal is over a link too, so a client's
     would not count anyway). On the process's own terminal the link's
     environment is the process's, so nothing changes there.
   - `runApp(screenReader:)` not given: the binding's to say, from that
     map. The screen is chosen before the terminal opens, by the
     process's environment, so a terminal that turns the screen reader
     on has the app read out on the alternate screen.

   Tests: twk_core's `link_test.dart` (the settings of a terminal of
   the process's, none over a link), `socket_test.dart` (a shell's
   welcome reaching `TwkApp`, a given environment the whole of it),
   `app_test.dart` (the merge); twk's `binding_test.dart` (the binding
   and `runApp`); twk_ssh's `serve_test.dart` (a client's
   `TWK_SCREEN_READER`, `TWK_DEBUG`, `TWK_EDITOR` reach nothing, the
   app's environment empty); the extension's `switches.test.ts`,
   `shell.test.ts`, `terminals.test.ts`, and in VS Code the overlay and
   the screen reader switched on and off across hot restarts.
3. **Capabilities a terminal can declare that are guessed from known
   terminal names**: done (vx-capabilities). The welcome's `declares`
   (`Wire.welcome`, the golden's welcome frame), read by `SocketLink`
   into a `TerminalDeclaration` (`link.dart`: notifications, progress
   reports, pointer shapes, REP, images; each null where not declared),
   and passed on by a `TerminalShell` whose link declares
   (`DeclaringLink`). The probe takes each declared one over the guess by
   the environment (`notificationProtocolFor`, `progressReportsFor`,
   `pointerShapesFor`, REP's known terminals, `graphicsProtocolFor`),
   which stays for real terminals, as they declare nothing; a field of
   another type or value declares nothing (`fromJson`). Not an
   environment variable: the process's own environment is the app's, and
   a `TWK_CAPS` there would be the program's word, not the terminal's.
   `TerminalDeclaration` and `DeclaringLink` are not exported yet: only
   the socket link declares; a program's own link (twk_web's xterm.js)
   would need them in `twk_core.dart`. Tests: twk_core's `link_test.dart`
   (declared over the guess by `TERM=xterm-kitty`, some declared and the
   rest guessed, the images declared and so not asked, the app's options
   over it, the JSON both ways and the wrong kinds; seen failing, three of
   them, with the declaration ignored), `socket_test.dart` (a shell's
   welcome declaring reaches `TerminalInfo`, a wrong or absent one is
   guessed; a `TerminalShell` welcomes with its link's declaration and
   with no `declares` for none), `shell_wire_golden_test.dart` (the
   golden's welcome now declares: its six conversations failed until
   `FakeLink` declared as the golden says); the extension's
   `wire_golden.test.ts` (the golden's `declares` is what the
   `everything` preset declares, field by field and in order) and
   `twk_probe.test.ts` (seen failing, three of its tests, with twk_core
   ignoring the declaration).
4. **A tree-changed event and where a widget was made**: done
   (vx-inspector), part 2d. `ext.twk.flags` `treeEvents`
   (`DebugAids.treeEvents`, off by default): after each frame in which
   elements built (`BuildOwner.rebuilds`, which every change of the
   element tree is), at most once a frame, the binding posts
   `twk.treeChanged` (`version`, `rebuilds`); nothing for a frame that
   only laid out or painted. And an element's `build` in `ext.twk.tree`
   and `ext.twk.properties`: the type whose `build` makes its child (a
   stateless widget's, a stateful one's state's). twk keeps no creation
   locations: its widgets' constructors are `const` and run no code (a
   `StackTrace` there can't be taken, and a const one is made by the
   compiler), and `dart run` has no kernel transformer such as Flutter's
   track-widget-creation (the SDK's frontend has one, keyed to Flutter's
   own library). So the extension finds the place in the app's code
   (part 2d), at no cost to the app's frames. Tests in twk's
   `service_extensions_test.dart` (off by default, nothing posted; on, one
   event a frame that built, two changes before a frame one, a child
   replaced one more, none for a frame of paint alone, none once off; the
   `build` of a stateful and a stateless element, none for a leaf; seen
   failing with the post taken out of `_afterPresent`, with the flag's
   test turned round, and with `build` left out).
5. **A test of the wire from the outside**: done (vx-wire-golden).
   `packages/twk_core/test/terminal/shell_wire.golden.json` describes
   protocol 1: every kind with its type and direction, each frame as hex
   (`type length payload`) beside what it says (JSON, text or bytes),
   and conversations (an app's visit, input out of raw mode, each
   refusal, a frame of no kind and one too long, a takeover; the app's
   end) as the frames sent and expected, the terminal's input and size,
   what it shows. twk_core's `shell_wire_golden_test.dart` holds `Wire`
   (its declarations read from `socket.dart`), `frame`, `FrameReader`,
   `TerminalShell` and `SocketLink` to it; the extension's
   `wire_golden.test.ts` holds `wire.ts` and `shell.ts` to it (the app's
   end is Dart's alone). The golden is twk_core's, as `socket.dart` is
   the wire's first statement, and in the repository both sides read. It
   found three drifts of `shell.ts`, now as `socket.dart`: a hello that
   is a JSON list was taken for an object, a hello naming no protocol was
   refused as of protocol `undefined` (Dart: `null`), and one not UTF-8
   was decoded with replacement characters (Dart: no hello). A change to
   the wire is made in `socket.dart`, the golden and the extension
   together: each test fails without the others.

## 5. A proposed first version

About 2-3 weeks of one person, beside the twk changes 1 and 2 (a few
days):

1. **The twk terminal** (the prototype, finished): one panel per debug
   session (done: TWK_SHELL), a launch config snippet (done: `"type":
   "twk"`, part 2) or a "Debug in twk Terminal" code lens, status bar
   with the size and profile, copy and paste, focus and the keys VS Code
   would take, theme colors following VS Code's, OSC 52 to the clipboard.
   ~1 week.
2. **Capability switches**: done (vx-capabilities, part 3), but for
   ambiguous width 2 and bidi (part 3 says why) and kitty's graphics
   protocol (not in the image addon for xterm.js 6.0). The screen reader
   and the debug aids: done (part 2).
3. **Inspector**: done (vx-inspector, part 2d): a tree view of
   `ext.twk.tree` that follows the app, a pick on the terminal (the
   node revealed and highlighted), where a widget was made, the frame
   overlay and the other `flags` as toggles, `ext.twk.reassemble` (part
   2a).
4. **Sequence log and recording**: done (vx-log-record, part 2e): a
   panel of the terminal's traffic with times, decoded; recorded as
   asciicast for `twk play`; replayed into a terminal of its own; the
   screen copied as text.

Left for later: kitty keyboard's flags beyond disambiguation (event
types, all keys as escape codes, alternate keys, text), the
external-terminal flavour of B (`twk shell` already is).
