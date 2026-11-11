# twk for VS Code

Run and debug [twk](https://github.com/pro100andrey/twk) terminal apps (Dart)
in a terminal of the extension's own, beside the editor.

- **A twk terminal per app.** Run or Debug a Dart file and its app draws in an
  xterm.js panel of its own, titled by the file. The app finds it through
  `TWK_SHELL` in its environment, so it needs no tty: the Debug Console stays
  free of its frames and the terminal survives a hot restart.
- **Run, Debug, F5.** Run with `dart run`; Debug through the Dart extension;
  F5 on a `"type": "twk"` launch configuration.
- **Hot reload on save**, and hot restart (Ctrl+Alt+R, Ctrl+Alt+Shift+R): every
  widget is rebuilt with its state kept.
- **What the terminal is**: presets and switches (colours, sixel and iTerm2
  images, kitty's keyboard protocol, synchronized output, notifications,
  links, the clipboard), a screen reader, and twk's debug aids.
- **The twk Inspector** in Run and Debug: the widget tree (or the render tree, switched in its title), a twk Node view of
  the selected widget's properties and layout, a pick mode that opens where a
  clicked widget was made, the frame overlay, the repaint rainbow.
- **The app's log** (levels, filter, pause; stack frames open the code), as
  `twk logs` shows it.
- **The sequence log** of what the app and its terminal send each other,
  **recording and replay** as asciicast (the format of `twk record` and
  `twk play`), **create a test** from a recording (`twk test-from-cast`), and
  **copy the screen** as text. **twk: New Project** (`twk create`: template,
  folder, files for coding agents) and **twk: Install Agent Skill** (`twk
  agents`) need twk_dev: the project's own, else `dart pub global activate twk_dev`
  (offered, never run for you).
- **Golden screens**: a file of twk_test's `matchesScreenFile` opened with
  twk: Open Screen File as a twk Screen (or "Open With..." twk Screen) is drawn
  cell by cell in its colours, with Text and Styles toggles. When a test
  failed on it, twk_test leaves the screen it saw beside the file as
  `<file>.actual`; the editor then shows both with the cells that differ marked,
  and **Accept Actual** makes that screen the golden (the file
  `TWK_UPDATE_GOLDENS=1` would write). Add `*.txt.actual` to `.gitignore`.
- **`.tape` files** (`twk tape`, VHS's language): highlighting, a hover on each
  statement from its documentation, and the lenses **Run** (`twk tape`: the
  `.cast` and SVGs it names, with Preview and Play offered after), **Check**
  (`twk tape --check`: the tape as a test; a Wait that timed out, or a tape twk
  cannot read, is an error on its line, taken away by the next edit) and
  **Preview** (the stills of its Screenshots and its SVG Output in a strip; a
  click goes to the statement). The problems are twk tape's own: there is no
  second parser here.
- **The terminal report** (twk: Show the Terminal Report): what an app is told
  by the twk terminal as the settings have it (`TERM`, `COLORTERM`, `NO_COLOR`,
  the switches' variables, what the welcome declares), which of the probe's
  queries are answered, denied or left silent, and what the terminal does
  for notifications, progress, links and the clipboard; and, from `twk doctor
  --json` of the project of the active file, the versions of twk's packages in
  its `pubspec.lock` and whether they agree, the Dart SDK, the files of
  `.dart_tool/twk` (listening or left behind) and the skill for agents. It
  follows a changed setting; Refresh asks `twk doctor` again.

Open a Dart file of a twk app, press Ctrl+Shift+P and type "twk".

## Requirements

- The Dart SDK on the `PATH` (`dart run`).
- The [Dart extension](https://marketplace.visualstudio.com/items?itemName=Dart-Code.dart-code)
  (Dart-Code) for Debug and F5; Run needs only the SDK.
- For the Inspector, the app's log and the debug aids, the app's project uses
  twk 0.3.0 or later (`package:twk`): they ask the running app for its
  service extensions (`ext.twk.*`), `TWK_DEBUG=logs` and `TWK_EDITOR`. A
  project with an older twk still runs, reloads and restarts in the terminal.
  `dart run twk_dev:twk create` makes a project that has all of it.
- Tried on Linux only; macOS and Windows are written for and not run.

## Settings

`twk.terminal.profile` and `twk.terminal.capabilities` (what the terminal is),
`twk.terminal.screenReader`, `twk.terminal.debugAids`, `twk.terminal.columns`
and `twk.terminal.lines` (a fixed size), `twk.codeLens` (the lenses over a twk app's `main`), `twk.command` (what `twk` is, for the tapes and the terminal report: `dart run twk_dev:twk` in the project, or `["twk"]` when activated globally), and `twk.hotReloadOnSave`. Keep the
Dart extension's `dart.hotReloadOnSave` at `never`, or both reload.

## From source

This is a preview. To run it from the repository, or to build the `.vsix`:

```sh
cd editors/vscode
npm install
npm run compile
code --extensionDevelopmentPath=$PWD path/to/your/twk/project

npm run package        # twk-vscode-<version>.vsix
code --install-extension twk-vscode-*.vsix
```

[DESIGN.md](https://github.com/pro100andrey/twk/blob/main/editors/vscode/DESIGN.md)
says how it works, how it was tested and what is not done yet.
