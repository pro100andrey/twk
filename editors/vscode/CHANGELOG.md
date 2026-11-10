# Changelog

## 0.1.0

The first packaged version (a preview, `.vsix` built from this repository).

- The code lenses leave out a test file by its place in its package (`test/` under the nearest `pubspec.yaml`), not by any `test` directory in its absolute path.
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
- The terminal's colours (background, foreground, cursor, selection, the 16 ANSI
  colours) are VS Code's terminal colours and follow a change of the colour
  theme; an app asking for the background (OSC 11) gets the theme's, so its
  light or dark detection is right.
- Code lenses Run in twk Terminal and Debug in twk Terminal over the `main` of a
  twk app (`runApp` or `TwkApp` in a file importing twk), off with
  `twk.codeLens`.
- Golden screens: a file of twk_test's `matchesScreenFile` opens in a custom
  editor, twk Screen (twk: Open Screen File as a twk Screen, "Open With...", the
  explorer's menu in a `goldens` folder), drawn in its colours with Text and
  Styles toggles; with the `<file>.actual` a failed test leaves (twk_test
  after this version), the golden and the actual side by side with the
  differing cells marked, and Accept Actual.
- The code lenses are not over test files (`*_test.dart`, under `test/`); a
  golden checked out with CRLF line ends opens as a twk Screen; a quote inside
  a string's `${...}` no longer throws off where the Inspector finds a widget's
  source.
- Needs twk 0.3.0 or later in the app's project for the Inspector, the log
  and the debug aids.
