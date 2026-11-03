import os, pty, time, select, signal
# the child writes a line and at once tells the parent; the parent types ^Z
# while the line may still be on its way to the master; the line is lost if
# the signal character's flush caught it
lost = 0
N = 2000
for k in range(N):
    r, w = os.pipe()
    pid, fd = pty.fork()
    if pid == 0:
        signal.signal(signal.SIGTSTP, signal.SIG_IGN)
        os.close(r)
        os.write(1, b"PROMPT$ ")
        os.write(w, b"x")       # written: now the parent types
        time.sleep(0.2)
        os._exit(0)
    os.close(w)
    os.read(r, 1)
    os.write(fd, b"\x1a" * 8)   # a burst of ^Z, as the test's loop
    out = b""
    end = time.time() + 0.5
    while time.time() < end:
        if select.select([fd], [], [], 0.05)[0]:
            try:
                out += os.read(fd, 1024)
            except OSError:
                break
    if b"PROMPT$ " not in out:
        lost += 1
    os.close(r)
    os.close(fd)
    os.waitpid(pid, 0)
print(f"line lost {lost} of {N} times")
