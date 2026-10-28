// The webview's emulation (webview/answers.ts) on a headless xterm.js:
// twk's probe written to it as an app writes it, the answers as the
// terminal's input (xterm.js's own through onData, the emulation's through
// its sink), and an app's requests.
import * as assert from 'node:assert/strict';

import { Terminal } from '@xterm/headless';

import { Answers, Capabilities, answersOf, presetNamed } from '../../../core/capabilities';
import { TerminalRequest } from '../../../core/emulation';
import { Emulation } from '../../../webview/answers';

/** twk's probe as Terminal._probe writes it (alternate screen, kitty keyboard asked). */
const probe =
  '\x1b[?2026$p\x1b[?2027$p\x1b[?2048$p\x1b[?69$p\x1b[?2031$p\x1b[8$p' +
  '\x1b]10;?\x1b\\\x1b]11;?\x1b\\\x1b]4;0;?;1;?\x1b\\\x1b[?u\x1b[16t' +
  '\x1b_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\\x1b[>0q' +
  '\x1b[?2026h\x1b[?1049h\x1b[H─\x1b[6n\x1b[?1049l\x1b[?2026l\x1b[c';

class Rig {
  readonly term = new Terminal({ cols: 40, rows: 5, allowProposedApi: true });
  /** What the terminal answered, xterm.js and the emulation in the order they did. */
  answered = '';
  readonly requests: TerminalRequest[] = [];
  readonly pointers: (string | null)[] = [];
  readonly emulation: Emulation;

  constructor() {
    this.term.onData((d) => (this.answered += d));
    this.emulation = new Emulation(this.term, {
      reply: (text) => (this.answered += text),
      request: (r) => this.requests.push(r),
      pointer: (shape) => this.pointers.push(shape),
      cellSize: () => ({ width: 9, height: 18 }),
    });
  }

  write(text: string): Promise<void> {
    return new Promise((r) => this.term.write(text, r));
  }

  /** What [capabilities] have answered to twk's probe. */
  async probed(capabilities: Capabilities): Promise<string> {
    this.emulation.configure(answersOf(capabilities));
    this.answered = '';
    await this.write(probe);
    return this.answered;
  }

  dispose(): void {
    this.emulation.dispose();
    this.term.dispose();
  }
}

