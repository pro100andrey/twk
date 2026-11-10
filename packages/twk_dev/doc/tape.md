# `twk tape`

```bash
dart run twk_dev:twk tape example/tally.tape     # from this directory
```

A tape is a script, VHS's language: a statement a line, `#` to the end of a
line a comment (not in a quoted word or a Wait's pattern). It runs a program
in a pseudo-terminal (twk_term's `Pty`, as `twk record` does) whose screen
twk_term's emulator keeps, types into it, waits, and writes what the program
showed. `example/tally.tape` records the walkthrough's app: hidden while it
compiles and draws its first frame, then counted.

```text
Output build/tally.cast          # asciicast v2, for twk play
Output build/tally.svg           # the session, animated
Set Width 44                     # cells
Set Height 7
Set TypingSpeed 250ms
Run dart example/tally.dart
Hide
Wait /q quit/
Show
Type "++"
Down
Type "+++"
Sleep 1s
Screenshot build/tally-counted.svg
```

## Statements

### `Output <file>`

writes the session, once the tape has run, to a `.cast` file (asciicast v2) or
an `.svg` file (an animated SVG); as many as wanted

### `Set Width <cells>`, `Set Height <cells>`

the terminal's size: 80 by 24

### `Set Theme <name>`

the terminal's colours: `dark` (the default), `light`, `xterm`, or a JSON
object of `#rrggbb` colours, VHS's and iTerm2's keys (`background`,
`foreground`, `cursor`, `black` to `white`, `brightBlack` to `brightWhite`,
`purple` for `magenta`), dark's for those left out

### `Set FontSize <px>`, `Set FontFamily "<css>"`, `Set Padding <px>`

the SVG's text (16 px, monospace fonts) and the space around the screen (the
font size)

### `Set Framerate <n>`

the most frames a second the animated SVG takes: 50

### `Set TypingSpeed <time>`

the pause after each character typed and each key: 50 ms; anywhere in the tape

### `Set WaitTimeout <time>`

how long a Wait waits: 15 s; anywhere

### `Env <name> <value>`

in the program's environment

### `Run <program> [<argument>...]`

the program, looked for in `PATH`, its arguments words or quoted; `sh` when
there is none, with `PS1='$ '`

### `Type[@<time>] "<text>"`

types the text, a character at a time, the typing speed (or `@<time>`) after
each

### `<key>[@<time>] [<count>]`

presses a key, `count` times: `Enter`, `Tab`, `Space`, `Backspace`, `Escape`,
`Up`, `Down`, `Left`, `Right`, `Home`, `End`, `PageUp`, `PageDown`, `Insert`,
`Delete`, `F1` to `F12`, and with `Ctrl+`, `Alt+`, `Shift+` before it those
and a character (`Ctrl+C`, `Alt+Shift+Tab`)

### `Sleep <time>`

waits

### `Wait[+Screen|+Line][@<time>] /<regexp>/`

waits until the screen's text (rows a line each; `+Line`, the cursor's row)
matches, or `"<text>"` shows; past the timeout the tape fails

### `Hide`, `Show`

the time between them is cut from the recording; at the Show the screen is
drawn as it is then

### `Screenshot <file.svg>`

writes the screen as it is to a still SVG

## Times, strings and paths

A time is a number of seconds, or of `ms`, `s` or `m` (`500ms`, `1.5s`, `2`,
`1m`); strings are quoted with `"`, `'` or `` ` ``, without escapes (a quote
of another kind goes inside); in a pattern `\/` is a slash. A statement other
than Output, TypingSpeed and WaitTimeout comes before the first that does
something. Paths are the current directory's, a file's directory made when
missing; the program runs in it too.

The program's terminal is `xterm-256color` with `COLORTERM=truecolor`, of the
theme's colours, and `CI=false`, so that a twk app draws in it in CI too
(where it would write plain text, as for a log): the emulator answers the
program's queries (the cursor's position, the colours by OSC 10, 11 and 4, the
modes) as a terminal does, and what the tape types goes through it too,
encoded as the program's modes want it (an arrow as `ESC O A` once the program
asked for application cursor keys; the kitty keyboard protocol). A Wait looks
at the screen after each piece the program writes, not while a synchronized
update (DEC 2026) is open.

What the program writes is recorded at its real time since the start, without
the time between a Hide and its Show (a tape that hides before anything was
recorded, from the start): in the `.cast` file an `o` event for each piece,
and at a Show one that draws the screen as it is then (the alternate screen
entered when the program is on it, each cell in its style, the cursor where it
is, shown or hidden). The animated SVG has a frame after each piece that
leaves no synchronized update open, a frame within 1/`Framerate` s of the last
taking its place and one that shows the same as the last none; it plays them
at their times to the end of the tape, then again, as svg-term does: the
frames side by side in a strip that a CSS animation moves under a window of a
screen's size, a step a frame; each row is drawn once (`<defs>`) and used by
every frame that shows it. A row is a `<text>` a run of cells of a style, as
long as its cells (`textLength`), a wide character one of its own, and a
`<rect>` a run of cells of a background; box-drawing lines (light and heavy,
rounded corners) are paths and block elements rectangles, so that they meet
the next cell's and the next row's as a terminal draws them; double and dashed
lines are text. Colours 0 to 15 are the theme's, the rest xterm's.

When the tape has run, the recording ends, the program is hung up
(`Pty.close`: SIGHUP as its terminal goes) and, still running 2 s later,
killed through its terminal (`Pty.kill`), then the outputs are written; a
Screenshot is written when the tape gets to it. A Wait that timed out ends the
tape with 1 and the screen, writing no output; so does an output that can't be
written; SIGINT, SIGTERM and SIGHUP end it with 128 and the signal's number,
writing nothing. A tape that can't be read or is wrong (the line is said)
exits with 1, a program that can't be started with 127, no tape with 64.

## `twk tape --check`

Runs the tape as a test, for CI and for an editor's check: the program runs
and the statements are done as in a recording, but nothing is recorded or
written (no Output, no Screenshot, no directory made). Each statement that
passes is told on stdout, `<tape>:<line>: ok <statement>` (a statement as the
tape wrote it, but for the Type text, which has its `"` as `'`), and the last
line says `<tape>: passed, <n> statements`. The first Wait that times out
fails the tape: stdout has `<tape>:<line>: FAIL <statement>` and
`<tape>: failed, <k> of <n> statements passed`, stderr the line of the
tape, the timeout and the screen at that time (as without `--check`), and the
exit code is 1. Exit codes are those of a run: 0 passed; 1 failed, or the
tape cannot be read or is wrong (stderr only); 127 the program cannot be
started; 128 and a signal's number when stopped. The Wait's timeout is
measured by the runner's clock (`TapeClock.alarm`; a test gives it a clock it
moves), the wall's in the command.
