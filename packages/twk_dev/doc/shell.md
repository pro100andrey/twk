# `twk shell`

Run it in a second terminal, then start the app from the IDE: its
`Terminal.open()` finds no terminal on stdin and stdout, finds the project's
shell instead, and draws in the shell's terminal over the socket (twk_core's
`TerminalShell`, `Terminal.connect`). The app is paused at a breakpoint, the
screen stays as it was; the app does its capability probe, its modes and its
frames over the socket as it does on its own terminal, and its stdout and
stderr stay the IDE's.

The shell holds what the app can't from its own process: raw mode while an app
has the terminal (input passed on byte for byte, Ctrl+C included), each change
of size (SIGWINCH, polled on Windows), and putting the terminal back: the app
tells the shell the bytes that undo its modes as it sets them, and when it
goes away without writing them — killed, or restarted by the debugger — the
shell writes them and turns the console back to cooked mode. Output is written
a whole frame at a time, so a killed app leaves no sequence cut short. One app
at a time: a newer one takes the terminal over and the older one is
disconnected (its `run()` ends with a `TerminalException`), as when the shell
goes away. Between apps the shell is in cooked mode and drops input; Ctrl+C
then stops it (exit 0), as do SIGTERM (143) and SIGHUP (129), each putting the
terminal back and removing the address file. A second shell for the same
project, or one started without a terminal, exits with 1.
