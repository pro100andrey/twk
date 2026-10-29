#!/usr/bin/env python3
"""Runs a command in a pseudo-terminal, like a user would in a real one.

Optionally answers the capability probe like a modern terminal, types a
scripted input sequence, saves everything the command wrote to the
terminal, and checks after exit that the terminal was handed back intact:

  * the command exited with the expected status (0 unless told otherwise);
  * the tty is back in cooked mode (ECHO, ICANON, ISIG, IXON and ICRNL as
    before the run);
  * every mode the command turned on was turned off again: the alternate
    screen left, the cursor shown, autowrap on, mouse, paste and focus
    reports off, kitty keyboard flags popped, BDSM set again (the probe is
    told the terminal reorders right-to-left text itself until told not
    to, as VTE does, so the command resets it for its own order).

The command runs with CI=false, whatever the environment says: in a real
terminal, a user's, and not a CI log, where a twk_core app writes plain
text only (runsInCi) and these tests are run. It runs with TERM
xterm-256color and without what names the terminal this script was run
from (TERM_PROGRAM, COLORTERM, KITTY_WINDOW_ID, TMUX and the like): its
terminal is the one this script stands for, answering as it does,
whatever the terminal outside is. --env NAME=VALUE (as often as wanted)
sets a variable after that, as a test that stands for a terminal of a
name does (TERM=foot, TERM_PROGRAM=tmux).

Input times count from the command's first output: for a twk_core app that
is its capability probe, sent once the terminal is in raw mode, so a slow
start can't make the input arrive while the tty still echoes it. Every
probe is answered, also those of apps run one after another (`sh -c 'app;
app'`, an app restarted by `twk run`), and so are a `CSI 6 n` outside one
and queries of the default colors (OSC 10, 11). A `CSI 6 n` is told where
the cursor is, followed through what was written before it: text by its
width (wrapping as autowrap says), CR, LF, BS, TAB, the cursor moves, its
saves and restores (DECSC, SCOSC, the alternate screen) and what homes it
(DECSTBM, DECSLRM).

The saved stream can then be checked by the test emulator:

  python3 tool/pty_run.py --out /tmp/demo.bin -- \\
      dart run example/chat_demo.dart --seconds=3
  dart run tool/replay.dart --fullscreen /tmp/demo.bin 100 30

An app in the inline mode draws below what was printed before it, which
the emulator then checks is left alone:

  python3 tool/pty_run.py --input none --out /tmp/inline.bin -- sh -c \\
      'printf "history 1\\nhistory 2\\n"; exec dart run test/inline/inline_demo.dart --seconds=3'
  dart run tool/replay.dart --inline /tmp/inline.bin 100 30

An app that hands the terminal to another program for a while (TwkApp's
suspend) is checked with --suspended MARKER, text the other program prints
(or the shell, for an app stopped by Ctrl+Z): when it appears the tty must
be in cooked mode as before the run and every mode turned off as at the
end; after it the tty must be raw again and every mode the app had turned
on turned on again. Input times written `@t` count from the marker:

  python3 tool/pty_run.py --suspended 'suspended> ' \\
      --input '1:s,@0.2:hello\\r,@1.5:q' --out /tmp/suspend.bin -- \\
      dart run test/terminal/suspend_app.dart
  dart run tool/replay.dart --fullscreen /tmp/suspend.bin 100 30

(replay.dart --fullscreen leaves out what the other program printed meanwhile).
Input can also wait for what the command writes instead of for a time
that is guessed to be long enough: each --when TEXT (with Python escapes,
given as often as wanted, in order) is the first time TEXT appears in the
output after where the --when before it appeared, and a time written `#N`
is when the Nth one appeared (`#N+t`: t seconds after it). An input, a
resize or a scheme switch timed so waits for its text however long the
command takes; a text that never appears is a failure (the command then
runs into --timeout unless it ends by itself). A resize due at the same
time as input is done first:

  python3 tool/pty_run.py --when 'typed:' --when hi \\
      --input '#1:hi,#2:q' -- dart run test/terminal/trace_app.dart

A terminal that reports changes of its color scheme (DEC mode 2031) is
--scheme T:light (or dark), given as often as wanted: the probe is told
the mode is there, and at time T, once the command has turned the mode
on, the terminal switches from its dark scheme to that one and says so
(CSI ? 997 ; 1|2 n); the default colors asked for after that (OSC 10, 11)
are the new scheme's. A switch that never happened is a failure:

  python3 tool/pty_run.py --input none --scheme 1:light \\
      --out /tmp/scheme.bin -- \\
      dart run packages/twk/test/binding/color_scheme_app.dart --seconds=2
  dart run tool/replay.dart --fullscreen /tmp/scheme.bin 100 30

Stopped for the shell (Ctrl+Z), with the terminal resized meanwhile:

  python3 tool/pty_run.py --input '@2:q' --suspended 'shell has it' \\
      --resize @0.2:90x25 -- bash --norc --noprofile -i -c \\
      'dart run test/terminal/suspend_app.dart --stop-after=1.5; \\
      echo shell has it; sleep 0.5; fg'

Exit status: 0 when every check passed, 1 otherwise. POSIX only (Linux,
macOS); needs nothing beyond the Python standard library.
"""
import argparse
import fcntl
import os
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time
import unicodedata

