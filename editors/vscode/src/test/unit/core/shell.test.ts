// The extension's shell against an app's end of the wire written here
// (what twk_core's SocketLink sends), over a real local socket; the
// address TWK_SHELL holds.
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

import { fromVariable, toVariable } from '../../../core/address';
import { TerminalPane, TerminalShell, Welcome } from '../../../core/shell';
import { Wire, frame } from '../../../core/wire';
import { App } from '../fakes';

class FakePane implements TerminalPane {
  columns = 100;
  lines = 30;
  readonly written: Buffer[] = [];
  write(bytes: Uint8Array): Promise<void> {
    this.written.push(Buffer.from(bytes));
    return Promise.resolve();
  }
  get text(): string {
    return Buffer.concat(this.written).toString('latin1');
  }
}

describe('TerminalShell', () => {
  let root: string;
  let pane: FakePane;
  let shell: TerminalShell;
  const xterm: Welcome = { environment: { TERM: 'xterm-256color', COLORTERM: 'truecolor' }, declares: {} };
  let welcomes: Welcome[] = [];
  const events: string[] = [];
  const start = (temporaryRoot = root) =>
    TerminalShell.start(pane, { welcome: () => welcomes.shift() ?? xterm, onEvent: (e) => events.push(e), temporaryRoot, tcp: false });

  beforeEach(async () => {
    root = fs.mkdtempSync(path.join(os.tmpdir(), 'twk-vscode-'));
    pane = new FakePane();
    welcomes = [];
    events.length = 0;
    shell = await start();
  });

  afterEach(async () => {
    await shell.stop();
    fs.rmSync(root, { recursive: true, force: true });
  });

  it('welcomes an app with the size and the environment, and passes output and input', async () => {
    const app = await App.connect(shell.variable);
    const welcome = JSON.parse((await app.next(Wire.welcome)).toString());
    assert.equal(welcome.columns, 100);
    assert.equal(welcome.lines, 30);
    assert.equal(welcome.eraseChar, 0x7f);
    assert.equal(welcome.environment.COLORTERM, 'truecolor');
    assert.deepEqual(events, ['connected']);

    app.socket.write(frame(Wire.output, Buffer.from('hello')));
    app.socket.write(frame(Wire.flush));
    await app.next(Wire.flushed);
    assert.equal(pane.text, 'hello');

    shell.input(Buffer.from('q'));
    assert.equal((await app.next(Wire.input)).toString(), 'q');

    pane.columns = 50;
    shell.resized();
    assert.deepEqual(JSON.parse((await app.next(Wire.size)).toString()), { columns: 50, lines: 30 });
    app.socket.destroy();
  });

  it('refuses a wrong token', async () => {
    const app = await App.connect(shell.variable, 'nope');
    assert.equal((await app.next(Wire.refused)).toString(), 'not the token of this shell');
    assert.equal(shell.serving, false);
    app.socket.destroy();
  });

  it('puts the terminal back with the lost bytes when the app goes away', async () => {
    const app = await App.connect(shell.variable);
    await app.next(Wire.welcome);
    app.socket.write(frame(Wire.lost, Buffer.from('\x1b[?1049l')));
    app.socket.write(frame(Wire.flush));
    await app.next(Wire.flushed);
    const gone = new Promise<void>((r) => {
      const poll = () => (shell.serving ? setImmediate(poll) : r());
      poll();
    });
    app.socket.destroy();
    await gone;
    assert.equal(pane.text, '\x1b[?1049l');
    assert.deepEqual(events, ['connected', 'disconnected']);
  });

  it('a newer app takes the terminal over: the older one cut off, and no "went away" between them', async () => {
    const first = await App.connect(shell.variable);
    await first.next(Wire.welcome);
    first.socket.write(frame(Wire.lost, Buffer.from('\x1b[?1049l')));
    first.socket.write(frame(Wire.flush));
    await first.next(Wire.flushed);
    const closed = new Promise((r) => first.socket.once('close', r));
    const second = await App.connect(shell.variable);
    await second.next(Wire.welcome);
    await closed;
    assert.deepEqual(events, ['connected', 'connected']);
    assert.equal(pane.text, '\x1b[?1049l', "the older one's terminal put back all the same");
    second.socket.destroy();
  });

  it('listens on a socket of its own in a new directory, which no project knows of; two shells, two sockets', async () => {
    const address = fromVariable(shell.variable);
    assert.ok(address, shell.variable);
    assert.equal(toVariable(address), shell.variable);
    assert.deepEqual(address, shell.address);
    const socket = address.where.substring('unix:'.length);
    assert.equal(path.dirname(path.dirname(socket)), root);
    assert.ok(fs.lstatSync(socket).isSocket());
    const other = await start();
    try {
      assert.notEqual(other.variable, shell.variable);
      assert.notEqual(other.address.token, shell.address.token);
    } finally {
      await other.stop();
    }
  });

  it('a listen that fails leaves no directory behind', async () => {
    // longer than a Unix domain socket's path may be: listen fails (EINVAL)
    const deep = path.join(root, 'x'.repeat(120));
    fs.mkdirSync(deep);
    await assert.rejects(start(deep), /EINVAL|ENAMETOOLONG|too long/);
    assert.deepEqual(fs.readdirSync(deep), []);
  });

  it('welcomes each app with what its welcome is as it is taken: the environment, and what the terminal declares, left out where nothing', async () => {
    const welcome = async (): Promise<Record<string, unknown>> => {
      const app = await App.connect(shell.variable);
      const json = JSON.parse((await app.next(Wire.welcome)).toString()) as Record<string, unknown>;
      app.socket.destroy();
      return json;
    };
    welcomes = [
      { environment: { TERM: 'xterm', TWK_SCREEN_READER: '1' }, declares: { repeatChar: true, graphics: 'sixel' } },
      { environment: { TERM: 'xterm-256color' }, declares: {} },
    ];
    const first = await welcome();
    assert.deepEqual(first.environment, { TERM: 'xterm', TWK_SCREEN_READER: '1' });
    assert.deepEqual(first.declares, { repeatChar: true, graphics: 'sixel' });
    const second = await welcome();
    assert.deepEqual(second.environment, { TERM: 'xterm-256color' });
    assert.equal('declares' in second, false);
  });

  it("passes the app's queries to the terminal as they are: what it answers is the webview's", async () => {
    const app = await App.connect(shell.variable);
    await app.next(Wire.welcome);
    app.socket.write(frame(Wire.output, Buffer.from('\x1b[?2026$p\x1b[?2027$p\x1b[c')));
    app.socket.write(frame(Wire.flush));
    await app.next(Wire.flushed);
    assert.equal(pane.text, '\x1b[?2026$p\x1b[?2027$p\x1b[c');
    app.socket.destroy();
  });

  it('removes its socket and its directory when stopped', async () => {
    const socket = shell.address.where.substring('unix:'.length);
    await shell.stop();
    assert.equal(fs.existsSync(path.dirname(socket)), false);
    assert.deepEqual(fs.readdirSync(root), []);
  });
});
