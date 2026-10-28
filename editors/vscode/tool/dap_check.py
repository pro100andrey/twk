"""A DAP client doing what VS Code does with Dart-Code's debugger (the SDK's
`dart debug_adapter`, which Dart-Code runs), its runInTerminal served by a
pseudo-terminal of its own, as VS Code's integrated terminal serves it.

  cd packages/twk
  COL=19 python3 -I ../../editors/vscode/tool/dap_check.py terminal $PWD example/counter.dart 25

COL: the breakpoint's column (19: `setState` in the Up key's closure);
STOP=terminate: end with the stop button instead of q; PAUSEKEY: what is
typed while paused (Ctrl+C by default). It prints the tty's state (raw,
ISIG, the alternate screen) as the app is drawn, paused, continued, ended.

scenarios: terminal (console: terminal, the app in the pty),
           console  (console: debugConsole, the app finds a twk shell:
                     the one TWK_SHELL names, passed in the launch's env,
                     or the project's),
           attach   (the app started here in the pty with the VM service,
                     the debugger attached by its service info file).
"""
import tempfile, fcntl, json, os, pty, re, select, struct, subprocess, sys, termios, threading, time

scenario, cwd, program, line = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
log = lambda *a: print(f'[{time.monotonic()-T0:6.2f}]', *a, flush=True)
T0 = time.monotonic()

dap = subprocess.Popen(['dart', 'debug_adapter'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, cwd=cwd)
seq = 0
events, responses, lock = [], {}, threading.Condition()

def send(msg):
    global seq
    seq += 1
    msg['seq'] = seq
    body = json.dumps(msg).encode()
    dap.stdin.write(b'Content-Length: %d\r\n\r\n' % len(body) + body)
    dap.stdin.flush()
    return seq

def request(command, **arguments):
    return send({'type': 'request', 'command': command, 'arguments': arguments})

def wait_response(s, timeout=60):
    with lock:
        lock.wait_for(lambda: s in responses, timeout)
        return responses.get(s)

def wait_event(name, timeout=60, pred=lambda e: True, since=0):
    with lock:
        ok = lock.wait_for(lambda: any(e['event'] == name and pred(e) for e in events[since:]), timeout)
        return next((e for e in events[since:] if e['event'] == name and pred(e)), None) if ok else None

# ---- the pty
master = slave = proc = None
output = bytearray()
def open_pty():
    global master, slave
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
    threading.Thread(target=read_pty, daemon=True).start()

def read_pty():
    while True:
        try:
            r, _, _ = select.select([master], [], [], 0.2)
            if r:
                b = os.read(master, 65536)
                if not b:
                    return
                output.extend(b)
                if b'\x1b[c' in b:  # answer DA1 so the probe doesn't wait
                    os.write(master, b'\x1b[?62;22c')
        except OSError:
            return

def spawn_in_pty(args, env, run_cwd):
    global proc
    def child():
        os.setsid()
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)
    e = dict(os.environ, TERM='xterm-256color', **(env or {}))
    proc = subprocess.Popen(args, stdin=slave, stdout=slave, stderr=slave, cwd=run_cwd, env=e, preexec_fn=child)
    return proc.pid

def tty_state():
    lflag = termios.tcgetattr(slave)[3]
    raw = not (lflag & termios.ICANON) and not (lflag & termios.ECHO)
    alt = [m.group(1) for m in re.finditer(rb'\x1b\[\?1049([hl])', output)]
    return f"raw={raw} isig={bool(lflag & termios.ISIG)} alt={'on' if alt and alt[-1] == b'h' else 'off'} bytes={len(output)}"

def read_dap():
    buf = b''
    while True:
        chunk = dap.stdout.read1(65536)
        if not chunk:
            return
        buf += chunk
        while True:
            h = buf.find(b'\r\n\r\n')
            if h < 0:
                break
            n = int(re.search(rb'Content-Length: (\d+)', buf[:h]).group(1))
            if len(buf) < h + 4 + n:
                break
            msg = json.loads(buf[h + 4:h + 4 + n]); buf = buf[h + 4 + n:]
            on_message(msg)