# What a modern terminal answers to the probe twk_core sends (DECRQM 2026
# set-able, 2027 unsupported, 2048 unsupported, 69 set-able, BDSM set,
# then the default colors of its color scheme, the kitty keyboard query,
# where the cursor is, DA1).
PROBE_MODES = (b'\x1b[?2026;2$y\x1b[?2027;0$y\x1b[?2048;0$y\x1b[?69;2$y'
               b'\x1b[8;1$y')
PROBE_KITTY = b'\x1b[?0u'
PROBE_DA1 = b'\x1b[?62;22c'
PROBE_END = b'\x1b[c'
# What names the terminal this script runs in, which a twk_core app would
# take for its own (colorModeFor, notificationProtocolFor, styledUnderlinesFor
# and the like): left out of the command's environment.
HOST_TERMINAL = {
    'TERM_PROGRAM', 'TERM_PROGRAM_VERSION', 'LC_TERMINAL',
    'LC_TERMINAL_VERSION', 'COLORTERM', 'COLORFGBG', 'ITERM_SESSION_ID',
    'KITTY_WINDOW_ID', 'KITTY_PID', 'GHOSTTY_RESOURCES_DIR', 'WEZTERM_PANE',
    'WEZTERM_EXECUTABLE', 'KONSOLE_VERSION', 'KONSOLE_DBUS_SESSION',
    'VTE_VERSION', 'WT_SESSION', 'ALACRITTY_WINDOW_ID', 'TMUX', 'TMUX_PANE',
    'STY', 'XTERM_VERSION', 'MLTERM',
}
# the probe's first query: what comes before it was printed by others
PROBE_START = b'\x1b[?2026$p'
# DEC mode 2031, set-able: the terminal reports changes of its color scheme
PROBE_SCHEME = b'\x1b[?2031;2$y'
# each color scheme: what its report says (CSI ? 997 ; n n) and its default
# colors (OSC 10, 11); the terminal starts dark, as PROBE_MODES says
SCHEMES = {'dark': (1, b'rgb:d0d0/d0d0/d0d0', b'rgb:1010/1212/1818'),
           'light': (2, b'rgb:4c4c/4f4f/6969', b'rgb:efef/f1f1/f5f5')}

# (seconds after the first output, bytes typed): text + Enter, mouse
# wheel, Up, paste.
DEMO_INPUT = [
    (0.5, b'hi there'), (0.7, b'\r'),
    (0.9, b'\x1b[<64;10;10M'), (1.0, b'\x1b[<64;10;10M'),
    (1.2, b'\x1b[A'), (1.4, b'\x1b[<65;10;10M'),
    (1.6, b'\x1b[200~pasted\r\ntext\x1b[201~'),
]