describe("the webview's answers, on xterm.js", () => {
  let rig: Rig;
  const everything = presetNamed('everything').capabilities;
  const xtermJs = presetNamed('xterm.js').capabilities;
  beforeEach(() => (rig = new Rig()));
  afterEach(() => rig.dispose());

  it("xterm.js's answers, and XTVERSION and the cell size besides, in the order asked: DA1 last", async () => {
    const a = await rig.probed(xtermJs);
    assert.match(a, /^\x1b\[\?2026;2\$y\x1b\[\?2027;0\$y/, "xterm.js's DECRQM");
    assert.ok(!a.includes('\x1b[?0u') && !a.includes('\x1b[?1u'), 'no kitty keyboard');
    assert.ok(a.includes('\x1b[6;18;9t'), 'the cell size');
    assert.ok(a.includes('\x1bP>|twk-vscode(0.0.1)\x1b\\'), 'XTVERSION');
    assert.ok(!a.includes('\x1b_G'), "kitty's graphics query unanswered: no");
    assert.match(a, /\x1b\[\?1;2c$/, 'DA1 last');
    assert.ok(a.indexOf('\x1b[6;18;9t') < a.indexOf('\x1bP>|'), 'as asked');
  });

  it('kitty keyboard: the query answered, the flags pushed and popped on the screen they were', async () => {
    const a = await rig.probed(everything);
    assert.ok(a.includes('\x1b[?0u'), a);
    await rig.write('\x1b[?1049h\x1b[>1u');
    const esc = { key: 'Escape', code: 'Escape', ctrl: false, alt: false, shift: false, meta: false };
    assert.equal(rig.emulation.key(esc), '\x1b[27u');
    rig.answered = '';
    await rig.write('\x1b[?u');
    assert.equal(rig.answered, '\x1b[?1u');
    await rig.write('\x1b[?1049l');
    assert.equal(rig.emulation.key(esc), undefined, "the normal screen's own: none pushed");
    await rig.write('\x1b[?1049h\x1b[<u');
    assert.equal(rig.emulation.key(esc), undefined, 'popped');
    await rig.write('\x1b[>1u');
    rig.emulation.configure(answersOf(everything));
    assert.equal(rig.emulation.key(esc), undefined, 'a new app starts with none pushed');
  });

  it('kitty keyboard off: neither answered nor kept, the keys xterm.js\'s', async () => {
    await rig.probed(xtermJs);
    await rig.write('\x1b[?1049h\x1b[>1u');
    assert.equal(rig.emulation.key({ key: 'Escape', code: 'Escape', ctrl: false, alt: false, shift: false, meta: false }), undefined);
  });

  it('no synchronized output: DECRQM 2026 not recognised, the rest as xterm.js answers', async () => {
    const a = await rig.probed(presetNamed('no synchronized output').capabilities);
    assert.match(a, /^\x1b\[\?2026;0\$y\x1b\[\?2027;0\$y/);
    assert.ok(a.endsWith('\x1b[?1;2c'));
  });

  it('no answers: nothing at all but the cursor report, the probe left to time out', async () => {
    const a = await rig.probed(presetNamed('no answers').capabilities);
    // what is no query of the probe's capabilities: CPR, xterm.js's
    assert.equal(a.replace(/\x1b\[\d+;\d+R/, ''), '\x1b[?2026;0$y\x1b[?2027;0$y\x1b[?2048;0$y\x1b[?69;0$y\x1b[?2031;0$y' + '\x1b[8;0$y');
  });

  it("an app's notification, progress, clipboard and pointer shape passed on where on, dropped where off", async () => {
    const write = async (answers: Answers) => {
      rig.requests.length = 0;
      rig.pointers.length = 0;
      rig.emulation.configure(answers);
      await rig.write(
        `\x1b]777;notify;Build;done\x1b\\\x1b]9;4;1;40\x1b\\\x1b]52;c;${Buffer.from('copied').toString('base64')}\x1b\\\x1b]22;pointer\x1b\\`,
      );
    };
    await write(answersOf(xtermJs));
    assert.deepEqual(rig.requests, [
      { type: 'notify', title: 'Build', body: 'done' },
      { type: 'progress', state: 1, percent: 40 },
      { type: 'clipboard', text: 'copied' },
    ]);
    assert.deepEqual(rig.pointers, [null, 'pointer'], 'the terminal\'s own as an app is taken, then the app\'s');
    await write(answersOf(presetNamed('bare').capabilities));
    assert.deepEqual(rig.requests, []);
    assert.deepEqual(rig.pointers, [null]);
  });

  it("links: left to xterm.js's own handling where on, shown as text alone where off; opened only to the web or mail", async () => {
    // a handler registered before the emulation's is reached only where the emulation leaves the sequence
    const seen: string[] = [];
    const term = new Terminal({ cols: 40, rows: 5, allowProposedApi: true });
    term.parser.registerOscHandler(8, (data) => {
      seen.push(data);
      return false;
    });
    const requests: TerminalRequest[] = [];
    const emulation = new Emulation(term, { reply: () => {}, request: (r) => requests.push(r), pointer: () => {}, cellSize: () => undefined });
    const link = '\x1b]8;;https://dart.dev\x1b\\dart\x1b]8;;\x1b\\';
    emulation.configure(answersOf(xtermJs));
    await new Promise<void>((r) => term.write(link, r));
    assert.deepEqual(seen, [';https://dart.dev', ';']);
    emulation.activateLink('https://dart.dev');
    emulation.activateLink('command:workbench.action.quit');
    assert.deepEqual(requests, [{ type: 'openLink', uri: 'https://dart.dev' }]);
    emulation.configure(answersOf(presetNamed('bare').capabilities));
    seen.length = 0;
    await new Promise<void>((r) => term.write(link, r));
    assert.deepEqual(seen, []);
    emulation.activateLink('https://dart.dev');
    assert.equal(requests.length, 1);
    emulation.dispose();
    term.dispose();
  });
});
