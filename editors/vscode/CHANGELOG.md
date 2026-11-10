# Changelog

## 0.1.0

The first packaged version (a preview, `.vsix` built from this repository).

- A twk terminal of the extension's own for each app run or debugged from
  VS Code, found by the app through `TWK_SHELL`; presets and switches for what
  the terminal can do.
- Run, Debug and F5 on a `"type": "twk"` launch configuration; hot reload on
  save, hot reload and hot restart commands.
- The twk Inspector (widget tree or render tree, switched in its title with the
  selected node's counterpart selected; twk Node, pick mode) and the app's log
  panel.
- The sequence log, recording and replay as asciicast, copy of the screen
  as text.
- A `file:` link of the app opens only a file whose real path is in a workspace
  folder (a symbolic link out of it does not), names compared without case on
  Windows and macOS.
- Needs twk 0.3.0 or later in the app's project for the Inspector, the log
  and the debug aids.
