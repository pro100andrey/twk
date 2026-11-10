// The messages of the screen file editor's webview, checked at both ends.
import * as assert from 'node:assert/strict';

import { parseScreenFile } from '../../../core/screen_file';
import { isFromScreen, isScreenFile, isToScreen } from '../../../webview/screen_protocol';

const file = parseScreenFile('screen 2×1, cursor at 0,0\ntext\n│ab│\nstyles\n│a │\nlegend\na bold\n');

describe('the messages of the screen file editor', () => {
  it('to the webview: a bad file, a golden alone, a golden against an actual', () => {
    assert.ok(isToScreen({ type: 'show', name: 'f.txt', state: { kind: 'bad', message: 'm' } }));
    assert.ok(isToScreen({ type: 'show', name: 'f.txt', state: { kind: 'ok', golden: file, actual: null, diff: null, stale: false } }));
    const diff = { size: null, cursor: [null, [1, 0]], cells: [{ x: 0, y: 0, text: ['a', 'b'], style: ['bold', null] }] };
    assert.ok(isToScreen({ type: 'show', name: 'f.txt', state: { kind: 'ok', golden: file, actual: file, diff, stale: false } }));
  });

  it('to the webview: nothing else', () => {
    const ok = { kind: 'ok', golden: file, actual: null, diff: null, stale: false };
    for (const m of [
      null,
      { type: 'show', name: 1, state: ok },
      { type: 'show', name: 'f', state: { kind: 'bad' } },
      { type: 'show', name: 'f', state: { ...ok, stale: 'no' } },
      { type: 'show', name: 'f', state: { ...ok, golden: { ...file, height: 2 } } },
      { type: 'show', name: 'f', state: { ...ok, diff: { size: null, cursor: null, cells: [{ x: -1 }] } } },
      { type: 'other' },
    ]) {
      assert.equal(isToScreen(m), false, JSON.stringify(m));
    }
    assert.equal(isScreenFile({ ...file, cursor: [1] }), false);
  });

  it('to the extension: ready and accept', () => {
    assert.ok(isFromScreen({ type: 'ready' }));
    assert.ok(isFromScreen({ type: 'accept' }));
    for (const m of [{ type: 'accept all' }, null, 'ready']) {
      assert.equal(isFromScreen(m), false);
    }
  });
});