def on_message(msg):
    if msg['type'] == 'request' and msg['command'] == 'runInTerminal':
        a = msg['arguments']
        log('runInTerminal', a['kind'], ' '.join(a['args'][1:]))
        pid = spawn_in_pty(a['args'], a.get('env'), a['cwd'])
        send({'type': 'response', 'request_seq': msg['seq'], 'success': True, 'command': 'runInTerminal', 'body': {'processId': pid}})
        return
    with lock:
        if msg['type'] == 'response':
            responses[msg['request_seq']] = msg
        elif msg['type'] == 'event':
            if msg['event'] == 'output':
                o = msg['body'].get('output', '').strip()
                if o:
                    log('output:', o[:200])
            else:
                log('event', msg['event'], json.dumps(msg.get('body', {}))[:160])
            events.append(msg)
        lock.notify_all()

threading.Thread(target=read_dap, daemon=True).start()
r = wait_response(request('initialize', clientID='vscode', adapterID='dart', supportsRunInTerminalRequest=True,
                          linesStartAt1=True, columnsStartAt1=True, pathFormat='path'))
log('initialize', r['success'])
prog = os.path.join(cwd, program)
if scenario in ('terminal', 'attach'):
    open_pty()
if scenario == 'attach':
    info = os.path.join(tempfile.mkdtemp(prefix='twk-dap'), 'vm-service-info.json')
    if os.path.exists(info):
        os.remove(info)
    spawn_in_pty(['dart', '--enable-vm-service=0', f'--write-service-info=file://{info}', '--pause-isolates-on-start',
                  'run', prog], {}, cwd)
    s = request('attach', vmServiceInfoFile=info, cwd=cwd, program=prog)
else:
    # console: the twk shell the app is to find, as the extension passes it
    env = {'TWK_SHELL': os.environ['TWK_SHELL']} if os.environ.get('TWK_SHELL') else {}
    s = request('launch', program=prog, cwd=cwd, console='terminal' if scenario == 'terminal' else 'debugConsole', env=env)
wait_event('initialized')
r = wait_response(request('setBreakpoints', source={'path': prog}, breakpoints=[{'line': line, **({'column': int(os.environ['COL'])} if os.environ.get('COL') else {})}]))
log('setBreakpoints', json.dumps(r['body'])[:200])
request('configurationDone')
log('launch/attach response', (wait_response(s) or {}).get('success'))

def stopped(reason):
    return wait_event('stopped', 90, lambda e: e['body']['reason'] == reason)

if scenario == 'attach':
    e = stopped('entry')
    log('paused on start; continue')
    request('continue', threadId=e['body']['threadId'])

def keys(b):
    if master is not None:
        os.write(master, b)
    else:  # console scenario: the headless shell types (see its keys)
        pass

if master is not None:
    t = time.monotonic()
    while b'Count' not in output and time.monotonic() - t < 60:
        time.sleep(0.1)
    log('drawn;', tty_state())
    time.sleep(0.5)
    keys(b'\x1b[A')
n = len(events)
e = wait_event('stopped', 90, lambda e: e['body']['reason'] == 'breakpoint')
log('stopped at breakpoint' if e else 'NOT stopped')
if e:
    tid = e['body']['threadId']
    st = wait_response(request('stackTrace', threadId=tid, levels=3))
    log('top frame', [f"{f['name']}:{f['line']}" for f in st['body']['stackFrames'][:3]])
    if master is not None:
        before = len(output)
        log('paused;', tty_state())
        keys(os.environ.get('PAUSEKEY', '\x03').encode())  # Ctrl+C while paused
        time.sleep(1.5)
        log('Ctrl+C while paused: new output bytes', len(output) - before, 'app alive', proc.poll() is None)
    r = wait_response(request('setBreakpoints', source={'path': prog}, breakpoints=[]))
    request('continue', threadId=tid)
    time.sleep(2)
    if master is not None:
        log('continued;', tty_state(), 'app alive', proc.poll() is None)
if os.environ.get('STOP') == 'terminate':
    log('terminate request (the stop button)')
    wait_response(request('terminate'), 20)
    time.sleep(3)
elif master is not None and proc.poll() is None:
    keys(b'q')
    time.sleep(3)
if master is not None:
    log('end;', tty_state(), 'app exit', proc.poll())
    if proc.poll() is None:
        proc.kill(); proc.wait()
wait_event('terminated', 20)
try:
    wait_response(request('disconnect', terminateDebuggee=True), 10)
except Exception:
    pass
dap.stdin.close()
try:
    dap.wait(10)
except subprocess.TimeoutExpired:
    dap.kill(); dap.wait()
log('done')
