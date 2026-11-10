# Changelog

## 0.1.0

- Create a Test from a Recording: a Test button in the replay's bar and a command on a `.cast` file (explorer menu, palette) run `twk test-from-cast` in the recording's project and open the test it wrote (a check of a line of the screen at each marker of the recording, else of the last screen).
- The sequence log: a stray `?2026l` no longer breaks the frames after it (noted), `CSI 1;5 R` is the answer to a cursor-position query when the app asked for one and is not answered yet, else F3, Alt with Enter/Tab/Ctrl keys and with a multi-byte character are named and read whole, an invalid CSI ends where it breaks, text is decoded per token, and an unterminated string is scanned once; as `twk decode`, held to one golden.
- The sequence log, as `twk decode`: `CSI ? r;c R` answers `CSI ? 6 n` (DECXCPR) and uses the query up, `ESC` before a key's sequence is Alt (`ESC ESC [ A` is Alt+Up), a C0 control inside a CSI is shown and the CSI goes on (CAN and SUB cancel it, ESC begins a new sequence), and the bytes of a cut character are shown before an ESC or a control, not dropped.
- The terminal report shows each twk package's version with where it came from (locked, path, workspace) or `not found`, and whether they agree, with or without a pubspec.lock. A twk run that ends on SIGTERM is no longer signalled again afterwards (its pid may have been reused).
- twk: Show the Terminal Report: what the twk terminal tells an app and answers (environment, declared features, the probe's queries) for the current profile and switches, and the project part of `twk doctor --json` (twk package versions and whether they agree, Dart, running app files, the agents skill). `twk.command` says what `twk` is for it too.
- `.tape` files: the language (highlighting, a hover on each statement), and
  the lenses Run (`twk tape`), Check (`twk tape --check`; a failed Wait or a
  tape that cannot be read is an error on its line) and Preview (the stills of
  its Screenshots and its SVG Output, a click going to the statement);
  `twk.command` says what `twk` is.
The first packaged version (a preview, `.vsix` built from this repository).

- Selection and clipboard in the twk terminal: drag selects (with Shift held
  while the app takes the mouse), Ctrl+Shift+C (Cmd+C on macOS, Ctrl+Insert)
  copies the selection, Ctrl+Shift+V (Cmd+V, Shift+Insert) pastes, bracketed
  when the app asked for it. Ctrl+C and Ctrl+V stay the app's.
- With a twk terminal focused, Ctrl+W, G, N, F, R, T, O and Ctrl+Shift+C reach
  the app and no longer VS Code (Ctrl+W would close the editor and with it the
  app). What VS Code's own terminal leaves to VS Code (Ctrl+P, Ctrl+Shift+P,
  Ctrl+E, Ctrl+K chords, Ctrl+B, Ctrl+J, F1) is still VS Code's here.
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
