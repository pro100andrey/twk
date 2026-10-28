"""A terminal with color scheme reports (DEC mode 2031), for
color_scheme_test.dart.

  python3 test/terminal/color_scheme_pty.py OUT COMMAND...

Runs COMMAND in a pseudo-terminal that answers the capability probe as a
dark terminal with mode 2031, reports a switch to a light color scheme
once the mode is turned on, and answers the query for the background
that follows with the colors of a light terminal. What the command wrote
to the terminal goes to the file OUT, its stderr to stderr. Exits with the
command's status, killing it after 30 seconds. POSIX only.
"""
import fcntl
import os
import pty
import select
import struct
import subprocess
import sys
import termios
import time

# (what the command writes, what the terminal answers)
STEPS = [
    (b'\x1b[c',
     b'\x1b[?2026;2$y\x1b[?2027;0$y\x1b[?2048;0$y\x1b[?69;2$y\x1b[?2031;2$y'
     b'\x1b]10;rgb:d0d0/d0d0/d0d0\x1b\\\x1b]11;rgb:1010/1212/1818\x1b\\'
     b'\x1b[?0u\x1b[1;2R\x1b[?62;22c'),
    (b'\x1b[?2031h', b'\x1b[?997;2n'),
    (b'\x1b]11;?\x1b\\',
     b'\x1b]10;rgb:4c4c/4f4f/6969\x1b\\\x1b]11;rgb:efef/f1f1/f5f5\x1b\\'),
]


def main():
    out_path, cmd = sys.argv[1], sys.argv[2:]
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))

    def make_controlling_tty():
        os.setsid()
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)

    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave,
                            stderr=subprocess.PIPE,
                            preexec_fn=make_controlling_tty)
    out, err = bytearray(), bytearray()
    steps = list(STEPS)
    seen = 0  # where the next step's cue is looked for
    streams = [master, proc.stderr.fileno()]
    start = time.time()
    while True:
        for fd in select.select(streams, [], [], 0.05)[0]:
            data = os.read(fd, 65536)
            if fd == master:
                out += data
            elif data:
                err += data
            else:
                streams.remove(fd)
        while steps:
            cue, answer = steps[0]
            at = out.find(cue, seen)
            if at < 0:
                break
            os.write(master, answer)
            seen = at + len(cue)
            steps.pop(0)
        if proc.poll() is not None and proc.stderr.fileno() not in streams:
            break
        if time.time() - start > 30 and proc.poll() is None:
            proc.kill()
    while select.select([master], [], [], 0.2)[0]:
        data = os.read(master, 65536)
        if not data:
            break
        out += data
    with open(out_path, 'wb') as f:
        f.write(out)
    sys.stderr.buffer.write(err)
    sys.exit(proc.returncode)


if __name__ == '__main__':
    main()