# what the cursor is followed through: a control sequence (CSI: prefix,
# parameters, intermediates, final byte), a string (OSC, DCS, APC, PM),
# another escape, a control byte, text
TOKEN = re.compile(rb'\x1b(?:\[([<-?]?)([0-9:;]*)([ -/]*)([@-~])'
                   rb'|[\]P_^][^\x07\x1b]*(?:\x07|\x1b\\)|(.))'
                   rb'|([\x00-\x1a\x1c-\x1f\x7f])|([^\x00-\x1f\x7f]+)', re.S)
DEC_MODE = re.compile(rb'\x1b\[\?([0-9;]+)([hl])')
# BDSM, ECMA-48's bidirectional support mode: reset (CSI 8 l) is explicit
# mode, which the terminal is told while the command orders text itself
BDSM = re.compile(rb'\x1b\[8([hl])')
# where the cursor is (CSI 6 n), the default colors (OSC 10, 11), and the
# device attributes (DA1) asked outside a probe
QUERY = re.compile(rb'\x1b\[6n|\x1b\]1([01]);\?(?:\x07|\x1b\\)|\x1b\[c')
KITTY_FLAGS = re.compile(rb'\x1b\[([<>])([0-9]*)u')


def char_width(ch, ambiguous):
    """Columns [ch] takes in a terminal that gives East Asian Ambiguous
    characters [ambiguous] columns."""
    if unicodedata.category(ch) in ('Mn', 'Me', 'Cf', 'Cc'):
        return 0
    eaw = unicodedata.east_asian_width(ch)
    return 2 if eaw in ('W', 'F') else ambiguous if eaw == 'A' else 1


