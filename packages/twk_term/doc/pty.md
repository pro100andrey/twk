# The pseudo-terminal

The [README](../README.md) is where to start. This is the `Pty` a program runs
in.

`Pty.start(executable, arguments, width:, height:, workingDirectory:,
environment:, includeParentEnvironment:)` runs a program in a new
pseudo-terminal; a `ProcessException` when it can't (no such program, no such
directory), an `UnsupportedError` off Linux and macOS. On the web the `Pty` is
a stand-in whose `start` throws, so that an app with a `TerminalSession` over
a link of its own (a scripted shell, a remote one) compiles for the browser
too (`tool/web_check.dart`'s gallery case).

- **The program's terminal**: the program leads a session of its own with the
  pseudo-terminal as its controlling terminal and its process group in the
  foreground, so `tty` names `ttyName` and `/dev/tty` opens, Ctrl+C, Ctrl+Z
  and Ctrl+\ written to it are signals to that group, and a shell runs jobs:
  `foregroundProcessGroup` (tcgetpgrp on the master) is the program's `pid`
  while it waits, a job's while one runs, so an app can ask before closing a
  busy shell.
  Its descriptors 0, 1 and 2 are the terminal, nothing else is inherited;
  every signal is at its default (the VM's ignored SIGPIPE isn't passed on)
  and none is blocked. IUTF8 is set, so the line discipline erases a UTF-8
  character whole.
- **Its environment**: this process's (unless `includeParentEnvironment` is
  false) with `TERM=xterm-256color`, the dialect the emulator speaks, and
  `environment` over both; an executable without a slash is looked for in that
  PATH.
- **Out**: `output`, a single-subscription stream of what the program writes,
  in pieces of up to 64 KiB. While it isn't listened to or is paused, the
  terminal is read no further and the program blocks in its writes, as with a
  terminal that scrolls no more. It ends when the terminal hangs up: the
  program and whatever it left running closed it, or `close` was called.
- **In**: `write(bytes)`; what the terminal doesn't take now (the program
  isn't reading) waits, in order.
- **Size**: `resize(width, height)` sets what the program reads with
  TIOCGWINSZ; its foreground group gets SIGWINCH.
- **The end**: `exitCode`, the program's exit code or the signal that killed
  it negated, as `dart:io`'s `Process.exitCode`; it can come before `output`
  ends, while something the program left running still writes. `kill(signal)`
  signals the program, `close()` hangs the terminal up as closing its window
  does (SIGHUP for the program and its foreground job). A signal goes through
  the pidfd made with the program where there is one (`pidfd_send_signal`,
  glibc 2.36), which reaches that process and no other, else to its `pid` only
  while that is positive: `pid` is -1 for a program that ended before its id
  was read (the VM may reap it first), and kill(2) with -1 would signal every
  process of the user. Nothing waits on a `pid` that is not positive.

`twk record` of [twk_dev](https://pub.dev/packages/twk_dev) runs the command
it records in a `Pty`.

The child is made with `posix_spawn` (`pidfd_spawn` where glibc has it, 2.39),
never by forking the VM, whose other threads would leave a forked copy only
async-signal-safe calls — and the VM runs Dart code between any two FFI calls.
The spawn attributes start a new session (`POSIX_SPAWN_SETSID`: glibc 2.26;
macOS has it too) and reset the signals; the file actions open the slave as
descriptor 0 — the session's leader opening a terminal without `O_NOCTTY`
makes it its controlling one, with its process group in the foreground, so no
`TIOCSCTTY` (which would need code in the child) is needed — duplicate it to 1
and 2, change the directory and close the rest (`addclosefrom_np`, glibc 2.34;
`POSIX_SPAWN_CLOEXEC_DEFAULT` on macOS). macOS performs the file actions
before it makes the new session, so its slave becomes no controlling terminal
there (Ctrl+C would signal nothing, a shell run no jobs, the hang-up send no
SIGHUP): the program is spawned through `/bin/sh`, the session's leader by
then, which opens the slave again, making it the controlling terminal, and
execs the program through `env -i`, in the environment given and with its name
as `argv[0]`, the pid the program's along the way. An isolate of its own polls
the master (non-blocking) and a pipe the main isolate tells it through (output
taken, a write waiting, closed), and waits for the program's end.

The VM waits for *any* child (`waitpid(-1)`) while a `dart:io` `Process` it
started runs — the test runner's compiler does throughout — and may so take
the program's end first. Linux 6.15 and later still tell it through the pidfd
made with the program (`PIDFD_INFO_EXIT`); elsewhere `exitCode` is null then.
macOS revokes a session's controlling terminal once its leader ends: a
descriptor of the slave reads nothing more, and what the program left running
writes to it no more; `modesAtEnd` keeps the terminal's attributes as the
program left them, read through the master. Tested on Linux (x86-64, glibc
2.44, Linux 7.2) and macOS (arm64, macOS 26.6); macOS's exit codes taken by
the VM would need kqueue's `NOTE_EXITSTATUS`.
