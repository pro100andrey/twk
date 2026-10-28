// Each switch of the twk terminal against twk itself: a twk app
// (packages/twk_core/test/terminal/info_app.dart, in a Dart VM of its own)
// opens the terminal its TWK_SHELL names, served by core's shell over a
// headless xterm.js with the webview's emulation on it (webview/answers.ts),
// welcomed as app/terminal.ts welcomes it, and prints what twk found out:
// it is held to what the switch says. Then keys, encoded as kitty's
// keyboard protocol where the app pushed it, read back as the keys they are.
import * as assert from 'node:assert/strict';
import { ChildProcess, execFile, spawn } from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

import { Terminal } from '@xterm/headless';

import { Capabilities, answersOf, choiceOf, declarationOf, environmentOf } from '../../../core/capabilities';
import { KeyPress } from '../../../core/kitty_keyboard';
import { TerminalShell } from '../../../core/shell';
import { Emulation } from '../../../webview/answers';

/** From out/test/unit/webview, where this runs compiled, to the repository's root. */
const root = path.resolve(__dirname, '../../../../../..');
const appSource = path.join(root, 'packages', 'twk_core', 'test', 'terminal', 'info_app.dart');

/** What info_app.dart prints of `TerminalInfo`. */
interface Found {
  colorMode: string;
  answeredQueries: boolean;
  synchronizedOutput: boolean;
  kittyKeyboard: boolean;
  kittyKeyboardFlags: number;
  graphics: string;
  cellPixelWidth: number;
  cellPixelHeight: number;
  notifications: string;
  progressReports: boolean;
  pointerShapes: boolean;
  repeatChar: boolean;
  ambiguousWidth: number;
  bidi: string;
}

/** A twk terminal of a headless xterm.js, as the extension makes one of a webview. */
class HeadlessTwkTerminal {
  readonly term = new Terminal({ cols: 60, rows: 12, allowProposedApi: true });
  readonly emulation: Emulation;
  shell: TerminalShell | undefined;

  constructor(private readonly capabilities: Capabilities) {
    this.emulation = new Emulation(this.term, {
      reply: (text) => this.shell?.input(Buffer.from(text, 'utf8')),
      request: () => {},
      pointer: () => {},
      cellSize: () => ({ width: 9, height: 18 }),
    });
    // xterm.js's own answers (DECRQM, DA1, CPR) come as its input
    this.term.onData((d) => this.shell?.input(Buffer.from(d, 'utf8')));
  }

  async start(temporaryRoot: string): Promise<void> {
    const term = this.term;
    this.shell = await TerminalShell.start(
      { columns: term.cols, lines: term.rows, write: (bytes) => new Promise((r) => term.write(bytes, r)) },
      {
        welcome: () => {
          this.emulation.configure(answersOf(this.capabilities));
          return { environment: environmentOf(this.capabilities), declares: declarationOf(this.capabilities) };
        },
        onEvent: () => {},
        temporaryRoot,
        tcp: false,
      },
    );
  }

  /** Types what the webview would send for [press]: the emulation's encoding, else xterm.js's (here, the key as typed). */
  press(press: KeyPress, legacy: string): void {
    this.shell?.input(Buffer.from(this.emulation.key(press) ?? legacy, 'utf8'));
  }

  private disposed = false;

  async dispose(): Promise<void> {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    await this.shell?.stop();
    this.emulation.dispose();
    this.term.dispose();
  }
}

/** The environment of the app: this process's, none of twk's own variables in it but its TWK_SHELL. */
function appEnvironment(variable: string): NodeJS.ProcessEnv {
  const env = Object.fromEntries(Object.entries(process.env).filter(([k]) => !k.startsWith('TWK_') && k !== 'NO_COLOR'));
  return { ...env, TWK_SHELL: variable };
}

