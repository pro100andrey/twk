// The view of a webview (app/webview_view.ts) over a fake panel: what it
// posts, what it makes of the webview's messages, a webview that loads
// again, and a panel closed with requests in flight.
import * as assert from 'node:assert/strict';

import { WebviewTerminalView, answerLimitMs } from '../../../app/webview_view';
import { FakeClock, FakePanel } from '../fakes';

describe('WebviewTerminalView', () => {
  let panel: FakePanel;
  let clock: FakeClock;
  let view: WebviewTerminalView;

  beforeEach(() => {
    panel = new FakePanel();
    clock = new FakeClock();
    view = new WebviewTerminalView(panel, clock);
  });

  it("is ready once the webview says so, at its size; keys, sizes and writes go through the protocol's messages", async () => {
    panel.send({ type: 'ready', columns: 90, lines: 20 });
    await view.ready;
    assert.deepEqual([view.columns, view.lines], [90, 20]);
    const keys: string[] = [];
    view.onInput((b) => keys.push(Buffer.from(b).toString('latin1')));
    panel.send({ type: 'input', data: 'q', binary: false });
    panel.send({ type: 'input', data: '\x1b[M\xff', binary: true });
    panel.send({ type: 'input', data: 42, binary: false }); // not a message
    assert.deepEqual(keys, ['q', '\x1b[M\xff']);
    let resized = 0;
    view.onResize(() => resized++);
    panel.send({ type: 'resize', columns: 70, lines: 10 });
    assert.deepEqual([view.columns, view.lines, resized], [70, 10, 1]);

    let written = false;
    const writing = view.write(Buffer.from('hi')).then(() => (written = true));
    await new Promise((r) => setImmediate(r));
    const [output] = panel.posted;
    assert.equal(output.type, 'output');
    assert.equal(written, false, 'until xterm.js parsed it');
    panel.send({ type: 'written', id: output.type === 'output' ? output.id : -1 });
    await writing;
  });

  it('a webview that loads again (a second "ready"): a reload, at its new size, what the old one was asked settled', async () => {
    panel.send({ type: 'ready', columns: 90, lines: 20 });
    await view.ready;
    let reloads = 0;
    view.onReload(() => reloads++);
    let written = false;
    const writing = view.write(Buffer.from('lost')).then(() => (written = true));
    const snapshot = view.snapshot();
    panel.send({ type: 'ready', columns: 80, lines: 24 });
    assert.equal(reloads, 1);
    assert.deepEqual([view.columns, view.lines], [80, 24]);
    await writing;
    assert.ok(written, 'a write the old webview never parses settles');
    assert.deepEqual(await snapshot, { buffer: 'normal', rows: [] });
  });

  it('closed: what was asked settles, nothing more is posted, and it says it was closed', async () => {
    const closes: number[] = [];
    view.onClose(() => closes.push(1));
    const writing = view.write(Buffer.from('x'));
    panel.dispose();
    await writing;
    await assert.rejects(view.ready, /closed before it was ready/);
    assert.ok(view.isClosed);
    assert.deepEqual(closes, [1]);
    const count = panel.posted.length;
    view.fixSize(10, 10);
    view.setTitle('gone');
    assert.equal(panel.posted.length, count);
    assert.equal(panel.title, '');
    assert.deepEqual(await view.snapshot(), { buffer: 'normal', rows: [] });
  });

  it('a webview alive but answering no more: a write and a snapshot settle once the limit passed, and no timer is left by one answered', async () => {
    panel.send({ type: 'ready', columns: 80, lines: 24 });
    await view.ready;
    let written = false;
    const writing = view.write(Buffer.from('x')).then(() => (written = true));
    const snapshot = view.snapshot();
    await new Promise((r) => setImmediate(r));
    clock.elapse(answerLimitMs - 1);
    await new Promise((r) => setImmediate(r));
    assert.equal(written, false);
    clock.elapse(1);
    await writing;
    assert.deepEqual(await snapshot, { buffer: 'normal', rows: [] });
    const answered = view.write(Buffer.from('y'));
    await new Promise((r) => setImmediate(r));
    const output = panel.posted[panel.posted.length - 1];
    panel.send({ type: 'written', id: output.type === 'output' ? output.id : -1 });
    await answered;
    assert.equal(clock.pending, 0);
  });

  it("a player's bar: its state posted, its buttons told; active as its panel is", async () => {
    panel.send({ type: 'ready', columns: 80, lines: 24 });
    await view.ready;
    const controls: string[] = [];
    view.onControl((c) => controls.push(c));
    view.player({ playing: false, frame: 1, frames: 2, time: 0.5, duration: 1 });
    view.player(null);
    await new Promise((r) => setImmediate(r));
    assert.deepEqual(panel.posted.slice(-2), [
      { type: 'player', state: { playing: false, frame: 1, frames: 2, time: 0.5, duration: 1 } },
      { type: 'player', state: null },
    ]);
    panel.send({ type: 'control', control: 'step' });
    panel.send({ type: 'control', control: 'fly' });
    assert.deepEqual(controls, ['step']);
    assert.equal(view.isActive, false);
    panel.active = true;
    assert.equal(view.isActive, true);
    panel.dispose();
    assert.equal(view.isActive, false);
  });
});
