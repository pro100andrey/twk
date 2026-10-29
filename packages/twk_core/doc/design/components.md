# twk_core design: §1.11 Techniques for components

[The design](README.md)

What text fields, lists, panels and chat views need:

## ICH / DCH (insert/delete characters, VT102)

Typing or deleting in the middle of a line shifts the tail on the terminal
with one command; the presenter detects the shift itself and compares its
cost with a rewrite.

How it is tested: typing in the middle of a 160-column line costs 5 bytes
instead of 132; the emulator models ICH/DCH strictly (splitting a wide glyph
is an error); Konsole's lines are as long as what was written on them: its
ICH inserts blanks in the default background, not the current one, and its
DCH appends its blanks, in the current colours, at the line's length —
mid-row on a short line — so there (`TerminalCaps.konsoleLines`, from
XTVERSION or `KONSOLE_VERSION`, never inside a multiplexer) the presenter
shifts a row only with the default SGR, which comes out right on a terminal
wrongly taken for Konsole too, as the emulator's Konsole line model
(`Vt(konsoleLines: true)`) and an xterm-like one check.

## several scroll blocks per frame

Auto-detection finds up to 4 disjoint blocks moved by different amounts (two
panes stacked vertically).

How it is tested: fuzz frames with ≥ 2 hardware scrolls.

## rectangle scrolling (`Surface.scrollRect`)

A list or log narrower than the screen (side panel, bordered box) moves
without a repaint; in hardware with DECSLRM margins on terminals with
DECLRMM (DECRQM `?69`); elsewhere, and in the inline mode, as whole rows
(`DECSTBM`) where that is estimated to write fewer bytes than the cells
inside would, the cells beside the rectangle that the shift left different
written again (`PresentStats.widenedScrollOps`; never over an image or a
wide glyph the rectangle's edge cuts, nor in a fixed viewport that does not
span the screen's rows), otherwise by a plain diff; the surface marks only
the rows the move brought in, and the damage inside moves with the cells.

How it is tested: a dedicated fuzz configuration, and every configuration
without margins widens scrolls; wide glyphs on the edges are broken up
front.

## cursor shape (DECSCUSR)

`Presenter.cursorShape` — a bar in a text field; the user's cursor is
restored on exit.

How it is tested: cursor position, visibility and shape are checked after
every fuzz frame.

## hyperlinks (OSC 8)

`Pen(link: 'https://…')`; the link is part of the interned style, but its
terminal state is tracked separately (SGR 0 doesn't close it); erased cells
lose their link, so erase is used only for styles without one.

How it is tested: the emulator stores the link per cell; compared in the
fuzz and canvas reference tests.

## clipboard (OSC 52) and title

`Terminal.copyToClipboard`, `Terminal.setTitle` (a `WindowBackend`'s, see
below; the user's title is pushed and restored); the raw strings are
`clipboardSequence`, `titleSequence`. The clipboard is wrapped for tmux or
screen (`TerminalInfo.multiplexer`, `clipboardSequence(text,
multiplexer:)`), as notifications are (below), and inside tmux also sent as
it is, first: tmux takes that one itself with `set-clipboard on` (keeping a
paste buffer too) and drops it by default, while the wrapped one needs
`allow-passthrough on`; a tmux inside another hands the outer one plain
OSC 52.

How it is tested: `test/sequences_test.dart` (control characters can't
escape the title; the clipboard's bytes per multiplexer),
`test/terminal/notify_test.dart` (`Terminal.copyToClipboard` in a
pseudo-terminal inside tmux, inside screen and outside both).

## desktop notifications (OSC 9, 777, 99)

`Terminal.notify(title, body)` (a `WindowBackend`'s), for "the long job
finished": the sequence the terminal is known to show
(`TerminalInfo.notifications`, see below), wrapped for tmux or screen
(`TerminalInfo.multiplexer`), nothing elsewhere; control characters removed,
the title cut to 256 bytes and the body to 1024 between graphemes; the raw
strings are `notifySequence` and `passthroughSequence`.

How it is tested: `test/sequences_test.dart` (the bytes per protocol and
multiplexer, control characters, the cut), `test/terminal_test.dart` (the
terminal from the environment), `test/terminal/notify_test.dart`
(`Terminal.notify` in a pseudo-terminal).

## Which terminal is sent what

Desktop notifications go to a terminal the environment names: its own
`TERM`, then `TERM_PROGRAM`, then the variables terminals set for their
programs, which programs inside tmux or screen inherit. Inside tmux the
sequence goes in `DCS tmux; … ST` (every ESC doubled), which tmux passes
on with `allow-passthrough on` (tmux 3.3+); inside GNU screen in `DCS …
ST` pieces of at most 252 bytes, the OSCs ended by BEL.

| terminal | known by | sent |
|---|---|---|
| kitty | `TERM=xterm-kitty`, `KITTY_WINDOW_ID` | OSC 99: the title, then the body under the same id (`pid.n`, so another notification doesn't replace it); a body with line breaks keeps them, in base64 (`e=1`) |
| iTerm2 | `TERM_PROGRAM=iTerm.app`, `ITERM_SESSION_ID`, `LC_TERMINAL=iTerm2` (passed on by ssh) | OSC 9: `title: body` |
| WezTerm | `TERM_PROGRAM=WezTerm`, `WEZTERM_PANE` | OSC 777 `notify;title;body` |
| Ghostty | `TERM=xterm-ghostty`, `TERM_PROGRAM=ghostty`, `GHOSTTY_RESOURCES_DIR` | OSC 777 (its OSC 9 reads a body like `4;…` as a ConEmu command) |
| foot | `TERM=foot…` | OSC 777 |
| Konsole 22.12+ | `KONSOLE_VERSION` | OSC 777 |
| Windows Terminal | `WT_SESSION` (passed on to WSL) | OSC 777, shown from 1.26, ignored before |
| urxvt | `TERM=rxvt-unicode…` | OSC 777, shown by a `notify` perl extension where one is installed |
| VTE 0.52+ (GNOME Terminal, Tilix, Ptyxis) | `VTE_VERSION` | OSC 777, shown where the distribution patched VTE for it (Fedora); upstream VTE ignores it |
| Alacritty, xterm, Terminal.app, any other `TERM_PROGRAM`, `TERM=dumb` | | nothing |

In OSC 777 a `;` would end its field (title or body), so it is sent as
`,`; a body without a title is sent as the title. OSC 9 and OSC 777 get
line breaks as spaces.

## Interfaces of a backend

What a terminal can do beyond drawing and input is an interface of its
own beside `TerminalBackend`, which `Terminal` and `HeadlessTerminal`
implement, and the app asks the backend it runs on for each one:

| interface | what it does | on a backend without it |
|---|---|---|
| `SuspendableBackend` | `suspend()`, `resume()`: hands the terminal to another program and takes it back (`TwkApp.suspend`) | only the frames wait |
| `MouseTrackingBackend` | `mouseTracking`: switches the mouse reports to what the app listens to | the reports stay as the terminal opened with them |
| `TerminalStateBackend` | `setTerminalState`, `restoreTerminalState`: the pointer's shape and the progress in the tab, put back on every way out | neither is shown |
| `WindowBackend` | `setTitle`, `notify`: the window's title (twk's `WindowTitle`) and desktop notifications (`AppBinding.notify`) | neither is sent |

A backend that wraps a terminal (to add to its input, as the gallery's
`Typing` does, or to record what is written) implements and passes on
each of these it wants to keep: one that implements only
`TerminalBackend` loses them all, and nothing says so.
