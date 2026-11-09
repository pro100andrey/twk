# Changelog

## Unreleased

Added:

- `TerminalEmulator.debugAssertInvariants`, the emulator's own state checked
  (cursor, margins, screens, tab stops, saved cursors, scrollback); `feed` and
  `resize` end with it as an `assert`. Input bytes are still clamped or
  ignored.
- `Pty.foregroundProcessGroup`, the process group in the foreground of the
  terminal: another than the program's while a shell runs a job, to ask
  before closing one that is busy.
- `TerminalView(canRequestFocus: false)`: a terminal to read only, as of
  a log a program writes, which a press does not focus and no key reaches;
  the wheel scrolls its scrollback.

## 0.3.0

Fixed:

- The emulator makes one screen wherever the program's writes are cut: a cluster
  continued in a later write acts as in one write, and a control ends it.
- A `TerminalSession` disposed before its program started completes `exitCode`
  with null.
- A color spec with a sign or whitespace in a channel is no color for OSC 4, 10,
  11 and 12.

## 0.2.0

- On macOS `Pty.start` fails when the SIGCONT that lets its suspended
  program run is refused, killing and waiting for the program, where the
  program stayed stopped and the `Pty` never ended; and the kqueue that
  watches the program is closed when setting it up fails.
- A program `Pty.start` spawned and killed when setting it up failed after
  the spawn is waited for, so no zombie of it is left until the process
  ends.
- `Pty` leaves the CI variables (`CI`, `CONTINUOUS_INTEGRATION`,
  `BUILD_NUMBER`, `RUN_ID`) out of its program's environment, as it does
  the host terminal's: a twk app in it draws in the emulator, not as for a
  CI log. `Pty.exitCode` knows the code on macOS too when the VM waited
  for the program first, and `Pty.tellsExitCode` says where it does.
- `Pty.debugUnreadOutput`: the bytes of the program's output the master
  holds unread (FIONREAD), for a test's report of a wait that failed.
- `Pty.exitCode` knows the code of a program that ends at once on macOS
  too: the program is spawned suspended (POSIX_SPAWN_START_SUSPENDED) and
  let run once its kqueue watch is set, which a VM reaping it could beat
  before. On Linux `Pty.tellsExitCode` is true only where the pidfd is made
  with the program (pidfd_spawn, glibc 2.39), not opened after it.

Breaking:

- A cell's style id is a `StyleId` (package:twk_core): `TerminalEmulator.styleAt`
  answers one, and `TerminalLine`'s constructor, `clear`, `erase` and
  `resize` take one, `StyleId.base` for the default style where 0 was.
  `TerminalLine.styles` stays a `Uint32List`.

## 0.1.0

The first release.

- `TerminalEmulator`: a permissive VT emulator (xterm's sequences, the
  alternate screen, scroll margins, a scrollback, wide characters, SGR
  in 16, 256 and 24-bit colors, OSC 8 links, the mouse's and the
  keyboard's encodings), its screen drawn by the core's `Canvas`, resized
  keeping what it shows. Its styles and glyphs, in tables of its own, are
  swept as a screen's are (`sweepFloor`), and its styles painted as they
  are, with no pen each, so a program of ever more 24-bit colors or new
  clusters (a video, an image viewer) keeps those on its screens and
  scrollback, not every one it sent.
- `Pty`: a pseudo-terminal through dart:ffi on Linux and macOS, a program
  run in it with its size, environment and working directory.
- `TerminalView`: a widget that runs a program in a terminal of its own,
  keys and the mouse passed to it, its title, its bell and its selection.
- The emulator and `TerminalView` on the web too (`platforms` lists it),
  over a link of the app's own: `Pty` there throws `UnsupportedError`.
