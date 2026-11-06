---
title: "Running an app"
about: "What runApp does with the process: when it returns, what ends it, signals, and a missing terminal."
order: 8
---
# Running an app

`runApp(app)` opens the process's terminal, runs the app on it and puts the
terminal back. This page is the contract: what ends the run, and what the
process does in the cases that are not a user at a terminal.

## What ends the run

- The Future `runApp` returns completes when the app quits
  (`AppBinding.quit`, or Ctrl+C below). The terminal is restored by then:
  raw mode, the alternate screen, the mouse and the cursor are as they were.
  The widgets' states are disposed.
- An error that ends the app is thrown from that Future, after the terminal
  is restored, so a `try`/`catch` around `await runApp(...)` sees it and an
  uncaught one prints on a terminal that shows it. It is a `WidgetError`
  when the code of a widget threw it (an `InputListener`'s `onEvent`, say).
  An error in a build, a layout or a paint does not end the app: it shows
  an `ErrorWidget` and goes to the log.
- Ctrl+C quits, when no widget takes the key, unless `exitOnCtrlC` is
  false. A SIGINT sent to the process is the same key.
- Ctrl+Z stops the app for the shell until `fg`, when no widget takes the
  key, unless `stopOnCtrlZ` is false. The terminal is given back to the
  shell while it is stopped and taken again on `fg`. POSIX only; the shell
  has to do job control, or nothing stops. A SIGTSTP from outside (`kill
  -TSTP`) does nothing while the app has the terminal.
- SIGTERM restores the terminal and exits the process with code 143, and
  SIGHUP (on Windows the console being closed) does the same with 129. The
  Future does not complete: the process is gone. A terminal that reads
  nothing keeps none of this from happening on Linux and macOS: it gets a
  second to take what puts its screen back, and its mode is put back then.

## When there is no terminal

`runApp` needs both stdin and stdout to be a terminal, and falls back where
it is not.

- stdout is not a terminal (piped, or redirected to a file), or the
  environment says CI, or `TWK_PLAIN=1`: the app runs on plain output. No
  capability probe is sent and no mode or escape sequence is written; the
  app draws at a fixed size (`COLUMNS` by `LINES`, else 80 by 24), and the
  last frame is written as text when the app ends. Stdin is read only
  where it is a terminal. Ctrl+C and SIGTERM end the app as above.
  `TWK_PLAIN=0` turns the fallback off, and the refusal below is what
  follows.
- stdout is a terminal and stdin is not (a file, a pipe, `/dev/null`, a
  tool that gives the program none): there is no input to read, and
  `runApp` throws a `TerminalException` saying so and what to do. Run the
  app in a terminal; or set `TWK_PLAIN=1` to have it write plain text; or
  start `twk shell` in the project, or point `TWK_SHELL` at one, and the
  app takes that shell's terminal.

An app started from an editor or an IDE that gives it no terminal is the
last case, and the shell is what the editor starts for it.

## Testing the run

`runApp(app, terminal: ...)` takes a terminal of a test's, in memory, as
[Testing](testing.md) shows. To see an app in a real terminal without a
test, or to record a session as a regression test, there are `twk record`
and `twk tape`, which Testing's last section describes. What the process does with real signals and a
real tty is covered by running a built app in a pseudo-terminal, which the
repository's own end-to-end checks do.