class Cursor:
    """Where the terminal's cursor is, followed through the output up to
    each `CSI 6 n` (see the module's doc)."""

    def __init__(self, cols, rows, ambiguous):
        self.cols, self.rows, self.ambiguous = cols, rows, ambiguous
        self.row = self.col = 0  # col == cols: past the last column
        self.saved = self.alt_saved = (0, 0)
        self.autowrap = True
        self.margins = False  # DEC mode 69: CSI s sets left/right margins
        self.last = 1  # the width of the last character, for REP
        self.done = 0  # how much of the output was followed

    def report(self, out, end):
        """The answer to the `CSI 6 n` at [end] of [out]."""
        for m in TOKEN.finditer(out, self.done, end):
            self.follow(*m.groups())
        self.done = end
        col = min(self.col, self.cols - 1)
        return b'\x1b[%d;%dR' % (self.row + 1, col + 1)

    def resize(self, cols, rows):
        self.cols, self.rows = cols, rows
        self.move(self.row, self.col)

    def move(self, row=None, col=None):
        if row is not None:
            self.row = max(0, min(row, self.rows - 1))
        if col is not None:
            self.col = max(0, min(col, self.cols - 1))

    def line_feed(self):
        self.move(self.row + 1, self.col)

    def put(self, width):
        if not width:
            return
        if self.col + width > self.cols:
            if self.autowrap:
                self.col = 0
                self.line_feed()
            else:
                self.col = self.cols - width
        self.col += width
        self.last = width

    def follow(self, prefix, params, inter, final, esc, ctl, text):
        x = min(self.col, self.cols - 1)
        if text is not None:
            for ch in text.decode(errors='replace'):
                self.put(char_width(ch, self.ambiguous))
        elif ctl is not None:
            if ctl == b'\r':
                self.col = 0
            elif ctl in (b'\n', b'\x0b', b'\x0c'):
                self.line_feed()
            elif ctl == b'\b':
                self.move(col=x - 1)
            elif ctl == b'\t':
                self.move(col=(x // 8 + 1) * 8)
        elif esc is not None:
            if esc == b'7':
                self.saved = (self.row, self.col)
            elif esc == b'8':
                self.row, self.col = self.saved
            elif esc in (b'D', b'E'):
                self.line_feed()
                if esc == b'E':
                    self.col = 0
            elif esc == b'M':
                self.move(row=self.row - 1)
        elif final is not None and not inter:
            nums = [int(p.split(b':')[0] or 0) for p in params.split(b';')]
            n = max(nums[0], 1)
            if prefix == b'?' and final in (b'h', b'l'):
                on = final == b'h'
                for mode in nums:
                    if mode == 1049 and on:
                        self.alt_saved = (self.row, self.col)
                    elif mode == 1049:
                        self.row, self.col = self.alt_saved
                    elif mode == 7:
                        self.autowrap = on
                    elif mode == 69:
                        self.margins = on
            elif prefix:
                pass  # kitty keyboard flags, queries
            elif final == b'A':
                self.move(row=self.row - n)
            elif final in (b'B', b'e'):
                self.move(row=self.row + n)
            elif final in (b'C', b'a'):
                self.move(col=x + n)
            elif final == b'D':
                self.move(col=x - n)
            elif final in (b'E', b'F'):
                self.move(self.row + (n if final == b'E' else -n), 0)
            elif final in (b'G', b'`'):
                self.move(col=n - 1)
            elif final == b'd':
                self.move(row=n - 1)
            elif final in (b'H', b'f'):
                self.move(n - 1, max(nums[1] if len(nums) > 1 else 0, 1) - 1)
            elif final in (b'L', b'M'):
                self.col = 0  # IL, DL: to the first column, as DEC's do
            elif final == b'r' or final == b's' and self.margins:
                self.move(0, 0)  # DECSTBM, DECSLRM
            elif final == b's':
                self.saved = (self.row, self.col)
            elif final == b'u':
                self.row, self.col = self.saved
            elif final == b'b':
                for _ in range(n):
                    self.put(self.last)


def unescape(text):
    """[text] with its Python escapes (\\r, \\x1b, ...) as bytes."""
    return text.encode().decode('unicode_escape').encode('latin-1')


def parse_input(spec):
    """'t:bytes,t:bytes' with Python escapes, e.g. '1.0:x,1.5:\\x1b'; a time
    written '@t' counts from the --suspended marker, '#N' and '#N+t' from
    the Nth --when text."""
    return [(at, unescape(data))
            for at, data in (item.split(':', 1) for item in spec.split(','))]


def when_number(at):
    """N of a time written '#N' or '#N+t', None for the other times."""
    return int(at[1:].partition('+')[0]) if at.startswith('#') else None


def due(at, input_start, marker_at, when_at=()):
    """Whether the time [at] has come: 't' after the first output, '@t'
    after the --suspended marker, '#N' once the Nth --when text appeared
    ([when_at] says when each did), '#N+t' t seconds after that."""
    if at.startswith('#'):
        n, _, after = at[1:].partition('+')
        start = when_at[int(n) - 1] if int(n) <= len(when_at) else None
        delay = float(after or 0)
    else:
        start = marker_at if at.startswith('@') else input_start
        delay = float(at.lstrip('@'))
    return start is not None and time.time() - start >= delay


def mode_on(out, mode):
    """Whether [out] leaves the DEC [mode] turned on."""
    on = False
    for m in DEC_MODE.finditer(out):
        if str(mode).encode() in m.group(1).split(b';'):
            on = m.group(2) == b'h'
    return on


def modes_left_on(out):
    """What [out] leaves turned on that a program handing the terminal back
    must have turned off."""
    modes = {}
    for m in DEC_MODE.finditer(out):
        for n in m.group(1).split(b';'):
            modes[int(n)] = m.group(2) == b'h'
    kitty = 0
    for m in KITTY_FLAGS.finditer(out):
        kitty = kitty + 1 if m.group(1) == b'>' else max(
            kitty - int(m.group(2) or 1), 0)
    problems = []
    if modes.get(1049):
        problems.append('alternate screen not left')
    if modes.get(25) is False:
        problems.append('cursor left hidden')
    if modes.get(7) is False:
        problems.append('autowrap left off')
    problems += [f'mode ?{n} left on' for n, on in sorted(modes.items())
                 if on and n not in (1049, 25, 7)]
    if kitty:
        problems.append('kitty keyboard flags not popped')
    if bidi_explicit(out):
        problems.append('BDSM left reset (explicit mode)')
    return problems


def bidi_explicit(out):
    """Whether [out] leaves BDSM reset: the terminal in explicit mode."""
    last = None
    for m in BDSM.finditer(out):
        last = m.group(1)
    return last == b'l'


def modes_turned_on(out):
    """The modes [out] turns on and keeps on (not the cursor, autowrap or
    synchronized output, which frames turn off and on), 'kitty' if it
    pushes keyboard flags and 'BDSM reset' if it resets BDSM."""
    on = {f'?{n}' for m in DEC_MODE.finditer(out) if m.group(2) == b'h'
          for n in m.group(1).decode().split(';')} - {'?25', '?7', '?2026'}
    if any(m.group(1) == b'>' for m in KITTY_FLAGS.finditer(out)):
        on.add('kitty')
    if any(m.group(1) == b'l' for m in BDSM.finditer(out)):
        on.add('BDSM reset')
    return on


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--size', default='100x30', help='COLSxROWS (100x30)')
    ap.add_argument('--out', help='file to save the terminal output to')
    ap.add_argument('--silent', action='store_true',
                    help="don't answer the capability probe (old terminal)")
    ap.add_argument('--no-kitty', action='store_true',
                    help="answer the probe, but without the kitty keyboard "
                         "protocol (lone ESC is then the Escape key)")
    ap.add_argument('--ambiguous-wide', action='store_true',
                    help='draw East Asian Ambiguous characters 2 columns '
                         'wide (CJK setups)')
    ap.add_argument('--no-echo', action='store_true',
                    help='start with echo off (a parent program that set '
                         'stty -echo); it must stay off after the run')
    ap.add_argument('--erase-ctrl-h', action='store_true',
                    help='set the tty erase character to ^H, as for a '
                         'terminal whose Backspace sends 0x08')
    ap.add_argument('--answer-delay', type=float, default=0,
                    help='answer the probe this many seconds late, each '
                         'of its rounds (a slow link)')
    ap.add_argument('--input', default='demo',
                    help="'demo', 'none' or 'T:bytes,...' (escapes "
                         "allowed), T 't', '@t' or '#N'")
    ap.add_argument('--timeout', type=float, default=120,
                    help='kill the command after this many seconds (120): '
                         'counted from its start, which on a loaded '
                         'machine a Dart program run from source takes '
                         '20 s and more of')
    ap.add_argument('--expect-status', type=int, default=0,
                    help='exit status the command should end with (0)')
    ap.add_argument('--suspended', metavar='MARKER',
                    help='text printed while the command has handed the '
                         'terminal over: check it then and after')
    ap.add_argument('--resize', metavar='T:COLSxROWS',
                    help="resize the terminal at time T ('t', '@t' or "
                         "'#N')")
    ap.add_argument('--scheme', metavar='T:light|dark', action='append',
                    default=[],
                    help="switch the terminal's color scheme at time T "
                         "('t', '@t' or '#N'), reported by DEC mode 2031; "
                         "may be repeated")
    ap.add_argument('--when', metavar='TEXT', action='append', default=[],
                    help="text the command writes (Python escapes "
                         "allowed): the Nth --when is its first appearance "
                         "after the one before, the time '#N' (or '#N+t') "
                         "of --input, --resize and --scheme; may be "
                         "repeated")
    ap.add_argument('--env', metavar='NAME=VALUE', action='append',
                    default=[],
                    help="a variable of the command's environment, set "
                         "after what names this script's own terminal is "
                         "left out; may be repeated")
    ap.add_argument('command', nargs=argparse.REMAINDER)
    args = ap.parse_args()
    cmd = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not cmd:
        ap.error('no command given')
    cols, rows = (int(v) for v in args.size.split('x'))
    script = {'demo': [(str(t), b) for t, b in DEMO_INPUT],
              'none': []}.get(args.input)
    if script is None:
        script = parse_input(args.input)
    resize = None
    if args.resize:
        at, size = args.resize.split(':')
        resize = (at, *(int(v) for v in size.split('x')))
    marker = args.suspended.encode() if args.suspended else None
    schemes = [tuple(item.split(':', 1)) for item in args.scheme]
    if any(name not in SCHEMES for _, name in schemes):
        ap.error('--scheme takes T:light or T:dark')
    scheme = 'dark'  # the terminal's color scheme now
    whens = [unescape(text) for text in args.when]
    for at in ([at for at, _ in script] + [at for at, _ in schemes]
               + ([resize[0]] if resize else [])):
        n = when_number(at)
        if n is not None and not 1 <= n <= len(whens):
            ap.error(f'{at}: there is no --when number {n}')

    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))
    attrs = termios.tcgetattr(slave)
    if args.erase_ctrl_h:
        attrs[6][termios.VERASE] = b'\x08'
    if args.no_echo:
        attrs[3] &= ~termios.ECHO
    termios.tcsetattr(slave, termios.TCSANOW, attrs)
    before = termios.tcgetattr(slave)

    def make_controlling_tty():
        os.setsid()
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)

    env = {k: v for k, v in os.environ.items() if k not in HOST_TERMINAL}
    env.update(CI='false', TERM='xterm-256color')
    for given in args.env:
        name, _, value = given.partition('=')
        env[name] = value
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave,
                            stderr=subprocess.PIPE, env=env,
                            preexec_fn=make_controlling_tty)
    out, err = bytearray(), bytearray()
    start = time.time()
    input_start = None  # the first output
    answered = False  # a probe was answered
    answered_to = 0  # the output up to here was answered
    probe_at = None  # when the probe waiting for its answer gets it
    round_at = None  # when a round ended by a DA1 alone gets its answers
    cursor = Cursor(cols, rows, 2 if args.ambiguous_wide else 1)
    scheme_reports = bool(schemes)
    pending = list(script)
    lflags = termios.ECHO | termios.ICANON | termios.ISIG
    iflags = termios.IXON | termios.ICRNL
    failures = []
    marker_at = None  # when the marker appeared
    marker_end = None  # and where it ends in the output
    taken_back = False  # raw again after the marker
    when_at = []  # when each --when text appeared
    when_from = 0  # where the next one is looked for in the output
    streams = [master, proc.stderr.fileno()]
    while True:
        ready, _, _ = select.select(streams, [], [], 0.05)
        for fd in ready:
            data = os.read(fd, 65536)
            if fd == master:
                out += data
                if input_start is None and data:
                    input_start = time.time()
            elif data:
                err += data
            else:
                streams.remove(fd)
        elapsed = time.time() - start
        # in the order asked: the queries before the next probe, then the
        # probe once it is complete (up to its DA1 query) and its time came
        while not args.silent:
            probe = out.find(PROBE_START, answered_to)
            until = len(out) if probe < 0 else probe
            # a round of queries a DA1 alone ends (the inline probe's
            # first) is answered as late as the probe
            if out.find(PROBE_END, answered_to, until) >= 0:
                if round_at is None:
                    round_at = time.time() + args.answer_delay
                if time.time() < round_at:
                    break
            for ask in QUERY.finditer(out, answered_to, until):
                which = ask.group(1)
                if ask.group(0) == PROBE_END:
                    # DA1 on its own: the end of the inline probe's first
                    # round, where the cursor is asked first
                    os.write(master, PROBE_DA1)
                    round_at = None
                elif which is None:
                    os.write(master, cursor.report(out, ask.start()))
                else:
                    color = SCHEMES[scheme][1 if which == b'0' else 2]
                    os.write(master, b'\x1b]1%s;%s\x1b\\' % (which, color))
                answered_to = ask.end()
            end = -1 if probe < 0 else out.find(PROBE_END, probe)
            if end < 0:
                break
            if probe_at is None:
                probe_at = time.time() + args.answer_delay
            if time.time() < probe_at:
                break
            cpr = out.find(b'\x1b[6n', probe, end)
            os.write(master, PROBE_MODES
                     + b'\x1b]10;%s\x1b\\\x1b]11;%s\x1b\\'
                     % SCHEMES[scheme][1:]
                     + (PROBE_SCHEME if scheme_reports else b'')
                     + (b'' if args.no_kitty else PROBE_KITTY)
                     + (cursor.report(out, cpr) if cpr >= 0 else b'')
                     + PROBE_DA1)
            answered = True
            answered_to = end + len(PROBE_END)
            probe_at = None
        while (schemes and answered
               and due(schemes[0][0], input_start, marker_at, when_at)
               and mode_on(out, 2031)):
            scheme = schemes.pop(0)[1]
            os.write(master, b'\x1b[?997;%dn' % SCHEMES[scheme][0])
        while len(when_at) < len(whens):
            text = whens[len(when_at)]
            found = out.find(text, when_from)
            if found < 0:
                when_from = max(when_from, len(out) - len(text) + 1)
                break
            when_at.append(time.time())
            when_from = found + len(text)
        if marker is not None and marker_at is None and marker in out:
            marker_at = time.time()
            marker_end = out.find(marker) + len(marker)
            now = termios.tcgetattr(slave)
            if (now[3] & lflags != before[3] & lflags
                    or now[0] & iflags != before[0] & iflags):
                failures.append('tty not in cooked mode while handed over')
            failures += [f'{p} while handed over'
                         for p in modes_left_on(out[:marker_end])]
        if marker_at is not None and not taken_back:
            taken_back = termios.tcgetattr(slave)[3] & lflags == 0
        # a resize first: input due with it may be what lets the command
        # go on to see it
        if resize and due(resize[0], input_start, marker_at, when_at):
            fcntl.ioctl(slave, termios.TIOCSWINSZ,
                        struct.pack('HHHH', resize[2], resize[1], 0, 0))
            cursor.resize(resize[1], resize[2])
            resize = None
        while pending and due(pending[0][0], input_start, marker_at, when_at):
            os.write(master, pending.pop(0)[1])
        if proc.poll() is not None and proc.stderr.fileno() not in streams:
            break
        if elapsed > args.timeout and proc.poll() is None:
            proc.send_signal(signal.SIGKILL)
    # drain what is left in the pty
    while select.select([master], [], [], 0.2)[0]:
        data = os.read(master, 65536)
        if not data:
            break
        out += data
    try:
        after = termios.tcgetattr(slave)
    except termios.error:
        # macOS revokes the slave once the session leader it was the
        # controlling terminal of has exited; the master shares its tty,
        # and so its modes, there (on Linux it has modes of its own)
        after = termios.tcgetattr(master)

    if args.out:
        with open(args.out, 'wb') as f:
            f.write(out)
    print(f'exit status {proc.returncode} after {time.time() - start:.2f} s, '
          f'{len(out)} bytes of output')
    if err:
        print('stderr:\n  ' + err.decode(errors='replace').strip()
              .replace('\n', '\n  '))

    if proc.returncode != args.expect_status:
        failures.append(f'exit status {proc.returncode}, '
                        f'expected {args.expect_status}')
    if (after[3] & lflags != before[3] & lflags
            or after[0] & iflags != before[0] & iflags):
        failures.append('tty modes not restored '
                        '(ECHO/ICANON/ISIG/IXON/ICRNL differ from before)')
    failures += modes_left_on(out)
    failures += [f'no switch to the {name} color scheme at {at}: mode '
                 f'?2031 was not on before the command ended'
                 for at, name in schemes]
    failures += [f'--when {n} never appeared: {text!r}'
                 for n, text in enumerate(args.when, 1)
                 if n > len(when_at)]
    if marker is not None:
        if marker_end is None:
            failures.append('the marker of the handover never appeared')
        else:
            if not taken_back:
                failures.append('the terminal was not taken back (raw '
                                'mode) after the handover')
            again = modes_turned_on(out[marker_end:])
            failures += [f'{m} not turned on again after the handover'
                         for m in sorted(modes_turned_on(out[:marker_end])
                                         - again)]
    for f in failures:
        print('FAIL:', f)
    if not failures:
        print('terminal restored')
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
