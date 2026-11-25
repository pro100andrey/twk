# Changelog

## Unreleased

- Run compiles its app through a resident frontend compiler of the
  extension's own (`dart run --resident`), kept between runs and ended with
  the window: a hot restart compiles what changed, 0.3 to 0.5 s where it
  took 3.7 s for a small app.
- Run or Debug of a file whose app has ended takes its panel again,
  instead of opening one more beside it.
- A hot restart says how long it took, `twk: restarted (N ms)`, in the
  status bar and the output, as a reload does.
- A hot restart runs the app's `main` again in a new isolate of its
  process, as Flutter's does, where its twk has the restart in the process
  (`ext.twk.teardown`): tens of milliseconds, the debug session and its
  breakpoints kept, the app's own `Platform.script`; an app paused at a
  breakpoint is resumed first, which the output says. A change the VM can't
  reload, or an older twk, restarts it as a new process as before.

## 0.1.0

The first packaged version (a preview, `.vsix` built from this repository).

- A twk terminal of the extension's own for each app run or debugged from
  VS Code, found by the app through `TWK_SHELL`; presets and switches for what
  the terminal can do. It speaks all of kitty's keyboard protocol to an app
  that pushes it (`TerminalOptions.kittyKeyboardFlags`): event types (repeat
  and release), alternate keys, all keys as escape codes and associated text;
  `CSI ? u` tells them back.
- The terminal's colours (background, foreground, cursor, selection, the 16
  ANSI colours) are VS Code's terminal colours and follow a change of the
  colour theme; an app asking for the background (OSC 11) gets the theme's,
  so its light or dark detection is right.
- Selection and clipboard: drag selects (with Shift held while the app takes
  the mouse), Ctrl+Shift+C (Cmd+C on macOS, Ctrl+Insert) copies the
  selection, Ctrl+Shift+V (Cmd+V, Shift+Insert) pastes, bracketed when the app
  asked for it. Ctrl+C and Ctrl+V stay the app's.
- With a twk terminal focused, Ctrl+W, G, N, F, R, T, O and Ctrl+Shift+C reach
  the app and no longer VS Code (Ctrl+W would close the editor and with it the
  app). What VS Code's own terminal leaves to VS Code (Ctrl+P, Ctrl+Shift+P,
  Ctrl+E, Ctrl+K chords, Ctrl+B, Ctrl+J, F1) is still VS Code's here.
- A `file:` link of the app opens only a file whose real path is in a
  workspace folder (a symbolic link out of it does not), names compared
  without case on Windows and macOS.
- The status bar shows the active twk terminal (the panel focused, else the
  newest) as `twk 44x7 · xterm.js · overlay`: its size, profile and the
  switches on; a click opens twk: Choose twk Terminal Capabilities.
- Run, Debug and F5 on a `"type": "twk"` launch configuration; hot reload on
  save, hot reload and hot restart commands. A twk run ended on SIGTERM whose
  child ignores it leaves no child: SIGKILL goes to the group after the grace
  (POSIX), only while the group still has a member.
- The twk Inspector (widget tree or render tree, switched in its title with
  the selected node's counterpart selected; twk Node, pick mode) and the
  app's log panel.
- Code lenses Run in twk Terminal and Debug in twk Terminal over the `main` of
  a twk app (`runApp` or `TwkApp` in a file importing twk), not over test
  files (by their place in their package: `test/` under the nearest
  `pubspec.yaml`), off with `twk.codeLens`.
- The sequence log, recording and replay as asciicast, copy of the screen as
  text. The log reads as `twk decode` does (held to one golden with it). It
  can be saved for a bug report: the log panel's Save… button, or twk: Save
  the Sequence Log of the twk Terminal to a File; a `.cast` gets the bytes
  with their times (the app's output, what the terminal sent, the notes as
  markers) which `twk decode`, `twk play` and the replay here read, any other
  name the rows as text.
- Replay markers: the markers of a recording (`twk record --marker-key`'s,
  this extension's, a hand-edited file's) are drawn on the replay bar's track
  with their labels as a tooltip, and `]` / `[` (or the bar's buttons, or a
  click on one) go to the next and the previous, as `twk play`. twk: Leave a
  Marker in the Recording of the twk Terminal (palette, while recording)
  leaves `marker <n>`.
- Replay Input into App: twk: Type a Recording's Keys into the App in the twk
  Terminal (palette, a `.cast` file's menu in the explorer, or the Keys button
  of the replay's bar) types the keys of a recording (made with input: the
  extension's recordings, `twk record --keys`) into the app running in the
  twk terminal, either at their recorded times or a step each time the status
  bar item is clicked, to reproduce what the recording shows. The terminal's
  answers to the app's queries are left out, told from keys as `twk record
  --replay` does.
- Create a Test from a Recording: a Test button in the replay's bar and a
  command on a `.cast` file (explorer menu, palette) run `twk test-from-cast`
  in the recording's project, one at a time, and open the test it wrote (a
  check of a line of the screen at each marker of the recording, else of the
  last screen).
- Trace viewer: twk: Open a Driver Trace (`twk.openTrace`; the explorer's menu
  on a `.trace.jsonl`, an Open Trace lens over `driverTest(`, a click on the
  trace's path in a terminal) shows twk_driver's trace step by step: the steps
  (passed, failed), the screen before, between frames and after a step with
  the target's cells outlined, and the step's facts, widget tree, app log and
  sequences.
- Golden screens: a file of twk_test's `matchesScreenFile` opens in a custom
  editor, twk Screen (twk: Open Screen File as a twk Screen, "Open With...",
  the explorer's menu in a `goldens` folder), drawn in its colours with Text
  and Styles toggles; with the `<file>.actual` a failed test leaves (twk_test
  after this version), the golden and the actual side by side with the
  differing cells marked, and Accept Actual.
- `.tape` files: the language (highlighting, a hover on each statement), and
  the lenses Run (`twk tape`), Check (`twk tape --check`; a failed Wait or a
  tape that cannot be read is an error on its line) and Preview (the stills of
  its Screenshots and its SVG Output, a click going to the statement);
  `twk.command` says what `twk` is.
- twk: New Project (`twk create`: a pick of the template with its description,
  of the folder and of the files for coding agents, then it offers to open the
  project) and twk: Install Agent Skill (`twk agents` in the project, saying
  what it wrote, removed and left). Where the workspace has no twk_dev the
  globally activated one (`dart pub global run twk_dev:twk`) is used, and
  where there is none the message offers to activate it (you press Enter).
- twk: Show the Terminal Report: what the twk terminal tells an app and
  answers (environment, declared features, the probe's queries) for the
  current profile and switches, and the project part of `twk doctor --json`:
  each twk package's version with where it came from (locked, path,
  workspace) or `not found`, and whether they agree, with or without a
  pubspec.lock, Dart, running app files, the agents skill.
- Needs twk 0.3.0 or later in the app's project for the Inspector, the log
  and the debug aids.
