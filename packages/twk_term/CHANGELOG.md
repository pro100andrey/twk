# Changelog

## 0.1.0

The first release.

- `TerminalEmulator`: a permissive VT emulator (xterm's sequences, the
  alternate screen, scroll margins, a scrollback, wide characters, SGR
  in 16, 256 and 24-bit colors, OSC 8 links, the mouse's and the
  keyboard's encodings), its screen drawn by the core's `Canvas`, resized
  keeping what it shows.
- `Pty`: a pseudo-terminal through dart:ffi on Linux and macOS, a program
  run in it with its size, environment and working directory.
- `TerminalView`: a widget that runs a program in a terminal of its own,
  keys and the mouse passed to it, its title, its bell and its selection.
