# How twk_term is tested and how fast it is

For those who work on the package. The [README](../README.md) is where to
start with using it.

## Tests

Sequence by sequence, vttest's screens (cursor movements with a border of `*`s
and `+`s around a frame of `E`s, autowrap mixed with controls), and the output
of real programs captured in an 80x24 pseudo-terminal with `tool/pty_run.py`
and checked as screens: a bash session, nano editing a file (vim isn't
installed where they were captured), less paging and searching, a few htop
frames, `git log --graph --color` and the core's chat demo; each fed in pieces
of every size gives the screen fed whole.

The pseudo-terminal runs real programs (`sh -c`, `cat`, `bash -i`, `stty`,
`tput`, `head`, `od`, `env`, `ls`): their output with the CR the terminal
adds, their exit codes and signals (also those the VM waited for first), the
controlling terminal, Ctrl+C, Ctrl+Z and `fg`, SIGWINCH and the new size, the
signals at their defaults, the environment, TERM and the directory, IUTF8,
input larger than the terminal takes, output held back while paused, the
hang-up, what a background job writes after the program's end, the inherited
descriptors, and the emulator fed by a program it answers.
`test/pty/signal_test.dart` checks, with stand-ins for the system, that a
signal goes through the pidfd where there is one and never to a pid that is
not positive.

The view (`test/view/`) over a link of the test's own: the screen in its
styles, its size told to the program, the rows painted (only those that
changed), the hardware scroll of the rows a program scrolls (with a status
line below its margins too), synchronized output and its timeout, the
scrollback under the wheel and kept in place by output, the wheel on the
alternate screen, keys in the program's modes (DECCKM, kitty), the ignored
keys, pastes, the mouse while tracked (motion only when asked), the focus of
two views and of the app's terminal, the cursor and its default shape, the
default colors (the theme's, `defaultStyle`'s, and what OSC 10, 11 and CSI ?
996 n answer), the callbacks, the end of the output and a program that could
not start. And real programs through `testTwk`, in pseudo-terminals: `sh` (a
command, `stty size` before and after a resize, Ctrl+C, a bracketed paste,
`exit 3`), `less` (pages, DECCKM's Down, the wheel as Down keys, a search, q),
`nano` (typing, Ctrl+O and Ctrl+X, the file written), `htop` (its meters, the
mouse it takes, q), and scripts reading raw what the keys and the mouse send
(DECCKM, the kitty protocol, SGR reports of a press, a drag and a release).
vim is not installed where they run. Each program is killed and waited for in
its tear-down, and at the end `ps` shows none of them left.

```bash
dart pub get
dart test
```

## Speed

`tool/feed_bench.dart` feeds a capture (or 10 MiB of its own) in pieces of 64
KiB, as reads from a pseudo-terminal come:

```bash
python3 ../../tool/pty_run.py --input none --size 120x40 \
    --out /tmp/cat.bin -- cat big.txt
taskset -c 21 dart run tool/feed_bench.dart /tmp/cat.bin
```

`cat` of 10 MiB of this repository's sources and READMEs (200 000 lines, 10.2
MiB with the CR the tty adds) takes about 70 ms on one core, some 140 MiB/s,
at 120x40 with 10 000 lines of scrollback.
