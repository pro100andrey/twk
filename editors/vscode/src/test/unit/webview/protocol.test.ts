// The checks of the messages between the extension and the webview.
import * as assert from 'node:assert/strict';

import { answersOf, presetNamed } from '../../../core/capabilities';
import { isFromLog, isToLog } from '../../../webview/log_protocol';
import { isFromWebview, isToWebview } from '../../../webview/protocol';

describe('the webview protocol', () => {
  it("takes the webview's messages", () => {
    for (const m of [
      { type: 'ready', columns: 80, lines: 24 },
      { type: 'resize', columns: 1, lines: 1 },
      { type: 'input', data: 'q', binary: false },
      { type: 'written', id: 3 },
      { type: 'snapshot', id: 4, buffer: 'alternate', rows: ['a', ''] },
      { type: 'snapshot', id: 4, buffer: 'alternate', rows: ['a', ''], backgrounds: [' #', ''] },
      { type: 'request', request: { type: 'notify', title: 't', body: '' } },
      { type: 'request', request: { type: 'progress', state: 1, percent: 40 } },
      { type: 'request', request: { type: 'progress', state: 3, percent: null } },
      { type: 'request', request: { type: 'clipboard', text: 'x' } },
      { type: 'request', request: { type: 'openLink', uri: 'https://dart.dev' } },
      { type: 'picked', cell: { x: 0, y: 3, cursorY: 7 } },
      { type: 'picked', cell: { x: 0, y: 3, cursorY: -2 } },
      { type: 'picked', cell: null },
      { type: 'control', control: 'toggle' },
      { type: 'control', control: 'restart' },
    ]) {
      assert.ok(isFromWebview(m), JSON.stringify(m));
    }
  });

  it('refuses anything else from it', () => {
    for (const m of [
      undefined,
      null,
      'ready',
      {},
      { type: 'ready', columns: '80', lines: 24 },
      { type: 'resize', columns: -1, lines: 24 },
      { type: 'input', data: 7, binary: false },
      { type: 'input', data: 'q' },
      { type: 'written', id: 1.5 },
      { type: 'snapshot', id: 1, buffer: 'other', rows: [] },
      { type: 'snapshot', id: 1, buffer: 'normal', rows: [1] },
      { type: 'snapshot', id: 1, buffer: 'normal', rows: [], backgrounds: [1] },
      { type: 'output', id: 1, data: new Uint8Array() },
      { type: 'request', request: { type: 'notify', title: 't' } },
      { type: 'request', request: { type: 'progress', state: 5, percent: null } },
      { type: 'request', request: { type: 'progress', state: 1, percent: 101 } },
      { type: 'request', request: { type: 'clipboard', text: 1 } },
      { type: 'request', request: { type: 'run', command: 'x' } },
      { type: 'request' },
      { type: 'picked' },
      { type: 'picked', cell: { x: -1, y: 0 } },
      { type: 'picked', cell: { x: 1 } },
      { type: 'picked', cell: { x: 0, y: 3 } },
      { type: 'picked', cell: { x: 0, y: 3, cursorY: 1.5 } },
      { type: 'control', control: 'eject' },
      { type: 'control' },
    ]) {
      assert.equal(isFromWebview(m), false, JSON.stringify(m));
    }
  });

  it("takes the extension's messages, and refuses anything else", () => {
    assert.ok(isToWebview({ type: 'output', id: 1, data: new Uint8Array([65]) }));
    assert.ok(isToWebview({ type: 'size', columns: null, lines: null }));
    assert.ok(isToWebview({ type: 'size', columns: 80, lines: 24 }));
    assert.ok(isToWebview({ type: 'snapshot', id: 2 }));
    assert.ok(isToWebview({ type: 'focus' }));
    assert.ok(isToWebview({ type: 'pick', on: true }));
    assert.equal(isToWebview({ type: 'pick', on: 'yes' }), false);
    assert.ok(isToWebview({ type: 'player', state: null }));
    assert.ok(isToWebview({ type: 'player', state: { playing: true, frame: 0, frames: 3, time: 0, duration: 1.5 } }));
    assert.equal(isToWebview({ type: 'player', state: { playing: true, frame: 0, frames: 3, time: -1, duration: 1.5 } }), false);
    assert.equal(isToWebview({ type: 'player', state: { playing: 'yes', frame: 0, frames: 3, time: 0, duration: 1 } }), false);
    assert.equal(isToWebview({ type: 'player' }), false);
    assert.equal(isToWebview({ type: 'output', id: 1, data: [65] }), false);
    assert.equal(isToWebview({ type: 'size', columns: 'x', lines: null }), false);
    assert.equal(isToWebview({ type: 'ready', columns: 80, lines: 24 }), false);
    for (const p of ['xterm.js', 'everything', 'no answers', 'bare']) {
      assert.ok(isToWebview({ type: 'answers', answers: answersOf(presetNamed(p).capabilities) }), p);
    }
    const answers = answersOf(presetNamed('xterm.js').capabilities);
    for (const wrong of [
      { ...answers, deny: ['everything'] },
      { ...answers, graphics: 'kitty' },
      { ...answers, version: 7 },
      { ...answers, links: 'yes' },
      { deny: [] },
    ]) {
      assert.equal(isToWebview({ type: 'answers', answers: wrong }), false, JSON.stringify(wrong));
    }
  });

  it("the sequence log's messages, each way, and nothing else", () => {
    const entry = { id: 0, time: 1, direction: 'out', kind: 'frame', name: 'frame 1', raw: '9 bytes', bytes: 9, children: [{ id: 1, time: 1, direction: 'out', kind: 'csi', name: 'CUP', raw: 'ESC [H', bytes: 3 }] };
    assert.ok(isToLog({ type: 'reset', title: 't', entries: [entry] }));
    assert.ok(isToLog({ type: 'entries', entries: [] }));
    assert.ok(isToLog({ type: 'ended' }));
    for (const wrong of [
      { ...entry, direction: 'up' },
      { ...entry, kind: 'other' },
      { ...entry, time: -1 },
      { ...entry, children: [{ id: 'x' }] },
      { ...entry, name: 1 },
    ]) {
      assert.equal(isToLog({ type: 'entries', entries: [wrong] }), false, JSON.stringify(wrong));
    }
    assert.equal(isToLog({ type: 'reset', entries: [] }), false);
    assert.equal(isToLog({ type: 'ready' }), false);
    assert.ok(isFromLog({ type: 'ready' }));
    assert.ok(isFromLog({ type: 'clear' }));
    assert.ok(isFromLog({ type: 'shown', rows: 3, held: 0, last: ['a'] }));
    assert.equal(isFromLog({ type: 'shown', rows: 3, held: 0, last: [1] }), false);
    assert.equal(isFromLog({ type: 'entries', entries: [] }), false);
    assert.equal(isFromLog(null), false);
  });
});
