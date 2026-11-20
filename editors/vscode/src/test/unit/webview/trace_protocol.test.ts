// What the trace viewer's page and the extension accept of each other
// (webview/trace_protocol.ts): the messages as they are, and not what only
// looks like one.
import * as assert from 'node:assert/strict';

import { isFromTrace, isToTrace } from '../../../webview/trace_protocol';

const row = { label: '1 press', ok: true, before: -1, after: 2, frames: [{ frame: 2, upTo: 2 }], outline: null };
const open = { type: 'open', title: 't', width: 20, height: 4, steps: [row], events: [[0, 'o', 'x']], select: 0 };

describe('the trace viewer protocol', () => {
  it('takes the messages of the page', () => {
    assert.ok(isFromTrace({ type: 'ready' }));
    assert.ok(isFromTrace({ type: 'select', index: 0 }));
    assert.ok(!isFromTrace({ type: 'select', index: -1 }));
    assert.ok(!isFromTrace({ type: 'select', index: 1.5 }));
    assert.ok(!isFromTrace({ type: 'other' }));
    assert.ok(!isFromTrace(null));
  });

  it('takes the messages of the extension', () => {
    assert.ok(isToTrace(open));
    assert.ok(isToTrace({ type: 'detail', index: 0, detail: { facts: [], tree: null, log: [], sequences: '' } }));
    assert.ok(!isToTrace({ ...open, steps: [{ ...row, ok: 'yes' }] }));
    assert.ok(!isToTrace({ ...open, events: [[0, 'i', 'x']] }));
    assert.ok(!isToTrace({ ...open, select: -2 }));
    assert.ok(!isToTrace({ type: 'detail', index: 0, detail: { facts: [1], tree: null, log: [], sequences: '' } }));
  });
});