describe('what twk finds out about the twk terminal, switch by switch', function () {
  this.timeout(180000);
  let dir: string;
  let kernel: string;
  /** The apps started and their terminals: what a test that failed left is ended after it. */
  const running: { readonly app: ChildProcess; readonly terminal: HeadlessTwkTerminal }[] = [];

  before(async () => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), 'twk-probe-'));
    kernel = path.join(dir, 'info_app.dill');
    await new Promise<void>((resolve, reject) =>
      execFile('dart', ['compile', 'kernel', appSource, '-o', kernel], { cwd: root, timeout: 150000 }, (e, _out, err) =>
        e ? reject(new Error(`${e.message}\n${err}`)) : resolve(),
      ),
    );
  });

  afterEach(async () => {
    for (const { app, terminal } of running.splice(0)) {
      if (app.exitCode === null && app.signalCode === null) {
        app.kill();
      }
      await terminal.dispose();
    }
  });

  after(() => fs.rmSync(dir, { recursive: true, force: true }));

  /** Starts info_app.dart on a terminal of [capabilities]; [lines], what it prints, line by line. */
  async function run(capabilities: Capabilities, args: string[] = []) {
    const t = new HeadlessTwkTerminal(capabilities);
    await t.start(dir);
    const p = spawn('dart', [kernel, ...args], { cwd: root, env: appEnvironment(t.shell!.variable), stdio: ['ignore', 'pipe', 'pipe'] });
    running.push({ app: p, terminal: t });
    let out = '';
    let err = '';
    p.stdout!.on('data', (b: Buffer) => (out += b.toString('utf8')));
    p.stderr!.on('data', (b: Buffer) => (err += b.toString('utf8')));
    const ended = new Promise<number | null>((r) => p.on('exit', (code) => r(code)));
    const lines = async (n: number): Promise<string[]> => {
      const end = Date.now() + 20000;
      while (out.split('\n').length <= n) {
        if (Date.now() > end) {
          throw new Error(`no ${n} lines from the app in 20 s; out:\n${out}\nerr:\n${err}`);
        }
        await new Promise((r) => setTimeout(r, 20));
      }
      return out.split('\n').slice(0, n);
    };
    const found = async (): Promise<Found> => {
      const [line] = await lines(1);
      return JSON.parse(line) as Found;
    };
    const done = async () => assert.equal(await ended, 0, `the app's exit; err:\n${err}`);
    return { t, found, lines, done };
  }

  async function foundWith(preset: string, changes: object = {}): Promise<Found> {
    const app = await run(choiceOf(preset, changes).capabilities);
    const f = await app.found();
    await app.done();
    return f;
  }

  it('xterm.js: 24-bit color, synchronized output, a cell of 9x18 pixels, notifications by OSC 777, progress, pointer shapes and REP as declared, no kitty keyboard, no images', async () => {
    const f = await foundWith('xterm.js');
    assert.equal(f.colorMode, 'trueColor');
    assert.equal(f.answeredQueries, true);
    assert.equal(f.synchronizedOutput, true);
    assert.deepEqual([f.cellPixelWidth, f.cellPixelHeight], [9, 18]);
    assert.equal(f.notifications, 'osc777');
    assert.equal(f.progressReports, true);
    assert.equal(f.pointerShapes, true);
    assert.equal(f.repeatChar, true);
    assert.equal(f.kittyKeyboard, false);
    assert.equal(f.graphics, 'none');
    assert.equal(f.ambiguousWidth, 1);
    assert.equal(f.bidi, 'app');
  });

  it('the colours: 256, 16, none', async () => {
    assert.equal((await foundWith('256 colors')).colorMode, 'ansi256');
    assert.equal((await foundWith('16 colors')).colorMode, 'ansi16');
    assert.equal((await foundWith('no color')).colorMode, 'none');
  });

  it('everything: kitty keyboard with disambiguation, sixel images', async () => {
    const f = await foundWith('everything');
    assert.equal(f.kittyKeyboard, true);
    assert.equal(f.kittyKeyboardFlags, 1);
    assert.equal(f.graphics, 'sixel');
  });

  it("iTerm2's images, as declared", async () => {
    assert.equal((await foundWith('xterm.js', { graphics: 'iterm2' })).graphics, 'iterm2');
  });

  it('no synchronized output; no cell size', async () => {
    assert.equal((await foundWith('no synchronized output')).synchronizedOutput, false);
    const f = await foundWith('xterm.js', { cellSize: false });
    assert.deepEqual([f.cellPixelWidth, f.cellPixelHeight], [0, 0]);
  });

  it('bare: none of notifications, progress, pointer shapes or REP, though TERM would say xterm', async () => {
    const f = await foundWith('bare');
    assert.equal(f.notifications, 'none');
    assert.equal(f.progressReports, false);
    assert.equal(f.pointerShapes, false);
    assert.equal(f.repeatChar, false);
    assert.equal(f.synchronizedOutput, false);
    assert.equal(f.answeredQueries, true);
  });

  it('no answers: the probe timed out, nothing that has to be asked', async () => {
    const f = await foundWith('no answers');
    assert.equal(f.answeredQueries, false);
    assert.equal(f.synchronizedOutput, false);
    assert.equal(f.kittyKeyboard, false);
    assert.deepEqual([f.cellPixelWidth, f.cellPixelHeight], [0, 0]);
  });

  it("kitty keyboard: Escape, Ctrl and Alt keys encoded as the app pushed, read back as those keys", async () => {
    const app = await run(choiceOf('everything', {}).capabilities, ['keys']);
    assert.equal((await app.found()).kittyKeyboard, true);
    const key = (k: string, code: string, mods: Partial<KeyPress> = {}): KeyPress => ({ key: k, code, ctrl: false, alt: false, shift: false, meta: false, ...mods });
    app.t.press(key('Escape', 'Escape'), '\x1b');
    app.t.press(key('c', 'KeyC', { ctrl: true }), '\x03');
    app.t.press(key('x', 'KeyX', { alt: true }), '\x1bx');
    app.t.press(key('Enter', 'Enter', { shift: true }), '\r');
    app.t.press(key('a', 'KeyA'), 'a');
    app.t.press(key('q', 'KeyQ', { ctrl: true }), '\x11');
    const lines = await app.lines(7);
    await app.done();
    assert.deepEqual(lines.slice(1), ['key escape "" 0', 'key char "c" 4', 'key char "x" 2', 'key enter "" 1', 'key char "a" 0', 'key char "q" 4']);
  });
});
