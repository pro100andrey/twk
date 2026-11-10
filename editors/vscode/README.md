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
  `twk play`), and **copy the screen** as text.

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
and `twk.terminal.lines` (a fixed size), and `twk.hotReloadOnSave`. Keep the
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
